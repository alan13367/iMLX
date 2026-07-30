import Foundation

nonisolated struct AggregatedToolTurnResult: Equatable, Sendable {
    let contextBlock: String
    let sources: [MessageSource]
}

extension ToolCallingService {
    nonisolated func aggregatedResults(
        for steps: [ToolTurnStep],
        maxCharacters: Int = Constants.ToolCalling.maxCombinedToolResultContextCharacters
    ) -> AggregatedToolTurnResult {
        guard !steps.isEmpty, maxCharacters > 0 else {
            return AggregatedToolTurnResult(contextBlock: "", sources: [])
        }

        let headers = steps.enumerated().map { index, step in
            "Tool result \(index + 1) — \(step.call.toolName) [\(step.result.status.rawValue)]:\n"
        }
        let bodies = steps.map { step in
            let content = step.result.contextBlock.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                return content
            }
            return step.result.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "No usable result content."
        }
        let separatorsLength = max(0, steps.count - 1) * 2
        let bodyBudget = max(0, maxCharacters - headers.reduce(0) { $0 + $1.count } - separatorsLength)
        let allocations = fairCharacterAllocations(for: bodies.map(\.count), budget: bodyBudget)

        let contextBlock = zip(zip(headers, bodies), allocations)
            .map { pair, allocation in
                let (header, body) = pair
                return header + String(body.prefix(allocation))
            }
            .joined(separator: "\n\n")

        var seenSourceKeys = Set<String>()
        let sources = steps.flatMap(\.result.sources).filter { source in
            seenSourceKeys.insert("\(source.kind.rawValue):\(source.id)").inserted
        }
        return AggregatedToolTurnResult(
            contextBlock: String(contextBlock.prefix(maxCharacters)),
            sources: sources
        )
    }

    private nonisolated func fairCharacterAllocations(
        for lengths: [Int],
        budget: Int
    ) -> [Int] {
        guard !lengths.isEmpty, budget > 0 else {
            return Array(repeating: 0, count: lengths.count)
        }

        var allocations = Array(repeating: 0, count: lengths.count)
        var unresolved = Set(lengths.indices)
        var remaining = budget

        while !unresolved.isEmpty, remaining > 0 {
            let share = remaining / unresolved.count
            let completed = unresolved.filter { index in
                lengths[index] - allocations[index] <= share
            }
            if completed.isEmpty {
                let ordered = unresolved.sorted()
                for (offset, index) in ordered.enumerated() {
                    let extra = share + (offset < remaining % ordered.count ? 1 : 0)
                    allocations[index] += min(extra, lengths[index] - allocations[index])
                }
                break
            }

            for index in completed {
                let extra = lengths[index] - allocations[index]
                allocations[index] += extra
                remaining -= extra
                unresolved.remove(index)
            }
        }

        return allocations
    }
}
