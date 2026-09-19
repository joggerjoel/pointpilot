import Foundation

/// The stages a voice conversation can be in, surfaced directly in the UI.
enum VoiceState: Equatable, Sendable {
    case idle
    case listening
    case thinking
    case speaking
    case unavailable(String)

    var isBusy: Bool {
        switch self {
        case .listening, .thinking, .speaking: return true
        case .idle, .unavailable: return false
        }
    }

    var statusText: String {
        switch self {
        case .idle: return "Tap to speak"
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        case .unavailable: return "Voice unavailable"
        }
    }
}

/// A transcript line shown beneath the voice button.
struct VoiceMessage: Identifiable, Hashable, Sendable {
    enum Speaker: String, Sendable {
        case user
        case agent

        var displayName: String {
            switch self {
            case .user: return "You"
            case .agent: return "PointPilot"
            }
        }
    }

    let id: UUID
    let speaker: Speaker
    let text: String
    /// When the line was produced, rendered in the device's local timezone.
    let timestamp: Date

    init(id: UUID = UUID(), speaker: Speaker, text: String, timestamp: Date = Date()) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }

    /// Timestamp for display, in the device's current timezone.
    ///
    /// No timezone is pinned: `Date.formatted` uses the user's locale and
    /// current timezone, so the transcript always reads in local mobile time.
    /// Today's lines show a clock time; older lines also carry the date, which
    /// is the convention iOS uses for message threads.
    var localTimestamp: String {
        if Calendar.current.isDateInToday(timestamp) {
            return timestamp.formatted(date: .omitted, time: .shortened)
        }
        return timestamp.formatted(date: .abbreviated, time: .shortened)
    }
}

/// The outcome the voice agent asks the app to compute.
struct RecommendationRequest: Equatable, Sendable {
    let merchant: String
    let amount: Decimal
    let category: RewardCategory
}

/// Why a voice session could not be started.
enum VoiceAgentError: LocalizedError, Equatable {
    case notConfigured
    case connectionFailed(String)
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Voice is unavailable — add your ElevenLabs agent ID in Config/ElevenLabs.plist to enable it."
        case .connectionFailed(let reason):
            return "Couldn't reach the voice service: \(reason)"
        case .microphonePermissionDenied:
            return "Microphone access is off. You can still type your merchant and amount."
        }
    }
}

/// The integration boundary between the app and any voice agent.
///
/// The rest of the app — views, view model, recommendation flow — depends only
/// on this protocol, so the ElevenLabs implementation can be swapped for the
/// mock service (or anything else) without any other code changing.
///
/// Implementations are responsible for translating agent tool calls into
/// `onRecommendationRequest`. They must not compute recommendations themselves;
/// the app answers every tool call from its own `RecommendationProviding`.
@MainActor
protocol VoiceAgentProviding: AnyObject {
    /// Emits every state change so the UI can render listening/thinking/speaking.
    var onStateChange: ((VoiceState) -> Void)? { get set }
    /// Emits transcript lines from both the user and the agent.
    var onMessage: ((VoiceMessage) -> Void)? { get set }
    /// Fired when the agent calls the `recommendCard` client tool.
    var onRecommendationRequest: ((RecommendationRequest) -> Void)? { get set }
    /// Fired when the user asks to activate an offer, which the app only simulates.
    var onActivationRequest: ((String) -> Void)? { get set }

    var isConfigured: Bool { get }

    func start() async throws
    func stop() async
    /// Sends typed text through the same conversational pipeline as speech.
    func send(text: String) async
}
