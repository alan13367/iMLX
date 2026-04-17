# AGENTS.md — iMLX Working Notes

## Project
`iMLX` is an on-device AI chat app for iOS/iPadOS built with SwiftUI and MLX Swift. It runs models locally on Apple Silicon with no required cloud backend.

## Use This File For
- Core architecture and safety constraints
- Build commands that work in this repo
- High-signal codebase orientation
- Project conventions that are easy to violate

Do not treat this file as a changelog. Prefer code as the source of truth for detailed UX, copy, and current model catalog contents.

## Quick Commands

### Build for simulator
```bash
xcodebuild build \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

### Build for device
```bash
xcodebuild build \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'generic/platform=iOS'
```

### Resolve packages
```bash
xcodebuild -resolvePackageDependencies \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX"
```

### Install Metal toolchain for CLI builds
```bash
xcodebuild -downloadComponent MetalToolchain
```

## Architecture

- App structure: SwiftUI + MVVM using `@Observable`
- Inference isolation: MLX work is serialized through `InferenceService` (`actor`)
- Streaming: actor inference streams tokens through `AsyncThrowingStream<String, Error>` into `@MainActor` view model state
- Shared app state: `AppState` owns shared services and persisted selection state
- Chat orchestration: `ChatViewModel` owns transcript state, send/generation flow, streaming UI state, attachments, persona selection, and save/update behavior
- Conversations: each generation rebuilds prompt/session state from visible conversation history rather than relying on hidden long-lived chat session state
- Persona system: each conversation binds to a `Persona`; persona selection changes prompting behavior but does not auto-load a different model
- Documents: local PDF/CSV/text files are imported, extracted, chunked, indexed, and retrieved locally through `DocumentLibraryService`
- Memory: compact user memories are stored locally through `MemorySystem`; ingestion is source-grounded and multilingual, evidence and lifecycle events are persisted in SQLite/GRDB, and bounded retrieval explanations are injected into prompt context when relevant
- Vision: vision-capable models must load through the VLM path, not the text-only loader
- TTS vendor boundary: `iMLX/Vendor/KokoroSwift` is a compatibility layer over downloaded Kokoro checkpoints; checkpoint-specific tensor normalization belongs in `WeightLoader.swift` and `QuantizedModuleFactory.swift`, not scattered through model code

## Important Constraints

1. MLX is not thread-safe. Do not perform MLX array/model work outside the inference actor.
2. Memory pressure is the main runtime constraint. Large models and long prompts can crash or be jetsammed on device.
3. SwiftPM CLI alone cannot compile the Metal pieces; use Xcode/Xcodebuild.
4. iOS Simulator cannot run MLX inference. Simulator builds are for UI/build verification only.
5. Inference is foreground-only. Do not design around background GPU execution.
6. Deployment target is iOS 18+.
7. The project currently uses `main` for `mlx-swift`, pins `mlx-swift-lm` to `3.31.3`, and links `swift-tokenizers-mlx` for local tokenizer loading with MLX Swift LM 3.x.
8. The Xcode target defaults actor isolation to `MainActor`, so pure helpers that run off the main actor may need explicit `nonisolated` annotations.
9. Memory extraction must only persist facts grounded in the user message. Do not turn assistant answers, recommendations, prices, or unquoted generated details into memories.
10. Current Kokoro checkpoints are not shape-compatible with the original vendor assumptions: many linear and embedding tensors are quantized (`U32` packed weights plus `scales`/`biases`), LSTM weights use newer key names, and conv/`weight_v` tensors already arrive in MLX-friendly layout. Do not blindly transpose or load them as dense tensors.

## Codebase Map

```text
iMLX/
├── App/          App entry and root navigation shell
├── Models/       App state and persisted data models
├── ViewModels/   Chat and model-management state
├── Views/        SwiftUI screens and components
├── Services/     Inference, downloads, persistence, memory, documents
├── Utilities/    Constants, localization, styling, helpers
└── Assets.xcassets/
```

High-value files:
- `iMLX/Models/AppState.swift`
- `iMLX/Models/UserMemory.swift`
- `iMLX/ViewModels/ChatViewModel.swift`
- `iMLX/Services/InferenceService.swift`
- `iMLX/Services/DocumentLibraryService.swift`
- `iMLX/Services/MemoryService.swift`
- `iMLX/Services/MemoryStore.swift`
- `iMLX/Services/MemoryDatabase.swift`
- `iMLX/Services/MemoryService+Extraction.swift`
- `iMLX/Services/MemoryService+Retrieval.swift`
- `iMLX/Services/MemoryService+Shared.swift`
- `iMLX/Services/MemorySupport.swift`
- `iMLX/Utilities/Constants.swift`

## Memory Architecture

- `MemoryService.swift` now defines `MemorySystem`, the app-facing facade used by `AppState` and chat flows. It owns legacy JSON import, relation blocking policy, and synchronous bridges into the actor-backed store/services.
- `MemoryStore.swift` is the persistence boundary (`actor`). It owns GRDB reads/writes, transactional inserts/updates, candidate generation, archive/status transitions, evidence/event loading, retrieval logging, and corruption recovery.
- `MemoryDatabase.swift` owns the normalized SQLite schema and migrations. The durable source of truth is now the `memory_item`, `memory_fact`, `memory_evidence`, `memory_event`, `memory_embedding_cache`, and `memory_fts` tables. The legacy `user_memory` table remains only for migration/backfill compatibility.
- `MemoryIngestionService` in `MemoryService.swift` orchestrates normalization, quote validation, duplicate detection, contradiction handling, and persistence of canonical memory rows plus evidence.
- `MemoryService+Extraction.swift` still parses structured LLM extraction output, normalizes candidates, validates source quotes, rejects unsupported memories, and handles legacy string outputs before they reach ingestion.
- `MemoryService+Retrieval.swift` owns archive/forget matching, candidate reranking, retrieval explanations, and trace generation. Candidate generation now starts from DB-bounded queries instead of a mutable whole-corpus cache.
- `MemoryService+Shared.swift` holds shared normalization, language detection, metadata cleanup, and Natural Language sentence embedding helpers.
- `MemorySupport.swift` contains local support types and algorithms: memory relations, fact signatures, multilingual tokenization, vector math, vector sketching, fact parsing, and vault indexing used for bounded reranking.
- `UserMemory` is now a UI-facing summary/projection model. Rich detail lives in `MemoryDetail`, `MemoryEvidence`, `MemoryEvent`, and `MemoryRetrievalExplanation`.
- New structured memories should prefer `factRelation` + `factValue` for deduplication and conflict handling. Every persisted memory should remain grounded in user text through at least one source quote.
- Retrieval should stay synchronous and local. Use FTS + typed fact lookup + bounded reranking rather than loading the entire corpus into a mutable in-memory index.

## Models and Personas

- Exact curated model entries live in `iMLX/Utilities/Constants.swift`
- Built-in personas are seeded by `PersonaService`
- If a task depends on exact model capabilities or IDs, read `Constants.swift` instead of duplicating assumptions from this file

## TTS Checkpoints

- The Kokoro compatibility boundary lives in `iMLX/Vendor/KokoroSwift/TTSEngine/WeightLoader.swift` and `iMLX/Vendor/KokoroSwift/BuildingBlocks/QuantizedModuleFactory.swift`.
- Newer Kokoro checkpoints may rename LSTM tensors (for example `Wx_forward`/`Wh_forward`) and store text/style/BERT layers as packed quantized weights with companion `scales` and `biases`.
- `predictor`, `text_encoder`, and `decoder` conv kernels in the current checkpoints already use the expected MLX layout. Extra transposes can silently corrupt kernel/channel axes and only fail later at runtime.
- If TTS crashes with MLX shape errors, inspect the loaded checkpoint tensor names and shapes first before changing model math. Most failures in this area come from loader assumptions, not the inference graph itself.

## Conventions

- Follow existing Swift 5.9+/SwiftUI style
- Use `@Observable` for view models, not `ObservableObject`
- Keep all UI state mutations on `@MainActor`
- Use `actor` for services that touch MLX or require serialized access
- Use `AsyncThrowingStream` for token streaming
- Avoid code comments unless they add real clarity
- Prefer updating existing architecture over introducing parallel patterns

## Updating This File

Only update `AGENTS.md` when one of these changes:
- build or dependency workflow
- architecture or ownership boundaries
- runtime constraints or safety assumptions
- top-level folder structure
- project conventions

Do not append minor UI tweaks, one-off bug fixes, or full feature histories here.
