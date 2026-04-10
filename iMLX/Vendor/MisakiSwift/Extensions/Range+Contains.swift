import Foundation

extension Range where Bound: Comparable {
    nonisolated func contains(_ other: Range<Bound>) -> Bool {
        return self.lowerBound <= other.lowerBound && self.upperBound >= other.upperBound
    }
}
