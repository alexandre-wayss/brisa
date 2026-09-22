import SwiftUI
import AppKit
import WebKit

/// YouTube links become video cards. Brisa plays them through YouTube's official embedded player and never
/// downloads or separates the audio: the video stays visible in its own small window while it plays.
enum YouTubeLink {
    /// The 11-character video ID for watch, short, embed, shorts and live links, or nil for anything else
    /// (channels, bare playlists, other sites).
    static func videoID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        var candidate: String?
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            candidate = parts.first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com") {
            if parts.first == "watch" {
                candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
            } else if let first = parts.first, ["embed", "shorts", "live", "v"].contains(first), parts.count > 1 {
                candidate = parts[1]
            }
        }
        guard let candidate, isValid(candidate) else { return nil }
        return candidate
    }

    static func isValid(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func watchURL(_ id: String) -> URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    static func thumbnailURL(_ id: String) -> URL { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")! }

    struct Metadata { var title: String; var channel: String; var thumbnail: String? }

    /// Title, channel and thumbnail from YouTube's public oEmbed endpoint. Returns nil if the video is private, removed or offline.
    static func fetchMetadata(for id: String) async -> Metadata? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: watchURL(id).absoluteString), URLQueryItem(name: "format", value: "json")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String else { return nil }
        return Metadata(title: title, channel: json["author_name"] as? String ?? "", thumbnail: json["thumbnail_url"] as? String)
    }

    static func message(forPlayerError code: Int) -> String {
        switch code {
        case 2: return "This link doesn't point to a valid video."
        case 5: return "YouTube couldn't play this video in an embedded player."
        case 100: return "This video was removed or is private."
        case 101, 150: return "The owner of this video doesn't allow it to be played outside YouTube."
        case 153: return "YouTube blocked the embedded player for this video."
        default: return "This video couldn't be played (error \(code))."
        }
    }
}

extension ImportedSound {
    var isYouTubeVideo: Bool { source == .youtube }

    /// Works for new items and for older bookmarks that only stored the original link.
    var youtubeID: String? { videoID ?? YouTubeLink.videoID(from: originalURL) }
}

/// One small floating window with YouTube's player. Playing another video reuses it.
@MainActor
final class YouTubeVideoPlayer: NSObject, ObservableObject, WKScriptMessageHandler, NSWindowDelegate {
    static let shared = YouTubeVideoPlayer()

    @Published private(set) var currentID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var errors: [String: String] = [:]
    /// Called with the real title once the player knows it (for links saved before titles were fetched).
    var onTitle: ((String, String) -> Void)?

    // Test hooks: keep automated runs silent and off-screen.
    var forceMuted = false
    var panelOrigin: NSPoint?

    /// YouTube requires the player to stay visible and at least 200×200 points. Compact is the smallest 16:9 size
    /// that meets that, so the video is out of the way but never hidden.
    static let normalSize = NSSize(width: 480, height: 270)
    static let compactSize = NSSize(width: 356, height: 200)

    @Published var compact = UserDefaults.standard.bool(forKey: "video.compact") {
        didSet {
            UserDefaults.standard.set(compact, forKey: "video.compact")
            guard let panel else { return }
            let size = compact ? Self.compactSize : Self.normalSize
            let frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            // Keep the top-right corner where it is while resizing.
            var next = panel.frame
            next.origin.y += next.height - frame.height
            next.origin.x += next.width - frame.width
            next.size = frame.size
            panel.setFrame(next, display: true, animate: true)
        }
    }

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var currentSoundID: String?

    func isCurrent(_ sound: ImportedSound) -> Bool { currentSoundID == sound.id }

    func toggle(_ sound: ImportedSound) {
        guard let id = sound.youtubeID else { return }
        if currentSoundID == sound.id, webView != nil {
            run(isPlaying ? "player.pauseVideo()" : "player.playVideo()")
            return
        }
        errors[sound.id] = nil
        load(videoID: id, sound: sound)
    }

