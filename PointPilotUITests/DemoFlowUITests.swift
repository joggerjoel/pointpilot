import XCTest

/// End-to-end test of the demo flow, driving the real UI.
///
/// This is the test that proves the app actually works as demonstrated: typed
/// input produces a recommendation, the breakdown opens, the comparison shows
/// the runner-up, and the simulated activation completes. The unit tests cover
/// the engine's arithmetic; this covers the flow a person will watch.
final class DemoFlowUITests: XCTestCase {

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

    /// The headline scenario: Nobu, $200, Amex Gold wins.
    func testTypedInputProducesAmexGoldRecommendation() {
        enterPurchase(merchant: "Nobu", amount: "200")

        // The recommendation sheet appears with the winning card.
        let value = app.staticTexts["estimatedValueText"]
        XCTAssertTrue(
            value.waitForExistence(timeout: 10),
            "The recommendation screen should appear after submitting input"
        )

        // $45.00 = $16.00 rewards + $20.00 offer + $9.00 airline dining.
        // The label carries VoiceOver context, so the value appears within it.
        XCTAssertEqual(value.label, "Estimated reward value $45.00")

        XCTAssertTrue(
            app.staticTexts["Amex Gold"].exists,
            "Amex Gold should be shown as the recommended card"
        )

        // The runner-up comparison is present with the Sapphire's total.
        XCTAssertTrue(app.staticTexts["Chase Sapphire Preferred"].exists)
        XCTAssertTrue(app.staticTexts["$19.50"].exists)
    }

    /// Expanding the breakdown shows every component of the calculation.
    func testBreakdownExpandsWithAllComponents() {
        enterPurchase(merchant: "Nobu", amount: "200")

        let toggle = app.buttons["seeTheMath"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()

        // Each component line is labelled with its kind and computed amount.
        XCTAssertTrue(app.staticTexts["Card rewards"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["+$16.00"].exists)
        XCTAssertTrue(app.staticTexts["Merchant offer"].exists)
        XCTAssertTrue(app.staticTexts["+$20.00"].exists)
        XCTAssertTrue(app.staticTexts["Airline dining rewards"].exists)
        XCTAssertTrue(app.staticTexts["+$9.00"].exists)
        XCTAssertTrue(app.staticTexts["Total estimated value"].exists)
    }

    /// A capped offer shows its cap as an explicit deduction.
    func testCappedOfferShowsAdjustmentLine() {
        enterPurchase(merchant: "Nobu", amount: "500")

        let toggle = app.buttons["seeTheMath"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()

        // 10% of $500 is $50, capped at $20, so the adjustment is −$30.00.
        XCTAssertTrue(app.staticTexts["Offer cap adjustment"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["−$30.00"].exists)
        XCTAssertTrue(app.staticTexts["Capped at $20.00"].exists)
    }

    /// Simulated activation completes and is labelled as simulated.
    func testSimulatedOfferActivation() {
        enterPurchase(merchant: "Nobu", amount: "200")

        let activate = app.buttons["activateOfferButton"]
        XCTAssertTrue(activate.waitForExistence(timeout: 10))
        activate.tap()

        // The button reflects the simulated state and cannot be pressed again.
        let activated = app.buttons["Activated (simulated)"]
        XCTAssertTrue(
            activated.waitForExistence(timeout: 5),
            "The offer should show as activated in demo mode"
        )
        XCTAssertFalse(activated.isEnabled)
    }

    /// An unknown merchant still works and invents no offer.
    func testUnknownMerchantStillProducesRecommendation() {
        enterPurchase(merchant: "Joe's Random Diner", amount: "200")

        let value = app.staticTexts["estimatedValueText"]
        XCTAssertTrue(value.waitForExistence(timeout: 10))

        // Rewards only: $16.00 on Amex Gold, with no offer at an unknown merchant.
        XCTAssertEqual(value.label, "Estimated reward value $16.00")
        XCTAssertFalse(app.staticTexts["Merchant offer"].exists)
    }

    /// Returning to the Ask screen clears the previous purchase.
    func testAskAnotherReturnsToCleanAskScreen() {
        enterPurchase(merchant: "Nobu", amount: "200")

        let askAnother = app.buttons["askAnotherButton"]
        XCTAssertTrue(askAnother.waitForExistence(timeout: 10))
        askAnother.tap()

        // Back on the Ask screen with the fields cleared.
        let heading = app.staticTexts["Which card should I use?"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))

        let merchantField = app.textFields["merchantField"]
        XCTAssertTrue(merchantField.exists)
        XCTAssertEqual(merchantField.value as? String, "Restaurant, e.g. Nobu")
    }

    /// Tapping the microphone twice must not stack duplicate greeting lines.
    ///
    /// Regression test: every tap re-ran the greeting, so the transcript filled
    /// with identical messages.
    func testRepeatedMicrophoneTapsDoNotDuplicateTheGreeting() {
        let voiceButton = app.buttons["voiceButton"]
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 10), "Voice button should be visible")

        // Transcript rows are combined accessibility elements, so match the
        // greeting by substring against the row label.
        let greetingRows = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Demo voice is on")
        )

        voiceButton.tap()
        XCTAssertTrue(
            greetingRows.firstMatch.waitForExistence(timeout: 5),
            "First tap should greet once"
        )
        XCTAssertEqual(greetingRows.count, 1, "Exactly one greeting after the first tap")

        // Second tap ends the session rather than greeting again.
        voiceButton.tap()
        sleep(1)

        XCTAssertEqual(
            greetingRows.count, 1,
            "The greeting must appear exactly once no matter how many times the mic is tapped"
        )
    }

