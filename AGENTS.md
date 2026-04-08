# AGENTS.md — iMLX Project Reference

## Project Overview
On-device AI chat app for iOS/iPadOS using MLX Swift. Runs LLMs locally on Apple Silicon with no cloud dependency.
Current status: Functional and actively evolving.

## Quick Commands

### Build
```bash
# Build for simulator (requires Metal Toolchain)
xcodebuild build \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# Build for physical device (requires signing team)
xcodebuild build \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'generic/platform=iOS'
```

### Resolve Dependencies
```bash
xcodebuild -resolvePackageDependencies \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX"
```

### Install Metal Toolchain (required for CLI builds)
```bash
xcodebuild -downloadComponent MetalToolchain
```

## Architecture

- **Pattern:** MVVM with `@Observable` + Swift `actor` for inference isolation
- **MLX is NOT thread-safe** — all MLX array operations must be serialized through `InferenceService` (actor)
- **Token streaming:** `AsyncThrowingStream<String, Error>` bridges actor inference to `@MainActor` ViewModels
- **Chat state ownership:** `ChatViewModel` is initialized with the shared `AppState` up front instead of late configuration, so chat/model actions always target the single shared inference/download services
- **Conversation correctness over hidden session state:** Each generation request rebuilds `ChatSession` from the visible conversation history plus system prompt, avoiding stale cross-conversation cache leakage while the model weights stay loaded in `InferenceService`
- **Persona-first prompting:** Global response-style sliders and the single app-wide system prompt have been removed. Conversations now bind to a reusable `Persona` that owns the guided role definition, effective system prompt, sampling settings, and an optional model suggestion; a built-in default persona provides a safe fallback if a saved persona is missing, and persona selection never changes the currently loaded model automatically
- **Persistent memory:** The app stores compact user memories locally in JSON through `MemoryService`, with explicit “remember …” requests saved immediately, high-confidence self facts such as names, occupations, and explicit fandom statements promoted directly to active memories after trimming mixed-in request text including comma-separated asks, greeting-prefixed name introductions captured, bare `I'm ...` names kept out of occupation capture, model-suggested candidates sanitized to remove request tails and reject tag/request-label output, and lower-confidence inferred memories added only as pending suggestions after a response. Inferred extraction prefers Apple Foundation Models (`SystemLanguageModel` general use case, gated by availability on iOS 26+) using only the user message so memory work can run independently of the loaded MLX chat model, then falls back to the loaded MLX model when Apple’s model is unavailable. Active memories are retrieved through a base relevance gate using lexical/semantic matches, lightweight topic affinity, and core name identity before persona/global boosts are applied for ranking, then injected into the system prompt after persona instructions and before document excerpts with an instruction to ignore any memory that does not fit the current request; prompt memory is capped more aggressively for memory-constrained large models. Chat surfaces saved/forgotten/pending memory activity in a structured bottom notice card, pending notices can deep-link into the Memory Library, dismissing a notice suppresses only re-emission of that specific memory event, and per-turn background extraction continues across quick follow-up sends so earlier candidate memories still reach review. Settings exposes a Memory library for pending review, editing, deletion, and clear-all management; no cloud APIs are used.
- **Model storage reliability:** Download manifest entries are reconciled with disk through a centralized `AppState.reconcileModelCatalogState()` path used by chat model picker and model browser flows, stale entries are pruned, missing manifest entries are backfilled for on-disk curated models, storage totals read from the shared manifest state, lookup resolves symlink/mirror/cache snapshot paths, and broken symlinks auto-heal with fresh relative links
- **Local document chat:** Conversations can import local PDF, CSV, and text documents through `DocumentLibraryService`, which copies files into app storage, extracts text locally, chunks content, stores a lightweight on-device index, and retrieves relevant excerpts to inject into the model prompt on each send; `ChatViewModel` now applies model-aware document-context caps before generation (stricter for Qwen3.5 and vision models) to avoid MLX broadcast-shape crashes from oversized prompt prefill
- **Vision pipeline correctness:** Vision-capable models must include `vision_config` plus processor configs, attached images are validated as decodable `CIImage` values, and vision loads are routed through `VLMModelFactory` (`MLXVLM`) instead of text-only fallbacks
- **Model catalog accuracy:** Curated entries are verified against upstream Hugging Face repos before shipping; Qwen3.5 0.8B is treated as vision-only in-app because enabling thinking crashes the current runtime, while Qwen3.5 2B/4B remain thinking-capable vision models. Gemma 3 1B is treated as text-only while Gemma 3 4B remains vision-capable, Liquid model IDs point to live MLX repos (`mlx-community/LFM2-1.2B-4bit`, `LiquidAI/LFM2.5-350M-MLX-4bit`, `mlx-community/LFM2.5-1.2B-Thinking-4bit`), and Gemma 4 E2B is intentionally not in the catalog yet because the current `mlx-swift` / `mlx-swift-lm` `main` revisions pinned by the project still do not include a `gemma4` loader
- **Model catalog accuracy:** Curated entries are verified against upstream Hugging Face repos before shipping; Qwen3.5 0.8B is treated as vision-only in-app because enabling thinking crashes the current runtime, while Qwen3.5 2B/4B remain thinking-capable vision models. Gemma 3 1B is treated as text-only while Gemma 3 4B remains vision-capable, the MLX `Ministral 3` text lineup (3B/8B/14B Instruct + Reasoning) is exposed as text-only without the app's thinking toggle because those repos do not advertise `enable_thinking`, Liquid model IDs point to live MLX repos (`mlx-community/LFM2-1.2B-4bit`, `LiquidAI/LFM2.5-350M-MLX-4bit`, `mlx-community/LFM2.5-1.2B-Thinking-4bit`), and Gemma 4 E2B is intentionally not in the catalog yet because the current `mlx-swift` / `mlx-swift-lm` `main` revisions pinned by the project still do not include a `gemma4` loader
- **Download progress accuracy:** Model download UI uses snapshot `Progress.fractionCompleted` so progress is continuous instead of file-count jumps
- **Runtime safety and eligibility:** Simulator load/generation is explicitly blocked with a user-facing message, model compatibility uses normalized `DeviceTier` cutoffs (8/12/16/24GB) so 12GB-class devices reporting ~11.x GiB still unlock 12GB-tier models, the app declares the increased-memory-limit entitlement for physical-device builds, generation polls available memory during streaming so the app can stop before severe memory pressure becomes an iOS jetsam kill, and 12GB-class large models now use adaptive internal generation caps, recent text-only prompt history, and reduced document context to keep Qwen3.5/Gemma-class vision loads from exhausting memory immediately after prefill without unnecessarily truncating responses when entitlement headroom is available
- **Loaded-model state:** `selectedModel` is the persisted model choice across launches, while `loadedModelId` is runtime-only and only reflects an actually loaded in-memory model
- **Startup flow:** App launch now loads directly into the chat root, with conversations seeded during `AppState` initialization so there is no custom splash-screen delay.
- **Branding and app icon pipeline:** `Assets.xcassets/AppIcon.appiconset` and `BrandLogo.imageset` are generated from the high-resolution brain-logo artwork as full-bleed `1024x1024` PNGs; border-connected white backing is replaced with a blurred brand underlay so no white padding survives iOS icon masking, the README uses the same app-icon asset, and `BrandPalette` centralizes cyan/magenta/navy accents for appropriate interactive and brand surfaces
- **Liquid Glass adoption:** Custom SwiftUI chrome now routes through `Utilities/LiquidGlass.swift`, which applies native `glassEffect`, `GlassEffectContainer`, and glass button styles on iOS 26+ with material-based fallbacks on earlier releases; the treatment is focused on custom app chrome such as the chat composer, model/persona surfaces, status cards, badges, and action controls
- **Chat UX:** Chat opens directly into the active conversation on iPhone and iPad (`NavigationStack` + `ChatRootView`) without a persistent bottom tab bar, freeing vertical space for the transcript and composer. Conversation history is a top-left sheet (`ConversationListView` in modal presentation) instead of a list-first or split sidebar root and can be opened from chat with the toolbar menu or a leading-edge left-to-right swipe. The leading toolbar icon now opens a dropdown menu for Chats, Models, and Settings, while Models and Settings are presented from chat in modal navigation stacks instead of bottom tabs. Keyboard dismisses on outside tap, chat stays visible during model load with compact status cards, the header model selector is styled as an obvious capsule button that reads `Select model` when nothing is loaded, the persona switcher is integrated into the top of the chat composer instead of a separate full-width footer card, bottom composer chrome is width-capped on regular-width layouts to avoid oversized floating slabs, memory suggestions and save confirmations render as a compact status card above the composer with a working dismiss affordance and a direct route into Memory Library review, document import is available from the chat composer for all chats while image import still depends on vision-capable models, imported documents now behave like one-turn visual attachments by moving from the composer onto the associated user message after send while remaining available to the conversation's document context, assistant replies persist retrieved source excerpts, users can unload models from Chat/Models without deleting files, the conversation list and model picker now use semantic button rows (not raw tap gestures) for better accessibility, conversation history rows show an inline delete button on iPad while iPhone relies on swipe-to-delete to reduce visual clutter, delete confirmation state is owned by the list-level conversation history view and presented as a stable root alert because row-anchored confirmation popovers can auto-dismiss when SwiftUI list rows re-render, full-swipe delete is disabled so the confirmation stays stable until the user chooses Delete or Cancel, deleting the final conversation immediately creates a fresh fallback chat so the chat tab never gets stuck without an active conversation, compact icon-only controls in chat/list/message surfaces now use explicit accessibility labels and 44pt tappable targets, single sender attachments render directly above the associated user bubble using the measured bubble width so they visually align with the message, the assistant copy control sits inline on the trailing side of the final response bubble, and send stays disabled until the text portion of the message is non-empty
- **Thinking UX:** Models declare thinking support for the UI toggle; inference sets only `enable_thinking` in chat-template context (user messages are not prefixed with `/think`/`/no_think`, avoiding models misreading those tokens as user input). Assistant reasoning is rendered in a collapsible Thinking card, with fallback parsing for both tagged thinking (`<think>`, `<thinking>`, `<reasoning>`) and untagged Qwen-style meta/planning output; parser boundary detection now prioritizes explicit answer headers (including `Final Answer:` variants used by Qwen3.5, plus markdown heading forms) so final responses are consistently separated from thinking text, while streaming inferred reasoning is kept in the Thinking card until an explicit answer marker or closing think tag arrives, trailing close-only tags are tolerated, thinking-enabled generations get a concise-reasoning instruction plus model-size-aware token caps with adaptive caps for large vision models on 12GB-class devices, repetitive hidden-thinking loops are cut off early when substantive lines start repeating, and if a capped thinking run ends without a visible answer the app automatically performs a short answer-only follow-up pass using the stricter streaming-style parser to detect missing final output
- **Streaming performance:** Chat autoscroll is throttled during token streaming with a non-starving scheduler so fast token bursts still keep the view pinned to the latest output, manual user scroll interaction latches autoscroll off until the explicit down-arrow resume action is tapped, and the same center down-arrow (styled with the brand gradient for visibility) is also shown whenever the chat is off-bottom (including idle/non-generating states) for a one-tap return to latest messages; streamed token UI assignments are coalesced to roughly 30fps while preserving the full response for saved messages, stable message bubbles use equatable rendering to avoid old rows recomputing during generation, streaming assistant bubbles skip markdown parsing until the final response is committed, attachment thumbnails are cached and downsampled off the main render path, and thinking parser answer-heading regexes are reused instead of rebuilt per parse
- **Response metrics UX:** Assistant messages persist `GenerationStats` inline, stats remain in a single horizontal row (scrolling when needed), and footer layout prioritizes stat readability
- **Settings and model controls:** Settings now focus on device/storage details plus persona-library management, persona editing keeps beginner-friendly guided fields while hiding raw system-prompt editing and sampling controls behind an advanced section, user-facing max-token controls remain removed while the app enforces internal safety caps and answer-only follow-up recovery, model cards emphasize capability badges (Vision/Thinking), keep those badges single-line to avoid clipped text, use slimmer right-aligned trailing download/delete actions instead of large bottom pills, family detail screens open with a short model-family description card above the list, the main model browser no longer appends a low-memory/incompatible section at the bottom, the Mistral family now uses the official rainbow `mistral_logo` asset, model browser flows still encourage unload from active chat, and clear-all model deletion now routes through app-state orchestration with a primitive model-id/huggingFace-id delete API instead of constructing synthetic `ModelInfo` values

