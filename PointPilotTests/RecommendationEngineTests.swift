import XCTest
@testable import PointPilot

/// Tests for the recommendation engine.
///
/// These are pure unit tests: no UI, no network, no voice service. Every case
/// runs against the shared sample repository so the tests also pin down the
/// demo data the presentation depends on.
final class RecommendationEngineTests: XCTestCase {

    private var repository: SampleDataRepository!
    private var engine: RecommendationEngine!

    override func setUp() {
        super.setUp()
        repository = SampleDataRepository.shared
        engine = RecommendationEngine(cards: repository.cards, merchantProvider: repository)
    }

    override func tearDown() {
        engine = nil
        repository = nil
        super.tearDown()
    }

    // MARK: 1 — Amex Gold wins for dining without an offer

    func testAmexGoldWinsForDiningWhenRewardValueIsHighest() throws {
        // Starbucks has no merchant offer, so this is a pure rewards comparison.
        let result = try engine.recommend(merchantQuery: "Starbucks", amount: 100)

        XCTAssertEqual(result.winner.card.id, SampleDataRepository.amexGoldID)

        // 4× points on $100 at $0.02 = $8.00
        let expectedBase = Decimal(8)
        XCTAssertEqual(result.winner.baseReward?.amount, expectedBase)
        XCTAssertEqual(result.winner.offerRequiringActivation, nil)
    }

    // MARK: 2 — A merchant offer changes the winning card

    func testMerchantOfferChangesWinningCard() throws {
        // Baseline: the same merchant with the Sapphire offer removed, so only
        // multipliers are in play. Amex Gold's 4× dining rate wins.
        let offersWithoutShakeShack = repository.offers.filter {
            $0.merchantID != SampleDataRepository.shakeShackID
        }
        let baselineEngine = RecommendationEngine(
            cards: repository.cards,
            merchantProvider: FixtureRepository(
                cards: repository.cards,
                merchants: repository.merchants,
                offers: offersWithoutShakeShack,
                diningProgram: repository.diningProgram
            )
        )

        let baseline = try baselineEngine.recommend(merchantQuery: "Shake Shack", amount: 50)
        XCTAssertEqual(baseline.winner.card.id, SampleDataRepository.amexGoldID)

        // Restoration of the $5 Sapphire offer flips the winner, proving that
        // offers — not just multipliers — drive the outcome.
        let flipped = try engine.recommend(merchantQuery: "Shake Shack", amount: 50)
        XCTAssertEqual(flipped.winner.card.id, SampleDataRepository.sapphirePreferredID)
        XCTAssertNotEqual(flipped.winner.card.id, baseline.winner.card.id)
    }

    // MARK: 3 — A capped percentage offer never exceeds its maximum

    func testCappedPercentageOfferDoesNotExceedMaximum() throws {
        // Nobu: 10% back on Amex Gold, capped at $20. On $500 the uncapped value
        // would be $50, so the cap must hold it to $20.
        let result = try engine.recommend(merchantQuery: "Nobu", amount: 500)
        let amex = try XCTUnwrap(
            result.ranked.first { $0.card.id == SampleDataRepository.amexGoldID }
        )

        let offerComponent = try XCTUnwrap(
            amex.components.first { $0.kind == .merchantOffer }
        )
        let capComponent = try XCTUnwrap(
            amex.components.first { $0.kind == .capAdjustment }
        )

        XCTAssertEqual(offerComponent.amount, Decimal(50))
        XCTAssertEqual(capComponent.amount, Decimal(-30))
        // Advertised value plus its adjustment equals the cap exactly.
        XCTAssertEqual(offerComponent.amount + capComponent.amount, Decimal(20))
        XCTAssertLessThanOrEqual(
            offerComponent.amount + capComponent.amount,
            Decimal(20)
        )
    }

    func testCappedOfferIsNotAppliedWhenUnderTheCap() throws {
        // 10% of $100 is $10, below the $20 cap, so no adjustment line appears.
        let result = try engine.recommend(merchantQuery: "Nobu", amount: 100)
        let amex = try XCTUnwrap(
            result.ranked.first { $0.card.id == SampleDataRepository.amexGoldID }
        )

        XCTAssertNil(amex.components.first { $0.kind == .capAdjustment })
        XCTAssertEqual(
            amex.components.first { $0.kind == .merchantOffer }?.amount,
            Decimal(10)
        )
    }

