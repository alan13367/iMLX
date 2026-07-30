import Foundation

actor TimerService {
    nonisolated static var isSupported: Bool {
        PlatformTimerScheduler.isSupported
    }

    private let scheduler: PlatformTimerScheduler

    init(scheduler: PlatformTimerScheduler = PlatformTimerScheduler()) {
        self.scheduler = scheduler
    }

    func createTimer(durationSeconds: TimeInterval, title: String?) async throws -> MessageGroundingResult {
        guard durationSeconds >= 1, durationSeconds <= 86_400 else {
            throw ToolExecutionFailure.invalidArguments("Timer duration must be between 1 second and 24 hours.")
        }
        let timerTitle = title?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = timerTitle?.isEmpty == false ? timerTitle! : "Timer"

        try await scheduler.schedule(durationSeconds: durationSeconds, title: displayTitle)

        let contextBlock = """
        Timer created:
        - Title: \(displayTitle)
        - Duration: \(Self.durationDescription(totalSeconds: Int(durationSeconds.rounded())))
        """

        return MessageGroundingResult(contextBlock: contextBlock, sources: [])
    }

    private nonisolated static func durationDescription(totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds) second\(seconds == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }
}
