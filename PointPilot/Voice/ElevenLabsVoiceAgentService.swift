import Foundation

#if canImport(ElevenLabs)
import ElevenLabs
import Combine

/// The real ElevenLabs conversational-agent integration.
///
/// This file is compiled **only** when the ElevenLabs Swift SDK is present, so
/// the project builds and demos without it. It is declared as a package
/// dependency in `project.yml`; remove that entry to fall back to
/// `MockVoiceAgentService`.
///
/// Remaining dashboard setup:
///
/// 1. Put your public agent ID in `Config/ElevenLabs.plist` (gitignored).
/// 2. Configure the agent in the ElevenLabs dashboard with a **client** tool
///    named `recommendCard` taking `merchant` (string) and `amount` (number).
///    The name must match `clientToolNamespace` below.
///
/// Only the public agent ID belongs in the app. An API key is a server-side
/// secret and must never be shipped in a binary — for a private agent, mint a
/// conversation token on a backend and use the `conversationToken:` overload.
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

    /// Tool calls already dispatched to the app.
    ///
    /// `pendingToolCalls` stays populated until a result is sent, so without
    /// this the same call would fire a second recommendation on every
    /// subsequent publish.
    private var handledToolCallIDs = Set<String>()

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

        let config = ConversationConfig(
            conversationOverrides: ConversationOverrides(textOnly: false),
            userId: configuration.userID
        )

        do {
            let conversation = try await ElevenLabs.startConversation(
                agentId: agentID,
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
        handledToolCallIDs.removeAll()
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

        conversation.$pendingToolCalls
            .receive(on: DispatchQueue.main)
            .sink { [weak self] toolCalls in
                guard let self else { return }
                for toolCall in toolCalls {
                    self.handle(toolCall: toolCall)
                }
            }
            .store(in: &cancellables)
    }

    private static func voiceState(for state: ConversationState) -> VoiceState {
        switch state {
        case .idle: return .idle
        case .connecting, .active: return .listening
        case .ended: return .idle
        case .error(let error):
            return .unavailable(error.localizedDescription)
        }
    }

    // MARK: - Client tools

    /// Dispatches a `recommendCard` call to the app and acknowledges it.
    ///
    /// The agent supplies `merchant` and `amount`; the app computes the
    /// recommendation and presents it. The acknowledgement only confirms the
    /// call was received — the engine, not the agent, owns the numbers.
    private func handle(toolCall: ClientToolCallEvent) {
        guard toolCall.toolName == Self.clientToolNamespace else { return }
        guard !handledToolCallIDs.contains(toolCall.toolCallId) else { return }
        handledToolCallIDs.insert(toolCall.toolCallId)

        let payload = (try? JSONSerialization.jsonObject(with: toolCall.parametersData)) as? [String: Any]

        guard
            let merchant = payload?["merchant"] as? String,
            let amount = Self.decimal(from: payload?["amount"])
        else {
            respond(to: toolCall.toolCallId, result: ToolAcknowledgement(status: nil, error: "merchant and amount are required"), isError: true)
            return
        }

        onRecommendationRequest?(
            RecommendationRequest(merchant: merchant, amount: amount, category: .dining)
        )
        respond(to: toolCall.toolCallId, result: ToolAcknowledgement(status: "computing", error: nil), isError: false)
    }

    private func respond(to toolCallID: String, result: ToolAcknowledgement, isError: Bool) {
        Task { [conversation] in
            try? await conversation?.sendToolResult(for: toolCallID, result: result, isError: isError)
        }
    }

    /// JSON numbers arrive as `NSNumber`, but a coercing agent may send a string.
    private static func decimal(from value: Any?) -> Decimal? {
        switch value {
        case let number as NSNumber: return number.decimalValue
        case let text as String: return Decimal(string: text)
        default: return nil
        }
    }

    /// The tool result the agent receives. Encodable so the SDK sends valid JSON.
    private struct ToolAcknowledgement: Encodable {
        let status: String?
        let error: String?
    }
}

#endif
