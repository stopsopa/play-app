import SwiftUI
import PlayLogic

/**
 * Bar at the top of the window showing whether the Decision Window is open.
 * Idle: gray. Open: orange, with the gesture state and a bar draining over the remaining time
 * (it refills on every press, because every press restarts the window).
 */
struct DecisionWindowIndicator: View {
    @ObservedObject var logic: PlayLogicController

    var body: some View {
        TimelineView(.animation(paused: logic.decisionWindowEndsAt == nil)) { context in
            let remaining = max(0, (logic.decisionWindowEndsAt ?? context.date).timeIntervalSince(context.date))
            let fraction = logic.decisionWindowDuration > 0 ? remaining / logic.decisionWindowDuration : 0
            let active = logic.gestureState != .idle

            ZStack(alignment: .leading) {
                Rectangle().fill(active ? Color.orange.opacity(0.3) : Color.gray.opacity(0.2))
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: geometry.size.width * fraction)
                }
                Text(label(remaining: remaining))
                    .font(.headline)
                    .foregroundStyle(active ? Color.black : Color.secondary)
                    .padding(.horizontal, 12)
            }
            .frame(height: 36)
        }
        .accessibilityIdentifier("decision-window-indicator")
    }

    private func label(remaining: TimeInterval) -> String {
        let left = String(format: "%.1f s", remaining)
        switch logic.gestureState {
        case .idle:
            return "Decision Window: idle"
        case .pending(.back):
            return "DECISION WINDOW ACTIVE: PENDING back (\(left))"
        case .pending(.forward):
            return "DECISION WINDOW ACTIVE: PENDING forward (\(left))"
        case .seeking:
            return "DECISION WINDOW ACTIVE: SEEKING (\(left))"
        }
    }
}

/**
 * All settings from LOGIC_FOR_PLAY.md section 2, plus "Choose folder".
 * Steppers instead of text fields on purpose: a focused text field would eat the arrow keys.
 */
struct SettingsBar: View {
    @ObservedObject var model: DemoModel
    @ObservedObject var logic: PlayLogicController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
                secondsStepper("Decision Window", value: $logic.settings.decisionWindow, id: "setting-decision-window")
                secondsStepper("Seek Step", value: $logic.settings.seekStep, id: "setting-seek-step")
                secondsStepper("Restart Threshold", value: $logic.settings.restartThreshold, id: "setting-restart-threshold")
            }
            HStack(spacing: 24) {
                Toggle("Resume when a track starts on its own", isOn: $logic.settings.resumeOnNaturalAdvance)
                    .accessibilityIdentifier("setting-resume-on-natural-advance")
                Toggle("Repeat queue", isOn: repeatAll)
                    .accessibilityIdentifier("setting-repeat-queue")
                Spacer()
                Button("Reset all Resume Points") {
                    logic.resetAllResumePoints()
                }
                .accessibilityIdentifier("reset-all-resume-points")
                Button(model.folderName == nil ? "Choose folder" : "Folder: \(model.folderName ?? "")") {
                    model.chooseFolder()
                }
                .accessibilityIdentifier("choose-folder")
            }
        }
        .padding(12)
        .focusable(false)
    }

    private var repeatAll: Binding<Bool> {
        Binding(
            get: { logic.settings.repeatMode == .all },
            set: { logic.settings.repeatMode = $0 ? .all : .off }
        )
    }

    private func secondsStepper(_ title: String, value: Binding<TimeInterval>, id: String) -> some View {
        Stepper(value: value, in: 0.5...60, step: 0.5) {
            Text("\(title): \(String(format: "%.1f", value.wrappedValue)) s")
                .monospacedDigit()
        }
        .accessibilityIdentifier(id)
    }
}

/**
 * Bottom bar: Back / Play-Pause / Forward (same calls as the keyboard keys)
 * and a clear indicator whether the song is playing or paused.
 */
struct TransportBar: View {
    @ObservedObject var logic: PlayLogicController

    var body: some View {
        HStack(spacing: 16) {
            Button {
                logic.press(.back)
            } label: {
                Label("Back (←)", systemImage: "backward.fill")
            }
            .accessibilityIdentifier("transport-back")

            Button {
                logic.togglePlayPause()
            } label: {
                Label(logic.isPlaying ? "Pause (space)" : "Play (space)", systemImage: logic.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 120)
            }
            .accessibilityIdentifier("transport-play-pause")

            Button {
                logic.press(.forward)
            } label: {
                Label("Forward (→)", systemImage: "forward.fill")
            }
            .accessibilityIdentifier("transport-forward")

            Label(logic.isPlaying ? "PLAYING" : "PAUSED", systemImage: logic.isPlaying ? "speaker.wave.2.fill" : "pause.circle")
                .font(.headline)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(logic.isPlaying ? Color.green : Color.gray, in: Capsule())
                .accessibilityIdentifier("playing-indicator")

            Spacer()

            // Current track with live position.
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                Text("\(logic.currentTrack?.title ?? "no track")   \(formatTime(logic.position)) / \(formatTime(logic.duration))")
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(12)
        .focusable(false)
    }
}
