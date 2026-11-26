import CoreMotion
import Foundation

struct HeadSample {
    let t: Double          // seconds since boot (CMDeviceMotion.timestamp)
    let recv: Double       // Clock.now() when the sample reached the app: recv - t shows what
                           // the timestamp means (sensor time vs arrival time) and how it jitters
    let yaw: Double        // radians, raw from CoreMotion
    let pitch: Double
    let roll: Double
    let qx: Double, qy: Double, qz: Double, qw: Double
    let rx: Double, ry: Double, rz: Double   // rotation rate, rad/s
}

/// Head orientation from AirPods (Pro, Max, 3rd gen or later) or Beats with head tracking.
/// Samples arrive at about 50 Hz (AirPods Pro, iOS 27); the motion rate test measures the real rate.
final class HeadTracker: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    private let manager = CMHeadphoneMotionManager()
    private let opQueue = OperationQueue()
    private let lock = NSLock()
    private var latest: HeadSample?

    @Published var connected = false
    @Published var available = false

    /// Called for every sample on `queue` (the session queue).
    var onSample: ((HeadSample) -> Void)?

    /// Calibration: +1 or -1 so that a turn to the RIGHT gives positive yaw, and the raw yaw
    /// that counts as straight ahead. CoreMotion's sign convention for headphones is not
    /// something we rely on: the participant turns right once and we read the sign.
    var yawSign: Double = 1
    var yawZero: Double = 0

    init(queue: DispatchQueue) {
        super.init()
        opQueue.maxConcurrentOperationCount = 1
        opQueue.underlyingQueue = queue
        manager.delegate = self
        available = manager.isDeviceMotionAvailable
    }

    func start() {
        available = manager.isDeviceMotionAvailable
        guard available, !manager.isDeviceMotionActive else { return }
        manager.startDeviceMotionUpdates(to: opQueue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let a = m.attitude, q = a.quaternion, r = m.rotationRate
            let s = HeadSample(t: m.timestamp, recv: Clock.now(), yaw: a.yaw, pitch: a.pitch, roll: a.roll,
                               qx: q.x, qy: q.y, qz: q.z, qw: q.w, rx: r.x, ry: r.y, rz: r.z)
            self.lock.lock(); self.latest = s; self.lock.unlock()
            self.onSample?(s)
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    func latestSample() -> HeadSample? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    /// Yaw in degrees, right-positive, relative to the calibrated straight-ahead.
    func relYawDeg(_ s: HeadSample) -> Double {
        wrapDeg(yawSign * (s.yaw - yawZero) * 180 / .pi)
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async { self.connected = true }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async { self.connected = false }
    }
}
