import SwiftUI

struct LiveVoiceConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: LiveVoiceSessionViewModel
    let appState: AppState

    init(appState: AppState, chatViewModel: ChatViewModel) {
        self.appState = appState
        _viewModel = State(initialValue: LiveVoiceSessionViewModel(appState: appState, chatViewModel: chatViewModel))
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                navigationBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 12)

                VoiceOrbView(state: viewModel.orbState, size: 200)
                    .padding(.bottom, 8)

                statusLabel
                    .padding(.bottom, 20)

                transcriptArea
                    .padding(.horizontal, 20)

                Spacer(minLength: 20)

                micButton
                    .padding(.bottom, 40)
            }
        }
        .task {
            await viewModel.refresh()
        }
        .onChange(of: appState.voiceSessionInvalidationSeed) { _, _ in
            Task {
                await viewModel.invalidateForLanguageChange()
                dismiss()
            }
        }
        .onDisappear {
            Task {
                await viewModel.close()
            }
        }
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [
                BrandPalette.navy,
                Color(red: 0.04, green: 0.04, blue: 0.10),
                Color(red: 0.02, green: 0.02, blue: 0.06)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Text(viewModel.voiceLocale.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .liquidGlassSurface(
                    tint: BrandPalette.accent.opacity(0.12),
                    in: Capsule(),
                    fallback: AnyShapeStyle(.ultraThinMaterial)
                )

            Spacer()

            Button {
                Haptics.impactLight()
                Task {
                    await viewModel.close()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .liquidGlassSurface(
                        in: Circle(),
                        fallback: AnyShapeStyle(.ultraThinMaterial),
                        interactive: true
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String.appLocalized("voice.close"))
        }
    }

    // MARK: - Status Label

    private var statusLabel: some View {
        Text(viewModel.statusText)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .animation(.easeInOut(duration: 0.3), value: viewModel.statusText)
    }

    // MARK: - Transcript Area

    private var transcriptArea: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !viewModel.lastUserTranscript.isEmpty {
                    userTranscriptCard
                }

                if !viewModel.partialTranscript.isEmpty {
                    listeningTranscriptCard
                }

                if let unavailableReason = viewModel.unavailableReason {
                    noticeCard(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        body: unavailableReason
                    )
                }

                if let memoryWarningMessage = viewModel.memoryWarningMessage {
                    noticeCard(
                        icon: "memorychip.fill",
                        tint: BrandPalette.cyan,
                        body: memoryWarningMessage
                    )
                }

                if let errorMessage = viewModel.errorMessage {
                    noticeCard(
                        icon: "exclamationmark.circle.fill",
                        tint: .red,
                        body: errorMessage
                    )
                }

                if viewModel.needsAssetDownload && viewModel.unavailableReason == nil {
                    assetDownloadCard
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var userTranscriptCard: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 6) {
                Text(String.appLocalized("voice.you_said"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandPalette.accent.opacity(0.8))
                Text(viewModel.lastUserTranscript)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .liquidGlassSurface(
                tint: BrandPalette.accent.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                fallback: AnyShapeStyle(.ultraThinMaterial)
            )
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private var listeningTranscriptCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(String.appLocalized("voice.listening"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandPalette.cyan.opacity(0.8))
                Text(viewModel.partialTranscript)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .liquidGlassSurface(
                tint: BrandPalette.cyan.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                fallback: AnyShapeStyle(.ultraThinMaterial)
            )
            Spacer(minLength: 48)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private func noticeCard(icon: String, tint: Color, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .liquidGlassSurface(
            tint: tint.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            fallback: AnyShapeStyle(.ultraThinMaterial)
        )
    }

    private var assetDownloadCard: some View {
        VStack(spacing: 14) {
            Text(String(format: String.appLocalized("voice.download_body"), viewModel.voiceLocale.displayName))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button {
                Haptics.impactMedium()
                Task {
                    await viewModel.downloadAssets()
                }
            } label: {
                Group {
                    if viewModel.isPreparingAssets {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        Text(String.appLocalized("voice.download_title"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .liquidGlassButtonStyle(prominent: true, tint: BrandPalette.accent)
            .disabled(viewModel.isPreparingAssets)
        }
        .padding(20)
        .liquidGlassSurface(
            tint: BrandPalette.accent.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            fallback: AnyShapeStyle(.ultraThinMaterial)
        )
    }

    // MARK: - Mic Button

    private var micButton: some View {
        Button {
            Haptics.impactMedium()
            Task {
                await viewModel.toggleListening()
            }
        } label: {
            ZStack {
                if viewModel.isListening {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 108, height: 108)

                    Circle()
                        .stroke(Color.red.opacity(0.25), lineWidth: 2)
                        .frame(width: 108, height: 108)
                }

                Image(systemName: viewModel.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .liquidGlassSurface(
                        tint: micButtonTint,
                        in: Circle(),
                        fallback: AnyShapeStyle(micButtonFallback),
                        interactive: true
                    )
            }
            .shadow(
                color: micButtonGlow,
                radius: viewModel.isListening ? 20 : 12,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canStartListening && !viewModel.isListening)
        .opacity(micButtonEnabled ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isListening)
        .animation(.easeInOut(duration: 0.3), value: micButtonEnabled)
        .accessibilityLabel(viewModel.isListening ? "Stop listening" : "Start listening")
    }

    private var micButtonEnabled: Bool {
        viewModel.canStartListening || viewModel.isListening
    }

    private var micButtonTint: Color? {
        guard micButtonEnabled else { return nil }
        return viewModel.isListening ? .red.opacity(0.3) : BrandPalette.cyan.opacity(0.22)
    }

    private var micButtonFallback: some ShapeStyle {
        if !micButtonEnabled {
            return AnyShapeStyle(Color.secondary.opacity(0.15))
        }
        if viewModel.isListening {
            return AnyShapeStyle(Color.red)
        }
        return AnyShapeStyle(BrandPalette.cyan.opacity(0.9))
    }

    private var micButtonGlow: Color {
        guard micButtonEnabled else { return .clear }
        return viewModel.isListening
            ? .red.opacity(0.4)
            : BrandPalette.cyan.opacity(0.3)
    }
}
