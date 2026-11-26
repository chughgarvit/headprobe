import AVFoundation
import Foundation
import UIKit

enum Mode: String, CaseIterable, Identifiable {
    case head = "Head turn"
    case tap = "Tap (button reference)"
    case sync = "Latency sync test (camera)"
    case idle = "System baseline (idle)"
    case rate = "Motion rate test"
    var id: String { rawValue }
    var tag: String {
        switch self {
        case .head: return "head"
        case .tap: return "tap"
        case .idle: return "idle"
        case .sync: return "sync"
        case .rate: return "rate"
        }
    }
}

struct SessionConfig {
    var participant = "P01"
    var condition = "practice"
    var mode: Mode = .head
    var minutes: Double = 5
    /// Lateral only, never straight ahead or behind: generic HRTFs cause front/back confusions,
    /// and a sound straight ahead needs no turn.
    var azimuths: [Double] = [-90, -60, -30, 30, 60, 90]
    var isiMin = 3.0          // s between probe onsets, uniform in [isiMin, isiMax] (as in the DRT)
    var isiMax = 5.0
    var window = 2.5          // s after onset in which a response counts
    var burstMs = 150.0
    /// Total delay from scheduled time to sound at the ear, measured with the sync test
    /// (it already contains the latency iOS reports). 0 = not measured: use the reported latency.
    var audioDelayMs = 0.0

    /// Seconds from scheduled time to sound onset at the ear.
    func onsetDelay(reported: Double) -> Double {
        audioDelayMs > 0 ? audioDelayMs / 1000 : reported
    }
}

/// Runs one session. All state lives on `queue`; the UI only reads the @Published values.
final class ProbeSession: ObservableObject {
    @Published var running = false
    @Published var status = "Idle"
    @Published var probesDone = 0
    @Published var lastResult = ""
    @Published var flash = false
    @Published var report = ""
    @Published var calibrated = false
    @Published var liveYaw: Double?
    @Published var headAvailable = false

    private let queue: DispatchQueue
    let tracker: HeadTracker
    let audio = ProbeAudio()

    private var cfg = SessionConfig()
    private var log: SessionLog?
    private var monitor: SystemMonitor?
    private var endTime = 0.0
    private var bag: [Double] = []
    private var probeCount = 0
    private var history: [(t: Double, y: Double)] = []
    /// Probes played but not yet scored. Scoring runs after each probe's window, independently
    /// of when the next probe is planned, so the ISI really is uniform in [isiMin, isiMax].
    private var pending: [Int: Pending] = [:]
    private var lastProbePlanned = false
    private var lastOnset = 0.0
    private var motionTimes: [Double] = []
    private var stopped = true

    private struct Pending {
        let id: Int
        let azimuth: Double
        let scheduled: Double
        let reported: Double
        let onset: Double
        var tapRT: Double?
        /// When iOS reported the burst as played back (.dataPlayedBack), on the same clock.
        var playedBack: Double?
    }

