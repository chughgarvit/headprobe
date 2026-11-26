import Foundation

/// One clock for everything: mach_absolute_time, in seconds.
/// CMDeviceMotion.timestamp and UITouch.timestamp are seconds since boot on the same clock
/// (ProcessInfo.systemUptime), and AVAudioTime host times are mach_absolute_time ticks.
/// meta.json records both at session start so the assumption can be checked in the data.
enum Clock {
    static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    static func seconds(fromHost host: UInt64) -> Double {
        Double(host) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }

    static func host(fromSeconds s: Double) -> UInt64 {
        UInt64(max(0, s) * 1e9 * Double(timebase.denom) / Double(timebase.numer))
    }

    static func now() -> Double { seconds(fromHost: mach_absolute_time()) }
}

/// Wrap an angle in degrees to (-180, 180].
func wrapDeg(_ d: Double) -> Double {
    var x = d.truncatingRemainder(dividingBy: 360)
    if x > 180 { x -= 360 }
    if x <= -180 { x += 360 }
    return x
}

func median(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    if s.isEmpty { return .nan }
    let m = s.count / 2
    return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
}
