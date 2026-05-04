# AGENTS.md — iMLX Working Notes

## Purpose

`iMLX` is an on-device AI chat app for iOS/iPadOS built with SwiftUI and MLX Swift. It runs local models on Apple Silicon with no required cloud backend.

Use this file for build commands, architecture boundaries, runtime constraints, and repo orientation. Do not use it as a changelog; source files are the authority for UX copy, exact model catalog entries, and feature details.

## Quick Commands

```bash
# Simulator build: UI/build verification only; simulator cannot run MLX inference.
xcodebuild build \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# Device build.
xcodebuild build \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'generic/platform=iOS'

# Resolve packages.
xcodebuild -resolvePackageDependencies \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX"

# Build tests, then run the app test bundle.
xcodebuild build-for-testing \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

xcodebuild test-without-building \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:iMLXTests

# Needed if CLI/Xcode builds complain about Metal pieces.
xcodebuild -downloadComponent MetalToolchain
```

## Non-Negotiable Constraints

1. MLX is not thread-safe. All MLX array/model work belongs inside the `InferenceService` actor or another explicit serialized boundary.
2. Memory pressure is the dominant runtime risk. Large models, long prompts, and unbounded retrieval context can jetsam the app.
3. SwiftPM CLI alone cannot compile the Metal pieces; use Xcode/Xcodebuild.
4. iOS Simulator cannot run MLX inference, AlarmKit scheduling, or Live Activities. Use it for builds/UI only; use a physical device for those features.
5. Inference is foreground-only. Do not design around background GPU execution.
6. Deployment target is iOS 26+.
7. The project uses `mlx-swift` from `main`, pins `mlx-swift-lm` to `3.31.3`, and uses `swift-tokenizers-mlx` for local tokenizer loading.
8. The Xcode target defaults actor isolation to `MainActor`; pure off-main helpers may need explicit `nonisolated`.
9. Persisted chat/conversation/tool/source models require backward-compatible decoding.
10. Do not add parallel architecture when an existing service boundary fits.

## Architecture

- App state: `AppState` owns shared services, model and conversation selection, assistant generation settings (system prompt and temperature), and persisted app-level state.
- Chat orchestration: `ChatViewModel` owns transcript state, send/generation flow, streaming UI state, attachments, tool traces, and save/update behavior.
- Inference: `InferenceService` is an actor; it loads models and streams tokens via `AsyncThrowingStream<String, Error>` into `@MainActor` UI state.
- Prompt/session policy: every generation rebuilds prompt/session state from visible conversation history instead of relying on hidden long-lived chat state.
- UI: SwiftUI + `@Observable`. Root chat orchestration lives in `ChatView`; extracted chat UI lives under `iMLX/Views/Chat/Components`.
- Models: curated model entries live in `Constants.swift`. Assistant defaults (system prompt, temperature) live in `AppState` and are edited in `AssistantSettingsView`.
- Documents: `DocumentLibraryService` imports local PDF/CSV/text files, extracts/chunks/indexes them, and retrieves bounded local context.
- Memory: `MemorySystem` is the app-facing facade over actor-backed GRDB persistence and retrieval. Persist only facts grounded in user text.
- Tool calling: `ToolCallingService` plans with the currently loaded local model, executes at most one tool per turn, and fails closed to normal generation on invalid planner output.
- Vision/OCR: vision-capable models must load through the VLM path. OCR is local via Vision and only reads images attached to the latest user turn in v1.
- TTS: Kokoro checkpoint compatibility belongs in `Vendor/KokoroSwift` loader/factory code, not scattered through model math.

## Codebase Map

```text
iMLX/
├── App/                  App entry and root navigation shell
├── Models/               App state and persisted data models
├── ViewModels/           Chat and model-management state
├── Views/                SwiftUI screens and components
│   └── Chat/
│       ├── ChatView.swift Root chat shell, toolbar, sheets, and orchestration
│       └── Components/    Transcript, composer, status, attachments, messages
├── Services/             Inference, downloads, persistence, memory, documents, tools
├── Utilities/            Constants, localization, styling, helpers
└── Assets.xcassets/
iMLXAlarmWidget/          Widget Extension for AlarmKit timer Live Activity
iMLXInfo.plist            Main app Info.plist for keys Xcode will not auto-inject
iMLXAlarmWidgetInfo.plist Widget extension Info.plist
```

High-value files and folders:

- `iMLX/Models/AppState.swift`
- `iMLX/Views/Settings/AssistantSettingsView.swift`
- `iMLX/Models/ToolCallingModels.swift`
- `iMLX/Models/MessageSource.swift`
- `iMLX/Models/UserMemory.swift`
- `iMLX/ViewModels/ChatViewModel.swift`
- `iMLX/Services/InferenceService.swift`
- `iMLX/Services/ToolCallingService.swift`
- `iMLX/Services/WebSearchService.swift`
- `iMLX/Services/ImageOCRService.swift`
- `iMLX/Services/DocumentLibraryService.swift`
- `iMLX/Services/MemoryService*.swift`
- `iMLX/Services/MemoryStore.swift`
- `iMLX/Services/MemoryDatabase.swift`
- `iMLX/Services/MemorySupport.swift`
- `iMLX/Services/TimerService.swift`
- `iMLX/Services/IMLXTimerMetadata.swift`
- `iMLX/Views/Chat/ChatView.swift`
- `iMLX/Views/Chat/Components/`
- `iMLX/Utilities/Constants.swift`
- `iMLX/Localizable.xcstrings`
- `iMLXAlarmWidget/IMLXAlarmWidgetBundle.swift`
- `iMLXAlarmWidget/IMLXAlarmLiveActivity.swift`
- `iMLXTests/ToolPlannerParsingTests.swift`
- `iMLXTests/ToolRegistryTests.swift`
- `iMLXTests/ToolExecutionTests.swift`

