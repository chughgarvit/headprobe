import AVFoundation
import Foundation
import UIKit

/// Once a second, writes the app's own resource use to system.csv in the session folder:
///   mem_mb       phys_footprint, the number iOS uses for memory limits (what Xcode's gauge shows)
///   cpu_pct      process CPU time over the last interval / wall time (100 = one core fully busy)
///   battery_pct  UIDevice.batteryLevel (iOS reports it in coarse steps; use the slope over a long run)
///   charging     1 if plugged in: battery numbers from such a session are not usable
///   thermal      ProcessInfo.thermalState: 0 nominal, 1 fair, 2 serious, 3 critical
///   low_power    Low Power Mode on
///   out_lat_s    output latency iOS reports right now (changes if the route changes)
/// Runs on the main queue (UIDevice is main-thread API) with its own file, so it never touches
/// the session queue's files.
final class SystemMonitor {
    private let csv: CSVFile
    private var timer: Timer?
    private var lastCPU = 0.0
    private var lastWall = 0.0

    init(folder: URL) throws {
        csv = try CSVFile(url: folder.appendingPathComponent("system.csv"), header: [
            "t", "mem_mb", "cpu_pct", "cpu_total_s", "battery_pct", "charging", "thermal", "low_power", "out_lat_s",
        ])
    }

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        lastCPU = SystemMonitor.cpuSeconds()
        lastWall = Clock.now()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sample()
        csv.close()
    }

    private func sample() {
        let now = Clock.now(), cpu = SystemMonitor.cpuSeconds()
        let pct = now > lastWall ? (cpu - lastCPU) / (now - lastWall) * 100 : 0
        lastCPU = cpu; lastWall = now
        let dev = UIDevice.current
        let level = dev.batteryLevel   // -1 if unknown
        let charging = dev.batteryState == .charging || dev.batteryState == .full
        csv.row([fmt(now, 3), fmt(SystemMonitor.footprintMB(), 2), fmt(pct, 2), fmt(cpu, 3),
                 level < 0 ? "" : fmt(Double(level) * 100, 0), fmt(charging),
                 String(ProcessInfo.processInfo.thermalState.rawValue),
                 fmt(ProcessInfo.processInfo.isLowPowerModeEnabled),
                 fmt(AVAudioSession.sharedInstance().outputLatency, 4)])
    }

    /// User + system CPU seconds used by this process so far (all threads, including audio).
    static func cpuSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        return s(u.ru_utime) + s(u.ru_stime)
    }

    /// Memory footprint in MB (task_vm_info.phys_footprint).
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : .nan
    }
}
