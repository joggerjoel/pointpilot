import XCTest
@testable import PointPilot

final class VoiceServiceProbeTests: XCTestCase {
    func testVoiceServiceConfiguration() throws {
        let env = AppEnvironment.shared

        let report: [String: Any] = [
            "isElevenLabsConfigured": env.isElevenLabsConfigured
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/pp-voice-probe.json"))

        XCTAssertTrue(env.isElevenLabsConfigured,
                      "Expected ElevenLabs to be configured, but AppEnvironment reported false.")
    }
}
