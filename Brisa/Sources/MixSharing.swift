import Foundation
import AppKit

/// A mix in a form that can travel between Macs, as a `.brisamix` file or a `brisa://mix?d=…` link.
struct SharedMix: Codable, Equatable {
    var v = 1
    var name: String
    var levels: [String: Double]
}

enum MixSharing {
    static let fileExtension = "brisamix"
    static let maxNameLength = 60
    static let maxSounds = 16
    static let maxBytes = 8 * 1024

    /// Only Brisa's built-in sounds can be shared; imported files exist only on the Mac that imported them.
    static var portableIDs: Set<String> { Set(library.map(\.id)) }

    /// The shareable part of a saved mix, and how many sounds had to be left out. Nil if nothing can be shared.
    static func shared(from mix: Mix) -> (mix: SharedMix, omitted: Int)? {
        let ids = portableIDs
        let kept = mix.levels.filter { ids.contains($0.key) && $0.value.isFinite && $0.value > 0 }
        guard !kept.isEmpty, kept.count <= maxSounds else { return nil }
        let levels = kept.mapValues { (min($0, 1) * 1000).rounded() / 1000 }
        return (SharedMix(name: cleanName(mix.name) ?? "Shared mix", levels: levels), mix.levels.count - kept.count)
    }

    static func fileData(_ mix: SharedMix) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(mix)
    }

    static func link(_ mix: SharedMix) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let json = try? encoder.encode(mix) else { return nil }
        var components = URLComponents()
        components.scheme = "brisa"
        components.host = "mix"
        components.queryItems = [URLQueryItem(name: "d", value: base64URL(json))]
        return components.url
    }

    static func decode(data: Data) -> SharedMix? {
        guard data.count <= maxBytes, let raw = try? JSONDecoder().decode(SharedMix.self, from: data) else { return nil }
        return validated(raw)
    }

    static func decode(link: URL) -> SharedMix? {
        guard link.scheme == "brisa", link.host == "mix",
              let payload = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value,
              payload.count <= maxBytes * 2, let data = dataFromBase64URL(payload) else { return nil }
        return decode(data: data)
    }

    /// Everything that arrives from outside is checked: known sounds only, sane levels, a plain name.
    static func validated(_ raw: SharedMix) -> SharedMix? {
        guard raw.v == 1, let name = cleanName(raw.name) else { return nil }
        let ids = portableIDs
        var levels: [String: Double] = [:]
        for (id, level) in raw.levels {
            guard ids.contains(id), level.isFinite else { continue }
            let clamped = min(max(level, 0), 1)
            if clamped > 0 { levels[id] = clamped }
        }
        guard !levels.isEmpty, levels.count <= maxSounds, raw.levels.count <= maxSounds * 2 else { return nil }
        return SharedMix(name: name, levels: levels)
    }

    static func cleanName(_ text: String) -> String? {
        let scalars = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) }
        let trimmed = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func dataFromBase64URL(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }

    /// Readable list for the confirmation dialog, e.g. "Light Rain, Brown Noise".
    static func soundNames(in mix: SharedMix) -> String {
        let names = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0.name) })
        return mix.levels.keys.sorted().compactMap { names[$0] }.joined(separator: ", ")
    }
}

extension AppModel {
    /// Adds a shared mix, renaming it if you already have one with that name.
    @discardableResult
    func importSharedMix(_ shared: SharedMix, play: Bool) -> Mix {
        var name = shared.name
        var suffix = 2
        while mixes.contains(where: { $0.name == name }) {
            name = "\(shared.name) (\(suffix))"
            suffix += 1
        }
        let mix = Mix(name: name, levels: shared.levels)
        mixes.append(mix)
        persistMixes()
        if play { applyMix(mix.levels) }
        return mix
    }
}
