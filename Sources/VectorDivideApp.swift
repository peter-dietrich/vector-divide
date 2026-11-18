import AppKit
import SwiftUI

@main
struct VectorDivideApp: App {
    var body: some Scene {
        WindowGroup("Vector Divide") {
            DivideWindow()
                .frame(minWidth: 1000, minHeight: 665)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1260, height: 810)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
final class DivideSession: ObservableObject {
    @Published var redraw = 0
    @Published var difficulty: DivideDifficulty = .veteran
    @Published var records = DivideStore.records()
    @Published var customRules: DivideRules? = nil
    @Published var modern: Bool = UserDefaults.standard.bool(forKey: "VectorDivide.ModernDisplay.v1") {
        didSet { UserDefaults.standard.set(modern, forKey: "VectorDivide.ModernDisplay.v1") }
    }
    var bestScore: Int { records.first?.score ?? 0 }
    var bestInitials: String { records.first?.initials ?? "---" }
    @Published var askInitials = false
    @Published var initialsDraft = ""

    var engine = DivideEngine()
    private var keys: Set<UInt16> = []
    private var shiftHeld = false
    private var lastTime = Date()
    private var promptedForRecord = false
    @Published var pendingMessage: String? = nil
    @Published var captureFX: DivideCaptureFX? = nil
    @Published var soundEnabled = DivideAudio.shared.enabled {
        didSet { DivideAudio.shared.enabled = soundEnabled }
    }

    private var direction: DivideDirection? {
        // Arrow keys and WASD, using native macOS key codes.
        if keys.contains(123) || keys.contains(0) { return .left }
        if keys.contains(124) || keys.contains(2) { return .right }
        if keys.contains(125) || keys.contains(1) { return .down }
        if keys.contains(126) || keys.contains(13) { return .up }
        return nil
    }

    func keyDown(_ event: NSEvent) {
        keys.insert(event.keyCode)
        if event.isARepeat { return }
        switch event.keyCode {
        case 36, 76: // Return or keypad Enter
            switch engine.phase {
            case .ready, .gameOver: newGame()
            case .levelClear: engine.nextLevel()
            case .paused: engine.togglePause()
            case .playing: break
            }
        case 35: engine.togglePause() // P
        case 15: newGame() // R
        default: break
        }
        redraw &+= 1
    }

    func keyUp(_ event: NSEvent) { keys.remove(event.keyCode) }
    func flagsChanged(_ event: NSEvent) { shiftHeld = event.modifierFlags.contains(.shift) }

    func newGame() {
        keys.removeAll()
        engine.start(difficulty, rules: customRules ?? DivideRules())
        if modern { DivideAudio.shared.play(.start) }
        captureFX = nil
        promptedForRecord = false
        lastTime = Date()
        redraw &+= 1
    }

    func pauseOrResume() { engine.togglePause(); redraw &+= 1 }
    func showPauseForDialog() {
        if engine.phase == .playing { engine.togglePause() }
        redraw &+= 1
    }
    func loadGame(_ save: DivideSave) {
        guard save.snapshot.validSnapshot else { return }
        engine = save.snapshot
        captureFX = nil
        difficulty = engine.difficulty
        customRules = engine.rules.isDefault ? nil : engine.rules
        if engine.phase == .playing { engine.togglePause() }
        promptedForRecord = false
        keys.removeAll()
        shiftHeld = false
        lastTime = Date()
        redraw &+= 1
    }
    func applyRules(_ rules: DivideRules?) {
        customRules = rules?.validated()
        newGame()
    }
    func nextLevel() { engine.nextLevel(); captureFX = nil; redraw &+= 1 }

    func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTime)
        lastTime = now
        guard engine.phase == .playing else { return }
        let request: DivideDrawMode? = shiftHeld ? .slow : (keys.contains(49) ? .fast : nil)
        // A completed line creates an ephemeral renderer-only power-up wave.
        // No animation data is included in saves, collision detection or the engine.
        let oldLives = engine.lives
        let oldPhase = engine.phase
        let previousTrail = engine.trail
        let previousStart = engine.trailStart
        let oldCells = previousTrail.isEmpty ? [] : engine.cells
        engine.tick(dt, direction: direction, request: request)
        if !previousTrail.isEmpty && engine.trail.isEmpty &&
            engine.lastGain > 0 && !oldCells.isEmpty {
            var restored: [DividePoint] = []
            for index in engine.cells.indices where oldCells[index] == 0 && engine.cells[index] != 0 {
                restored.append(DividePoint(x: index % DivideEngine.columns,
                                            y: index / DivideEngine.columns))
            }
            if !restored.isEmpty {
                captureFX = DivideCaptureFX(
                    began: Date.timeIntervalSinceReferenceDate,
                    newCells: restored,
                    origin: previousTrail.last ?? previousStart ?? engine.player,
                    gain: engine.lastGain,
                    award: engine.lastAward)
                if modern { DivideAudio.shared.play(.capture, magnitude: engine.lastGain) }
            }
        }
        if modern && engine.lives < oldLives { DivideAudio.shared.play(.damage) }
        if modern && engine.phase == .levelClear && oldPhase != .levelClear { DivideAudio.shared.play(.victory) }
        if modern && previousTrail.isEmpty && !engine.trail.isEmpty { DivideAudio.shared.play(.trace) }
        if let effect = captureFX,
           Date.timeIntervalSinceReferenceDate - effect.began >= effect.duration {
            captureFX = nil
        }
        redraw &+= 1
        if engine.phase == .gameOver, DivideStore.qualifies(engine.score), !promptedForRecord {
            promptedForRecord = true
            initialsDraft = ""
            askInitials = true
        }
    }

