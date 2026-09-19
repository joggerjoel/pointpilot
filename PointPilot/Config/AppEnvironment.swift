import Foundation

/// Safely loads configuration from `.env` files, ProcessInfo, or bundled configuration.
///
/// Designed to satisfy Security & Privacy Council mandates:
/// - No API tokens are hardcoded into compiled binaries.
/// - Reads from local gitignored `.env` or `PointPilot.env` files in the development/runtime environment.
/// - Validates placeholders vs real credentials.
struct AppEnvironment: Sendable {
    let yelpAPIKey: String?
    let elevenLabsAgentID: String?

    static let shared = AppEnvironment.load()

    var isYelpConfigured: Bool {
        guard let key = yelpAPIKey else { return false }
        return !key.isEmpty && key != "YOUR_YELP_API_KEY_HERE"
    }

    var isElevenLabsConfigured: Bool {
        guard let id = elevenLabsAgentID else { return false }
        return !id.isEmpty && id != "YOUR_ELEVENLABS_AGENT_ID_HERE"
    }

    static func load(filePaths: [String] = defaultSearchPaths()) -> AppEnvironment {
        var envDict: [String: String] = [:]

        // 1. Check ProcessInfo (e.g. scheme environment variables)
        for (key, value) in ProcessInfo.processInfo.environment {
            envDict[key] = value
        }

        // 2. Parse .env files if present on disk
        for path in filePaths {
            if let parsed = parseEnvFile(at: path) {
                for (k, v) in parsed {
                    // File values take precedence if ProcessInfo is unset or placeholder
                    if envDict[k] == nil || envDict[k]?.contains("YOUR_") == true {
                        envDict[k] = v
                    }
                }
            }
        }

        // 3. Fall back to bundled ElevenLabs.plist if present
        let plistConfig = ElevenLabsConfiguration.load()
        let elevenLabsID = envDict["ELEVENLABS_AGENT_ID"] ?? plistConfig.agentID

        return AppEnvironment(
            yelpAPIKey: sanitize(envDict["YELP_API_KEY"] ?? envDict["YELP_TOKEN"]),
            elevenLabsAgentID: sanitize(elevenLabsID)
        )
    }

    private static func defaultSearchPaths() -> [String] {
        var paths: [String] = []

        // In app bundle (if copied into target)
        if let bundlePath = Bundle.main.path(forResource: "PointPilot", ofType: "env") {
            paths.append(bundlePath)
        }
        if let bundleEnv = Bundle.main.path(forResource: ".env", ofType: nil) {
            paths.append(bundleEnv)
        }

        // Standard development working directory & home paths
        let fm = FileManager.default
        let currentDir = fm.currentDirectoryPath
        paths.append("\(currentDir)/.env")
        paths.append("\(currentDir)/Config/PointPilot.env")
        paths.append("\(currentDir)/PointPilot/Config/PointPilot.env")

        // Also check Developer/PointPilot root if running in Simulator
        #if targetEnvironment(simulator)
        let home = NSHomeDirectory()
        // In simulator, NSHomeDirectory points to sandboxed container; check standard paths
        paths.append("\(home)/Documents/.env")
        #endif

        return paths
    }

    /// Parses a standard .env formatted file (KEY=VALUE with # comments)
    static func parseEnvFile(at path: String) -> [String: String]? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return parseEnvContent(content)
    }

    static func parseEnvContent(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                var val = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip optional quotes
                if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                    val = String(val.dropFirst().dropLast())
                }
                if !key.isEmpty {
                    result[key] = val
                }
            }
        }
        return result
    }

    private static func sanitize(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("YOUR_") || value.hasSuffix("_HERE") {
            return nil
        }
        return value
    }
}
