"""Re-score HeadProbe sessions from the raw motion log and summarise them.

    python analysis/headprobe_analyze.py sessions/            # every session folder inside
    python analysis/headprobe_analyze.py --selftest           # check the scorer on synthetic turns
    python analysis/headprobe_analyze.py --system sessions/   # system cost: memory, CPU, battery, timing

The scorer is the same algorithm as Sources/HeadProbe/ResponseDetector.swift, with the same
constants. This file is the authoritative version: the app's probes.csv scores are first-pass only.
Writes probes_scored.csv per session and prints one summary line per session.
Standard library only.
"""
import csv
import json
import math
import random
import statistics
import sys
from pathlib import Path

BASELINE_S = 0.3
START_DEG = 2.0
EXCEED_DEG = 8.0
STILL_DPS = 20.0
MIN_LATENCY_S = 0.1
MAX_GAP_S = 0.25


def wrap(d):
    x = math.fmod(d, 360.0)
    if x > 180:
        x -= 360
    if x <= -180:
        x += 360
    return x


def crossing(t, y, level, k, onset):
    j = k
    while j > 0 and y[j - 1] >= level:
        j -= 1
    if j == 0:
        return t[0] - onset
    t0, t1, y0, y1 = t[j - 1], t[j], y[j - 1], y[j]
    f = (level - y0) / (y1 - y0) if y1 != y0 else 0.0
    return t0 + f * (t1 - t0) - onset


def score(samples, onset, window, target):
    """samples: list of (t, right-positive yaw deg). Returns a dict of measures."""
    r = dict(no_data=False, miss=True, latency_start=None, latency_exceed=None, anticipation=False,
             first_side=0, correct_side=None, endpoint=None, error=None, peak_vel=None,
             final_yaw=None, n=0)
    base = [y for t, y in samples if onset - BASELINE_S <= t <= onset]
    post = [(t, y) for t, y in samples if onset < t <= onset + window]
    r["n"] = len(post)
    if not base or len(post) < 3:
        r["no_data"] = True
        return r
    # Earbud dropouts: a gap longer than MAX_GAP_S anywhere from onset to window end (including
    # before the first and after the last sample) makes the probe unscorable. A stream that stops
    # mid-window, or a recording that ends before the window does, is no_data, never a miss.
    edges = [onset] + [p[0] for p in post] + [onset + window]
    if max(b - a for a, b in zip(edges, edges[1:])) > MAX_GAP_S:
        r["no_data"] = True
        return r
    b = statistics.median(base)
    t = [p[0] for p in post]
    y = [wrap(p[1] - b) for p in post]
    v = [0.0] + [((y[i] - y[i - 1]) / (t[i] - t[i - 1]) if t[i] > t[i - 1] else 0.0)
                 for i in range(1, len(y))]
    r["final_yaw"] = y[-1]
    k = next((i for i, yy in enumerate(y) if abs(yy) >= EXCEED_DEG), None)
    if k is None:
        return r
    r["miss"] = False
    side = 1.0 if y[k] > 0 else -1.0
    r["first_side"] = int(side)
    if target != 0:
        r["correct_side"] = (side > 0) == (target > 0)
    ys = [yy * side for yy in y]
    r["latency_exceed"] = crossing(t, ys, EXCEED_DEG, k, onset)
    r["latency_start"] = crossing(t, ys, START_DEG, k, onset)
    r["anticipation"] = r["latency_start"] < MIN_LATENCY_S
    m = len(y) - 1
    for i in range(k, len(y) - 1):
        if abs(v[i]) < STILL_DPS and abs(v[i + 1]) < STILL_DPS:
            m = i
            break
    r["endpoint"] = y[m]
    r["error"] = y[m] - target
    r["peak_vel"] = max(abs(x) for x in v[k:m + 1])
    return r


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def num(s):
    return float(s) if s not in ("", None) else None