    func recordInitials() {
        let entered = String(initialsDraft.uppercased().filter { $0.isLetter }.prefix(3))
        DivideStore.submit(score: engine.score, level: engine.level,
                           difficulty: engine.difficulty, initials: entered)
        records = DivideStore.records()
        askInitials = false
    }
}

struct DivideWindow: View {
    @StateObject private var session = DivideSession()
    @State private var showRecords = false
    @State private var showCustom = false
    @State private var showSaves = false
    private let heartbeat = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let cyan = Color(red: 0.30, green: 0.92, blue: 0.98)
    private let amber = Color(red: 1, green: 0.71, blue: 0.28)
    private let magenta = Color(red: 1, green: 0.36, blue: 0.75)

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(v) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                HStack(spacing: 11) {
                    Image(systemName: "square.on.square.dashed")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(cyan)
                    Text("VECTOR DIVIDE")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .tracking(2)
                    Text(version)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.53))
                }
                Spacer(minLength: 10)
                Text(session.modern ? "CONTAINMENT" : "CLASSIC")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(cyan.opacity(0.9))
                    .tracking(1.1)
                Picker("Skill", selection: $session.difficulty) {
                    ForEach(DivideDifficulty.allCases, id: \.self) { difficulty in
                        Text(difficulty.rawValue).tag(difficulty)
                    }
                }
                .labelsHidden()
                .frame(width: 128)
                // The selected difficulty takes effect on New Game.
                Button { session.pauseOrResume() } label: {
                    Label(session.engine.phase == .paused ? "Resume" : "Pause",
                          systemImage: session.engine.phase == .paused ? "play.fill" : "pause.fill")
                }
                .disabled(session.engine.phase != .playing && session.engine.phase != .paused)
                Button { session.showPauseForDialog(); showRecords = true } label: {
                    Label("Scores", systemImage: "trophy")
                }
                Button { session.showPauseForDialog(); showCustom = true } label: {
                    Label("Custom", systemImage: "slider.horizontal.3")
                }
                Button {
                    if DivideStore.save(session.engine, name: "") {
                        session.pendingMessage = "Game saved locally. Open Load to resume."
                    } else {
                        session.pendingMessage = "Start a game before saving."
                    }
                } label: { Label("Save", systemImage: "square.and.arrow.down") }
                Button { session.showPauseForDialog(); showSaves = true } label: {
                    Label("Load", systemImage: "folder")
                }
                Button { session.newGame() } label: {
                    Label("New Game", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(cyan)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 20)
            .frame(height: 66)
            .background(Color(red: 0.044, green: 0.056, blue: 0.093))

            HStack(spacing: 14) {
                Label("DISPLAY", systemImage: "square.3.layers.3d")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                Picker("Visual Mode", selection: $session.modern) {
                    Text("Classic").tag(false)
                    Text("Modern / Containment").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
                Text(session.modern ?
                     "REACTOR CORE  /  ARMOR RESTORATION  /  ACTIVE CONTAINMENT" :
                     "ORIGINAL VECTOR GRID  /  CLASSIC RULES")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(session.modern ? cyan.opacity(0.85) : .white.opacity(0.53))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if session.modern {
                    Toggle(isOn: $session.soundEnabled) {
                        Label("SOUND", systemImage: session.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                    }
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(cyan)
                }
                Text("STANDARD ENEMY SPEED 2.5×")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(amber)
            }
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(Color(red: 0.025, green: 0.039, blue: 0.073))

            GeometryReader { geometry in
                HStack(spacing: 18) {
                    Group {
                        if session.modern {
                            DivideContainmentBoard(engine: session.engine,
                                clock: Date.timeIntervalSinceReferenceDate,
                                capture: session.captureFX)
                        } else {
                            DivideBoard(engine: session.engine)
                        }
                    }
                        .aspectRatio(CGFloat(DivideEngine.columns) / CGFloat(DivideEngine.rows), contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DivideKeyboardCapture(session: session))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(cyan.opacity(0.45), lineWidth: 1))
                        .overlay(alignment: .center) { statusOverlay }

                    telemetry
                        .frame(width: 230)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            HStack(spacing: 21) {
                Text("ARROWS / WASD  MOVE")
                Text("SPACE + DIRECTION  FAST DRAW")
                Text("SHIFT + DIRECTION  SLOW DRAW / 2× POINTS")
                Spacer(minLength: 0)
                Text("P  PAUSE     R  RESET")
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.64))
            .padding(.horizontal, 18)
            .frame(height: 45)
            .background(Color(red: 0.049, green: 0.065, blue: 0.105))
        }
        .background(Color(red: 0.025, green: 0.035, blue: 0.065))
        .onReceive(heartbeat) { _ in session.tick() }
        .sheet(isPresented: $session.askInitials) { initialsSheet }
        .sheet(isPresented: $showRecords) { recordsSheet }
        .sheet(isPresented: $showCustom) { customSheet }
        .sheet(isPresented: $showSaves) { savesSheet }
        .alert("VECTOR DIVIDE", isPresented: Binding(
            get: { session.pendingMessage != nil },
            set: { if !$0 { session.pendingMessage = nil } }
        )) { Button("OK", role: .cancel) { session.pendingMessage = nil } } message: {
            Text(session.pendingMessage ?? "")
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch session.engine.phase {
        case .ready:
            statusCard("VECTOR DIVIDE", detail: "CLAIM YOUR TARGET TERRITORY", instruction: "PRESS RETURN TO PLAY")
        case .paused:
            statusCard("PAUSED", detail: "THE GRID IS HOLDING", instruction: "PRESS P OR RETURN TO RESUME")
        case .levelClear:
            statusCard("FIELD SECURED", detail: "\(Int(session.engine.percentClaimed))% CAPTURED  ·  \(session.engine.score) POINTS",
                       instruction: "PRESS RETURN FOR LEVEL \(session.engine.level + 1)")
        case .gameOver:
            statusCard("GAME OVER", detail: "FINAL SCORE  \(session.engine.score)", instruction: "PRESS RETURN TO RESTART")
        case .playing: EmptyView()
        }
    }

    private func statusCard(_ title: String, detail: String, instruction: String) -> some View {
        VStack(spacing: 15) {
            Text(title)
                .font(.system(size: 29, weight: .black, design: .monospaced))
                .foregroundStyle(cyan)
                .tracking(2)
            Text(detail)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
            Text(instruction)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(amber)
                .tracking(1)
        }
        .padding(.horizontal, 35)
        .padding(.vertical, 30)
        .background(Color.black.opacity(0.93))
        .overlay(Rectangle().stroke(cyan.opacity(0.85), lineWidth: 1.5))
        .allowsHitTesting(false)
    }

    private var telemetry: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FIELD TELEMETRY")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .tracking(1.4).foregroundStyle(cyan)
            Divider().overlay(cyan.opacity(0.2))
            numberRow("SCORE", String(format: "%07d", session.engine.score), color: .white)
            numberRow("HIGH SCORE", String(format: "%07d", session.bestScore), color: amber)
            Text("RECORD HOLDER  \(session.bestInitials)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(amber.opacity(0.8))
            Divider().overlay(cyan.opacity(0.2))
            HStack {
                numberColumn("LEVEL", "\(session.engine.level)")
                Spacer()
                numberColumn("LIVES", "\(session.engine.lives)")
            }
            Divider().overlay(cyan.opacity(0.2))
            Text("TERRITORY SECURED")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            Text(String(format: "%.1f%%", session.engine.percentClaimed))
                .font(.system(size: 37, weight: .black, design: .monospaced))
                .foregroundStyle(cyan)
                .monospacedDigit()
            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.09))
                    Rectangle().fill(cyan).frame(width: bar.size.width * min(1, session.engine.percentClaimed / 100))
                    Rectangle().fill(amber.opacity(0.7))
                        .frame(width: 2)
                        .offset(x: bar.size.width * CGFloat(session.engine.rules.targetPercent / 100.0))
                }
            }
            .frame(height: 9)
            Text(String(format: "TARGET  %.1f%%", session.engine.rules.targetPercent))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(amber)
            Divider().overlay(cyan.opacity(0.2))
            numberRow("LAST CAPTURE", String(format: "+%.1f%%", session.engine.lastGain), color: cyan)
            numberRow("AREA BONUS", "+\(session.engine.lastAward)", color: amber)
            if session.modern {
                Divider().overlay(cyan.opacity(0.2))
                Text("TACTICAL FIELD / LIVE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(cyan.opacity(0.85))
                DivideTacticalMap(engine: session.engine)
                    .aspectRatio(CGFloat(DivideEngine.columns) / CGFloat(DivideEngine.rows), contentMode: .fit)
                    .overlay(Rectangle().stroke(cyan.opacity(0.25), lineWidth: 1))
                Text(session.engine.isDrawing ? "EXPOSED CIRCUIT — CONNECT TO SEAL" : "CORE STATUS — ACTIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(session.engine.isDrawing ? amber : cyan)
                if let effect = session.captureFX {
                    Text(String(format: "REACTOR RESTORED  +%.1f%%", effect.gain))
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(amber)
                }
            }
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 8) {
                Text("FIELD THREATS")
                    .foregroundStyle(magenta)
                Text("\(session.engine.enemies.count)  ENERGY ANOMAL\(session.engine.enemies.count == 1 ? "Y" : "IES")")
                Text("\(session.engine.sparks.count)  BORDER SPARKS")
                Text(session.engine.isDrawing ? "OPEN TRACE / EXPOSED" : "TRACE READY")
                    .foregroundStyle(session.engine.isDrawing ? amber : .white.opacity(0.55))
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.052, green: 0.073, blue: 0.116))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(cyan.opacity(0.18)))
    }

    private func numberRow(_ caption: String, _ value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(caption).foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value).foregroundStyle(color).monospacedDigit()
        }
        .font(.system(size: 12, weight: .bold, design: .monospaced))
    }

    private func numberColumn(_ caption: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: 25, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private var recordsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TOP TEN / VECTOR DIVIDE").font(.system(size: 23, weight: .black, design: .monospaced))
            if session.records.isEmpty {
                Text("No recorded scores yet. Finish a game to enter your initials.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.records.indices, id: \.self) { offset in
                    let record = session.records[offset]
                    HStack {
                        Text(String(format: "%02d", offset + 1)).frame(width: 35, alignment: .leading)
                        Text(record.initials).frame(width: 50)
                        Text(String(format: "%07d", record.score)).frame(width: 100, alignment: .trailing)
                        Text("LV \(record.level)").frame(width: 65, alignment: .trailing)
                        Text(record.difficulty).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
            }
            HStack { Spacer(); Button("Close") { showRecords = false } }
        }
        .padding(24).frame(width: 570)
        .preferredColorScheme(.dark)
    }

    private var customSheet: some View {
        DivideCustomSheet(initial: session.customRules ?? DivideRules()) { rules in
            session.applyRules(rules)
            showCustom = false
        }
    }

    private var savesSheet: some View {
        DivideSavesSheet { save in
            session.loadGame(save)
            showSaves = false
        }
    }

    private var initialsSheet: some View {
        VStack(alignment: .center, spacing: 18) {
            Text("NEW HIGH SCORE")
                .font(.system(size: 25, weight: .black, design: .monospaced))
                .foregroundStyle(amber)
            Text(String(format: "%07d", session.engine.score))
                .font(.system(size: 36, weight: .black, design: .monospaced))
            Text("ENTER UP TO THREE INITIALS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            TextField("AAA", text: $session.initialsDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 116)
                .multilineTextAlignment(.center)
                .onSubmit { session.recordInitials() }
            Button("SAVE RECORD") { session.recordInitials() }
                .buttonStyle(.borderedProminent)
        }
        .padding(38)
        .frame(width: 365)
        .preferredColorScheme(.dark)
    }
}

private struct DivideKeyboardCapture: NSViewRepresentable {
    @ObservedObject var session: DivideSession
    func makeNSView(context: Context) -> DivideKeyboardView {
        let view = DivideKeyboardView()
        view.session = session
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }
    func updateNSView(_ view: DivideKeyboardView, context: Context) {
        view.session = session
    }
}

private final class DivideKeyboardView: NSView {
    weak var session: DivideSession?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { session?.keyDown(event) }
    override func keyUp(with event: NSEvent) { session?.keyUp(event) }
    override func flagsChanged(with event: NSEvent) { session?.flagsChanged(event) }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }
}