## Folder Structure
```
README.md                # GitHub project overview and quick start
LICENSE-APACHE           # Apache 2.0 license text
LICENSE-MIT              # MIT license text

iMLX/
├── App/                    # Entry point and ChatRootView shell (chat-first on all devices)
├── iMLX.entitlements       # Increased-memory-limit entitlement for physical-device inference headroom
├── Models/                 # Data models (ChatMessage, ModelInfo, GenerationStats, Conversation, AppState, Persona, DocumentRecord, UserMemory)
├── ViewModels/             # @Observable state (Chat, ModelManager)
├── Views/
│   ├── Chat/               # ChatView, MessageBubbleView, InputBarView, StatsOverlayView, ConversationListView, PersonaPickerSheet
│   ├── Models/             # ModelBrowserView, ModelCardView
│   └── Settings/           # SettingsView, PersonaLibraryView, PersonaEditorView, MemoryLibraryView
├── Services/               # InferenceService, ModelDownloadService, DeviceCapabilityService, ConversationService, ManifestService, PersonaService, MemoryService, DocumentLibraryService
├── Utilities/              # Constants, Haptics, Extensions, LiquidGlass helpers
└── Assets.xcassets/
    ├── AppIcon.appiconset   # Production app icon asset catalog entry driven by a full-bleed 1024x1024 PNG
    └── BrandLogo.imageset   # README/brand logo generated from the same high-resolution icon source
```

