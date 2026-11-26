import SwiftUI

struct ContentView: View {
    @StateObject private var session = ProbeSession()
    @State private var cfg = SessionConfig()

    var body: some View {
        if session.running {
            RunView(session: session, mode: cfg.mode)
        } else {
            setup
        }
    }

    private var setup: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Participant (e.g. P01)", text: $cfg.participant)
                        .textInputAutocapitalization(.characters)
                    TextField("Condition (e.g. 0back, 2back)", text: $cfg.condition)
                        .textInputAutocapitalization(.never)
                    Picker("Mode", selection: $cfg.mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if cfg.mode == .head || cfg.mode == .tap || cfg.mode == .sync || cfg.mode == .idle {
                        Stepper(String(format: "Length: %.0f min", cfg.minutes), value: $cfg.minutes, in: 1...30)
                    }
                    if cfg.mode == .head || cfg.mode == .tap {
                        HStack {
                            Text("Audio delay from sync test (ms, 0 = reported)")
                            TextField("0", value: $cfg.audioDelayMs, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("Earbuds") {
                    LabeledContent("Head tracking", value: session.headAvailable ? "available" : "not available")
                    LabeledContent("Live yaw", value: session.liveYaw.map { String(format: "%+.0f°", $0) } ?? "–")
                    Button("1. Face forward, then tap: Set forward") { session.setForward() }
                    Button("2. Turn head right, then tap: Confirm right") { session.confirmRight() }
                    if session.calibrated { Text("Calibrated").foregroundStyle(.green) }
                }

                Section {
                    Button("Start") { session.start(cfg) }
                        .disabled(cfg.mode == .head && !session.calibrated)
                }

                Section("Status") {
                    Text(session.status).font(.footnote)
                    if !session.report.isEmpty { Text(session.report).font(.footnote.monospaced()) }
                }
            }
            .navigationTitle("HeadProbe")
        }
    }
}

struct RunView: View {
    @ObservedObject var session: ProbeSession
    let mode: Mode

    var body: some View {
        ZStack {
            (session.flash ? Color.white : Color.black).ignoresSafeArea()
            if mode == .tap {
                TapCatcher { t in session.tapped(at: t) }.ignoresSafeArea()
            }
            VStack(spacing: 16) {
                Spacer()
                Text(instruction)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 24)
                    .allowsHitTesting(false)
                Text("\(session.probesDone)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.gray)
                    .allowsHitTesting(false)
                Text(session.lastResult)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.gray)
                    .allowsHitTesting(false)
                Spacer()
                Button("Stop") { session.stop() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .padding(.bottom, 32)
            }
        }
    }

    private var instruction: String {
        switch mode {
        case .head: return "Whenever you hear a sound, turn your head toward it as quickly as you can, then face forward again."
        case .tap: return "Whenever you hear a sound, tap the screen as quickly as you can."
        case .idle: return "System baseline: keep the earbuds in and the phone unplugged. Nothing will play. Leave the app open until it ends."
        case .sync: return "Sync test: film this screen in slow motion with an AirPod held to the camera's microphone."
        case .rate: return "Motion rate test: keep the earbuds in and move your head naturally for 60 seconds."
        }
    }
}
