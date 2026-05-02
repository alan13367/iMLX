import AlarmKit
import Foundation
import SwiftUI

struct IMLXTimerMetadata: AlarmMetadata {
    let title: String
}

actor TimerService {
    func createTimer(durationSeconds: TimeInterval, title: String?) async throws -> MessageGroundingResult {
        guard durationSeconds >= 1, durationSeconds <= 86_400 else {
            throw ToolExecutionFailure.invalidArguments("Timer duration must be between 1 second and 24 hours.")
        }
        let timerTitle = title?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = timerTitle?.isEmpty == false ? timerTitle! : "Timer"

        guard try await ensureTimerAccess() else {
            throw ToolExecutionFailure.permissionDenied("Timer access is required to create a timer.")
        }

        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.fill"
        )
        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: displayTitle),
                stopButton: stopButton
            )
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: IMLXTimerMetadata(title: displayTitle),
            tintColor: .blue
        )
        let fireDate = Date().addingTimeInterval(durationSeconds)
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(fireDate),
            attributes: attributes
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
        } catch AlarmManager.AlarmError.maximumLimitReached {
            throw ToolExecutionFailure.unavailable("The system alarm limit has been reached. Delete an existing alarm or timer and try again.")
        } catch {
            throw ToolExecutionFailure.executionFailed("Timer could not be created: \(error.localizedDescription)")
        }

        let contextBlock = """
        Timer created:
        - Title: \(displayTitle)
        - Duration: \(Self.durationDescription(seconds: Int(durationSeconds.rounded())))
        """

        return MessageGroundingResult(contextBlock: contextBlock, sources: [])
    }

    private func ensureTimerAccess() async throws -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .notDetermined:
            return try await AlarmManager.shared.requestAuthorization() == .authorized
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private nonisolated static func durationDescription(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let seconds = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds) second\(seconds == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }
}
