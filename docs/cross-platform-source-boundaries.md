# Cross-Platform Source Boundaries

## Decision

iMLX remains one repository with two native application targets:

- `iMLX`: iOS and iPadOS
- `iMLXMac`: Apple-silicon macOS

The products share domain and orchestration code, but compile different platform roots. Platform code is selected by Xcode target membership rather than broad source-level `#if os(...)` branches.

## Source roots

```text
iMLX/
├── Shared/                 Compiled into iMLX and iMLXMac
│   ├── App/                Cross-platform app routes and shared root content
│   ├── Models/             Domain and persisted models
│   ├── Resources/          Shared assets and localization
│   ├── Services/           Stable façades and domain implementations
│   ├── Utilities/          Platform-neutral utilities
│   ├── ViewModels/         Shared UI orchestration
│   └── Views/              Shared SwiftUI content
├── Platforms/
│   ├── iOS/                Compiled only into iMLX
│   │   ├── App/
│   │   ├── Compatibility/
│   │   ├── Services/
│   │   └── Views/
│   └── macOS/              Compiled only into iMLXMac
│       ├── App/
│       ├── Compatibility/
│       ├── Models/
│       ├── Services/
│       └── Views/
└── Vendor/                 Compiled into both applications
```

Tests use the same ownership model:

```text
iMLXTests/
├── Shared/                 Runs against both application targets
└── Platforms/
    ├── iOS/                Runs only in iMLXTests
    └── macOS/              Runs only in iMLXMacTests
```

The widget remains an independent iOS extension. `IMLXTimerMetadata.swift` is the only intentional app-platform source shared directly with the widget target.

## Target membership matrix

| Root | iMLX | iMLXMac | Alarm widget |
|---|:---:|:---:|:---:|
| `iMLX/Shared` | Yes | Yes | No |
| `iMLX/Platforms/iOS` | Yes | No | Metadata exception only |
| `iMLX/Platforms/macOS` | No | Yes | No |
| `iMLX/Vendor` | Yes | Yes | No |
| `iMLXTests/Shared` | iMLXTests | iMLXMacTests | No |
| `iMLXTests/Platforms/iOS` | iMLXTests | No | No |
| `iMLXTests/Platforms/macOS` | No | iMLXMacTests | No |

`PBXFileSystemSynchronizedRootGroup` entries enforce this matrix. Do not restore a synchronized root for the entire `iMLX` or `iMLXTests` directory.

## Dependency direction

Allowed dependencies:

```text
Platforms/iOS  ─┐
                ├──> Shared ──> Vendor / package products
Platforms/macOS ┘
```

Rules:

1. Shared code must not import UIKit, AppKit, or AlarmKit.
2. Shared code must not select between iOS and macOS with `#if os(...)`.
3. Platform roots may use OS frameworks directly.
4. Platform roots may depend on shared types; shared code must not depend on a concrete platform implementation beyond a matching target-selected API.
5. Persisted models, coding keys, migration behavior, tool names, and conversation formats stay shared.
6. `InferenceService` remains the single serialized MLX boundary on both platforms.
7. Do not create parallel app state, inference, memory, tool-routing, or persistence architectures.
8. Simulator checks and `DEBUG` feature checks are not platform ownership checks and may remain where their guarded behavior is genuinely shared.

## Target-selected adapter pattern

When shared orchestration needs an OS implementation, each platform root defines the same small API:

```swift
// Platforms/iOS/...
struct PlatformFeature { /* iOS implementation */ }

// Platforms/macOS/...
struct PlatformFeature { /* macOS implementation */ }
```

Only one declaration is compiled into each application target. The shared façade calls `PlatformFeature` without an OS conditional.

Current adapters cover:

- Clipboard, images, colors, toolbar placement, and Settings launching
- Haptics
- Available-memory accounting and host classification
- Wired-memory inference policy
- Profiling battery metadata
- Speech recognition and playback sessions
- Model-download background identifiers and macOS folder bookmarks
- AlarmKit scheduling and the unsupported macOS timer implementation
- Chat, onboarding, model-browser, and settings presentation

Adapters must remain thin. Validation, normalization, policy, persistence, and user-facing result construction belong in shared façades when they are common behavior.

## UI composition

Each product has its own app entry and navigation shell:

- iOS owns `WindowGroup`, `NavigationStack`, full-screen onboarding, camera presentation, and mobile settings navigation.
- macOS owns named windows, commands, `Settings` scenes, `NavigationSplitView`, file drops, desktop sheet sizing, and tabbed preferences.

Shared SwiftUI views own transcript rendering, model browser content, conversation mutations, settings detail panes, onboarding content, and chat orchestration.

When a shared view needs different presentation, prefer a target-selected `ViewModifier` or a small platform view over an inline OS branch.

## Adding a feature

Place a new file by answering these questions in order:

1. Does it define persisted/domain data, policy, orchestration, or UI content that must behave the same? Put it in `Shared`.
2. Does it import an OS-only framework or define platform navigation/presentation? Put it in the matching `Platforms` root.
3. Does shared code need both implementations? Give the iOS and macOS files the same narrow API and keep the caller shared.
4. Is it iOS-only with no meaningful macOS behavior? Keep it out of the macOS target and expose capability through the shared façade or catalog.
5. Does it need widget access? Add a narrow synchronized membership exception; never attach an application root to the widget.

Every platform-specific behavior should have a platform-specific test when practical. Domain behavior should remain in `iMLXTests/Shared`.

## Validation

Run the iOS build and native macOS tests documented in `AGENTS.md` after any target-membership or platform-adapter change.

For membership verification, inspect generated Swift file lists and assert that neither app compiles the other platform root:

```bash
! rg 'iMLX/Platforms/macOS/' /tmp/iMLX-ios/Build/Intermediates.noindex -g '*.SwiftFileList'
! rg 'iMLX/Platforms/iOS/' /tmp/iMLX-mac/Build/Intermediates.noindex -g '*.SwiftFileList'
```

Also verify that the widget file list includes `IMLXTimerMetadata.swift` and no other application source.
