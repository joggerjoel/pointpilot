import SwiftUI

@main
struct PointPilotApp: App {
    /// Built once and shared, so cards, offers and merchants come from exactly
    /// one place for the whole app.
    private let repository = SampleDataRepository.shared
    private let configuration = ElevenLabsConfiguration.load()

    var body: some Scene {
        WindowGroup {
            AskView(viewModel: makeViewModel())
        }
    }

    @MainActor
    private func makeViewModel() -> AskViewModel {
        // The real SDK is used when it is linked and configured; otherwise the
        // app runs the same flow through the local mock service.
        let voiceService: VoiceAgentProviding
        if configuration.isConfigured {
            #if canImport(ElevenLabs)
            voiceService = ElevenLabsVoiceAgentService(configuration: configuration)
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
            voiceIsConfigured: configuration.isConfigured
        )
    }
}
