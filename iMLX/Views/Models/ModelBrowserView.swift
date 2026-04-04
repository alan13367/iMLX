import SwiftUI

struct ModelBrowserView: View {
    @State private var viewModel: ModelManagerViewModel
    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        self._viewModel = State(initialValue: ModelManagerViewModel(appState: appState))
    }

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    errorRow(message: error)
                }
            }

            if !viewModel.downloadableModels.isEmpty {
                Section(String.appLocalized("models.section.available")) {
                    ForEach(viewModel.downloadableModels) { model in
                        ModelCardView(
                            model: model,
                            progress: viewModel.downloadProgress[model.id] ?? 0,
                            isDownloading: viewModel.isDownloading[model.id] ?? false,
                            isSelected: appState.loadedModelId == model.id,
                            onDownload: {
                                viewModel.errorMessage = nil
                                viewModel.download(model: model)
                            },
                            onDelete: { viewModel.delete(model: model) }
                        )
                    }
                }
            }
            if !viewModel.incompatibleModels.isEmpty {
                Section(String.appLocalized("models.section.low_memory")) {
                    ForEach(viewModel.incompatibleModels) { model in
                        ModelCardView(
                            model: model,
                            progress: 0,
                            isDownloading: false,
                            isSelected: false,
                            onDownload: {},
                            onDelete: {}
                        )
                        .dimmed(true)
                    }
                }
            }
        }
        .navigationTitle(String.appLocalized("models.browser.title"))
        .task {
            viewModel.refreshDownloadStatusFromDisk()
        }
    }

    private func errorRow(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.vertical, 4)
    }
}

private extension View {
    func dimmed(_ dimmed: Bool) -> some View {
        self.opacity(dimmed ? 0.4 : 1.0)
    }
}
