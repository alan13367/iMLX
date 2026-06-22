import Foundation

nonisolated enum DocumentCSVParser {
    static func fields(in row: String) -> [String] {
        var values: [String] = []
        var current = ""
        var isInsideQuotes = false

        for character in row {
            if character == "\"" {
                isInsideQuotes.toggle()
                continue
            }
            if character == ",", !isInsideQuotes {
                values.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }

        values.append(current)
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func pair(
        headers: [String],
        values: [String]
    ) -> [(header: String, value: String)] {
        let maximumCount = max(headers.count, values.count)
        return (0..<maximumCount).map { index in
            (
                header: index < headers.count ? headers[index] : "",
                value: index < values.count ? values[index] : ""
            )
        }
    }
}
