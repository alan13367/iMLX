<p align="center">
  <img src="iMLX/Assets.xcassets/AppIcon.appiconset/icon-1024.png" alt="iMLX app icon" width="96" height="96" />
</p>

<p align="center"><strong>iMLX</strong></p>
<p align="center">On-device AI chat for <strong>iOS</strong> and <strong>iPadOS</strong> using MLX Swift.</p>
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
| **Personas** | Reusable roles (goal, tone, optional default model); editor under **Settings → Personas**; per-chat persona + picker; starters + custom personas |
| **Chat** | Saved conversations, history from the toolbar, chat-first launch |
| **Memory** | Private on-device user memories, multilingual extraction, review queue, local retrieval for personalization |
| **Thinking** | Per-model toggle where the model supports `enable_thinking` |
| **UX** | Chat-first launch, brain-logo icon, cyan/magenta brand accents, EN / ES / zh-Hans + optional in-app language |

---

## Memory

iMLX includes a local memory vault for compact user facts that can help future chats feel more personal. Memories are stored on device and can be reviewed, edited, accepted, rejected, or cleared under **Settings → Memory**.

The memory system is designed around source-grounded facts:

- It extracts only from the user's message, not from assistant replies or recommendations.
- It supports multilingual user input while storing canonical English memory text for consistency.
- It keeps the original source quote and language metadata when available.
- It filters low-value conversation events such as greetings, thanks, and generic requests.
- High-confidence identity facts, such as the user's name, can be saved directly; broader inferred memories go through Pending Review.

Retrieval stays local and synchronous. The app combines BM25-style sparse scoring, Natural Language embeddings, source-quote tokens, and relation-aware query hints so memories can be found even when the later query is in another supported language.

---

## How It Works

iMLX keeps the main assistant loop local:

- `InferenceService` serializes MLX model work and streams tokens back to the chat UI.
- `ChatViewModel` rebuilds prompt context from the visible conversation, selected persona, relevant memories, and retrieved documents.
- `MemoryService` stores compact user facts locally and retrieves only the memories that look relevant to the next turn.
- `PersonaService` seeds built-in assistants and saves custom personas.
- `DocumentLibraryService` imports local files, chunks content, indexes it, and retrieves relevant snippets for chat context.

The app is designed to degrade clearly when a feature cannot run, such as MLX inference on Simulator.

---

## Requirements

- macOS with **Xcode 16+**
- **iOS 18.0+** deployment target
- **Apple Silicon** device for realistic performance
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

---

## Project layout

```text
iMLX/
├── App/
├── Models/          # Persona, Conversation, ChatMessage, …
├── Services/        # Inference, downloads, memory, documents, personas
├── Utilities/
├── ViewModels/
└── Views/
    ├── Chat/        # e.g. PersonaPickerSheet
    └── Settings/    # e.g. PersonaLibraryView, PersonaEditorView
```

---

## Technical notes

- MLX work is serialized through an **actor**-based inference service.
- Memory extraction uses the active model or Apple Foundation Models when available, but retrieval is local and does not require a translation/generation pass.
- Memory internals are split across `MemoryService.swift`, `MemoryService+Extraction.swift`, `MemoryService+Retrieval.swift`, `MemoryService+Shared.swift`, and `MemorySupport.swift`.
- The Simulator is not a reliable stand-in for GPU behavior on device.
- Inference is intended for **foreground** use.

---

## License

Dual-licensed at your option:

- [Apache License 2.0](LICENSE-APACHE)
- [MIT License](LICENSE-MIT)

Copyright (c) 2026 Alan Beltran Pozo
