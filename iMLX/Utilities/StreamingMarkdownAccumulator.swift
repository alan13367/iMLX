import Foundation

nonisolated struct StreamingMarkdownSegment: Equatable, Identifiable, Sendable {
    let id: Int
    let source: String
}

nonisolated enum StreamingMarkdownTailKind: Equatable, Sendable {
    case inline
    case heading
    case thematicBreak
    case list
    case blockQuote
    case table
    case fencedCode
    case displayMath

    var supportsInlineRendering: Bool {
        self == .inline
    }
}

nonisolated struct StreamingMarkdownSnapshot: Equatable, Sendable {
    let completedSegments: [StreamingMarkdownSegment]
    let activeTail: String
    let activeTailKind: StreamingMarkdownTailKind
    let resetGeneration: Int

    static let empty = StreamingMarkdownSnapshot(
        completedSegments: [],
        activeTail: "",
        activeTailKind: .inline,
        resetGeneration: 0
    )

    var reconstructedSource: String {
        completedSegments.map(\.source).joined() + activeTail
    }
}

nonisolated struct StreamingSourceCursor {
    private static let continuityWindow = 64

    private var consumedByteCount = 0
    private var leadingBytes: [UInt8] = []
    private var trailingBytes: [UInt8] = []

    init(source: String = "") {
        update(with: source)
    }

    mutating func consume(_ source: String) -> String? {
        let bytes = source.utf8
        guard bytes.count >= consumedByteCount,
              hasMatchingBoundary(in: bytes) else {
            return nil
        }

        let suffixStart = bytes.index(bytes.startIndex, offsetBy: consumedByteCount)
        let appendedText = String(decoding: bytes[suffixStart...], as: UTF8.self)
        update(with: source)
        return appendedText
    }

    private func hasMatchingBoundary(in bytes: String.UTF8View) -> Bool {
        guard consumedByteCount > 0 else { return true }
        guard bytes.prefix(leadingBytes.count).elementsEqual(leadingBytes) else {
            return false
        }

        let trailingCount = trailingBytes.count
        let trailingStart = bytes.index(
            bytes.startIndex,
            offsetBy: consumedByteCount - trailingCount
        )
        let trailingEnd = bytes.index(trailingStart, offsetBy: trailingCount)
        return bytes[trailingStart..<trailingEnd].elementsEqual(trailingBytes)
    }

    private mutating func update(with source: String) {
        let bytes = source.utf8
        consumedByteCount = bytes.count
        leadingBytes = Array(bytes.prefix(Self.continuityWindow))
        trailingBytes = Array(bytes.suffix(Self.continuityWindow))
    }
}

