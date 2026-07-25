import SwiftUI
import UniformTypeIdentifiers

struct LLMProfilingView: View {
    @Bindable var appState: AppState
    @State private var copiedMessage: String?
    @State private var isExportingSessionJSON = false
    @State private var sessionExportDocument = LLMProfilingExportDocument()
    @State private var sessionExportFilename = "imlx-llm-profiling-session.json"
    @State private var benchmarkPrompt = "Write one short sentence about on-device AI."
    @State private var benchmarkIterations = 3
    @State private var isRunningBenchmark = false
    @State private var benchmarkErrorMessage: String?
    @State private var isImportingIFBenchJSONL = false
    @State private var ifBenchPrompts: [IFBenchPrompt] = []
    @State private var ifBenchMaxTokens = 1024
    @State private var isRunningIFBench = false
    @State private var ifBenchCompletedPrompts = 0
    @State private var ifBenchTotalPrompts = 0
    @State private var ifBenchErrorMessage: String?
    @State private var ifBenchExportDocument = LLMProfilingExportDocument()
    @State private var ifBenchExportFilename = "imlx-ifbench-responses.jsonl"
    @State private var isExportingIFBenchFile = false

    var body: some View {
        Form {
            if let profile = appState.latestLLMExecutionProfile {
                Section {
                    metricRow("Run", profile.runLabel)
                    metricRow("Model", profile.modelName)
                    if let modelId = profile.modelId {
                        metricRow("Model ID", modelId)
                    }
                    if let quantization = profile.quantization {
                        metricRow("Quantization", quantization)
                    }
                    metricRow("Max tokens", profile.maxTokens.map(String.init) ?? "n/a")
                    metricRow("Temperature", profile.temperature.map { String($0) } ?? "n/a")
                    metricRow("Total inference", LLMProfileFormatters.duration(profile.totalInferenceDuration))
                    metricRow("Time to first output", LLMProfileFormatters.duration(profile.timeToFirstGeneratedToken))
                    metricRow("Time to first text chunk", LLMProfileFormatters.duration(profile.timeToFirstOutputChunk))
                    metricRow("Input tokens", LLMProfileFormatters.integer(profile.inputTokenCount))
                    metricRow("Output tokens", LLMProfileFormatters.integer(profile.measuredOutputTokenCount))
                    metricRow("Output text chunks", LLMProfileFormatters.integer(profile.outputTextChunkCount))
                    metricRow("Output characters", LLMProfileFormatters.integer(profile.outputCharacterCount))
                    metricRow("Output token speed", LLMProfileFormatters.rate(profile.tokensPerSecond))
                    metricRow("Output character speed", LLMProfileFormatters.characterRate(profile.outputCharactersPerSecond))
                    metricRow("Memory before (footprint)", LLMProfileFormatters.memory(profile.memoryBeforeInference))
                    metricRow("Memory peak (footprint)", LLMProfileFormatters.memory(profile.memoryPeakDuringInference))
                    metricRow("Memory after (footprint)", LLMProfileFormatters.memory(profile.memoryAfterInference))
                    metricRow("Memory delta", LLMProfileFormatters.memoryDelta(profile.memoryDelta))
                    metricRow("Available at start", LLMProfileFormatters.memory(profile.memoryAvailableAtInferenceStart))
                    if let deviceRAM = profile.devicePhysicalMemoryGB {
                        metricRow("Device RAM", "\(deviceRAM) GB")
                    }
                    metricRow("Thermal before", profile.thermalStateBeforeInference ?? "n/a")
                    metricRow("Thermal after", profile.thermalStateAfterInference ?? "n/a")
                } header: {
                    Label("Latest Run", systemImage: "gauge.with.dots.needle.67percent")
                }

                Section {
                    metricRow("Model load", LLMProfileFormatters.duration(profile.modelLoadDuration))
                    metricRow("Tokenizer load", LLMProfileFormatters.duration(profile.tokenizerLoadDuration))
                    metricRow("Prompt construction", LLMProfileFormatters.duration(profile.promptConstructionDuration))
                    metricRow("Tokenization", LLMProfileFormatters.duration(profile.tokenizationDuration))
                    metricRow("Prefill / prompt eval", LLMProfileFormatters.duration(profile.prefillPromptEvaluationDuration))
                    metricRow("Decode", LLMProfileFormatters.duration(profile.decodeGenerationDuration))
                    metricRow("Total scope", "Inference service only")
                    metricRow("Battery before (coarse)", LLMProfileFormatters.battery(profile.batteryLevelBeforeInference))
                    metricRow("Battery after (coarse)", LLMProfileFormatters.battery(profile.batteryLevelAfterInference))
                    metricRow("Energy", "Indirect indicators only")
                    metricRow("Stop reason", profile.stopReason ?? "n/a")
                    if let errorInfo = profile.errorInfo {
                        metricRow("Error", errorInfo.message)
                    }
                } header: {
                    Label("Detailed Metrics", systemImage: "timer")
                }

                Section {
                    Button("Copy JSON") {
                        PlatformClipboard.copy(LLMExecutionProfileExport(profile).jsonString)
                        copiedMessage = "Copied JSON"
                    }
                    Button("Copy CSV Row") {
                        PlatformClipboard.copy(LLMExecutionProfile.csvHeader + "\n" + profile.csvRow)
                        copiedMessage = "Copied CSV"
                    }
                } header: {
                    Label("Latest Run Export", systemImage: "square.and.arrow.up")
                } footer: {
                    if let copiedMessage {
                        Text(copiedMessage)
                    }
                }

            } else {
                Section {
                    ContentUnavailableView(
                        "No Profile Yet",
                        systemImage: "gauge.with.dots.needle.0percent",
                        description: Text("Run local generation once, then return here.")
                    )
                }
            }

            Section {
                metricRow("Saved sessions", appState.llmProfilingSessions.count.formatted())
                metricRow("Saved profiles", appState.llmExecutionProfiles.count.formatted())
                ForEach(appState.llmProfilingSessions) { session in
                    sessionRow(session)
                }
            } header: {
                Label("Profiling Sessions", systemImage: "clock.arrow.circlepath")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let copiedMessage {
                        Text(copiedMessage)
                    }
                    Text("Each app launch/debug run is saved as its own timestamped session. Measurement notes and limitations are included once per session export, not repeated on every profile.")
                }
            }

            Section {
                TextField("Benchmark prompt", text: $benchmarkPrompt, axis: .vertical)
                    .lineLimit(2...4)
                Stepper(value: $benchmarkIterations, in: 1...10) {
                    Text("Iterations: \(benchmarkIterations)")
                }
                Button {
                    Task {
                        await runBenchmark()
                    }
                } label: {
                    if isRunningBenchmark {
                        Label("Running Benchmark…", systemImage: "hourglass")
                    } else {
                        Label("Run Benchmark", systemImage: "play.fill")
                    }
                }
                .disabled(isRunningBenchmark || !canRunBenchmark)
                if let benchmarkErrorMessage {
                    Text(benchmarkErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Label("Benchmark", systemImage: "chart.xyaxis.line")
            } footer: {
                Text("Runs repeated local generation with an empty system prompt. Load a model before starting. Exports omit the raw prompt text.")
            }

            if let benchmark = appState.latestLLMBenchmarkResult {
                Section {
                    metricRow("Iterations", benchmark.iterations.formatted())
                    metricRow("Prompt size", "\(benchmark.prompt.count.formatted()) characters")
                    metricRow("Mean total", LLMProfileFormatters.duration(benchmark.totalInferenceTime?.mean))
                    metricRow("Median first output", LLMProfileFormatters.duration(benchmark.timeToFirstToken?.median))
                    metricRow("Mean tokens/sec", LLMProfileFormatters.rate(benchmark.tokensPerSecond?.mean))
                    metricRow("Mean characters/sec", LLMProfileFormatters.characterRate(benchmark.charactersPerSecond?.mean))
                    metricRow("Mean memory delta", benchmarkMemoryDelta(benchmark.memoryDelta))
                    Button("Copy Benchmark JSON") {
                        PlatformClipboard.copy(LLMBenchmarkResultExport(benchmark).jsonString)
                        copiedMessage = "Copied benchmark JSON"
                    }
                } header: {
                    Label("Latest Benchmark", systemImage: "chart.xyaxis.line")
                }
            }

            Section {
                Button {
                    isImportingIFBenchJSONL = true
                } label: {
                    Label("Import IFBench JSONL", systemImage: "doc.badge.plus")
                }
                if !ifBenchPrompts.isEmpty {
                    metricRow("Loaded prompts", ifBenchPrompts.count.formatted())
                    Stepper(value: $ifBenchMaxTokens, in: 128...4096, step: 128) {
                        Text("Max tokens: \(ifBenchMaxTokens)")
                    }
                    Button {
                        Task {
                            await runIFBench()
                        }
                    } label: {
                        if isRunningIFBench {
                            Label("Running IFBench…", systemImage: "hourglass")
                        } else {
                            Label("Run IFBench", systemImage: "play.fill")
                        }
                    }
                    .disabled(isRunningIFBench || !canRunBenchmark)
                }
                if isRunningIFBench {
                    ProgressView(
                        value: Double(ifBenchCompletedPrompts),
                        total: Double(max(ifBenchTotalPrompts, 1))
                    )
                    Text("Completed \(ifBenchCompletedPrompts.formatted()) of \(ifBenchTotalPrompts.formatted()) prompts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let ifBenchErrorMessage {
                    Text(ifBenchErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Label("IFBench", systemImage: "checklist.checked")
            } footer: {
                Text("Imports the official IFBench test JSONL, runs every loaded prompt on-device at temperature 0, and exports response JSONL for the AllenAI evaluator.")
            }

            if let ifBench = appState.latestIFBenchRunResult {
                Section {
                    metricRow("Model", ifBench.modelName)
                    metricRow("Prompts", ifBench.promptCount.formatted())
                    metricRow("Mean total", LLMProfileFormatters.duration(ifBench.totalInferenceTime?.mean))
                    metricRow("Median first output", LLMProfileFormatters.duration(ifBench.timeToFirstToken?.median))
                    metricRow("Mean tokens/sec", LLMProfileFormatters.rate(ifBench.tokensPerSecond?.mean))
                    metricRow("Mean memory peak", benchmarkMemory(ifBench.memoryPeakDuringInference))
                    Button("Copy Responses JSONL") {
                        PlatformClipboard.copy(ifBench.officialResponsesJSONL)
                        copiedMessage = "Copied IFBench responses"
                    }
                    Button("Save Responses JSONL") {
                        prepareIFBenchExport(
                            text: ifBench.officialResponsesJSONL,
                            filename: "imlx-ifbench-\(ifBench.modelName.fileSafeName)-responses.jsonl"
                        )
                    }
                    Button("Save Run JSON") {
                        prepareIFBenchExport(
                            text: ifBench.jsonString,
                            filename: "imlx-ifbench-\(ifBench.modelName.fileSafeName)-run.json"
                        )
                    }
                } header: {
                    Label("Latest IFBench Run", systemImage: "checklist.checked")
                }
            }
        }
        .navigationTitle("LLM Profiling")
        .toolbar {
            ToolbarItem(placement: .imlxTrailing) {
                Button {
                    Task {
                        await appState.refreshLLMExecutionProfiles()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .fileExporter(
            isPresented: $isExportingSessionJSON,
            document: sessionExportDocument,
            contentType: .json,
            defaultFilename: sessionExportFilename
        ) { result in
            switch result {
            case .success:
                copiedMessage = "Saved session JSON"
            case .failure(let error):
                copiedMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isImportingIFBenchJSONL,
            allowedContentTypes: Self.ifBenchImportTypes,
            allowsMultipleSelection: false
        ) { result in
            importIFBenchJSONL(result)
        }
        .fileExporter(
            isPresented: $isExportingIFBenchFile,
            document: ifBenchExportDocument,
            contentType: ifBenchExportFilename.hasSuffix(".jsonl") ? .plainText : .json,
            defaultFilename: ifBenchExportFilename
        ) { result in
            switch result {
            case .success:
                copiedMessage = "Saved IFBench export"
            case .failure(let error):
                copiedMessage = "IFBench export failed: \(error.localizedDescription)"
            }
        }
        .task {
            await appState.refreshLLMExecutionProfiles()
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func benchmarkMemoryDelta(_ summary: LLMBenchmarkMetricSummary?) -> String {
        guard let summary else {
            return "n/a"
        }
        return LLMProfileFormatters.memoryDelta(Int64(summary.mean))
    }

    private func benchmarkMemory(_ summary: LLMBenchmarkMetricSummary?) -> String {
        guard let summary else {
            return "n/a"
        }
        return LLMProfileFormatters.memory(UInt64(summary.mean))
    }

    private func sessionRow(_ session: LLMProfilingSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(session.profiles.count.formatted()) runs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(sessionSummary(session))
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.crashReports.isEmpty == false {
                Label("\(session.crashReports.count.formatted()) recovered interruption(s)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button {
                    Task {
                        await prepareSessionJSONExport(session)
                    }
                } label: {
                    Label("Save JSON", systemImage: "square.and.arrow.down")
                }
                Spacer()
                Button("Copy JSON") {
                    Task {
                        await copySessionJSON(session)
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    Task {
                        await deleteSession(session)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(session.activeSnapshot != nil)
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
        .padding(.vertical, 2)
    }

    private func sessionSummary(_ session: LLMProfilingSessionRecord) -> String {
        let profileText = "\(session.profiles.count.formatted()) profile(s)"
        let latestProfile = session.profiles.last
        let latestModel = latestProfile?.modelName ?? "No completed model run"
        let updated = session.updatedAt.formatted(date: .omitted, time: .shortened)
        if let snapshot = session.activeSnapshot {
            return "\(profileText) - active stage: \(snapshot.stage) - \(latestModel) - updated \(updated)"
        }
        return "\(profileText) - \(latestModel) - updated \(updated)"
    }

    @MainActor
    private func prepareSessionJSONExport(_ session: LLMProfilingSessionRecord) async {
        await appState.refreshLLMExecutionProfiles()
        guard let export = appState.makeLLMProfilingSessionExport(for: session.id) else { return }
        sessionExportDocument = LLMProfilingExportDocument(text: export.jsonString)
        sessionExportFilename = "imlx-llm-profiling-session-\(Self.exportTimestamp(from: export.session.startedAt)).json"
        isExportingSessionJSON = true
    }

    @MainActor
    private func copySessionJSON(_ session: LLMProfilingSessionRecord) async {
        await appState.refreshLLMExecutionProfiles()
        guard let export = appState.makeLLMProfilingSessionExport(for: session.id) else { return }
        PlatformClipboard.copy(export.jsonString)
        copiedMessage = "Copied session JSON"
    }

    @MainActor
    private func deleteSession(_ session: LLMProfilingSessionRecord) async {
        await appState.deleteLLMProfilingSession(id: session.id)
        copiedMessage = "Deleted profiling session"
    }

    private static func exportTimestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }

    private static var ifBenchImportTypes: [UTType] {
        [
            UTType(filenameExtension: "jsonl") ?? .plainText,
            .json,
            .plainText,
            .data
        ]
    }

    private var canRunBenchmark: Bool {
        appState.loadedModelId != nil
    }

    @MainActor
    private func runBenchmark() async {
        benchmarkErrorMessage = nil
        guard canRunBenchmark else {
            benchmarkErrorMessage = "Load a model before running a benchmark."
            return
        }

        isRunningBenchmark = true
        defer { isRunningBenchmark = false }

        do {
            try await appState.runLLMBenchmark(
                prompt: benchmarkPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                iterations: benchmarkIterations
            )
            await appState.refreshLLMExecutionProfiles()
            copiedMessage = "Benchmark finished"
        } catch {
            benchmarkErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importIFBenchJSONL(_ result: Result<[URL], Error>) {
        ifBenchErrorMessage = nil
        do {
            guard let url = try result.get().first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                ifBenchErrorMessage = "The selected file is not valid UTF-8 text."
                return
            }
            let prompts = try IFBenchPrompt.decodeJSONL(text)
            ifBenchPrompts = prompts
            ifBenchCompletedPrompts = 0
            ifBenchTotalPrompts = 0
            copiedMessage = "Imported IFBench JSONL"
        } catch {
            ifBenchErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func prepareIFBenchExport(text: String, filename: String) {
        ifBenchExportDocument = LLMProfilingExportDocument(text: text)
        ifBenchExportFilename = filename
        isExportingIFBenchFile = true
    }

    @MainActor
    private func runIFBench() async {
        ifBenchErrorMessage = nil
        guard canRunBenchmark else {
            ifBenchErrorMessage = "Load a model before running IFBench."
            return
        }
        guard !ifBenchPrompts.isEmpty else {
            ifBenchErrorMessage = "Import IFBench_test.jsonl before running IFBench."
            return
        }

        ifBenchCompletedPrompts = 0
        ifBenchTotalPrompts = ifBenchPrompts.count
        isRunningIFBench = true
        defer { isRunningIFBench = false }

        do {
            try await appState.runIFBench(
                prompts: ifBenchPrompts,
                maxTokens: ifBenchMaxTokens,
                progress: { completedPrompts, totalPrompts in
                    ifBenchCompletedPrompts = completedPrompts
                    ifBenchTotalPrompts = totalPrompts
                }
            )
            await appState.refreshLLMExecutionProfiles()
            copiedMessage = "IFBench finished"
        } catch {
            ifBenchErrorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var fileSafeName: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        .joined()
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        .lowercased()
    }
}