## Dependencies

| Package | URL | Branch | Purpose |
|---------|-----|--------|---------|
| mlx-swift | `https://github.com/ml-explore/mlx-swift` | `main` | Core MLX framework (MLX, MLXNN, MLXRandom) |
| mlx-swift-lm | `https://github.com/ml-explore/mlx-swift-lm` | `main` | LLM loading, ChatSession, model architectures |

Transitive: swift-huggingface, swift-transformers, swift-nio, swift-crypto, swift-collections, swift-numerics, swift-system, swift-atomics, swift-asn1, Jinja, EventSource, yyjson

## Key Technical Constraints

1. **MLX is not thread-safe** — all array ops must be serialized (actor enforces this)
2. **Memory is #1 constraint** — 4-bit 4B model = ~2.5GB weights + KV cache
3. **Build in Xcode only** — SwiftPM CLI cannot compile Metal shaders
4. **iOS Simulator cannot run MLX inference** — use a physical device or Mac Designed for iPad for model loading and generation
5. **No background inference** — iOS suspends GPU compute; inference only while foregrounded
6. **Deployment target:** iOS 18.0+
7. **Package versions:** Use `main` branch for both mlx-swift and mlx-swift-lm (version pins cause conflicts)

## Model Registry

Curated models in `Utilities/Constants.swift`:
- Qwen3 1.7B / 4B (mlx-community, 4-bit, thinking toggle supported)
- Qwen3.5 0.8B / 2B / 4B (mlx-community, 4-bit MLX; 0.8B is vision-only in-app, 2B/4B support thinking + vision)
- Qwen2-VL 2B Instruct (mlx-community, 4-bit, vision)
- Gemma 3 1B / 4B (mlx-community, 4-bit; 1B text-only, 4B vision)
- Ministral 3 3B / 8B / 14B Instruct + Reasoning (mlx-community, 4-bit MLX, text-only; reasoning variants do not use the app's thinking toggle)
- LFM2 1.2B (mlx-community, 4-bit)
- LFM2.5 350M / 1.2B Thinking (LiquidAI official MLX repo for 350M, mlx-community for 1.2B Thinking, only the Thinking variant enables the toggle)

Device tiers: 8GB (1-3B models), 12GB (3-4B models), 16GB+ (up to 8B)

## Persona Starters

Built-in personas currently seeded by `PersonaService`:
- General Assistant
- Personal Financial Advisor
- Code Reviewer
- Creative Writer
- Study Tutor


## Auto-Update Instructions

After every code change, update this file to reflect the current state: refresh file listings when layout changes, note architectural or UX behavior changes, and keep the model registry aligned with `Utilities/Constants.swift`. This file is the single source of truth for project status.

## Conventions

- No comments in code unless explicitly requested
- Follow existing code style (Swift 5.9+, SwiftUI, @Observable)
- Use `@Observable` for ViewModels (not `ObservableObject`/`@Published`)
- Use `actor` for any service that touches MLX
- Use `AsyncThrowingStream` for streaming token output
- All UI updates must be on `@MainActor`
