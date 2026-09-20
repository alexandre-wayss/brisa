import SwiftUI

struct PomodoroTimerView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case timer = "Timer", stats = "Stats", settings = "Settings"
        var id: String { rawValue }
    }

    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.timer
    @State private var confirmClear = false

    private var phaseColor: Color {
        switch model.pomodoroPhase {
        case .work: return accent
        case .shortBreak: return Color(red: 0.55, green: 0.75, blue: 0.95)
        case .longBreak: return Color(red: 0.75, green: 0.65, blue: 0.95)
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label("Pomodoro", systemImage: "timer")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Close Pomodoro")
            }
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            switch tab {
            case .timer: timerTab
            case .stats: statsTab
            case .settings: settingsTab
            }
        }
        .padding(26).frame(width: 460, height: 640)
    }

    // MARK: Timer

    private var timerTab: some View {
        VStack(spacing: 18) {
            TextField("What are you focusing on?", text: $model.pomodoroTask)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Current task")

            ZStack {
                Circle().stroke(phaseColor.opacity(0.15), lineWidth: 10)
                Circle().trim(from: 0, to: model.pomodoroProgress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.4), value: model.pomodoroProgress)
                VStack(spacing: 8) {
                    Image(systemName: model.pomodoroPhase.symbol)
                        .font(.system(size: 22, weight: .medium)).foregroundStyle(phaseColor)
                    Text(model.pomodoroTimeText)
                        .font(.system(size: 58, weight: .medium, design: .rounded).monospacedDigit())
                    Text(model.pomodoroPhase.title.uppercased())
                        .font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.secondary)
                }
            }
            .frame(width: 250, height: 250).padding(.top, 4)

            HStack(spacing: 7) {
                ForEach(0..<model.longBreakInterval, id: \.self) { index in
                    Circle()
                        .fill(index < model.pomodoroCycleProgress ? phaseColor : phaseColor.opacity(0.18))
                        .frame(width: 9, height: 9)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.pomodoroCycleProgress) of \(model.longBreakInterval) sessions before long break")

            HStack(spacing: 10) {
                Button { model.isPomodoroRunning ? model.pausePomodoro() : model.startPomodoro() } label: {
                    Label(model.isPomodoroRunning ? "Pause" : "Start", systemImage: model.isPomodoroRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(phaseColor).foregroundStyle(.black)
                Button("+5 min", systemImage: "plus") { model.extendPomodoro() }
                    .buttonStyle(.bordered).help("Add 5 minutes to this phase")
                Button("Skip", systemImage: "forward.fill") { model.skipPomodoro() }
                    .buttonStyle(.bordered)
                Button { model.resetPomodoro() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.bordered).help("Reset to a fresh focus session")
                    .accessibilityLabel("Reset")
            }

            VStack(spacing: 6) {
                ProgressView(value: min(Double(model.pomodoroSessionsToday.count), Double(model.pomodoroDailyGoal)), total: Double(model.pomodoroDailyGoal))
                    .tint(phaseColor)
                HStack {
                    Text("\(model.pomodoroSessionsToday.count) of \(model.pomodoroDailyGoal) sessions today")
                    Spacer()
                    Text(minutesText(model.focusMinutesToday) + " focused")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("Brisa keeps the timer running while its window is minimized and notifies you when a phase ends.")
                .font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Stats

    private var statsTab: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                statCard("Today", "\(model.pomodoroSessionsToday.count)", "sessions")
                statCard("Focus today", minutesText(model.focusMinutesToday), "")
                statCard("Streak", "\(model.pomodoroStreak)", model.pomodoroStreak == 1 ? "day" : "days")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Last 7 days").font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                let week = model.pomodoroWeek
                let peak = max(week.map(\.minutes).max() ?? 0, 1)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(week, id: \.date) { day in
                        VStack(spacing: 4) {
                            Text(day.minutes > 0 ? "\(day.minutes)" : " ").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Calendar.current.isDateInToday(day.date) ? accent : accent.opacity(0.4))
                                .frame(height: max(3, 80 * CGFloat(day.minutes) / CGFloat(peak)))
                            Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 115, alignment: .bottom)
                Text("Minutes of completed focus sessions · \(minutesText(model.totalFocusMinutes)) all time")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Recent sessions").font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                    Spacer()
                    if !model.pomodoroHistory.isEmpty {
                        Button("Clear history", role: .destructive) { confirmClear = true }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.pomodoroHistory.isEmpty {
                    Text("Finish a focus session and it will show up here.")
                        .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.pomodoroHistory.suffix(30).reversed()) { session in
                                HStack {
                                    Text(session.task.isEmpty ? "Untitled focus" : session.task)
                                        .foregroundStyle(session.task.isEmpty ? .secondary : .primary).lineLimit(1)
                                    Spacer()
                                    Text("\(session.minutes) min").monospacedDigit().foregroundStyle(.secondary)
                                    Text(session.end.formatted(.relative(presentation: .named)))
                                        .font(.caption).foregroundStyle(.tertiary).frame(width: 96, alignment: .trailing)
                                }
                                .font(.callout).padding(.vertical, 7)
                                Divider()
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .confirmationDialog("Delete all Pomodoro history?", isPresented: $confirmClear) {
            Button("Delete history", role: .destructive) { model.clearPomodoroHistory() }
        }
    }

    private func statCard(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
            Text(unit.isEmpty ? " " : unit).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Settings

    private var settingsTab: some View {
        Form {
            Section("Durations") {
                Stepper("Focus: \(model.workMinutes) min", value: $model.workMinutes, in: 1...180)
                Stepper("Short break: \(model.shortBreakMinutes) min", value: $model.shortBreakMinutes, in: 1...60)
                Stepper("Long break: \(model.longBreakMinutes) min", value: $model.longBreakMinutes, in: 1...120)
                Stepper("Long break after \(model.longBreakInterval) sessions", value: $model.longBreakInterval, in: 1...12)
            }
            Section("Routine") {
                Toggle("Start the next phase automatically", isOn: $model.autoStartPomodoro)
                Stepper("Daily goal: \(model.pomodoroDailyGoal) sessions", value: $model.pomodoroDailyGoal, in: 1...24)
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
    }

    private func minutesText(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
