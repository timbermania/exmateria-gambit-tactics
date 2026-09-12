#!/usr/bin/env python3
"""Stop the PSX magnitude-conversion duplication from regrowing (ADR-0091).

The PSX→game unit conversion is proven and lives in ONE home: `PsxMagnitude`
(continuous magnitude↔game) plus its `CameraCalibration` render layer, mirroring
`tools/parse_effect.py` on the Python side. The disease this guard treats is
DUPLICATION — the same conversion re-derived inline in a new file, which is
exactly how the junk regrew during the effect-studio authoring work.

So this net does NOT ban the bare number 4096 (it is a legitimate inertia
default, a zoom baseline, a facing-wheel modulus, a Q12 unit, an AABB size…).
It bans the CONVERSION IDIOMS — the re-derivation forms that only appear when
someone re-implements the mapping instead of calling the seam:

  * the unique effect divisors      14336 / 114688   (velocity / accel scale)
  * the tile divisor in arithmetic  `/ 28`           (world-units-per-tile)
  * the angle idioms                `TAU / 4096`, `4096 / 360`, `360 / 4096`
                                    and their reversed / *-forms
  * the fixed-point shift           `>> 12`
  * the inverted-Y emission reason  `-Y=UP`

Route the magnitude through PsxMagnitude (`tile_to_game` / `angle_to_rad` /
`radial_velocity_to_game` / `accel_to_game`, or the shared bases
`PsxMagnitude.FULL_TURN` / `UNITS_PER_TILE` in a const expression) — then the
literal disappears and this net stays green.

Scope: the effect / scenario-camera / projectile magnitude surface —
`src/effects`, `src/scenarios`, `src/projectiles`. (The Python parser mirror
`tools/parse_effect.py` is the ADR-0091 §5 accepted cross-language copy, kept
in lock-step by the PsxMagnitudeTest golden-value parity test, not by this text
net; other tools carry unrelated /28 and >>12 and are out of scope.)

Exemptions (ADR-0091 §4 / §6):
  * faithful-sim carve-outs — a per-file `# psx-faithful-sim: <reason>` header,
    and the whole `src/effects/callbacks/` directory (GTE fixed-point microcode
    where the >>12 / 4096 IS the algorithm, not a leaking game unit);
  * the homes themselves — PsxMagnitude.gd / PsxNum.gd / CameraCalibration.gd;
  * a genuine one-off — a per-line `# psx-units-exempt: <reason>` marker.

Scans every `.gd` under the scope dirs. Exit 0 if clean, 1 on any violation.
Pure stdlib.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
# ADR-0148 dec. 3: a guard's scan root is a WALK. `src` alone stops covering a file
# the moment the refactor extracts it, SILENTLY — see tools/_walk_roots.py.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402
SCAN_DIRS = [PROJECT_DIR / d for d in ("src/effects", "src/scenarios", "src/projectiles")] \
            + [r for r in walk_roots() if r.parent.name == "addons"]
FAITHFUL_HEADER = "psx-faithful-sim:"
LINE_EXEMPT = "psx-units-exempt:"
HOME_FILES = {"PsxMagnitude.gd", "PsxNum.gd", "CameraCalibration.gd"}
# The GTE fixed-point callback microcode is a faithful-sim carve-out wholesale.
EXEMPT_DIR_PARTS = ("callbacks",)

# Each pattern is (label, compiled regex). Whitespace around operators is optional.
BANNED = [
    ("velocity divisor 14336", re.compile(r"\b14336\b")),
    ("accel divisor 114688", re.compile(r"\b114688\b")),
    ("tile divisor `/ 28`", re.compile(r"/\s*28(?:\.0+)?\b")),
    ("angle idiom `TAU / 4096`", re.compile(r"\bTAU\s*/\s*4096")),
    ("angle idiom `/ 4096 * TAU`", re.compile(r"/\s*4096(?:\.0+)?\s*\*\s*TAU")),
    ("angle idiom `4096 / TAU`", re.compile(r"\b4096(?:\.0+)?\s*/\s*TAU")),
    ("angle idiom `/ TAU * 4096`", re.compile(r"/\s*TAU\s*\*\s*4096")),
    ("degree idiom `4096 / 360`", re.compile(r"\b4096(?:\.0+)?\s*/\s*360")),
    ("degree idiom `360 / 4096`", re.compile(r"\b360(?:\.0+)?\s*/\s*4096")),
    ("degree idiom `* 360 / 4096`", re.compile(r"\*\s*360(?:\.0+)?\s*/\s*4096")),
    ("degree idiom `/ 4096 * 360`", re.compile(r"/\s*4096(?:\.0+)?\s*\*\s*360")),
    ("fixed-point shift `>> 12`", re.compile(r">>\s*12\b")),
    ("inverted-Y emission reason `-Y=UP`", re.compile(r"-Y\s*=\s*UP")),
]


def _is_exempt_file(path: Path) -> bool:
    if path.name in HOME_FILES:
        return True
    if any(part in EXEMPT_DIR_PARTS for part in path.parts):
        return True
    # A per-file faithful-sim header anywhere in the first few lines.
    for line in path.read_text(encoding="utf-8").splitlines()[:5]:
        if FAITHFUL_HEADER in line:
            return True
    return False


def check_file(path: Path) -> list[str]:
    problems = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        code = line.split("#", 1)[0]  # strip line comment before matching
        if not code.strip():
            continue
        if LINE_EXEMPT in line:
            continue
        for label, rx in BANNED:
            if rx.search(code):
                problems.append(f"{lineno}: [{label}] {line.strip()}")
                break
    return problems


def main() -> int:
    violations = {}
    for sub in SCAN_DIRS:
        root = sub
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.gd")):
            if _is_exempt_file(path):
                continue
            problems = check_file(path)
            if problems:
                violations[path.relative_to(PROJECT_DIR)] = problems

    if violations:
        print("ADR-0091 raw-PSX-magnitude violations (re-derived conversion in src/):")
        for rel, problems in violations.items():
            for p in problems:
                print(f"  {rel}:{p}")
        print(
            "\nFix: route the magnitude through the PsxMagnitude seam "
            "(tile_to_game / angle_to_rad / radial_velocity_to_game / accel_to_game, "
            "or reference PsxMagnitude.FULL_TURN / UNITS_PER_TILE / CameraCalibration in a const). "
            "For faithful ROM per-frame arithmetic add a `# " + FAITHFUL_HEADER +
            " <reason>` file header; for a genuine one-off add a per-line `# " +
            LINE_EXEMPT + " <reason>`. See ADR-0091."
        )
        return 1

    print("OK: no re-derived PSX magnitude conversions in %s (ADR-0091)." % ", ".join(str(d.relative_to(PROJECT_DIR)) for d in SCAN_DIRS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
