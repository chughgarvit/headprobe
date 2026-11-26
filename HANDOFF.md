# Handoff: continue on the Mac

Written 2026-11-24 on a Windows machine that cannot build iOS apps. Everything in `Sources/` has
**never been compiled**. The analysis script has been run and its self-test passes.

## The project in one paragraph

HeadProbe tests whether ordinary earbuds can run a reaction-time test for mental load and alertness.
While a person does a task, a 150 ms noise burst plays from a random direction (±30/60/90°, spatial
audio, every 3-5 s). They turn their head toward it. AirPods head tracking gives: time to start turning,
misses, and how accurately the head lands (error, side, left/right bias). Ground truth is task difficulty
we control (n-back 0/1/2/3), compared against the standard button-press method (Detection Response Task,
ISO 17488), which the app also runs ("Tap" mode). Questionnaires (NASA-TLX, Karolinska Sleepiness
Scale) are only manipulation checks.

## Tasks, in order

### 1. Build and install (first session on the Mac)

Pick one route. Route A is easier for debugging.

**A. Xcode project via XcodeGen**
```bash
brew install xcodegen
cd headprobe
xcodegen                     # creates HeadProbe.xcodeproj from project.yml
open HeadProbe.xcodeproj
```
In Xcode: target HeadProbe > Signing & Capabilities > pick your Team (a free personal team works;
the app then expires after 7 days and must be re-installed). Change the bundle ID if it clashes.
Connect the iPhone, select it as the run destination, press Run. On the phone, trust the developer
under Settings > General > VPN & Device Management.

**B. xtool** (matches the original setup)
```bash
brew install xtool-org/tap/xtool
xtool setup                  # Apple ID login
cd headprobe && xtool dev    # builds and installs to the connected iPhone
```

Expect compile errors on the first build: fix them, keeping the behaviour described in the comments.
Things most likely to need attention:
- `ProbeSession.swift`: Swift 5 language mode is set on purpose (motion and audio callbacks run on
  one serial queue). If Xcode defaults to Swift 6, set SWIFT_VERSION 5.
- `ProbeAudio.swift`: `AVAudioEnvironmentNode.outputType`, `player.renderingAlgorithm = .HRTFHQ`,
  scheduling with `AVAudioTime(hostTime:)`.
- `HeadTracker.swift`: `OperationQueue.underlyingQueue` set to the session queue.

### 2. Check that it works, with earbuds in (AirPods Pro / 3rd gen+ / Max)

1. Control Center: turn **Spatial Audio / Spatialize Stereo off** for HeadProbe.
2. Head tracking shows "available" and live yaw moves when you turn. Calibrate: Set forward, turn
   right, Confirm right. Turning right must now give positive yaw.
3. **Motion rate test** (60 s). Note the Hz, jitter and gaps it reports. Measured 50 Hz on AirPods Pro (2026-11-25).
4. **Head turn**, 1 minute: sounds come from the left and right as labelled in the live result line
   (a -60° probe must sound left). If left/right are swapped, the sign in
   `ProbeAudio.setDirection` is wrong for this renderer: fix it there.
5. **Latency sync test**: film the screen at 240 fps with a second phone, an AirPod held to its mic.
   Frames from flash to click (x 4.17 ms) plus about one display frame = total audio delay
   (enter it as "Audio delay"; it replaces the reported latency, it is not added to it). Repeat
   10+ clicks; record the mean and SD in `docs/timing.md` (create it).
6. Get the session folders off the phone (Files app > On My iPhone > HeadProbe > sessions, or
   Finder's file sharing), then:
   ```bash
   python3 analysis/headprobe_analyze.py --selftest
   python3 analysis/headprobe_analyze.py path/to/sessions/
   ```
   Check that `meta.json` clock_mach_s and clock_uptime_s are nearly equal (the scorer assumes motion,
   touch and audio share one clock).

**Decision point:** if the audio delay varies by more than about 20 ms between clicks, the paper
reports misses, lapses and turn accuracy, not fine-grained mean reaction times.

### 3. Not built yet

- **n-back task** on a laptop screen (a small web page): letters every 2.5 s, 0/1/2/3-back blocks,
  logs accuracy. It runs on a separate screen because Tap mode uses the phone screen. Its clock is not
  shared with the phone; align blocks by start time (blocks are minutes long, so seconds of error are fine).
- **Left/right bias analysis** in `headprobe_analyze.py`: miss rate and signed error for left vs right
  probes per session (the drowsiness question below).
- **Study protocol and ethics application.** No participant data before approval.

## Open decision (supervisor)

Two directions; not decided as of 2026-11-24:
1. **Load first** (recommended): n-back difficulty x {head turn, tap}, 15-20 seated participants.
   Left/right bias recorded as a secondary measure.
2. **Drowsiness**: replicate the leftward-neglect-at-sleep-onset effect (Bareham et al. 2014) with
   earbud head turns, in a long eyes-closed listening session, against the Karolinska Sleepiness Scale or
   EEG. Risk: Minton et al. CHI 2025 found ordinary fatigue did not change sound-pointing error, and
   reaction times got faster.

## Prior art (searched 2026-11-24, web only; not a systematic review)

Nothing found that plays a spatial probe through earbuds and uses the head turn to measure load or
alertness. Closest work, must cite:
- Lertpoompunya, Ozmeral, Higgins, Eddins. Head-orienting behaviors during simultaneous speech
  detection and localization. Front. Psychol. 15:1425972, 2024. doi:10.3389/fpsyg.2024.1425972.
  Loudspeakers + optical tracker at 120 Hz; undershoot beyond 60°; "wait-and-listen" pause in hard conditions.
- ISO 17488:2016 Detection Response Task; head-mounted DRT in driving (https://trid.trb.org/view/1261938).
- Bareham, Manly, Pustovaya, Scott, Bekinschtein. Losing the left side of the world. Sci. Rep. 4:5092, 2014.
  Also Jagannathan et al., J. Neurosci. 42(3):454, 2022.
- Minton et al. A Longitudinal Study on the Effects of Circadian Fatigue on Sound Source Identification
  and Localization using a Heads-Up Display. CHI 2025.
- Jung et al. Auditory vs visual PVT under sleep deprivation. J. Sleep Res. 2011, doi:10.1111/j.1365-2869.2010.00877.x.
- Samsung patent US12155989B2 (headset checks for a head turn toward a loud sound within ~1 s).
- Brungart, Simpson et al. 2004 (head-tracker latency vs response time; slower above ~73 ms).
- AudioPIN, Naitou et al., CHI EA 2026, doi:10.1145/3772363.3798635 (spatial audio + AirPods head tracking).

Verify each citation against its DOI before it goes in a paper.
