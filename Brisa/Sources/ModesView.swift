import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

/// The Modes page: workspaces that open apps, arrange their windows and start sounds in one click.
struct ModesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var themeStore = BrisaThemeStore.shared
    @State private var editing: BrisaMode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Modes").font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("Open your apps where you like them, quiet distractions, and start sounds in one click.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { editing = BrisaMode(name: "") } label: {
                        Label("New mode", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(accent, in: Capsule()).foregroundStyle(onAccent)
                    }.buttonStyle(.plain)
                }

                if model.modes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.3.group").font(.largeTitle).foregroundStyle(accent)
                        Text("Set up a mode for studying, work or anything else").font(.title3)
                        Text("Pick the apps, arrange their windows once, and Brisa puts everything back each time you start the mode.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                    }.frame(maxWidth: .infinity).padding(.vertical, 50)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                        ForEach(model.modes) { mode in card(mode) }
                    }
                }

                Text("Arranging and minimizing windows needs Accessibility access (System Settings → Privacy & Security → Accessibility). Without it, Brisa still opens, hides and quits apps. Full-screen windows and other Spaces aren't moved.")
                    .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 34).padding(.bottom, 24).padding(.top, 4)
        }
        .sheet(item: $editing) { mode in ModeEditor(model: model, mode: mode) }
    }

    private func card(_ mode: BrisaMode) -> some View {
        let active = model.activeModeID == mode.id
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: mode.symbol).font(.system(size: 20)).foregroundStyle(accent)
                    .frame(width: 42, height: 42).background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(active ? "Active" : "\(mode.apps.count) app\(mode.apps.count == 1 ? "" : "s")")
                        .font(.caption.weight(active ? .semibold : .regular)).foregroundStyle(active ? accent : .secondary)
                }
                Spacer()
            }
            HStack(spacing: -6) {
                ForEach(mode.apps.prefix(8)) { app in AppIcon(bundleID: app.bundleID, size: 26) }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(summary(mode), id: \.self) { line in
                    Label(line.text, systemImage: line.symbol).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack {
                Button { active ? model.endMode() : model.startMode(mode) } label: {
                    Label(active ? "End mode" : "Start", systemImage: active ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 8)
                        .background(active ? surface.opacity(0.12) : accent, in: Capsule())
                        .foregroundStyle(active ? Color.primary : onAccent)
                }.buttonStyle(.plain)
                Spacer()
                Button { editing = mode } label: { Image(systemName: "pencil").font(.system(size: 12)).frame(width: 30, height: 30).background(surface.opacity(0.08), in: Circle()) }
                    .buttonStyle(.plain).help("Edit").accessibilityLabel("Edit \(mode.name)")
                Button { withAnimation { model.removeMode(mode.id) } } label: { Image(systemName: "trash").font(.system(size: 12)).frame(width: 30, height: 30).background(surface.opacity(0.08), in: Circle()) }
                    .buttonStyle(.plain).help("Delete").accessibilityLabel("Delete \(mode.name)")
            }
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(active ? accent.opacity(0.10) : surface.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(active ? accent.opacity(0.55) : .clear, lineWidth: 1))
    }

    private struct SummaryLine: Hashable { let symbol: String; let text: String }

    private func summary(_ mode: BrisaMode) -> [SummaryLine] {
        var lines: [SummaryLine] = []
        let windows = mode.apps.reduce(0) { $0 + $1.windows.count }
        if windows > 0 { lines.append(SummaryLine(symbol: "macwindow.on.rectangle", text: "Arranges \(windows) window\(windows == 1 ? "" : "s")")) }
        if !mode.sound.isEmpty { lines.append(SummaryLine(symbol: "waveform", text: "Plays \(RoutineSounds.title(for: mode.sound, in: model))")) }
        if mode.startFocusSession { lines.append(SummaryLine(symbol: "timer", text: "Starts a focus session")) }
        if mode.distractionAction != .leave, !mode.distractions.isEmpty {
            let verb = mode.distractionAction == .hide ? "Hides" : "Quits"
            lines.append(SummaryLine(symbol: "eye.slash", text: "\(verb) \(mode.distractions.map(\.name).joined(separator: ", "))"))
        }
        let ending = mode.endAction == .leaveOpen ? "leaves apps open" : mode.endAction == .minimize ? "minimizes its apps" : "quits its apps"
        lines.append(SummaryLine(symbol: "flag.checkered", text: "When it ends, \(ending)"))
        return lines
    }
}

/// An app's icon, looked up from its bundle identifier.
struct AppIcon: View {
    let bundleID: String
    var size: CGFloat = 20

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application))
            .resizable().frame(width: size, height: size)
    }
}

