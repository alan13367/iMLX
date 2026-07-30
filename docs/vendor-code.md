# Vendored code

`iMLX/Vendor` contains source and resources copied from upstream projects because iMLX carries integration and checkpoint-compatibility changes that are not assembled by app callers.

| Path | Upstream baseline | License | Local changes |
|---|---|---|---|
| `KokoroSwift`, `KokoroResources` | [mlalma/kokoro-ios@4d6d1d8](https://github.com/mlalma/kokoro-ios/commit/4d6d1d8ff8cd012014180c9cd4cf0151e7682354) | MIT | Target integration, concurrency isolation, multilingual G2P, and checkpoint compatibility |
| `MisakiSwift`, `MisakiResources` | [mlalma/MisakiSwift@6835a1c](https://github.com/mlalma/MisakiSwift/commit/6835a1ce4a8854075c89f18ff75c74b13ef58e15) | Apache-2.0 | Target integration and concurrency isolation |
| `MLXUtilsLibrary` | [mlalma/MLXUtilsLibrary@66f7cd5](https://github.com/mlalma/MLXUtilsLibrary/commit/66f7cd58026f335c46699f0f8030cb3bda495c54) | Apache-2.0 | Target integration and concurrency isolation |

The baseline revisions were identified by comparing the initial vendored import with upstream files; some integration edits were already present in that import. Do not remove upstream attribution when updating these copies. Record any new upstream revision, review license changes, preserve local modifications, and run TTS and G2P tests when importing updates.

See [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) and [`ThirdPartyLicenses`](../ThirdPartyLicenses) for additional upstream attribution and license information.
