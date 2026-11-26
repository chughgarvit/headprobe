# HeadProbe (iOS app)

This is the iOS app that goes with the paper. While a person does a task, the app plays a short noise burst from
a random direction to the left or right using spatial audio. The person turns their head toward the
sound. The head tracking in the earbuds records how fast the turn starts, whether the person turned
at all, and which side they turned to. A tap mode plays the same sounds but takes a touch on the
screen as the response. This is the standard Detection Response Task (DRT, ISO 17488), which the
head turns are compared against.

## Requirements

- An iPhone with iOS 17 or later.
- Earbuds that support head tracking: AirPods Pro, AirPods (3rd generation or later), AirPods Max,
  or Beats models with spatial audio.
- A free or paid Apple ID to sign the app. With a free Apple ID the installed app expires after 7 days.
  You then reinstall it.

## Build and install

Every route builds the same sources in `Sources/HeadProbe`. First change the bundle ID in
`xtool.yml` and in `project.yml` to one that is unique to you, for example `com.yourname.HeadProbe`.

**macOS with Xcode**

```bash
brew install xcodegen
xcodegen                      # generates HeadProbe.xcodeproj from project.yml
open HeadProbe.xcodeproj      # choose your signing team, select the iPhone, then Run
```

**macOS or Linux with xtool (no Xcode project)**

```bash
brew install xtool-org/tap/xtool      # on Linux, see the xtool Linux installation guide
xtool setup                           # one time: makes the iOS SDK from an Xcode .xip
xtool auth login                      # sign in with your Apple ID
xtool devices                         # the iPhone should be listed (USB, phone unlocked, "Trust" accepted)
xtool dev run                         # build, sign and install
```

**Windows (WSL)**

Use the xtool steps inside WSL (Ubuntu). USB passthrough into WSL is unreliable. Instead, let WSL use
the Apple Mobile Device service that iTunes or the Apple Devices app installs on Windows:

```powershell
# Admin PowerShell, one time. <WSL_HOST_IP> is the Windows side of the WSL network
# (in WSL, `ip route` shows it as the default gateway).
New-NetFirewallRule -DisplayName "WSL to usbmuxd" -Direction Inbound `
  -InterfaceAlias "vEthernet (WSL (Hyper-V firewall))" -Protocol TCP -LocalPort 27015 -Action Allow
netsh interface portproxy set v4tov4 listenport=27015 listenaddress=<WSL_HOST_IP> connectport=27015 connectaddress=127.0.0.1
Restart-Service iphlpsvc      # if the port proxy does not start listening
```

```bash
# In WSL
export USBMUXD_SOCKET_ADDRESS=<WSL_HOST_IP>:27015
xtool devices
xtool dev run
```

The first time you install the app, trust the developer profile on the iPhone under
Settings > General > VPN & Device Management.

## Running a session

1. Put the earbuds in. In Control Center, long-press the volume slider and turn **Spatial Audio /
   Spatialize Stereo off**. The app positions the sound itself.
2. Calibrate. Face forward and tap **Set forward**. Then turn your head clearly to the right and tap
   **Confirm right**.
3. Enter a participant code (e.g. `P01`), a condition label (e.g. `0back`, `2back`), the mode, the
   session length and, if measured, the audio delay (see below). Tap **Start**.
4. The screen shows the instruction for the chosen mode. In head-turn mode it is: "Whenever you hear
   a sound, turn your head toward it as quickly as you can, then face forward again."

A sound plays every 3–5 s, from ±30°, ±60° or ±90°.

| Mode | What it does |
|---|---|
| **Head turn** | The measurement. The response is a head turn. |
| **Tap (button reference)** | The same sounds. The response is a tap on the screen (standard DRT). |
| **Motion rate test** | Logs head motion for 60 s and reports the sample rate, jitter and gaps. Run it first. |
| **Latency sync test (camera)** | A click and a white flash at the same scheduled moment every 2 s, for measuring the Bluetooth audio delay with a slow-motion camera. |
| **System baseline (idle)** | The app is open with the screen on, no audio and no head tracking. Use it as the reference for battery, CPU and memory cost. |

**Audio delay (optional).** Film the screen in slow motion (240 fps) during the sync test, with one
earbud held against the filming phone's microphone. Count the frames from the flash to the click, then
add about one display frame. Enter that number as the audio delay. If you leave it at 0, the app uses
the output latency that iOS reports. The two values are never added together. Comparisons between
conditions for the same person are not affected by a constant delay.

## Output

Each session writes a folder that you can find in the Files app under On My iPhone > HeadProbe >
sessions:

| File | Contents |
|---|---|
| `meta.json` | Settings, device model, audio route, clock references, calibration |
| `motion.csv` | Every raw head-motion sample (attitude, rotation rate, timestamps) |
| `probes.csv` | Each sound: direction, scheduled, played and onset times, plus a live score (start latency, miss, endpoint, correct side) |
| `taps.csv` | Screen touches (tap mode) |
| `system.csv` | Once a second: memory footprint, CPU, battery, charging, thermal state, Low Power Mode, reported output latency |

To copy the folders to a computer without using the Files app:
`pymobiledevice3 apps pull --documents <bundle-id> /sessions <destination>`.

## How the head turn is scored live

The scoring code is in `Sources/HeadProbe/ResponseDetector.swift`. For each sound:

- **Start latency:** the time from sound onset until the head has turned 2° away from where it pointed
  just before the sound. The exact crossing time is interpolated between samples.
- **Miss:** no turn beyond 8° within 2.5 s.
- **Anticipation:** the turn started less than 100 ms after onset, which is too early to be a response.
- **Endpoint and correct side:** where the first movement stops, and whether it went toward the
  side the sound came from.
- **No data:** the motion stream had a gap of more than 250 ms, for example an earbud dropout.

## Source files

| File | Role |
|---|---|
| `HeadProbeApp.swift`, `ContentView.swift` | App entry point, setup screen and session screen |
| `ProbeSession.swift` | Session timing, probe schedule, logging |
| `ProbeAudio.swift` | Spatial noise bursts scheduled on the audio clock |
| `HeadTracker.swift` | Head motion from the earbuds (CMHeadphoneMotionManager) |
| `ResponseDetector.swift` | Live head-turn scoring |
| `TapCatcher.swift` | Touch timestamps for tap mode |
| `Clock.swift` | One shared clock (mach_absolute_time) for audio, motion and touch timestamps |
| `SessionLog.swift` | CSV and JSON writers |
| `SystemMonitor.swift` | Once-a-second resource logging |

## Known limitations

- The audio uses a generic HRTF, so direction is coarse and front and back can be confused. That is
  why every sound comes from the left or the right.
- The yaw from the earbuds drifts slowly. Each sound is therefore scored relative to where the head
  pointed just before it.
- The same sound is played every time, as in the DRT. People orient to it less and less over
  time, which is why they are told to respond on purpose.