    /// Transcript lines expose a local timestamp alongside the speaker and text.
    ///
    /// The hierarchy exposes speaker, time and message as separate elements, so
    /// the assertion matches each rather than expecting one merged label.
    func testTranscriptLineExposesLocalTimestamp() {
        let voiceButton = app.buttons["voiceButton"]
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 10))
        voiceButton.tap()

        let message = app.staticTexts[
            "Demo voice is on. Tell me the restaurant and roughly how much you'll spend."
        ]
        XCTAssertTrue(message.waitForExistence(timeout: 5), "The transcript row should be present")

        // A clock time in either 12- or 24-hour form, rendered in local time.
        let clockText = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", #".*\d{1,2}:\d{2}.*"#)
        )
        XCTAssertTrue(
            clockText.firstMatch.waitForExistence(timeout: 5),
            "A transcript line should show a local timestamp"
        )
    }

    /// Tapping a nearby merchant chip auto-populates the merchant field.
    func testNearbyMerchantChipPopulatesMerchantField() {
        let nobuChip = app.buttons["chip_nobu"]
        XCTAssertTrue(nobuChip.waitForExistence(timeout: 10), "Nearby merchant chip should appear")
        nobuChip.tap()

        let merchantField = app.textFields["merchantField"]
        XCTAssertEqual(merchantField.value as? String, "Nobu")
    }

    /// The wallet sheet lists all three sample cards.
    func testWalletShowsAllSampleCards() {
        let walletButton = app.buttons["Wallet"]
        XCTAssertTrue(walletButton.waitForExistence(timeout: 10))
        walletButton.tap()

        XCTAssertTrue(app.staticTexts["Your cards"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Amex Gold"].exists)
        XCTAssertTrue(app.staticTexts["Chase Sapphire Preferred"].exists)
        XCTAssertTrue(app.staticTexts["Capital One Venture"].exists)
    }

    /// A zero amount is rejected without producing a recommendation.
    func testZeroAmountIsRejected() {
        enterPurchase(merchant: "Nobu", amount: "0")

        // The app stays on the Ask screen and explains the problem.
        XCTAssertTrue(
            app.staticTexts["Enter a purchase amount greater than $0.00."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.staticTexts["estimatedValueText"].exists)
    }

    // MARK: - Helpers

    /// Types a merchant and amount, then taps the primary action.
    private func enterPurchase(merchant: String, amount: String) {
        let merchantField = app.textFields["merchantField"]
        XCTAssertTrue(merchantField.waitForExistence(timeout: 10), "Ask screen should be visible")
        merchantField.tap()
        merchantField.typeText(merchant)

        let amountField = app.textFields["amountField"]
        amountField.tap()
        amountField.typeText(amount)

        app.buttons["findBestCardButton"].tap()
    }
}
