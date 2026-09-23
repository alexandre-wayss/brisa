import Foundation

enum MixSharingTests {
    static let all: [TestCase] = [
        TestCase(name: "link round-trips a mix") {
            let mix = SharedMix(name: "Rainy study", levels: ["rain": 0.4, "brown": 0.25])
            let link = try unwrap(MixSharing.link(mix))
            try expectEqual(link.scheme, "brisa")
            try expectEqual(MixSharing.decode(link: link), mix)
        },
        TestCase(name: "file data round-trips a mix") {
            let mix = SharedMix(name: "Night", levels: ["pink": 0.3])
            try expectEqual(MixSharing.decode(data: try unwrap(MixSharing.fileData(mix))), mix)
        },
        TestCase(name: "shared(from:) drops imported and silent sounds") {
            let mix = Mix(name: "Mine", levels: ["rain": 0.5, "imported-123": 0.5, "white": 0])
            let result = try unwrap(MixSharing.shared(from: mix))
            try expectEqual(result.mix.levels, ["rain": 0.5])
            try expectEqual(result.omitted, 2)
        },
        TestCase(name: "shared(from:) clamps and rounds levels") {
            let result = try unwrap(MixSharing.shared(from: Mix(name: "Loud", levels: ["rain": 3, "pink": 0.12345])))
            try expectEqual(result.mix.levels, ["rain": 1, "pink": 0.123])
        },
        TestCase(name: "shared(from:) returns nil when nothing is portable") {
            try expectNil(MixSharing.shared(from: Mix(name: "Imported only", levels: ["imported-1": 0.5])))
        },
        TestCase(name: "shared(from:) falls back to a default name") {
            try expectEqual(try unwrap(MixSharing.shared(from: Mix(name: "  \n ", levels: ["rain": 0.5]))).mix.name, "Shared mix")
        },
        TestCase(name: "validated keeps only known sounds and clamps levels") {
            let raw = SharedMix(name: "Mixed", levels: ["rain": 2, "pink": -1, "unknown": 0.5, "brown": .nan, "white": 0.2])
            try expectEqual(MixSharing.validated(raw), SharedMix(name: "Mixed", levels: ["rain": 1, "white": 0.2]))
        },
        TestCase(name: "validated rejects unknown versions") {
            var raw = SharedMix(name: "Future", levels: ["rain": 0.5])
            raw.v = 2
            try expectNil(MixSharing.validated(raw))
        },
        TestCase(name: "validated rejects mixes without playable sounds") {
            try expectNil(MixSharing.validated(SharedMix(name: "Empty", levels: ["unknown": 0.5, "rain": 0])))
        },
        TestCase(name: "validated rejects oversized level lists") {
            var levels: [String: Double] = ["rain": 0.5]
            for index in 0..<(MixSharing.maxSounds * 2) { levels["fake-\(index)"] = 0.5 }
            try expectNil(MixSharing.validated(SharedMix(name: "Spam", levels: levels)))
        },
        TestCase(name: "cleanName strips control characters and limits length") {
            try expectEqual(MixSharing.cleanName("  Deep\nfocus\u{0007}  "), "Deepfocus")
            try expectEqual(MixSharing.cleanName(String(repeating: "a", count: 100))?.count, MixSharing.maxNameLength)
            try expectNil(MixSharing.cleanName(" \t "))
        },
        TestCase(name: "decode(link:) rejects other schemes and hosts") {
            let link = try unwrap(MixSharing.link(SharedMix(name: "Rain", levels: ["rain": 0.5])))
            var components = try unwrap(URLComponents(url: link, resolvingAgainstBaseURL: false))
            components.scheme = "https"
            try expectNil(MixSharing.decode(link: try unwrap(components.url)))
            components.scheme = "brisa"
            components.host = "other"
            try expectNil(MixSharing.decode(link: try unwrap(components.url)))
        },
        TestCase(name: "decode rejects garbage and oversized payloads") {
            try expectNil(MixSharing.decode(link: try unwrap(URL(string: "brisa://mix?d=not-json"))))
            try expectNil(MixSharing.decode(data: Data(repeating: 32, count: MixSharing.maxBytes + 1)))
        },
        TestCase(name: "stereo positions travel with the mix") {
            let mix = Mix(name: "Wide", levels: ["rain": 0.5, "wind": 0.3, "imported-1": 0.4], pans: ["rain": -0.456, "wind": 0, "imported-1": 1])
            let shared = try unwrap(MixSharing.shared(from: mix)).mix
            try expectEqual(shared.pans, ["rain": -0.46])
            try expectEqual(MixSharing.decode(link: try unwrap(MixSharing.link(shared)))?.pans, ["rain": -0.46])
        },
        TestCase(name: "validated clamps positions and drops ones for missing sounds") {
            let raw = SharedMix(name: "Pans", levels: ["rain": 0.5, "wind": 0.5], pans: ["rain": -4, "wind": .infinity, "pink": 0.5])
            try expectEqual(MixSharing.validated(raw)?.pans, ["rain": -1])
        },
        TestCase(name: "links without positions still open") {
            let json = #"{"v":1,"name":"Old","levels":{"rain":0.5}}"#
            let mix = try unwrap(MixSharing.decode(data: Data(json.utf8)))
            try expectNil(mix.pans)
        },
        TestCase(name: "saved mixes without positions still load") {
            let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","name":"Old","levels":{"rain":0.5}}]"#
            let mixes = try JSONDecoder().decode([Mix].self, from: Data(json.utf8))
            try expectEqual(mixes.first?.pans, [:])
        },
        TestCase(name: "base64URL uses URL-safe characters without padding") {
            let data = Data([0xfb, 0xff, 0xfe])
            let text = MixSharing.base64URL(data)
            try expect(!text.contains("+") && !text.contains("/") && !text.contains("="), text)
            try expectEqual(MixSharing.dataFromBase64URL(text), data)
        }
    ]
}
