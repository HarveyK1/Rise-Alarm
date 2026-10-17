import AVFoundation
import MediaPlayer
import UIKit

/// Keeps the app alive with a silent loop while alarms are set, and plays the alarm itself.
/// On iOS 17 third-party apps have no alarm API (AlarmKit is iOS 26+), so staying alive is the only way to ring.
@MainActor
final class AlarmAudio {
    private let session = AVAudioSession.sharedInstance()
    private var silence: AVAudioPlayer?
    private var ringer: AVAudioPlayer?
    private var previewer: AVAudioPlayer?
    private var ringing: (sound: URL, volume: Double)?
    private var volumeWatch: NSKeyValueObservation?
    private var volumeBeforePreview: Float?
    private var rampEnds = Date.distantPast
    private var ducked = false
    private let speaker = AVSpeechSynthesizer()
    private let speechDone = SpeechDone()

    init() {
        let nc = NotificationCenter.default
        // A call or Siri interrupts us; pick straight back up afterwards.
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            MainActor.assumeIsolated { self?.restartIfNeeded() }
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    func setKeepAlive(_ on: Bool) {
        if on, silence == nil {
            activate(mixWithOthers: ringer == nil)
            silence = try? AVAudioPlayer(contentsOf: SoundFiles.silence)
            silence?.numberOfLoops = -1
            silence?.play()
        } else if !on, let player = silence, ringer == nil {
            player.stop()
            silence = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func startRinging(_ sound: URL, volume: Double, ramp: Bool = false) {
        ringing = (sound, volume)
        ducked = false
        activate(mixWithOthers: false)   // stops other apps' audio while ringing; plays even on silent
        ringer?.stop()
        // An imported sound that can't play (file gone) still rings, with a built-in one.
        ringer = (try? AVAudioPlayer(contentsOf: sound)) ?? (try? AVAudioPlayer(contentsOf: AlarmSound.beeps.url))
        ringer?.numberOfLoops = -1
        if ramp {
            // Gentle wake-up: start near silent and fade up to full over 30 s.
            ringer?.volume = 0.05
            ringer?.play()
            ringer?.setVolume(1, fadeDuration: 30)
            rampEnds = Date().addingTimeInterval(30)
        } else {
            ringer?.play()
            rampEnds = .distantPast
        }
        SystemVolume.set(Float(volume))
        lockVolume(Float(volume))
    }

    /// Backup loud sound: nobody responded, so switch to a harsh siren at full phone volume.
    func escalate() {
        guard let current = ringing else { return }
        startRinging(current.sound == AlarmSound.siren.url ? AlarmSound.buzzer.url : AlarmSound.siren.url, volume: 1)
    }

    /// Talking alarm: reads text out while the alarm drops quieter, then brings it back up.
    func speak(_ text: String) {
        guard ringer != nil, !ducked else { return }
        ringer?.setVolume(0.2, fadeDuration: 0.3)
        speechDone.onFinish = { [weak self] in
            guard let self, !ducked else { return }
            ringer?.setVolume(1, fadeDuration: max(0.3, rampEnds.timeIntervalSinceNow))   // resume any gentle ramp
        }
        speaker.delegate = speechDone
        speaker.speak(AVSpeechUtterance(string: text))
    }

    /// Like the Clock app, the volume buttons can't turn a ringing alarm down: push it straight back up.
    private func lockVolume(_ target: Float) {
        volumeWatch = session.observe(\.outputVolume, options: [.new]) { _, change in
            guard let now = change.newValue, now < target - 0.01 else { return }
            Task { @MainActor in SystemVolume.set(target) }
        }
    }

    /// Quieter while a mission is being done, full volume again if the user wanders off.
    func duck(_ on: Bool) {
        ducked = on
        if on { speaker.stopSpeaking(at: .immediate) }
        ringer?.setVolume(on ? 0.15 : 1, fadeDuration: 0.3)
    }

    /// "Say the word" needs the mic (.playAndRecord, still out of the speaker); mute the alarm so it doesn't hear itself.
    func setListening(_ on: Bool) {
        if on {
            ringer?.setVolume(0, fadeDuration: 0.2)
            try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
            try? session.setActive(true)
        } else {
            activate(mixWithOthers: ringer == nil)
            ringer?.setVolume(0.15, fadeDuration: 0.2)
        }
    }

    func stopRinging() {
        volumeWatch = nil
        speaker.stopSpeaking(at: .immediate)
        ducked = false
        rampEnds = .distantPast
        ringer?.stop()
        ringer = nil
        ringing = nil
        if silence != nil { activate(mixWithOthers: true) }
    }

    /// Plays 3 s at the alarm's volume (by setting the phone volume like the real alarm), then restores it.
    func preview(_ sound: URL, volume: Double) {
        if ringer == nil { activate(mixWithOthers: true) }
        if volumeBeforePreview == nil { volumeBeforePreview = session.outputVolume }
        SystemVolume.set(Float(volume))
        previewer?.stop()
        let player = try? AVAudioPlayer(contentsOf: sound)
        player?.play()
        previewer = player
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            player?.stop()
            guard let self, previewer === player, let before = volumeBeforePreview else { return }   // a newer preview owns it
            volumeBeforePreview = nil
            SystemVolume.set(before)
        }
    }

    func restartIfNeeded() {
        if let player = silence, !player.isPlaying {
            activate(mixWithOthers: ringer == nil)
            player.play()
        }
        if let player = ringer, !player.isPlaying { player.play() }
    }

    private func rebuild() {
        let keepAlive = silence != nil, current = ringing
        silence = nil
        ringer = nil
        if keepAlive { setKeepAlive(true) }
        if let current { startRinging(current.sound, volume: current.volume) }
    }

    private func activate(mixWithOthers: Bool) {
        try? session.setCategory(.playback, options: mixWithOthers ? [.mixWithOthers] : [])
        try? session.setActive(true)
    }
}

/// Tells AlarmAudio when a spoken line has finished.
private final class SpeechDone: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (@MainActor () -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finish = onFinish
        Task { @MainActor in finish?() }
    }
}

/// Sets the phone's media volume through a hidden MPVolumeView slider (the only way apps can).
@MainActor
enum SystemVolume {
    static func set(_ value: Float) {
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first }
            .first?
            .addSubview(view)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            (view.subviews.first { $0 is UISlider } as? UISlider)?.value = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { view.removeFromSuperview() }
        }
    }
}

