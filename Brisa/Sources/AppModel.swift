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
    @Published var workMinutes = 25 { didSet { let valid = min(max(workMinutes, 1), 180); if valid != workMinutes { workMinutes = valid } else { persistPomodoro() } } }
    @Published var shortBreakMinutes = 5 { didSet { let valid = min(max(shortBreakMinutes, 1), 60); if valid != shortBreakMinutes { shortBreakMinutes = valid } else { persistPomodoro() } } }
    @Published var longBreakMinutes = 15 { didSet { let valid = min(max(longBreakMinutes, 1), 120); if valid != longBreakMinutes { longBreakMinutes = valid } else { persistPomodoro() } } }
    @Published var longBreakInterval = 4 { didSet { let valid = min(max(longBreakInterval, 1), 12); if valid != longBreakInterval { longBreakInterval = valid } else { persistPomodoro() } } }
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

    var pomodoroTimeText: String {
        String(format: "%02d:%02d", max(0, pomodoroRemainingSeconds) / 60, max(0, pomodoroRemainingSeconds) % 60)
    }

    func startPomodoro() {
        if pomodoroRemainingSeconds <= 0 { pomodoroRemainingSeconds = pomodoroDurationSeconds }
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
        pomodoroRemainingSeconds = workMinutes * 60
        persistPomodoro()
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
        if completed && finished == .work { completedPomodoros += 1 }
        if finished == .work {
            pomodoroPhase = completedPomodoros > 0 && completedPomodoros % longBreakInterval == 0 ? .longBreak : .shortBreak
        } else {
            pomodoroPhase = .work
        }
        pomodoroRemainingSeconds = pomodoroDurationSeconds
        pomodoroEndDate = nil
        isPomodoroRunning = false
        applyPomodoroSoundscape()
        notifyPomodoroTransition(from: finished, to: pomodoroPhase)
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
        pomodoroPhase = PomodoroPhase(rawValue: defaults.string(forKey: "pomodoro.phase") ?? "") ?? .work
        pomodoroRemainingSeconds = defaults.object(forKey: "pomodoro.remaining") as? Int ?? pomodoroDurationSeconds
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
        defaults.set(pomodoroEndDate?.timeIntervalSince1970, forKey: "pomodoro.end")
    }

    private func notifyPomodoroTransition(from finished: PomodoroPhase, to next: PomodoroPhase) {
        let content = UNMutableNotificationContent()
        content.title = finished == .work ? "Focus session complete" : "Break complete"
        content.body = next == .work ? "Time to focus again." : "Take a (next.title.lowercased())."
        content.sound = .default
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