def analyse_session(folder):
    folder = Path(folder)
    meta = json.loads((folder / "meta.json").read_text(encoding="utf-8"))
    motion = [(float(r["t"]), float(r["yaw_rel_deg"])) for r in read_csv(folder / "motion.csv")]
    probes = [p for p in read_csv(folder / "probes.csv") if p["mode"] in ("head", "tap")]
    window = float(meta["window_s"])
    rows = []
    for p in probes:
        onset = float(p["onset_t"])
        target = float(p["azimuth_deg"])
        if p["mode"] == "head":
            s = score(motion, onset, window, target)
        else:
            rt = num(p["tap_rt_s"])
            s = dict(no_data=False, miss=rt is None, latency_start=rt, anticipation=rt is not None and rt < MIN_LATENCY_S)
        rows.append({"probe": p["probe"], "mode": p["mode"], "azimuth_deg": target, **s})

    out = folder / "probes_scored.csv"
    keys = sorted({k for r in rows for k in r}, key=lambda k: (k not in ("probe", "mode", "azimuth_deg"), k))
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)

    valid = [r for r in rows if not r["no_data"]]
    hits = [r for r in valid if not r["miss"] and not r["anticipation"]]
    rts = [r["latency_start"] for r in hits]
    summary = dict(
        session=folder.name, mode=meta["mode"], condition=meta["condition"], probes=len(rows),
        no_data=len(rows) - len(valid), misses=sum(r["miss"] for r in valid),
        anticipations=sum(bool(r["anticipation"]) for r in valid),
        median_rt_ms=round(1000 * statistics.median(rts)) if rts else None,
        mean_rt_ms=round(1000 * statistics.fmean(rts)) if rts else None,
    )
    if meta["mode"] == "head" and hits:
        errs = [r["error"] for r in hits if r["error"] is not None]
        summary.update(
            wrong_side=sum(r["correct_side"] is False for r in hits),
            mean_abs_error_deg=round(statistics.fmean(abs(e) for e in errs), 1) if errs else None,
            signed_error_deg=round(statistics.fmean(errs), 1) if errs else None,
        )
    return summary


# ---------------------------------------------------------------- system cost

def pct(xs, q):
    """Percentile with linear interpolation (q in 0..100)."""
    xs = sorted(xs)
    if not xs:
        return None
    k = (len(xs) - 1) * q / 100
    lo, hi = math.floor(k), math.ceil(k)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def r1(x, d=1):
    return None if x is None else round(x, d)


def system_report(folder):
    """Resource use and timing of one session, from system.csv, motion.csv, probes.csv."""
    folder = Path(folder)
    meta = json.loads((folder / "meta.json").read_text(encoding="utf-8"))
    rep = dict(session=folder.name, mode=meta["mode"], hw=meta.get("hw_model"), ios=meta.get("ios"),
               route=meta.get("audio_route"))

    sysf = folder / "system.csv"
    if sysf.exists():
        rows = read_csv(sysf)
        t = [float(r["t"]) for r in rows]
        mem = [float(r["mem_mb"]) for r in rows if r["mem_mb"]]
        cpu = [float(r["cpu_pct"]) for r in rows[1:] if r["cpu_pct"]]   # first row has no interval
        cpu_total = [float(r["cpu_total_s"]) for r in rows]
        dur = t[-1] - t[0] if len(t) > 1 else 0
        bat = [(float(r["t"]), float(r["battery_pct"])) for r in rows if r["battery_pct"]]
        charging = any(r["charging"] == "1" for r in rows)
        rep.update(
            duration_min=r1(dur / 60, 2),
            mem_median_mb=r1(statistics.median(mem)) if mem else None, mem_peak_mb=r1(max(mem)) if mem else None,
            cpu_mean_pct=r1(statistics.fmean(cpu), 2) if cpu else None, cpu_p95_pct=r1(pct(cpu, 95), 2),
            cpu_s_per_min=r1((cpu_total[-1] - cpu_total[0]) / dur * 60, 2) if dur else None,
            thermal_max=max(int(r["thermal"]) for r in rows), low_power=any(r["low_power"] == "1" for r in rows),
            charging=charging,
        )
        if bat and not charging and dur >= 600:
            # iOS reports the level in coarse steps: only the slope over 10+ minutes means anything.
            rep.update(battery_start_pct=bat[0][1], battery_end_pct=bat[-1][1],
                       battery_drain_pct_per_h=r1((bat[0][1] - bat[-1][1]) / (dur / 3600), 2))
        else:
            rep["battery_drain_pct_per_h"] = None
            rep["battery_note"] = "plugged in" if charging else "run >= 10 min unplugged for a battery figure"

    mrows = read_csv(folder / "motion.csv") if (folder / "motion.csv").exists() else []
    if len(mrows) > 10:
        mt = [float(r["t"]) for r in mrows]
        d = [b - a for a, b in zip(mt, mt[1:])]
        m = statistics.fmean(d)
        rep.update(motion_hz=r1(1 / m, 1), motion_interval_ms=r1(1000 * m, 2),
                   motion_jitter_sd_ms=r1(1000 * statistics.pstdev(d), 2), motion_max_gap_ms=r1(1000 * max(d)),
                   motion_gaps_over_2x=sum(x > 2 * m for x in d), motion_samples=len(mt))
        if "t_recv" in mrows[0] and mrows[0]["t_recv"]:
            delay = [1000 * (float(r["t_recv"]) - float(r["t"])) for r in mrows]
            rep.update(motion_delivery_median_ms=r1(statistics.median(delay), 2),
                       motion_delivery_p95_ms=r1(pct(delay, 95), 2), motion_delivery_max_ms=r1(max(delay), 2))

    probes = [p for p in read_csv(folder / "probes.csv") if p["mode"] in ("head", "tap")]         if (folder / "probes.csv").exists() else []
    if probes:
        sched = [float(p["scheduled_t"]) for p in probes]
        isi = [b - a for a, b in zip(sched, sched[1:])]
        rep.update(probes=len(probes), isi_min_s=r1(min(isi), 3) if isi else None,
                   isi_max_s=r1(max(isi), 3) if isi else None, isi_mean_s=r1(statistics.fmean(isi), 3) if isi else None,
                   reported_latency_ms=r1(1000 * float(probes[0]["reported_latency_s"])))
        burst = float(meta["burst_ms"]) / 1000
        pb = [1000 * (float(p["played_back_t"]) - float(p["scheduled_t"]) - burst)
              for p in probes if p.get("played_back_t")]
        if pb:
            # Time from the scheduled end of the burst to iOS calling it "played back".
            rep.update(playback_residual_median_ms=r1(statistics.median(pb), 1),
                       playback_residual_sd_ms=r1(statistics.pstdev(pb), 1),
                       playback_residual_range_ms=[r1(min(pb), 1), r1(max(pb), 1)])
        sc = [float(p["score_ms"]) for p in probes if p.get("score_ms")]
        if sc:
            rep.update(score_compute_median_ms=r1(statistics.median(sc), 3), score_compute_max_ms=r1(max(sc), 3))

    size = sum(f.stat().st_size for f in folder.iterdir() if f.is_file())
    rep["storage_kb"] = r1(size / 1024)
    if rep.get("duration_min"):
        rep["storage_kb_per_min"] = r1(size / 1024 / rep["duration_min"])
    return rep


