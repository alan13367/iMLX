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

### Build tests for simulator
```bash
xcodebuild build-for-testing \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

### Run tool-calling tests
```bash
xcodebuild test-without-building \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:iMLXTests
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
- Tool calling: `ToolCallingService` is the generic planner/executor layer for model-driven tools; it plans with the currently loaded model, executes at most one tool per turn, and fails closed to local generation on invalid planner output
- Tool inputs: tool availability is current-turn-aware via `ToolInputContext` (latest message text, attached images, detected public URLs)
- Current tools: `read_url`, `ocr_image_text`, and `web_search`
- Tool gating: the Web Search toggle gates internet-dependent tools (`web_search` and `read_url`); local OCR remains available when the latest user message includes attached images
- Tool precedence: one tool call per turn, with deterministic preference for `read_url` over OCR/text extraction fallbacks over `web_search`
- Retrieval grounding: assistant source attribution can now come from document, web, or image/OCR results
- Persona system: each conversation binds to a `Persona`; persona selection changes prompting behavior but does not auto-load a different model
- Documents: local PDF/CSV/text files are imported, extracted, chunked, indexed, and retrieved locally through `DocumentLibraryService`
- Memory: compact user memories are stored locally through `MemorySystem`; ingestion is source-grounded and multilingual, evidence and lifecycle events are persisted in SQLite/GRDB, and bounded retrieval explanations are injected into prompt context when relevant
- Vision: vision-capable models must load through the VLM path, not the text-only loader
- OCR: attached-image text extraction is local and on-device via Vision (`ImageOCRService`); v1 only reads images attached on the current user message
- TTS vendor boundary: `iMLX/Vendor/KokoroSwift` is a compatibility layer over downloaded Kokoro checkpoints; checkpoint-specific tensor normalization belongs in `WeightLoader.swift` and `QuantizedModuleFactory.swift`, not scattered through model code

## Important Constraints

1. MLX is not thread-safe. Do not perform MLX array/model work outside the inference actor.
2. Memory pressure is the main runtime constraint. Large models and long prompts can crash or be jetsammed on device.
3. SwiftPM CLI alone cannot compile the Metal pieces; use Xcode/Xcodebuild.
4. iOS Simulator cannot run MLX inference. Simulator builds are for UI/build verification only.
5. Inference is foreground-only. Do not design around background GPU execution.
6. Deployment target is iOS 26+.
7. The project currently uses `main` for `mlx-swift`, pins `mlx-swift-lm` to `3.31.3`, and links `swift-tokenizers-mlx` for local tokenizer loading with MLX Swift LM 3.x.
8. The Xcode target defaults actor isolation to `MainActor`, so pure helpers that run off the main actor may need explicit `nonisolated` annotations.
9. Memory extraction must only persist facts grounded in the user message. Do not turn assistant answers, recommendations, prices, or unquoted generated details into memories.
10. Current Kokoro checkpoints are not shape-compatible with the original vendor assumptions: many linear and embedding tensors are quantized (`U32` packed weights plus `scales`/`biases`), LSTM weights use newer key names, and conv/`weight_v` tensors already arrive in MLX-friendly layout. Do not blindly transpose or load them as dense tensors.
11. Tool-calling planner output is intentionally treated as untrusted and brittle. Invalid or ambiguous planner output must degrade to `.none`, not to a guessed tool call, except for narrowly defined deterministic fallbacks already encoded in `ToolCallingService`.
12. Do not treat enabling Web Search as permission to always search. Search is now a tool decision, not a side effect of the toggle.
13. `read_url` and OCR are grounded only in the latest user turn in v1. Do not silently scrape older messages or attachments when planning/executing these tools.
14. `read_url` v1 is for a single public `http/https` URL in the latest message. Multiple URLs should force clarification instead of arbitrary selection.

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
- `iMLX/Models/ToolCallingModels.swift`
- `iMLX/Models/MessageSource.swift`
- `iMLX/ViewModels/ChatViewModel.swift`
- `iMLX/Services/InferenceService.swift`
- `iMLX/Services/DocumentLibraryService.swift`
- `iMLX/Services/ToolCallingService.swift`
- `iMLX/Services/WebSearchService.swift`
- `iMLX/Services/ImageOCRService.swift`
- `iMLX/Services/MemoryService.swift`
- `iMLX/Services/MemoryStore.swift`
- `iMLX/Services/MemoryDatabase.swift`
- `iMLX/Services/MemoryService+Extraction.swift`
- `iMLX/Services/MemoryService+Retrieval.swift`
- `iMLX/Services/MemoryService+Shared.swift`
- `iMLX/Services/MemorySupport.swift`
- `iMLX/Views/Chat/ChatView.swift`
- `iMLX/Utilities/Constants.swift`
- `iMLX/Localizable.xcstrings`
- `iMLXTests/ToolPlannerParsingTests.swift`
- `iMLXTests/ToolRegistryTests.swift`
- `iMLXTests/ToolExecutionTests.swift`

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
- Tool-planner behavior also depends on model characteristics. Thinking-tuned checkpoints may need deterministic fallbacks handled in app code rather than assuming strict JSON planner output compliance.

