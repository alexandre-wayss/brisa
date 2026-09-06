import SwiftUI
import AppKit

@MainActor
enum BrisaWindowActions {
    static func moveToMenuBar() {
        for window in NSApp.windows where window.title == "Brisa" {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
    }

    static func showInDock() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class BrisaAppDelegate: NSObject, NSApplicationDelegate {
    var playbackAction: (() -> Void)?
    private var pendingPlaybackActions = 0

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "brisa" && url.host == "playback" && url.path == "/toggle" {
            if let playbackAction { playbackAction() }
            else { pendingPlaybackActions += 1 }
        }
    }

    func connectPlayback(_ action: @escaping () -> Void) {
        playbackAction = action
        let pending = pendingPlaybackActions
        pendingPlaybackActions = 0
        for _ in 0..<pending { action() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        BrisaWindowActions.showInDock()
        NotificationCenter.default.post(name: Notification.Name("BrisaShowWindow"), object: nil)
        return true
    }
}

@main
struct BrisaApp: App {
    @NSApplicationDelegateAdaptor(BrisaAppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Brisa", id: "main") {
            BrisaMainView(model: model)
                .onAppear { delegate.connectPlayback { model.togglePlayback() }; BrisaDesktopPlayer.shared.restore() }
        }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1080, height: 770)
            .commands {
                CommandGroup(replacing: .appTermination) {
                    Button("Keep Running in Menu Bar") { BrisaWindowActions.moveToMenuBar() }
                        .keyboardShortcut("q")
                    Button("Quit Brisa Completely") { NSApp.terminate(nil) }
                        .keyboardShortcut("q", modifiers: [.command, .option])
                }
            }
        MenuBarExtra("Brisa", systemImage: "wind") {
            MenuBarPlayerView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct BrisaMainView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ContentView(model: model)
            .onDisappear { BrisaWindowActions.moveToMenuBar() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BrisaShowWindow"))) { _ in
                openWindow(id: "main")
                BrisaWindowActions.showInDock()
            }
    }
}

// A single live panel shares the main player's model and audio engine.
@MainActor
final class BrisaDesktopPlayer: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = BrisaDesktopPlayer()
    private var panel: NSPanel?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    func dragFromSurface() {
        guard !locked, let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
        guard let start = dragStart else { return }
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                     y: start.origin.y + mouse.y - start.mouse.y))
    }

    func endSurfaceDrag() { dragStart = nil }
    @Published var enabled = UserDefaults.standard.bool(forKey: "mini.enabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "mini.enabled"); if enabled { show() } else { panel?.orderOut(nil) } }
    }
    @Published var aboveApps = UserDefaults.standard.bool(forKey: "mini.aboveApps") {
        didSet { UserDefaults.standard.set(aboveApps, forKey: "mini.aboveApps"); applyPlacement() }
    }
    @Published var locked = UserDefaults.standard.bool(forKey: "mini.locked") {
        didSet { UserDefaults.standard.set(locked, forKey: "mini.locked"); panel?.isMovableByWindowBackground = false }
    }

    func addToDesktop() {
        locked = false
        aboveApps = false
        show()
        BrisaWindowActions.moveToMenuBar()
        // Reveal the desktop using macOS Mission Control.
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--show-desktop"]
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
    }

    func restore() { if enabled { show() } }
    private func applyPlacement() {
        panel?.level = aboveApps ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel?.collectionBehavior = aboveApps ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.canJoinAllSpaces, .stationary]
    }
    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "mini.frame")
    }

    func show() {
        if !enabled { enabled = true; return }
        if let panel { applyPlacement(); panel.orderFrontRegardless(); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Brisa Mini Player"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: LiveBrisaPlayer(model: .shared))
        panel.center()
        if let saved = UserDefaults.standard.string(forKey: "mini.frame") {
            let frame = NSRectFromString(saved)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(frame) }) {
                panel.setFrame(frame, display: false)
            }
        }
        self.panel = panel
        panel.delegate = self
        applyPlacement()
        panel.orderFrontRegardless()
    }

    func hide() { enabled = false }
}

