import Foundation

/// Reads ElevenLabs credentials from a gitignored plist that is not committed.
///
/// The real agent ID never lives in source. When the plist is missing or still
/// holds placeholders, `isConfigured` is false and the app runs in demo mode
/// using typed input plus local recommendations.
///
/// `Config/ElevenLabs.example.plist` is committed as the safe template.
struct ElevenLabsConfiguration {
    let agentID: String?
    let userID: String?

    static let placeholderAgentID = "YOUR_AGENT_ID_HERE"

    /// Loads configuration, preferring a local plist in the app bundle.
    ///
    /// In a production app the conversation token would be minted by a backend;
    /// this MVP reads a public agent ID from local configuration only.
    static func load(bundle: Bundle = .main) -> ElevenLabsConfiguration {
        guard
            let url = bundle.url(forResource: "ElevenLabs", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return ElevenLabsConfiguration(agentID: nil, userID: nil)
        }

        let agentID = (plist["AgentID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userID = (plist["UserID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ElevenLabsConfiguration(
            agentID: Self.isUsable(agentID) ? agentID : nil,
            userID: Self.isUsable(userID) ? userID : nil
        )
    }

    /// Rejects nil, empty, and untouched placeholder values.
    private static func isUsable(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value != placeholderAgentID
    }

    var isConfigured: Bool { agentID != nil }
}
