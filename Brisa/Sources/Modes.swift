import AppKit
import ApplicationServices

// Modes set up a whole workspace at once: open apps, put their windows where you like them,
// quiet the apps that distract you, and start sounds and a focus session.

/// A window's frame in the Accessibility coordinate space: origin at the top-left of the main display, y grows downwards.
struct WindowPlacement: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height }
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct ModeApp: Codable, Identifiable, Equatable {
    var bundleID: String
    var name: String
    /// Captured front to back, and restored in the same order.
    var windows: [WindowPlacement] = []
    var id: String { bundleID }
}

struct BrisaMode: Codable, Identifiable, Equatable {
    enum DistractionAction: String, Codable, CaseIterable, Identifiable {
        case leave, hide, quit
        var id: String { rawValue }
        var title: String {
            switch self {
            case .leave: return "Leave alone"
            case .hide: return "Hide"
            case .quit: return "Quit"
            }
        }
    }

    enum EndAction: String, Codable, CaseIterable, Identifiable {
        case leaveOpen, minimize, quit
        var id: String { rawValue }
        var title: String {
            switch self {
            case .leaveOpen: return "Leave open"
            case .minimize: return "Minimize"
            case .quit: return "Quit"
            }
        }
    }

    var id = UUID()
    var name: String
    var symbol = "book"
    var apps: [ModeApp] = []
    /// A sound choice in the same form Routines use ("mix:…", "scene:…", "preset:…", a sound id), or empty for none.
    var sound = ""
    var startFocusSession = false
    var distractions: [ModeApp] = []
    var distractionAction = DistractionAction.hide
    /// What happens to the mode's apps when it ends. Sounds and the focus timer always stop.
    var endAction = EndAction.minimize

    static let symbols = ["book", "graduationcap", "laptopcomputer", "pencil.and.outline", "paintbrush", "music.note",
                          "chart.bar", "briefcase", "brain.head.profile", "moon.stars", "gamecontroller", "leaf"]
}

/// Decisions about which apps a mode touches, kept free of AppKit so they can be tested.
enum ModePlanner {
    /// Brisa never hides, quits or minimizes itself or the Finder.
    static let protectedBundleIDs: Set<String> = ["local.brisa.ambient", "com.apple.finder"]

    /// Distracting apps to hide or quit: running ones only, and never one the mode itself uses.
    static func distractionsToHandle(in mode: BrisaMode, running: Set<String>) -> [String] {
        guard mode.distractionAction != .leave else { return [] }
        let modeApps = Set(mode.apps.map(\.bundleID))
        return mode.distractions.map(\.bundleID).filter { running.contains($0) && !modeApps.contains($0) && !protectedBundleIDs.contains($0) }
    }

    /// Apps to minimize or quit when a mode ends. When switching to another mode, apps both modes use stay put.
    static func appsToPutAway(ending mode: BrisaMode, switchingTo next: BrisaMode?) -> [String] {
        guard mode.endAction != .leaveOpen else { return [] }
        let kept = Set(next?.apps.map(\.bundleID) ?? [])
        return mode.apps.map(\.bundleID).filter { !kept.contains($0) && !protectedBundleIDs.contains($0) }
    }

    /// Converts an AppKit screen frame (origin bottom-left of the main display) to Accessibility coordinates.
    static func accessibilityFrame(of screenFrame: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: screenFrame.minX, y: mainScreenHeight - screenFrame.maxY, width: screenFrame.width, height: screenFrame.height)
    }

    /// A placement is restored only if enough of it lands on a connected display, so a window saved
    /// on a monitor that is no longer attached isn't moved out of reach.
    static func isVisible(_ placement: WindowPlacement, on screens: [CGRect], minimumSide: CGFloat = 80) -> Bool {
        screens.contains { screen in
            let overlap = screen.intersection(placement.rect)
            return !overlap.isNull && overlap.width >= minimumSide && overlap.height >= minimumSide
        }
    }
}

// MARK: - Windows

