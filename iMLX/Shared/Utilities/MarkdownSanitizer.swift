import Foundation

nonisolated enum MarkdownSanitizer {
    private struct CodeFence {
        let marker: Character
        let minimumLength: Int
    }

    static func preparingForRendering(
        _ markdown: String,
        linkPhoneNumbers: Bool = false
    ) -> String {
        let normalizedMath = normalizingLaTeXDelimiters(from: markdown)
        let withoutRemoteImages = removingRemoteImages(from: normalizedMath)
        guard linkPhoneNumbers else { return withoutRemoteImages }
        return linkingPhoneNumbers(from: withoutRemoteImages)
    }

    static func normalizingLaTeXDelimiters(from markdown: String) -> String {
        var result: [String] = []
        result.reserveCapacity(markdown.components(separatedBy: .newlines).count)

        var activeFence: CodeFence?
        for line in markdown.components(separatedBy: .newlines) {
            if let fence = activeFence {
                result.append(line)
                if isClosingCodeFence(line, matching: fence) {
                    activeFence = nil
                }
                continue
            }

            if let fence = openingCodeFence(in: line) {
                activeFence = fence
                result.append(line)
                continue
            }

            result.append(normalizingLaTeXDelimiters(inLine: line))
        }

        return result.joined(separator: "\n")
    }

    static func removingRemoteImages(from markdown: String) -> String {
        var result: [String] = []
        result.reserveCapacity(markdown.components(separatedBy: .newlines).count)

        var activeFence: CodeFence?
        for line in markdown.components(separatedBy: .newlines) {
            if let fence = activeFence {
                result.append(line)
                if isClosingCodeFence(line, matching: fence) {
                    activeFence = nil
                }
                continue
            }

            if let fence = openingCodeFence(in: line) {
                activeFence = fence
                result.append(line)
                continue
            }

            result.append(removingRemoteImages(fromLine: line))
        }

        return result.joined(separator: "\n")
    }

    static func linkingPhoneNumbers(from markdown: String) -> String {
        var result: [String] = []
        result.reserveCapacity(markdown.components(separatedBy: .newlines).count)

        var activeFence: CodeFence?
        for line in markdown.components(separatedBy: .newlines) {
            if let fence = activeFence {
                result.append(line)
                if isClosingCodeFence(line, matching: fence) {
                    activeFence = nil
                }
                continue
            }

            if let fence = openingCodeFence(in: line) {
                activeFence = fence
                result.append(line)
                continue
            }

            result.append(linkingPhoneNumbers(inLine: line))
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

    private static func normalizingLaTeXDelimiters(inLine line: String) -> String {
        var output = ""
        var index = line.startIndex
        var inlineCodeDelimiterLength: Int?

        while index < line.endIndex {
            if line[index] == "`" {
                let runEnd = line[index...].firstIndex(where: { $0 != "`" }) ?? line.endIndex
                let runLength = line.distance(from: index, to: runEnd)
                output.append(contentsOf: line[index..<runEnd])
                if inlineCodeDelimiterLength == nil {
                    inlineCodeDelimiterLength = runLength
                } else if inlineCodeDelimiterLength == runLength {
                    inlineCodeDelimiterLength = nil
                }
                index = runEnd
                continue
            }

            guard inlineCodeDelimiterLength == nil, line[index] == "\\" else {
                output.append(line[index])
                index = line.index(after: index)
                continue
            }

            let slashRunEnd = line[index...].firstIndex(where: { $0 != "\\" }) ?? line.endIndex
            let slashCount = line.distance(from: index, to: slashRunEnd)
            guard slashRunEnd < line.endIndex else {
                output.append(contentsOf: line[index..<slashRunEnd])
                break
            }

            let delimiter = line[slashRunEnd]
            let replacement: String?
            switch delimiter {
            case "(", ")":
                replacement = "$"
            case "[", "]":
                replacement = "$$"
            default:
                replacement = nil
            }

            guard let replacement, !slashCount.isMultiple(of: 2) else {
                output.append(contentsOf: line[index..<slashRunEnd])
                index = slashRunEnd
                continue
            }

            if slashCount > 1 {
                output.append(String(repeating: "\\", count: slashCount - 1))
            }
            output.append(replacement)
            index = line.index(after: slashRunEnd)
        }

        return output
    }

    private static func openingCodeFence(in line: String) -> CodeFence? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard line.count - trimmed.count <= 3,
              let marker = trimmed.first,
              marker == "`" || marker == "~" else {
            return nil
        }

        let markerCount = trimmed.prefix(while: { $0 == marker }).count
        guard markerCount >= 3 else { return nil }
        return CodeFence(marker: marker, minimumLength: markerCount)
    }

    private static func isClosingCodeFence(_ line: String, matching fence: CodeFence) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard line.count - trimmed.count <= 3 else { return false }

        let markerCount = trimmed.prefix(while: { $0 == fence.marker }).count
        guard markerCount >= fence.minimumLength else { return false }
        return trimmed.dropFirst(markerCount).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func linkingPhoneNumbers(inLine line: String) -> String {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        ) else {
            return line
        }

        let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
        let protectedRanges = protectedMarkdownRanges(in: line)
        let matches = detector.matches(in: line, options: [], range: fullRange)
            .filter { match in
                match.resultType == .phoneNumber
                    && match.phoneNumber?.isEmpty == false
                    && !protectedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 })
            }

        guard !matches.isEmpty else { return line }

        var output = ""
        var cursor = line.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: line) else { continue }
            output.append(contentsOf: line[cursor..<matchRange.lowerBound])

            let visibleNumber = String(line[matchRange])
            if let url = telURLString(from: match.phoneNumber ?? visibleNumber) {
                output.append("[\(visibleNumber)](\(url))")
            } else {
                output.append(visibleNumber)
            }
            cursor = matchRange.upperBound
        }
        output.append(contentsOf: line[cursor...])
        return output
    }

    private static func protectedMarkdownRanges(in line: String) -> [NSRange] {
        let patterns = [
            #"\[[^\]]+\]\([^)]+\)"#,
            #"`[^`]+`"#
        ]
        let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
        return patterns.flatMap { pattern -> [NSRange] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: line, options: [], range: fullRange).map(\.range)
        }
    }

    private static func telURLString(from phoneNumber: String) -> String? {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var output = ""
        for character in trimmed {
            if character.isNumber {
                output.append(character)
            } else if character == "+", output.isEmpty {
                output.append(character)
            }
        }

        guard output.contains(where: \.isNumber) else { return nil }
        return "tel:\(output)"
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
