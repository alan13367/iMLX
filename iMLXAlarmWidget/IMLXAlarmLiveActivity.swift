import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

struct IMLXAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<IMLXTimerMetadata>.self) { context in
            lockScreenView(attributes: context.attributes, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    title(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    bottomView(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                countdown(state: context.state, maxWidth: 44)
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                progressView(mode: context.state.mode, tint: context.attributes.tintColor)
            } minimal: {
                progressView(mode: context.state.mode, tint: context.attributes.tintColor)
            }
            .keylineTint(context.attributes.tintColor)
        }
    }

    private func lockScreenView(attributes: AlarmAttributes<IMLXTimerMetadata>, state: AlarmPresentationState) -> some View {
        VStack(alignment: .leading) {
            title(attributes: attributes, state: state)
            bottomView(attributes: attributes, state: state)
        }
        .padding(.all, 12)
    }

    private func bottomView(attributes: AlarmAttributes<IMLXTimerMetadata>, state: AlarmPresentationState) -> some View {
        HStack {
            countdown(state: state, maxWidth: 150)
                .font(.system(size: 40, design: .rounded))
            Spacer()
            controls(presentation: attributes.presentation, state: state)
        }
    }

    private func countdown(state: AlarmPresentationState, maxWidth: CGFloat = .infinity) -> some View {
        Group {
            switch state.mode {
            case .countdown(let countdown):
                Text(timerInterval: Date.now ... countdown.fireDate, countsDown: true)
            case .paused(let paused):
                let remaining = Duration.seconds(paused.totalCountdownDuration - paused.previouslyElapsedDuration)
                let pattern: Duration.TimeFormatStyle.Pattern = remaining > .seconds(60 * 60) ? .hourMinuteSecond : .minuteSecond
                Text(remaining.formatted(.time(pattern: pattern)))
            default:
                EmptyView()
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private func progressView(mode: AlarmPresentationState.Mode, tint: Color) -> some View {
        Group {
            switch mode {
            case .countdown(let countdown):
                ProgressView(timerInterval: Date.now ... countdown.fireDate, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: "timer").scaleEffect(0.9)
                }
            case .paused(let paused):
                let remaining = paused.totalCountdownDuration - paused.previouslyElapsedDuration
                ProgressView(value: remaining, total: paused.totalCountdownDuration) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: "pause.fill").scaleEffect(0.8)
                }
            default:
                EmptyView()
            }
        }
        .progressViewStyle(.circular)
        .foregroundStyle(tint)
        .tint(tint)
    }

    @ViewBuilder
    private func title(attributes: AlarmAttributes<IMLXTimerMetadata>, state: AlarmPresentationState) -> some View {
        let resource: LocalizedStringResource? = switch state.mode {
        case .countdown: attributes.presentation.countdown?.title
        case .paused: attributes.presentation.paused?.title
        default: nil
        }
        Text(resource ?? attributes.presentation.alert.title)
            .font(.title3)
            .fontWeight(.semibold)
            .lineLimit(1)
    }

    private func controls(presentation: AlarmPresentation, state: AlarmPresentationState) -> some View {
        HStack(spacing: 4) {
            switch state.mode {
            case .countdown:
                if let pauseButton = presentation.countdown?.pauseButton {
                    button(config: pauseButton, intent: PauseIntent(alarmID: state.alarmID.uuidString), tint: .orange)
                }
            case .paused:
                if let resumeButton = presentation.paused?.resumeButton {
                    button(config: resumeButton, intent: ResumeIntent(alarmID: state.alarmID.uuidString), tint: .orange)
                }
            default:
                EmptyView()
            }
            button(config: presentation.alert.stopButton, intent: StopIntent(alarmID: state.alarmID.uuidString), tint: .red)
        }
    }

    private func button<I: AppIntent>(config: AlarmButton, intent: I, tint: Color) -> some View {
        Button(intent: intent) {
            Label(config.text, systemImage: config.systemImageName)
                .lineLimit(1)
        }
        .tint(tint)
        .buttonStyle(.borderedProminent)
        .frame(width: 96, height: 30)
    }
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