    // MARK: 4 — Airline dining value stacks correctly

    func testAirlineDiningValueStacksOnTopOfCardRewards() throws {
        // Nobu is airline-dining eligible: 3 miles per dollar at $0.015 = $0.045
        // per dollar, so $200 yields $9.00 on top of the card's own rewards.
        let result = try engine.recommend(merchantQuery: "Nobu", amount: 200)
        let amex = try XCTUnwrap(
            result.ranked.first { $0.card.id == SampleDataRepository.amexGoldID }
        )

        let dining = try XCTUnwrap(
            amex.components.first { $0.kind == .diningProgram }
        )
        XCTAssertEqual(dining.amount, Decimal(string: "9.00"))

        // Every card earns the program, since it belongs to the restaurant.
        for evaluation in result.ranked {
            XCTAssertNotNil(
                evaluation.components.first { $0.kind == .diningProgram },
                "\(evaluation.card.name) should earn airline dining value at Nobu"
            )
        }

        // Components sum exactly to the reported total.
        let summed = amex.components.reduce(Decimal.zero) { $0 + $1.amount }
        XCTAssertEqual(summed, amex.totalValue)
    }

    func testAirlineDiningProgramSkippedForIneligibleMerchant() throws {
        // Starbucks is not in the dining program, so no program line appears.
        let result = try engine.recommend(merchantQuery: "Starbucks", amount: 200)
        for evaluation in result.ranked {
            XCTAssertNil(evaluation.components.first { $0.kind == .diningProgram })
        }
    }

    // MARK: 5 — Unknown merchants get no invented offer

    func testUnknownMerchantReceivesNoInventedOffer() throws {
        let result = try engine.recommend(merchantQuery: "Joe's Random Diner", amount: 200)

        XCTAssertTrue(result.usedFallbackMerchant)
        XCTAssertEqual(result.category, .dining)

        for evaluation in result.ranked {
            XCTAssertNil(
                evaluation.components.first { $0.kind == .merchantOffer },
                "\(evaluation.card.name) must not receive an offer at an unknown merchant"
            )
            XCTAssertNil(evaluation.components.first { $0.kind == .diningProgram })
            XCTAssertNil(evaluation.offerRequiringActivation)
        }

        // The calculation still works, using the dining category rate alone.
        XCTAssertEqual(result.winner.card.id, SampleDataRepository.amexGoldID)
        XCTAssertEqual(result.winner.baseReward?.amount, Decimal(16))
    }

    func testEmptyMerchantQueryFallsBackWithoutWarning() throws {
        let result = try engine.recommend(merchantQuery: "", amount: 100)
        XCTAssertTrue(result.usedFallbackMerchant)
        XCTAssertTrue(result.warnings.isEmpty, "An empty query should not warn about an unknown merchant")
    }

    // MARK: 6 — Non-positive amounts are rejected

    func testZeroAmountIsRejected() {
        XCTAssertThrowsError(try engine.recommend(merchantQuery: "Nobu", amount: 0)) { error in
            XCTAssertEqual(error as? RecommendationError, .invalidAmount(0))
        }
    }

    func testNegativeAmountIsRejected() {
        XCTAssertThrowsError(try engine.recommend(merchantQuery: "Nobu", amount: -25)) { error in
            XCTAssertEqual(error as? RecommendationError, .invalidAmount(-25))
        }
    }

    func testNoCardsIsRejected() {
        let empty = RecommendationEngine(cards: [], merchantProvider: repository)
        XCTAssertThrowsError(try empty.recommend(merchantQuery: "Nobu", amount: 100)) { error in
            XCTAssertEqual(error as? RecommendationError, .noCardsAvailable)
        }
    }

    // MARK: 7 — Ties resolve deterministically

    func testTiesResolveDeterministically() throws {
        // Two identical cards except for wallet priority: the lower number wins,
        // regardless of the order they are supplied in.
        let cardA = try makeCard(id: "card-a", priority: 1)
        let cardB = try makeCard(id: "card-b", priority: 0)

        let forward = RecommendationEngine(
            cards: [cardA, cardB],
            merchantProvider: repository
        )
        let reversed = RecommendationEngine(
            cards: [cardB, cardA],
            merchantProvider: repository
        )

        let firstResult = try forward.recommend(merchantQuery: "Starbucks", amount: 100)
        let secondResult = try reversed.recommend(merchantQuery: "Starbucks", amount: 100)

        XCTAssertEqual(firstResult.winner.card.id, "card-b")
        XCTAssertEqual(secondResult.winner.card.id, "card-b")
        XCTAssertEqual(firstResult.winner.totalValue, secondResult.winner.totalValue)
        XCTAssertEqual(firstResult.advantageOverRunnerUp, 0)
    }

