import AVFoundation
import Speech
import SwiftUI
import UIKit
import Vision

// Round 2 missions. Each falls back to hard maths if it can't run (permission off etc).

private func level(_ mission: Mission, _ values: [Double]) -> Double {
    values[min(max(mission.difficulty, 0), values.count - 1)]
}

/// For typed answers: case, punctuation and extra spaces don't count; the words do.
func normalizedWords(_ s: String) -> String {
    s.lowercased()
        .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
}

// MARK: - Memory tiles

struct MemoryMission: View {
    let mission: Mission
    let done: () -> Void
    @State private var round = 0
    @State private var pattern: Set<Int> = []
    @State private var found: Set<Int> = []
    @State private var showing = true
    @State private var wrongTile: Int?

    private var size: Int { Int(level(mission, [3, 4, 5])) }
    private var lit: Int { Int(level(mission, [3, 5, 7])) }

    var body: some View {
        VStack(spacing: 18) {
            Text(showing ? "Remember the lit tiles" : "Tap the tiles you saw").font(.title2.bold())
            Text("Round \(round + 1) of \(mission.count)").foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: size), spacing: 10) {
                ForEach(0..<(size * size), id: \.self) { tile in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color(tile))
                        .aspectRatio(1, contentMode: .fit)
                        .onTapGesture { tap(tile) }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showing)
        }
        .padding()
        .onAppear(perform: newRound)
    }

    private func color(_ tile: Int) -> Color {
        if tile == wrongTile { return .red }
        if found.contains(tile) || (showing && pattern.contains(tile)) { return .orange }
        return .white.opacity(0.12)
    }

    private func newRound() {
        pattern = Set((0..<(size * size)).shuffled().prefix(lit))
        found = []
        showing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showing = false }
    }

    private func tap(_ tile: Int) {
        guard !showing, wrongTile == nil else { return }
        if pattern.contains(tile) {
            found.insert(tile)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard found == pattern else { return }
            round += 1
            if round >= mission.count { done() } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { newRound() }
            }
        } else {
            wrongTile = tile
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                wrongTile = nil
                newRound()
            }
        }
    }
}

// MARK: - Typing

struct TypingMission: View {
    let mission: Mission
    let done: () -> Void
    @State private var phrase = ""
    @State private var typed = ""
    @State private var finished = 0
    @State private var wrong = false
    @State private var used: Set<String> = []
    @FocusState private var focused: Bool

    // At least 10 per length, so the max of 10 phrases never repeats one.
    static let phrases = [
        ["Rise and shine", "Good morning world", "Today is a new day", "Feet on the floor",
         "Time to get going", "One step at a time", "Open the curtains", "Coffee is calling",
         "Stretch and breathe", "Up and moving", "Hello sunshine", "Fresh start today",
         "Wake up and win", "Make the bed", "Splash some water", "Big day ahead"],
        ["Every morning is a fresh start", "I am awake and ready for today", "Small steps add up to big results",
         "Today I will make it count", "Getting up is the first win of the day", "The early hours belong to me",
         "A glass of water and a deep breath", "I will finish what I start today",
         "My future self will thank me for this", "Good habits are built one morning at a time",
         "I have plenty of energy for today", "Progress beats perfection every time",
         "I am up before the excuses wake up", "Today I choose focus over comfort",
         "Let the light in and get moving"],
        ["Discipline is choosing what I want most over what I want right now",
         "I am not hitting snooze because my goals are waiting for me",
         "A strong morning sets the tone for a strong day ahead",
         "The best way to wake up is to have something worth getting up for",
         "Motivation gets me started but habit is what keeps me going",
         "Every time I get up on the first alarm I prove I keep my promises",
         "The bed is comfortable but the life I want is out there waiting",
         "I would rather be tired from doing things than tired from doing nothing",
         "Small efforts repeated every day turn into results that last",
         "Waking up early gives me time that nobody else can take away",
         "I do not need to feel ready to start because starting makes me ready",
         "Consistency on the boring days is what builds results on the big days",
         "The snooze button has never helped anyone reach their goals",
         "Today is a chance to do a little better than I did yesterday",
         "Getting out of bed right now is the first decision of a good day"],
    ]

