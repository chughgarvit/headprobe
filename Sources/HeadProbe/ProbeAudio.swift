import AVFoundation

/// Plays a short noise burst from a chosen direction using Apple's HRTF renderer.
///
/// Directions are relative to the head at the moment of the probe: +90 is the right ear,
/// -90 the left ear. The burst is short (150 ms by default), so it ends before the head starts
/// to move (head-turn onsets are typically 200-300 ms) and no head-tracked re-rendering is
/// needed while it plays.
///
/// Turn OFF "Spatialize Stereo" / Spatial Audio for this app in Control Center: the app renders
/// the direction itself and the system must not process the stereo output again.
final class ProbeAudio {
    let engine = AVAudioEngine()
    let environment = AVAudioEnvironmentNode()
    let player = AVAudioPlayerNode()
    let format: AVAudioFormat
    private(set) var burst: AVAudioPCMBuffer
    private(set) var click: AVAudioPCMBuffer

    init(burstMs: Double = 150) {
        let f = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        format = f
        burst = ProbeAudio.makeNoiseBurst(format: f, ms: burstMs, seed: 1)
        click = ProbeAudio.makeNoiseBurst(format: f, ms: 10, seed: 2)

        engine.attach(environment)
        engine.attach(player)
        // A source must be mono for the environment node to spatialise it.
        engine.connect(player, to: environment, format: format)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)

        player.renderingAlgorithm = .HRTFHQ
        player.reverbBlend = 0
        environment.outputType = .headphones
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        environment.reverbParameters.enable = false
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 1
        setDirection(degrees: 0)
    }

    func setBurstLength(ms: Double) {
        burst = ProbeAudio.makeNoiseBurst(format: format, ms: ms, seed: 1)
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // .playback only: no microphone, so AirPods stay in the high-quality A2DP profile.
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        engine.prepare()
        try engine.start()
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
    }

    /// Latency the system reports (I/O buffer plus route). For Bluetooth this is only part of the
    /// story; the sync test measures the rest, entered as the Bluetooth offset.
    var reportedLatency: Double {
        let s = AVAudioSession.sharedInstance()
        return s.outputLatency + s.ioBufferDuration
    }

    var routeDescription: String {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .map { "\($0.portName) [\($0.portType.rawValue)]" }
            .joined(separator: ", ")
    }

    /// Right-positive azimuth in degrees, at 1 m, on the horizontal plane.
    /// Environment coordinates: +x right, +y up, -z straight ahead.
    func setDirection(degrees: Double) {
        let r = degrees * .pi / 180
        player.position = AVAudio3DPoint(x: Float(sin(r)), y: 0, z: -Float(cos(r)))
    }

    /// Queue a buffer to start at an absolute host time (mach_absolute_time ticks).
    func play(_ buffer: AVAudioPCMBuffer, atHostTime host: UInt64) {
        player.scheduleBuffer(buffer, at: AVAudioTime(hostTime: host), options: [], completionHandler: nil)
    }

    /// Broadband white noise (good for localisation: HRTF cues need high frequencies) with
    /// 5 ms raised-cosine ramps. Fixed seed, so every probe is the identical sound.
    static func makeNoiseBurst(format: AVAudioFormat, ms: Double, seed: UInt64) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(format.sampleRate * ms / 1000)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        let data = buf.floatChannelData![0]
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        let ramp = Int(format.sampleRate * 0.005)
        for i in 0..<Int(n) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u = Double(state >> 11) / Double(1 << 53) * 2 - 1
            var g = 1.0
            if i < ramp { g = 0.5 - 0.5 * cos(.pi * Double(i) / Double(ramp)) }
            if i >= Int(n) - ramp { g = 0.5 - 0.5 * cos(.pi * Double(Int(n) - 1 - i) / Double(ramp)) }
            data[i] = Float(0.35 * u * g)
        }
        return buf
    }
}
