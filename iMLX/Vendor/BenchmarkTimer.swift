import Foundation

enum BenchmarkTimer {
    static func reset() {}
    static func startTimer(_ name: String) {
        logPrint("Starting benchmark: \(name)")
    }

    static func stopTimer(_ name: String) {
        logPrint("Stopping benchmark: \(name)")
    }
}
