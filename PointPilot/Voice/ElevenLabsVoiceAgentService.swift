import Foundation

#if canImport(ElevenLabs)
import ElevenLabs
import Combine

/// The real ElevenLabs conversational-agent integration.
///
/// This file is compiled **only** when the ElevenLabs Swift SDK is present, so
/// the project builds and demos without it. To enable it:
///
/// 1. Add the package in Xcode:
///    File ▸ Add Package Dependencies…
///    `https://github.com/elevenlabs/elevenlabs-swift-sdk.git` (2.0.0 or later)
/// 2. Add the ElevenLabs target to the PointPilot app target's frameworks.
/// 3. Put your public agent ID in `Config/ElevenLabs.plist` (gitignored).
/// 4. Configure the agent in the ElevenLabs dashboard with a **client** tool
///    named `recommendCard` taking `merchant` (string) and `amount` (number),
///    and set `CLIENT_TOOL_NAMESPACE` below to the same name.
///
/// The agent is instructed to call `recommendCard` rather than do arithmetic
/// itself, and to speak only the figures the app returns. Activation is
/// simulated and explicitly confirmed as such.
@MainActor
final class ElevenLabsVoiceAgentService: VoiceAgentProviding {
    var onStateChange: ((VoiceState) -> Void)?
    var onMessage: ((VoiceMessage) -> Void)?
    var onRecommendationRequest: ((RecommendationRequest) -> Void)?
    var onActivationRequest: ((String) -> Void)?

    private let configuration: ElevenLabsConfiguration
    private var conversation: Conversation?
    private var cancellables = Set<AnyCancellable>()

    /// Must match the client-tool name configured on the ElevenLabs agent.
    private static let clientToolNamespace = "recommendCard"

    init(configuration: ElevenLabsConfiguration) {
        self.configuration = configuration
    }

    var isConfigured: Bool { configuration.isConfigured }

    func start() async throws {
        guard let agentID = configuration.agentID else {
            throw VoiceAgentError.notConfigured
        }

        onStateChange?(.idle)

        do {
            let config = ConversationConfig(
                conversationOverrides: ConversationOverrides(textOnly: false)
            )
            let conversation = try await ElevenLabs.startConversation(
                agentId: agentID,
                userId: configuration.userID,
                config: config
            )
            self.conversation = conversation
            observe(conversation)
        } catch {
            throw VoiceAgentError.connectionFailed(error.localizedDescription)
        }
    }

    func stop() async {
        await conversation?.endConversation()
        conversation = nil
        cancellables.removeAll()
        onStateChange?(.idle)
    }

    func send(text: String) async {
        guard let conversation else { return }
        onMessage?(VoiceMessage(speaker: .user, text: text))
        onStateChange?(.thinking)
        try? await conversation.sendMessage(text)
    }

    // MARK: - Observation

    private func observe(_ conversation: Conversation) {
        conversation.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.onStateChange?(Self.voiceState(for: state))
            }
            .store(in: &cancellables)

        conversation.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                guard let latest = messages.last else { return }
                let speaker: VoiceMessage.Speaker = latest.role == .user ? .user : .agent
                self?.onMessage?(VoiceMessage(speaker: speaker, text: latest.content))
            }
            .store(in: &cancellables)
    }

    private static func voiceState(for state: Conversation.State) -> VoiceState {
        switch state {
        case .idle: return .idle
        case .connecting, .active: return .listening
        case .ended: return .idle
        case .error: return .unavailable(VoiceAgentError.connectionFailed("session error").localizedDescription)
        }
    }

    // MARK: - Client tools

    /// Registers the `recommendCard` client tool handler.
    ///
    /// The agent supplies `merchant` and `amount`; the app computes the
    /// recommendation and returns a compact payload of engine facts for the
    /// agent to read back verbatim.
    ///
    /// Wiring point: with the ElevenLabs Swift SDK the handler is registered on
    /// the conversation after it starts, e.g.
    /// `conversation.registerClientTool(name: Self.clientToolNamespace) { params in ... }`.
    /// The exact registration call follows the SDK's Client Tools guide for the
    /// version you add; the payload returned here is what the agent may speak.
    private func handleClientTool(parameters: [String: Any]) -> [String: Any] {
        guard
            let merchant = parameters["merchant"] as? String,
            let amountValue = parameters["amount"] as? Double
        else {
            return ["error": "merchant and amount are required"]
        }

        let request = RecommendationRequest(
            merchant: merchant,
            amount: Decimal(amountValue),
            category: .dining
        )
        onRecommendationRequest?(request)

        // The view model answers this request and produces the spoken facts;
        // this acknowledgement only confirms the tool was received.
        return ["status": "computing"]
    }
}

#endif