## Tool Calling Notes

- `ToolCallingService` owns tool registry, planner prompt construction, planner-output parsing, deterministic arbitration, timeout handling, and executor dispatch.
- The planner uses the currently loaded MLX model with a short deterministic generation budget. It is not a second model or a cloud fallback.
- Current registered tools:
  - `read_url`: reads one pasted public URL directly and is gated by the Web Search toggle because it requires network access
  - `ocr_image_text`: extracts text from images attached on the latest user message
  - `web_search`: live web retrieval, still gated by the conversation’s Web Search toggle
  - `document_synthesize`: retrieves excerpts from attached conversation documents
  - `calendar_brief`: reads local Calendar events for bounded private schedule briefs
  - `calendar_create`: creates one basic event in the default Calendar when title, concrete start, and concrete end/duration are present (EventKit; mutating)
  - `current_datetime`: reads local date, time, and timezone from the device clock (no permissions)
  - `reminders_brief`: reads incomplete local reminders for bounded private briefs
  - `reminders_create`: creates one reminder in the default Reminders list (EventKit; mutating)
  - `timer_create`: starts one native iOS 26 AlarmKit timer for an explicit duration (mutating)
  - `contacts_lookup`: reads matching local Contacts names plus phone/email handles only
- Deterministic arbitration currently prefers:
  1. `read_url` when the latest message contains exactly one supported public URL
  2. `document_synthesize` when attached documents and the message imply document Q&A or summary
  3. `ocr_image_text` for text-focused image requests when the planner returns `.none`
  4. `calendar_brief` for schedule-shaped requests when the planner returns `.none`
  5. `timer_create` for explicit “set/start a timer …” phrasing with a parseable duration
  6. `calendar_create` for explicit event creation when all required fields are parseable
  7. `contacts_lookup` for explicit local contact/phone/email lookups
  8. `reminders_create` for explicit “remind me to …” / “add a reminder …” phrasing (before `reminders_brief`)
  9. `current_datetime` for explicit current time/date questions
  7. `reminders_brief` for todo/reminder list requests
  8. `web_search` heuristics for obvious live-data requests when planner output fails on some thinking-oriented models
- Persisted tool traces are stored on assistant `ChatMessage`s. Backward compatibility matters because older conversation JSON may still decode `rewrittenQuery` instead of `displayInput`.

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
- Keep tool contracts generic and data-driven. New tools should add a `ToolDefinition`, executor, and context-aware enablement path rather than branching ad hoc in `ChatViewModel`
- Preserve backward-compatible decoding for persisted conversation models when adding fields to `ChatMessage`, `Conversation`, tool traces, or source types
- Keep tool results grounded and clipped before prompt injection; use source attribution rather than opaque assistant claims
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
