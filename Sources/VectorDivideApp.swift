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
    @Published var bestScore: Int = UserDefaults.standard.integer(forKey: "VectorDivide.HighScore.v1")
    @Published var bestInitials: String = UserDefaults.standard.string(forKey: "VectorDivide.Initials.v1") ?? "---"
    @Published var askInitials = false
    @Published var initialsDraft = ""

    var engine = DivideEngine()
    private var keys: Set<UInt16> = []
    private var shiftHeld = false
    private var lastTime = Date()
    private var promptedForRecord = false

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
        engine.start(difficulty)
        promptedForRecord = false
        lastTime = Date()
        redraw &+= 1
    }

    func pauseOrResume() { engine.togglePause(); redraw &+= 1 }
    func nextLevel() { engine.nextLevel(); redraw &+= 1 }

    func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTime)
        lastTime = now
        guard engine.phase == .playing else { return }
        let request: DivideDrawMode? = shiftHeld ? .slow : (keys.contains(49) ? .fast : nil)
        engine.tick(dt, direction: direction, request: request)
        redraw &+= 1
        if engine.phase == .gameOver, engine.score > bestScore, !promptedForRecord {
            promptedForRecord = true
            initialsDraft = ""
            askInitials = true
        }
    }

    func recordInitials() {
        let entered = String(initialsDraft.uppercased().filter { $0.isLetter }.prefix(3))
        bestScore = engine.score
        bestInitials = entered.isEmpty ? "---" : entered
        UserDefaults.standard.set(bestScore, forKey: "VectorDivide.HighScore.v1")
        UserDefaults.standard.set(bestInitials, forKey: "VectorDivide.Initials.v1")
        askInitials = false
    }
}

struct DivideWindow: View {
    @StateObject private var session = DivideSession()
    private let heartbeat = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let cyan = Color(red: 0.30, green: 0.92, blue: 0.98)
    private let amber = Color(red: 1, green: 0.71, blue: 0.28)
    private let magenta = Color(red: 1, green: 0.36, blue: 0.75)

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
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
                Text("CLASSIC / WIREFRAME")
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
                .onChange(of: session.difficulty) { _ in session.newGame() }
                Button { session.pauseOrResume() } label: {
                    Label(session.engine.phase == .paused ? "Resume" : "Pause",
                          systemImage: session.engine.phase == .paused ? "play.fill" : "pause.fill")
                }
                .disabled(session.engine.phase != .playing && session.engine.phase != .paused)
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

            GeometryReader { geometry in
                HStack(spacing: 18) {
                    DivideBoard(engine: session.engine)
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
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch session.engine.phase {
        case .ready:
            statusCard("VECTOR DIVIDE", detail: "CLAIM 75% OF THE FIELD", instruction: "PRESS RETURN TO PLAY")
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
                        .offset(x: bar.size.width * 0.75)
                }
            }
            .frame(height: 9)
            Text("TARGET  75.0%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(amber)
            Divider().overlay(cyan.opacity(0.2))
            numberRow("LAST CAPTURE", String(format: "+%.1f%%", session.engine.lastGain), color: cyan)
            numberRow("AREA BONUS", "+\(session.engine.lastAward)", color: amber)
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
