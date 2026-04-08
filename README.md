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
| **Thinking** | Per-model toggle where the model supports `enable_thinking` |
| **UX** | Chat-first launch, brain-logo icon, cyan/magenta brand accents, EN / ES / zh-Hans + optional in-app language |

---

## Recent updates

- **Personas** replace a single global system prompt: choose or create a persona per chat; manage under **Settings → Personas** (guided fields or advanced sampling).
- Chat opens into the current conversation; use the top-left list control for history.
- The README and asset catalog use the same full-bleed high-resolution brain-logo icon so installed app icons do not show white padding.
- Manifest validation prunes stale download entries; model paths tolerate symlinks and cache snapshots; broken links auto-heal.
- Simulator shows a clear “unsupported” path instead of failing inside MLX load.
- Generation uses safety caps, memory-aware stops, thinking budgets by model size, repetitive-thinking detection, and an answer-only follow-up when needed.

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
├── Services/        # PersonaService, InferenceService, …
├── Utilities/
├── ViewModels/
└── Views/
    ├── Chat/        # e.g. PersonaPickerSheet
    └── Settings/    # e.g. PersonaLibraryView, PersonaEditorView
```

---

## Technical notes

- MLX work is serialized through an **actor**-based inference service.
- The Simulator is not a reliable stand-in for GPU behavior on device.
- Inference is intended for **foreground** use.

---

## License

Dual-licensed at your option:

- [Apache License 2.0](LICENSE-APACHE)
- [MIT License](LICENSE-MIT)

Copyright (c) 2026 Alan Beltran Pozo
