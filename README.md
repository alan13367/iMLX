# iMLX

On-device AI chat for iOS and iPadOS using MLX Swift.

Status: Work in progress (WIP).

iMLX runs supported LLMs locally on Apple Silicon with no cloud dependency.

## Features

- Fully on-device inference with MLX
- Streaming token output in chat UI
- Model browser and download management
- Conversation persistence and history
- Device-aware model recommendations

## Requirements

- macOS with Xcode 16+
- iOS 18.0+ deployment target
- Apple Silicon device for best performance
- Metal Toolchain installed for CLI builds

## Quick Start

### 1) Resolve Swift packages

```bash
xcodebuild -resolvePackageDependencies \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX"
```

### 2) Install Metal Toolchain

```bash
xcodebuild -downloadComponent MetalToolchain
```

### 3) Build for iOS Simulator

```bash
xcodebuild build \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

### 4) Build for physical device

```bash
xcodebuild build \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX" \
  -destination 'generic/platform=iOS'
```

## Project Structure

```text
iMLX/
├── App/
├── Models/
├── Services/
├── Utilities/
├── ViewModels/
└── Views/
```

## Technical Notes

- MLX array operations are serialized through an actor-based inference service.
- Simulator builds may run on CPU fallback and are not representative of real-device performance.
- Inference is intended for foreground app usage.

## License

This project is dual-licensed under either of the following, at your option:

- Apache License 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT License ([LICENSE-MIT](LICENSE-MIT))

Copyright (c) 2026 Alan Beltran Pozo