def overhead(reports):
    """Each session's cost above the idle baseline (app open, screen on, nothing running)."""
    idle = [r for r in reports if r["mode"] == "idle" and r.get("cpu_mean_pct") is not None]
    if not idle:
        return []
    base = idle[-1]
    out = []
    for r in reports:
        if r["mode"] == "idle" or r.get("cpu_mean_pct") is None:
            continue
        o = dict(session=r["session"], mode=r["mode"], vs=base["session"],
                 extra_cpu_pct=r1(r["cpu_mean_pct"] - base["cpu_mean_pct"], 2),
                 extra_mem_mb=r1(r["mem_median_mb"] - base["mem_median_mb"]))
        if r.get("battery_drain_pct_per_h") is not None and base.get("battery_drain_pct_per_h") is not None:
            o["extra_drain_pct_per_h"] = r1(r["battery_drain_pct_per_h"] - base["battery_drain_pct_per_h"], 2)
        out.append(o)
    return out


# ---------------------------------------------------------------- self-test

def synthetic_turn(onset, latency, target, overshoot=0.0, rate_hz=25.0, noise=0.3, duration=0.4,
                   seed=0, start_yaw=0.0, window=2.5, miss=False):
    """Minimum-jerk head turn sampled like AirPods (about 25 Hz, random phase)."""
    rnd = random.Random(seed)
    t = onset - 1.0 + rnd.random() / rate_hz
    out = []
    amp = target * (1 + overshoot)
    while t < onset + window + 0.5:
        if miss:
            yaw = start_yaw
        else:
            s = (t - onset - latency) / duration
            s = min(max(s, 0.0), 1.0)
            yaw = start_yaw + amp * (10 * s**3 - 15 * s**4 + 6 * s**5)
        out.append((t, yaw + rnd.gauss(0, noise)))
        t += 1.0 / rate_hz
    return out


