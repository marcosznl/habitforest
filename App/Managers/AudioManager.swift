import AVFoundation
import AudioToolbox
import Foundation

enum AmbientSound: String, CaseIterable, Identifiable {
    case silence, rain, wind, forest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .silence: "Silêncio"
        case .rain: "Chuva"
        case .wind: "Vento na floresta"
        case .forest: "Floresta viva"
        }
    }

    var symbolName: String {
        switch self {
        case .silence: "speaker.slash.fill"
        case .rain: "cloud.rain.fill"
        case .wind: "wind"
        case .forest: "bird.fill"
        }
    }
}

enum SoundEffect {
    case waterDrop, leafRustle, chime
}

/// Ambient loops and organic effects, synthesized in real time with AVAudioEngine so the app
/// ships without audio assets.
final class AudioManager {
    static let shared = AudioManager()

    private let engine = AVAudioEngine()
    private let effectsPlayer = AVAudioPlayerNode()
    private var ambientNode: AVAudioSourceNode?
    private let generator = AmbientGenerator()
    private let format: AVAudioFormat
    private var effectBuffers: [SoundEffect: AVAudioPCMBuffer] = [:]

    private(set) var currentAmbient: AmbientSound = .silence

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.attach(effectsPlayer)
        engine.connect(effectsPlayer, to: engine.mainMixerNode, format: format)

        let generator = generator
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let (left, right) = generator.nextSample()
                if buffers.count > 0, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self) { l[frame] = left }
                if buffers.count > 1, let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) { r[frame] = right }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        ambientNode = node

        effectBuffers[.waterDrop] = makeBuffer(duration: 0.35) { t in
            let freq = 1_400 * exp(-t * 9) + 380
            return sin(2 * .pi * freq * t) * exp(-t * 14) * 0.6
        }
        effectBuffers[.leafRustle] = makeBuffer(duration: 0.3) { t in
            Double.random(in: -1...1) * sin(.pi * t / 0.3) * 0.18
        }
        effectBuffers[.chime] = makeBuffer(duration: 1.6) { t in
            let partials = [523.25, 659.25, 783.99, 1_046.5]
            return partials.enumerated().reduce(0) { sum, item in
                sum + sin(2 * .pi * item.element * t) * exp(-t * (2.2 + Double(item.offset))) * 0.12
            }
        }
    }

    // MARK: - Effects

    func play(_ effect: SoundEffect) {
        guard AppGroup.defaults.bool(forKey: SettingsKey.soundsEnabled), let buffer = effectBuffers[effect] else { return }
        guard startEngineIfNeeded() else {
            AudioServicesPlaySystemSound(kSystemSoundID_UserPreferredAlert)
            return
        }
        effectsPlayer.volume = Float(AppGroup.defaults.double(forKey: SettingsKey.effectsVolume))
        effectsPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !effectsPlayer.isPlaying { effectsPlayer.play() }
    }

    // MARK: - Ambient

    func setAmbient(_ sound: AmbientSound) {
        currentAmbient = sound
        generator.sound = sound
        generator.volume = Float(AppGroup.defaults.double(forKey: SettingsKey.ambientVolume))
        if sound != .silence { _ = startEngineIfNeeded() }
    }

    func setAmbientVolume(_ volume: Double) {
        AppGroup.defaults.set(volume, forKey: SettingsKey.ambientVolume)
        generator.volume = Float(volume)
    }

    func stopAmbient() {
        setAmbient(.silence)
    }

    // MARK: - Internals

    private func startEngineIfNeeded() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private func makeBuffer(duration: Double, sample: (Double) -> Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            let value = Float(sample(Double(frame) / format.sampleRate))
            buffer.floatChannelData?[0][frame] = value
            buffer.floatChannelData?[1][frame] = value
        }
        return buffer
    }
}

/// Real-time noise synthesis. Accessed from the audio render thread; the few fields written by
/// the main thread are plain scalars, which is acceptable for this use.
private final class AmbientGenerator: @unchecked Sendable {
    var sound: AmbientSound = .silence
    var volume: Float = 0.5

    private var gain: Float = 0
    private var lowpassL: Float = 0
    private var lowpassR: Float = 0
    private var brown: Float = 0
    private var phase: Double = 0
    private var dropEnvelope: Float = 0
    private var dropFreq: Double = 0
    private var dropPhase: Double = 0
    private var chirpRemaining = 0
    private var chirpPhase: Double = 0
    private let sampleRate = 44_100.0

    func nextSample() -> (Float, Float) {
        let target: Float = sound == .silence ? 0 : volume
        gain += (target - gain) * 0.0005
        guard gain > 0.0001 else { return (0, 0) }

        phase += 1 / sampleRate
        let white = Float.random(in: -1...1)
        var left: Float = 0
        var right: Float = 0

        switch sound {
        case .rain, .silence:
            lowpassL += (white - lowpassL) * 0.35
            lowpassR += (Float.random(in: -1...1) - lowpassR) * 0.35
            left = lowpassL * 0.35
            right = lowpassR * 0.35
            if dropEnvelope < 0.01, Int.random(in: 0..<2_500) == 0 {
                dropEnvelope = Float.random(in: 0.2...0.5)
                dropFreq = Double.random(in: 1_800...3_200)
            }
            dropPhase += dropFreq / sampleRate
            let drop = Float(sin(2 * .pi * dropPhase)) * dropEnvelope
            dropEnvelope *= 0.9985
            left += drop * 0.4
            right += drop * 0.25
        case .wind, .forest:
            brown = (brown + white * 0.02) * 0.998
            let gust = Float(0.55 + 0.45 * sin(2 * .pi * phase * 0.07) * sin(2 * .pi * phase * 0.031))
            lowpassL += (brown - lowpassL) * 0.08
            left = lowpassL * 2.2 * gust
            right = brown * 2.0 * gust
            if sound == .forest {
                if chirpRemaining == 0, Int.random(in: 0..<160_000) == 0 { chirpRemaining = 9_000 }
                if chirpRemaining > 0 {
                    let t = Double(9_000 - chirpRemaining) / sampleRate
                    chirpPhase += (3_200 + 900 * sin(2 * .pi * 14 * t)) / sampleRate
                    let env = Float(sin(.pi * Double(9_000 - chirpRemaining) / 9_000))
                    let chirp = Float(sin(2 * .pi * chirpPhase)) * env * 0.12
                    left += chirp * 0.6
                    right += chirp
                    chirpRemaining -= 1
                }
            }
        }
        return (left * gain, right * gain)
    }
}
