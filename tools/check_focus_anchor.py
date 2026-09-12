#!/usr/bin/env python3
"""ADR-0119's MANDATORY CODE ANCHOR for focus, built at last by ADR-0177.

ADR-0119 shipped `focus` as a capability and then said the honest thing about it:

    Focus is a discipline, not a guarantee, and this is the honest weakness: one
    system polling the device directly breaks the invariant for everyone,
    silently. That is exactly the platform-tier case in CONTEXT.md — "violations
    do not surface as test failures" — so the focus ADR carries a MANDATORY CODE
    ANCHOR.

That anchor is this file. `src/core/Focus.gd` governs REGISTERED roots and nothing
else, so a consumer that never registers hears everything however deep the stack is.
`tests/FocusStackTest.gd` arm 7 asserts that hole exists at runtime; this closes it
statically.

    python3 tools/check_focus_anchor.py          # guard
    python3 tools/check_focus_anchor.py --list   # print the current surface, for rebasing

WHY A RATCHET AND NOT A BAN

42 files carry an input surface today and 13 of them are effect-studio authoring
tools. Converting them is a schedule, not a decision (ADR-0177 dec. 4). So the
current set is GRANDFATHERED and the list can only SHRINK: a file that converts
comes off, and nothing may be added without editing this file deliberately.

TWO ARMS, because a one-armed ratchet is not one (a listed entry must keep being
checked against the FILE, never against the list's own existence):

  1. GREW   — a file has an input surface and is neither registered nor listed.
  2. STALE  — a listed file no longer has an input surface, or has converted. Its
              entry must go, or the list stops meaning anything and the ratchet
              silently stops turning.

CALLBACKS AND POLLS ARE NOT THE SAME DEBT

A CALLBACK consumer is discharged by registering: Focus deafens it structurally and
Godot stops calling it. A POLL is not — `set_process_*input(false)` stops the engine
calling you, it cannot stop you asking `Input.is_action_pressed()` in `_process`. So a
poller that registers is STILL reading the device on frames it does not hold focus, and
it stays listed until the poll itself is gone. That asymmetry is the mechanism's real
limit and this guard is the only thing that records it.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WALK = ("src", "addons")

# A device-input surface: an engine input callback, or a poll of the Input singleton.
# `_gui_input` is deliberately absent — it is Control's own path, Focus does not gate it
# (ADR-0177 dec. 2), and a LineEdit in an F3 panel must keep working regardless of focus.
CALLBACK = re.compile(
    r"func\s+_(?:unhandled_input|unhandled_key_input|shortcut_input|input)\s*\("
)
# A POLL is a different problem and registering does NOT fix it. `set_process_*input(false)`
# stops Godot CALLING you; it cannot stop you asking. A poller that registers with Focus is
# still reading the device on a frame it does not hold focus, so it must stay listed until
# the poll itself is gone. Found by converting WorldMapScene, whose `held_direction()` polls
# `Input` and whose `_input_enabled` boolean existed for exactly this reason.
POLL = re.compile(r"\bInput\.(?:is_action|is_key|is_mouse|get_vector|get_axis)")
# A file that puts itself under the switch is exempt: it is a participant, not a stowaway.
REGISTERS = re.compile(r"\bFocus\.(?:push|register)\s*\(")

# --- the grandfathered surface (ADR-0177 dec. 4). SHRINK ONLY. -----------------------
# Every entry is a file that reads the device without registering with Focus. Take one
# off when it converts; do not add one without a decision. Sorted, one per line, so the
# diff of a conversion is one deleted line.
GRANDFATHERED = {
    "src/audio/SfxStressTest.gd",
    "src/debug/DebugDashboard.gd",
    "src/debug/DebugOverlay.gd",
    "src/debug/FuncTracerDumper.gd",
    "src/debug/UI3OwnerMapPicker.gd",
    "src/effects/studio/EffectStudioPage.gd",
    "src/effects/studio/FramesetCanvas.gd",
    "src/scenarios/ScenarioPlayerScene.gd",
    "src/scenarios/ScenarioVM.gd",  # poll gone; still an unregistered CALLBACK consumer
    "src/scenes/DepthDebugScene.gd",
    "src/scenes/GPUArena.gd",
    "src/scenes/OpeningMenu.gd",
    "src/scenes/PlayerCamera.gd",  # poll gone; still an unregistered CALLBACK consumer
    "src/scenes/ProjectileTester.gd",  # poll gone; still an unregistered CALLBACK consumer
    "src/scenes/RangeTileAtlasViewer.gd",
    "src/scenes/TileCursor.gd",  # poll gone; still an unregistered CALLBACK consumer
    "src/scenes/UnitInfoWindowViewer.gd",
    "src/ui3/FieldInspectController.gd",
    "src/ui3/UICombatManager.gd",
    "src/ui3/UIGambitEditor.gd",
    "src/ui3/UILearnPanel.gd",
    "src/ui3/UIListModalWindow.gd",
    "src/ui3/components/UIScrollableList.gd",
    "src/ui3/detail/StartActionMenuBoot.gd",
    "src/ui3/formation/FormationDetailTransition.gd",
    "src/ui3/formation/FormationMapHost.gd",
    "src/ui3/formation/FormationScene.gd",
}
# ------------------------------------------------------------------------------------


def strip_comments(text):
    """Drop `#` comments, keeping the code. A guard that scans raw text scores PROSE.

    Found the hard way: converting `TileCursor` left the sentence "the two
    `Input.is_action_pressed` re-derivations that stood here are gone" in a comment, and this
    file went on reporting the file as a poller — the guard reading the very sentence that
    says the poll was removed. Every conversion commit writes that phrase naturally, so this
    is not a one-off.

    Quote-aware, because `#` is legal inside a string. Line-based, so a `#` inside a GDScript
    multi-line string would still be cut; there are none in this tree and a false NEGATIVE
    there would need the removed text to also contain a real device read.
    """
    out = []
    for line in text.split("\n"):
        quote = ""
        cut = len(line)
        i = 0
        while i < len(line):
            ch = line[i]
            if quote:
                if ch == "\\":
                    i += 2
                    continue
                if ch == quote:
                    quote = ""
            elif ch in ("'", '"'):
                quote = ch
            elif ch == "#":
                cut = i
                break
            i += 1
        out.append(line[:cut])
    return "\n".join(out)


def surface_files():
    out = []
    for top in WALK:
        base = ROOT / top
        if not base.is_dir():
            continue
        for p in sorted(base.rglob("*.gd")):
            rel = p.relative_to(ROOT).as_posix()
            try:
                text = strip_comments(p.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError):
                continue
            cb = bool(CALLBACK.search(text))
            poll = bool(POLL.search(text))
            if cb or poll:
                out.append((rel, bool(REGISTERS.search(text)), poll))
    return out


def main() -> int:
    found = surface_files()
    if "--list" in sys.argv:
        for rel, registered, poll in found:
            print("%-62s %-14s %s" % (rel, "REGISTERED" if registered else "grandfathered",
                                      "POLLS" if poll else ""))
        print("\n%d files with a device-input surface, %d registered, %d polling"
              % (len(found), sum(1 for _, r, _ in found if r),
                 sum(1 for _, _, p in found if p)))
        return 0

    have = {rel for rel, _, _ in found}
    # A poll is never discharged by registering — see the module docstring.
    unregistered = {rel for rel, reg, poll in found if poll or not reg}

    polls = {rel for rel, _r, p in found if p}
    grew = sorted(unregistered - GRANDFATHERED)
    # STALE has two causes and they are different mistakes, so name them apart.
    gone = sorted(GRANDFATHERED - have)
    converted = sorted(GRANDFATHERED & (have - unregistered))
    polls = {rel for rel, _, poll in found if poll}

    fail = []
    for rel in grew:
        if rel in polls:
            fail.append("POLLS — %s polls the Input singleton and is not grandfathered. "
                        "Registering with Focus does NOT discharge a poll: the switch stops "
                        "Godot CALLING you, not you ASKING. Remove the poll, or list it." % rel)
        else:
            fail.append("GREW  — %s reads the device and neither registers with Focus nor is "
                        "grandfathered. Register it (ADR-0177), or add it here deliberately." % rel)
    for rel in gone:
        fail.append("STALE — %s is grandfathered but has no input surface any more. "
                    "Delete its entry; the ratchet only counts if the list shrinks." % rel)
    for rel in converted:
        fail.append("STALE — %s now registers with Focus and does not poll. Delete its entry "
                    "— leaving it listed would exempt it from arm 1 forever." % rel)

    if fail:
        print("check_focus_anchor: RED — %d problem(s)" % len(fail))
        for f in fail:
            print("  " + f)
        print("\nADR-0119's Consequences: \"one system polling the device directly breaks "
              "the invariant for everyone, silently.\"")
        return 1

    print("check_focus_anchor: OK — %d file(s) with a device-input surface; "
          "%d discharged by registering, %d grandfathered (shrink-only), of which %d POLL "
          "and cannot be discharged by registering at all"
          % (len(found), len(have) - len(unregistered), len(GRANDFATHERED),
             len(GRANDFATHERED & polls)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