nonisolated struct StreamingMarkdownAccumulator {
    private enum BlockKind: Equatable {
        case paragraph
        case list
        case blockQuote
        case table
        case fencedCode(Fence)
        case displayMath(DisplayMathFence)
    }

    private struct Fence: Equatable {
        let marker: Character
        let minimumLength: Int
    }

    private struct DisplayMathFence: Equatable {
        let opening: String
        let closing: String
    }

    private(set) var processedCharacterCount = 0

    private var completedSegments: [StreamingMarkdownSegment] = []
    private var activeSource = ""
    private var activeKind: BlockKind?
    private var activeContentLines: [String] = []
    private var incompleteLine = ""
    private var nextSegmentID = 0
    private var resetGeneration = 0
    private var awaitsContinuationLookahead = false

    mutating func consume(appending appendedText: String) -> StreamingMarkdownSnapshot {
        processedCharacterCount += appendedText.count
        consumeAppendedText(appendedText)

        return makeSnapshot()
    }

    mutating func reset(with source: String = "") -> StreamingMarkdownSnapshot {
        completedSegments.removeAll(keepingCapacity: true)
        activeSource = ""
        activeKind = nil
        activeContentLines.removeAll(keepingCapacity: true)
        incompleteLine = ""
        awaitsContinuationLookahead = false
        resetGeneration += 1
        processedCharacterCount += source.count
        consumeAppendedText(source)
        return makeSnapshot()
    }

    private mutating func consumeAppendedText(_ appendedText: String) {
        guard !appendedText.isEmpty else { return }

        let combined = incompleteLine + appendedText
        var lineStart = combined.startIndex

        while lineStart < combined.endIndex,
              let newline = combined[lineStart...].firstIndex(of: "\n") {
            let lineEnd = combined.index(after: newline)
            processCompletedLine(String(combined[lineStart..<lineEnd]))
            lineStart = lineEnd
        }

        incompleteLine = lineStart < combined.endIndex
            ? String(combined[lineStart...])
            : ""
        resolveContinuationLookaheadFromIncompleteLine()
    }

    private mutating func resolveContinuationLookaheadFromIncompleteLine() {
        guard awaitsContinuationLookahead,
              !incompleteLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        switch activeKind {
        case .list:
            guard !isPotentialListContinuationPrefix(incompleteLine) else { return }
            commitActiveBlock()
        case .blockQuote:
            guard !isBlockQuoteLine(incompleteLine) else { return }
            commitActiveBlock()
        default:
            break
        }
    }

    private mutating func processCompletedLine(_ line: String) {
        if case .fencedCode(let fence) = activeKind {
            appendToActiveBlock(line)
            if isClosingFence(line, matching: fence) {
                commitActiveBlock()
            }
            return
        }

        if case .displayMath(let fence) = activeKind {
            appendToActiveBlock(line)
            if closesDisplayMath(line, matching: fence, isOpeningLine: false) {
                commitActiveBlock()
            }
            return
        }

        let content = lineContent(line)
        let isBlank = content.trimmingCharacters(in: .whitespaces).isEmpty

        if awaitsContinuationLookahead, !isBlank {
            let continues: Bool
            switch activeKind {
            case .list:
                continues = isListContinuation(content)
            case .blockQuote:
                continues = isBlockQuoteLine(content)
            default:
                continues = false
            }

            if continues {
                awaitsContinuationLookahead = false
            } else {
                commitActiveBlock()
            }
        }

        if isBlank {
            appendToActiveBlock(line, countsAsContent: false)
            switch activeKind {
            case .list, .blockQuote:
                awaitsContinuationLookahead = true
            case .some:
                commitActiveBlock()
            case .none:
                break
            }
            return
        }

        if activeKind == nil {
            beginBlock(with: line, content: content)
            return
        }

        switch activeKind {
        case .paragraph:
            if activeContentLines.count == 1, isSetextUnderline(content) {
                appendToActiveBlock(line)
                commitActiveBlock()
            } else if activeContentLines.count == 1,
                      isTableDelimiter(content, headerLine: activeContentLines[0]) {
                activeKind = .table
                appendToActiveBlock(line)
            } else {
                appendToActiveBlock(line)
            }

        case .list, .blockQuote, .table:
            appendToActiveBlock(line)

        case .fencedCode, .displayMath, .none:
            break
        }
    }

    private mutating func beginBlock(with line: String, content: String) {
        if let displayMathFence = openingDisplayMath(in: content) {
            activeKind = .displayMath(displayMathFence)
            appendToActiveBlock(line)
            if closesDisplayMath(line, matching: displayMathFence, isOpeningLine: true) {
                commitActiveBlock()
            }
            return
        }

        if let fence = openingFence(in: content) {
            activeKind = .fencedCode(fence)
            appendToActiveBlock(line)
            return
        }

        if isATXHeading(content) {
            activeKind = .paragraph
            appendToActiveBlock(line)
            commitActiveBlock()
            return
        }

        if isThematicBreak(content) {
            activeKind = .paragraph
            appendToActiveBlock(line)
            commitActiveBlock()
            return
        }

        if isListLine(content) {
            activeKind = .list
        } else if isBlockQuoteLine(content) {
            activeKind = .blockQuote
        } else {
            activeKind = .paragraph
        }
        appendToActiveBlock(line)
    }

    private mutating func appendToActiveBlock(_ line: String, countsAsContent: Bool = true) {
        activeSource += line
        if countsAsContent {
            activeContentLines.append(lineContent(line))
        }
    }

    private mutating func commitActiveBlock() {
        guard activeKind != nil, !activeSource.isEmpty else { return }

        completedSegments.append(
            StreamingMarkdownSegment(id: nextSegmentID, source: activeSource)
        )
        nextSegmentID += 1
        activeSource = ""
        activeKind = nil
        activeContentLines.removeAll(keepingCapacity: true)
        awaitsContinuationLookahead = false
    }

    private func makeSnapshot() -> StreamingMarkdownSnapshot {
        StreamingMarkdownSnapshot(
            completedSegments: completedSegments,
            activeTail: activeSource + incompleteLine,
            activeTailKind: activeTailKind(),
            resetGeneration: resetGeneration
        )
    }

    private func activeTailKind() -> StreamingMarkdownTailKind {
        switch activeKind {
        case .list:
            return .list
        case .blockQuote:
            return .blockQuote
        case .table:
            return .table
        case .fencedCode:
            return .fencedCode
        case .displayMath:
            return .displayMath
        case .paragraph:
            if activeContentLines.count == 1 {
                if isSetextUnderline(incompleteLine) {
                    return .heading
                }
                if isTableDelimiter(incompleteLine, headerLine: activeContentLines[0]) {
                    return .table
                }
            }
            return .inline
        case .none:
            let content = incompleteLine.trimmingCharacters(in: .newlines)
            if openingFence(in: content) != nil {
                return .fencedCode
            }
            if openingDisplayMath(in: content) != nil {
                return .displayMath
            }
            if isATXHeading(content) {
                return .heading
            }
            if isThematicBreak(content) {
                return .thematicBreak
            }
            if isListLine(content) {
                return .list
            }
            if isBlockQuoteLine(content) {
                return .blockQuote
            }
            return .inline
        }
    }

    private func lineContent(_ line: String) -> String {
        var content = line
        if content.last == "\n" {
            content.removeLast()
        }
        if content.last == "\r" {
            content.removeLast()
        }
        return content
    }

    private func openingFence(in line: String) -> Fence? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard line.count - trimmed.count <= 3,
              let marker = trimmed.first,
              marker == "`" || marker == "~" else {
            return nil
        }

        let markerCount = trimmed.prefix(while: { $0 == marker }).count
        guard markerCount >= 3 else { return nil }
        return Fence(marker: marker, minimumLength: markerCount)
    }

    private func openingDisplayMath(in line: String) -> DisplayMathFence? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        if trimmed.hasPrefix("$$") {
            return DisplayMathFence(opening: "$$", closing: "$$")
        }
        if trimmed.hasPrefix(#"\["#) {
            return DisplayMathFence(opening: #"\["#, closing: #"\]"#)
        }
        return nil
    }

    private func closesDisplayMath(
        _ line: String,
        matching fence: DisplayMathFence,
        isOpeningLine: Bool
    ) -> Bool {
        let content = lineContent(line)
        let searchStart: String.Index
        if isOpeningLine,
           let openingRange = content.range(of: fence.opening) {
            searchStart = openingRange.upperBound
        } else {
            searchStart = content.startIndex
        }
        return content.range(of: fence.closing, range: searchStart..<content.endIndex) != nil
    }

    private func isClosingFence(_ line: String, matching fence: Fence) -> Bool {
        let content = lineContent(line)
        let trimmed = content.drop(while: { $0 == " " || $0 == "\t" })
        guard content.count - trimmed.count <= 3 else { return false }

        let markerCount = trimmed.prefix(while: { $0 == fence.marker }).count
        guard markerCount >= fence.minimumLength else { return false }
        return trimmed.dropFirst(markerCount).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private func isATXHeading(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard line.count - trimmed.count <= 3 else { return false }
        let markerCount = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markerCount), trimmed.count > markerCount else { return false }
        return trimmed[trimmed.index(trimmed.startIndex, offsetBy: markerCount)].isWhitespace
    }

    private func isSetextUnderline(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1, let marker = trimmed.first, marker == "=" || marker == "-" else {
            return false
        }
        return trimmed.allSatisfy { $0 == marker }
    }

    private func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marker = trimmed.first, marker == "*" || marker == "-" || marker == "_" else {
            return false
        }
        let nonWhitespace = trimmed.filter { !$0.isWhitespace }
        return nonWhitespace.count >= 3 && nonWhitespace.allSatisfy { $0 == marker }
    }

    private func isListLine(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        if let first = trimmed.first,
           first == "-" || first == "+" || first == "*",
           trimmed.dropFirst().first?.isWhitespace == true {
            return true
        }

        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty,
              let delimiter = trimmed.dropFirst(digits.count).first,
              delimiter == "." || delimiter == ")" else {
            return false
        }
        return trimmed.dropFirst(digits.count + 1).first?.isWhitespace == true
    }

    private func isListContinuation(_ line: String) -> Bool {
        isListLine(line) || line.first?.isWhitespace == true
    }

    private func isPotentialListContinuationPrefix(_ line: String) -> Bool {
        if line.first?.isWhitespace == true {
            return true
        }

        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = trimmed.first else { return true }
        if first == "-" || first == "+" || first == "*" {
            return trimmed.count == 1 || trimmed.dropFirst().first?.isWhitespace == true
        }

        if first.isNumber {
            let digits = trimmed.prefix(while: \.isNumber)
            let remainder = trimmed.dropFirst(digits.count)
            guard let delimiter = remainder.first else { return true }
            guard delimiter == "." || delimiter == ")" else { return false }
            return remainder.count == 1 || remainder.dropFirst().first?.isWhitespace == true
        }

        return false
    }

    private func isBlockQuoteLine(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        return trimmed.first == ">"
    }

    private func isTableDelimiter(_ line: String, headerLine: String) -> Bool {
        guard headerLine.contains("|"), line.contains("|") else { return false }

        var cells = line.split(separator: "|", omittingEmptySubsequences: false)
        if cells.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            cells.removeFirst()
        }
        if cells.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            cells.removeLast()
        }
        guard !cells.isEmpty else { return false }

        return cells.allSatisfy { cell in
            var delimiter = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            if delimiter.first == ":" {
                delimiter.removeFirst()
            }
            if delimiter.last == ":" {
                delimiter.removeLast()
            }
            return delimiter.count >= 3 && delimiter.allSatisfy { $0 == "-" }
        }
    }
}
