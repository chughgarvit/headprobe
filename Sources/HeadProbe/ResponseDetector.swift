import Foundation

/// Scores one head-turn response. The same algorithm, with the same constants, is in
/// analysis/headprobe_analyze.py, which is the authoritative version (it re-scores the raw
/// motion log and is tested there). This copy only gives live feedback and a first-pass log.
struct ResponseResult {
    var noData = false            // too few motion samples (earbud dropped out?)
    var miss = true               // never turned more than exceedDeg within the window
    var latencyStart: Double?     // s from sound onset to the 2-degree crossing (movement start)
    var latencyExceed: Double?    // s from sound onset to the 8-degree crossing (more robust)
    var anticipation = false      // started moving within 100 ms of onset: not a response to the sound
    var firstSide = 0             // +1 right, -1 left
    var correctSide: Bool?
    var endpoint: Double?         // yaw (deg) where the first movement stops
    var error: Double?            // endpoint - target (deg)
    var peakVelocity: Double?     // deg/s
    var finalYaw: Double?         // yaw at window end; differs from endpoint after a correction
    var samples = 0
}

enum ResponseDetector {
    static let baselineWindow = 0.3   // s before onset used as the head's resting direction
    static let startDeg = 2.0
    static let exceedDeg = 8.0
    static let stillVelocity = 20.0   // deg/s; below this for two samples = movement has stopped
    static let minLatency = 0.1       // s; faster starts are anticipations
    static let maxGap = 0.25          // s; a longer gap in motion samples = dropout

    /// samples: (time s, right-positive yaw deg) on the motion clock.
    static func analyze(samples: [(t: Double, y: Double)], onset: Double,
                        window: Double, target: Double) -> ResponseResult {
        var r = ResponseResult()
        let base = samples.filter { $0.t >= onset - baselineWindow && $0.t <= onset }.map { $0.y }
        let post = samples.filter { $0.t > onset && $0.t <= onset + window }
        r.samples = post.count
        guard !base.isEmpty, post.count >= 3 else { r.noData = true; return r }
        // Earbud dropouts: any gap longer than maxGap from onset to window end makes the probe unscorable.
        let edges = [onset] + post.map { $0.t } + [min(onset + window, samples.last?.t ?? onset)]
        if zip(edges, edges.dropFirst()).map({ $1 - $0 }).max() ?? 0 > maxGap { r.noData = true; return r }

        let b = median(base)
        let t = post.map { $0.t }
        let y = post.map { wrapDeg($0.y - b) }
        var v = [0.0]
        for i in 1..<y.count {
            let dt = t[i] - t[i - 1]
            v.append(dt > 0 ? (y[i] - y[i - 1]) / dt : 0)
        }
        r.finalYaw = y.last

        guard let k = y.firstIndex(where: { abs($0) >= exceedDeg }) else { return r }
        r.miss = false
        let side = y[k] > 0 ? 1.0 : -1.0
        r.firstSide = Int(side)
        if target != 0 { r.correctSide = (side > 0) == (target > 0) }

        // Crossing times, interpolated between samples, counted in the direction of the turn.
        r.latencyExceed = crossing(t: t, y: y.map { $0 * side }, level: exceedDeg, upTo: k, onset: onset)
        r.latencyStart = crossing(t: t, y: y.map { $0 * side }, level: startDeg, upTo: k, onset: onset)
        if let s = r.latencyStart, s < minLatency { r.anticipation = true }

        // End of the first movement: two consecutive slow samples.
        var m = y.count - 1
        var i = k
        while i < y.count - 1 {
            if abs(v[i]) < stillVelocity && abs(v[i + 1]) < stillVelocity { m = i; break }
            i += 1
        }
        r.endpoint = y[m]
        r.error = y[m] - target
        r.peakVelocity = v[k...m].map { abs($0) }.max()
        return r
    }

    /// Time after onset at which `y` (already signed so the turn is positive) last rises through
    /// `level` before index `upTo`. If the head was already past `level` at the first sample,
    /// returns the first sample's time.
    static func crossing(t: [Double], y: [Double], level: Double, upTo k: Int, onset: Double) -> Double {
        var j = k
        while j > 0 && y[j - 1] >= level { j -= 1 }
        if j == 0 { return t[0] - onset }
        let (t0, t1, y0, y1) = (t[j - 1], t[j], y[j - 1], y[j])
        let f = y1 != y0 ? (level - y0) / (y1 - y0) : 0
        return t0 + f * (t1 - t0) - onset
    }
}
