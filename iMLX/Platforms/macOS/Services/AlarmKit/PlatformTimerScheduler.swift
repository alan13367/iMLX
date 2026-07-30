import Foundation

nonisolated struct PlatformTimerScheduler: Sendable {
    static let isSupported = false

    func schedule(durationSeconds: TimeInterval, title: String) async throws {
        throw ToolExecutionFailure.unavailable("Native timer creation is not available on macOS.")
    }
}
