import SwiftUI

/// The card finder: one question, one action.
///
/// Pushed onto the stack owned by `RootView`; it deliberately does not create
/// its own `NavigationStack`.
struct AskView: View {
    @State var viewModel: AskViewModel
    @FocusState private var focusedField: Field?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Text typed into the voice agent, so voice is usable without a microphone
    /// — the same affordance the web app offers.
    @State private var voiceText = ""

    private enum Field { case merchant, amount }

    var body: some View {
        // No NavigationStack here: this screen is pushed onto the stack that
        // RootView owns. Nesting a second stack would break the back button.
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                header
                voiceSection
                fallbackSection
                walletPreview
            }
            .padding(.horizontal, Theme.Spacing.section)
            .padding(.bottom, Theme.Spacing.loose)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("PointPilot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showWallet()
                } label: {
                    Label("Wallet", systemImage: "wallet.pass")
                }
            }
        }
        // The wallet sheet lives on RootView: two observers of the same flag
        // would race to present it.
        .sheet(item: Binding(
            get: { viewModel.recommendation },
            set: { if $0 == nil { viewModel.askAnother() } }
        )) { recommendation in
            RecommendationView(
                recommendation: recommendation,
                activatedOfferID: viewModel.activatedOfferID,
                onActivate: { viewModel.activateOffer(offerID: $0) },
                onAskAnother: { viewModel.askAnother() }
            )
        }
        // Location is requested only when the user taps "Nearby" — never on
        // launch, so the system permission dialog never greets the user before
        // they have asked for anything.
        .task {
            viewModel.loadDefaultNearbyMerchants()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text("Which card should I use?")
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text("Tell me where you are and what you'll spend, and I'll pick your best card.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Spacing.standard)
    }

    // MARK: - Voice

    private var voiceSection: some View {
        VStack(spacing: Theme.Spacing.standard) {
            voiceButton

            Text(viewModel.voiceState.statusText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(viewModel.voiceState.isBusy ? Color.accentColor : .secondary)
                .accessibilityAddTraits(.updatesFrequently)

            if let notice = viewModel.voiceNotice {
                NoticeBanner(text: notice, systemImage: "mic.slash", tone: .informational)
            }

            if let error = viewModel.errorMessage {
                NoticeBanner(text: error, systemImage: "exclamationmark.triangle", tone: .warning) {
                    viewModel.dismissError()
                }
            }

            if !viewModel.messages.isEmpty {
                transcript
            }

            if viewModel.isVoiceBusy {
                voiceTextInput
            }
        }
    }

    /// Typed input for the running agent.
    ///
    /// The agent's parser is the same either way, so typing exercises the real
    /// tool-calling path. This is what makes the conversational flow usable when
    /// speech recognition is unavailable.
    private var voiceTextInput: some View {
        HStack(spacing: Theme.Spacing.tight) {
            TextField("Type what you'd say…", text: $voiceText)
                .submitLabel(.send)
                .onSubmit(sendVoiceText)
                .padding(Theme.Spacing.standard)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .accessibilityIdentifier("voiceTextField")
                .accessibilityLabel("Type a message for the voice agent")

            Button(action: sendVoiceText) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .frame(minWidth: Theme.minimumTouchTarget, minHeight: Theme.minimumTouchTarget)
            }
            .disabled(voiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("voiceSendButton")
            .accessibilityLabel("Send to the voice agent")
        }
    }

    private func sendVoiceText() {
        viewModel.sendVoiceText(voiceText)
        voiceText = ""
    }

    private var voiceButton: some View {
        Button {
            Haptics.impact()
            viewModel.toggleVoice()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: buttonDiameter + 28, height: buttonDiameter + 28)
                    .scaleEffect(viewModel.voiceState.isBusy ? 1.06 : 1)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: viewModel.isVoiceBusy
                    )

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: buttonDiameter, height: buttonDiameter)
                    .shadow(color: .accentColor.opacity(0.3), radius: 12, y: 6)

                Image(systemName: viewModel.voiceState.isBusy ? "waveform" : "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor, isActive: viewModel.voiceState.isBusy)
            }
            .frame(minWidth: Theme.minimumTouchTarget, minHeight: Theme.minimumTouchTarget)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canUseVoice)
        .opacity(viewModel.canUseVoice ? 1 : 0.5)
        .accessibilityLabel(viewModel.voiceState.isBusy ? "Stop listening" : "Start voice input")
        .accessibilityHint("Asks for the restaurant and how much you'll spend.")
        .accessibilityIdentifier("voiceButton")
        .padding(.top, Theme.Spacing.tight)
    }

    /// Shrinks slightly at the largest accessibility sizes so the button never
    /// pushes the text input off screen.
    private var buttonDiameter: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 108 : 132
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            // Newest first: `messages` is ordered latest-to-earliest, so the
            // top of the list is always the most recent exchange.
            ForEach(viewModel.messages.prefix(4)) { message in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.tight) {
                        Text(message.speaker.displayName)
                            .font(.caption2.weight(.semibold))
                        Spacer(minLength: 0)
                        Text(message.localTimestamp)
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)

                    Text(message.text)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.standard)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conversation history, most recent first")
    }

    // MARK: - Typed fallback

    private var fallbackSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            HStack {
                Text("Or choose / type")
                    .font(.headline)
                Spacer()
                Button {
                    Haptics.impact()
                    viewModel.detectLocationAndFetchNearby()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isLocating ? "location.fill" : "location")
                            .symbolEffect(.pulse, isActive: viewModel.isLocating)
                        Text(viewModel.isLocating ? "Locating…" : "Nearby")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityLabel("Detect nearby restaurants with GPS")
                .accessibilityIdentifier("nearbyGpsButton")
            }

            if !viewModel.nearbyMerchants.isEmpty {
                nearbyChips

                // Live venues and bundled samples look identical once they are
                // chips, so the sample case has to say so — otherwise an
                // expired key or an outage reads as working GPS results. Shown
                // only after a real attempt, so launch is not noisy.
                if viewModel.showsSampleSourceNotice {
                    Text("Showing sample venues — live Yelp results unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("nearbySourceNotice")
                }
            }

            // A failed location attempt must explain itself rather than look
            // like a dead button.
            if let locationNotice = viewModel.locationNotice {
                NoticeBanner(
                    text: locationNotice,
                    systemImage: "location.slash",
                    tone: .informational
                )
                .accessibilityIdentifier("locationNotice")
            }

            TextField("Restaurant, e.g. Nobu", text: $viewModel.merchantQuery)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focusedField, equals: .merchant)
                .onSubmit { focusedField = .amount }
                .accessibilityIdentifier("merchantField")
                .padding(Theme.Spacing.standard)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .accessibilityLabel("Restaurant name")

            TextField("Amount, e.g. 200", text: $viewModel.amountText)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .amount)
                .accessibilityIdentifier("amountField")
                .padding(Theme.Spacing.standard)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .accessibilityLabel("Purchase amount in dollars")

            Button {
                focusedField = nil
                viewModel.submitTypedInput()
            } label: {
                Text("Find My Best Card")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.minimumTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("findBestCardButton")
        }
    }

    private var nearbyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.tight) {
                ForEach(viewModel.nearbyMerchants) { merchant in
                    let isSelected = viewModel.merchantQuery.lowercased() == merchant.name.lowercased()
                    let hasOffer = viewModel.repository.offers.contains { $0.merchantID == merchant.id }

                    Button {
                        viewModel.selectNearbyMerchant(merchant)
                    } label: {
                        HStack(spacing: 4) {
                            if hasOffer {
                                Image(systemName: "tag.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Text(merchant.name)
                                .font(.caption.weight(isSelected ? .bold : .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(merchant.name)\(hasOffer ? ", active card offer available" : "")")
                    .accessibilityIdentifier("chip_\(merchant.id)")
                }
            }
        }
        .accessibilityLabel("Nearby restaurants suggestions")
    }

    // MARK: - Wallet preview

    private var walletPreview: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            HStack {
                Text("Your wallet")
                    .font(.headline)
                Spacer()
                Button("View all") { viewModel.showWallet() }
                    .font(.subheadline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.standard) {
                    ForEach(viewModel.cards) { card in
                        CardFaceView(card: card, isCompact: true)
                            .frame(width: 180)
                    }
                }
            }
            .accessibilityLabel("Cards in your wallet")

            Text("Demo data — sample cards and offers, not real accounts.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// A small inline banner used for notices and errors.
struct NoticeBanner: View {
    enum Tone {
        case informational
        case warning
        case success

        var color: Color {
            switch self {
            case .informational: return .accentColor
            case .warning: return .orange
            case .success: return .green
            }
        }
    }

    let text: String
    let systemImage: String
    let tone: Tone
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.tight) {
            Image(systemName: systemImage)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)

            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(Theme.Spacing.standard)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(tone.color.opacity(0.10))
        )
        // Only merge the banner into one element when there is nothing
        // interactive inside it. Combining would fold the dismiss button into a
        // single element and make it unreachable for VoiceOver.
        .accessibilityElement(children: onDismiss == nil ? .combine : .contain)
    }
}

#Preview {
    AskView(
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
