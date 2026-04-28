import Foundation

nonisolated enum MarkdownSanitizer {
    static func removingRemoteImages(from markdown: String) -> String {
        var result: [String] = []
        result.reserveCapacity(markdown.components(separatedBy: .newlines).count)

        var isInsideFence = false
        for line in markdown.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInsideFence.toggle()
                result.append(line)
                continue
            }

            result.append(isInsideFence ? line : removingRemoteImages(fromLine: line))
        }

        return result.joined(separator: "\n")
    }

    private static func removingRemoteImages(fromLine line: String) -> String {
        var output = ""
        var index = line.startIndex

        while index < line.endIndex {
            guard line[index] == "!",
                  line.index(after: index) < line.endIndex,
                  line[line.index(after: index)] == "[" else {
                output.append(line[index])
                index = line.index(after: index)
                continue
            }

            guard let closeBracket = line[index...].firstIndex(of: "]"),
                  closeBracket < line.index(before: line.endIndex),
                  line[line.index(after: closeBracket)] == "(",
                  let closeParen = line[line.index(after: closeBracket)...].firstIndex(of: ")") else {
                output.append(line[index])
                index = line.index(after: index)
                continue
            }

            let destinationStart = line.index(closeBracket, offsetBy: 2)
            let destination = String(line[destinationStart..<closeParen])
            if isRemoteMarkdownDestination(destination) {
                let altStart = line.index(index, offsetBy: 2)
                let altText = String(line[altStart..<closeBracket]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !altText.isEmpty {
                    output.append("[Image: \(altText)]")
                }
            } else {
                output.append(contentsOf: line[index...closeParen])
            }

            index = line.index(after: closeParen)
        }

        return output
    }

    private static func isRemoteMarkdownDestination(_ destination: String) -> Bool {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstToken = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? trimmed
        let normalized = firstToken.trimmingCharacters(in: CharacterSet(charactersIn: "<>")).lowercased()
        return normalized.hasPrefix("http://")
            || normalized.hasPrefix("https://")
            || normalized.hasPrefix("//")
    }
}
