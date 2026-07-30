import AlarmKit
import Foundation
import SwiftUI

nonisolated struct PlatformTimerScheduler: Sendable {
    static let isSupported = true

    func schedule(durationSeconds: TimeInterval, title: String) async throws {
        let authorized: Bool
        do {
            authorized = try await ensureTimerAccess()
        } catch {
            let nsError = error as NSError
            throw ToolExecutionFailure.executionFailed(
                "Timer authorization failed (\(nsError.domain) \(nsError.code)): \(error.localizedDescription)"
            )
        }
        guard authorized else {
            throw ToolExecutionFailure.permissionDenied(
                "Timer access is required to create a timer. Enable it in Settings → iMLX."
            )
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
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: stopButton
            ),
            countdown: AlarmPresentation.Countdown(
                title: LocalizedStringResource(stringLiteral: title),
                pauseButton: pauseButton
            ),
            paused: AlarmPresentation.Paused(
                title: LocalizedStringResource(stringLiteral: "Paused"),
                resumeButton: resumeButton
            )
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: IMLXTimerMetadata(title: title),
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
                throw ToolExecutionFailure.unavailable(
                    "The system alarm limit has been reached. Delete an existing alarm or timer and try again."
                )
            @unknown default:
                throw ToolExecutionFailure.executionFailed("AlarmKit error: \(alarmError).")
            }
        } catch {
            let nsError = error as NSError
            throw ToolExecutionFailure.executionFailed(
                "Timer could not be created (\(nsError.domain) \(nsError.code)): \(error.localizedDescription)"
            )
        }
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
}
