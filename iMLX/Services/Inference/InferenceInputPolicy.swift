import Foundation

nonisolated enum InferenceInputPolicy {
    static func speechChunks(
        for text: String,
        maximumInputCharacters: Int,
        maximumChunks: Int
    ) -> [String] {
        let normalizedText = String(
            text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumInputCharacters)
        )
        guard !normalizedText.isEmpty else { return [] }

        let sentenceFragments = normalizedText
            .components(separatedBy: CharacterSet(charactersIn: ".!?;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let baseFragments = sentenceFragments.isEmpty ? [normalizedText] : sentenceFragments
        var chunks: [String] = []
        var currentChunk = ""

        for fragment in baseFragments {
            for wordChunk in splitIntoWordChunks(fragment, maximumCharacters: 180) {
                let candidate = currentChunk.isEmpty ? wordChunk : "\(currentChunk). \(wordChunk)"
                if candidate.count <= 220 {
                    currentChunk = candidate
                } else {
                    if !currentChunk.isEmpty {
                        chunks.append(currentChunk)
                    }
                    currentChunk = wordChunk
                }
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        return Array(chunks.prefix(maximumChunks))
    }

    static func modelConfigurationSupportsVision(in directory: URL) -> Bool {
        let configURL = directory.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL),
              let configObject = try? JSONSerialization.jsonObject(with: configData),
              let config = configObject as? [String: Any] else {
            return false
        }

        if config["vision_config"] != nil {
            return true
        }

        guard let modelType = config["model_type"] as? String else {
            return false
        }
        let normalizedType = modelType.lowercased()
        return normalizedType.contains("_vl") || normalizedType == "qwen3_5"
    }

    private static func splitIntoWordChunks(
        _ text: String,
        maximumCharacters: Int
    ) -> [String] {
        guard text.count > maximumCharacters else { return [text] }

        var chunks: [String] = []
        var currentChunk = ""
        for word in text.split(separator: " ") {
            let wordString = String(word)
            if currentChunk.isEmpty {
                currentChunk = wordString
                continue
            }

            let candidate = "\(currentChunk) \(wordString)"
            if candidate.count <= maximumCharacters {
                currentChunk = candidate
            } else {
                chunks.append(currentChunk)
                currentChunk = wordString
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        return chunks
    }
}
