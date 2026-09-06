import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    let inputSounds = InputSounds()

    @Published var levels: [String: Double] = [:]
    @Published var favorites: Set<String> = []
    @Published var mixes: [Mix] = []
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
