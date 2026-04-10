import Foundation
import NaturalLanguage

extension NLTag {
  nonisolated var isProperNoun: Bool {
    return self == .personalName || self == .organizationName || self == .placeName
  }
}