def selftest():
    failures = 0

    def check(name, cond, detail=""):
        nonlocal failures
        print(("ok   " if cond else "FAIL ") + name + (f"  ({detail})" if detail else ""))
        failures += not cond

    # Latency: the true start is when the minimum-jerk curve leaves zero; the 2-degree crossing comes
    # a little later. Compare against the crossing time of the noise-free curve.
    for target in (-90, -60, -30, 30, 60, 90):
        for lat in (0.25, 0.45, 0.8):
            errs = []
            for seed in range(30):
                s = synthetic_turn(10.0, lat, target, seed=seed)
                r = score(s, 10.0, 2.5, target)
                clean = synthetic_turn(10.0, lat, target, noise=0.0, rate_hz=2000, seed=seed)
                truth = next(t for t, y in clean if abs(y) >= START_DEG) - 10.0
                errs.append(r["latency_start"] - truth)
                assert not r["miss"] and r["correct_side"]
            check(f"latency target {target:+} lat {lat}", max(abs(e) for e in errs) < 0.03,
                  f"max error {1000 * max(abs(e) for e in errs):.0f} ms over 30 random sample phases")

    r = score(synthetic_turn(10.0, 0.3, 60, overshoot=-0.25, seed=3), 10.0, 2.5, 60)
    check("undershoot endpoint", abs(r["error"] - (-15)) < 3, f"error {r['error']:.1f} deg, expected -15")

    r = score(synthetic_turn(10.0, 0.3, 60, overshoot=0.2, seed=4), 10.0, 2.5, 60)
    check("overshoot endpoint", abs(r["error"] - 12) < 3, f"error {r['error']:.1f} deg, expected +12")

    r = score(synthetic_turn(10.0, 0.3, -60, seed=5), 10.0, 2.5, 60)
    check("wrong side", r["correct_side"] is False and r["first_side"] == -1)

    r = score(synthetic_turn(10.0, 0.0, 60, miss=True, seed=6), 10.0, 2.5, 60)
    check("no turn = miss", r["miss"] and not r["no_data"])

    r = score(synthetic_turn(10.0, 0.03, 60, seed=7), 10.0, 2.5, 60)
    check("anticipation flagged", r["anticipation"], f"start {1000 * r['latency_start']:.0f} ms")

    r = score(synthetic_turn(10.0, 0.3, 30, start_yaw=170, seed=8), 10.0, 2.5, 30)
    check("wrap-around at 180 deg", not r["miss"] and abs(r["error"]) < 3, f"error {r['error']:.1f}")

    r = score([(t, y) for t, y in synthetic_turn(10.0, 0.3, 60, seed=9) if not (10.0 < t < 12.0)], 10.0, 2.5, 60)
    check("dropout = no data", r["no_data"])

    r = score([(t, y) for t, y in synthetic_turn(10.0, 0, 60, miss=True, seed=11) if t < 11.0], 10.0, 2.5, 60)
    check("stream stops mid-window before any turn = no data, not a miss", r["no_data"])

    still = [score(synthetic_turn(10.0, 0, 60, miss=True, noise=1.5, seed=s), 10.0, 2.5, 60)["miss"]
             for s in range(50)]
    check("noisy still head (1.5 deg SD) is never a turn", all(still), f"{sum(still)}/50 misses")

    r = score(synthetic_turn(10.0, 0.3, 60, noise=1.5, seed=10), 10.0, 2.5, 60)
    check("noisy turn still scored", not r["miss"] and abs(r["error"]) < 6, f"error {r['error']:.1f}")
    print("\nall passed" if failures == 0 else f"\n{failures} FAILED")
    return failures


def main(argv):
    if "--selftest" in argv:
        sys.exit(1 if selftest() else 0)
    if not argv:
        print(__doc__)
        sys.exit(2)
    system = "--system" in argv
    argv = [a for a in argv if a != "--system"]
    root = Path(argv[0])
    folders = [root] if (root / "meta.json").exists() else sorted(p for p in root.iterdir() if (p / "meta.json").exists())
    if system:
        reports = [system_report(f) for f in folders]
        for r in reports:
            print(json.dumps(r))
        for o in overhead(reports):
            print(json.dumps(o))
        out = (root if not (root / "meta.json").exists() else root.parent) / "system_report.json"
        out.write_text(json.dumps(dict(sessions=reports, overhead_vs_idle=overhead(reports)), indent=2))
        return
    for f in folders:
        print(json.dumps(analyse_session(f)))


if __name__ == "__main__":
    main(sys.argv[1:])
