import SwiftUI

/// The app's root: one navigation stack, one shared view model.
///
/// The home screen is the front door; the card finder and the rewards dashboard
/// are pushed onto the same stack. The wallet is a sheet, because it is
/// reference material the user dips into rather than a step in a flow.
struct RootView: View {
    @State var viewModel: AskViewModel

    /// Destinations that can be pushed. An enum keeps the stack typed, so a
    /// route can never be pushed with the wrong payload.
    enum Route: Hashable {
        case findCard
        case rewards
    }

    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                viewModel: viewModel,
                onFindCard: { path.append(.findCard) },
                onShowMetrics: { path.append(.rewards) },
                onShowWallet: { viewModel.showWallet() }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .findCard:
                    AskView(viewModel: viewModel)
                case .rewards:
                    MetricsView(metrics: viewModel.repository.metrics)
                }
            }
        }
        // The wallet is presented once, here, rather than by each screen that
        // can open it — two sheets observing the same flag would race.
        .sheet(isPresented: Binding(
            get: { viewModel.isShowingWallet },
            set: { if !$0 { viewModel.hideWallet() } }
        )) {
            WalletView(repository: viewModel.repository)
        }
    }
}

#Preview {
    RootView(
        viewModel: AskViewModel(
            engine: RecommendationEngine(
                cards: SampleDataRepository.shared.cards,
                merchantProvider: SampleDataRepository.shared
            ),
            repository: .shared,
            voiceService: MockVoiceAgentService(),
            voiceIsConfigured: false
        )
    )
}
