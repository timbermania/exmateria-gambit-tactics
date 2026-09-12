#!/usr/bin/env python3
"""Enforce "every debug-panel field goes through the Tune system" (ADR-0068).

A debug panel is a VIEW onto tunable state. Every value-holding control it shows
should therefore be built through the `TuneField` factory and so declare its
persistence class — TUNABLE (cyan, Pin to keep), AUTOSAVE (green, sticks on every
edit), or EPHEMERAL (grey, declared session-only). A raw `SpinBox.new()` etc. in a
panel is a smell: a value control that is NONE of those, i.e. state nobody decided
how to treat. The whole point is to make "I forgot to route this" impossible to
tell apart from "I chose ephemeral" — so we force the choice through the one door.

This is the config analogue of check_no_env_vars.py / check_color_shaders.py: a
cheap text net. It scans every `.gd` under src/ that `extends BaseDebugPanel` and
flags raw instantiation of the five value-input widgets. Buttons and labels are
out of scope — they are actions/display, not fields. `TuneField.gd` itself (the
factory) is out of scope by construction (it is a RefCounted, not a panel).

A genuinely un-Tune-able control — a dropdown populated dynamically from a
database, a data-driven readout whose value is owned elsewhere — may opt out with
an explicit, greppable marker on the same line:
    var cb = CheckBox.new()  # tune-exempt: per-emitter, data-driven per effect
That escape hatch is a code-review call, not a routine convenience.

PANEL IDENTITY IS TWO THINGS, NOT ONE (ADR-0151). A panel is a file that
`extends BaseDebugPanel` OR a class some walked file mounts through
`DebugOverlay.register_panel`. The second half exists because the first stops
being true inside an extracted addon, and a guard that keys on a marker the
refactor retires goes green because it no longer looks.

REPORT MODE: while the existing panels are migrated field-by-field, this runs in
report mode — it prints the outstanding sites and exits 0 (never fails the build).
Flip ENFORCE to True once the tree is clean to make it a hard gate. Pure stdlib.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
# ADR-0147 / extraction #1: the scan root is `classify_blueprint.WALK_ROOTS`, not a
# hard-coded directory. A guard root that does not follow the refactor's output loses
# coverage SILENTLY — see tools/_walk_roots.py for the reproduction.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402
SCAN_DIRS = walk_roots()
PANEL_MARKER = re.compile(r"^\s*extends\s+BaseDebugPanel\b", re.MULTILINE)
CLASS_NAME = re.compile(r"^\s*class_name\s+(\w+)", re.MULTILINE)
# `var NAME ... = CLASS.new()` and `DebugOverlay.register_panel(NAME` — the two
# halves of "this class is mounted as a panel", read across the whole walk.
NEW_ASSIGN = re.compile(r"^\s*(?:var|@onready\s+var)\s+(\w+)[^=\n]*=\s*(\w+)\.new\s*\(", re.MULTILINE)
REGISTERED = re.compile(r"register_panel\(\s*(\w+)")
EXEMPT = "tune-exempt:"
BANNED = re.compile(r"\b(SpinBox|CheckBox|OptionButton|ColorPickerButton|LineEdit)\.new\s*\(")

# Flip to True once every debug panel routes its value controls through TuneField.
# Until then, report the outstanding sites without failing the suite.
ENFORCE = True


def registered_panel_classes() -> set[str]:
    """Class names some walked file mounts via `DebugOverlay.register_panel`.

    ADR-0151 retires `extends BaseDebugPanel` from inside an extracted addon:
    a system's panel is a plain `Control` satisfying the registration signature
    (ADR-0140 dec. 8). `PANEL_MARKER` alone would then stop seeing it, and this
    guard would go green because it no longer looks — the ADR-0148 defect, with
    a marker in the role of a scan root. The registration IS the identity, so it
    is read directly rather than replaced by a new convention nobody enforces.
    """
    out: set[str] = set()
    for path in sorted(p for d in SCAN_DIRS for p in d.rglob("*.gd")):
        text = path.read_text(encoding="utf-8", errors="replace")
        names = REGISTERED.findall(text)
        if not names:
            continue
        by_var = dict((v, c) for v, c in NEW_ASSIGN.findall(text))
        out.update(by_var[n] for n in names if n in by_var)
    return out


PANEL_CLASSES = registered_panel_classes()


def is_debug_panel(text: str) -> bool:
    if PANEL_MARKER.search(text):
        return True
    m = CLASS_NAME.search(text)
    return bool(m and m.group(1) in PANEL_CLASSES)


def check_file(text: str) -> list[str]:
    problems = []
    for lineno, line in enumerate(text.splitlines(), 1):
        code = line.split("#", 1)[0]  # strip line comment before matching
        if BANNED.search(code) and EXEMPT not in line:
            problems.append(f"{lineno}: {line.strip()}")
    return problems


def main() -> int:
    violations = {}
    for path in sorted(p for d in SCAN_DIRS for p in d.rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        if not is_debug_panel(text):
            continue
        problems = check_file(text)
        if problems:
            violations[path.relative_to(PROJECT_DIR)] = problems

    total = sum(len(v) for v in violations.values())

    if not violations:
        print("OK: every debug-panel value control is built through TuneField (ADR-0068).")
        return 0

    header = (
        "ADR-0068: debug-panel value controls NOT built through TuneField"
        if ENFORCE
        else "ADR-0068 REPORT (not enforced yet): debug-panel value controls to route through TuneField"
    )
    print(header + ":")
    for rel, problems in violations.items():
        print(f"  {rel}  ({len(problems)})")
        for p in problems:
            print(f"    {p}")
    print(
        f"\n{total} site(s) across {len(violations)} panel(s). Fix each by building the "
        "control via TuneField.add(parent, label, slug, default, hint, <persist>) — choose "
        "TUNABLE / AUTOSAVE / EPHEMERAL. A control that genuinely cannot be Tune-backed "
        f"(dynamic dropdown, data-driven readout) opts out with a `# {EXEMPT} <reason>` marker."
    )
    if ENFORCE:
        return 1
    print("[report mode] not failing the build — flip ENFORCE in this script once clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
