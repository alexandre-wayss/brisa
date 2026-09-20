import SwiftUI

struct PomodoroTimerView: View {
    @ObservedObject private var themeStore = BrisaThemeStore.shared
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Label("Pomodoro", systemImage: "timer")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Close Pomodoro")
            }

            VStack(spacing: 9) {
                Image(systemName: model.pomodoroPhase.symbol)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(accent)
                Text(model.pomodoroPhase.title.uppercased())
                    .font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.secondary)
                Text(model.pomodoroTimeText)
                    .font(.system(size: 64, weight: .medium, design: .rounded).monospacedDigit())
                Text("\(model.completedPomodoros) focus sessions completed")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 25)
            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))

            HStack(spacing: 12) {
                Button { model.isPomodoroRunning ? model.pausePomodoro() : model.startPomodoro() } label: {
                    Label(model.isPomodoroRunning ? "Pause" : "Start", systemImage: model.isPomodoroRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(accent).foregroundStyle(onAccent)
                Button("Skip", systemImage: "forward.fill") { model.skipPomodoro() }
                    .buttonStyle(.bordered)
                Button("Reset", systemImage: "arrow.counterclockwise") { model.resetPomodoro() }
                    .buttonStyle(.bordered)
            }

            Form {
                Section("Durations") {
                    Stepper("Focus: \(model.workMinutes) min", value: $model.workMinutes, in: 1...180)
                    Stepper("Short break: \(model.shortBreakMinutes) min", value: $model.shortBreakMinutes, in: 1...60)
                    Stepper("Long break: \(model.longBreakMinutes) min", value: $model.longBreakMinutes, in: 1...120)
                    Stepper("Long break after \(model.longBreakInterval) sessions", value: $model.longBreakInterval, in: 1...12)
                }
                Section("Ambient sound") {
                    Toggle("Change soundscape with each phase", isOn: $model.changesSoundscapeWithPomodoro)
                    if model.changesSoundscapeWithPomodoro {
                        ForEach(PomodoroPhase.allCases, id: \.self) { phase in
                            Picker("\(phase.title) sound", selection: Binding(
                                get: { model.pomodoroSoundID(for: phase) },
                                set: { model.setPomodoroSoundID($0, for: phase) }
                            )) {
                                Text("Suggested soundscape").tag("")
                                ForEach(model.availableLibrary) { sound in
                                    Label(sound.name, systemImage: sound.icon).tag(sound.id)
                                }
                            }
                        }
                        HStack {
                            Text("Default volume")
                            Slider(value: $model.pomodoroSoundVolume, in: 0...1)
                            Text("\(Int(model.pomodoroSoundVolume * 100))%")
                                .monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                        }
                        Button("Apply \(model.pomodoroPhase.title) soundscape now") { model.applyPomodoroSoundscape() }
                    }
                }
            }
            .formStyle(.grouped)
            Text("Brisa keeps the active timer running while its window is minimized. You’ll receive a desktop notification when a phase ends.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(26).frame(width: 460)
    }
}
