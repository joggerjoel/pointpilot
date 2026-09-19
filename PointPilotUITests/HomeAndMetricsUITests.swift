import XCTest

/// Covers the home screen and the rewards dashboard.
///
/// These are the two screens the redesign added, so they need their own
/// end-to-end coverage: the home screen is the app's front door and the
/// dashboard's figures are the ones most likely to drift from the engine.
final class HomeAndMetricsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// The app opens on the home screen, not straight into the finder.
    func testAppOpensOnHomeScreen() {
        XCTAssertTrue(
            app.buttons["homeFindCardButton"].waitForExistence(timeout: 10),
            "The home screen should be the first thing shown"
        )
        // The finder's text fields must not be present until the user asks for them.
        XCTAssertFalse(app.textFields["merchantField"].exists)
    }

    /// The home screen states what the user has earned and missed.
    func testHomeScreenShowsEarnedAndMissedTotals() {
        XCTAssertTrue(
            app.buttons["homeFindCardButton"].waitForExistence(timeout: 10),
            "The home screen should be visible on launch"
        )

        // The stat tiles are combined accessibility elements, so the exact
        // element type depends on how SwiftUI renders them. Match any type by
        // identifier rather than assuming staticText or other.
        let earned = app.descendants(matching: .any)["homeEarnedStat"]
        XCTAssertTrue(
            earned.waitForExistence(timeout: 5),
            "The earned total should be visible on the home screen"
        )
        XCTAssertTrue(app.descendants(matching: .any)["homeMissedStat"].exists)
    }

    /// The dashboard opens from the home screen and reports its headline figures.
    func testRewardsDashboardOpensFromHome() {
        let rewardsRow = app.buttons["homeRewardsRow"]
        XCTAssertTrue(rewardsRow.waitForExistence(timeout: 10))
        rewardsRow.tap()

        XCTAssertTrue(
            app.staticTexts["metricsTotalEarned"].waitForExistence(timeout: 10),
            "The dashboard should show a total earned figure"
        )
        XCTAssertTrue(app.staticTexts["Left on the table"].exists)
        XCTAssertTrue(app.staticTexts["Card leaderboard"].exists)
        XCTAssertTrue(app.staticTexts["Where you spent"].exists)
        XCTAssertTrue(app.staticTexts["Activity"].exists)
    }

    /// The dashboard disclaims that its figures are demo data.
    func testRewardsDashboardDisclosesDemoData() {
        let rewardsRow = app.buttons["homeRewardsRow"]
        XCTAssertTrue(rewardsRow.waitForExistence(timeout: 10))
        rewardsRow.tap()

        XCTAssertTrue(
            app.staticTexts[
                "Demo data — sample cards, offers and purchase history. Nothing here is financial advice."
            ].waitForExistence(timeout: 10),
            "The dashboard must disclose that its figures are sample data"
        )
    }

    /// The wallet can be opened from the home screen.
    func testWalletOpensFromHome() {
        let walletRow = app.buttons["homeWalletRow"]
        XCTAssertTrue(walletRow.waitForExistence(timeout: 10))
        walletRow.tap()

        XCTAssertTrue(app.staticTexts["Your cards"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Amex Gold"].exists)
    }
}
