import Foundation
import Observation

/// Drives the Ask screen and owns the flow from user input to recommendation.
///
/// The view model is the only place that talks to both the voice service and
/// the recommendation engine. Views stay declarative and the engine stays pure.
@MainActor
@Observable
final class AskViewModel {
    // MARK: - Input

    var merchantQuery: String = ""
    var amountText: String = ""

    // MARK: - Output

    private(set) var voiceState: VoiceState = .idle
    private(set) var messages: [VoiceMessage] = []
    private(set) var recommendation: CardRecommendation?
    private(set) var errorMessage: String?
    /// Non-blocking notice shown when voice is not available. The rest of the
    /// experience stays fully usable.
    private(set) var voiceNotice: String?
    private(set) var isShowingWallet = false
    private(set) var activatedOfferID: String?

    // MARK: - Location & Yelp Output
    private(set) var locationState: LocationState = .notDetermined
    private(set) var nearbyMerchants: [Merchant] = []
    private(set) var isLocating: Bool = false

    var repository: SampleDataRepository
    private var engine: RecommendationProviding
    private let voiceService: VoiceAgentProviding
    private let locationService: LocationServiceProtocol?
    private let merchantDataService: MerchantDataProviding?
    private let voiceIsConfigured: Bool

    init(
        engine: RecommendationProviding,
        repository: SampleDataRepository,
        voiceService: VoiceAgentProviding,
        locationService: LocationServiceProtocol? = nil,
        merchantDataService: MerchantDataProviding? = nil,
        voiceIsConfigured: Bool
    ) {
        self.engine = engine
        self.repository = repository
        self.voiceService = voiceService
        self.locationService = locationService
        self.merchantDataService = merchantDataService
        self.voiceIsConfigured = voiceIsConfigured
        self.nearbyMerchants = repository.merchants.filter { !$0.isFallback }

        if !voiceIsConfigured {
            self.voiceNotice = "Voice is off in demo mode — type a merchant and amount below. "
                + "Everything else works the same."
        }

        wireVoiceCallbacks()
        wireLocationCallbacks()
    }

    var cards: [CreditCard] { repository.cards }

    /// The voice control is offered whenever a service can run.
    var canUseVoice: Bool { voiceService.isConfigured }

    var isVoiceBusy: Bool { voiceState.isBusy }

    // MARK: - Typed flow

    /// The reliable fallback path: text in, recommendation out.
    func submitTypedInput() {
        errorMessage = nil
        let trimmedMerchant = merchantQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let amount = Self.parseAmount(amountText) else {
            errorMessage = RecommendationError.invalidAmount(0).localizedDescription
            return
        }

        compute(merchantQuery: trimmedMerchant, amount: amount)
    }

    /// Runs the engine and presents the result, with the success haptic on iOS.
    private func compute(merchantQuery: String, amount: Decimal) {
        do {
            let result = try engine.recommend(merchantQuery: merchantQuery, amount: amount)
            recommendation = result
            errorMessage = nil
            Haptics.success()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            recommendation = nil
        }
    }

    // MARK: - Voice flow

    func toggleVoice() {
        Task {
            if isVoiceBusy {
                await voiceService.stop()
                voiceState = .idle
            } else {
                await startVoice()
            }
        }
    }

    private func startVoice() async {
        do {
            try await voiceService.start()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            voiceState = .unavailable(message)
            voiceNotice = message
        }
    }

    func stopVoice() {
        Task {
            await voiceService.stop()
            voiceState = .idle
        }
    }