    var body: some View {
        VStack(spacing: 18) {
            Text("\(finished + 1) of \(mission.count)").foregroundStyle(.secondary)
            Text("Type this exactly").font(.headline)
            Text(phrase)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            TextField("Start typing…", text: $typed, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .font(.title3)
                .foregroundStyle(wrong ? Color.red : Color.primary)
                .padding()
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            Button("Check", action: check).buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
        .padding()
        .onAppear {
            phrase = pick()
            focused = true
        }
        .onChange(of: typed) { _, text in
            if normalizedWords(text) == normalizedWords(phrase) { next() }   // no need to press Check
        }
    }

    /// A phrase not used yet in this mission.
    private func pick() -> String {
        let pool = Self.phrases[min(max(mission.difficulty, 0), Self.phrases.count - 1)]
        let choice = pool.filter { !used.contains($0) }.randomElement() ?? pool.randomElement() ?? pool[0]
        used.insert(choice)
        return choice
    }

    private func check() {
        if normalizedWords(typed) == normalizedWords(phrase) { return next() }
        wrong = true
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { wrong = false }
    }

    private func next() {
        finished += 1
        typed = ""
        if finished >= mission.count { done() } else { phrase = pick() }
    }
}

// MARK: - Tap challenge

struct TapMission: View {
    let mission: Mission
    let done: () -> Void
    @State private var taps = 0
    @State private var startedAt: Date?
    @State private var attempt = 0
    @State private var failed = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Tap \(mission.count) times in 10 seconds").font(.title2.bold())
            if let startedAt {
                // A fixed range (not Date()...end), which would crash if redrawn after the time runs out.
                Text(timerInterval: startedAt...startedAt.addingTimeInterval(10), countsDown: true)
                    .font(.title.monospacedDigit())
            } else {
                Text(failed ? "Too slow! Try again." : "The timer starts on your first tap")
                    .foregroundStyle(failed ? Color.red : Color.secondary)
            }
            Text("\(taps) / \(mission.count)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Button(action: tap) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 210, height: 210)
                    .overlay(Text("TAP").font(.largeTitle.bold()).foregroundStyle(.black))
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private func tap() {
        if startedAt == nil {
            startedAt = Date()
            failed = false
            let thisAttempt = attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                guard thisAttempt == attempt, taps < mission.count else { return }
                attempt += 1
                failed = true
                taps = 0
                startedAt = nil
            }
        }
        taps += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if taps >= mission.count {
            attempt += 1   // cancels the timeout
            done()
        }
    }
}

// MARK: - Photo match

/// Reference photos live in Application Support, one per mission.
enum PhotoStore {
    private static var dir: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func url(_ id: UUID) -> URL { dir.appendingPathComponent("photo-\(id.uuidString).jpg") }

    static func save(_ image: UIImage, for id: UUID) {
        try? prepared(image).jpegData(compressionQuality: 0.8)?.write(to: url(id))
    }

    static func load(_ id: UUID) -> UIImage? { UIImage(contentsOfFile: url(id).path) }

    /// Upright and at most 640 px, so both photos are compared the same way (and quickly).
    static func prepared(_ image: UIImage) -> UIImage {
        let scale = min(1, 640 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Vision feature-print distance between two photos: small = same scene. nil if Vision fails.
    static func distance(_ a: UIImage, _ b: UIImage) -> Float? {
        func featurePrint(_ image: UIImage) -> VNFeaturePrintObservation? {
            guard let cg = image.cgImage else { return nil }
            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = VNGenerateImageFeaturePrintRequestRevision1   // fixed scale for the thresholds below
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            return request.results?.first
        }
        guard let fa = featurePrint(a), let fb = featurePrint(b) else { return nil }
        var distance: Float = 0
        do { try fa.computeDistance(&distance, to: fb) } catch { return nil }
        return distance
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct PhotoMission: View {
    let mission: Mission
    let done: () -> Void
    @State private var reference: UIImage?
    @State private var taking = false
    @State private var checking = false
    @State private var result: String?

    init(mission: Mission, done: @escaping () -> Void) {
        self.mission = mission
        self.done = done
        _reference = State(initialValue: PhotoStore.load(mission.id))
    }

    // ponytail: Vision revision-1 distance thresholds are a first guess; the score is shown so they can be tuned.
    private var threshold: Float { Float(level(mission, [18, 15, 12])) }

    var body: some View {
        if cameraBlocked || reference == nil {
            MathFallback(reason: reference == nil ? "No reference photo was saved, so it's maths instead."
                                                  : "Camera access is off, so it's maths instead.",
                         done: done)
        } else if let reference {
            VStack(spacing: 16) {
                Text("Take a photo of \(mission.codeName.isEmpty ? "your spot" : mission.codeName)")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Image(uiImage: reference)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(result ?? "Match this view as closely as you can")
                    .foregroundStyle(result == nil ? Color.secondary : Color.red)
                    .multilineTextAlignment(.center)
                Button { taking = true } label: {
                    Label(checking ? "Checking…" : "Take photo", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(checking)
            }
            .padding()
            .fullScreenCover(isPresented: $taking) {
                CameraPicker { photo in check(photo, against: reference) }.ignoresSafeArea()
            }
        }
    }

    private func check(_ photo: UIImage, against reference: UIImage) {
        checking = true
        let limit = threshold
        Task.detached(priority: .userInitiated) {
            let distance = PhotoStore.distance(PhotoStore.prepared(photo), reference)
            await MainActor.run {
                checking = false
                guard let distance else {
                    result = "Couldn't compare the photos. Try again."
                    return
                }
                if distance < limit {
                    done()
                } else {
                    result = "Not a match yet (score \(Int(distance)), needs under \(Int(limit))). Try the same angle."
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Say the word

struct SpeakMission: View {
    let mission: Mission
    let done: () -> Void
    @EnvironmentObject private var engine: AlarmEngine
    @StateObject private var listener = SpeechListener()
    @State private var word = SpeakMission.words.randomElement() ?? "morning"
    @State private var said = 0
    @State private var blocked = false

    static let words = ["sunshine", "breakfast", "morning", "coffee", "window", "energy", "orange", "garden",
                        "mountain", "rocket", "banana", "thunder", "pancake", "jungle", "violin", "pirate",
                        "tomato", "rainbow", "dragon", "volcano", "penguin", "pizza", "guitar", "football"]

    var body: some View {
        if blocked {
            MathFallback(reason: "Microphone or speech recognition is off, so it's maths instead.", done: done)
        } else {
            VStack(spacing: 18) {
                Text("\(said + 1) of \(mission.count)").foregroundStyle(.secondary)
                Text("Say this word out loud").font(.headline)
                Text(word.capitalized)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Image(systemName: "mic.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
                Text(listener.heard.isEmpty ? "Listening…" : "Heard: \(listener.heard)")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .task {
                guard await SpeechListener.authorize() else { blocked = true; return }
                engine.audio.setListening(true)
                listen()
            }
            .onChange(of: listener.heard) { _, text in
                guard text.lowercased().contains(word) else { return }
                said += 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if said >= mission.count {
                    finish()
                    done()
                } else {
                    word = Self.words.filter { $0 != word }.randomElement() ?? word
                    listen()
                }
            }
            .onDisappear(perform: finish)
        }
    }

    private func listen() {
        do { try listener.start() } catch { blocked = true }
    }

    private func finish() {
        listener.stop()
        engine.audio.setListening(false)
    }
}

/// Live speech-to-text from the microphone (on-device when the phone supports it).
@MainActor
final class SpeechListener: ObservableObject {
    @Published private(set) var heard = ""
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapped = false

    static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    /// (Re)starts listening with a fresh transcript.
    func start() throws {
        stop()
        heard = ""
        guard let recognizer, recognizer.isAvailable else { throw CancellationError() }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        tapped = true
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in self?.heard = text }
        }
    }

    func stop() {
        audioEngine.stop()
        if tapped {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
