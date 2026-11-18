import AVFoundation
import Foundation

/// Synthesized local arcade cues; no bundled samples, network, or third-party sounds.
/// Kept outside the game engine and saved-state format.
@MainActor
final class DivideAudio {
    static let shared = DivideAudio()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let rate: Double = 44_100
    private var running = false
    var enabled = UserDefaults.standard.object(forKey: "VectorDivide.SoundEnabled.v1") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "VectorDivide.SoundEnabled.v1") }
    }

    private init() {
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.23
    }

    enum Cue {
        case capture, damage, victory, start, trace
    }

    func play(_ cue: Cue, magnitude: Double = 1) {
        guard enabled else { return }
        do {
            if !running {
                try engine.start()
                player.play()
                running = true
            }
        } catch { return }
        let duration: Double
        switch cue {
        case .capture: duration = 0.46
        case .damage: duration = 0.35
        case .victory: duration = 0.88
        case .start: duration = 0.23
        case .trace: duration = 0.12
        }
        let frames = AVAudioFrameCount(duration*rate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let output = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        let strength = min(1.65, max(0.7, magnitude/10))
        let twoPi = 2 * Double.pi
        for frame in 0..<Int(frames) {
            let t = Double(frame)/rate
            let u = t/duration
            let envelope = min(1.0, t/0.012) * pow(max(0, 1-u), cue == .victory ? 0.65 : 1.65)
            let sample: Double
            switch cue {
            case .capture:
                let frequency = 230 + 500*u + 115*strength
                sample = 0.65*sin(twoPi*(230*t + (250+60*strength)*t*t))
                    + 0.22*sin(twoPi*frequency*t)
                    + 0.12*sin(twoPi*82*t)*exp(-12*u)
            case .damage:
                let noise = sin(Double(frame)*53.71)*sin(Double(frame)*12.83)
                sample = 0.50*noise + 0.52*sin(twoPi*(190*t-155*t*t))
            case .victory:
                let tones = [392.0, 523.25, 659.25, 783.99]
                let step = min(3, Int(u*4))
                sample = 0.54*sin(twoPi*tones[step]*t)
                    + 0.19*sin(twoPi*tones[step]*2*t)
                    + 0.14*sin(twoPi*130.8*t)
            case .start:
                sample = 0.65*sin(twoPi*(270*t+350*t*t))
                    + 0.20*sin(twoPi*540*t)
            case .trace:
                sample = 0.44*sin(twoPi*(570*t+560*t*t))
                    + 0.24*sin(twoPi*920*t)
            }
            output[frame] = Float(max(-1, min(1, sample*envelope*0.62)))
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }
}
