# Contributing to iMLX

Thanks for helping improve iMLX. Bug reports, focused feature proposals, documentation fixes, and pull requests are welcome.

## Before you start

- Search existing issues before opening a new one.
- Open an issue before starting a large feature or architectural change so the approach can be discussed.
- Report security problems privately as described in [`SECURITY.md`](SECURITY.md).
- Follow the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## Development requirements

- Xcode 26 or newer
- iOS/iPadOS 26 or macOS 26
- An Apple-silicon Mac for native MLX inference
- The Xcode Metal Toolchain

Resolve packages and install the Metal toolchain:

```bash
xcodebuild -resolvePackageDependencies \
  -project "iMLX.xcodeproj" \
  -scheme "iMLX"

xcodebuild -downloadComponent MetalToolchain
```

The iOS Simulator is suitable for builds and most tests, but it cannot run MLX inference, AlarmKit scheduling, or Live Activities. See `AGENTS.md` for the canonical build and test commands.

For physical-device builds, select your own development team in Xcode. You may also need unique bundle identifiers for the app and widget.

## Source boundaries

- Put cross-platform code in `iMLX/Shared`.
- Put target-selected implementations in `iMLX/Platforms/iOS` or `iMLX/Platforms/macOS`.
- Keep vendored code in `iMLX/Vendor` and document its origin and license.
- Put shared tests in `iMLXTests/Shared` and platform tests in the matching platform directory.

Read [`docs/cross-platform-source-boundaries.md`](docs/cross-platform-source-boundaries.md) before changing target membership or platform adapters.

## Pull requests

Keep each pull request focused and include:

1. A concise description of the problem and solution.
2. The platforms affected.
3. Tests performed, including simulator/device limitations.
4. Screenshots or recordings for visible UI changes.
5. Compatibility notes for persisted data, model formats, or tool traces.

Please also:

- Preserve actor isolation around MLX work.
- Avoid adding new dependencies when an existing service boundary is sufficient.
- Add or update tests for behavior changes.
- Run `git diff --check` before submitting.
- Do not commit secrets, signing credentials, downloaded models, derived data, or user-specific Xcode state.

There is no hosted CI workflow. Contributors are responsible for running the relevant local builds and tests.

## Licensing contributions

Unless explicitly stated otherwise, by submitting a contribution you agree that it may be distributed under either the Apache License 2.0 or the MIT License, at the recipient's option, consistent with this project's dual-license policy.
