import XCTest
@testable import PointPilot

/// Tests for the voice transcript behavior: state deduplication, newest-first
/// history, and local-timezone timestamps.
@MainActor
final class VoiceTranscriptTests: XCTestCase {

    // MARK: - State deduplication

    /// Tapping the microphone twice must not re-announce the greeting.
    ///
    /// Regression test: `start()` re-ran its greeting on every call, so each
    /// tap appended another identical line to the transcript.
    func testStartingAnAlreadyRunningSessionDoesNotRepeatTheGreeting() async throws {
        let service = MockVoiceAgentService()
        var messages: [VoiceMessage] = []
        service.onMessage = { messages.append($0) }

        try await service.start()
        XCTAssertEqual(messages.count, 1, "The first start greets once")

        try await service.start()
        try await service.start()
        XCTAssertEqual(
            messages.count, 1,
            "Repeated starts must not append duplicate greetings"
        )
    }

    /// Only actual state changes are published.
    func testRepeatedIdenticalStatesAreNotReEmitted() async throws {
        let service = MockVoiceAgentService()
        var states: [VoiceState] = []
        service.onStateChange = { states.append($0) }

        try await service.start()
        await service.stop()
        await service.stop()

        // listening -> idle. The second stop changes nothing, so it emits nothing.
        XCTAssertEqual(states, [.listening, .idle])
    }

    /// A second tap while running ends the session rather than restarting it.
    func testSecondTapStopsInsteadOfRestarting() async throws {
        let service = MockVoiceAgentService()
        var states: [VoiceState] = []
        service.onStateChange = { states.append($0) }
        var messages: [VoiceMessage] = []
        service.onMessage = { messages.append($0) }

        try await service.start()
        XCTAssertEqual(states.last, .listening)

        await service.stop()

        XCTAssertEqual(states.last, .idle)
        XCTAssertEqual(messages.count, 1, "Stopping must not add a message")
    }

    // MARK: - Newest-first ordering

    func testHistoryIsOrderedNewestFirst() {
        let repo = SampleDataRepository.shared
        let viewModel = makeViewModel(repository: repo)

        viewModel.appendMessage(VoiceMessage(speaker: .agent, text: "First"))
        viewModel.appendMessage(VoiceMessage(speaker: .user, text: "Second"))
        viewModel.appendMessage(VoiceMessage(speaker: .agent, text: "Third"))

        XCTAssertEqual(
            viewModel.messages.map(\.text),
            ["Third", "Second", "First"],
            "The newest line must be at the top of the history"
        )
    }

    func testConsecutiveDuplicateMessagesAreDropped() {
        let viewModel = makeViewModel(repository: SampleDataRepository.shared)

        viewModel.appendMessage(VoiceMessage(speaker: .agent, text: "Same line"))
        viewModel.appendMessage(VoiceMessage(speaker: .agent, text: "Same line"))

        XCTAssertEqual(viewModel.messages.count, 1, "An immediate repeat must be ignored")
    }

    func testDuplicateTextFromADifferentSpeakerIsKept() {
        let viewModel = makeViewModel(repository: SampleDataRepository.shared)

        viewModel.appendMessage(VoiceMessage(speaker: .agent, text: "Nobu"))
        viewModel.appendMessage(VoiceMessage(speaker: .user, text: "Nobu"))

        XCTAssertEqual(
            viewModel.messages.count, 2,
            "A repeat from the other speaker is a distinct line and must be kept"
        )
    }

    func testNonConsecutiveRepeatsAreKept() {
        let viewModel = makeViewModel(repository: SampleDataRepository.shared)

        viewModel.appendMessage(VoiceMessage(speaker: .agent, text: "A"))
        viewModel.appendMessage(VoiceMessage(speaker: .user, text: "B"))
        viewModel.appendMessage(VoiceMessage(speaker: .agent, text: "A"))

        XCTAssertEqual(
            viewModel.messages.count, 3,
            "Only immediate repeats are duplicates; A-B-A is three real lines"
        )
    }

    // MARK: - Timestamps

    func testMessagesCarryATimestampAndRenderInLocalTime() {
        let now = Date()
        let message = VoiceMessage(speaker: .agent, text: "Hello", timestamp: now)

        XCTAssertEqual(message.timestamp, now)

        // The rendered string must match this device's local timezone
        // formatting for that instant, not a fixed or remote zone.
        let expected = now.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(message.localTimestamp, expected)
        XCTAssertFalse(message.localTimestamp.isEmpty)
    }

    func testTimestampReflectsLocalTimezoneOffset() {
        // Formatting is timezone-relative: the same instant renders differently
        // in two zones. This asserts the value tracks the current timezone
        // rather than being pinned to UTC.
        let instant = Date(timeIntervalSince1970: 1_700_000_000)

        let localFormatter = DateFormatter()
        // .medium matches Date.FormatStyle's .abbreviated, e.g. "Sep 19, 2026".
        localFormatter.dateStyle = .medium
        localFormatter.timeStyle = .short
        localFormatter.timeZone = .current

        let utcFormatter = DateFormatter()
        utcFormatter.dateStyle = .medium
        utcFormatter.timeStyle = .short
        utcFormatter.timeZone = TimeZone(identifier: "UTC")

        let message = VoiceMessage(speaker: .agent, text: "x", timestamp: instant)

        // Whatever the zone, the displayed time must equal the local rendering.
        XCTAssertEqual(message.localTimestamp, localFormatter.string(from: instant))

        if TimeZone.current.secondsFromGMT(for: instant) != 0 {
            XCTAssertNotEqual(
                message.localTimestamp,
                utcFormatter.string(from: instant),
                "Local rendering should differ from UTC when the device is not on UTC"
            )
        }
    }

    /// Today's lines show a bare clock time; older lines also carry the date,
    /// following the convention iOS uses for message threads.
    func testTimestampShowsDateOnlyForLinesNotFromToday() {
        let now = Date()
        let today = VoiceMessage(speaker: .agent, text: "x", timestamp: now)
        XCTAssertEqual(
            today.localTimestamp,
            now.formatted(date: .omitted, time: .shortened),
            "A line from today should show only the time"
        )

        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(
            Calendar.current.isDateInToday(earlier),
            "Fixture must predate today for this assertion to mean anything"
        )

        let older = VoiceMessage(speaker: .agent, text: "x", timestamp: earlier)
        XCTAssertEqual(
            older.localTimestamp,
            earlier.formatted(date: .abbreviated, time: .shortened),
            "An older line should include its date"
        )
    }

    // MARK: - Helpers

    private func makeViewModel(repository: SampleDataRepository) -> AskViewModel {
        AskViewModel(
            engine: RecommendationEngine(cards: repository.cards, merchantProvider: repository),
            repository: repository,
            voiceService: MockVoiceAgentService(),
            voiceIsConfigured: false
        )
    }
}
