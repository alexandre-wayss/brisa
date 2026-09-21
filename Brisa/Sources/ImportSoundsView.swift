import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ImportSoundsView: View {
    @ObservedObject private var themeStore = BrisaThemeStore.shared
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var urlText = ""
    @State private var attribution = ""
    @State private var license = ""
    @State private var choosingFile = false
    @State private var importing = false
    @State private var error: String?

    private let audioTypes: [UTType] = [.wav, .aiff, .mp3]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Import audio").font(.title2.weight(.semibold))
            Text("Files are copied into Brisa’s private library, so the original can move or be deleted. WAV, AIFF, and MP3 are supported.")
                .font(.callout).foregroundStyle(.secondary)
            Button { choosingFile = true } label: {
                Label("Choose audio file…", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }.buttonStyle(.borderedProminent)
            Divider()
            Text("External audio URL").font(.headline)
            TextField("https://example.com/sound.mp3 or a YouTube link", text: $urlText).textFieldStyle(.roundedBorder)
            Text("Direct HTTPS links to WAV, AIFF, and MP3 are downloaded once after type and size checks. YouTube links become video buttons that play in Brisa’s video window through YouTube’s official player. Brisa never downloads or extracts YouTube audio.")
                .font(.caption).foregroundStyle(.secondary)
            Group {
                TextField("Attribution (optional)", text: $attribution)
                TextField("License (optional, e.g. CC BY 4.0)", text: $license)
            }.textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(importing ? "Importing…" : "Add URL") {
                    importing = true
                    Task {
                        do {
                            try await model.importExternalURL(urlText.trimmingCharacters(in: .whitespacesAndNewlines), attribution: attribution, license: license)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                        importing = false
                    }
                }.disabled(importing || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26).frame(width: 520).preferredColorScheme(themeStore.current.scheme).tint(accent)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: audioTypes, allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                try model.importLocalFile(url, attribution: attribution, license: license)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
        .alert("Could not import audio", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
