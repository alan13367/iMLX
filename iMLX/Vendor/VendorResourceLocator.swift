import Foundation

nonisolated enum VendorResourceLocator {
    private static let subdirectories = [
        "Vendor/KokoroResources",
        "Vendor/MisakiResources",
        "KokoroResources",
        "MisakiResources",
        "Resources",
    ]

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        let bundle = Bundle.main

        for subdirectory in subdirectories {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
        }

        guard let resourceURL = bundle.resourceURL else { return nil }
        let enumerator = FileManager.default.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.lastPathComponent == "\(name).\(ext)" {
                return candidate
            }
        }

        return nil
    }
}
