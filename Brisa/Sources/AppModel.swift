import Foundation
import Combine

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

    private var volumeBeforeMute = 0.65
    private let audio = AudioBank()
    private var timer: Timer?

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
        guard remainingSeconds > 0 else { return }
        remainingSeconds -= 1
        if remainingSeconds == 0 { isPlaying = false; synchronizeAudio() }
        else if remainingSeconds <= 15 { audio.engine.mainMixerNode.outputVolume = Float(masterVolume) * Float(remainingSeconds) / 15 }
    }
}
