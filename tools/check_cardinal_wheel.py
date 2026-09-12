#!/usr/bin/env python3
"""Enforce the canonical cardinal→PSX-12-bit wheel in `Unit._CARDINAL_TO_12BIT`.

THE RULE. Combat units (facing_angle == -1) derive their pose-octant RENDER
angle from `Unit._CARDINAL_TO_12BIT[facing_direction]`. That table MUST be the
chapel-calibrated wheel documented at `ScenarioPlayerScene`'s spawn seed
(0x000=E, 0x400=S, 0x800=W, 0xC00=N), so a combat unit renders the SAME
world-locked cardinal+mirror the events path renders for the same world
facing — at every camera yaw.

THE BUG THIS PINS. Combat originally fed the render an E/S-SWAPPED cardinal
table (E=0x400, S=0x000), so combat units facing EAST/SOUTH rendered the
perpendicular cardinal frame (a unit moving/attacking along an axis showed the
wrong walk/attack frames). Fix (2026-06-30 harmonization): un-swap
`_CARDINAL_TO_12BIT` and its inverse `AnimationStateController.angle_12bit_to_facing`
onto the single canonical wheel.

WHY STATIC. This guard replaced `tests/CombatFacingAngleTest.gd` (test-audit
loop #81, DEMOTE logic→static-guard): that test's only live assertion was
`Unit._CARDINAL_TO_12BIT == canonical` — a constant-table spelling check; its
second arm called `get_pose_octant` on both sides with the same input once the
first arm passed, i.e. it could not fail on anything the first arm did not
already catch. The table is data, so a `tools/check_*.py` in the pre-flight
guards it at ~0 cost and the 2.3 s Godot process disappears.

Exit 0 if the table is the canonical wheel, 1 otherwise (including the table
being missing or no longer parseable — a reformat must red, never silently
pass). Pure stdlib.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
UNIT_GD = PROJECT_DIR / "src" / "units" / "Unit.gd"

# The canonical wheel, in _CARDINAL_TO_12BIT's order: NORTH, EAST, SOUTH, WEST.
CANONICAL = [0xC00, 0x000, 0x400, 0x800]

TABLE = re.compile(r"^const _CARDINAL_TO_12BIT := \[([^\]]+)\]", re.MULTILINE)


def main() -> int:
	text = UNIT_GD.read_text(encoding="utf-8")
	match = TABLE.search(text)
	if match is None:
		print("ABORT: Unit._CARDINAL_TO_12BIT not found in %s — reformat or rename "
			  "broke the guard; restore the const or update this tool." % UNIT_GD.name)
		return 1

	entries = [tok.strip() for tok in match.group(1).split(",")]
	if len(entries) != 4:
		print("ABORT: Unit._CARDINAL_TO_12BIT has %d entries, want 4 "
			  "(NORTH, EAST, SOUTH, WEST): [%s]" % (len(entries), match.group(1)))
		return 1

	try:
		got = [int(tok, 0) for tok in entries]
	except ValueError as e:
		print("ABORT: Unit._CARDINAL_TO_12BIT entry is not a literal int: %s (%s)"
			  % (match.group(1), e))
		return 1

	if got != CANONICAL:
		want = ", ".join("0x%03X" % v for v in CANONICAL)
		have = ", ".join("0x%03X" % v for v in got)
		print("ABORT: Unit._CARDINAL_TO_12BIT is not the canonical chapel-calibrated "
			  "wheel: got [%s] (N,E,S,W), want [%s]. E/S swapped again — combat units "
			  "facing EAST/SOUTH will render the perpendicular cardinal frame."
			  % (have, want))
		return 1

	print("OK: Unit._CARDINAL_TO_12BIT is the canonical cardinal→12-bit wheel")
	return 0


if __name__ == "__main__":
	sys.exit(main())
