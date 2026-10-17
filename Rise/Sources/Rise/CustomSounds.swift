import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// A sound the user imported from the Files app.
struct CustomSound: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let ext: String

    /// The full original file, used while ringing (any length, loops).
    var url: URL { SoundLibrary.dir.appendingPathComponent("\(id.uuidString).\(ext)") }
    /// First 29 s as CAF in Library/Sounds: iOS only plays short PCM files as notification sounds.
    var notificationName: String { "custom-\(id.uuidString).caf" }
}

final class SoundLibrary: ObservableObject {
    static let shared = SoundLibrary()
    static let dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CustomSounds")

    @Published private(set) var sounds: [CustomSound] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: "customSounds"),
           let saved = try? JSONDecoder().decode([CustomSound].self, from: data) {
            sounds = saved
        }
    }

    func sound(_ id: UUID) -> CustomSound? { sounds.first { $0.id == id } }

    /// Copies the picked file into the app and makes the notification copy. nil if it isn't playable audio.
    func importSound(from picked: URL) -> CustomSound? {
        let access = picked.startAccessingSecurityScopedResource()
        defer { if access { picked.stopAccessingSecurityScopedResource() } }
        let ext = picked.pathExtension.isEmpty ? "m4a" : picked.pathExtension.lowercased()
        let sound = CustomSound(id: UUID(), name: picked.deletingPathExtension().lastPathComponent, ext: ext)
        do {
            try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: picked, to: sound.url)
            _ = try AVAudioPlayer(contentsOf: sound.url)   // throws if it isn't audio iOS can play
            try writeNotificationCopy(of: sound)
        } catch {
            delete(sound)
            return nil
        }
        sounds.append(sound)
        save()
        return sound
    }

    func delete(_ sound: CustomSound) {
        try? FileManager.default.removeItem(at: sound.url)
        try? FileManager.default.removeItem(at: SoundFiles.dir.appendingPathComponent(sound.notificationName))
        sounds.removeAll { $0.id == sound.id }
        save()
    }

    private func writeNotificationCopy(of sound: CustomSound) throws {
        let input = try AVAudioFile(forReading: sound.url)
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        try FileManager.default.createDirectory(at: SoundFiles.dir, withIntermediateDirectories: true)
        let output = try AVAudioFile(forWriting: SoundFiles.dir.appendingPathComponent(sound.notificationName),
                                     settings: settings, commonFormat: format.commonFormat,
                                     interleaved: format.isInterleaved)
        let end = min(input.length, AVAudioFramePosition(29 * format.sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else { return }
        while input.framePosition < end {
            try input.read(into: buffer, frameCount: AVAudioFrameCount(min(32_768, end - input.framePosition)))
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(sounds), forKey: "customSounds")
    }
}

extension Alarm {
    /// The imported sound if one is chosen (and still exists), else the built-in one.
    var soundURL: URL { customSound.flatMap(SoundLibrary.shared.sound)?.url ?? sound.url }
    var notificationSoundName: String {
        customSound.flatMap(SoundLibrary.shared.sound)?.notificationName ?? sound.fileName
    }
}

/// Settings list of imported sounds, swipe to delete.
struct CustomSoundsSection: View {
    @ObservedObject private var library = SoundLibrary.shared

    var body: some View {
        Section {
            if library.sounds.isEmpty {
                Text("None yet. Import one from an alarm's Sound section.").foregroundStyle(.secondary)
            }
            ForEach(library.sounds) { Label($0.name, systemImage: "music.note") }
                .onDelete { offsets in offsets.map { library.sounds[$0] }.forEach(library.delete) }
        } header: {
            Text("Your sounds")
        } footer: {
            Text("Alarms using a deleted sound go back to their built-in sound.")
        }
    }
}
