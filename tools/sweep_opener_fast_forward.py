#!/usr/bin/env python3
"""The 72-opener fast-forward sweep — ADR-0264's load-bearing measurement.

    uv run python tools/sweep_opener_fast_forward.py            # all 72 battle groups
    uv run python tools/sweep_opener_fast_forward.py --jobs 3
    uv run python tools/sweep_opener_fast_forward.py --roots 9 15 3

WHY THIS EXISTS. "Play battle N" is a seek into the navigator, and a seek settles
the battle world by REPLAYING the group's opener at 30x
(`NavigatorMain._settle_world_via_opener`). That fast-forward is bounded by
`ScenarioPathApplier._MAX_FF_FRAMES = 2100` host frames, and until this sweep ran
the bound had never been exercised across the range it now carries: 72 openers of
24-679 instructions, mean 144. A truncated fast-forward does not raise anything on
its own — it leaves the world on whichever `{19}` it reached, which is an authored
camera pose, just not the one the battle opens on. That is the exact defect
ADR-0264 is about, wearing the costume of a working battle.

HOW IT MEASURES. One Godot process per battle group, launched the way a player
launches one (`-- --battle=N`), reading the `[opener-ff]` line the seek prints:

    [opener-ff] scn=10 outcome=ended frames=1123 cap=2100

`outcome=ended` is the only settled result; `capped` means the cap ran out and
`stalled` means the opener parked with no PC progress (a combat barrier a seek
never fights). One process per group rather than one process looping 72 times, so
a crash at group 40 costs group 40 and not the sweep, and so no group inherits the
world another one left behind.

OUTPUT. A TSV on stdout and, with `--out`, on disk:

    root  opener_scn  instructions  outcome  frames  cap  margin_frames

Pure stdlib apart from the Godot binary. Run from the package root.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import pathlib
import re
import subprocess
import sys
import threading

ROOT = pathlib.Path(__file__).resolve().parent.parent
GRAPH = ROOT / "assets" / "scenarios" / "transition_graph.json"
CHUNKS = ROOT / "assets" / "scenarios" / "chunks"
NAV_SCENE = "res://assets/scenes/NavigatorMain.tscn"

# `[opener-ff] scn=10 outcome=ended frames=1123 cap=2100`
FF_RE = re.compile(
    r"\[opener-ff\]\s+scn=(?P<scn>\d+)\s+outcome=(?P<outcome>\w+)"
    r"\s+frames=(?P<frames>\d+)\s+cap=(?P<cap>\d+)"
)
# The seek prints which opener it is about to replay, so a group that never got
# that far is distinguishable from one whose fast-forward failed.
START_RE = re.compile(r"fast-forwarding opener scn (?P<scn>\d+)")

# Real seconds per group before the launch is abandoned. Generous: the walk boots a
# map, spawns an ENTD cast and replays a cinematic, and a loaded box does all three
# slower. A group that trips this is reported as `timeout`, never as settled.
DEFAULT_TIMEOUT_S = 240
# `--quit-after` is DebugConfig's own unscaled-real-time auto-quit — the backstop for a
# walk that never reports. The watchdog below is the one that governs; this only has to
# be longer than it.
DEFAULT_QUIT_AFTER_S = 300
# Real time, because that is what the shipping game runs at — but the frame count does
# NOT depend on it, and that is worth stating because the obvious worry is that it does.
# `_MAX_FF_FRAMES` counts HOST FRAMES, so a sweep run under `Engine.time_scale` would
# report a margin the game never has IF the fast-play advanced by delta. It does not: it
# advances `rewind_speed` (30) scenario ticks per host frame regardless of how long the
# frame took. MEASURED, same two groups, both ways — root 9 read 16 frames at 20x and 17
# at 1x; root 291 read 156 and 170. Leave it at 1 anyway: nothing is bought by scaling it.
DEFAULT_TIME_SCALE = 1


def battle_roots() -> list[int]:
    """Every battle group root, ascending — the sweep's population."""
    nodes = json.loads(GRAPH.read_text())["nodes"]
    return sorted(int(k) for k, v in nodes.items() if v.get("kind") == "battle")


def opener_for(root: int) -> int:
    """The opener member's scenario id for a battle group, or -1.

    Mirrors `GameNavigator._battle_beats`: the opener is the target of the group
    root's `BC` edge whose reason names the Var509 latch, NOT a role written in
    `scenario_groups.json` (whose battle members are all plain `member`).
    """
    node = json.loads(GRAPH.read_text())["nodes"].get(str(root), {})
    for e in node.get("edges", []):
        if str(e.get("via", "")) == "BC" and "509" in str(e.get("why", "")):
            return int(e.get("target", -1))
    return -1


