<p align="center">
  <img src="iMLX/Assets.xcassets/AppIcon.appiconset/icon-1024.png" alt="iMLX app icon" width="96" height="96" />
</p>

<p align="center"><strong>iMLX</strong></p>
<p align="center">On-device AI chat for <strong>iOS</strong>, <strong>iPadOS</strong>, and native <strong>macOS</strong> using MLX Swift.</p>
<p align="center"><sub>Runs supported LLMs locally on Apple Silicon · no cloud dependency · actively evolving</sub></p>

---

## Overview

iMLX is a native app for streaming, multi-turn chat with curated MLX models: download what you need, load from Chat or the Models tab, and keep conversations on device.

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
├── App/
├── Models/          # Conversation, ChatMessage, UserMemory, …
├── Services/        # Inference, downloads, memory, documents
├── Utilities/
├── ViewModels/
└── Views/
    ├── Chat/        # ChatView, composer, message components
    └── Settings/    # SettingsView, MemoryLibraryView, AssistantSettingsView
```

---

## Technical notes

- MLX work is serialized through an **actor**-based inference service.
- Memory extraction uses the active model or Apple Foundation Models when available, but retrieval is local and does not require a translation/generation pass.
- Memory internals are split across `MemoryService.swift`, `MemoryStore.swift`, `MemoryDatabase.swift`, `MemoryService+Extraction.swift`, `MemoryService+Retrieval.swift`, `MemoryService+Shared.swift`, and `MemorySupport.swift`.
- A dedicated architecture note lives in `docs/memory-architecture.md`.
- The iOS Simulator is not a reliable stand-in for GPU behavior; the native macOS target can run MLX directly on Apple silicon.
- AlarmKit timer creation and its Live Activity remain iOS-only; unsupported tools are omitted from the macOS catalog.
- Inference is intended for **foreground** use.

---

## License

Dual-licensed at your option:

- [Apache License 2.0](LICENSE-APACHE)
- [MIT License](LICENSE-MIT)

Copyright (c) 2026 Alan Beltran Pozo
