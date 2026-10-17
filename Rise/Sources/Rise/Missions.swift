import SwiftUI
import UIKit
import AVFoundation
import CoreMotion

// MARK: - Running missions

struct MissionRunner: View {
    let missions: [Mission]
    let finished: () -> Void
    let escaped: () -> Void
    @State private var index = 0
    @State private var escaping = false
    @AppStorage("emergencyEscape") private var escapeAllowed = true

    var body: some View {
        if escaping {
            EmergencyEscape(finished: escaped) { escaping = false }
        } else {
            // Missions get the whole screen (Shake fills it); the counter and Emergency float on top.
            ZStack(alignment: .top) {
                if index < missions.count {
                    MissionView(mission: missions[index]) {
                        if index + 1 < missions.count { index += 1 } else { finished() }
                    }
                    .id(index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    if missions.count > 1 {
                        Text("Mission \(min(index + 1, missions.count)) of \(missions.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if escapeAllowed {
                        Button("Emergency") { escaping = true }
                            .font(.caption.bold())
                            .buttonStyle(.bordered)
                            .tint(.red)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Skips the mission by typing a pledge that gets longer every time it's used.
struct EmergencyEscape: View {
    let finished: () -> Void
    let cancel: () -> Void
    @AppStorage("escapeCount") private var uses = 0
    @State private var typed = ""

    static let pledges = [
        "This is a real emergency and I need to turn off my alarm right now",
        "I promise this is a genuine emergency and not just me trying to stay in bed a little longer",
        "I have used the emergency escape before and I know that using it again means skipping the morning mission I set for myself",
        "I admit I keep using the emergency escape instead of doing my wake up mission and I promise that tomorrow I will get up on the first alarm and do it properly with no excuses",
    ]

    private var pledge: String { Self.pledges[min(uses, Self.pledges.count - 1)] }

    var body: some View {
        VStack(spacing: 16) {
            Text("Emergency escape").font(.title2.bold())
            Text("Type this pledge to turn the alarm off without doing your mission. It gets longer every time you use it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(pledge)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            TextField("Type the pledge…", text: $typed, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            Button("Back to my mission", action: cancel).buttonStyle(.bordered)
            Spacer()
        }
        .padding()
        .onChange(of: typed) { _, text in
            guard normalizedWords(text) == normalizedWords(pledge) else { return }
            uses += 1
            finished()
        }
    }
}

struct MissionView: View {
    let mission: Mission
    let done: () -> Void

    var body: some View {
        switch mission.kind {
        case .math: MathMission(mission: mission, done: done)
        case .shake: ShakeMission(mission: mission, done: done)
        case .scan: ScanMission(mission: mission, done: done)
        case .memory: MemoryMission(mission: mission, done: done)
        case .typing: TypingMission(mission: mission, done: done)
        case .tap: TapMission(mission: mission, done: done)
        case .photo: PhotoMission(mission: mission, done: done)
        case .speak: SpeakMission(mission: mission, done: done)
        }
    }
}

/// Used when a mission can't run (permission off, no camera...): never leave someone with an alarm they can't stop.
struct MathFallback: View {
    let reason: String
    let done: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(reason).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            MathMission(mission: Self.mission, done: done)
        }
    }

    private static var mission: Mission {
        var m = Mission(kind: .math)
        m.count = 5
        m.difficulty = 2
        return m
    }
}

// MARK: - Editing missions

struct MissionSettings: View {
    @Binding var mission: Mission
    let register: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(mission.kind.title, systemImage: mission.kind.icon).font(.headline)
            switch mission.kind {
            case .math:
                Stepper("\(mission.count) problem\(mission.count == 1 ? "" : "s")", value: $mission.count, in: 1...10)
                Picker("Difficulty", selection: $mission.difficulty) {
                    ForEach(MathProblem.levels.indices, id: \.self) { Text(MathProblem.levels[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
            case .shake:
                Stepper("\(mission.count) shakes", value: $mission.count, in: 5...100, step: 5)
                Picker("Strength", selection: $mission.difficulty) {
                    Text("Light").tag(0)
                    Text("Normal").tag(1)
                    Text("Hard").tag(2)
                }
                .pickerStyle(.segmented)
            case .scan:
                TextField("Where is it? (e.g. Bathroom mirror)", text: $mission.codeName)
                Button(mission.code.isEmpty ? "Scan the code to register it" : "Registered ✓  Tap to scan a different one",
                       action: register)
                    .buttonStyle(.borderless)   // a plain button would fire when anywhere in the row is tapped
            case .memory:
                Stepper("\(mission.count) round\(mission.count == 1 ? "" : "s")", value: $mission.count, in: 1...10)
                levels(["3×3", "4×4", "5×5"], "Grid")
            case .typing:
                Stepper("\(mission.count) phrase\(mission.count == 1 ? "" : "s")", value: $mission.count, in: 1...10)
                levels(["Short", "Medium", "Long"], "Length")
            case .tap:
                Stepper("\(mission.count) taps in 10 seconds", value: $mission.count, in: 20...150, step: 10)
            case .photo:
                TextField("What's the spot? (e.g. Kitchen sink)", text: $mission.codeName)
                HStack {
                    if !mission.code.isEmpty, let photo = PhotoStore.load(mission.id) {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Button(mission.code.isEmpty ? "Take the reference photo" : "Retake the photo", action: register)
                        .buttonStyle(.borderless)
                }
                levels(["Easy", "Normal", "Strict"], "Matching")
            case .speak:
                Stepper("\(mission.count) word\(mission.count == 1 ? "" : "s")", value: $mission.count, in: 1...10)
                    .task { _ = await SpeechListener.authorize() }   // ask now, not half asleep at 7am
            }
        }
        .padding(.vertical, 4)
    }

    private func levels(_ names: [String], _ title: String) -> some View {
        Picker(title, selection: $mission.difficulty) {
            ForEach(names.indices, id: \.self) { Text(names[$0]).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Math

struct MathProblem {
    let text: String
    let answer: Int

    static let levels = ["Easy", "Normal", "Hard", "Super hard"]

    static func make(_ difficulty: Int) -> MathProblem {
        func r(_ range: ClosedRange<Int>) -> Int { Int.random(in: range) }
        switch difficulty {
        case 0:
            let a = r(10...50), b = r(2...9)
            return MathProblem(text: "\(a) + \(b)", answer: a + b)
        case 1:
            let a = r(10...99), b = r(10...99), c = r(10...99)
            return MathProblem(text: "\(a) + \(b) + \(c)", answer: a + b + c)
        case 2:
            let a = r(11...20), b = r(3...9), c = r(10...99)
            return MathProblem(text: "\(a) × \(b) + \(c)", answer: a * b + c)
        default:
            let a = r(11...30), b = r(11...20), c = r(100...999)
            return MathProblem(text: "\(a) × \(b) + \(c)", answer: a * b + c)
        }
    }
}

struct MathMission: View {
    let mission: Mission
    let done: () -> Void
    @State private var problem = MathProblem(text: "", answer: 0)
    @State private var solved = 0
    @State private var input = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 20) {
            Text("\(solved + 1) of \(mission.count)").foregroundStyle(.secondary)
            Text("\(problem.text) =")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(input.isEmpty ? "?" : input)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .foregroundStyle(wrong ? Color.red : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 70)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            Keypad(input: $input, submit: check)
        }
        .padding()
        .onAppear { problem = MathProblem.make(mission.difficulty) }
    }

    private func check() {
        if Int(input) == problem.answer {
            solved += 1
            input = ""
            if solved >= mission.count { done() } else { problem = MathProblem.make(mission.difficulty) }
        } else {
            wrong = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                wrong = false
                input = ""
            }
        }
    }
}

struct Keypad: View {
    @Binding var input: String
    let submit: () -> Void
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "✓"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            ForEach(keys, id: \.self) { key in
                Button {
                    switch key {
                    case "⌫": if !input.isEmpty { input.removeLast() }
                    case "✓": submit()
                    default: if input.count < 6 { input += key }
                    }
                } label: {
                    Text(key)
                        .font(.title.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(key == "✓" ? Color.orange : Color.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Shake

struct ShakeMission: View {
    let mission: Mission
    let done: () -> Void
    @State private var left: Int
    @State private var detector = ShakeDetector()

    init(mission: Mission, done: @escaping () -> Void) {
        self.mission = mission
        self.done = done
        _left = State(initialValue: mission.count)
    }

    var body: some View {
        // Each shake fills the screen a bit more from the bottom; full screen = done.
        let progress = mission.count > 0 ? Double(mission.count - left) / Double(mission.count) : 1
        VStack(spacing: 16) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 90))
                .symbolEffect(.bounce, value: left)
            Text("\(left)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .contentTransition(.numericText(countsDown: true))
            Text("shakes to go").foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { geo in
                LinearGradient(colors: [.orange, .yellow], startPoint: .bottom, endPoint: .top)
                    .frame(height: geo.size.height * progress)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .ignoresSafeArea()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: left)
        .onAppear {
            // ponytail: fixed g thresholds per strength; tune these if shakes don't register on your phone.
            let threshold = [1.8, 2.3, 2.8][min(max(mission.difficulty, 0), 2)]
            detector.start(threshold: threshold) {
                left -= 1
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                if left <= 0 {
                    detector.stop()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { done() }   // let the full screen show
                }
            }
        }
        .onDisappear { detector.stop() }
    }
}

/// Counts a shake whenever total acceleration spikes past `threshold` g (1 g = phone at rest).
final class ShakeDetector {
    private let motion = CMMotionManager()
    private var lastShake = Date.distantPast

    func start(threshold: Double, onShake: @escaping () -> Void) {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1.0 / 60
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            let g = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            guard g > threshold, Date().timeIntervalSince(lastShake) > 0.25 else { return }
            lastShake = Date()
            onShake()
        }
    }

    func stop() { motion.stopAccelerometerUpdates() }
}

// MARK: - Scan a code

struct ScanMission: View {
    let mission: Mission
    let done: () -> Void
    @State private var wrong = false

    var body: some View {
        if cameraBlocked {
            MathFallback(reason: "Camera access is off, so it's maths instead.", done: done)
        } else {
            VStack(spacing: 16) {
                Text("Scan \(mission.codeName.isEmpty ? "your code" : mission.codeName)")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                CodeScanner { code in
                    if mission.code.isEmpty || code == mission.code {
                        done()
                    } else {
                        wrong = true
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                Text(wrong ? "Wrong code. Find the one you registered." : "Go to where you put it")
                    .foregroundStyle(wrong ? Color.red : Color.secondary)
            }
            .padding()
        }
    }
}

var cameraBlocked: Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    return status == .denied || status == .restricted
}

struct RegisterCodeView: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Point the camera at a QR code or barcode away from your bed: a shampoo bottle, a toothpaste tube, or a printed QR code on the bathroom wall.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                CodeScanner(onCode: onCode)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .padding()
            .navigationTitle("Register code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

struct CodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {
        controller.onCode = onCode
    }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var lastCode = ""
    private var lastTime = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { if granted { self.configure() } }
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        let wanted: [AVMetadataObject.ObjectType] = [
            .qr, .ean8, .ean13, .upce, .code39, .code93, .code128,
            .pdf417, .aztec, .dataMatrix, .itf14, .interleaved2of5,
        ]
        output.metadataObjectTypes = wanted.filter(output.availableMetadataObjectTypes.contains)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { self.session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        // The camera reports the same code many times a second; only react to a new sighting.
        guard code != lastCode || Date().timeIntervalSince(lastTime) > 2 else { return }
        lastCode = code
        lastTime = Date()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCode?(code)
    }
}