def instruction_count(scn: int) -> int:
    """How many opcodes that opener carries — the size the cap is bounding."""
    path = CHUNKS / f"scenario_{scn:03d}_chunk.json"
    if not path.exists():
        return -1
    return len(json.loads(path.read_text()).get("instructions", []))


def run_one(root: int, godot: str, timeout_s: int, quit_after_s: int,
            time_scale: int, log_dir: pathlib.Path | None) -> dict:
    """Launch one battle, read its `[opener-ff]` line back, and stop it there.

    The launch is STREAMED and killed the moment it reports, rather than left to run
    out `--quit-after`: the report lands ~15-25 s in and the auto-quit is only the
    backstop for a walk that never gets there. Waiting it out anyway would have made
    the sweep four times its length for no extra evidence. A watchdog kills a launch
    that produces nothing at all, so a hung group costs `timeout_s` and not the sweep.
    """
    cmd = [
        godot, "--path", str(ROOT), NAV_SCENE, "--",
        f"--battle={root}",
        f"--time-scale={time_scale}",
        f"--quit-after={quit_after_s}",
    ]
    row = {"root": root, "outcome": "no-report", "frames": -1, "cap": -1, "scn": -1}
    captured: list[str] = []
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, bufsize=1)
    watchdog = threading.Timer(timeout_s, proc.kill)
    watchdog.start()
    timed_out = False
    try:
        assert proc.stdout is not None
        for line in proc.stdout:
            captured.append(line)
            match = FF_RE.search(line)
            if match:
                row["scn"] = int(match["scn"])
                row["outcome"] = match["outcome"]
                row["frames"] = int(match["frames"])
                row["cap"] = int(match["cap"])
                break
    finally:
        timed_out = not watchdog.is_alive()
        watchdog.cancel()
        proc.kill()
        proc.wait()
    out = "".join(captured)
    if log_dir is not None:
        (log_dir / f"battle_{root}.log").write_text(out)
    if row["outcome"] == "no-report":
        if timed_out:
            row["outcome"] = "timeout"
        elif not START_RE.search(out):
            # Told apart on purpose: `no-opener-replay` means the seek never reached
            # the fast-forward (no opener beat, or the walk died before it), which is a
            # different finding from a fast-forward that ran and did not settle.
            row["outcome"] = "no-opener-replay"
    return row


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", default="godot", help="Godot 4.8 fork binary (default: godot)")
    ap.add_argument("--roots", type=int, nargs="*", help="sweep only these group roots")
    ap.add_argument("--jobs", type=int, default=3,
                    help="concurrent Godot processes (default 3; each holds a Vulkan device)")
    ap.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_S)
    ap.add_argument("--quit-after", type=int, default=DEFAULT_QUIT_AFTER_S)
    ap.add_argument("--time-scale", type=int, default=DEFAULT_TIME_SCALE)
    ap.add_argument("--out", type=pathlib.Path, help="write the TSV here as well as stdout")
    ap.add_argument("--log-dir", type=pathlib.Path, help="keep each launch's full stdout here")
    args = ap.parse_args()

    roots = args.roots if args.roots else battle_roots()
    if args.log_dir:
        args.log_dir.mkdir(parents=True, exist_ok=True)

    print(f"# sweeping {len(roots)} battle openers, {args.jobs} at a time", file=sys.stderr)
    rows: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {
            pool.submit(run_one, r, args.godot, args.timeout, args.quit_after,
                        args.time_scale, args.log_dir): r
            for r in roots
        }
        for fut in concurrent.futures.as_completed(futures):
            row = fut.result()
            rows.append(row)
            print(f"#   root {row['root']:>4}  {row['outcome']:<18} frames={row['frames']}",
                  file=sys.stderr)

    rows.sort(key=lambda r: r["root"])
    lines = ["\t".join(("root", "opener_scn", "instructions", "outcome",
                        "frames", "cap", "margin_frames"))]
    for row in rows:
        scn = row["scn"] if row["scn"] > 0 else opener_for(row["root"])
        cap = row["cap"] if row["cap"] > 0 else -1
        margin = cap - row["frames"] if cap > 0 and row["frames"] >= 0 else -1
        lines.append("\t".join(str(x) for x in (
            row["root"], scn, instruction_count(scn) if scn > 0 else -1,
            row["outcome"], row["frames"], cap, margin)))
    text = "\n".join(lines) + "\n"
    print(text, end="")
    if args.out:
        args.out.write_text(text)

    settled = [r for r in rows if r["outcome"] == "ended"]
    worst = max((r["frames"] for r in settled), default=-1)
    print(f"# {len(settled)}/{len(rows)} openers reached Event End; "
          f"worst settled fast-forward = {worst} frames", file=sys.stderr)
    # A group that did not settle is the finding this sweep exists to surface, so it
    # is the exit code too — a green sweep has to mean all 72.
    return 0 if len(settled) == len(rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
