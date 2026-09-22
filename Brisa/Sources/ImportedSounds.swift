import Foundation
import UniformTypeIdentifiers

enum ImportedSoundSource: String, Codable {
    case localFile, externalURL, youtube
}

struct ImportedSound: Codable, Identifiable {
    let id: String
    var name: String
    var source: ImportedSoundSource
    var originalURL: String
    var storedFile: String?
    var bookmark: Data?
    var attribution: String
    var license: String
    var importedAt: Date
    var unavailableReason: String?
    var videoID: String?
    var thumbnailURL: String?

    var sound: Sound {
        Sound(id: id, name: name, icon: source == .youtube ? "play.rectangle" : "music.note",
              category: "Imported", detail: detail)
    }

    var detail: String {
        if let unavailableReason { return unavailableReason }
        if !attribution.isEmpty || !license.isEmpty { return [attribution, license].filter { !$0.isEmpty }.joined(separator: " · ") }
        return source == .externalURL ? "Downloaded from external URL" : "Imported audio"
    }
}

enum AudioImportError: LocalizedError {
    case unsupportedFormat, invalidURL, unsupportedLink, unsafeResponse, fileTooLarge, downloadFailed, notAVideo, duplicateVideo

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Choose a WAV, AIFF, or MP3 file."
        case .invalidURL: return "Enter a valid HTTPS audio URL."
        case .unsupportedLink: return "This link cannot provide an audio file in Brisa."
        case .unsafeResponse: return "The link did not return a supported audio file."
        case .fileTooLarge: return "Audio files must be smaller than 250 MB."
        case .downloadFailed: return "Brisa could not download this audio file."
        case .notAVideo: return "Paste a link to a single YouTube video, not a channel or a playlist."
        case .duplicateVideo: return "This video is already in your library."
        }
    }
}

enum ImportedSoundStore {
    static let maximumFileSize = 250 * 1024 * 1024
    static let supportedExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "mp3"]

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Brisa/Imported Audio", isDirectory: true)
    }

    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func isSupported(_ url: URL) -> Bool { supportedExtensions.contains(url.pathExtension.lowercased()) }

    static func fileExtension(for contentType: String) -> String? {
        switch contentType.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        case "audio/aiff", "audio/x-aiff": return "aiff"
        default: return nil
        }
    }

    static func makeStoredURL(id: String, sourceURL: URL) -> URL {
        directory.appendingPathComponent("\(id).\(sourceURL.pathExtension.lowercased())")
    }

    static func isYouTube(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be" || host.hasSuffix(".youtu.be")
    }
}