    init() {
        let q = DispatchQueue(label: "headprobe.session", qos: .userInteractive)
        queue = q
        tracker = HeadTracker(queue: q)
        tracker.onSample = { [weak self] s in self?.handle(sample: s) }
        tracker.start()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.headAvailable { self.tracker.start() }   // retry until earbuds are connected
            self.headAvailable = self.tracker.available
            if let s = self.tracker.latestSample() { self.liveYaw = self.tracker.relYawDeg(s) }
        }
    }

    // MARK: Calibration

    func setForward() {
        guard let s = tracker.latestSample() else { status = "No head data: are the earbuds in?"; return }
        tracker.yawZero = s.yaw
        tracker.yawSign = 1
        calibrated = false
        status = "Forward set. Now turn your head clearly to the RIGHT and press Confirm right."
    }

    func confirmRight() {
        guard let s = tracker.latestSample() else { status = "No head data"; return }
        let raw = wrapDeg((s.yaw - tracker.yawZero) * 180 / .pi)
        guard abs(raw) >= 20 else { status = "Turn further to the right (at least 20°) and press again."; return }
        tracker.yawSign = raw > 0 ? 1 : -1
        calibrated = true
        status = String(format: "Calibrated (sign %+.0f). Face forward again before starting.", tracker.yawSign)
    }

    // MARK: Start / stop

    func start(_ config: SessionConfig) {
        cfg = config
        if cfg.mode == .head && !calibrated { status = "Calibrate first."; return }
        if (cfg.mode == .head || cfg.mode == .rate) && tracker.latestSample() == nil {
            status = "No head-motion data. Put the earbuds in and wait a moment."; return
        }
        if cfg.mode == .idle {
            tracker.stop()   // baseline = app open and screen on, nothing else
        } else {
            audio.setBurstLength(ms: cfg.burstMs)
            do { try audio.start() } catch { status = "Audio failed: \(error.localizedDescription)"; return }
        }

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let modeTag = cfg.mode.tag
        let name = "\(cfg.participant)_\(cfg.condition)_\(modeTag)_\(stamp)"
        let meta: [String: Any] = [
            "participant": cfg.participant, "condition": cfg.condition, "mode": modeTag,
            "minutes": cfg.minutes, "azimuths_deg": cfg.azimuths, "isi_s": [cfg.isiMin, cfg.isiMax],
            "window_s": cfg.window, "burst_ms": cfg.burstMs, "audio_delay_ms": cfg.audioDelayMs,
            "onset_rule": "onset = scheduled + (audio_delay_ms > 0 ? audio_delay_ms : reported latency)",
            "yaw_sign": tracker.yawSign, "yaw_zero_rad": tracker.yawZero,
            "reported_latency_s": audio.reportedLatency, "audio_route": audio.routeDescription,
            "clock_mach_s": Clock.now(), "clock_uptime_s": ProcessInfo.processInfo.systemUptime,
            "device": UIDevice.current.model, "hw_model": hardwareModel(), "ios": UIDevice.current.systemVersion,
            "started": ISO8601DateFormatter().string(from: Date()),
            "detector": ["baseline_s": ResponseDetector.baselineWindow, "start_deg": ResponseDetector.startDeg,
                         "exceed_deg": ResponseDetector.exceedDeg, "still_dps": ResponseDetector.stillVelocity,
                         "min_latency_s": ResponseDetector.minLatency],
        ]
        do { log = try SessionLog(name: name, meta: meta) } catch { status = "Could not create log: \(error)"; return }
        monitor = try? SystemMonitor(folder: log!.folder)
        monitor?.start()

        UIApplication.shared.isIdleTimerDisabled = true
        running = true
        probesDone = 0
        lastResult = ""
        report = ""
        status = "Running: \(name)"
        queue.async {
            self.stopped = false
            self.history.removeAll()
            self.motionTimes.removeAll()
            self.pending.removeAll()
            self.lastProbePlanned = false
            self.probeCount = 0
            self.bag.removeAll()
            let now = Clock.now()
            self.endTime = now + (self.cfg.mode == .rate ? 60 : self.cfg.minutes * 60)
            self.lastOnset = now
            switch self.cfg.mode {
            case .rate:
                self.queue.asyncAfter(deadline: .now() + 60) { self.finish() }
            case .sync:
                self.scheduleSyncClick(at: now + 2)
            case .head, .tap:
                self.scheduleNextProbe(earliest: now + 3)
            case .idle:
                // Battery/CPU/memory reference: app open, screen on, earbuds connected, no probes.
                self.queue.asyncAfter(deadline: .now() + self.cfg.minutes * 60) { self.finish() }
            }
        }
    }

    func stop() {
        queue.async { self.finish() }
    }

    private func finish() {
        guard !stopped else { return }
        stopped = true
        pending.removeAll()
        var summary = ""
        if cfg.mode == .rate { summary = rateSummary() }
        log?.close()
        let folder = log?.folder.lastPathComponent ?? ""
        log = nil
        let wasIdle = cfg.mode == .idle
        DispatchQueue.main.async {
            self.monitor?.stop()
            self.monitor = nil
            self.audio.stop()
            if wasIdle { self.tracker.start() }
            UIApplication.shared.isIdleTimerDisabled = false
            self.running = false
            self.report = summary
            self.status = "Saved \(folder). Files app > On My iPhone > HeadProbe > sessions."
        }
    }

    // MARK: Motion

    private func handle(sample s: HeadSample) {
        guard !stopped, let log else { return }
        let rel = tracker.relYawDeg(s)
        log.motion.row([fmt(s.t, 5), fmt(s.recv, 5), fmt(rel, 3), fmt(s.yaw, 6), fmt(s.pitch, 6), fmt(s.roll, 6),
                        fmt(s.qx, 6), fmt(s.qy, 6), fmt(s.qz, 6), fmt(s.qw, 6),
                        fmt(s.rx, 5), fmt(s.ry, 5), fmt(s.rz, 5)])
        history.append((s.t, rel))
        if let first = history.first, s.t - first.t > 8 { history.removeFirst(history.count / 4) }
        if cfg.mode == .rate { motionTimes.append(s.t) }
    }

    private func rateSummary() -> String {
        guard motionTimes.count > 10 else { return "Too few samples (\(motionTimes.count))." }
        let d = zip(motionTimes.dropFirst(), motionTimes).map { $0 - $1 }
        let mean = d.reduce(0, +) / Double(d.count)
        let sd = sqrt(d.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(d.count))
        let gaps = d.filter { $0 > 2 * mean }.count
        return String(format: "%d samples, %.1f Hz, interval %.1f ± %.1f ms, max %.0f ms, %d gaps > 2× mean",
                      motionTimes.count, 1 / mean, mean * 1000, sd * 1000, (d.max() ?? 0) * 1000, gaps)
    }

    // MARK: Probes

    private func nextAzimuth() -> Double {
        if bag.isEmpty { bag = cfg.azimuths.shuffled() }   // every direction once per cycle
        return bag.removeLast()
    }

    /// Plans one probe, then plans the next one shortly after this one plays. Planning never waits
    /// for scoring (which happens ~3 s after onset), so short ISIs are not pushed up to a floor.
    private func scheduleNextProbe(earliest: Double) {
        guard !stopped else { return }
        let isi = Double.random(in: cfg.isiMin...cfg.isiMax)
        let scheduled = max(lastOnset + isi, earliest, Clock.now() + 0.2)
        let reported = audio.reportedLatency
        let onset = scheduled + cfg.onsetDelay(reported: reported)
        guard onset + cfg.window < endTime else {
            lastProbePlanned = true
            if pending.isEmpty { queue.asyncAfter(deadline: .now() + 0.5) { self.finish() } }
            return
        }
        probeCount += 1
        let id = probeCount
        let az = nextAzimuth()
        lastOnset = scheduled
        pending[id] = Pending(id: id, azimuth: az, scheduled: scheduled, reported: reported, onset: onset)
        audio.setDirection(degrees: az)
        audio.play(audio.burst, atHostTime: Clock.host(fromSeconds: scheduled)) { [weak self] in
            let t = Clock.now()
            self?.queue.async { self?.pending[id]?.playedBack = t }
        }
        // Score once the window has passed, plus a margin for late motion samples.
        let wait = onset + cfg.window + 0.3 - Clock.now()
        queue.asyncAfter(deadline: .now() + max(0, wait)) { self.score(id) }
        // Plan the next probe once this burst has ended (the direction must not change mid-burst).
        let afterBurst = scheduled + cfg.burstMs / 1000 + 0.05 - Clock.now()
        queue.asyncAfter(deadline: .now() + max(0, afterBurst)) { self.scheduleNextProbe(earliest: Clock.now()) }
    }

    private func score(_ id: Int) {
        guard !stopped, let p = pending.removeValue(forKey: id), let log else { return }
        defer {
            if lastProbePlanned && pending.isEmpty { queue.asyncAfter(deadline: .now() + 0.5) { self.finish() } }
        }
        var r = ResponseResult()
        let c0 = Clock.now()
        if cfg.mode == .head {
            r = ResponseDetector.analyze(samples: history, onset: p.onset, window: cfg.window, target: p.azimuth)
        }
        let scoreMs = (Clock.now() - c0) * 1000
        log.probes.row([
            String(p.id), cfg.mode == .head ? "head" : "tap", fmt(p.azimuth, 0), fmt(p.scheduled, 5),
            fmt(p.reported, 4), fmt(cfg.audioDelayMs / 1000, 4), fmt(p.onset, 5), fmt(p.tapRT, 4),
            fmt(cfg.mode == .head ? r.miss : p.tapRT == nil), fmt(r.noData), fmt(r.anticipation),
            fmt(r.latencyStart), fmt(r.latencyExceed), String(r.firstSide), fmt(r.correctSide),
            fmt(r.endpoint, 1), fmt(r.error, 1), fmt(r.peakVelocity, 0), fmt(r.finalYaw, 1), String(r.samples),
            fmt(p.playedBack, 5), fmt(scoreMs, 3),
        ])
        let text: String
        if cfg.mode == .tap {
            text = p.tapRT.map { String(format: "#%d %+.0f°: tap %.0f ms", p.id, p.azimuth, $0 * 1000) }
                ?? String(format: "#%d %+.0f°: no tap", p.id, p.azimuth)
        } else if r.noData {
            text = "#\(p.id): no motion data"
        } else if r.miss {
            text = String(format: "#%d %+.0f°: no turn", p.id, p.azimuth)
        } else {
            text = String(format: "#%d %+.0f°: start %.0f ms, end %+.0f° (error %+.0f°)%@", p.id, p.azimuth,
                          (r.latencyStart ?? .nan) * 1000, r.endpoint ?? .nan, r.error ?? .nan,
                          r.correctSide == false ? ", WRONG SIDE" : "")
        }
        let n = p.id
        DispatchQueue.main.async { self.probesDone = n; self.lastResult = text }
    }

    /// Button-reference mode: a touch anywhere on the run screen. `t` is UITouch.timestamp.
    func tapped(at t: Double) {
        queue.async {
            guard !self.stopped, let log = self.log else { return }
            var during = false
            // Windows never overlap (isiMin > window), so at most one probe can claim the tap.
            let window = self.cfg.window
            if var p = self.pending.values.first(where: { $0.tapRT == nil && t >= $0.onset && t <= $0.onset + window }) {
                p.tapRT = t - p.onset
                self.pending[p.id] = p
                during = true
            }
            log.taps.row([fmt(t, 5), during ? "1" : "0"])
        }
    }

    // MARK: Sync test

    /// A click from straight ahead and a white screen flash at the same scheduled instant, every
    /// 2 s. Film the phone screen with a second phone in slow motion (240 fps), with one AirPod
    /// held against that phone's microphone. The delay from flash to click in the video, plus the
    /// display delay (about one frame), is the total audio delay to enter for real sessions.
    private func scheduleSyncClick(at t: Double) {
        guard !stopped else { return }
        guard t < endTime else { finish(); return }
        audio.setDirection(degrees: 0)
        audio.play(audio.click, atHostTime: Clock.host(fromSeconds: t))
        probeCount += 1
        let id = probeCount
        let reported = audio.reportedLatency
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, t - Clock.now())) {
            self.flash = true
            let shown = Clock.now()
            self.queue.async {
                self.log?.probes.row([String(id), "sync", "0", fmt(t, 5), fmt(reported, 4), "", fmt(shown, 5)]
                                     + Array(repeating: "", count: 15))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.flash = false }
        }
        DispatchQueue.main.async { self.probesDone = id }
        queue.asyncAfter(deadline: .now() + max(0, t + 2 - 0.5 - Clock.now())) { self.scheduleSyncClick(at: t + 2) }
    }
}

/// e.g. "iPhone16,1": the exact hardware, which UIDevice.model ("iPhone") does not give.
func hardwareModel() -> String {
    var u = utsname()
    uname(&u)
    return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
}
