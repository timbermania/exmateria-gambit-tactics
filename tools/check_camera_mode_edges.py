#!/usr/bin/env python3
"""Guard: `PlayerCamera.camera_mode` is never ASSIGNED from outside the rig.

    uv run python tools/check_camera_mode_edges.py          # guard
    uv run python tools/check_camera_mode_edges.py --list   # print what it scanned

THE RULE. Only `addons/exmateria_battlefield/camera/PlayerCamera.gd` may write
`camera_mode`. Everyone else asks the rig for the EDGE it wants — `request_takeover` /
`release_takeover` for a driver that owns the pose, or `enter_takeover_framing` /
`resume_cursor_framing` for the by-fiat flips the navigator does.

WHY THIS IS A GUARD AND NOT A CONVENTION. `camera_mode` is a plain property with a setter
that only emits a signal, so an assignment compiles, runs, flips the mode, and skips every
piece of framing work the edge owns. That is not hypothetical — it shipped at BOTH of the
navigator's sites and produced two separate reported defects:

  * `NavigatorMain._return_camera()` assigned `TAKEOVER` on the victory beat.
    `_apply_vertical_datum` targets 0 in TAKEOVER and re-plants every frame in every mode,
    so `camera.position.y` fell 1.383 → 0.000 in ONE frame — 40 of 240 native px, 16.7 %
    of the view height at ortho 8.30. Scenario 12's next authored `{19}` is 120 ticks
    (1.49 s) later, so the jump played bare on the live battlefield. This was the user's
    "the camera teleports to some position at the end".

  * `NavigatorMain._enter_command_cursor()` assigned `CURSOR` at battle entry. Besides the
    mirrored datum step, it skipped the rotation-target sync, so the whole battle ran with
    the rig holding `yaw=135.0` while `y_target_rot=-45.0` and `rotation_settled=true` —
    the targets a flat lie, and the first Q/E stepping from a yaw nobody was looking at.

Both are the SAME defect: an assignment bypassed an edge the rig owns. Two sites, found
months apart, neither one visible in review. The fix deliberately did NOT move the work
into the `camera_mode` setter (a property setter that moves the body is a worse surprise,
and it would put a body-moving side effect under four takeover drivers that have no such
defect), which leaves the bypass structurally possible. This guard is what closes it.

NOT A RATCHET — a BAN. There is no grandfathered list, because after the fix the violating
set is EMPTY. If you are here because this went red, the answer is a named edge method on
`PlayerCamera`, not an entry in a list.

COMMENTS AND STRINGS ARE STRIPPED FIRST, deliberately. `NavigatorMain` and this repo's
tests both spell `camera_mode = ...` inside prose and inside `print()` payloads, and a
guard that matched those would be red on arrival and would have to be neutered to land —
the exact failure mode where a check's own text keeps it green (or red) independent of the
code it is supposed to be reading.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WALK = ("src", "addons", "tests")

# The rig itself — the one file allowed to write the property.
OWNER = "addons/exmateria_battlefield/camera/PlayerCamera.gd"

# `camera_mode` on the left of a single `=`. Excludes `==`, `!=`, `<=`, `>=` by requiring
# the next character not to be `=`, and excludes `:=` / `+=` by anchoring on whitespace or
# a dot-access chain immediately before the `=`.
ASSIGN = re.compile(r"(^|[^=!<>+\-*/%])\bcamera_mode\s*=(?!=)")

# A `#` comment, and single/double-quoted string bodies. Applied per line, in this order.
STRING = re.compile(r"'[^']*'|\"[^\"]*\"")


def strip_noise(line: str) -> str:
    """Blank out string literals, then everything from the first surviving `#`.

    Strings go first so a `#` inside a quoted payload cannot truncate the line early, and
    so a `camera_mode =` inside a `print()` format string is invisible to the matcher.
    """
    line = STRING.sub('""', line)
    hash_at = line.find("#")
    return line if hash_at < 0 else line[:hash_at]


def scan() -> tuple[list[str], int]:
    violations: list[str] = []
    scanned = 0
    for top in WALK:
        base = ROOT / top
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.gd")):
            rel = path.relative_to(ROOT).as_posix()
            if rel == OWNER:
                continue
            scanned += 1
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            if "camera_mode" not in text:
                continue
            for n, line in enumerate(text.splitlines(), 1):
                if ASSIGN.search(strip_noise(line)):
                    violations.append("%s:%d: %s" % (rel, n, line.strip()))
    return violations, scanned


def main() -> int:
    violations, scanned = scan()
    if "--list" in sys.argv:
        print("scanned %d .gd file(s) under %s, owner exempt: %s"
              % (scanned, "/".join(WALK), OWNER))
    if violations:
        print("FAIL: camera_mode assigned outside the rig (%d site(s)):" % len(violations))
        for v in violations:
            print("  " + v)
        print()
        print("Ask PlayerCamera for the edge instead:")
        print("  request_takeover(driver) / release_takeover()  — a driver that owns the pose")
        print("  enter_takeover_framing() / resume_cursor_framing()  — a by-fiat flip")
        print("An assignment flips the mode and skips the framing work the edge owns.")
        return 1
    print("OK: camera_mode is written only by %s (%d other .gd file(s) scanned)"
          % (OWNER, scanned))
    return 0


if __name__ == "__main__":
    sys.exit(main())