    func testRepeatedRunsProduceIdenticalResults() throws {
        let first = try engine.recommend(merchantQuery: "Nobu", amount: 200)
        let second = try engine.recommend(merchantQuery: "Nobu", amount: 200)

        XCTAssertEqual(first.winner.card.id, second.winner.card.id)
        XCTAssertEqual(first.winner.totalValue, second.winner.totalValue)
        XCTAssertEqual(first.winner.components, second.winner.components)
        XCTAssertEqual(first.explanation, second.explanation)
    }

    // MARK: 8 — Currency values round consistently

    func testCurrencyRoundingIsConsistent() throws {
        XCTAssertEqual(
            Currency.rounded(try XCTUnwrap(Decimal(string: "1.005"))),
            try XCTUnwrap(Decimal(string: "1.01"))
        )
        XCTAssertEqual(
            Currency.rounded(try XCTUnwrap(Decimal(string: "1.004"))),
            try XCTUnwrap(Decimal(string: "1.00"))
        )
        XCTAssertEqual(
            Currency.rounded(try XCTUnwrap(Decimal(string: "2.675"))),
            try XCTUnwrap(Decimal(string: "2.68"))
        )
        XCTAssertEqual(
            Currency.rounded(try XCTUnwrap(Decimal(string: "-1.005"))),
            try XCTUnwrap(Decimal(string: "-1.01"))
        )
        XCTAssertEqual(Currency.rounded(Decimal(10)), Decimal(10))
    }

    func testDisplayedComponentsSumToDisplayedTotal() throws {
        // Any amount a user can type must produce a breakdown whose lines add up.
        for amount in [Decimal(1), 7, 19.99, 100, 200, 333.33, 5000] {
            let result = try engine.recommend(merchantQuery: "Nobu", amount: amount)
            for evaluation in result.ranked {
                let roundedSum = evaluation.components
                    .map { Currency.rounded($0.amount) }
                    .reduce(Decimal.zero) { $0 + $1 }
                XCTAssertEqual(
                    Currency.rounded(roundedSum),
                    evaluation.totalValue,
                    "Breakdown must sum to the total for \(evaluation.card.name) at \(amount)"
                )
            }
        }
    }

    func testAmountIsRoundedBeforeEvaluation() throws {
        // $10.005 rounds to $10.01 → 4× points at $0.02 = $0.80.
        let result = try engine.recommend(
            merchantQuery: "Starbucks",
            amount: try XCTUnwrap(Decimal(string: "10.005"))
        )
        XCTAssertEqual(result.amount, Decimal(string: "10.01"))
        XCTAssertEqual(result.winner.baseReward?.amount, Decimal(string: "0.80"))
    }

    func testCurrencyFormatting() throws {
        XCTAssertEqual(Currency.string(try XCTUnwrap(Decimal(string: "21.4"))), "$21.40")
        XCTAssertEqual(Currency.string(Decimal(0)), "$0.00")
        XCTAssertEqual(Currency.signedString(Decimal(-20)), "−$20.00")
        XCTAssertEqual(Currency.signedString(Decimal(20)), "+$20.00")
    }

    /// Sub-cent rates must not be rounded into a figure that contradicts the
    /// total on the same screen. $0.015 must never read as "$0.02".
    func testRateFormattingKeepsSubCentPrecision() throws {
        XCTAssertEqual(Currency.rateString(try XCTUnwrap(Decimal(string: "0.015"))), "$0.015")
        XCTAssertEqual(Currency.rateString(try XCTUnwrap(Decimal(string: "0.0175"))), "$0.0175")
        XCTAssertEqual(Currency.rateString(try XCTUnwrap(Decimal(string: "0.02"))), "$0.02")
        XCTAssertEqual(Currency.rateString(Decimal(1)), "$1.00")
    }

