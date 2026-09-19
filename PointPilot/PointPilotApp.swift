import SwiftUI

@main
struct PointPilotApp: App {
    /// Built once and shared, so cards, offers and merchants come from exactly
    /// one place for the whole app.
    private let repository = SampleDataRepository.shared
    /// One source of truth for credentials — `.env`, scheme environment
    /// variables, or the gitignored `ElevenLabs.plist`. Reading it here keeps
    /// the Yelp and voice halves from disagreeing about what is configured.
    private let environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: makeViewModel())
        }
    }

    @MainActor
    private func makeViewModel() -> AskViewModel {
        // The real SDK is used when it is linked and configured; otherwise the
        // app runs the same flow through the local mock service.
        let voiceService: VoiceAgentProviding
        if let agentID = environment.elevenLabsAgentID {
            #if canImport(ElevenLabs)
            voiceService = ElevenLabsVoiceAgentService(
                configuration: ElevenLabsConfiguration(agentID: agentID, userID: nil)
            )
            #else
            voiceService = MockVoiceAgentService()
            #endif
        } else {
            voiceService = MockVoiceAgentService()
        }

        let locationService = LocationService()
        let yelpService = YelpFusionService()

        return AskViewModel(
            engine: RecommendationEngine(cards: repository.cards, merchantProvider: repository),
            repository: repository,
            voiceService: voiceService,
            locationService: locationService,
            merchantDataService: yelpService,
            voiceIsConfigured: environment.elevenLabsAgentID != nil
        )
    }
}
