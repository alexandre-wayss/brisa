import AppIntents
import SwiftUI
import WidgetKit

private let widgetSuite = "group.local.brisa.ambient"

struct BrisaEntry: TimelineEntry {
    let date: Date
    let isPlaying: Bool
    let title: String
    let soundCount: Int
    let volume: Double
}

struct BrisaProvider: TimelineProvider {
    func placeholder(in context: Context) -> BrisaEntry { preview }
    func getSnapshot(in context: Context, completion: @escaping (BrisaEntry) -> Void) { completion(current) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BrisaEntry>) -> Void) {
        completion(Timeline(entries: [current], policy: .after(.now.addingTimeInterval(60))))
    }

    private var preview: BrisaEntry { BrisaEntry(date: .now, isPlaying: true, title: "Light Rain + Wind", soundCount: 2, volume: 0.4) }
    private var current: BrisaEntry {
        let defaults = UserDefaults(suiteName: widgetSuite) ?? .standard
        return BrisaEntry(date: .now,
                          isPlaying: defaults.bool(forKey: "widget.isPlaying"),
                          title: defaults.string(forKey: "widget.title") ?? "Ready to play",
                          soundCount: defaults.integer(forKey: "widget.soundCount"),
                          volume: defaults.object(forKey: "widget.volume") as? Double ?? 0.65)
    }
}

struct ToggleBrisaPlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Brisa playback"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: widgetSuite) ?? .standard
        defaults.set("togglePlayback", forKey: "widget.pendingAction")
        return .result()
    }
}

struct BrisaDesktopWidget: Widget {
    let kind = "local.brisa.ambient.desktop"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BrisaProvider()) { entry in
            BrisaWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(red: 0.045, green: 0.09, blue: 0.08) }
        }
        .configurationDisplayName("Brisa player")
        .description("Control your current Brisa soundscape.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct BrisaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BrisaEntry
    private let accent = Color(red: 0.66, green: 0.79, blue: 0.63)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wind").foregroundStyle(accent)
                Text("brisa").font(.headline.weight(.semibold))
                Spacer()
                Circle().fill(entry.isPlaying ? accent : .secondary).frame(width: 7, height: 7)
            }
            Spacer(minLength: 0)
            Text(entry.title).font(.system(.title3, design: .rounded).weight(.semibold)).lineLimit(1)
            Text(entry.isPlaying ? "\(entry.soundCount) sounds playing" : "Ready when you are")
                .font(.caption).foregroundStyle(.secondary)
            if family == .systemMedium {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill").font(.caption)
                    ProgressView(value: entry.volume).tint(accent)
                    Text("\(Int(entry.volume * 100))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button(intent: ToggleBrisaPlaybackIntent()) {
                    Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline).foregroundStyle(Color.black.opacity(0.8))
                        .frame(width: 42, height: 42).background(accent, in: Circle())
                }.buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(16)
    }
}

@available(macOS 26.0, *)
struct BrisaPlaybackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.brisa.ambient.playback") {
            ControlWidgetButton(action: ToggleBrisaPlaybackIntent()) {
                Label("Brisa", systemImage: "wind")
            }
        }
        .displayName("Brisa")
        .description("Play or pause your ambient soundscape.")
    }
}

@main
struct BrisaWidgets: WidgetBundle {
    var body: some Widget {
        BrisaDesktopWidget()
        if #available(macOS 26.0, *) { BrisaPlaybackControl() }
    }
}