    func testAirlineDiningLabelShowsTheRateActuallyUsed() throws {
        let result = try engine.recommend(merchantQuery: "Nobu", amount: 200)
        let amex = try XCTUnwrap(
            result.ranked.first { $0.card.id == SampleDataRepository.amexGoldID }
        )
        let dining = try XCTUnwrap(amex.components.first { $0.kind == .diningProgram })

        // 3 miles per dollar on $200 = 600 miles, valued at $0.015 each = $9.00.
        XCTAssertEqual(dining.amount, Decimal(9))
        XCTAssertTrue(
            dining.label.contains("$0.015"),
            "Label should state the real rate, got: \(dining.label)"
        )
        XCTAssertFalse(
            dining.label.contains("$0.02 each"),
            "Label must not round the rate into a contradictory figure: \(dining.label)"
        )
    }

    // MARK: Merchant matching

    func testMerchantMatchingIsCaseAndPunctuationInsensitive() {
        XCTAssertEqual(repository.merchant(matching: "  NOBU! ")?.id, SampleDataRepository.nobuID)
        XCTAssertEqual(repository.merchant(matching: "shake shack")?.id, SampleDataRepository.shakeShackID)
        XCTAssertEqual(repository.merchant(matching: "ShakeShack")?.id, SampleDataRepository.shakeShackID)
        XCTAssertNil(repository.merchant(matching: "Some Place Nobody Knows"))
    }

    func testMerchantMatchingResolvesAliasesAndSubstrings() {
        XCTAssertEqual(repository.merchant(matching: "nobu downtown")?.id, SampleDataRepository.nobuID)
        XCTAssertEqual(repository.merchant(matching: "chipotle mexican grill")?.id, SampleDataRepository.chipotleID)
    }

    // MARK: Explanation

    func testExplanationStatesTheDollarAdvantage() throws {
        let result = try engine.recommend(merchantQuery: "Starbucks", amount: 100)
        XCTAssertTrue(result.explanation.contains("Amex Gold"))
        XCTAssertTrue(result.explanation.contains("Starbucks"))
        XCTAssertTrue(result.explanation.contains(Currency.string(result.winner.totalValue)))
        XCTAssertTrue(result.explanation.contains(Currency.string(result.advantageOverRunnerUp)))
    }

    func testNobuEndToEndMatchesDocumentedBreakdown() throws {
        // The demo scenario, checked component by component.
        let result = try engine.recommend(merchantQuery: "Nobu", amount: 200)
        let amex = try XCTUnwrap(
            result.ranked.first { $0.card.id == SampleDataRepository.amexGoldID }
        )

        XCTAssertEqual(result.winner.card.id, SampleDataRepository.amexGoldID)
        XCTAssertEqual(amex.components.first { $0.kind == .baseReward }?.amount, Decimal(16))
        XCTAssertEqual(amex.components.first { $0.kind == .merchantOffer }?.amount, Decimal(20))
        XCTAssertEqual(amex.components.first { $0.kind == .diningProgram }?.amount, Decimal(9))
        XCTAssertEqual(amex.totalValue, Decimal(45))
        XCTAssertNotNil(amex.offerRequiringActivation)

        // Runner-up is Chase Sapphire Preferred: $10.50 rewards + $9.00 dining.
        let runnerUp = try XCTUnwrap(result.runnerUp)
        XCTAssertEqual(runnerUp.card.id, SampleDataRepository.sapphirePreferredID)
        XCTAssertEqual(runnerUp.totalValue, Decimal(string: "19.50"))
        XCTAssertEqual(result.advantageOverRunnerUp, Decimal(string: "25.50"))
    }

    // MARK: - Helpers

    private func makeCard(id: String, priority: Int) throws -> CreditCard {
        CreditCard(
            id: id,
            name: "Tie Card \(id)",
            issuer: "Sample Bank",
            rewardUnitName: "points",
            multipliers: [:],
            defaultMultiplier: 1,
            pointValue: try XCTUnwrap(Decimal(string: "0.01")),
            annualFee: 0,
            priority: priority,
            accentHex: "#555555"
        )
    }
}

/// A repository with caller-supplied contents, used to isolate tests from the
/// shipped sample data. It reuses the real matching logic from the protocol
/// extension so merchant resolution behaves identically.
private struct FixtureRepository: MerchantProviding {
    let cards: [CreditCard]
    let merchants: [Merchant]
    let offers: [CardOffer]
    let diningProgram: DiningProgram
}