    func stop() {
        run("player.stopVideo()")
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)   // ends playback and audio
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "yt")
        webView = nil
        panel = nil
        currentID = nil
        currentSoundID = nil
        isPlaying = false
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript("try { \(script) } catch (e) {}", completionHandler: nil)
    }

    private func load(videoID: String, sound: ImportedSound) {
        let panel = existingOrNewPanel()
        panel.title = sound.name
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "yt")

        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(self, name: "yt")
        let web = WKWebView(frame: panel.contentView?.bounds ?? .zero, configuration: configuration)
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        panel.contentView = web
        webView = web
        currentSoundID = sound.id
        currentID = videoID
        isPlaying = false

        // A real https origin is required, otherwise YouTube refuses to embed (error 153).
        web.loadHTMLString(Self.html(videoID: videoID, muted: forceMuted), baseURL: URL(string: "https://brisa.local"))
        panel.orderFrontRegardless()
    }

    private func existingOrNewPanel() -> NSPanel {
        if let panel { return panel }
        let size = compact ? Self.compactSize : Self.normalSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentAspectRatio = NSSize(width: 16, height: 9)
        panel.contentMinSize = Self.compactSize
        panel.backgroundColor = .black
        panel.delegate = self
        if let origin = panelOrigin {
            panel.setFrameOrigin(origin)
        } else if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.maxX - panel.frame.width - 28, y: area.maxY - panel.frame.height - 60))
        }
        self.panel = panel
        return panel
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "state":
            // 1 playing, 3 buffering; everything else (paused, ended, cued) is not playing.
            let state = body["value"] as? Int ?? -1
            isPlaying = state == 1 || state == 3
        case "error":
            let code = body["value"] as? Int ?? 0
            if let soundID = currentSoundID { errors[soundID] = YouTubeLink.message(forPlayerError: code) }
            isPlaying = false
        case "title":
            if let title = body["value"] as? String, !title.isEmpty, let soundID = currentSoundID {
                panel?.title = title
                onTitle?(soundID, title)
            }
        default: break
        }
    }

    static func html(videoID: String, muted: Bool) -> String {
        """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0;background:#000;overflow:hidden"><div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function post(kind, value) { window.webkit.messageHandlers.yt.postMessage({kind: kind, value: value}); }
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('p', { width: '100%', height: '100%', videoId: '\(videoID)', host: 'https://www.youtube-nocookie.com',
            playerVars: { playsinline: 1, rel: 0, autoplay: 1, enablejsapi: 1, origin: 'https://brisa.local' },
            events: {
              onReady: function (e) { \(muted ? "e.target.mute();" : "") e.target.playVideo(); post('title', e.target.getVideoData().title); },
              onStateChange: function (e) { post('state', e.data); if (e.data === 1) { post('title', player.getVideoData().title); } },
              onError: function (e) { post('error', e.data); }
            } });
        }
        </script></body></html>
        """
    }
}

/// A video button that sits in the library next to the sounds.
struct YouTubeVideoCard: View {
    let video: ImportedSound
    @ObservedObject var player: YouTubeVideoPlayer
    @ObservedObject private var themeStore = BrisaThemeStore.shared
    var onRemove: () -> Void

    private var isCurrent: Bool { player.isCurrent(video) }
    private var isPlaying: Bool { isCurrent && player.isPlaying }
    private var errorText: String? { player.errors[video.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { player.toggle(video) } label: {
                Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { thumbnail }
                    .overlay {
                        Circle().fill(.black.opacity(0.5)).frame(width: 46, height: 46)
                            .overlay(Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white))
                    }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isCurrent ? accent : surface.opacity(0.12), lineWidth: isCurrent ? 2 : 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isPlaying ? "Pause" : "Play") video \(video.name)")

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.name).font(.system(size: 14, weight: .medium)).lineLimit(2)
                    HStack(spacing: 5) {
                        Image(systemName: "play.rectangle.fill").font(.caption2).foregroundStyle(.red)
                        Text(video.attribution.isEmpty ? "YouTube" : video.attribution).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if isPlaying { Text("· Playing").font(.caption.weight(.medium)).foregroundStyle(accent) }
                    }
                }
                Spacer(minLength: 4)
                Menu {
                    Button { NSWorkspace.shared.open(YouTubeLink.watchURL(video.youtubeID ?? "")) } label: { Label("Open on YouTube", systemImage: "arrow.up.right.square") }
                    Divider()
                    Button(role: .destructive, action: onRemove) { Label("Remove", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("More options for \(video.name)")
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(surface.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }

    private var thumbnail: some View {
        let url = video.thumbnailURL.flatMap(URL.init(string:)) ?? video.youtubeID.map(YouTubeLink.thumbnailURL)
        return AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default: Rectangle().fill(surface.opacity(0.08)).overlay(Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.secondary))
            }
        }
    }
}