/// Reads and moves other apps' windows through the Accessibility API.
@MainActor
enum WindowArranger {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func runningApp(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    /// Normal document windows, front to back. Panels, sheets and palettes are left out.
    static func windows(of app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.filter { window in
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            return (subrole as? String) == kAXStandardWindowSubrole as String
        }
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func setFrame(_ rect: CGRect, of window: AXUIElement) {
        var origin = rect.origin, size = rect.size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        // Move, resize, then move again: some apps clamp the size to the screen the window is currently on.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    }

    static func minimizeWindows(of app: NSRunningApplication) {
        for window in windows(of: app) {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    /// Where each running app's windows are right now.
    static func capture(_ apps: [ModeApp]) -> [ModeApp] {
        apps.map { app in
            var copy = app
            if let running = runningApp(app.bundleID) {
                copy.windows = windows(of: running).compactMap(frame).map(WindowPlacement.init)
            }
            return copy
        }
    }

    static var screenFrames: [CGRect] {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { ModePlanner.accessibilityFrame(of: $0.frame, mainScreenHeight: mainHeight) }
    }

    /// Waits for a just-opened app's windows, then puts them where they were captured.
    static func arrange(_ app: ModeApp, timeout: TimeInterval = 12) async {
        guard !app.windows.isEmpty, isTrusted else { return }
        let deadline = Date().addingTimeInterval(timeout)
        var found: [AXUIElement] = []
        var firstSeen: Date?
        while Date() < deadline {
            if let running = runningApp(app.bundleID), running.isFinishedLaunching {
                found = windows(of: running)
                if found.count >= app.windows.count { break }
                // Some windows are up; give the rest a moment, then place what exists.
                if !found.isEmpty {
                    if let firstSeen, Date().timeIntervalSince(firstSeen) > 2 { break }
                    if firstSeen == nil { firstSeen = Date() }
                }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let screens = screenFrames
        for (window, placement) in zip(found, app.windows) where ModePlanner.isVisible(placement, on: screens) {
            setFrame(placement.rect, of: window)
        }
    }
}

// MARK: - Starting and ending

extension AppModel {
    var activeMode: BrisaMode? { modes.first { $0.id == activeModeID } }

    func startMode(_ mode: BrisaMode) {
        if let current = activeMode { endMode(switchingTo: mode, current: current) }
        activeModeID = mode.id

        // Sounds a mode starts don't count towards "Most used".
        let wasAutomatic = isAutomaticChange
        isAutomaticChange = true
        if !mode.sound.isEmpty { playSoundChoice(mode.sound) }
        isAutomaticChange = wasAutomatic
        if mode.startFocusSession { resetPomodoro(); startPomodoro() }

        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for bundleID in ModePlanner.distractionsToHandle(in: mode, running: running) {
            guard let app = WindowArranger.runningApp(bundleID) else { continue }
            if mode.distractionAction == .hide, app.hide() { hiddenByMode.insert(bundleID) }
            if mode.distractionAction == .quit { app.terminate() }
        }

        openModeApps(mode.apps)
    }

    /// Opens every app in the list that isn't running, shows the ones that are, and puts windows in place.
    func openModeApps(_ apps: [ModeApp]) {
        for app in apps {
            if let running = WindowArranger.runningApp(app.bundleID) {
                running.unhide()
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
        }
        Task { @MainActor in
            for app in apps { await WindowArranger.arrange(app) }
            // The first app in the list ends up in front.
            if let first = apps.first, let running = WindowArranger.runningApp(first.bundleID) { running.activate() }
        }
    }

    func endMode() {
        guard let current = activeMode else { activeModeID = nil; return }
        endMode(switchingTo: nil, current: current)
    }

    private func endMode(switchingTo next: BrisaMode?, current mode: BrisaMode) {
        if isPlaying { isPlaying = false; synchronizeAudio() }
        if isPomodoroRunning { pausePomodoro() }

        for bundleID in ModePlanner.appsToPutAway(ending: mode, switchingTo: next) {
            guard let app = WindowArranger.runningApp(bundleID) else { continue }
            switch mode.endAction {
            case .leaveOpen: break
            // Without Accessibility access windows can't be minimized, so hiding the app is the closest thing.
            case .minimize: if WindowArranger.isTrusted { WindowArranger.minimizeWindows(of: app) } else { app.hide() }
            case .quit: app.terminate()
            }
        }

        // Bring back what the mode hid, unless the next mode wants it hidden too.
        let stillHidden = Set(next.map { ModePlanner.distractionsToHandle(in: $0, running: hiddenByMode) } ?? [])
        for bundleID in hiddenByMode.subtracting(stillHidden) { WindowArranger.runningApp(bundleID)?.unhide() }
        hiddenByMode = stillHidden
        activeModeID = nil
    }

    // MARK: Editing and saving

    func saveMode(_ mode: BrisaMode) {
        if let index = modes.firstIndex(where: { $0.id == mode.id }) { modes[index] = mode } else { modes.append(mode) }
    }

    func removeMode(_ id: UUID) {
        if activeModeID == id { endMode() }
        modes.removeAll { $0.id == id }
    }

    func persistModes() {
        if let data = try? JSONEncoder().encode(modes) { UserDefaults.standard.set(data, forKey: "modes") }
        BrisaIntegration.refreshShortcutPhrases()
    }

    func loadModes() {
        if let data = UserDefaults.standard.data(forKey: "modes"), let saved = try? JSONDecoder().decode([BrisaMode].self, from: data) { modes = saved }
        activeModeID = UserDefaults.standard.string(forKey: "activeMode").flatMap(UUID.init)
        hiddenByMode = Set(UserDefaults.standard.stringArray(forKey: "hiddenByMode") ?? [])
    }
}