## Tool Calling Rules

Registered tools include `read_url`, `ocr_image_text`, `web_search`, `document_synthesize`, Calendar/Reminders read/create tools, `current_datetime`, `timer_create`, and `contacts_lookup`.

Important behavior:

- Planner output is untrusted. Invalid or ambiguous output must degrade to `.none`, except for deterministic fallbacks already encoded in `ToolCallingService`.
- Enabling Web Search is permission to make internet tools available, not permission to always search. Search remains a tool decision.
- `web_search` and `read_url` are gated by the Web Search toggle; local OCR can run when the latest user message has attached images.
- `read_url` v1 supports exactly one public `http/https` URL in the latest user message. Multiple URLs should force clarification, not arbitrary selection.
- OCR and `read_url` are grounded only in the latest user turn in v1. Do not silently scrape older messages or attachments.
- Retrieval results must be clipped, grounded, and source-attributed before prompt injection.
- Tool traces are stored on assistant `ChatMessage`s; keep older `rewrittenQuery` decoding compatible with newer `displayInput`.

## Memory Rules

- Persisted memories must be grounded in user-provided text with source quotes. Never store facts from assistant answers, generated recommendations, prices, or unquoted inferred details.
- Prefer structured `factRelation` + `factValue` for deduplication and contradiction handling.
- `MemoryStore` is the GRDB actor/persistence boundary; `MemoryDatabase` owns schema/migrations; `MemoryService+Extraction/Retrieval/Shared` split extraction, retrieval, and shared normalization.
- Retrieval should remain synchronous and local: use FTS + typed fact lookup + bounded reranking, not a mutable whole-corpus in-memory index.
- `UserMemory` is a UI projection. Rich detail lives in `MemoryDetail`, `MemoryEvidence`, `MemoryEvent`, and retrieval explanation types.

## AlarmKit / Timer Tool

`timer_create` runs through `TimerService` and `AlarmManager.shared`. AlarmKit failures often surface as opaque `com.apple.AlarmKit.Alarm` code 1 errors, so preserve these requirements:

1. `NSAlarmKitUsageDescription` must be in the built runtime `Info.plist`. Xcode 26.4 does not auto-inject it from `INFOPLIST_KEY_*`; keep it in `iMLXInfo.plist`.
2. `NSSupportsLiveActivities = YES` must be present.
3. The embedded `iMLXAlarmWidgetExtension` must register `ActivityConfiguration(for: AlarmAttributes<IMLXTimerMetadata>.self)`.
4. Use `AlarmManager.AlarmConfiguration.timer(duration:attributes:)`, not the generic `countdownDuration` initializer.
5. `IMLXTimerMetadata.swift` is shared with the widget target via a `PBXFileSystemSynchronizedBuildFileExceptionSet`.
6. Keep `iMLXAlarmWidgetInfo.plist` outside the synchronized widget folder so Xcode does not process it as both Info.plist and resource.
7. On device, fully delete the app before reinstalling after AlarmKit/widget metadata changes; AlarmKit can cache stale `AlarmAttributes` registrations.
8. Treat non-`.maximumLimitReached` AlarmKit errors as generic `NSError`s and surface domain/code/userInfo; do not map by `code == 1`.

## TTS Checkpoints

- Kokoro compatibility lives in `iMLX/Vendor/KokoroSwift/TTSEngine/WeightLoader.swift` and `iMLX/Vendor/KokoroSwift/BuildingBlocks/QuantizedModuleFactory.swift`.
- Current checkpoints may store linear/embedding tensors as packed quantized `U32` weights plus `scales`/`biases`, and may use newer LSTM key names such as `Wx_forward`/`Wh_forward`.
- Predictor/text encoder/decoder conv kernels and `weight_v` tensors already arrive in MLX-friendly layout. Do not blindly transpose or densify.
- If TTS hits MLX shape errors, inspect loaded tensor names/shapes before changing graph math.

## Coding Conventions

- Follow existing Swift 5.9+/SwiftUI style.
- Use `@Observable` for view models, not `ObservableObject`.
- Keep UI mutations on `@MainActor`.
- Use `actor` for MLX or other serialized service boundaries.
- Use `AsyncThrowingStream` for token streaming.
- Add new tools through `ToolDefinition`, executor, and context-aware enablement, not ad hoc `ChatViewModel` branches.
- Preserve backward-compatible decoding for persisted conversations, messages, tool traces, source types, and memory records.
- Prefer source attribution over opaque assistant claims.
- Avoid comments unless they clarify non-obvious code.

## Updating This File

Update `AGENTS.md` only when build/dependency workflow, architecture boundaries, runtime constraints, top-level structure, or project conventions change. Do not append minor UI tweaks, one-off bug fixes, or feature history.
