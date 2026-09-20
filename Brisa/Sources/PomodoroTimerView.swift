import SwiftUI

/// Full-page Pomodoro: a timer hero on the left, today's progress, history and settings on the right.
struct PomodoroTimerView: View {
    @ObservedObject var model: AppModel
    @State private var confirmClear = false
    @State private var showSettings = false
    @State private var editingTime = false
    @State private var minutesInput = ""

    private var phaseColor: Color {
        switch model.pomodoroPhase {
        case .work: return accent
        case .shortBreak: return Color(red: 0.55, green: 0.75, blue: 0.95)
        case .longBreak: return Color(red: 0.75, green: 0.65, blue: 0.95)
        }
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 22) {
                timerHero.frame(minWidth: 400)
                VStack(spacing: 16) {
                    todayCard
                    weekCard
                    historyCard
                    settingsCard
                }
                .frame(width: 340)
            }
            .padding(.horizontal, 34).padding(.bottom, 18).padding(.top, 4)
        }
        .confirmationDialog("Delete all Pomodoro history?", isPresented: $confirmClear) {
            Button("Delete history", role: .destructive) { model.clearPomodoroHistory() }
        }
    }

    // MARK: Hero

    private var timerHero: some View {
        VStack(spacing: 22) {
            HStack(spacing: 6) {
                ForEach(PomodoroPhase.allCases, id: \.self) { phase in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { model.selectPomodoroPhase(phase) } } label: {
                        Label(phase.title, systemImage: phase.symbol)
                            .font(.system(size: 12, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 8)
                            .background(model.pomodoroPhase == phase ? phaseColor : .white.opacity(0.07), in: Capsule())
                            .foregroundStyle(model.pomodoroPhase == phase ? Color.black.opacity(0.82) : .primary)
                    }
                    .buttonStyle(.plain).disabled(model.isPomodoroRunning && model.pomodoroPhase != phase)
                }
            }

            ZStack {
                Circle().fill(phaseColor.opacity(model.isPomodoroRunning ? 0.16 : 0.08)).blur(radius: 50).frame(width: 300, height: 300)
                Circle().stroke(.white.opacity(0.07), lineWidth: 12)
                Circle().trim(from: 0, to: model.pomodoroProgress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.4), value: model.pomodoroProgress)
                VStack(spacing: 6) {
                    Button {
                        minutesInput = "\(model.pomodoroTotalSeconds / 60)"
                        editingTime = true
                    } label: {
                        Text(model.pomodoroTimeText)
                            .font(.system(size: 76, weight: .light, design: .rounded).monospacedDigit())
                    }
                    .buttonStyle(.plain).help("Click to set the time")
                    .accessibilityLabel("Time remaining \(model.pomodoroTimeText). Click to change.")
                    .popover(isPresented: $editingTime, arrowEdge: .bottom) { timeEditor }
                    Text(model.isPomodoroRunning ? "In progress" : "Ready")
                        .font(.caption.weight(.bold)).tracking(1.6).textCase(.uppercase).foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        ForEach(0..<model.longBreakInterval, id: \.self) { index in
                            Circle().fill(index < model.pomodoroCycleProgress ? phaseColor : .white.opacity(0.15)).frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(model.pomodoroCycleProgress) of \(model.longBreakInterval) sessions before long break")
                }
            }
            .frame(width: 290, height: 290)

            HStack(spacing: 8) {
                Image(systemName: "text.cursor").foregroundStyle(.secondary)
                TextField("What are you focusing on?", text: $model.pomodoroTask).textFieldStyle(.plain)
                    .accessibilityLabel("Current task")
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(.white.opacity(0.06), in: Capsule()).frame(maxWidth: 340)

            HStack(spacing: 12) {
                roundButton("arrow.counterclockwise", "Reset") { model.resetPomodoro() }
                roundButton("minus", "Remove 5 minutes") { model.extendPomodoro(minutes: -5) }
                Button { model.isPomodoroRunning ? model.pausePomodoro() : model.startPomodoro() } label: {
                    Label(model.isPomodoroRunning ? "Pause" : "Start", systemImage: model.isPomodoroRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 120, height: 46).background(phaseColor, in: Capsule())
                        .foregroundStyle(Color.black.opacity(0.85))
                }
                .buttonStyle(.plain)
                roundButton("forward.fill", "Skip phase") { model.skipPomodoro() }
                roundButton("plus", "Add 5 minutes") { model.extendPomodoro() }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 20)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22))
    }

    private var timeEditor: some View {
        let range = model.pomodoroMinutesRange
        func apply() {
            if let value = Int(minutesInput.trimmingCharacters(in: .whitespaces)) { model.setPomodoroMinutes(value) }
            editingTime = false
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(model.pomodoroPhase.title) length").font(.headline)
            HStack(spacing: 6) {
                TextField("min", text: $minutesInput).textFieldStyle(.roundedBorder).frame(width: 64).multilineTextAlignment(.trailing)
                    .onSubmit(apply)
                Text("min").foregroundStyle(.secondary)
                Spacer()
                Button("Set", action: apply).keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 6) {
                ForEach([5, 10, 15, 25, 45, 60].filter { range.contains($0) }, id: \.self) { preset in
                    Button("\(preset)") { model.setPomodoroMinutes(preset); editingTime = false }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            Text("Applies now and becomes the default for this phase.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 260)
    }

    private func roundButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .frame(width: 46, height: 46).background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    // MARK: Cards

    private func card<Content: View>(_ title: String, @ViewBuilder trailing: () -> some View = { EmptyView() }, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.caption.weight(.bold)).tracking(1.2).textCase(.uppercase).foregroundStyle(.secondary)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }

    private var todayCard: some View {
        let done = model.pomodoroSessionsToday.count
        return card("Today") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(done)").font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                Text("of \(model.pomodoroDailyGoal) sessions").font(.callout).foregroundStyle(.secondary)
            }
            ProgressView(value: min(Double(done), Double(model.pomodoroDailyGoal)), total: Double(model.pomodoroDailyGoal)).tint(accent)
            HStack {
                miniStat("clock", minutesText(model.focusMinutesToday), "focused")
                Divider().frame(height: 26)
                miniStat("flame.fill", "\(model.pomodoroStreak)", model.pomodoroStreak == 1 ? "day streak" : "day streak")
                Divider().frame(height: 26)
                miniStat("sum", minutesText(model.totalFocusMinutes), "all time")
            }
        }
    }

    private func miniStat(_ symbol: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Label(value, systemImage: symbol).font(.system(size: 14, weight: .semibold).monospacedDigit()).labelStyle(.titleAndIcon)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekCard: some View {
        let week = model.pomodoroWeek
        let peak = max(week.map(\.minutes).max() ?? 0, 1)
        return card("Last 7 days") {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(week, id: \.date) { day in
                    VStack(spacing: 4) {
                        Text(day.minutes > 0 ? "\(day.minutes)" : " ").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Calendar.current.isDateInToday(day.date) ? accent : accent.opacity(0.35))
                            .frame(height: max(3, 64 * CGFloat(day.minutes) / CGFloat(peak)))
                        Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 100, alignment: .bottom)
        }
    }

    private var historyCard: some View {
        card("Recent sessions", trailing: {
            if !model.pomodoroHistory.isEmpty {
                Button("Clear") { confirmClear = true }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }) {
            if model.pomodoroHistory.isEmpty {
                Text("Finish a focus session and it will show up here.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.pomodoroHistory.suffix(5).reversed())) { session in
                        HStack {
                            Text(session.task.isEmpty ? "Untitled focus" : session.task)
                                .foregroundStyle(session.task.isEmpty ? .secondary : .primary).lineLimit(1)
                            Spacer()
                            Text("\(session.minutes) min").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout).padding(.vertical, 6)
                        if session.id != model.pomodoroHistory.suffix(5).first?.id { Divider().opacity(0.4) }
                    }
                }
            }
        }
    }

    private var settingsCard: some View {
        card("Settings", trailing: {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() } } label: {
                Image(systemName: showSettings ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(showSettings ? "Hide settings" : "Show settings")
        }) {
            if showSettings {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper("Focus: \(model.workMinutes) min", value: $model.workMinutes, in: 1...180)
                    Stepper("Short break: \(model.shortBreakMinutes) min", value: $model.shortBreakMinutes, in: 1...60)
                    Stepper("Long break: \(model.longBreakMinutes) min", value: $model.longBreakMinutes, in: 1...120)
                    Stepper("Long break every \(model.longBreakInterval) sessions", value: $model.longBreakInterval, in: 1...12)
                    Stepper("Daily goal: \(model.pomodoroDailyGoal) sessions", value: $model.pomodoroDailyGoal, in: 1...24)
                    Toggle("Auto-start the next phase", isOn: $model.autoStartPomodoro)
                    Divider().opacity(0.4)
                    Toggle("Change soundscape per phase", isOn: $model.changesSoundscapeWithPomodoro)
                    if model.changesSoundscapeWithPomodoro {
                        ForEach(PomodoroPhase.allCases, id: \.self) { phase in
                            Picker(phase.title, selection: Binding(
                                get: { model.pomodoroSoundID(for: phase) },
                                set: { model.setPomodoroSoundID($0, for: phase) }
                            )) {
                                Text("Suggested").tag("")
                                ForEach(model.availableLibrary) { sound in
                                    Label(sound.name, systemImage: sound.icon).tag(sound.id)
                                }
                            }
                        }
                        HStack {
                            Text("Volume")
                            Slider(value: $model.pomodoroSoundVolume, in: 0...1)
                            Text("\(Int(model.pomodoroSoundVolume * 100))%")
                                .monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                        }
                        Button("Apply \(model.pomodoroPhase.title) sound now") { model.applyPomodoroSoundscape() }
                    }
                }
                .font(.callout)
            } else {
                Text("\(model.workMinutes)/\(model.shortBreakMinutes)/\(model.longBreakMinutes) min · long break every \(model.longBreakInterval)")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func minutesText(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
