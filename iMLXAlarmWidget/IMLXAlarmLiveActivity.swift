import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

struct IMLXAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<IMLXTimerMetadata>.self) { context in
            TimerLockScreenView(
                title: context.attributes.metadata?.title ?? "Timer",
                presentation: context.attributes.presentation,
                state: context.state,
                tint: context.attributes.tintColor
            )
            .activityBackgroundTint(TimerPalette.background)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimerIslandTitle(
                        title: context.attributes.metadata?.title ?? "Timer",
                        tint: context.attributes.tintColor
                    )
                }

                DynamicIslandExpandedRegion(.trailing) {
                    TimerCountdownText(mode: context.state.mode)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 116, alignment: .trailing)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    TimerIslandBottomView(
                        presentation: context.attributes.presentation,
                        state: context.state,
                        tint: context.attributes.tintColor
                    )
                }
            } compactLeading: {
                Image(systemName: timerSymbol(for: context.state.mode))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                TimerCountdownText(mode: context.state.mode)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 52, alignment: .trailing)
            } minimal: {
                TimerCircularProgress(
                    mode: context.state.mode,
                    tint: context.attributes.tintColor
                )
            }
            .keylineTint(context.attributes.tintColor)
        }
    }

    private func timerSymbol(for mode: AlarmPresentationState.Mode) -> String {
        switch mode {
        case .paused:
            "pause.fill"
        default:
            "timer"
        }
    }
}

private struct TimerLockScreenView: View {
    let title: String
    let presentation: AlarmPresentation
    let state: AlarmPresentationState
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimerHeader(title: title, mode: state.mode, tint: tint)

            HStack(alignment: .center, spacing: 16) {
                TimerCountdownText(mode: state.mode)
                    .font(.system(size: 52, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TimerControls(
                    presentation: presentation,
                    state: state,
                    tint: tint,
                    style: .lockScreen
                )
            }

            TimerLinearProgress(mode: state.mode, tint: tint)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            LinearGradient(
                colors: [
                    tint.opacity(0.10),
                    TimerPalette.background.opacity(0.96),
                    TimerPalette.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct TimerHeader: View {
    let title: String
    let mode: AlarmPresentationState.Mode
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: Circle())

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            if case .paused = mode {
                Label("Paused", systemImage: "pause.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct TimerCountdownText: View {
    let mode: AlarmPresentationState.Mode

    var body: some View {
        switch mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now ... countdown.fireDate, countsDown: true)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

        case .paused(let paused):
            Text(remainingDuration(for: paused).formatted(.time(pattern: durationPattern(for: paused))))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

        default:
            Text(verbatim: "—:—")
                .monospacedDigit()
        }
    }

    private func remainingDuration(
        for paused: AlarmPresentationState.Mode.Paused
    ) -> Duration {
        .seconds(max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration))
    }

    private func durationPattern(
        for paused: AlarmPresentationState.Mode.Paused
    ) -> Duration.TimeFormatStyle.Pattern {
        remainingDuration(for: paused) > .seconds(60 * 60)
            ? .hourMinuteSecond
            : .minuteSecond
    }
}

private struct TimerLinearProgress: View {
    let mode: AlarmPresentationState.Mode
    let tint: Color

    var body: some View {
        switch mode {
        case .countdown(let countdown):
            ProgressView(
                timerInterval: countdown.startDate ... countdown.fireDate,
                countsDown: true
            )
            .labelsHidden()
            .tint(tint)

        case .paused(let paused):
            ProgressView(
                value: max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration),
                total: max(1, paused.totalCountdownDuration)
            )
            .labelsHidden()
            .tint(.orange)

        default:
            EmptyView()
        }
    }
}

private struct TimerIslandTitle: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.18), in: Circle())

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

private struct TimerIslandBottomView: View {
    let presentation: AlarmPresentation
    let state: AlarmPresentationState
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            TimerLinearProgress(mode: state.mode, tint: tint)
                .frame(maxWidth: .infinity)

            TimerControls(
                presentation: presentation,
                state: state,
                tint: tint,
                style: .dynamicIsland
            )
        }
        .padding(.top, 10)
    }
}

private struct TimerCircularProgress: View {
    let mode: AlarmPresentationState.Mode
    let tint: Color

    var body: some View {
        switch mode {
        case .countdown(let countdown):
            ProgressView(
                timerInterval: countdown.startDate ... countdown.fireDate,
                countsDown: true
            ) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: "timer")
                    .font(.caption2.weight(.bold))
            }
            .progressViewStyle(.circular)
            .tint(tint)
            .foregroundStyle(tint)

        case .paused(let paused):
            ProgressView(
                value: max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration),
                total: max(1, paused.totalCountdownDuration)
            ) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: "pause.fill")
                    .font(.caption2.weight(.bold))
            }
            .progressViewStyle(.circular)
            .tint(.orange)
            .foregroundStyle(.orange)

        default:
            Image(systemName: "timer")
                .foregroundStyle(tint)
        }
    }
}

private struct TimerControls: View {
    enum Style {
        case lockScreen
        case dynamicIsland

        var buttonSize: CGFloat {
            switch self {
            case .lockScreen: 46
            case .dynamicIsland: 36
            }
        }

        var spacing: CGFloat {
            switch self {
            case .lockScreen: 10
            case .dynamicIsland: 8
            }
        }
    }

    let presentation: AlarmPresentation
    let state: AlarmPresentationState
    let tint: Color
    let style: Style

    var body: some View {
        HStack(spacing: style.spacing) {
            switch state.mode {
            case .countdown:
                if let pauseButton = presentation.countdown?.pauseButton {
                    TimerControlButton(
                        config: pauseButton,
                        intent: PauseIntent(alarmID: state.alarmID.uuidString),
                        foreground: .orange,
                        background: Color.white.opacity(0.10),
                        size: style.buttonSize
                    )
                }

            case .paused:
                if let resumeButton = presentation.paused?.resumeButton {
                    TimerControlButton(
                        config: resumeButton,
                        intent: ResumeIntent(alarmID: state.alarmID.uuidString),
                        foreground: tint,
                        background: tint.opacity(0.16),
                        size: style.buttonSize
                    )
                }

            default:
                EmptyView()
            }

            TimerControlButton(
                config: AlarmButton(
                    text: "Stop",
                    textColor: .white,
                    systemImageName: "xmark"
                ),
                intent: StopIntent(alarmID: state.alarmID.uuidString),
                foreground: .red,
                background: Color.red.opacity(0.16),
                size: style.buttonSize
            )
        }
    }
}

private struct TimerControlButton<Intent: AppIntent>: View {
    let config: AlarmButton
    let intent: Intent
    let foreground: Color
    let background: Color
    let size: CGFloat

    var body: some View {
        Button(intent: intent) {
            Label(config.text, systemImage: config.systemImageName)
                .font(.body.weight(.semibold))
                .labelStyle(.iconOnly)
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(config.text))
    }
}

private enum TimerPalette {
    static let background = Color(red: 0.018, green: 0.024, blue: 0.045)
}

struct PauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause"
    @Parameter(title: "alarmID") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try AlarmManager.shared.pause(id: id)
        }
        return .result()
    }
}

struct ResumeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume"
    @Parameter(title: "alarmID") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try AlarmManager.shared.resume(id: id)
        }
        return .result()
    }
}

struct StopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop"
    @Parameter(title: "alarmID") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try AlarmManager.shared.stop(id: id)
        }
        return .result()
    }
}
