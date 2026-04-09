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
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("Live Voice")
                        .font(.largeTitle.weight(.bold))
                    Text(viewModel.statusText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                VStack(spacing: 16) {
                    if !viewModel.lastUserTranscript.isEmpty {
                        transcriptCard(title: "You said", body: viewModel.lastUserTranscript)
                    }

                    if !viewModel.partialTranscript.isEmpty {
                        transcriptCard(title: "Listening", body: viewModel.partialTranscript)
                    }

                    if let unavailableReason = viewModel.unavailableReason {
                        transcriptCard(title: "Unavailable", body: unavailableReason)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        transcriptCard(title: "Issue", body: errorMessage)
                    }

                    if viewModel.needsAssetDownload && viewModel.unavailableReason == nil {
                        VStack(spacing: 12) {
                            Text("This downloads Kokoro voice assets for \(viewModel.voiceLocale.displayName) before live voice starts.")
                                .font(.body)
                                .multilineTextAlignment(.center)
                            Button {
                                Task {
                                    await viewModel.downloadAssets()
                                }
                            } label: {
                                if viewModel.isPreparingAssets {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Download Voice Assets")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isPreparingAssets)
                        }
                        .padding(20)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                }

                Spacer()

                Button {
                    Task {
                        await viewModel.toggleListening()
                    }
                } label: {
                    Image(systemName: viewModel.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 92, height: 92)
                        .background(viewModel.isListening ? Color.red : BrandPalette.accent, in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canStartListening && !viewModel.isListening)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        Task {
                            await viewModel.close()
                            dismiss()
                        }
                    }
                }
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

    private func transcriptCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
