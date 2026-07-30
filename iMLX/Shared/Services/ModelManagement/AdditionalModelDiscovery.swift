import Foundation

nonisolated enum AdditionalModelsFolderError: LocalizedError {
    case notDirectory

    var errorDescription: String? {
        "The selected location is not a folder."
    }
}

nonisolated struct DiscoveredAdditionalModel: Sendable {
    let model: ModelInfo
    let directoryURL: URL
    let matchesCuratedModel: Bool
}

nonisolated enum AdditionalModelDiscovery {
    static func discoverModels(
        in rootURL: URL,
        curatedModels: [ModelInfo] = Constants.ModelRegistry.curatedModels,
        fileManager: FileManager = .default
    ) -> [DiscoveredAdditionalModel] {
        let root = rootURL.standardizedFileURL
        let candidates = candidateDirectories(in: root, fileManager: fileManager)
        var discoveredByID: [String: DiscoveredAdditionalModel] = [:]

        for directory in candidates {
            guard let metadata = modelMetadata(in: directory, fileManager: fileManager) else {
                continue
            }

            let relativePath = relativePath(from: root, to: directory)
            if let curated = matchingCuratedModel(
                for: directory,
                relativePath: relativePath,
                config: metadata.config,
                curatedModels: curatedModels
            ) {
                guard discoveredByID[curated.id] == nil else { continue }
                var model = curated
                model.isDownloaded = true
                model.localURL = directory
                discoveredByID[curated.id] = DiscoveredAdditionalModel(
                    model: model,
                    directoryURL: directory,
                    matchesCuratedModel: true
                )
                continue
            }

            let model = makeImportedModel(
                directory: directory,
                relativePath: relativePath,
                metadata: metadata
            )
            discoveredByID[model.id] = DiscoveredAdditionalModel(
                model: model,
                directoryURL: directory,
                matchesCuratedModel: false
            )
        }

        return discoveredByID.values.sorted {
            $0.model.displayName.localizedStandardCompare($1.model.displayName) == .orderedAscending
        }
    }

    private struct ModelMetadata {
        let config: [String: Any]
        let sizeOnDiskBytes: Int64
    }

    private static func candidateDirectories(in root: URL, fileManager: FileManager) -> [URL] {
        if modelMetadata(in: root, fileManager: fileManager) != nil {
            return [root]
        }

        var candidates: [URL] = []
        for firstLevel in childDirectories(of: root, fileManager: fileManager) {
            if modelMetadata(in: firstLevel, fileManager: fileManager) != nil {
                candidates.append(firstLevel)
                continue
            }

            for secondLevel in childDirectories(of: firstLevel, fileManager: fileManager) {
                if modelMetadata(in: secondLevel, fileManager: fileManager) != nil {
                    candidates.append(secondLevel)
                }
            }
        }
        return candidates
    }

    private static func childDirectories(of directory: URL, fileManager: FileManager) -> [URL] {
        let entries = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private static func modelMetadata(
        in directory: URL,
        fileManager: FileManager
    ) -> ModelMetadata? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let configURL = directory.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: configData),
              let config = object as? [String: Any] else {
            return nil
        }

        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let weightFiles = files.filter { $0.pathExtension.lowercased() == "safetensors" }
        guard !weightFiles.isEmpty else { return nil }

        if inferredVisionSupport(from: config, name: directory.lastPathComponent) {
            let hasProcessorConfiguration = files.contains {
                $0.lastPathComponent == "processor_config.json"
                    || $0.lastPathComponent == "preprocessor_config.json"
            }
            guard hasProcessorConfiguration else { return nil }
        }

        var size: Int64 = 0
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += Int64(fileSize)
            }
        }

        return ModelMetadata(config: config, sizeOnDiskBytes: size)
    }

    private static func matchingCuratedModel(
        for directory: URL,
        relativePath: String,
        config: [String: Any],
        curatedModels: [ModelInfo]
    ) -> ModelInfo? {
        let directoryName = directory.lastPathComponent.lowercased()
        let normalizedRelativePath = relativePath.lowercased()
        let configuredName = (config["_name_or_path"] as? String)?.lowercased()

        return curatedModels.first { model in
            let repository = model.huggingFaceId.lowercased()
            let repositoryName = repository.split(separator: "/").last.map(String.init) ?? repository
            return directoryName == model.id.lowercased()
                || directoryName == repositoryName
                || normalizedRelativePath == repository
                || configuredName == repository
                || configuredName == repositoryName
        }
    }

    private static func makeImportedModel(
        directory: URL,
        relativePath: String,
        metadata: ModelMetadata
    ) -> ModelInfo {
        let configuredName = metadata.config["_name_or_path"] as? String
        let displayName = displayName(directoryName: directory.lastPathComponent)
        let sizeGB = max(Double(metadata.sizeOnDiskBytes) / 1_073_741_824, 0.01)
        let family = inferredFamily(
            directoryName: directory.lastPathComponent,
            config: metadata.config
        )
        let repositoryID = repositoryIdentifier(
            relativePath: relativePath,
            directoryName: directory.lastPathComponent,
            configuredName: configuredName
        )

        return ModelInfo(
            id: "external-\(stableIdentifier(for: relativePath.lowercased()))",
            displayName: displayName,
            huggingFaceId: repositoryID,
            parameterCount: inferredParameterCount(from: displayName),
            quantization: inferredQuantization(from: metadata.config, name: displayName),
            estimatedSizeGB: sizeGB,
            minDeviceRAM: minimumRAM(forModelSizeGB: sizeGB),
            family: family,
            logoName: family.logoName,
            supportsThinking: inferredThinkingSupport(from: displayName),
            supportsVision: inferredVisionSupport(from: metadata.config, name: displayName),
            prefersThinkingEnabled: false,
            isDownloaded: true,
            localURL: directory
        )
    }

    private static func displayName(directoryName: String) -> String {
        directoryName.replacingOccurrences(of: "_", with: " ")
    }

    private static func repositoryIdentifier(
        relativePath: String,
        directoryName: String,
        configuredName: String?
    ) -> String {
        if relativePath.split(separator: "/").count == 2 {
            return relativePath
        }
        if let configuredName, configuredName.split(separator: "/").count == 2 {
            return configuredName
        }
        return "local/\(directoryName)"
    }

    private static func inferredFamily(
        directoryName: String,
        config: [String: Any]
    ) -> ModelInfo.ModelFamily {
        let architectureNames = (config["architectures"] as? [String])?.joined(separator: " ") ?? ""
        let modelType = config["model_type"] as? String ?? ""
        let value = "\(directoryName) \(architectureNames) \(modelType)".lowercased()

        if value.contains("imlx") { return .imlx }
        if value.contains("qwen3.5") || value.contains("qwen3_5") { return .qwen35 }
        if value.contains("qwen2") && (value.contains("vl") || value.contains("vision")) { return .qwen2vl }
        if value.contains("qwen3") { return .qwen3 }
        if value.contains("minicpm") { return .minicpm }
        if value.contains("gemma4") || value.contains("gemma_4") { return .gemma4 }
        if value.contains("gemma3") || value.contains("gemma_3") { return .gemma3 }
        if value.contains("mistral") || value.contains("ministral") { return .mistral3 }
        if value.contains("lfm2.5") || value.contains("lfm2_5") { return .lfm25 }
        if value.contains("lfm2") { return .lfm2 }
        if value.contains("bonsai") { return .bonsai }
        return .custom
    }

    private static func inferredParameterCount(from name: String) -> String {
        let pattern = #"(?i)(\d+(?:\.\d+)?)\s*([bm])\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: name,
                range: NSRange(name.startIndex..., in: name)
              ),
              let valueRange = Range(match.range(at: 1), in: name),
              let suffixRange = Range(match.range(at: 2), in: name) else {
            return "Local"
        }
        return "\(name[valueRange])\(name[suffixRange].uppercased())"
    }

    private static func inferredQuantization(from config: [String: Any], name: String) -> String {
        for key in ["quantization", "quantization_config"] {
            if let quantization = config[key] as? [String: Any],
               let bits = integerValue(quantization["bits"]) {
                return "\(bits)-bit"
            }
        }

        let lowercasedName = name.lowercased()
        if let regex = try? NSRegularExpression(pattern: #"(?i)\b(2|3|4|5|6|8)\s*[- ]?bit\b"#),
           let match = regex.firstMatch(
            in: lowercasedName,
            range: NSRange(lowercasedName.startIndex..., in: lowercasedName)
           ),
           let range = Range(match.range(at: 1), in: lowercasedName) {
            return "\(lowercasedName[range])-bit"
        }

        let dataType = (config["torch_dtype"] as? String)
            ?? (config["dtype"] as? String)
            ?? "MLX"
        switch dataType.lowercased() {
        case "bfloat16", "bf16": return "BF16"
        case "float16", "fp16": return "FP16"
        case "float32", "fp32": return "FP32"
        default: return "MLX"
        }
    }

    private static func inferredThinkingSupport(from name: String) -> Bool {
        let value = name.lowercased()
        return value.contains("thinking") || value.contains("reasoning")
    }

    private static func inferredVisionSupport(from config: [String: Any], name: String) -> Bool {
        if config["vision_config"] != nil { return true }
        let architectureNames = (config["architectures"] as? [String])?.joined(separator: " ") ?? ""
        let modelType = config["model_type"] as? String ?? ""
        let value = "\(name) \(architectureNames) \(modelType)".lowercased()
        return value.contains("vision")
            || value.contains("-vl")
            || value.contains("_vl")
            || value.contains(" vl")
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func minimumRAM(forModelSizeGB size: Double) -> Int {
        let estimatedRequirement = max(8, Int(ceil(size * 1.5)))
        if estimatedRequirement <= 8 { return 8 }
        if estimatedRequirement <= 12 { return 12 }
        if estimatedRequirement <= 16 { return 16 }
        return 24
    }

    private static func relativePath(from root: URL, to directory: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let directoryComponents = directory.standardizedFileURL.pathComponents
        guard directoryComponents.starts(with: rootComponents) else {
            return directory.lastPathComponent
        }
        let relativeComponents = directoryComponents.dropFirst(rootComponents.count)
        return relativeComponents.isEmpty ? directory.lastPathComponent : relativeComponents.joined(separator: "/")
    }

    private static func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
