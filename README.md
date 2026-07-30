<p align="center">
  <img src="iMLX/Shared/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" alt="iMLX app icon" width="96" height="96" />
</p>

<p align="center"><strong>iMLX</strong></p>
<p align="center">On-device AI chat for <strong>iOS</strong>, <strong>iPadOS</strong>, and native <strong>macOS</strong> using MLX Swift.</p>
<p align="center"><sub>Runs supported LLMs locally on Apple Silicon · no cloud dependency · actively evolving</sub></p>

---

## Overview

iMLX is a native app for streaming, multi-turn chat with curated MLX models: download what you need, load from Chat or the Models tab, and keep conversations on device.

> **Project status:** iMLX is under active development. APIs, persisted formats, the model catalog, and platform behavior may change. Review model licenses and resource requirements before downloading or redistributing third-party models.

---

## Features

| Area | What you get |
|------|----------------|
| **Inference** | On-device MLX, streaming tokens, inline generation metrics |
| **Models** | Browser, downloads, device-aware picks, load/unload from Chat and Models |
| **Assistant** | Global system prompt and temperature; edited under **Settings → Assistant** |
| **Chat** | Saved conversations, history from the toolbar, chat-first launch |
| **Memory** | Private on-device user memories, multilingual extraction, review queue, local retrieval for personalization |
| **Thinking** | Per-model toggle where the model supports `enable_thinking` |
| **Grounding** | Local documents, image OCR, source attribution, optional web search and URL reading |
| **Tools** | Local date/time plus permission-gated Calendar, Reminders, Contacts, and iOS timer tools |
| **Voice** | On-device speech recognition and optional local Kokoro speech synthesis |
| **UX** | Chat-first launch, brain-logo icon, cyan/magenta brand accents, EN / ES / zh-Hans + optional in-app language |

---

## Memory

iMLX includes a local memory vault for compact user facts that can help future chats feel more personal. Memories are stored on device and can be reviewed, edited, accepted, rejected, archived, or cleared under **Settings → Memory**.

The memory system is designed around source-grounded facts:

- It extracts only from the user's message, not from assistant replies or recommendations.
- It supports multilingual user input while storing normalized canonical memory text plus typed relation/value metadata.
- It keeps source evidence, language metadata, and lifecycle events alongside the canonical memory item.
- It filters low-value conversation events such as greetings, thanks, and generic requests.
- High-confidence identity facts, such as the user's name, can be saved directly; broader inferred memories go through Pending Review.

Retrieval stays local and synchronous. The app uses a bounded local pipeline: FTS candidate lookup, typed fact matching, local semantic reranking, and retrieval explanations so selected memories can be inspected later.

---

## How It Works

iMLX keeps the main assistant loop local:

- `InferenceService` serializes MLX model work and streams tokens back to the chat UI.
- `ChatViewModel` rebuilds prompt context from the visible conversation, relevant memories, and retrieved documents.
- `MemorySystem` is the app-facing memory facade.
- `MemoryStore` owns GRDB persistence, migrations, and transactional writes.
- `MemoryRetrievalService` retrieves only the memories that look relevant to the next turn and records why they were chosen.
- `DocumentLibraryService` imports local files, chunks content, indexes it, and retrieves relevant snippets for chat context.

The app is designed to degrade clearly when a feature cannot run, such as MLX inference on Simulator.

---

## Privacy and network use

Core inference, OCR, memories, document retrieval, and speech synthesis run locally. iMLX has no required account, developer-operated backend, analytics SDK, or advertising SDK.

Optional features make network requests: model and speech-asset downloads use Hugging Face, Web Search sends the selected query to DuckDuckGo and result sites, and Read URL contacts the requested host. Contacts, calendars, reminders, files, photos, camera, microphone, speech recognition, and alarms remain behind Apple system permissions.

See [`docs/privacy.md`](docs/privacy.md) for the complete data-flow summary.

---

## Requirements

- macOS with **Xcode 26+**
- **iOS/iPadOS 26+** or **macOS 26+**
- **Apple Silicon** hardware for local MLX inference
- **Metal Toolchain** for CLI builds (see below)

---

## Quick start

**1. Resolve Swift packages**

```bash
xcodebuild -resolvePackageDependencies \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX"
```

**2. Install Metal Toolchain**

```bash
xcodebuild -downloadComponent MetalToolchain
```

**3. Build for iOS Simulator**

```bash
xcodebuild build \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

**4. Build for a physical device**

```bash
xcodebuild build \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'generic/platform=iOS'
```

**5. Build the native Apple-silicon Mac app**

```bash
xcodebuild build \
  -project "iMLX.xcodeproj" \
  -scheme "iMLXMac" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

---

## Project layout

```text
iMLX/
├── Shared/          # Cross-platform models, services, view models, views, resources
├── Platforms/
│   ├── iOS/         # iOS app shell, UIKit/AlarmKit adapters, mobile presentation
│   └── macOS/       # Mac app shell, AppKit adapters, commands and desktop presentation
└── Vendor/          # Shared vendored implementations and resources

iMLXTests/
├── Shared/
└── Platforms/       # Target-specific iOS and macOS tests
```

The Xcode project enforces these boundaries with separate synchronized source roots. See [`docs/cross-platform-source-boundaries.md`](docs/cross-platform-source-boundaries.md).

For a physical-device build, select your own Apple development team in Xcode. Forks may also need unique app and widget bundle identifiers.

---

## Technical notes

- MLX work is serialized through an **actor**-based inference service.
- Memory extraction uses the active model or Apple Foundation Models when available, but retrieval is local and does not require a translation/generation pass.
- Memory internals are split across `MemoryService.swift`, `MemoryStore.swift`, `MemoryDatabase.swift`, `MemoryExtraction.swift`, `MemoryRetrieval.swift`, `MemoryService+Shared.swift`, and `MemorySupport.swift` under `iMLX/Shared/Services/Memory/`.
- A dedicated architecture note lives in `docs/memory-architecture.md`.
- The iOS Simulator is not a reliable stand-in for GPU behavior; the native macOS target can run MLX directly on Apple silicon.
- AlarmKit timer creation and its Live Activity remain iOS-only; unsupported tools are omitted from the macOS catalog.
- Inference is intended for **foreground** use.

---

## Contributing and support

Contributions are welcome. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before proposing substantial changes and follow the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

- General help and bug reports: [`SUPPORT.md`](SUPPORT.md)
- Private vulnerability reports: [`SECURITY.md`](SECURITY.md)

This repository intentionally has no hosted CI workflow; use the local Xcode build and test commands documented above and in `AGENTS.md`.

---

## License

Original iMLX code is dual-licensed at your option under:

- [Apache License 2.0](LICENSE-APACHE)
- [MIT License](LICENSE-MIT)

Vendored code, package dependencies, downloaded models, and third-party assets remain governed by their respective terms. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), [`NOTICE`](NOTICE), and [`TRADEMARKS.md`](TRADEMARKS.md).

Copyright (c) 2026 Alan Beltran Pozo
