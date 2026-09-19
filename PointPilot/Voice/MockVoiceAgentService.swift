import Foundation

/// A fully local stand-in for the voice agent.
///
/// It is the default service whenever ElevenLabs credentials are absent, and it
/// exercises the exact same `VoiceAgentProviding` path as the real SDK: it emits
/// states, transcripts, and a `recommendCard` tool call. That keeps the voice
/// flow demonstrable with no credentials and no network, and it means the app
/// never has a dead end when the microphone or the service is unavailable.
///
/// Every action it takes is clearly labelled as simulated.
@MainActor
final class MockVoiceAgentService: VoiceAgentProviding {
    var onStateChange: ((VoiceState) -> Void)?
    var onMessage: ((VoiceMessage) -> Void)?
    var onRecommendationRequest: ((RecommendationRequest) -> Void)?
    var onActivationRequest: ((String) -> Void)?

    /// Reported as configured so the UI offers the voice button in demo mode;
    /// the transcript states plainly that the response is simulated.
    var isConfigured: Bool { true }

    private var isRunning = false
    private var pendingActivationOfferID: String?
    /// The last state actually published, so unchanged states are not re-emitted.
    private var lastEmittedState: VoiceState?

    func start() async throws {
        // Tapping the microphone again while a session is already live must not
        // re-announce the greeting. Without this guard every tap appended
        // another identical line to the transcript.
        guard !isRunning else { return }

        isRunning = true
        emit(.listening)
        onMessage?(
            VoiceMessage(
                speaker: .agent,
                text: "Demo voice is on. Tell me the restaurant and roughly how much you'll spend."
            )
        )
    }

    func stop() async {
        isRunning = false
        pendingActivationOfferID = nil
        emit(.idle)
    }

    /// Publishes a state only when it actually differs from the last one, so
    /// repeated taps cannot produce a stream of identical state changes.
    private func emit(_ state: VoiceState) {
        guard state != lastEmittedState else { return }
        lastEmittedState = state
        onStateChange?(state)
    }

    /// Parses free text the way a conversational agent would, then calls the
    /// client tool. Supports the demo phrasing "I'm at Nobu and spending
    /// around $200".
    func send(text: String) async {
        guard isRunning else { return }

        onMessage?(VoiceMessage(speaker: .user, text: text))
        emit(.thinking)

        // A bare confirmation completes a pending simulated activation.
        if let offerID = pendingActivationOfferID, Self.isAffirmative(text) {
            pendingActivationOfferID = nil
            onMessage?(
                VoiceMessage(
                    speaker: .agent,
                    text: "Got it — simulating activation of that offer now. "
                        + "No real activation has occurred."
                )
            )
            onActivationRequest?(offerID)
            emit(.speaking)
            return
        }

        let parsed = Self.parse(text)

        guard let merchant = parsed.merchant, let amount = parsed.amount else {
            var missing: [String] = []
            if parsed.merchant == nil { missing.append("which restaurant you're at") }
            if parsed.amount == nil { missing.append("about how much you'll spend") }

            emit(.speaking)
            onMessage?(
                VoiceMessage(
                    speaker: .agent,
                    text: "I can help with that — just tell me \(missing.joined(separator: " and "))."
                )
            )
            return
        }

        // The agent hands the app structured inputs and lets it compute.
        onRecommendationRequest?(
            RecommendationRequest(merchant: merchant, amount: amount, category: .dining)
        )
    }

    /// Records an offer so the next affirmative reply simulates activating it.
    func expectActivationConfirmation(offerID: String) {
        pendingActivationOfferID = offerID
        emit(.speaking)
        onMessage?(
            VoiceMessage(
                speaker: .agent,
                text: "Want me to simulate activating that offer? Say yes and I'll confirm."
            )
        )
    }

    // MARK: - Lightweight parsing

    /// Extracts an amount and a merchant from a spoken-style sentence.
    ///
    /// This is deliberately simple and local: the real agent does this work in
    /// production, and the typed path is the reliable fallback either way.
    static func parse(_ text: String) -> (merchant: String?, amount: Decimal?) {
        (merchant: parseMerchant(text), amount: parseAmount(text))
    }

    /// Pulls the first currency-looking number out of the text.
    static func parseAmount(_ text: String) -> Decimal? {
        let pattern = #"\$?\s?(\d+(?:[.,]\d{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text)
        else { return nil }

        // Normalize a comma decimal separator before parsing.
        let raw = String(text[captured])
            .lowercased()
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: raw), value > 0 else { return nil }
        return value
    }

    /// Removes filler words so "I'm at Nobu and spending around $200" yields "Nobu".
    static func parseMerchant(_ text: String) -> String? {
        var working = text.lowercased()

        let noise = [
            "i'm at", "i am at", "im at", "i'm", "i am", "at the", "at", "spending",
            "spend", "around", "about", "roughly", "approximately", "expect to",
            "going to", "will", "and", "for", "on", "my", "card", "which",
            "should i use", "use", "dollars", "dollar", "bucks", "please", "the"
        ]
        for phrase in noise {
            working = working.replacingOccurrences(of: phrase, with: " ")
        }

        // Drop currency figures and stray punctuation, then collapse whitespace.
        working = working.replacingOccurrences(
            of: #"\$?\s?\d+(?:[.,]\d{1,2})?"#,
            with: " ",
            options: .regularExpression
        )
        working = working.replacingOccurrences(
            of: #"[^a-z0-9 ]"#,
            with: " ",
            options: .regularExpression
        )

        let cleaned = working
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }

    private static func isAffirmative(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let affirmatives = ["yes", "yeah", "yep", "sure", "ok", "okay", "do it", "go ahead", "please do"]
        return affirmatives.contains { normalized == $0 || normalized.hasPrefix("\($0) ") }
    }
}