    /// Sends typed text through the conversational agent when one is running,
    /// so the same parsing and tool-calling path is exercised either way.
    func sendVoiceText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await voiceService.send(text: trimmed) }
    }

    private func wireVoiceCallbacks() {
        voiceService.onStateChange = { [weak self] state in
            guard let self else { return }
            // Defensive: a service may still emit a state it has already
            // reported. Ignoring repeats keeps the UI from re-rendering (and
            // re-announcing via VoiceOver) for a state that has not changed.
            guard state != self.voiceState else { return }
            self.voiceState = state
        }

        voiceService.onMessage = { [weak self] message in
            self?.appendMessage(message)
        }

        voiceService.onRecommendationRequest = { [weak self] request in
            guard let self else { return }
            // The agent supplies the inputs; the app computes the answer.
            self.merchantQuery = request.merchant
            self.amountText = Self.string(for: request.amount)
            self.compute(merchantQuery: request.merchant, amount: request.amount)
        }

        voiceService.onActivationRequest = { [weak self] offerID in
            self?.activateOffer(offerID: offerID, source: .voice)
        }
    }

    /// Adds a transcript line, newest first, ignoring immediate repeats.
    ///
    /// History reads top-to-bottom with the latest line at the top, so the most
    /// recent exchange is always the first thing visible without scrolling. An
    /// identical consecutive line from the same speaker is dropped, which is
    /// what stops a repeated microphone tap from stacking duplicates.
    func appendMessage(_ message: VoiceMessage) {
        if let newest = messages.first,
           newest.speaker == message.speaker,
           newest.text == message.text {
            return
        }
        messages.insert(message, at: 0)
    }

    private func wireLocationCallbacks() {
        locationService?.onStateChange = { [weak self] state in
            self?.locationState = state
        }
    }

    // MARK: - Location & Yelp Discovery

    /// Populates the quick-pick chips from local sample merchants without ever
    /// prompting for location. Safe to call on launch.
    ///
    /// The GPS permission dialog is deliberately *not* shown here: asking for
    /// location before the user requests anything is hostile, and it would
    /// interrupt the demo before it starts. Location is requested only from
    /// `detectLocationAndFetchNearby()`, behind the "Nearby" button.
    func loadDefaultNearbyMerchants() {
        let local = repository.merchants.filter { !$0.isFallback }
        if nearbyMerchants.isEmpty {
            nearbyMerchants = local
        }
    }

    /// Requests GPS location and fetches nearby restaurants via Yelp.
    ///
    /// Only ever called from an explicit user action.
    func detectLocationAndFetchNearby() {
        guard let locationService else { return }
        isLocating = true

        Task {
            defer { isLocating = false }

            // Only query for real venues when there is an actual fix. Falling
            // back to invented coordinates would present unrelated restaurants
            // as though they were around the user, which is worse than simply
            // keeping the local sample merchants.
            guard let coordinate = await locationService.requestLocation() else {
                nearbyMerchants = repository.merchants.filter { !$0.isFallback }
                return
            }

            await fetchNearby(for: coordinate)
        }
    }

    private func fetchNearby(for coordinate: LocationCoordinate) async {
        guard let merchantDataService else { return }
        do {
            let fetched = try await merchantDataService.fetchNearbyMerchants(coordinate: coordinate)
            if !fetched.isEmpty {
                self.nearbyMerchants = fetched
                // Enrich repository and engine dynamically so new merchants can be evaluated
                self.repository = self.repository.withAdditionalMerchants(fetched)
                self.engine = RecommendationEngine(cards: self.repository.cards, merchantProvider: self.repository)
            }
        } catch {
            // Keep local sample merchants on failure
            self.nearbyMerchants = repository.merchants.filter { !$0.isFallback }
        }
    }

    /// User taps a quick-pick nearby merchant chip.
    func selectNearbyMerchant(_ merchant: Merchant) {
        merchantQuery = merchant.name
        Haptics.impact()
    }

    // MARK: - Simulated offer activation

    enum ActivationSource {
        case voice
        case manual
    }

    /// Simulates activating an offer. No real activation occurs, and the UI and
    /// the agent both say so.
    func activateOffer(offerID: String, source: ActivationSource = .manual) {
        activatedOfferID = offerID
        Haptics.success()

        guard source == .voice, let mock = voiceService as? MockVoiceAgentService else { return }
        mock.onMessage?(VoiceMessage(
            speaker: .agent,
            text: "Offer activated in the demo. This is simulated — nothing was activated with the issuer."
        ))
    }

    /// Asks the agent to confirm before simulating activation.
    func requestActivationConfirmation(offerID: String) {
        if let mock = voiceService as? MockVoiceAgentService, voiceState.isBusy {
            mock.expectActivationConfirmation(offerID: offerID)
        } else {
            activateOffer(offerID: offerID)
        }
    }

    // MARK: - Navigation

    func showWallet() { isShowingWallet = true }
    func hideWallet() { isShowingWallet = false }

    /// Returns to a clean Ask screen for the next demo run.
    func askAnother() {
        recommendation = nil
        errorMessage = nil
        merchantQuery = ""
        amountText = ""
        activatedOfferID = nil
        messages.removeAll()
    }

    func dismissError() { errorMessage = nil }

    // MARK: - Parsing helpers

    /// Parses typed currency input, tolerating "$", thousands separators and
    /// comma decimals. Returns nil for non-positive or unparseable input.
    static func parseAmount(_ text: String) -> Decimal? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        guard !cleaned.isEmpty, let value = Decimal(string: cleaned), value > 0 else {
            return nil
        }
        return value
    }

    /// Formats a decimal for the amount field without a currency symbol.
    static func string(for amount: Decimal) -> String {
        amount.formatted(.number.precision(.fractionLength(0...2)))
    }
}
