#!/usr/bin/env python3
"""Universal compositor-routing scoreboard (the non-opaque-prim burn-down).

The goal of the compositor effort is to route **every** non-opaque world prim
through the display-space compositor (which blends via RD
`RDPipelineColorBlendState`, not a gdshader flag) so the game can shed the
Mobile-renderer lock-in and move to Forward+. The renderer is nailed to Mobile
by exactly the in-scene materials that hardware-blend `blend_add`/`blend_sub`
into the base buffer and rely on Mobile's UNORM clamp for the PSX per-step
saturation. Drive that set to zero and Forward+ becomes viable.

This is the scoreboard for that effort. It **locates every non-opaque spatial
shader** (add / sub / mix) across `assets/shaders/` AND `src/` so none can hide
(the E065 Shiva callbacks were mis-composited precisely because their shader lived
outside the old assets-only scan), and it prints a full inventory. Enforcement is
scoped to the lock-in set:

  * `blend_add` / `blend_sub` — the per-step-clamp blockers. HARD-ENFORCED: each
    must be routed, exempt, or allowlisted (below).
  * `blend_mix` — alpha blend does NOT accumulate-saturate, so it is Forward+-safe
    regardless of the base-buffer format; the Mobile-UNORM lock-in this checker
    tracks simply does not apply. So mix shaders are INVENTORIED (located, per the
    "every non-opaque shader" ask) but not failed here. Their *compositor
    completeness* (Pass C's coverage-discard clobbers any non-opaque 3D prim not in
    the scratch — the actual Shiva failure mode) is enforced at RUNTIME by
    tests/CallbackFoldRoutingTest, which the static scan cannot substitute for.

An add/sub `.gdshader`/`.gdshaderinc` is compliant iff one of:
  1. it also declares `compositor_layer` in its render_mode — it folds through the
     compositor by definition (the engine-fold variants, e.g. effect_callback_fold), or
  2. it carries an explicit `// compositor-exempt: <kind> [<arg>] <reason>` marker whose
     KIND is one of EXEMPT_KINDS below — and, for the checkable kind, whose claim the
     guard has actually VERIFIED (see "Axis 1's exemptions are kinded" below), or
  3. it is named in ALLOWLIST below (the burn-down list of not-yet-routed prims).

The allowlist RATCHETS BOTH WAYS:
  - a NEW blend_add/blend_sub shader that is neither routed, exempt, nor listed
    FAILS (no silent regressions),
  - a STALE allowlist entry — one that no longer blends, or has since been
    routed / given an exempt marker — FAILS too, forcing its removal as each
    category lands. The allowlist shrinking to empty *is* the burn-down chart.
  - an entry the scan can never REACH (deleted, canvas_item, outside walk_roots)
    FAILS as well: it can never go stale, so it would otherwise sit on the list
    forever inflating the count with a prim nothing measures.

CLAMP_ARGUMENT_ALLOWLIST ratchets the same way, for exemptions resting on the one
argument the static scan cannot verify (see below).

Companion scoping: research/working_documents/COMPOSITOR_UNIVERSAL_ROUTING_SCOPING.md
Its own arms are seeded red by `tools/test_check_compositor_routing.py`, which the
pre-flight runs beside this file -- three shrink-only ratchets across two axes are
exactly the thing that can rot green, and this guard's whole argument is that a rule
nobody has watched fail is a comment.
Exit 0 if clean, 1 if any violation. Pure stdlib.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
# Scan production shaders wherever they live — NOT just assets/shaders. src/ui3/shaders
# holds the formation add/sub blends that the old assets-only scan never saw.
# ADR-0147 / extraction #1: the scan root is `classify_blueprint.WALK_ROOTS`, not a
# hard-coded directory. A guard root that does not follow the refactor's output loses
# coverage SILENTLY — see tools/_walk_roots.py for the reproduction.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402
SCAN_DIRS = walk_roots()

EXEMPT = "compositor-exempt:"

# --- Axis 1's exemptions are KINDED, and the checkable kind is CHECKED -----------------------
# This arm exists because the axis-2 work below found the hole and fixed it on ONE axis only.
#
# For most of this guard's life an exemption was accepted on `EXEMPT in text` — the marker's
# PRESENCE. The reason after the colon was free prose that nothing ever read. That is precisely
# how menu_cursor_shadow.gdshader carried, through a permanently green scoreboard, the reason
# "the glove sits ON TOP of already-composited opaque chrome ... it does NOT belong in the fold
# scratch" — which was simply FALSE (folding it took max |err| vs the ROM's `bg - CLUT` from 104
# to 4, half an RGB555 step). A reason nobody can check is not a guard; it is a comment.
#
# So the marker now leads with a KIND, and the kinds are the two arguments actually in use:
#
#   `// compositor-exempt: off-fork-fallback <twin.gdshader> — <prose>`
#       "the Forward+ path folds this prim; this in-scene file is only the stock/Mobile
#       fallback, so it is not a Forward+ lock-in blocker." VERIFIED: <twin> must exist in
#       the scan AND declare compositor_layer. The arg may be omitted when the twin is the
#       `<stem>_fold` sibling, which the guard then finds itself. This is the kind the glove's
#       false marker could not have satisfied: it named no twin, and claimed no fallback.
#
#   `// compositor-exempt: pre-clamped-single-layer — <prose>`
#       "a SINGLE additive/subtractive layer whose source is already clamped to [0,1], so the
#       final display clamp equals the PSX per-step clamp — no Mobile UNORM dependency."
#       (Cat C2/D in COMPOSITOR_UNIVERSAL_ROUTING_SCOPING.md.) This one is an ARGUMENT ABOUT
#       SATURATION and the static scan cannot verify it: "single layer" is a runtime fact about
#       what else is on screen. So it is not accepted on the strength of the prose either — it
#       is admitted ONLY for the names on CLAMP_ARGUMENT_ALLOWLIST, which RATCHETS: a new
#       shader cannot talk its way in, and an entry that stops being a marked in-scene add/sub
#       FAILS as stale. Being unable to check a claim is a reason to bound WHO may make it, not
#       a reason to wave it through.
#
# Any other first token — including the old free-prose markers, which began "Cat D screen tint",
# "OFF-FORK in-scene fallback ONLY", "routed through the compositor ...", "dead-unit fade" — is
# a violation that names the kinds. NOTE this is axis 1 only (saturation / Forward+ lock-in);
# the display-space axis below is independent and asks its own question separately.
_EXEMPT_TAG = re.compile(r"//\s*compositor-exempt:\s*(\S+)(?:[ \t]+(\S+))?")
OFF_FORK = "off-fork-fallback"
PRE_CLAMPED = "pre-clamped-single-layer"
EXEMPT_KINDS = (OFF_FORK, PRE_CLAMPED)

# The in-scene add/sub prims permitted to make the un-checkable clamp-equivalence argument.
# Every one is a single pre-clamped layer per COMPOSITOR_UNIVERSAL_ROUTING_SCOPING.md §C2/§D.
# It only shrinks: fold the prim (then it is `off-fork-fallback`, verified) and delete the line.
CLAMP_ARGUMENT_ALLOWLIST = {
    "screen_color_mode1.gdshader",     # §D CPU-folded full-screen additive tint
    "screen_color_mode2.gdshader",     # §D CPU-folded full-screen subtractive tint
    "screen_color_mode3.gdshader",     # §D as mode1, quarter-weighted
    "show_graphic.gdshader",           # §C2 full-screen additive title card
    "show_graphic_shadow.gdshader",    # §C2 its subtractive drop shadow
    "show_map_title.gdshader",         # §C2 full-screen additive title strip
    "show_map_title_shadow.gdshader",  # §C2 its subtractive drop shadow
    "unit_additive.gdshader",          # dead-unit additive fade ({43}); palette-clamped, decays to black
}

# --- Axis 2: COLOUR SPACE (added after the page-turn-icon / glove-cursor defect) -------------
# The axis above asks "does this depend on Mobile's UNORM per-step clamp?" — a SATURATION
# question, about Forward+ lock-in. It is silent on a second, independent property:
#
#   PSX blends in the 8-bit FRAMEBUFFER (DISPLAY, gamma-encoded space). Godot's Forward+ main
#   target is LINEAR. So an IN-SCENE blend_add/blend_sub applies a display-magnitude constant
#   to linear light: the units do not match and the error grows with the backdrop's brightness.
#   The engine fold is the fix — Pass A seeds a display-space scratch from the opaque scene,
#   Pass B blends THERE, Pass C resolves to linear + RGB555 (ADR-0074).
#
# The glove cursor's drop shadow carried `compositor-exempt: ... it does NOT belong in the fold
# scratch` — prose that satisfied axis 1's `EXEMPT in text` test, was never validated, and was
# simply FALSE. Measured after routing it to a fold twin, max |err| vs the ROM's `bg - CLUT`
# fell 104 -> 4 (half an RGB555 step). A free-text reason nobody can check is not a guard.
#
# So an in-scene add/sub must ANSWER the display-space question in a machine-checkable way:
#   (a) it declares compositor_layer (it folds — nothing to answer), or
#   (b) a sibling `<stem>_fold.gdshader` exists AND declares compositor_layer, so this file is
#       demonstrably the off-fork fallback of a routed pair — VERIFIED, not claimed, or
#   (c) it carries `// display-space: folds-on-fork <twin.gdshader>` naming a twin that exists
#       and declares compositor_layer (for pairs whose names do not follow the `_fold` suffix), or
#   (d) it carries `// display-space: <any other reason>` — an explicit, reviewed decision, or
#   (e) it is on DISPLAY_SPACE_ALLOWLIST below (the burn-down of not-yet-reviewed prims).
#
# Note what (b)/(c) buy that prose does not: "this is the off-fork fallback" becomes a claim the
# guard can falsify by looking for the twin. The old glove marker had NO twin and claimed no
# fallback, so this arm would have failed it.
DISPLAY_SPACE = "display-space:"
_DS_TAG = re.compile(r"//\s*display-space:\s*(\S+)(?:[ \t]+(\S+))?")

# In-scene add/sub prims whose DISPLAY-SPACE question has not been answered yet. Each argues
# clamp-equivalence on axis 1 ("a SINGLE pre-clamped layer, so the final display clamp equals the
# PSX per-step clamp") — true, and about SATURATION. None of them has been checked for GAMMA.
# Shrink this list by folding the prim, or by adding a `// display-space:` reason that survives
# measurement. It only shrinks; a stale entry fails.
DISPLAY_SPACE_ALLOWLIST = {
    # REMOVED 2026-09-08: shadow_blob.gdshader — ROUTED. It now has a `shadow_blob_fold`
    # compositor_layer twin (rule (b): the sibling exists and folds), so the display-space
    # question is answered by construction, exactly as its formation counterpart's was.
    "trap_charge_line.gdshader",       # blend_add tubes over the map
    "screen_color_mode1.gdshader",     # full-screen additive tint
    "screen_color_mode2.gdshader",     # full-screen SUBTRACTIVE tint (fade curve is gamma-shaped)
    "screen_color_mode3.gdshader",     # full-screen additive tint, quarter-weighted
    "show_graphic.gdshader",           # full-screen additive title card
    "show_graphic_shadow.gdshader",    # its SUBTRACTIVE drop shadow — same shape as the glove
    "show_map_title.gdshader",         # full-screen additive title strip
    "show_map_title_shadow.gdshader",  # its SUBTRACTIVE drop shadow — same shape as the glove
    "unit_additive.gdshader",          # dead-unit additive fade ({43})
    # REMOVED 2026-09-06: screen_in_mode2.gdshader (world-map screen-in). It is
    # `shader_type canvas_item`, which this scan skips by design — so it was an entry no
    # ratchet could ever reach or retire, inflating the un-reviewed count by one forever.
    # Its display-space question is also already answered in its own header, by design and
    # not by prose: the world map composites in the GPU's own 5-bit channels with every quad
    # baked as `8 * v`, and psx_expand_555 runs the expansion ONCE on the finished frame —
    # i.e. that pipeline blends in a quantised display-like space on purpose. If the 2D
    # canvas path ever needs its own colour-space scoreboard, that is a new guard with its
    # own domain, not a name parked on this one's list.
}

# A `render_mode ...;` declaration (line-anchored so a `blend_add` in a COMMENT — e.g.
# unit.gdshader's "opaque here, blend_add there" note — is never matched). The render_mode
# line is always single-line in this tree.
_ADD_SUB = re.compile(r"^[ \t]*render_mode\b[^;]*\b(blend_add|blend_sub)\b", re.MULTILINE)
_MIX = re.compile(r"^[ \t]*render_mode\b[^;]*\bblend_mix\b", re.MULTILINE)
_FOLD = re.compile(r"^[ \t]*render_mode\b[^;]*\bcompositor_layer\b", re.MULTILINE)
_CANVAS = re.compile(r"^[ \t]*shader_type\s+canvas_item\b", re.MULTILINE)

# ---------------------------------------------------------------------------
# The burn-down list of in-scene blend_add/blend_sub shaders not yet routed or
# exempt. Delete a line as its material routes through the compositor (gains
# compositor_layer / a routed variant) or earns a `// compositor-exempt:` marker.
# When this set is empty the effort is done — switch to the hard-zero form.
# Category tags per COMPOSITOR_UNIVERSAL_ROUTING_SCOPING.md.
# ---------------------------------------------------------------------------
ALLOWLIST = {
    # Category A/B — quad + OT-depth or arbitrary mesh; route via UnifiedPrimStager / a fold variant.
    # ROUTED + DELETED FROM TREE: tile_overlay_mode1/2/3, tile_cursor_semi_mode1/2/3, crystal_sprite
    # (2026-07-21). EXEMPT-MARKED (single pre-clamped [0,1] full-screen / fading layer, Forward+-safe):
    # show_graphic[_shadow], show_map_title[_shadow], screen_color_mode1/2/3, unit_additive (2026-07-21).
    # ROUTED via compositor_layer variant (2026-07-27): effect_callback_additive — callbacks now fold
    # through the compositor on Forward+ (effect_callback_fold.gdshader); its in-scene file is the Mobile
    # fallback and is exempt-marked. See memory engine-shaded-fold-passB / the callback-fold work.
    #
    # Category B — arbitrary mesh (Path 2 mesh-carrier: per-vertex Gouraud / draped decal / tube).
    # ROUTED 2026-09-08: shadow_blob — the Category-B row is retired. The scoping pass filed it
    # as "arbitrary mesh", but UnitShadow.gd drapes by rotating the whole QuadMesh BASIS to the
    # terrain normal: it is a rigid quad, so the fold twin (shadow_blob_fold.gdshader) needed no
    # new mesh input path. Its in-scene file is exempt-marked as the off-fork fallback.
    "trap_charge_line.gdshader",          # blend_add tubes (needs ImmediateMesh -> ArrayMesh+CUSTOM0)
    # FORMATION screen UI3 blends — ROUTED 2026-07-30 (ADR-0077): all five now fold via *_fold
    # compositor_layer variants on the Forward+ fork, and their in-scene files are exempt-marked as the
    # off-fork Mobile fallback. Removed from the burn-down (the allowlist only shrinks).
}


def _classify(text: str) -> dict:
    return {
        "canvas": _CANVAS.search(text) is not None,
        "add_sub": _ADD_SUB.search(text) is not None,
        "mix": _MIX.search(text) is not None,
        "fold": _FOLD.search(text) is not None,
        "exempt": EXEMPT in text,
        "ex_tag": _EXEMPT_TAG.search(text),
        "ds_tag": _DS_TAG.search(text),
    }


def check(scan_dirs=None, *, allowlist=None, clamp_allowlist=None,
          display_space_allowlist=None, out=None) -> int:
    """The whole scoreboard, with its scan root and its three lists INJECTABLE.

    Every default is the module constant, so a bare `check()` is exactly what the
    pre-flight runs. The parameters exist for `tools/test_check_compositor_routing.py`
    and they exist for one reason: this guard carries three shrink-only ratchets
    across two axes, and until that test NOBODY HAD EVER WATCHED ONE FAIL. The
    seeded-defect harness that proved the axis-1 arms mutated the real shader tree
    and restored it with `git checkout -- .` between cases -- fine for one session,
    unrunnable as a test, and a future edit could silently break the verification
    with nothing going red. (It restored the GUARD too, so a refactor of this file
    made that harness re-run the pre-refactor code and report 9/9 regardless.)
    Injecting the scan root lets each arm be seeded against a handful of files in a
    tmpdir instead, which is what makes the arms provable on every run.

    Returns 0 clean / 1 violation, and writes its whole report to `out` (default
    stdout) -- including the missing-scan-dir error, which used to go to stderr.
    """
    scan_dirs = SCAN_DIRS if scan_dirs is None else [Path(p) for p in scan_dirs]
    allowlist = ALLOWLIST if allowlist is None else set(allowlist)
    clamp_allowlist = (CLAMP_ARGUMENT_ALLOWLIST if clamp_allowlist is None
                       else set(clamp_allowlist))
    display_space_allowlist = (DISPLAY_SPACE_ALLOWLIST if display_space_allowlist is None
                               else set(display_space_allowlist))
    stream = sys.stdout if out is None else out

    def say(*args):
        print(*args, file=stream)

    seen: dict[str, dict] = {}   # name -> classification (spatial non-opaque only)
    for base in scan_dirs:
        if not base.is_dir():
            say(f"ERROR: scan dir not found: {base}")
            return 1
        for path in sorted(base.rglob("*.gdshader")) + sorted(base.rglob("*.gdshaderinc")):
            c = _classify(path.read_text(encoding="utf-8"))
            if c["canvas"]:
                continue  # 2D UI is not in the 3D compositor's Pass-C domain
            if c["add_sub"] or c["mix"]:
                seen[path.name] = c

    fold_names = {n for n, c in seen.items() if c["fold"]}

    # --- Axis 1 (lock-in): every exemption must NAME A KIND, and the checkable kind is CHECKED ---
    def _twin_of(name: str, arg: str | None):
        """(ok, how) — does an off-fork-fallback claim point at a real folding twin?"""
        # The token after the kind is the twin only if it LOOKS like one. Without this the
        # regex would read the first word of the prose as a filename, and the no-arg form
        # (lean on the `<stem>_fold` sibling) could never be written at all.
        if arg and not arg.endswith((".gdshader", ".gdshaderinc")):
            arg = None
        if arg:
            if arg not in fold_names:
                return False, (f"`{EXEMPT} {OFF_FORK} {arg}` — that file does not exist in the "
                               f"scan or does not declare compositor_layer")
            return True, f"off-fork fallback of {arg} (verified)"
        stem = name.rsplit(".", 1)[0]
        for ext in (".gdshader", ".gdshaderinc"):
            if f"{stem}_fold{ext}" in fold_names:
                return True, f"off-fork fallback of {stem}_fold{ext} (verified)"
        return False, (f"`{EXEMPT} {OFF_FORK}` names no twin and there is no folding "
                       f"`{stem}_fold` sibling to stand in for one")

    def _answers_lock_in(name: str, c: dict):
        """(ok, how) — is this file's EXEMPTION a kinded claim the guard accepts?"""
        m = c["ex_tag"]
        if not m:
            return False, (f"`{EXEMPT}` marker is malformed (it must be a `// ` comment and name "
                           f"a kind)")
        kind, arg = m.group(1), m.group(2)
        if kind == OFF_FORK:
            return _twin_of(name, arg)
        if kind == PRE_CLAMPED:
            if name not in clamp_allowlist:
                return False, (f"claims `{PRE_CLAMPED}`, which the scan cannot verify, but is not "
                               f"on CLAMP_ARGUMENT_ALLOWLIST — that list only shrinks")
            return True, f"{PRE_CLAMPED} (allowlisted argument)"
        return False, (f"`{EXEMPT} {kind}` — unknown kind; use one of {', '.join(EXEMPT_KINDS)}")

    ex_bad, ex_stale = [], []
    for name, c in sorted(seen.items()):
        if not c["add_sub"] or c["fold"] or not c["exempt"]:
            continue
        ok_ex, how = _answers_lock_in(name, c)
        if not ok_ex:
            ex_bad.append((name, how))
    marked_in_scene = {n for n, c in seen.items()
                       if c["add_sub"] and not c["fold"] and c["exempt"]}
    for name in sorted(clamp_allowlist):
        if name not in marked_in_scene:
            ex_stale.append(name)

    # --- Axis 2 (colour space): every in-scene add/sub must ANSWER the display-space question ---
    ds_leaks, ds_stale, ds_badtwin = [], [], []

    def _answers_display_space(name: str, c: dict):
        """(ok, how) — is this file's display-space question answered in a CHECKABLE way?"""
        if c["fold"]:
            return True, "folds"
        stem = name.rsplit(".", 1)[0]
        for ext in (".gdshader", ".gdshaderinc"):
            if f"{stem}_fold{ext}" in fold_names:
                return True, f"off-fork fallback of {stem}_fold{ext} (verified)"
        m = c["ds_tag"]
        if m:
            kind, arg = m.group(1), m.group(2)
            if kind == "folds-on-fork":
                if not arg:
                    return False, "`display-space: folds-on-fork` names no twin"
                if arg not in fold_names:
                    return False, (f"`display-space: folds-on-fork {arg}` — that file does not "
                                   f"exist or does not declare compositor_layer")
                return True, f"off-fork fallback of {arg} (verified)"
            return True, f"reviewed ({kind})"
        return False, "no display-space answer"

    for name, c in sorted(seen.items()):
        if not c["add_sub"] or c["fold"]:
            continue
        ok_ds, how = _answers_display_space(name, c)
        if ok_ds:
            if name in display_space_allowlist:
                ds_stale.append((name, how))
        elif name not in display_space_allowlist:
            (ds_badtwin if how.startswith("`") else ds_leaks).append((name, how))

    # A burn-down entry the scan can never REACH is the same hole one level up: it can never go
    # stale, so it sits on the list forever inflating the "still un-reviewed" count with a prim
    # nothing is measuring. (screen_in_mode2.gdshader was one — `shader_type canvas_item`, which
    # the loop above skips by design.) The loop can only report a name it iterates, so the
    # unreachable ones are found by difference, not by the loop.
    ds_unreachable = []
    for name in sorted(display_space_allowlist):
        if name not in seen:
            ds_unreachable.append((name, "the scan never sees this file (canvas_item, no longer "
                                         "add/sub or mix, deleted, or outside walk_roots())"))
        elif seen[name]["fold"]:
            ds_unreachable.append((name, "now declares compositor_layer — it folds"))
        elif not seen[name]["add_sub"]:
            ds_unreachable.append((name, "no longer declares blend_add/blend_sub"))

    leaks = []   # add/sub, not routed, not exempt, not allowlisted -> regression
    stale = []   # allowlisted but no longer an un-routed in-scene add/sub -> tighten the ratchet
    for name, c in seen.items():
        if not c["add_sub"]:
            continue
        if c["fold"] or c["exempt"] or name in allowlist:
            continue
        leaks.append(name)

    unrouted_add_sub = {n for n, c in seen.items()
                        if c["add_sub"] and not c["fold"] and not c["exempt"]}
    for name in sorted(allowlist):
        if name not in unrouted_add_sub:
            stale.append(name)

    # --- Inventory: locate EVERY non-opaque spatial shader with its status. ---
    def status(name: str, c: dict) -> str:
        if c["fold"]:
            return "ROUTED (compositor_layer)"
        if c["exempt"]:
            return "exempt"
        if c["add_sub"] and name in allowlist:
            return "allowlist (add/sub burn-down)"
        if c["add_sub"]:
            return "LEAK (un-routed add/sub)"
        return "mix (inventory; runtime-probe enforces completeness)"

    say("Non-opaque spatial shader inventory (add/sub enforced, mix located):")
    for name in sorted(seen):
        say(f"  {name}: {status(name, seen[name])}")
    say()

    ok = True
    if ex_bad:
        ok = False
        say("`compositor-exempt:` marker(s) whose claim is not a KIND the guard can accept:")
        for n, how in sorted(ex_bad):
            say(f"  {n}: {how}")
        say(
            f"\nAn exemption is a CLAIM about Forward+ lock-in, and free prose is not a guard —\n"
            f"that is how the glove cursor's shadow kept a FALSE reason through a green\n"
            f"scoreboard for months. Lead the marker with its kind:\n"
            f"  // {EXEMPT} {OFF_FORK} <twin.gdshader> — <prose>   (twin must really fold;\n"
            f"      omit the arg only when the twin is the `<stem>_fold` sibling)\n"
            f"  // {EXEMPT} {PRE_CLAMPED} — <prose>   (the Cat C2/D single-pre-clamped-layer\n"
            f"      argument; un-checkable, so admitted only from CLAMP_ARGUMENT_ALLOWLIST)\n"
            f"If the prim really does need routing, route it instead — that is the burn-down."
        )
    if ex_stale:
        ok = False
        say("Stale CLAMP_ARGUMENT_ALLOWLIST entries in check_compositor_routing.py:")
        for n in ex_stale:
            say(f"  {n}: no longer a `{EXEMPT}`-marked in-scene add/sub")
        say("\nRemove these — the un-checkable-argument list only shrinks.")
    if ds_leaks or ds_badtwin:
        ok = False
        say("In-scene blend_add/blend_sub with an UNANSWERED display-space question:")
        for n, how in sorted(ds_leaks + ds_badtwin):
            say(f"  {n}: {how}")
        say(
            "\nPSX blends in the 8-bit framebuffer (DISPLAY space); Godot's main target is LINEAR,\n"
            "so an in-scene add/sub applies a display-magnitude constant to linear light and the\n"
            "error grows with the backdrop's brightness. Either fold the prim (compositor_layer +\n"
            f"a `<stem>_fold` twin), or add `// {DISPLAY_SPACE} folds-on-fork <twin.gdshader>` naming\n"
            f"a twin that really declares compositor_layer, or `// {DISPLAY_SPACE} <reviewed reason>`.\n"
            "A free-text `compositor-exempt:` reason does NOT answer this axis — that is exactly how\n"
            "the glove cursor's shadow kept a false exemption through a green scoreboard."
        )
    if ds_stale:
        ok = False
        say("Stale DISPLAY_SPACE_ALLOWLIST entries in check_compositor_routing.py:")
        for n, how in sorted(ds_stale):
            say(f"  {n}: now answered — {how}")
        say("\nRemove these from DISPLAY_SPACE_ALLOWLIST — the burn-down list only shrinks.")
    if ds_unreachable:
        ok = False
        say("DISPLAY_SPACE_ALLOWLIST entries the scan can never REACH:")
        for n, why in ds_unreachable:
            say(f"  {n}: {why}")
        say(
            "\nAn entry the scan never iterates can never go stale either, so it inflates the\n"
            "un-reviewed count forever with a prim nothing measures. Remove it — and if the prim\n"
            "does still blend somewhere this guard does not look, that is a SCOPE question for\n"
            "the docstring, not a name to park on a burn-down list."
        )
    if leaks:
        ok = False
        say("Un-routed additive/subtractive shader(s) not in the allowlist:")
        for n in sorted(leaks):
            say(f"  {n}: declares blend_add/blend_sub in-scene")
        say(
            "\nRoute it through the compositor (add compositor_layer / a fold variant, or a\n"
            "UnifiedPrimStager producer), or if it is a CPU-clamped full-screen / by-decision\n"
            f"in-scene material, add a `// {EXEMPT} <reason>` marker. Do NOT grow the ALLOWLIST\n"
            "for genuinely new prims — it only shrinks."
        )
    if stale:
        ok = False
        say("Stale ALLOWLIST entries in check_compositor_routing.py:")
        for n in stale:
            say(f"  {n}: no longer an un-routed in-scene add/sub (routed or exempt-marked)")
        say("\nRemove these from ALLOWLIST — the burn-down list only shrinks.")

    if ok:
        remaining = len([n for n in seen if seen[n]["add_sub"] and n in allowlist])
        exempt_n = sum(1 for c in seen.values() if c["exempt"])
        fold_n = sum(1 for c in seen.values() if c["fold"])
        mix_n = sum(1 for c in seen.values() if c["mix"] and not c["add_sub"])
        say(
            f"OK: compositor-routing scoreboard clean — {remaining} add/sub shader(s) left on the "
            f"burn-down allowlist, {fold_n} routed (compositor_layer), {exempt_n} exempt-marked, "
            f"{mix_n} mix inventoried. (0 allowlisted = ready for Forward+.)"
        )
        verified_twin = sum(1 for n, c in seen.items()
                            if c["add_sub"] and not c["fold"] and c["exempt"]
                            and _answers_lock_in(n, c)[1].startswith("off-fork fallback"))
        say(
            f"    lock-in axis: of the {exempt_n} exemptions, {verified_twin} are "
            f"`{OFF_FORK}` claims VERIFIED against a real folding twin and "
            f"{exempt_n - verified_twin} rest on the un-checkable `{PRE_CLAMPED}` argument "
            f"(CLAMP_ARGUMENT_ALLOWLIST, {len(clamp_allowlist)} entries, shrink-only)."
        )
        say(
            f"    display-space axis: {len(display_space_allowlist)} in-scene add/sub prim(s) still "
            f"un-reviewed for the LINEAR-vs-DISPLAY blend defect (burn-down)."
        )
    return 0 if ok else 1


def main() -> int:
    return check()


if __name__ == "__main__":
    sys.exit(main())
