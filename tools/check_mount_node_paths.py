#!/usr/bin/env python3
"""Guard: a host file reaching INTO a mount scene by node NAME is a declared crossing.

    uv run python tools/check_mount_node_paths.py [--list]

WHY THIS EXISTS (ADR-0217 dec. 3, #744). Dec. 3 collapses 114 files referencing
`assets/scenes/Unit.tscn` down to ONE file naming an addon path — the declared
mount. That is the SCENE-PATH channel and `tools/check_lattice_scene.py` scores
it. It leaves the NODE-PATH channel untouched, and the two are not the same
question: `speaker.get_node_or_null("UnitMesh")` names a node inside
`addons/exmateria_sprite_rig/UnitRig.tscn` without naming a single path, so no
path-based guard can see it and the mount collapse does not cover it.

🔴 THE CASE FOR THE ARM IS THE SILENCE, NOT A MAGNITUDE. ADR-0217 dec. 18
renamed `UnitMesh` on the fork, headful, and re-ran the crossing: the lookup
returns `null` with **zero engine diagnostic**, and both dialogue-box sites
carry an explicit `if == null` fallback to `speaker.global_position`. So a
rename does not remove the dialogue box; it substitutes the unit's tile origin
for the sprite's mesh origin, and nothing in the log says so.

⚠️ #745 MEASURED THAT SUBSTITUTION AND THE ERROR IS ZERO TODAY — this header's
earlier claim of a **~65-76 px** mis-anchor is FALSIFIED and is corrected here
rather than deleted, because the number was published in the guard's own red
message. Driven headful against the real `ScenarioVM` / `box_pool` /
`DialogueBox` on `assets/scenes/ScenarioPlayer.tscn` (scenario 1), all ten live
units report `UnitMesh.global_position - unit.global_position == (0, 0, 0)`, so
BOTH crossings return byte-identical anchors with the node present and with it
renamed. The cause is two defaults, not luck: `ANCHOR_QUAD_FRAC_Y_DEFAULT` is
`0.0`, and `Tune`'s `render.unit_y_lift` binds `0.0` (`Unit.gd`'s literal
fallback of `0.05` is a third home for the same value that never runs). Displace
the mesh synthetically and the fallback DOES diverge — measured **43.2 native
px** at `(-2.285 tiles, +0.5 y)` — so the arm guards a live channel, not a dead
one. The ~18 px PAR drift and Simon's carry pose stranding the tail 76 px left
are decode facts of the SPRITE; both survive the fallback unchanged, and a
rename cannot re-open either.

The warrant is therefore stronger than the original wording, not weaker: the
reach fails silently, AND its harm is invisible today only because a value that
is free to move is currently zero. A guard keyed on the observable damage would
score nothing.

Meanwhile `src/units/Unit.gd:497` spells the same reach `get_node("UnitMesh")`,
bare, and errors loudly. **The host adapter fails loudly and the two crossings
fail silently**, which is why a static declaration is worth more here than the
usual "it would break, someone would notice".

The measured register, per crossing, as of #744:

    src/units/Unit.gd:112          $SpriteLayerManager           LOUD
    src/units/Unit.gd:115          $AnimationStateController     LOUD
    src/units/Unit.gd:118          $CameraRelativeRenderer       LOUD
    src/units/Unit.gd:497          get_node("UnitMesh")          LOUD
    src/scenarios/ScenarioDialogueBoxPool.gd:517  get_node_or_null  SILENT
    src/scenarios/ScenarioDialogueBoxPool.gd:728  get_node_or_null  SILENT

`Unit.gd:547-549` names the same three nodes again, as STRINGS in
`ValidationUtils.validate_required_components`'s list — a runtime presence
assertion, which is the loud channel doing its job and not a fourth reach. It is
declared below anyway, because a rename has to update it too and a guard that
scored the `$` spelling but not the string beside it would send you to fix half.

THE THREE ARMS.

  arm 1  Every declared crossing's node name EXISTS in its mount scene. This is
         the rename arm — the one thing no runtime fallback can tell you.

  arm 2  The DISCOVERED crossing set equals the DECLARED one. A new host file
         reaching into the rig has to say so, and a crossing that goes away has
         to be removed here rather than leaving a row guarding nothing. Set
         equality, `check_move_manifest.py` arm 3's shape.

  arm 3  Every mount scene resolves and parses to at least one node. Without it
         a mount that moved would make arm 1 vacuously green — a scene with no
         nodes trivially satisfies "every declared name is missing"... which is
         to say it would fail LOUDLY, but for the wrong reason and pointing at
         six innocent call sites instead of at the moved scene.

WHAT THIS DOES NOT CHECK. That the node is the right TYPE, or that the fallback
is correct. Both are runtime questions and `tests/` owns them. It also cannot
see a name built at runtime (`get_node("Unit" + suffix)`) — a static scan never
can, and the discovery arm's `--list` output is the honest statement of what it
did look at.

Exit 0 when every declared crossing resolves and the discovered set matches.
Pure stdlib.
"""
import pathlib
import re
import sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent

# Scenes an addon publishes as a mount. The node names inside one are part of the
# addon's surface whether or not anything says so, which is the finding.
MOUNT_SCENES = ["addons/exmateria_sprite_rig/UnitRig.tscn"]

# Host trees scanned for a crossing. The addon's own files are NOT host files:
# a rig script naming a rig node is internal, not a crossing.
HOST_ROOTS = ["src", "tests", "assets"]

# (host file, node name) -> (failure mode, why this reach exists).
# A row is a DECLARATION with a reason, not a suppression: arm 1 still asserts
# the name resolves, and arm 2 still fails if the reach disappears.
CROSSINGS: dict[tuple[str, str], tuple[str, str]] = {
    ("src/units/Unit.gd", "SpriteLayerManager"):
        ("LOUD", "the `@onready var sprite_layers` bind. `$X` on a miss prints "
                 "`Node not found` and the typed assignment takes the unit down."),
    ("src/units/Unit.gd", "AnimationStateController"):
        ("LOUD", "the `@onready var anim_state` bind, same shape."),
    ("src/units/Unit.gd", "CameraRelativeRenderer"):
        ("LOUD", "the `@onready var camera_renderer` bind, same shape."),
    ("src/units/Unit.gd", "UnitMesh"):
        ("LOUD", "`get_node(\"UnitMesh\")` in `_initialize_mesh_and_rendering` — "
                 "bare, so a miss errors. This is the host adapter and it is the "
                 "half of the asymmetry that behaves."),
    ("src/scenarios/ScenarioDialogueBoxPool.gd", "UnitMesh"):
        ("SILENT", "TWO sites, :517 and :728, each with an `if == null` fallback "
                   "to `speaker.global_position`. A rename does not remove the "
                   "box — it silently swaps the mesh origin for the unit's tile "
                   "origin. #745 measured that swap headful: 0.0 px today (the "
                   "two origins coincide, `anchor_quad_frac_y` and "
                   "`render.unit_y_lift` are both 0.0) and 43.2 px with the mesh "
                   "displaced. See the header — the old `~65-76 px` was wrong."),
    ("tests/DialogueBoxAnchorParTest.gd", "UnitMesh"):
        ("SILENT", "not a reach — the test BUILDS a `UnitMesh` child so that "
                   "`_sprite_billboard_anchor`'s own lookup (the SILENT row above) "
                   "takes its billboard branch at all. Declared here rather than "
                   "exempted because the coupling runs the WRONG way: on a rename "
                   "production silently swaps to the tile origin while this test, "
                   "holding its own copy of the name, stays green and reports the "
                   "PAR stretch working. Arm 1 is what makes that rename loud for "
                   "the test too. Rename the node and this row fails; the anchor "
                   "assertions do not."),
}

# A bare STRING that happens to spell a mount node name and is not a reach at all.
# Named, with the reason, rather than filtered by a cleverer regex: the string
# channel is in this scan because `validate_required_components`'s argument list IS
# a reach, and no pattern separates that from a label without knowing the callee.
#
# ⚠️ AN EXEMPTION IS KEYED ON (file, name), SO IT MASKS THAT PAIR IN THAT FILE. If
# `UnitMaterialVariantTest` later grows a real `$SpriteLayerManager`, this row hides
# it. That is the cost of the coarser key; the alternative is keying on line number,
# which every unrelated edit above it would invalidate.
COINCIDENT_SPELLINGS: dict[tuple[str, str], str] = {
    ("tests/UnitMaterialVariantTest.gd", "SpriteLayerManager"):
        "a LABEL, not a lookup: `required[param] = \"SpriteLayerManager\"` records "
        "which script pushed each shader parameter, so the test can say WHERE a "
        "missing uniform was supposed to come from. The test reaches no node — it "
        "reads the driver as TEXT, which is the whole reason it holds its own "
        "`const BASE_MATERIAL` (the independent oracle; do not route it through "
        "`UnitAssets`).",
}

# `$Name`, `%Name`, and the three lookup verbs with a bare single-segment literal.
_DOLLAR = re.compile(r"[$%]([A-Za-z_][A-Za-z0-9_]*)\b")
_LOOKUP = re.compile(r"\b(?:get_node|get_node_or_null|has_node)\(\s*\^?\"([A-Za-z_][A-Za-z0-9_]*)\"")
# A node-name STRING in an argument list, e.g. validate_required_components's.
_STRING = re.compile(r"\"([A-Za-z_][A-Za-z0-9_]*)\"")


def _mount_nodes(rel: str) -> set[str]:
    text = (PROJECT_DIR / rel).read_text(encoding="utf-8")
    return set(re.findall(r"^\[node name=\"([^\"]+)\"", text, re.M))