private struct LiveBrisaPlayer: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var desktop = BrisaDesktopPlayer.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heldPhase = 0.0
    @State private var lastRenderedPhase = 0.0
    @State private var animationStart: Date?
    private let mint = Color(red: 0.65, green: 0.93, blue: 0.77)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: [mint.opacity(0.14), Color.black.opacity(0.35)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isPlaying || reduceMotion)) { timeline in
                let phase = animationStart.map { heldPhase + max(0, timeline.date.timeIntervalSince($0)) * 0.65 } ?? heldPhase
                Canvas { context, size in
                    for layer in 0..<22 {
                        var path = Path()
                        for step in 0...100 {
                            let t = Double(step) / 100
                            let wave = sin(t * .pi * 3.5 + phase + Double(layer) * 0.06)
                            let second = sin(t * .pi * 6 - phase * 0.6 + Double(layer) * 0.12)
                            let point = CGPoint(x: t * size.width,
                                                y: size.height * (0.5 + wave * 0.21 + second * 0.09) + Double(layer) * 0.5)
                            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                        context.stroke(path, with: .color(mint.opacity(0.38)), lineWidth: 0.6)
                    }
                }
                .onChange(of: timeline.date) { _ in lastRenderedPhase = phase }
            }.frame(height: 90).offset(y: 24).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("brisa", systemImage: "wind").font(.system(size: 18, weight: .medium, design: .rounded))
                    Spacer()
                    Text(model.isPlaying ? "PLAYING" : "PAUSED").font(.system(size: 9, weight: .medium)).tracking(1)
                    Button { desktop.aboveApps.toggle() } label: {
                        Image(systemName: desktop.aboveApps ? "pin.fill" : "pin").frame(width: 22, height: 24)
                    }.buttonStyle(.plain).help(desktop.aboveApps ? "Keep on desktop" : "Keep above apps")
                    Button { desktop.locked.toggle() } label: {
                        Image(systemName: desktop.locked ? "lock.fill" : "lock.open").frame(width: 22, height: 24)
                    }.buttonStyle(.plain).help(desktop.locked ? "Unlock position" : "Lock position")
                    Button { BrisaDesktopPlayer.shared.hide() } label: {
                        Image(systemName: "xmark").font(.system(size: 10)).frame(width: 24, height: 24)
                    }.buttonStyle(.plain).accessibilityLabel("Close mini player")
                }.foregroundStyle(mint)
                Menu {
                    ForEach(["Noise", "Water", "Nature", "Spaces"], id: \.self) { category in
                        Menu(category) {
                            ForEach(library.filter { $0.category == category }) { sound in
                                Button { model.replaceWith(sound) } label: { Label(sound.name, systemImage: sound.icon) }
                            }
                        }
                    }
                    if !model.mixes.isEmpty {
                        Divider()
                        Menu("My mixes") {
                            ForEach(model.mixes) { mix in
                                Button(mix.name) { model.applyMix(mix.levels) }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(model.nowPlayingTitle).font(.system(size: 24, weight: .regular, design: .rounded)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption)
                    }
                }.menuStyle(.borderlessButton).help("Choose a sound or saved mix")
                Text("Your quiet space").font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 12) {
                    Button { model.toggleMute() } label: {
                        Image(systemName: model.masterVolume == 0 ? "speaker.slash" : "speaker.wave.2")
                    }.buttonStyle(.plain).accessibilityLabel("Toggle mute")
                    Slider(value: $model.masterVolume, in: 0...1)
                        .onChange(of: model.masterVolume) { _ in model.synchronizeAudio() }
                        .accessibilityLabel("Volume")
                    Text("\(Int(model.masterVolume * 100))%").font(.caption.monospacedDigit()).frame(width: 32)
                    Button { model.togglePlayback() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20)).frame(width: 52, height: 52)
                            .background(.white.opacity(0.12), in: Circle())
                            .overlay(Circle().strokeBorder(mint.opacity(0.5), lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                }
            }.padding(22)
        }
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(
            LinearGradient(colors: [.white.opacity(0.5), .clear, mint.opacity(0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .frame(width: 380, height: 240).preferredColorScheme(.dark).tint(mint)
        .coordinateSpace(name: "miniSurface")
        .onAppear { if model.isPlaying && !reduceMotion { animationStart = .now } }
        .onChange(of: model.isPlaying && !reduceMotion) { running in
            heldPhase = lastRenderedPhase
            animationStart = running ? .now : nil
        }
        .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("miniSurface"))
            .onChanged { gesture in
                // The panel is 240 pt tall. Reserve the entire bottom control
                // strip, including the slider's thumb and native hit padding.
                // Check the start point so leaving the slider mid-drag cannot
                // turn a volume gesture into a window drag.
                guard gesture.startLocation.y < 158 else { return }
                desktop.dragFromSurface()
            }
            .onEnded { _ in desktop.endSurfaceDrag() })
    }
}




struct BrisaWidgetSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Settings").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            Label("Widgets", systemImage: "square.grid.2x2").font(.headline)
            Text("Your quiet space, right on your desktop.").foregroundStyle(.secondary)
            LiveBrisaPlayer(model: model).allowsHitTesting(false)
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            BrisaDesktopPlayer.shared.addToDesktop()
                        }
                    } label: {
                        Image(systemName: "plus").font(.title2.weight(.medium))
                            .frame(width: 48, height: 48).background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.3)))
                    }.buttonStyle(.plain).help("Add to desktop").accessibilityLabel("Add widget to desktop")
                        .offset(x: 16, y: 16)
                }
            Text("Drag anywhere except the volume slider to position it. Pin and lock controls live on the widget.")
                .font(.caption).foregroundStyle(.secondary).frame(width: 380, alignment: .leading)
        }.padding(32).frame(width: 470).preferredColorScheme(.dark)
    }
}