/// Create or edit one mode.
struct ModeEditor: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var themeStore = BrisaThemeStore.shared
    @Environment(\.dismiss) private var dismiss
    @State var mode: BrisaMode
    @State private var captureMessage: String?
    @State private var trusted = WindowArranger.isTrusted
    private let trustTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var canSave: Bool { !mode.name.trimmingCharacters(in: .whitespaces).isEmpty && !mode.apps.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.modes.contains { $0.id == mode.id } ? "Edit mode" : "New mode").font(.title2.weight(.semibold)).padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(BrisaMode.symbols, id: \.self) { symbol in
                                Button { mode.symbol = symbol } label: { Image(systemName: symbol) }
                            }
                        } label: { Image(systemName: mode.symbol).frame(width: 22) }
                            .menuStyle(.borderlessButton).fixedSize().help("Icon")
                        TextField("Name, e.g. Studying", text: $mode.name).textFieldStyle(.roundedBorder)
                    }

                    section("Apps and windows") {
                        if mode.apps.isEmpty {
                            Text("Add the apps this mode opens.").font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(mode.apps) { app in
                            appRow(app, detail: app.windows.isEmpty ? "Opens without arranging" : "\(app.windows.count) window\(app.windows.count == 1 ? "" : "s") placed") {
                                mode.apps.removeAll { $0.id == app.id }
                            }
                        }
                        AppPickerMenu(title: "Add an app", excluding: Set(mode.apps.map(\.bundleID))) { app in
                            mode.apps.append(app)
                            mode.distractions.removeAll { $0.bundleID == app.bundleID }
                        }
                        if !mode.apps.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Arrange these apps' windows the way you like, then save the layout.")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("Open these apps") { model.openModeApps(mode.apps.map { ModeApp(bundleID: $0.bundleID, name: $0.name) }) }
                                    Button("Use current window layout") { captureLayout() }.disabled(!trusted)
                                }.controlSize(.small)
                                if !trusted {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                        Text("Brisa needs Accessibility access to read and move windows.").font(.caption)
                                        Button("Allow…") { WindowArranger.requestAccess() }.controlSize(.small)
                                    }
                                }
                                if let captureMessage { Text(captureMessage).font(.caption).foregroundStyle(accent) }
                            }
                            .padding(12).background(surface.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    section("Sound and focus") {
                        HStack { Text("Sound").frame(width: 60, alignment: .leading); SoundChoicePicker(model: model, choice: $mode.sound, allowsNone: true) }
                        Toggle("Start a focus session", isOn: $mode.startFocusSession)
                    }

                    section("Distractions") {
                        Picker("", selection: $mode.distractionAction) {
                            ForEach(BrisaMode.DistractionAction.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 300)
                        if mode.distractionAction != .leave {
                            ForEach(mode.distractions) { app in
                                appRow(app, detail: mode.distractionAction == .hide ? "Hidden while the mode is on" : "Quit when the mode starts") {
                                    mode.distractions.removeAll { $0.id == app.id }
                                }
                            }
                            AppPickerMenu(title: "Add a distracting app", excluding: Set((mode.apps + mode.distractions).map(\.bundleID))) { app in
                                mode.distractions.append(app)
                            }
                            if mode.distractionAction == .quit {
                                Text("Apps get a chance to ask about unsaved work before quitting.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    section("When the mode ends") {
                        Text("Sounds and the focus timer stop, and hidden apps come back.").font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Text("This mode's apps")
                            Picker("", selection: $mode.endAction) {
                                ForEach(BrisaMode.EndAction.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 280)
                        }
                    }
                }
                .padding(.trailing, 6)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    mode.name = mode.name.trimmingCharacters(in: .whitespaces)
                    model.saveMode(mode)
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(!canSave)
            }.padding(.top, 16)
        }
        .padding(28).frame(width: 560, height: 680)
        .preferredColorScheme(themeStore.current.scheme).tint(accent)
        .onReceive(trustTimer) { _ in trusted = WindowArranger.isTrusted }
    }

    private func captureLayout() {
        let captured = WindowArranger.capture(mode.apps)
        mode.apps = captured
        let windows = captured.reduce(0) { $0 + $1.windows.count }
        let closed = captured.filter { WindowArranger.runningApp($0.bundleID) == nil }.map(\.name)
        var message = "Saved \(windows) window\(windows == 1 ? "" : "s")."
        if !closed.isEmpty { message += " Not open: \(closed.joined(separator: ", ")). Open them and try again to include their windows." }
        captureMessage = message
    }

    private func appRow(_ app: ModeApp, detail: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            AppIcon(bundleID: app.bundleID, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.system(size: 13, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.tertiary).accessibilityLabel("Remove \(app.name)")
        }
        .padding(10).background(surface.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.bold)).tracking(1.2).textCase(.uppercase).foregroundStyle(.secondary)
            content()
        }
    }
}

/// Offers the apps that are open right now, or any app from the Applications folder.
struct AppPickerMenu: View {
    let title: String
    let excluding: Set<String>
    let onPick: (ModeApp) -> Void

    private var runningApps: [ModeApp] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> ModeApp? in
                guard let id = app.bundleIdentifier, !excluding.contains(id), !ModePlanner.protectedBundleIDs.contains(id),
                      seen.insert(id).inserted else { return nil }
                return ModeApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Menu {
            Section("Open now") {
                ForEach(runningApps) { app in Button(app.name) { onPick(app) } }
            }
            Divider()
            Button("Choose from Applications…") { chooseFromApplications() }
        } label: { Label(title, systemImage: "plus.circle.fill") }
            .menuStyle(.borderlessButton).fixedSize()
    }

    private func chooseFromApplications() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !excluding.contains(id), !ModePlanner.protectedBundleIDs.contains(id) else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            onPick(ModeApp(bundleID: id, name: name))
        }
    }
}
