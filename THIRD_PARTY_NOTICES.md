# Third-party notices

iMLX depends on and includes third-party software. The project licenses in `LICENSE-MIT` and `LICENSE-APACHE` apply only to material for which the iMLX copyright holder can grant those rights. Third-party components remain under their respective licenses.

This file is an attribution summary, not a substitute for the license text distributed by each upstream project.

## Vendored source and resources

### KokoroSwift

- Upstream baseline: [mlalma/kokoro-ios@4d6d1d8](https://github.com/mlalma/kokoro-ios/commit/4d6d1d8ff8cd012014180c9cd4cf0151e7682354)
- Copyright: © 2025 Lassi Maksimainen
- License: MIT
- Location: `iMLX/Vendor/KokoroSwift` and `iMLX/Vendor/KokoroResources`

The vendored copy contains iMLX-specific integration, checkpoint-compatibility, isolation, and multilingual changes. The upstream Swift port is based on the Kokoro implementation in [mlx-audio](https://github.com/Blaizzy/mlx-audio), which is MIT-licensed, copyright © 2024 Prince Canuma.

### MisakiSwift and Misaki resources

- Upstream baseline: [mlalma/MisakiSwift@6835a1c](https://github.com/mlalma/MisakiSwift/commit/6835a1ce4a8854075c89f18ff75c74b13ef58e15)
- Original Python project: <https://github.com/hexgrad/misaki>
- License: Apache License 2.0
- Location: `iMLX/Vendor/MisakiSwift` and `iMLX/Vendor/MisakiResources`

The vendored copy contains iMLX-specific integration and Swift isolation changes. The model weights and pronunciation dictionaries in `MisakiResources` were distributed as resources of MisakiSwift.

### MLXUtilsLibrary

- Upstream baseline: [mlalma/MLXUtilsLibrary@66f7cd5](https://github.com/mlalma/MLXUtilsLibrary/commit/66f7cd58026f335c46699f0f8030cb3bda495c54)
- License: Apache License 2.0
- Location: `iMLX/Vendor/MLXUtilsLibrary`

The vendored copy contains iMLX-specific integration and Swift isolation changes. Its NumPy reader is based on [swift-npy](https://github.com/qoncept/swift-npy), MIT-licensed, copyright © 2020 Qoncept, Inc.

The Apache License 2.0 text is available in `LICENSE-APACHE`. Original MIT notices for vendored projects and upstream work are preserved under `ThirdPartyLicenses`. More detail about the import baselines and local modifications is in [`docs/vendor-code.md`](docs/vendor-code.md).

## Swift package dependencies

The Xcode project resolves package dependencies from their upstream repositories. Direct dependencies include:

- [MLX Swift](https://github.com/ml-explore/mlx-swift)
- [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm)
- [GRDB.swift](https://github.com/groue/GRDB.swift)
- [swift-tokenizers-mlx](https://github.com/DePasqualeOrg/swift-tokenizers-mlx)
- [Textual](https://github.com/gonzalezreal/textual)
- [ZIP Foundation](https://github.com/weichsel/ZIPFoundation)

`iMLX.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` records the complete resolved dependency graph and revisions. Each package is governed by the license in its upstream distribution.

## Models downloaded at runtime

iMLX does not grant rights to third-party models, tokenizers, or voice assets downloaded at runtime. Their model cards, repositories, and license terms govern use and redistribution. In particular, Kokoro speech assets are downloaded from [mlx-community/Kokoro-82M-4bit](https://huggingface.co/mlx-community/Kokoro-82M-4bit), whose model card identifies Apache-2.0 licensing.

## Names and logos

Apple, MLX, Hugging Face, DuckDuckGo, model-family names, and their logos are property of their respective owners. Their appearance identifies compatibility or data recipients and does not imply endorsement. See [`TRADEMARKS.md`](TRADEMARKS.md).
