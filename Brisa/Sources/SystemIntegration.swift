import AppKit
import MediaPlayer
import ServiceManagement

/// Ties Brisa into macOS: media keys and Now Playing, and reacting to the Mac sleeping and waking.
@MainActor
final class SystemIntegration {
    private unowned let model: AppModel
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        registerRemoteCommands()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.systemWillSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.systemDidWake() }
        })
    }

    deinit { observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }

    // MARK: Media keys and Now Playing

    private func registerRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if let model = self?.model, !model.isPlaying { model.togglePlayback() } }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if let model = self?.model, model.isPlaying { model.togglePlayback() } }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.model.togglePlayback() }
            return .success
        }
        for command in [commands.nextTrackCommand, commands.previousTrackCommand, commands.seekForwardCommand, commands.seekBackwardCommand] {
            command.isEnabled = false
        }
    }

    func refreshNowPlaying() {
        let info = MPNowPlayingInfoCenter.default()
        guard !model.levels.isEmpty else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: model.nowPlayingTitle,
            MPMediaItemPropertyArtist: "Brisa",
            MPNowPlayingInfoPropertyPlaybackRate: model.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
        info.playbackState = model.isPlaying ? .playing : .paused
    }
}

/// Opens Brisa automatically when the user logs in.
enum LaunchAtLogin {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
