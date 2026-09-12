#!/usr/bin/env python3
"""Pre-flight the world map's generated asset hub before any scene loads it.

`assets/world_map/` is not in git. It is written by `tools/parse_world_map.py`
from the disc, it is **shared between every worktree** (each one symlinks the
path to a single physical directory), and it is gitignored — so nothing in a
normal checkout, diff or `git status` says anything about its state. That
combination has now cost three sessions in a row the same wrong diagnosis, in
two different shapes:

  * **Stale.** A hub generated before `parse_world_map.py` grew `start_menu`,
    `place_list`, `town` and `routes[].waypoints` still loads, still parses, and
    still renders the parts that predate those keys. Ten tests go red, and they
    go red in ten unrelated-looking ways — `WorldMapPrimitives.gd` reads
    `routes[r]["polyline"]` and works while `WorldMapTravel.gd:155` reads
    `routes[r]["waypoints"]` on the same dict and throws. Two readers of one
    stale dict disagreeing looks exactly like two branches disagreeing.
  * **Missing.** `main` used to track `godot-learning/assets/world_map` as a
    symlink (PR #657 untracked it). Merging that removal DELETES the symlink in
    a worktree that still has it, and every world-map scene then dies on the
    missing path until the linker is re-run.

Both are one-line facts about a directory, and both were being read off ten
failing Godot scenes instead. This guard states them once, before the suite.

WHY NOT AN MTIME CHECK. "Is the artifact older than its generator?" is the
check that would have closed the original incident in one command, and it is
*wrong as a gate*: `git worktree add` stamps the checkout time on
`tools/parse_world_map.py`, so a worktree created after a perfectly fresh
regeneration would abort on a hub that is completely correct. The staleness
that actually matters is a SHAPE — the keys the readers name — and shape is
worktree-independent. That is what arms 4 and 5 assert.

The required-key set is the set the readers actually index, as of 2026-08-28:

    routes, layout, nodes, frames, cels, background_grid   WorldMapAssets.gd,
                                                           WorldMapPrimitives.gd,
                                                           WorldMapTravel.gd
    place_list                                             WorldMapPlaceList.gd:98
    start_menu                                             WorldMapStartMenu.gd:153
    town                                                   WorldMapTownPage.gd:251
    routes[].waypoints                                     WorldMapTravel.gd:155

`events.json` is Campaign's node-script table (`Campaign.gd:22`) and is written
by the same generator run; the 08-23 hub had never written it at all.

Exit 0 if the hub is present and well-shaped, 1 otherwise. Pure stdlib.
Pass `--assets-dir DIR` to point it at a fixture instead of the real hub — that
is how each arm above is seed-proven without writing into the shared directory.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT_DIR = HERE.parent

# The nine top-level keys the world-map readers index. See the module docstring
# for the reader behind each one.
REQUIRED_MODEL_KEYS = [
    "background_grid",
    "cels",
    "frames",
    "layout",
    "nodes",
    "place_list",
    "routes",
    "start_menu",
    "town",
]

REMEDY = (
    "\n  If assets/world_map is MISSING: the symlink was deleted by a merge that\n"
    "  brought in PR #657 (it untracked the path). Restore it with\n"
    "      bash tools/link_worktree_godot_assets.sh\n"
    "\n  If it is present but INCOMPLETE: the hub is stale. Regenerate it with\n"
    "      uv run python tools/parse_world_map.py   (from the package root)\n"
    "  That directory is SHARED by every worktree — check `pgrep -c godot` is 0\n"
    "  first, because the write moves every worktree's results at once.\n"
)


def vram_dims():
    """VRAM_W / VRAM_H from WorldMapAssets.gd, so the guard cannot drift off it."""
    src = (PROJECT_DIR / "src/world_map/WorldMapAssets.gd").read_text()
    w = re.search(r"const VRAM_W := (\d+)", src)
    h = re.search(r"const VRAM_H := (\d+)", src)
    if not w or not h:
        return None, None
    return int(w.group(1)), int(h.group(1))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--assets-dir",
        default=str(PROJECT_DIR / "assets/world_map"),
        help="the hub to check (default: this checkout's assets/world_map)",
    )
    args = ap.parse_args()
    hub = Path(args.assets_dir)
    problems = []

    # Arm 1 — the directory resolves at all. A dangling symlink fails `is_dir()`
    # exactly like an absent path, which is the state a merge of #657 leaves.
    if not hub.is_dir():
        what = "a dangling symlink" if hub.is_symlink() else "absent"
        print(f"world-map asset guard FAILED: {hub} is {what}.")
        print(REMEDY)
        return 1

    # Arm 2 — the three generated files exist.
    model_p, events_p, vram_p = hub / "model.json", hub / "events.json", hub / "vram.bin"
    for p in (model_p, events_p, vram_p):
        if not p.is_file():
            problems.append(f"{p.name} is missing")

    # Arm 3 — vram.bin is exactly one PSX VRAM frame of halfwords. WorldMapAssets
    # checks this at load; hoisting it here names the cause before ten scenes do.
    vw, vh = vram_dims()
    if vw is None:
        problems.append("could not read VRAM_W/VRAM_H out of WorldMapAssets.gd")
    elif vram_p.is_file():
        want = vw * vh * 2
        got = os.path.getsize(vram_p)
        if got != want:
            problems.append(f"vram.bin is {got} bytes, expected {want} ({vw}x{vh} u16)")

    # Arms 4 + 5 — model.json parses, and holds every key a reader indexes,
    # including the per-route `waypoints` whose absence throws at
    # WorldMapTravel.gd:155 while `polyline` beside it keeps working.
    if model_p.is_file():
        try:
            model = json.loads(model_p.read_text())
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            model = None
            problems.append(f"model.json did not parse: {exc}")
        if isinstance(model, dict):
            missing = [k for k in REQUIRED_MODEL_KEYS if k not in model]
            if missing:
                problems.append("model.json has no " + ", ".join(f"`{k}`" for k in missing))
            routes = model.get("routes")
            if isinstance(routes, list):
                if not routes:
                    problems.append("model.json `routes` is empty")
                else:
                    no_wp = [i for i, r in enumerate(routes)
                             if not isinstance(r, dict) or "waypoints" not in r]
                    if no_wp:
                        problems.append(
                            f"{len(no_wp)} of {len(routes)} routes have no `waypoints` "
                            f"(first: index {no_wp[0]})"
                        )
        elif model is not None:
            problems.append("model.json did not parse as an object")

    # Arm 6 — events.json is Campaign's table, and an empty one is as useless as
    # an absent one (the 08-23 hub simply never wrote the file).
    if events_p.is_file():
        try:
            events = json.loads(events_p.read_text())
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            problems.append(f"events.json did not parse: {exc}")
        else:
            if not isinstance(events, dict):
                problems.append("events.json did not parse as an object")
            elif not events:
                problems.append("events.json is an empty object")

    if problems:
        print("world-map asset guard FAILED:")
        for p in problems:
            print(f"  - {p}")
        print(REMEDY)
        return 1

    print(
        f"world-map asset guard OK: {hub} holds model.json "
        f"(all {len(REQUIRED_MODEL_KEYS)} reader keys, waypoints on every route), "
        f"events.json and a {vw}x{vh} vram.bin."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
