import Foundation

enum SoundSynthesisTests {
    static let rate = SoundSynthesis.rate

    /// Average power at `frequency`, from Hann-windowed Goertzel over consecutive windows.
    static func power(_ samples: [Float], at frequency: Double, window: Int = 4096) -> Double {
        let coefficient = 2 * cos(2 * .pi * frequency / rate)
        var total = 0.0, windows = 0
        var start = 0
        while start + window <= samples.count {
            var s1 = 0.0, s2 = 0.0
            for i in 0..<window {
                let hann = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(window - 1))
                let s = Double(samples[start + i]) * hann + coefficient * s1 - s2
                s2 = s1; s1 = s
            }
            total += s1 * s1 + s2 * s2 - coefficient * s1 * s2
            windows += 1
            start += window
        }
        return total / Double(max(windows, 1))
    }

    /// How many dB louder the noise is at `low` than at `high`, averaged over nearby frequencies to steady the estimate.
    static func dropDB(_ samples: [Float], from low: Double, to high: Double) -> Double {
        let offsets = [-0.06, -0.03, 0, 0.03, 0.06]
        let lowPower = offsets.map { power(samples, at: low * (1 + $0)) }.reduce(0, +)
        let highPower = offsets.map { power(samples, at: high * (1 + $0)) }.reduce(0, +)
        return 10 * log10(lowPower / highPower)
    }

    static func noise(_ color: SoundSynthesis.NoiseColor) -> [Float] {
        SoundSynthesis.noise(color, frames: 4096 * 80, seed: 42)
    }

    static func rms(_ samples: [Float]) -> Double {
        (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    static func correlation(_ a: [Float], _ b: [Float]) -> Double {
        var ab = 0.0, aa = 0.0, bb = 0.0
        for i in a.indices { ab += Double(a[i] * b[i]); aa += Double(a[i] * a[i]); bb += Double(b[i] * b[i]) }
        return ab / (aa * bb).squareRoot()
    }

    static func expectNear(_ value: Double, _ expected: Double, within tolerance: Double, _ label: String,
                           file: StaticString = #fileID, line: UInt = #line) throws {
        try expect(abs(value - expected) <= tolerance, "\(label): \(String(format: "%.2f", value)), expected \(expected) ± \(tolerance)", file: file, line: line)
    }

    static let all: [TestCase] = [
        TestCase(name: "white noise is flat") {
            try expectNear(dropDB(noise(.white), from: 250, to: 4000), 0, within: 1.5, "250 Hz vs 4 kHz")
        },
        TestCase(name: "pink noise falls 3 dB per octave") {
            // 250 Hz to 4 kHz is four octaves.
            try expectNear(dropDB(noise(.pink), from: 250, to: 4000), 12, within: 1.5, "250 Hz vs 4 kHz")
        },
        TestCase(name: "brown noise falls 6 dB per octave") {
            // 200 Hz to 1.6 kHz is three octaves, well above the 20 Hz corner.
            try expectNear(dropDB(noise(.brown), from: 200, to: 1600), 18, within: 1.5, "200 Hz vs 1.6 kHz")
        },
        TestCase(name: "deep brown noise is darker than brown") {
            let brown = dropDB(noise(.brown), from: 200, to: 1600)
            try expect(dropDB(noise(.deepBrown), from: 200, to: 1600) > brown + 10)
        },
        TestCase(name: "green noise peaks in the middle") {
            let green = noise(.green)
            try expect(dropDB(green, from: 500, to: 60) > 6, "quieter at 60 Hz")
            try expect(dropDB(green, from: 500, to: 5000) > 6, "quieter at 5 kHz")
        },
        TestCase(name: "grey noise has more bass and a dip near 3.5 kHz") {
            let grey = noise(.grey)
            try expect(dropDB(grey, from: 60, to: 1000) > 8, "bass boost")
            try expect(dropDB(grey, from: 1000, to: 3500) > 3, "presence dip")
        },
        TestCase(name: "noise channels hit their loudness and are partly correlated") {
            for color in SoundSynthesis.NoiseColor.allCases {
                let channels = SoundSynthesis.noiseChannels(color, frames: 44100 * 4)
                try expectEqual(channels.count, 2)
                try expectNear(rms(channels[0]), color.targetRMS, within: color.targetRMS * 0.02, "\(color) left RMS")
                try expectNear(rms(channels[1]), color.targetRMS, within: color.targetRMS * 0.02, "\(color) right RMS")
                try expect(channels.allSatisfy { $0.allSatisfy { abs($0) < 1 } }, "\(color) stays below full scale")
                try expectNear(correlation(channels[0], channels[1]), SoundSynthesis.stereoCorrelation, within: 0.05, "\(color) correlation")
            }
        },
        TestCase(name: "noise is reproducible for a seed") {
            try expectEqual(SoundSynthesis.noise(.pink, frames: 1000, seed: 7), SoundSynthesis.noise(.pink, frames: 1000, seed: 7))
            try expect(SoundSynthesis.noise(.pink, frames: 1000, seed: 7) != SoundSynthesis.noise(.pink, frames: 1000, seed: 8))
        },
        TestCase(name: "binaural tones play the carrier left and carrier plus beat right") {
            for (id, tone) in SoundSynthesis.binauralTones {
                let channels = SoundSynthesis.toneChannels(tone)
                // Two-second windows resolve beats as narrow as 2.5 Hz.
                let window = 44100 * 2
                let left = Array(channels[0].prefix(window * 2)), right = Array(channels[1].prefix(window * 2))
                try expect(power(left, at: tone.carrier, window: window) > 100 * power(left, at: tone.carrier + tone.beat, window: window), "\(id) left")
                try expect(power(right, at: tone.carrier + tone.beat, window: window) > 100 * power(right, at: tone.carrier, window: window), "\(id) right")
            }
        },
        TestCase(name: "binaural tones loop without a click") {
            for (id, tone) in SoundSynthesis.binauralTones {
                for channel in SoundSynthesis.toneChannels(tone) {
                    // The step from the last sample back to the first must look like any other step.
                    let wrap = abs(channel[0] - channel[channel.count - 1])
                    let largestStep = zip(channel, channel.dropFirst()).map { abs($1 - $0) }.max() ?? 0
                    try expect(wrap <= largestStep * 1.01, "\(id) jumps \(wrap) at the loop point")
                }
            }
        },
        TestCase(name: "every synthesized sound is in the library") {
            let ids = Set(library.map(\.id))
            for color in SoundSynthesis.NoiseColor.allCases { try expect(ids.contains(color.rawValue), color.rawValue) }
            for id in SoundSynthesis.binauralTones.keys { try expect(ids.contains(id), id) }
        },
        TestCase(name: "living mix stays within its depth") {
            for id in ["rain", "brown", "realForest"] {
                var low = 1.0, high = 1.0
                for second in stride(from: 0.0, through: 600, by: 0.5) {
                    let factor = LivingMix.factor(for: id, at: second, depth: 0.35)
                    low = min(low, factor); high = max(high, factor)
                }
                try expect(low >= 0.65 && high <= 1.35, "\(id) range \(low)...\(high)")
                try expect(high - low > 0.3, "\(id) barely moves: \(low)...\(high)")
            }
        },
        TestCase(name: "living mix moves slowly") {
            // At the ticker's slowest rate each step stays under 1% (about 0.1 dB), far below what the ear notices.
            for second in stride(from: 0.0, through: 300, by: 1.0 / 15) {
                let step = abs(LivingMix.factor(for: "rain", at: second + 1.0 / 15, depth: 0.5) - LivingMix.factor(for: "rain", at: second, depth: 0.5))
                try expect(step < 0.01, "step of \(step) at \(second) s")
            }
        },
        TestCase(name: "living mix is off at zero depth and differs between sounds") {
            try expectEqual(LivingMix.factor(for: "rain", at: 123, depth: 0), 1)
            try expect(LivingMix.factor(for: "rain", at: 30, depth: 0.35) != LivingMix.factor(for: "wind", at: 30, depth: 0.35))
            try expectEqual(LivingMix.stableHash("rain"), LivingMix.stableHash("rain"))
        }
    ]
}
