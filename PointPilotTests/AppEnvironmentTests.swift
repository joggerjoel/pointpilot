import XCTest
@testable import PointPilot

final class AppEnvironmentTests: XCTestCase {

    func testParseEnvContentWithStandardAndQuotedValues() {
        let envContent = """
        # Comment line
        YELP_API_KEY=test_yelp_token_12345
        ELEVENLABS_AGENT_ID="agent_abc_789"
        EMPTY_VAR=
        SPACED_KEY = 'single_quoted_val'
        # Another comment
        """

        let parsed = AppEnvironment.parseEnvContent(envContent)
        XCTAssertEqual(parsed["YELP_API_KEY"], "test_yelp_token_12345")
        XCTAssertEqual(parsed["ELEVENLABS_AGENT_ID"], "agent_abc_789")
        XCTAssertEqual(parsed["SPACED_KEY"], "single_quoted_val")
    }

    func testPlaceholdersAreSanitized() {
        let envContent = """
        YELP_API_KEY=YOUR_YELP_API_KEY_HERE
        ELEVENLABS_AGENT_ID=YOUR_ELEVENLABS_AGENT_ID_HERE
        """

        // Writing temporary env file to verify loader
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_placeholder.env")
        try? envContent.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let env = AppEnvironment.load(filePaths: [tempFile.path])
        XCTAssertFalse(env.isYelpConfigured)
        XCTAssertFalse(env.isElevenLabsConfigured)
    }

    func testValidEnvKeyIsRecognized() {
        let envContent = "YELP_API_KEY=real_fusion_key_abcdef123456"
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_valid.env")
        try? envContent.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let env = AppEnvironment.load(filePaths: [tempFile.path])
        XCTAssertTrue(env.isYelpConfigured)
        XCTAssertEqual(env.yelpAPIKey, "real_fusion_key_abcdef123456")
    }
}
