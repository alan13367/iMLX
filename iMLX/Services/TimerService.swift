import AlarmKit
import Foundation
import SwiftUI

actor TimerService {
    func createTimer(durationSeconds: TimeInterval, title: String?) async throws -> MessageGroundingResult {
        guard durationSeconds >= 1, durationSeconds <= 86_400 else {
            throw ToolExecutionFailure.invalidArguments("Timer duration must be between 1 second and 24 hours.")
        }
        let timerTitle = title?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = timerTitle?.isEmpty == false ? timerTitle! : "Timer"

        let authorized: Bool
        do {
            authorized = try await ensureTimerAccess()
        } catch {
            let nsError = error as NSError
            throw ToolExecutionFailure.executionFailed("Timer authorization failed (\(nsError.domain) \(nsError.code)): \(error.localizedDescription)")
        }
        guard authorized else {
            throw ToolExecutionFailure.permissionDenied("Timer access is required to create a timer. Enable it in Settings → iMLX.")
        }

        let stopButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: "Stop"),
            textColor: .white,
            systemImageName: "stop.fill"
        )
        let pauseButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: "Pause"),
            textColor: .white,
            systemImageName: "pause.fill"
        )
        let resumeButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: "Resume"),
            textColor: .white,
            systemImageName: "play.fill"
        )
        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: displayTitle),
                stopButton: stopButton
            ),
            countdown: AlarmPresentation.Countdown(
                title: LocalizedStringResource(stringLiteral: displayTitle),
                pauseButton: pauseButton
            ),
            paused: AlarmPresentation.Paused(
                title: LocalizedStringResource(stringLiteral: "Paused"),
                resumeButton: resumeButton
            )
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: IMLXTimerMetadata(title: displayTitle),
            tintColor: .blue
        )
        let configuration = AlarmManager.AlarmConfiguration.timer(
            duration: durationSeconds,
            attributes: attributes
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
        } catch let alarmError as AlarmManager.AlarmError {
            switch alarmError {
            case .maximumLimitReached:
                throw ToolExecutionFailure.unavailable("The system alarm limit has been reached. Delete an existing alarm or timer and try again.")
            @unknown default:
                throw ToolExecutionFailure.executionFailed("AlarmKit error: \(alarmError).")
            }
        } catch {
            let nsError = error as NSError
            throw ToolExecutionFailure.executionFailed("Timer could not be created (\(nsError.domain) \(nsError.code)): \(error.localizedDescription)")
        }

        let contextBlock = """
        Timer created:
        - Title: \(displayTitle)
        - Duration: \(Self.durationDescription(totalSeconds: Int(durationSeconds.rounded())))
        """

        return MessageGroundingResult(contextBlock: contextBlock, sources: [])
    }

    private func ensureTimerAccess() async throws -> Bool {
        let state = AlarmManager.shared.authorizationState
        switch state {
        case .authorized:
            return true
        case .notDetermined:
            let result = try await AlarmManager.shared.requestAuthorization()
            return result == .authorized
        case .denied:
            return false
        @unknown default:
            return false
        }
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