def _strip_noncode(text: str) -> str:
    """Blank `#` comments and `\"\"\"` docstring blocks, LINE COUNT preserved.

    Both channels quote node names on purpose — this file's own register does —
    and a scan that reads prose as a reach reports the documentation as the
    defect. The opposite mistake (stripping so hard the reach vanishes) is why
    the blanking is per-line rather than a whole-file regex.
    """
    out: list[str] = []
    in_doc = False
    for line in text.split("\n"):
        fences = line.count('"""')
        if in_doc:
            if fences:
                in_doc = False
            out.append("")
            continue
        if fences == 1:
            in_doc = True
            out.append("")
            continue
        if fences >= 2:
            out.append("")
            continue
        stripped = line.lstrip()
        out.append("" if stripped.startswith("#") else line)
    return "\n".join(out)


def _host_files() -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for root in HOST_ROOTS:
        files.extend(sorted((PROJECT_DIR / root).rglob("*.gd")))
    return files


def discover(node_names: set[str]) -> dict[tuple[str, str], list[int]]:
    """Every (host file, mount node name) reach, with the 1-indexed lines."""
    found: dict[tuple[str, str], list[int]] = {}
    for path in _host_files():
        rel = str(path.relative_to(PROJECT_DIR))
        try:
            text = _strip_noncode(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError):
            continue
        for n, line in enumerate(text.split("\n"), start=1):
            hits = set(_DOLLAR.findall(line)) | set(_LOOKUP.findall(line))
            hits |= {s for s in _STRING.findall(line) if s in node_names}
            for name in hits & node_names:
                found.setdefault((rel, name), []).append(n)
    return found


def main() -> int:
    fail: list[str] = []

    # --- arm 3: the mounts themselves ---------------------------------------
    node_names: set[str] = set()
    owner: dict[str, str] = {}
    for rel in MOUNT_SCENES:
        if not (PROJECT_DIR / rel).exists():
            fail.append(f"MOUNT MISSING — {rel} does not exist. Every arm below is "
                        f"vacuous until this is repointed.")
            continue
        names = _mount_nodes(rel)
        if not names:
            fail.append(f"MOUNT EMPTY — {rel} parses to zero `[node name=` rows, so "
                        f"arm 1 would fail every crossing for the wrong reason.")
        node_names |= names
        for name in names:
            owner[name] = rel

    if not fail:
        # --- arm 1: every declared name still resolves in its mount ----------
        renamed: set[str] = set()
        for (rel, name), (mode, why) in sorted(CROSSINGS.items()):
            if name not in node_names:
                renamed.add(name)
                fail.append(f"RENAMED OR REMOVED — {rel} reaches `{name}`, which is no "
                            f"longer a node in {', '.join(MOUNT_SCENES)}. This reach is "
                            f"{mode}: {why}")

        # --- arm 2: discovered == declared -----------------------------------
        found = discover(node_names)
        for key in sorted(set(COINCIDENT_SPELLINGS) - set(found)):
            fail.append(f"STALE EXEMPTION — COINCIDENT_SPELLINGS excuses {key[0]}'s "
                        f"`{key[1]}` and that spelling is gone. Remove the row.")
        for key in sorted(set(found) - set(CROSSINGS) - set(COINCIDENT_SPELLINGS)):
            lines = ",".join(str(n) for n in found[key])
            fail.append(f"UNDECLARED CROSSING — {key[0]}:{lines} reaches the mount node "
                        f"`{key[1]}`. Add it to CROSSINGS with its failure mode, measured "
                        f"(rename the node and boot it) rather than assumed.")
        # A name arm 1 already reported is excluded here: discovery matches against the
        # MOUNT's node set, so a renamed node makes every live reach to it undiscoverable
        # and the row would be accused of guarding nothing while it is doing its job.
        # Reporting a rename twice, the second time with the wrong cause, is the shape
        # that sends you to edit the six call sites instead of the one scene.
        for key in sorted(set(CROSSINGS) - set(found)):
            if key[1] in renamed:
                continue
            fail.append(f"STALE ROW — CROSSINGS declares {key[0]} reaches `{key[1]}` and "
                        f"nothing in that file does any more. Remove the row; a row "
                        f"guarding nothing reads as coverage.")

        if "--list" in sys.argv:
            for key in sorted(found):
                mode = CROSSINGS.get(key, ("not-a-reach" if key in COINCIDENT_SPELLINGS
                                              else "?", ""))[0]
                print(f"  {mode:<7} {key[0]}:{','.join(str(n) for n in found[key])}"
                      f"  -> {key[1]}  (in {owner.get(key[1], '?')})")

    if fail:
        print("mount node-path crossings:")
        for f in fail:
            print(f"  {f}")
        print("\nADR-0217 dec. 3. A node inside a mount scene is addon surface: renaming "
              "one returns null with NO engine diagnostic, and two of the six crossings "
              "swallow that null by design.")
        return 1

    silent = sum(1 for m, _ in CROSSINGS.values() if m == "SILENT")
    print(f"OK: {len(CROSSINGS)} declared mount-node crossing(s) resolve, {silent} of them "
          f"SILENT on a miss; discovered set matches "
          f"({len(COINCIDENT_SPELLINGS)} coincident spelling(s) named).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