private struct DivideCustomSheet: View {
    let initial: DivideRules
    let apply: (DivideRules?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rules = DivideRules()
    @State private var savedPresets: [DividePreset] = []
    @State private var selected: UUID?
    @State private var presetName = "My Divide"

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("CUSTOM GAME SETTINGS")
                .font(.system(size: 22, weight: .black, design: .monospaced))
            Text("Save named configurations independently of saved games.")
                .foregroundStyle(.secondary)
            HStack {
                Picker("Preset", selection: $selected) {
                    Text("New setup").tag(nil as UUID?)
                    ForEach(savedPresets) { item in Text(item.name).tag(Optional(item.id)) }
                }
                .onChange(of: selected) { id in
                    guard let item = savedPresets.first(where: { $0.id == id }) else { return }
                    rules = item.rules
                    presetName = item.name
                }
                Button("Reset") { rules = DivideRules(); selected = nil }
            }
            TextField("Configuration name", text: $presetName)
            Form {
                Section("Challenge") {
                    Stepper("Extra lives: \(rules.extraLives)", value: $rules.extraLives, in: -2...6)
                    Stepper("Additional enemies: \(rules.extraEnemies)", value: $rules.extraEnemies, in: 0...3)
                    slider("Enemy movement speed", value: $rules.enemySpeed, range: 0.5...4.0)
                    slider("Border spark speed", value: $rules.sparkSpeed, range: 0.5...2.5)
                    slider("Territory target %", value: $rules.targetPercent, range: 50...95, step: 1)
                }
                Section("Movement and trace") {
                    slider("Drawing speed", value: $rules.drawSpeed, range: 0.6...1.7)
                    slider("Idle time before fuse", value: $rules.fuseDelay, range: 0.4...3.5)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Delete Preset", role: .destructive) {
                    guard let selected else { return }
                    DivideStore.removePreset(selected)
                    savedPresets = DivideStore.presets()
                    self.selected = nil
                }.disabled(selected == nil)
                Spacer()
                Button("Save Preset") {
                    let item = DividePreset(id: selected ?? UUID(),
                                            name: presetName.isEmpty ? "My Divide" : presetName,
                                            rules: rules.validated())
                    DivideStore.upsert(item)
                    savedPresets = DivideStore.presets()
                    selected = item.id
                }
                Button("Standard Game") { apply(nil); dismiss() }
                Button("Apply & Start") { apply(rules.validated()); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(width: 640, height: 680)
        .onAppear {
            rules = initial
            savedPresets = DivideStore.presets()
        }
        .preferredColorScheme(.dark)
    }

    private func slider(_ name: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double = 0.05) -> some View {
        HStack {
            Text(name)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%.2f", value.wrappedValue))
                .monospacedDigit().frame(width: 50, alignment: .trailing)
        }
    }
}

private struct DivideSavesSheet: View {
    let restore: (DivideSave) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saves: [DivideSave] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LOAD SAVED GAME")
                .font(.system(size: 22, weight: .black, design: .monospaced))
            Text("Eight local saves maximum. Resumed games start paused.")
                .foregroundStyle(.secondary)
            if saves.isEmpty { Text("No saved games yet.") }
            else {
                List {
                    ForEach(saves) { save in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(save.name).fontWeight(.semibold)
                                Text("Level \(save.snapshot.level) · \(save.snapshot.score) points · \(save.saved.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Resume") { restore(save); dismiss() }
                                .buttonStyle(.borderedProminent)
                            Button(role: .destructive) {
                                DivideStore.deleteSave(save.id)
                                saves = DivideStore.saves()
                            } label: { Image(systemName: "trash") }
                        }
                    }
                }
            }
            HStack { Spacer(); Button("Close") { dismiss() } }
        }
        .padding(22).frame(width: 620, height: 480)
        .onAppear { saves = DivideStore.saves() }
        .preferredColorScheme(.dark)
    }
}
