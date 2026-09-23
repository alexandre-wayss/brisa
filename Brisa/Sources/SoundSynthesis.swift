import Foundation
import AVFoundation

/// Noise colours and binaural tones, rendered once into stereo buffers that loop without a seam.
enum SoundSynthesis {
    static let rate = 44100.0

    // MARK: Noise

    enum NoiseColor: String, CaseIterable {
        case white, pink, brown, deepBrown, green, grey

        /// Loudness matches the earlier generator, so saved mixes keep their balance.
        var targetRMS: Double {
            switch self {
            case .white: return 0.131
            case .pink: return 0.140
            case .brown: return 0.059
            case .deepBrown: return 0.065
            case .green: return 0.116
            case .grey: return 0.114
            }
        }
    }

    /// How alike the two channels are. 1 would be mono; lower sounds wider, as if the noise surrounds you.
    static let stereoCorrelation = 0.3
    static let noiseSeconds = 24.0

    static func noiseBuffer(_ color: NoiseColor) -> AVAudioPCMBuffer {
        let frames = Int(rate * noiseSeconds)
        let channels = noiseChannels(color, frames: frames)
        return seamlessLoop(makeBuffer(channels))
    }

    /// Two partly correlated channels of the given colour, normalised to its target loudness.
    static func noiseChannels(_ color: NoiseColor, frames: Int, seed: UInt64 = 0x5EED_B815A) -> [[Float]] {
        let a = noise(color, frames: frames, seed: seed)
        let b = noise(color, frames: frames, seed: seed &+ 0x9E37_79B9_7F4A_7C15)
        let side = (1 - stereoCorrelation * stereoCorrelation).squareRoot()
        let right = zip(a, b).map { Float(stereoCorrelation) * $0 + Float(side) * $1 }
        return [a, right].map { normalized($0, rms: color.targetRMS) }
    }

    /// One channel of coloured noise, before normalisation.
    static func noise(_ color: NoiseColor, frames: Int, seed: UInt64) -> [Float] {
        var random = Xorshift(seed: seed)
        var output = [Float](repeating: 0, count: frames)
        switch color {
        case .white:
            for i in 0..<frames { output[i] = Float(random.next()) }
        case .pink:
            var pink = PinkFilter()
            for i in 0..<frames { output[i] = Float(pink.process(random.next())) }
        case .brown, .deepBrown:
            // A leaky integrator falls 6 dB per octave above ~20 Hz; the DC blocker keeps it centred.
            var brown = OnePoleLowPass(cutoff: 20, rate: rate)
            var dc = DCBlocker()
            var deep = OnePoleLowPass(cutoff: 220, rate: rate)
            for i in 0..<frames {
                var x = dc.process(brown.process(random.next()))
                if color == .deepBrown { x = deep.process(x) }
                output[i] = Float(x)
            }
        case .green:
            // Noise gathered around the middle of the spectrum, near 500 Hz, fading evenly on both sides.
            var band = Biquad.bandPass(frequency: 500, q: 0.7, rate: rate)
            for i in 0..<frames { output[i] = Float(band.process(random.next())) }
        case .grey:
            // Roughly the inverse of the ear's sensitivity: more low end, a dip where hearing is keenest.
            var low = Biquad.lowShelf(frequency: 160, gainDB: 12, rate: rate)
            var dip = Biquad.peaking(frequency: 3500, gainDB: -6, q: 1, rate: rate)
            var high = Biquad.highShelf(frequency: 10000, gainDB: 3, rate: rate)
            for i in 0..<frames { output[i] = Float(high.process(dip.process(low.process(random.next())))) }
        }
        return output
    }

