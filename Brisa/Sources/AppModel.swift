import Foundation
import Combine
import UserNotifications

enum PomodoroPhase: String, CaseIterable, Codable {
    case work
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    var symbol: String {
        switch self {
        case .work: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "leaf.fill"
        }
    }
}

struct PomodoroSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var end: Date
    var task: String
    var minutes: Int
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    let inputSounds = InputSounds()

    @Published var levels: [String: Double] = [:]
    @Published var favorites: Set<String> = []
    @Published var mixes: [Mix] = []
    @Published var importedSounds: [ImportedSound] = []
    @Published var isPlaying = false
    @Published var masterVolume = (UserDefaults.standard.object(forKey: "masterVolume") as? Double) ?? 0.65 {
        didSet { UserDefaults.standard.set(masterVolume, forKey: "masterVolume") }
    }
    @Published var remainingSeconds = 0
    @Published var error: String?
    @Published var pomodoroPhase: PomodoroPhase = .work { didSet { persistPomodoro() } }
    @Published var pomodoroRemainingSeconds = 25 * 60 { didSet { persistPomodoro() } }
    @Published var isPomodoroRunning = false { didSet { persistPomodoro() } }
    @Published var completedPomodoros = 0 { didSet { persistPomodoro() } }
    @Published var workMinutes = 25 { didSet { let valid = min(max(workMinutes, 1), 180); if valid != workMinutes { workMinutes = valid } else { syncIdlePomodoro(); persistPomodoro() } } }
    @Published var shortBreakMinutes = 5 { didSet { let valid = min(max(shortBreakMinutes, 1), 60); if valid != shortBreakMinutes { shortBreakMinutes = valid } else { syncIdlePomodoro(); persistPomodoro() } } }
    @Published var longBreakMinutes = 15 { didSet { let valid = min(max(longBreakMinutes, 1), 120); if valid != longBreakMinutes { longBreakMinutes = valid } else { syncIdlePomodoro(); persistPomodoro() } } }
    @Published var longBreakInterval = 4 { didSet { let valid = min(max(longBreakInterval, 1), 12); if valid != longBreakInterval { longBreakInterval = valid } else { persistPomodoro() } } }
    @Published var pomodoroTotalSeconds = 25 * 60
    @Published var pomodoroTask = "" { didSet { persistPomodoro() } }
    @Published var autoStartPomodoro = false { didSet { persistPomodoro() } }
    @Published var pomodoroDailyGoal = 8 { didSet { let valid = min(max(pomodoroDailyGoal, 1), 24); if valid != pomodoroDailyGoal { pomodoroDailyGoal = valid } else { persistPomodoro() } } }
    @Published var pomodoroHistory: [PomodoroSession] = [] { didSet { persistPomodoroHistory() } }
    @Published var changesSoundscapeWithPomodoro = false { didSet { persistPomodoro() } }
    @Published var pomodoroSoundIDs: [String: String] = [:] { didSet { persistPomodoro() } }
    @Published var pomodoroSoundVolume = 0.05 { didSet { let valid = min(max(pomodoroSoundVolume, 0), 1); if valid != pomodoroSoundVolume { pomodoroSoundVolume = valid } else { persistPomodoro() } } }

    private var volumeBeforeMute = 0.65
    private let audio = AudioBank()
    private var timer: Timer?
    private var pomodoroEndDate: Date?
    private var isRestoringPomodoro = false

    init() {
        levels = UserDefaults.standard.dictionary(forKey: "levels") as? [String: Double] ?? [:]
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        if let data = UserDefaults.standard.data(forKey: "mixes"),
           let savedMixes = try? JSONDecoder().decode([Mix].self, from: data) {
            mixes = savedMixes
        }
        if let data = UserDefaults.standard.data(forKey: "importedSounds"),
           let savedSounds = try? JSONDecoder().decode([ImportedSound].self, from: data) {
            importedSounds = savedSounds
        }
        audio.importedURL = { [weak self] id in self?.importedSounds.first(where: { $0.id == id }).flatMap { $0.storedFile }.map(URL.init(fileURLWithPath:)) }
        volumeBeforeMute = masterVolume > 0 ? masterVolume : 0.65
        restorePomodoro()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor [weak model] in model?.tickTimer() }
        }
        synchronizeAudio()
    }

    func toggle(_ soundID: String) {
        if levels[soundID] != nil { levels.removeValue(forKey: soundID) }
        else { levels[soundID] = 0.05; isPlaying = true }
        if levels.isEmpty { isPlaying = false }
        synchronizeAudio()
    }

    func togglePlayback() {
        if levels.isEmpty { levels["rain"] = 0.05 }
        isPlaying.toggle()
        synchronizeAudio()
    }

    func setFavorite(_ soundID: String) {
        if favorites.contains(soundID) { favorites.remove(soundID) }
        else { favorites.insert(soundID) }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
    }

    func applyMix(_ levels: [String: Double]) { self.levels = levels; isPlaying = true; synchronizeAudio() }
    func replaceWith(_ sound: Sound) { levels = [sound.id: 0.05]; isPlaying = true; synchronizeAudio() }
    func saveMix(named name: String) { mixes.append(Mix(name: name, levels: levels)); persistMixes() }
    func persistMixes() { if let data = try? JSONEncoder().encode(mixes) { UserDefaults.standard.set(data, forKey: "mixes") } }
    func persistImportedSounds() { if let data = try? JSONEncoder().encode(importedSounds) { UserDefaults.standard.set(data, forKey: "importedSounds") } }

    var availableLibrary: [Sound] { library + importedSounds.map(\.sound) }

    func importLocalFile(_ url: URL, attribution: String = "", license: String = "") throws {
        guard ImportedSoundStore.isSupported(url) else { throw AudioImportError.unsupportedFormat }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= ImportedSoundStore.maximumFileSize else { throw AudioImportError.fileTooLarge }
        try ImportedSoundStore.prepareDirectory()
        let id = "imported-\(UUID().uuidString)"
        let destination = ImportedSoundStore.makeStoredURL(id: id, sourceURL: url)
        try FileManager.default.copyItem(at: url, to: destination)
        let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        importedSounds.append(ImportedSound(id: id, name: url.deletingPathExtension().lastPathComponent, source: .localFile,
                                            originalURL: url.absoluteString, storedFile: destination.path, bookmark: bookmark,
                                            attribution: attribution, license: license, importedAt: .now, unavailableReason: nil))
        persistImportedSounds()
    }

    func importExternalURL(_ rawURL: String, attribution: String = "", license: String = "") async throws {
        guard let url = URL(string: rawURL), url.scheme?.lowercased() == "https" else { throw AudioImportError.invalidURL }
        if ImportedSoundStore.isYouTube(url) {
            importYouTubeLink(url, attribution: attribution, license: license)
            return
        }
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), http.url?.scheme?.lowercased() == "https" else { throw AudioImportError.downloadFailed }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let resolvedExtension = ImportedSoundStore.isSupported(http.url ?? url) ? (http.url ?? url).pathExtension.lowercased() : ImportedSoundStore.fileExtension(for: contentType)
        guard let resolvedExtension, ImportedSoundStore.supportedExtensions.contains(resolvedExtension),
              ImportedSoundStore.fileExtension(for: contentType) != nil || (contentType.split(separator: ";").first == "application/octet-stream" && ImportedSoundStore.isSupported(http.url ?? url)) else { throw AudioImportError.unsafeResponse }
        let size = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= ImportedSoundStore.maximumFileSize else { throw AudioImportError.fileTooLarge }
        try ImportedSoundStore.prepareDirectory()
        let id = "imported-\(UUID().uuidString)"
        let destination = ImportedSoundStore.makeStoredURL(id: id, sourceURL: URL(fileURLWithPath: "audio.\(resolvedExtension)"))
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        let fallbackName = url.deletingPathExtension().lastPathComponent
        importedSounds.append(ImportedSound(id: id, name: fallbackName.isEmpty ? "External audio" : fallbackName, source: .externalURL,
                                            originalURL: url.absoluteString, storedFile: destination.path, bookmark: nil,
                                            attribution: attribution, license: license, importedAt: .now, unavailableReason: nil))
        persistImportedSounds()
    }

    private func importYouTubeLink(_ url: URL, attribution: String, license: String) {
        let id = "imported-\(UUID().uuidString)"
        importedSounds.append(ImportedSound(id: id, name: "YouTube source", source: .youtube, originalURL: url.absoluteString,
                                            storedFile: nil, bookmark: nil, attribution: attribution, license: license, importedAt: .now,
                                            unavailableReason: "YouTube link saved — import an authorized audio file to play it."))
        persistImportedSounds()
    }

    func removeImportedSound(_ sound: ImportedSound) {
        levels.removeValue(forKey: sound.id)
        audio.discardBuffer(for: sound.id)
        if let path = sound.storedFile { try? FileManager.default.removeItem(atPath: path) }
        importedSounds.removeAll { $0.id == sound.id }
        persistImportedSounds(); synchronizeAudio()
    }

    func relink(_ sound: ImportedSound, to url: URL) throws {
        guard ImportedSoundStore.isSupported(url) else { throw AudioImportError.unsupportedFormat }
        guard let index = importedSounds.firstIndex(where: { $0.id == sound.id }) else { return }
        try ImportedSoundStore.prepareDirectory()
        let destination = ImportedSoundStore.makeStoredURL(id: sound.id, sourceURL: url)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        importedSounds[index].storedFile = destination.path
        importedSounds[index].bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        importedSounds[index].unavailableReason = nil
        audio.discardBuffer(for: sound.id); persistImportedSounds()
    }

    func toggleMute() {
        if masterVolume > 0 { volumeBeforeMute = masterVolume; masterVolume = 0 }
        else { masterVolume = volumeBeforeMute }
        synchronizeAudio()
    }

    var pomodoroDurationSeconds: Int {
        switch pomodoroPhase {
        case .work: return workMinutes * 60
        case .shortBreak: return shortBreakMinutes * 60
        case .longBreak: return longBreakMinutes * 60
        }
    }

    var pomodoroProgress: Double {
        guard pomodoroTotalSeconds > 0 else { return 0 }
        return min(max(1 - Double(pomodoroRemainingSeconds) / Double(pomodoroTotalSeconds), 0), 1)
    }

    /// Focus sessions finished in the current long-break cycle (drives the dots).
    var pomodoroCycleProgress: Int {
        pomodoroPhase == .longBreak ? longBreakInterval : completedPomodoros % longBreakInterval
    }

    var pomodoroSessionsToday: [PomodoroSession] {
        pomodoroHistory.filter { Calendar.current.isDateInToday($0.end) }
    }

    var focusMinutesToday: Int { pomodoroSessionsToday.reduce(0) { $0 + $1.minutes } }
    var totalFocusMinutes: Int { pomodoroHistory.reduce(0) { $0 + $1.minutes } }

    /// Consecutive days with at least one focus session, counting back from today (or yesterday if today is still empty).
    var pomodoroStreak: Int {
        let calendar = Calendar.current
        let days = Set(pomodoroHistory.map { calendar.startOfDay(for: $0.end) })
        var day = calendar.startOfDay(for: Date())
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? .distantPast
        }
        return streak
    }

    /// Focus minutes per day for the last 7 days, oldest first.
    var pomodoroWeek: [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let minutes = pomodoroHistory.filter { calendar.isDate($0.end, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
            return (day, minutes)
        }
    }

    func clearPomodoroHistory() { pomodoroHistory = [] }

    var pomodoroTimeText: String {
        String(format: "%02d:%02d", max(0, pomodoroRemainingSeconds) / 60, max(0, pomodoroRemainingSeconds) % 60)
    }

    func startPomodoro() {
        if pomodoroRemainingSeconds <= 0 {
            pomodoroTotalSeconds = pomodoroDurationSeconds
            pomodoroRemainingSeconds = pomodoroTotalSeconds
        }
        pomodoroEndDate = Date().addingTimeInterval(TimeInterval(pomodoroRemainingSeconds))
        isPomodoroRunning = true
        persistPomodoro()
    }

    func pausePomodoro() {
        updatePomodoroRemaining()
        pomodoroEndDate = nil
        isPomodoroRunning = false
        persistPomodoro()
    }

    func resetPomodoro() {
        pomodoroEndDate = nil
        isPomodoroRunning = false
        pomodoroPhase = .work
        pomodoroTotalSeconds = workMinutes * 60
        pomodoroRemainingSeconds = pomodoroTotalSeconds
        persistPomodoro()
    }

    func selectPomodoroPhase(_ phase: PomodoroPhase) {
        guard !isPomodoroRunning, phase != pomodoroPhase else { return }
        pomodoroPhase = phase
        pomodoroTotalSeconds = pomodoroDurationSeconds
        pomodoroRemainingSeconds = pomodoroTotalSeconds
        persistPomodoro()
    }

    var pomodoroMinutesRange: ClosedRange<Int> {
        switch pomodoroPhase {
        case .work: return 1...180
        case .shortBreak: return 1...60
        case .longBreak: return 1...120
        }
    }

    /// Sets the length of the current phase; also becomes the default for that phase.
    func setPomodoroMinutes(_ minutes: Int) {
        let valid = min(max(minutes, pomodoroMinutesRange.lowerBound), pomodoroMinutesRange.upperBound)
        switch pomodoroPhase {
        case .work: workMinutes = valid
        case .shortBreak: shortBreakMinutes = valid
        case .longBreak: longBreakMinutes = valid
        }
        pomodoroTotalSeconds = valid * 60
        pomodoroRemainingSeconds = valid * 60
        if isPomodoroRunning { pomodoroEndDate = Date().addingTimeInterval(TimeInterval(valid * 60)) }
        persistPomodoro()
    }

    func extendPomodoro(minutes: Int = 5) {
        let extra = max(minutes * 60, 60 - pomodoroRemainingSeconds)
        pomodoroTotalSeconds += extra
        pomodoroRemainingSeconds += extra
        pomodoroEndDate = pomodoroEndDate?.addingTimeInterval(TimeInterval(extra))
        persistPomodoro()
    }

    private func syncIdlePomodoro() {
        guard !isRestoringPomodoro, !isPomodoroRunning, pomodoroRemainingSeconds == pomodoroTotalSeconds else { return }
        pomodoroTotalSeconds = pomodoroDurationSeconds
        pomodoroRemainingSeconds = pomodoroTotalSeconds
    }

    func skipPomodoro() {
        advancePomodoro(completed: false)
    }

    func applyPomodoroSoundscape() {
        guard changesSoundscapeWithPomodoro else { return }
        if let soundID = pomodoroSoundIDs[pomodoroPhase.rawValue], !soundID.isEmpty {
            applyMix([soundID: pomodoroSoundVolume])
            return
        }
        switch pomodoroPhase {
        case .work: applyMix(["brown": pomodoroSoundVolume, "rain": pomodoroSoundVolume])
        case .shortBreak: applyMix(["ocean": pomodoroSoundVolume, "wind": pomodoroSoundVolume])
        case .longBreak: applyMix(["night": pomodoroSoundVolume, "fireplace": pomodoroSoundVolume])
        }
    }

    func pomodoroSoundID(for phase: PomodoroPhase) -> String {
        pomodoroSoundIDs[phase.rawValue] ?? ""
    }

    func setPomodoroSoundID(_ id: String, for phase: PomodoroPhase) {
        pomodoroSoundIDs[phase.rawValue] = id
    }

    func synchronizeAudio() {
        do { try audio.update(levels, playing: isPlaying, master: masterVolume) }
        catch { self.error = error.localizedDescription; isPlaying = false }
        UserDefaults.standard.set(levels, forKey: "levels")
    }

    var nowPlayingTitle: String {
        let names = levels.keys.compactMap { id in library.first(where: { $0.id == id })?.name }
        return names.isEmpty ? "No sounds selected" : names.prefix(2).joined(separator: " + ")
    }

    private func tickTimer() {
        if remainingSeconds > 0 {
            remainingSeconds -= 1
            if remainingSeconds == 0 { isPlaying = false; synchronizeAudio() }
            else if remainingSeconds <= 15 { audio.engine.mainMixerNode.outputVolume = Float(masterVolume) * Float(remainingSeconds) / 15 }
        }

        updatePomodoroRemaining()
    }

    private func updatePomodoroRemaining() {
        guard isPomodoroRunning, let pomodoroEndDate else { return }
        let seconds = max(0, Int(pomodoroEndDate.timeIntervalSinceNow.rounded(.up)))
        if seconds != pomodoroRemainingSeconds { pomodoroRemainingSeconds = seconds }
        if seconds == 0 { advancePomodoro(completed: true) }
    }

    private func advancePomodoro(completed: Bool) {
        let finished = pomodoroPhase
        let wasRunning = isPomodoroRunning
        if completed && finished == .work {
            completedPomodoros += 1
            let task = pomodoroTask.trimmingCharacters(in: .whitespacesAndNewlines)
            pomodoroHistory.append(PomodoroSession(end: Date(), task: task, minutes: max(1, Int((Double(pomodoroTotalSeconds) / 60).rounded()))))
            if pomodoroHistory.count > 500 { pomodoroHistory.removeFirst(pomodoroHistory.count - 500) }
        }
        if finished == .work {
            pomodoroPhase = completedPomodoros > 0 && completedPomodoros % longBreakInterval == 0 ? .longBreak : .shortBreak
        } else {
            pomodoroPhase = .work
        }
        pomodoroTotalSeconds = pomodoroDurationSeconds
        pomodoroRemainingSeconds = pomodoroTotalSeconds
        pomodoroEndDate = nil
        isPomodoroRunning = false
        applyPomodoroSoundscape()
        if completed { notifyPomodoroTransition(from: finished, to: pomodoroPhase) }
        if completed ? autoStartPomodoro : wasRunning { startPomodoro() }
        persistPomodoro()
    }

    private func restorePomodoro() {
        isRestoringPomodoro = true
        defer { isRestoringPomodoro = false; persistPomodoro() }
        let defaults = UserDefaults.standard
        workMinutes = defaults.object(forKey: "pomodoro.workMinutes") as? Int ?? 25
        shortBreakMinutes = defaults.object(forKey: "pomodoro.shortBreakMinutes") as? Int ?? 5
        longBreakMinutes = defaults.object(forKey: "pomodoro.longBreakMinutes") as? Int ?? 15
        longBreakInterval = defaults.object(forKey: "pomodoro.longBreakInterval") as? Int ?? 4
        changesSoundscapeWithPomodoro = defaults.bool(forKey: "pomodoro.changesSoundscape")
        pomodoroSoundIDs = defaults.dictionary(forKey: "pomodoro.soundIDs") as? [String: String] ?? [:]
        pomodoroSoundVolume = defaults.object(forKey: "pomodoro.soundVolume") as? Double ?? 0.05
        completedPomodoros = defaults.integer(forKey: "pomodoro.completed")
        pomodoroTask = defaults.string(forKey: "pomodoro.task") ?? ""
        autoStartPomodoro = defaults.bool(forKey: "pomodoro.autoStart")
        pomodoroDailyGoal = defaults.object(forKey: "pomodoro.dailyGoal") as? Int ?? 8
        if let data = defaults.data(forKey: "pomodoro.history"),
           let saved = try? JSONDecoder().decode([PomodoroSession].self, from: data) {
            pomodoroHistory = saved
        }
        pomodoroPhase = PomodoroPhase(rawValue: defaults.string(forKey: "pomodoro.phase") ?? "") ?? .work
        pomodoroRemainingSeconds = defaults.object(forKey: "pomodoro.remaining") as? Int ?? pomodoroDurationSeconds
        pomodoroTotalSeconds = max(defaults.object(forKey: "pomodoro.total") as? Int ?? pomodoroDurationSeconds, pomodoroRemainingSeconds, 1)
        if let end = defaults.object(forKey: "pomodoro.end") as? Double {
            let endDate = Date(timeIntervalSince1970: end)
            if endDate > Date() {
                pomodoroEndDate = endDate
                isPomodoroRunning = true
                updatePomodoroRemaining()
            } else if defaults.bool(forKey: "pomodoro.running") {
                pomodoroEndDate = Date()
                isPomodoroRunning = true
                advancePomodoro(completed: true)
            }
        }
    }

    private func persistPomodoro() {
        guard !isRestoringPomodoro else { return }
        let defaults = UserDefaults.standard
        defaults.set(pomodoroPhase.rawValue, forKey: "pomodoro.phase")
        defaults.set(pomodoroRemainingSeconds, forKey: "pomodoro.remaining")
        defaults.set(isPomodoroRunning, forKey: "pomodoro.running")
        defaults.set(completedPomodoros, forKey: "pomodoro.completed")
        defaults.set(workMinutes, forKey: "pomodoro.workMinutes")
        defaults.set(shortBreakMinutes, forKey: "pomodoro.shortBreakMinutes")
        defaults.set(longBreakMinutes, forKey: "pomodoro.longBreakMinutes")
        defaults.set(longBreakInterval, forKey: "pomodoro.longBreakInterval")
        defaults.set(changesSoundscapeWithPomodoro, forKey: "pomodoro.changesSoundscape")
        defaults.set(pomodoroSoundIDs, forKey: "pomodoro.soundIDs")
        defaults.set(pomodoroSoundVolume, forKey: "pomodoro.soundVolume")
        defaults.set(pomodoroTotalSeconds, forKey: "pomodoro.total")
        defaults.set(pomodoroTask, forKey: "pomodoro.task")
        defaults.set(autoStartPomodoro, forKey: "pomodoro.autoStart")
        defaults.set(pomodoroDailyGoal, forKey: "pomodoro.dailyGoal")
        defaults.set(pomodoroEndDate?.timeIntervalSince1970, forKey: "pomodoro.end")
    }

    private func persistPomodoroHistory() {
        guard !isRestoringPomodoro, let data = try? JSONEncoder().encode(pomodoroHistory) else { return }
        UserDefaults.standard.set(data, forKey: "pomodoro.history")
    }

    private func notifyPomodoroTransition(from finished: PomodoroPhase, to next: PomodoroPhase) {
        let content = UNMutableNotificationContent()
        content.title = finished == .work ? "Focus session complete" : "Break complete"
        content.body = next == .work ? "Time to focus again." : "Take a \(next.title.lowercased())."
        content.sound = .default
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
