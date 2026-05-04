import SwiftUI

struct LiveVoiceConversationView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState
    @State private var viewModel: LiveVoiceSessionViewModel
    @State private var hapticLightTrigger = 0
    @State private var hapticMediumTrigger = 0

    init(appState: AppState, chatViewModel: ChatViewModel) {
        self.appState = appState
        _viewModel = State(initialValue: LiveVoiceSessionViewModel(appState: appState, chatViewModel: chatViewModel))
    }

    var body: some View {
        ZStack {
            LiveVoiceBackground()

            VStack(spacing: 0) {
                LiveVoiceHeaderBar(
                    voiceLocaleName: viewModel.voiceLocale.displayName,
                    onClose: close
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 12)

                VoiceOrbView(state: viewModel.orbState, size: 200)
                    .padding(.bottom, 8)

                LiveVoiceStatusLabel(statusText: viewModel.statusText)
                    .padding(.bottom, 20)

                LiveVoiceTranscriptArea(
                    lastUserTranscript: viewModel.lastUserTranscript,
                    partialTranscript: viewModel.partialTranscript,
                    unavailableReason: viewModel.unavailableReason,
                    memoryWarningMessage: viewModel.memoryWarningMessage,
                    errorMessage: viewModel.errorMessage,
                    needsAssetDownload: viewModel.needsAssetDownload,
                    showAssetDownloadCard: viewModel.unavailableReason == nil,
                    voiceLocaleName: viewModel.voiceLocale.displayName,
                    isPreparingAssets: viewModel.isPreparingAssets,
                    onDownloadAssets: downloadAssets
                )
                .padding(.horizontal, 20)

                Spacer(minLength: 20)

                LiveVoiceMicButton(
                    isListening: viewModel.isListening,
                    isSpeaking: viewModel.isSpeaking,
                    isEnabled: micButtonEnabled,
                    onTap: primaryControlTap
                )
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
        .sensoryFeedback(.impact(weight: .light), trigger: hapticLightTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticMediumTrigger)
    }

    private var micButtonEnabled: Bool {
        viewModel.canStartListening || viewModel.isListening || viewModel.canStopSpeaking
    }

    private func close() {
        hapticLightTrigger += 1
        Task {
            await viewModel.close()
            dismiss()
        }
    }

    private func downloadAssets() {
        hapticMediumTrigger += 1
        Task {
            await viewModel.downloadAssets()
        }
    }

    private func primaryControlTap() {
        hapticMediumTrigger += 1
        Task {
            if viewModel.isSpeaking, viewModel.canStopSpeaking {
                await viewModel.stopSpeaking()
            } else {
                await viewModel.toggleListening()
            }
        }
    }
}

private struct LiveVoiceBackground: View {
    var body: some View {
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
}

private struct LiveVoiceHeaderBar: View {
    let voiceLocaleName: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(voiceLocaleName)
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

            Button(action: onClose) {
                CloseButtonLabel(foregroundStyle: .white.opacity(0.72))
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
}

private struct LiveVoiceStatusLabel: View {
    let statusText: String

    var body: some View {
        Text(statusText)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .animation(.easeInOut(duration: 0.3), value: statusText)
    }
}

private struct LiveVoiceTranscriptArea: View {
    let lastUserTranscript: String
    let partialTranscript: String
    let unavailableReason: String?
    let memoryWarningMessage: String?
    let errorMessage: String?
    let needsAssetDownload: Bool
    let showAssetDownloadCard: Bool
    let voiceLocaleName: String
    let isPreparingAssets: Bool
    let onDownloadAssets: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !lastUserTranscript.isEmpty {
                    LiveVoiceTranscriptCard(
                        title: String.appLocalized("voice.you_said"),
                        text: lastUserTranscript,
                        titleColor: BrandPalette.accent.opacity(0.8),
                        textColor: .white,
                        alignment: .trailing,
                        horizontalSpacer: 48,
                        tint: BrandPalette.accent.opacity(0.14)
                    )
                }

                if !partialTranscript.isEmpty {
                    LiveVoiceTranscriptCard(
                        title: String.appLocalized("voice.listening"),
                        text: partialTranscript,
                        titleColor: BrandPalette.cyan.opacity(0.8),
                        textColor: .white.opacity(0.85),
                        alignment: .leading,
                        horizontalSpacer: 48,
                        tint: BrandPalette.cyan.opacity(0.12)
                    )
                }

                if let unavailableReason {
                    LiveVoiceNoticeCard(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        bodyText: unavailableReason
                    )
                }

                if let memoryWarningMessage {
                    LiveVoiceNoticeCard(
                        icon: "memorychip.fill",
                        tint: BrandPalette.cyan,
                        bodyText: memoryWarningMessage
                    )
                }

                if let errorMessage {
                    LiveVoiceNoticeCard(
                        icon: "exclamationmark.circle.fill",
                        tint: .red,
                        bodyText: errorMessage
                    )
                }

                if needsAssetDownload && showAssetDownloadCard {
                    LiveVoiceAssetDownloadCard(
                        voiceLocaleName: voiceLocaleName,
                        isPreparingAssets: isPreparingAssets,
                        onDownloadAssets: onDownloadAssets
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct LiveVoiceTranscriptCard: View {
    let title: String
    let text: String
    let titleColor: Color
    let textColor: Color
    let alignment: HorizontalAlignment
    let horizontalSpacer: CGFloat
    let tint: Color

    private var isTrailing: Bool {
        alignment == .trailing
    }

    var body: some View {
        HStack {
            if isTrailing {
                Spacer(minLength: horizontalSpacer)
            }

            VStack(alignment: alignment, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(titleColor)
                Text(text)
                    .font(.body)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(isTrailing ? .trailing : .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .liquidGlassSurface(
                tint: tint,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                fallback: AnyShapeStyle(.ultraThinMaterial)
            )

            if !isTrailing {
                Spacer(minLength: horizontalSpacer)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: isTrailing ? .trailing : .leading).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

private struct LiveVoiceNoticeCard: View {
    let icon: String
    let tint: Color
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
            Text(bodyText)
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
}

private struct LiveVoiceAssetDownloadCard: View {
    let voiceLocaleName: String
    let isPreparingAssets: Bool
    let onDownloadAssets: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(String(format: String.appLocalized("voice.download_body"), voiceLocaleName))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button(action: onDownloadAssets) {
                Group {
                    if isPreparingAssets {
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
            .disabled(isPreparingAssets)
        }
        .padding(20)
        .liquidGlassSurface(
            tint: BrandPalette.accent.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            fallback: AnyShapeStyle(.ultraThinMaterial)
        )
    }
}

private struct LiveVoiceMicButton: View {
    let isListening: Bool
    let isSpeaking: Bool
    let isEnabled: Bool
    let onTap: () -> Void

    /// Red “stop” affordance when recording or when TTS is playing (tap stops that activity).
    private var isStopMode: Bool {
        isListening || isSpeaking
    }

    private var accessibilityLabel: String {
        if isListening {
            return String.appLocalized("voice.stop_listening")
        }
        if isSpeaking {
            return String.appLocalized("voice.stop_speaking")
        }
        return String.appLocalized("voice.start_listening")
    }

    private var tint: Color? {
        guard isEnabled else { return nil }
        return isStopMode ? .red.opacity(0.3) : BrandPalette.cyan.opacity(0.22)
    }

    private var fallback: some ShapeStyle {
        if !isEnabled {
            return AnyShapeStyle(Color.secondary.opacity(0.15))
        }
        if isStopMode {
            return AnyShapeStyle(Color.red)
        }
        return AnyShapeStyle(BrandPalette.cyan.opacity(0.9))
    }

    private var glow: Color {
        guard isEnabled else { return .clear }
        return isStopMode ? .red.opacity(0.4) : BrandPalette.cyan.opacity(0.3)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isStopMode {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 108, height: 108)

                    Circle()
                        .stroke(Color.red.opacity(0.25), lineWidth: 2)
                        .frame(width: 108, height: 108)
                }

                Image(systemName: isStopMode ? "stop.fill" : "mic.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .liquidGlassSurface(
                        tint: tint,
                        in: Circle(),
                        fallback: AnyShapeStyle(fallback),
                        interactive: isEnabled
                    )
            }
            .shadow(color: glow, radius: isStopMode ? 20 : 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.3), value: isStopMode)
        .animation(.easeInOut(duration: 0.3), value: isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("Voice Notice Card") {
    ZStack {
        LiveVoiceBackground()
        LiveVoiceNoticeCard(
            icon: "memorychip.fill",
            tint: BrandPalette.cyan,
            bodyText: "Voice mode may pause if available memory drops too low."
        )
        .padding()
    }
}

#Preview("Voice Mic Button") {
    ZStack {
        LiveVoiceBackground()
        LiveVoiceMicButton(isListening: false, isSpeaking: false, isEnabled: true, onTap: {})
    }
}