    static func normalized(_ samples: [Float], rms target: Double) -> [Float] {
        let rms = (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(samples.count, 1))).squareRoot()
        guard rms > 0 else { return samples }
        let gain = Float(target / rms)
        // tanh only touches the rare peaks near full scale.
        return samples.map { tanhf($0 * gain) }
    }

    // MARK: Binaural tones

    /// Each ear hears a slightly different pitch; the brain perceives the difference as a slow beat. Needs headphones.
    struct BinauralTone {
        let carrier: Double
        let beat: Double
    }

    static let binauralTones: [String: BinauralTone] = [
        "binauralDelta": BinauralTone(carrier: 140, beat: 2.5),
        "binauralTheta": BinauralTone(carrier: 180, beat: 6),
        "binauralAlpha": BinauralTone(carrier: 200, beat: 10),
        "binauralBeta": BinauralTone(carrier: 220, beat: 16)
    ]

    static let toneSeconds = 16.0
    static let toneAmplitude = 0.15

    static func isBinaural(_ id: String) -> Bool { binauralTones[id] != nil }

    static func toneBuffer(_ tone: BinauralTone) -> AVAudioPCMBuffer {
        makeBuffer(toneChannels(tone))
    }

    /// Left plays the carrier, right the carrier plus the beat. Every frequency completes whole cycles
    /// within `toneSeconds`, so the buffer loops with no click and needs no crossfade.
    static func toneChannels(_ tone: BinauralTone) -> [[Float]] {
        let frames = Int(rate * toneSeconds)
        return [tone.carrier, tone.carrier + tone.beat].map { frequency in
            (0..<frames).map { Float(toneAmplitude * sin(2 * .pi * frequency * Double($0) / rate)) }
        }
    }

    // MARK: Helpers

    static func makeBuffer(_ channels: [[Float]]) -> AVAudioPCMBuffer {
        let frames = channels[0].count
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels.count))!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for (index, samples) in channels.enumerated() {
            samples.withUnsafeBufferPointer { buffer.floatChannelData![index].update(from: $0.baseAddress!, count: frames) }
        }
        return buffer
    }

    /// Fast, reproducible uniform noise in -1...1.
    struct Xorshift {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x2545_F491_4F6C_DD1D : seed }
        mutating func next() -> Double {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
    }

    /// Paul Kellet's filter: -3 dB per octave, within 0.05 dB across the audible range.
    struct PinkFilter {
        private var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0
        mutating func process(_ white: Double) -> Double {
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            return pink
        }
    }

    struct OnePoleLowPass {
        private let pole: Double
        private var state = 0.0
        init(cutoff: Double, rate: Double) { pole = exp(-2 * .pi * cutoff / rate) }
        mutating func process(_ x: Double) -> Double {
            state = pole * state + (1 - pole) * x
            return state
        }
    }

    struct DCBlocker {
        private var lastInput = 0.0, lastOutput = 0.0
        mutating func process(_ x: Double) -> Double {
            lastOutput = x - lastInput + 0.9995 * lastOutput
            lastInput = x
            return lastOutput
        }
    }

    /// Standard second-order filters (Robert Bristow-Johnson's audio EQ cookbook).
    struct Biquad {
        private let b0, b1, b2, a1, a2: Double
        private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
            self.b0 = b0 / a0; self.b1 = b1 / a0; self.b2 = b2 / a0; self.a1 = a1 / a0; self.a2 = a2 / a0
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }

        static func bandPass(frequency: Double, q: Double, rate: Double) -> Biquad {
            let w = 2 * .pi * frequency / rate, alpha = sin(w) / (2 * q)
            return Biquad(b0: alpha, b1: 0, b2: -alpha, a0: 1 + alpha, a1: -2 * cos(w), a2: 1 - alpha)
        }

        static func peaking(frequency: Double, gainDB: Double, q: Double, rate: Double) -> Biquad {
            let a = pow(10, gainDB / 40), w = 2 * .pi * frequency / rate, alpha = sin(w) / (2 * q)
            return Biquad(b0: 1 + alpha * a, b1: -2 * cos(w), b2: 1 - alpha * a,
                          a0: 1 + alpha / a, a1: -2 * cos(w), a2: 1 - alpha / a)
        }

        /// Shelf slope of 1, the steepest without overshoot.
        private static func shelfAlpha(_ w: Double) -> Double { sin(w) / 2 * 2.0.squareRoot() }

        static func lowShelf(frequency: Double, gainDB: Double, rate: Double) -> Biquad {
            let a = pow(10, gainDB / 40), w = 2 * .pi * frequency / rate, cw = cos(w)
            let root = 2 * a.squareRoot() * shelfAlpha(w)
            return Biquad(b0: a * ((a + 1) - (a - 1) * cw + root), b1: 2 * a * ((a - 1) - (a + 1) * cw),
                          b2: a * ((a + 1) - (a - 1) * cw - root), a0: (a + 1) + (a - 1) * cw + root,
                          a1: -2 * ((a - 1) + (a + 1) * cw), a2: (a + 1) + (a - 1) * cw - root)
        }

        static func highShelf(frequency: Double, gainDB: Double, rate: Double) -> Biquad {
            let a = pow(10, gainDB / 40), w = 2 * .pi * frequency / rate, cw = cos(w)
            let root = 2 * a.squareRoot() * shelfAlpha(w)
            return Biquad(b0: a * ((a + 1) + (a - 1) * cw + root), b1: -2 * a * ((a - 1) + (a + 1) * cw),
                          b2: a * ((a + 1) + (a - 1) * cw - root), a0: (a + 1) - (a - 1) * cw + root,
                          a1: 2 * ((a - 1) - (a + 1) * cw), a2: (a + 1) - (a - 1) * cw - root)
        }
    }
}

// MARK: - Living mix

/// Slowly drifts each sound's volume up and down so a long session doesn't feel static.
enum LivingMix {
    enum Intensity: String, CaseIterable, Identifiable {
        case subtle, moderate, strong
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        /// The largest change, as a fraction of the sound's own level.
        var depth: Double {
            switch self {
            case .subtle: return 0.2
            case .moderate: return 0.35
            case .strong: return 0.5
            }
        }
    }

    /// A volume multiplier in 1 ± depth. Two slow waves with periods picked per sound keep sounds from moving together.
    static func factor(for id: String, at time: TimeInterval, depth: Double) -> Double {
        guard depth > 0 else { return 1 }
        let seed = stableHash(id)
        let slow = 45 + Double(seed % 40)             // 45–84 s
        let fast = 17 + Double((seed / 40) % 12)      // 17–28 s
        let phase = Double(seed % 628) / 100
        let wave = 0.65 * sin(2 * .pi * time / slow + phase) + 0.35 * sin(2 * .pi * time / fast + phase * 1.7)
        return 1 + depth * wave
    }

    /// FNV-1a, so a sound keeps the same rhythm every launch (Swift's `hashValue` changes per run).
    static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf2_9ce4_8422_2325 as UInt64) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}
