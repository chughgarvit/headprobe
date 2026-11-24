import Foundation

/// Append-only CSV file. Only used from the session queue.
final class CSVFile {
    private let handle: FileHandle

    init(url: URL, header: [String]) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        row(header)
    }

    func row(_ fields: [String]) {
        let line = fields.map { f -> String in
            f.contains(",") || f.contains("\"") ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
        }.joined(separator: ",") + "\n"
        handle.write(line.data(using: .utf8)!)
    }

    func close() { try? handle.close() }
}

/// One folder per session in the app's Documents, visible in the Files app:
///   meta.json   configuration, device, audio route, clocks, calibration
///   motion.csv  every head-motion sample (raw, so analysis can re-score everything)
///   probes.csv  one row per probe: when and where it played, and the first-pass score
///   taps.csv    every screen touch (button-reference mode)
final class SessionLog {
    let folder: URL
    let motion: CSVFile
    let probes: CSVFile
    let taps: CSVFile

    init(name: String, meta: [String: Any]) throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("sessions").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: folder.appendingPathComponent("meta.json"))

        motion = try CSVFile(url: folder.appendingPathComponent("motion.csv"), header: [
            "t", "yaw_rel_deg", "yaw", "pitch", "roll", "qx", "qy", "qz", "qw", "rx", "ry", "rz",
        ])
        probes = try CSVFile(url: folder.appendingPathComponent("probes.csv"), header: [
            "probe", "mode", "azimuth_deg", "scheduled_t", "reported_latency_s", "bt_offset_s", "onset_t",
            "tap_rt_s", "miss", "no_data", "anticipation", "latency_start_s", "latency_exceed_s",
            "first_side", "correct_side", "endpoint_deg", "error_deg", "peak_vel_dps", "final_yaw_deg", "n_samples",
        ])
        taps = try CSVFile(url: folder.appendingPathComponent("taps.csv"), header: ["t", "during_probe"])
    }

    func close() {
        motion.close(); probes.close(); taps.close()
    }
}

func fmt(_ x: Double?, _ digits: Int = 4) -> String {
    guard let x, x.isFinite else { return "" }
    return String(format: "%.\(digits)f", x)
}

func fmt(_ b: Bool?) -> String {
    guard let b else { return "" }
    return b ? "1" : "0"
}
