# HeadProbe

A reaction-time test on ordinary earbuds. While a person does a task, a short noise burst plays from a
random direction (spatial audio). They turn their head toward it. AirPods head tracking records how fast
they start to turn, whether they turn at all, and how accurately they land on the sound. These measures
are compared with the standard button-press reaction-time test (Detection Response Task, ISO 17488),
using a task with known difficulty levels (n-back) as ground truth.

**Status:** written, **never compiled or run**. It was written on a Windows machine without a Swift
toolchain. Expect the first build to need small fixes. The analysis script is tested (see below).

## What the app does

| Mode | Purpose |
|---|---|
| **Motion rate test** | 60 s of head-motion logging. Reports the real sample rate, jitter and gaps. Run this first. |
| **Latency sync test** | A click and a white screen flash at the same scheduled instant every 2 s. Film it to measure the Bluetooth delay (below). |
| **Head turn** | The measurement: probes every 3-5 s from ±30/60/90°, head turn as the response. |
| **Tap (button reference)** | Same probes, response is a touch on the screen. This is the standard-method comparison. |

Every session writes a folder (Files app > On My iPhone > HeadProbe > sessions):
`meta.json` (settings, device, audio route, clocks, calibration), `motion.csv` (every raw head sample),
`probes.csv` (each probe and a first-pass score), `taps.csv`.

## Before any real session: the two timing checks

The whole method depends on timing. Do these on the actual phone and earbuds before designing the study.

1. **Motion rate test.** Expected about 25 Hz. If it is much lower or has frequent gaps, latency
   resolution suffers (the scorer interpolates, and the self-test shows ±15 ms at 25 Hz).
2. **Latency sync test.** Bluetooth adds a delay the system does not fully report. Film the phone screen
   with a second phone in slow motion (240 fps), with one AirPod held against that phone's microphone.
   In the video, count the frames from the flash to the click. That delay, minus about one display frame,
   is the **Bluetooth offset**. Enter it in milliseconds on the setup screen for all real sessions.
   Repeat it a few times: if it varies by more than about 20 ms between clicks, reaction times are only
   usable as lapses and misses, not as fine-grained means.

## Running a session

1. Put the earbuds in. In Control Center, long-press the volume slider and turn **Spatial Audio /
   Spatialize Stereo off** for this app: the app renders direction itself.
2. Face forward, tap **Set forward**. Turn your head clearly right, tap **Confirm right**. This fixes
   which way is right, so nothing depends on CoreMotion's sign convention.
3. Enter participant (P01...), condition (e.g. `0back`, `2back`), mode, length, Bluetooth offset. Start.
4. Instruction to the participant: "Whenever you hear a sound, turn your head toward it as quickly as
   you can, then face forward again."

The n-back task itself is not in the app yet. It should run on a separate screen (laptop), because the
tap reference mode uses the phone screen.

## Scoring

`Sources/HeadProbe/ResponseDetector.swift` scores live; `analysis/headprobe_analyze.py` is the same
algorithm and is the version to report. Per probe:

- **latency_start**: time from sound onset to the head passing 2° (interpolated between samples).
  `latency_exceed` uses 8°, more robust to noise.
- **miss**: no turn beyond 8° within 2.5 s. **anticipation**: started within 100 ms (not a response).
- **endpoint / error**: where the first movement stops (two samples under 20°/s), and its distance
  from the target. **correct_side**: first turned toward the right side.
- **no_data**: a gap over 250 ms in the motion stream (earbud dropout).

Sound onset = scheduled time + reported output latency + Bluetooth offset.

```
python analysis/headprobe_analyze.py --selftest          # synthetic turns, should print "all passed"
python analysis/headprobe_analyze.py path/to/sessions/   # writes probes_scored.csv, prints summaries
```

The self-test passes: start latency within 15 ms of truth at 25 Hz across 540 synthetic turns
(±30/60/90°, three latencies, random sample phases), undershoot/overshoot, wrong side, misses,
anticipations, 180° wrap-around, dropouts, and no false turns from 1.5° head noise.

## Build

On a Mac, see **HANDOFF.md** for step-by-step instructions. Two routes, same sources:

- **Xcode:** `brew install xcodegen && xcodegen`, open `HeadProbe.xcodeproj`, choose your signing team, run.
- **xtool:** `brew install xtool-org/tap/xtool`, `xtool setup`, then `xtool dev` in this folder.
  (xtool also works from Linux or Windows via WSL; see its Installation-Linux guide.)

Needs an iPhone and earbuds with head tracking (AirPods Pro, AirPods 3rd gen or later, AirPods Max,
some Beats). Change the bundle ID (`xtool.yml` / `project.yml`) to something unique to you.

## Known limitations

- Generic HRTF, so directions are coarse and front/back is unreliable: probes are lateral only.
- AirPods yaw drifts slowly; every probe is scored relative to the head direction just before it.
- The probe sound is the same every time (as the DRT does). The orienting response habituates to
  repeated sounds, which is why the participant is instructed to respond.
- Clock assumption: motion, touch and audio times share one clock. `meta.json` records both clocks at
  the start so this can be checked.