// MARK: - Sounds

/// Alarm sounds are generated, not bundled, so nothing is copied from other apps.
enum AlarmSound: String, Codable, CaseIterable, Identifiable {
    case beeps, siren, buzzer, chirps, chimes

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var fileName: String { "rise-\(rawValue)-v1.wav" }   // bump v1 when a sound changes
    var url: URL { SoundFiles.dir.appendingPathComponent(fileName) }

    /// Sample value (-1...1) at time t seconds.
    func sample(_ t: Double) -> Double {
        switch self {
        case .beeps:    // four quick beeps, then a pause
            let p = t.truncatingRemainder(dividingBy: 1)
            return p < 0.5 && (p * 8).truncatingRemainder(dividingBy: 1) < 0.6 ? tone(1760, t) : 0
        case .siren:    // swoops between 600 and 1400 Hz every 1.5 s
            return tone(phase: 2 * .pi * 1000 * t - 400 * 1.5 * cos(2 * .pi * t / 1.5))
        case .buzzer:   // harsh two-tone, four switches a second
            return tone((t * 4).truncatingRemainder(dividingBy: 2) < 1 ? 880 : 1320, t)
        case .chirps:   // fast rising chirps, 2 to 4 kHz
            let p = t.truncatingRemainder(dividingBy: 0.2)
            return p < 0.1 ? tone(phase: 2 * .pi * (2000 * p + 10_000 * p * p)) : 0
        case .chimes:   // gentle three-note chime every 2 s
            let p = t.truncatingRemainder(dividingBy: 2)
            return [(0.0, 1047.0), (0.25, 1319.0), (0.5, 1568.0)].reduce(0) { sum, note in
                let dt = p - note.0
                return dt < 0 ? sum : sum + sin(2 * .pi * note.1 * dt) * exp(-3 * dt) * 0.4
            }
        }
    }
}

private func tone(_ frequency: Double, _ t: Double) -> Double { tone(phase: 2 * .pi * frequency * t) }
private func tone(phase: Double) -> Double { tanh(3 * sin(phase)) * 0.9 }

enum SoundFiles {
    /// Library/Sounds is where iOS looks for custom notification sounds.
    static let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Sounds")
    static var silence: URL { dir.appendingPathComponent("rise-silence.wav") }

    static func generate() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        write(silence, seconds: 2) { _ in 0 }
        for sound in AlarmSound.allCases {
            write(sound.url, seconds: 29, sound.sample)   // notification sounds must be under 30 s
        }
    }

    private static func write(_ url: URL, seconds: Int, _ wave: (Double) -> Double) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let rate = 22_050, n = seconds * rate
        var samples = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            samples[i] = Int16(max(-1, min(1, wave(Double(i) / Double(rate)))) * 30_000)
        }
        var data = Data()
        func put(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func put32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }
        put("RIFF"); put32(36 + n * 2); put("WAVE")
        put("fmt "); put32(16); put16(1); put16(1); put32(rate); put32(rate * 2); put16(2); put16(16)
        put("data"); put32(n * 2)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }   // iOS is little-endian, like WAV
        try? data.write(to: url)
    }
}
