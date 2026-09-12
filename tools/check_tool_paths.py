#!/usr/bin/env python3
"""Guard: a tool's hardcoded tree path must resolve, and a booking prefix must match.

    uv run python tools/check_tool_paths.py [--list]

WHY THIS EXISTS. #744 moved 33 files out of `src/animation/` and `assets/` into
`addons/exmateria_sprite_rig/`, and the ticket asked one question of every tool that
named one of those paths: **if the path were left stale, would anything say so?**
The answer was measured, one tool at a time, by hiding the named file in a scratch
worktree and running the tool. The register:

    LOUD   check_color_shaders.py           rc 1  "expected colour consumer is missing"
    LOUD   check_par_shaders.py             rc 1  "STALE BURN_DOWN entry"
    LOUD   check_sprite_layers_one_mesh.py  rc 1  "ADR-0019: expected <path> - it is missing"
    LOUD   check_unit_shader_paths.py       rc 1  "VARIANT_PATHS names a file that does not exist"
    LOUD   bake_populated_rows.py --check   rc 1  "ABORT: <path> missing"  (in the pre-flight)
    LOUD*  gen_activity_taxonomy.py --check rc 1  "STALE activity taxonomy"
    SILENT parse_weapon_animation_ids.py          an OUTPUT path, no --check, unrun
    SILENT asset_census.py                        a booking PREFIX that matches nothing

`check_sprite_layers_one_mesh.py` is not a hypothetical: both of its path constants
were left behind by #744's own move commit and it went red on the spot, which is the
whole case for a loud tool.

The asterisk on `gen_activity_taxonomy.py` is the finding underneath this guard.
It is loud, but the remedy it PRINTS is silently wrong: the regenerate path does
`path.parent.mkdir(parents=True, exist_ok=True)` before writing, so following the
tool's own instructions would re-create the dead `src/animation/` and drop a
resurrected `DisplayActivity.gd` into it that nothing loads, while the addon's real
one drifts. Loud about the symptom, silent about the cure.

THE TWO ARMS ARE THE TWO SILENT SHAPES, and they are different failures:

  arm 1  A BOOKING PREFIX THAT MATCHES NOTHING NEVER FIRES. `asset_census.py`'s
         `FORMAT_OWNER` is a longest-prefix table; a row whose directory has been
         deleted simply stops being consulted, and every file it used to book falls
         through to reader-booking or to `(NO FORMAT RULE)` -- a number that moves
         with no row saying why. This is the census half of the defect this repo has
         already paid for once: *a prefix rule makes a wrong move read as a WIN*.

  arm 2  AN OUTPUT PATH IS NEVER READ, SO IT IS NEVER CHECKED. A generator whose
         destination moved keeps writing to the old address. Nothing loads what it
         wrote, the committed copy drifts, and the tool exits 0 the whole time.
         The arm reads the DECLARED constant out of the source with `ast` rather
         than importing the module -- `asset_census.py` and `classify_blueprint.py`
         both run work at import, and importing the latter EXITS the process.

WHAT THIS DOES NOT CHECK. That a path is the RIGHT one -- only that it resolves.
Set equality against the move manifest is `tools/check_move_manifest.py` arm 3, and
quoted `res://` literals are `tools/check_res_paths.py`. Neither can see either shape
here: a `Path(__file__).parent.parent / "assets" / "sprites" / "x.json"` is not a
`res://` literal, and a booking prefix is not a file reference at all.

ROM-DERIVED TARGETS ARE EXCLUDED BY NAME, NOT BY RULE. `assets/sprites/` and the
other gitignored asset roots are absent on a correct fresh checkout, so asserting
them would make this guard red for everyone who has not run `bootstrap_assets.sh`
-- the failure mode #424 named, where a guard that is red on a correct tree teaches
everyone to ignore it. Each excluded constant is listed with its reason.

Exit 0 if every declared path resolves and every booking prefix matches. Pure stdlib.
"""
import ast
import pathlib
import sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent

# --- arm 1 -----------------------------------------------------------------
# Module-level tables in asset_census.py whose entries are (prefix, owner) pairs.
# A prefix is a path relative to PROJECT_DIR; a trailing "/" means a directory.
CENSUS_TABLES = [("tools/asset_census.py", "FORMAT_OWNER"),
                 ("tools/asset_census.py", "PACKET_CLASSES")]

# Prefixes that are allowed to match nothing, each with the reason. A row here is
# a DECISION with a name on it, not a filter -- same shape as check_res_paths.py's
# KNOWN_BREAKS, and a prefix that starts matching again also fails.
# EMPTY, and that is the point: the one row this table ever held was
# `assets/animation_resolution/`, the pre-#744 output of
# `tools/migrate_state_animations_to_tres.gd`. Both the prefix and the one-shot are
# gone now, so the exemption went with them rather than outliving its subject. The
# table stays because the SHAPE is the decision — a prefix allowed to match nothing
# is a row with a name on it, never a filter, and a prefix that starts matching
# again fails (#424).
CENSUS_ALLOWED_EMPTY: dict[str, str] = {}

# --- arm 2 -----------------------------------------------------------------
# (module, constant) pairs whose value is a Path built from literal segments.
TOOL_PATH_CONSTANTS = [
    ("tools/parse_weapon_animation_ids.py", "DEFAULT_OUTPUT_PATH"),
    ("tools/parse_weapon_wep1_anim_ids.py", "DEFAULT_BODY_TABLE"),
    ("tools/parse_weapon_wep1_anim_ids.py", "DEFAULT_OUTPUT"),
    ("tools/bake_populated_rows.py", "OUTPUT_PATH"),
    ("tools/gen_activity_taxonomy.py", "DISPLAY_ACTIVITY_PATH"),
    ("tools/check_sprite_layers_one_mesh.py", "MANAGER"),
    ("tools/check_sprite_layers_one_mesh.py", "UNIT_SHADER"),
]

# Constants whose target is ROM-derived and gitignored -- absent on a correct fresh
# checkout, so asserting them would be red for a tree with nothing wrong with it.
TOOL_PATHS_EXCLUDED = {
    ("tools/parse_weapon_wep1_anim_ids.py", "DEFAULT_TYPE1_SEQ"):
        "assets/sprites/animations/type1_seq.json -- ISO-derived, gitignored",
    ("tools/bake_populated_rows.py", "TEXTURES_DIR"):
        "assets/sprites/textures/ -- the ISO-derived NN.palette.tga set, gitignored",
    ("tools/parse_weapon_animation_ids.py", "DEFAULT_BATTLE_PATH"):
        "BATTLE.BIN, out of tree entirely (project-assets/, local-only)",
}


def _module(rel: str) -> ast.Module:
    return ast.parse((PROJECT_DIR / rel).read_text(encoding="utf-8"), filename=rel)


def _assigned(tree: ast.Module, name: str) -> ast.expr | None:
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name) and t.id == name:
                    return node.value
    return None


def _path_segments(node: ast.expr) -> list[str] | None:
    """`<anything> / "a" / "b"` -> ["a", "b"]. None if any segment is not a literal."""
    segs: list[str] = []
    while isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        if not (isinstance(node.right, ast.Constant) and isinstance(node.right.value, str)):
            return None
        segs.insert(0, node.right.value)
        node = node.left
    return segs or None


def arm_one() -> list[str]:
    """Every booking prefix in the census matches at least one real path."""
    fail: list[str] = []
    seen: set[str] = set()
    for rel, table in CENSUS_TABLES:
        value = _assigned(_module(rel), table)
        if value is None:
            fail.append(f"{rel}: no module-level `{table}` -- this arm went blind, repoint it")
            continue
        for entry in ast.literal_eval(value):
            prefix = entry[0]
            if not isinstance(prefix, str) or not prefix.startswith("assets/"):
                continue  # addon members and the `None` rules are ruled elsewhere
            seen.add(prefix)
            hit = (PROJECT_DIR / prefix).exists() or any(
                str(q.relative_to(PROJECT_DIR)).startswith(prefix)
                for q in (PROJECT_DIR / "assets").glob("*"))
            allowed = prefix in CENSUS_ALLOWED_EMPTY
            if hit and allowed:
                fail.append(f"{rel} {table}: `{prefix}` is on CENSUS_ALLOWED_EMPTY but now "
                            f"MATCHES -- the row came back; remove the exemption.")
            elif not hit and not allowed:
                fail.append(f"{rel} {table}: booking prefix `{prefix}` matches nothing. A "
                            f"prefix that matches nothing never fires, so the bytes it used "
                            f"to book fall silently to `(NO FORMAT RULE)`. Repoint or retire it.")
    for prefix in CENSUS_ALLOWED_EMPTY:
        if prefix not in seen:
            fail.append(f"CENSUS_ALLOWED_EMPTY names `{prefix}`, which is not a booking "
                        f"prefix any more -- the exemption outlived its row.")
    return fail


def arm_two() -> list[str]:
    """Every declared tree path in a generator or path-holding guard resolves."""
    fail: list[str] = []
    for rel, const in TOOL_PATH_CONSTANTS:
        value = _assigned(_module(rel), const)
        if value is None:
            fail.append(f"{rel}: no module-level `{const}` -- renamed or removed, and this "
                        f"arm silently stopped checking it. Repoint TOOL_PATH_CONSTANTS.")
            continue
        segs = _path_segments(value)
        if segs is None:
            fail.append(f"{rel}: `{const}` is no longer a literal path expression, so it "
                        f"cannot be read statically. Keep it literal or drop the row.")
            continue
        rel_target = "/".join(segs)
        if not (PROJECT_DIR / rel_target).exists():
            fail.append(f"{rel}: `{const}` names `{rel_target}`, which does not exist. "
                        f"If this is an OUTPUT path, nothing would have told you: the tool "
                        f"writes to the dead address and the committed copy drifts.")
    return fail


def main() -> int:
    fail = arm_one() + arm_two()
    if "--list" in sys.argv:
        for rel, const in TOOL_PATH_CONSTANTS:
            segs = _path_segments(_assigned(_module(rel), const)) or []
            print(f"  {rel:<45} {const:<22} {'/'.join(segs)}")
        for (rel, const), why in TOOL_PATHS_EXCLUDED.items():
            print(f"  EXCLUDED {rel:<36} {const:<22} {why}")
    if fail:
        print("stale tool paths / booking prefixes:")
        for f in fail:
            print(f"  {f}")
        print("\nFix: repoint the constant. A tool that names a moved path and has no arm "
              "on it is the SILENT half of #744's LOUD/SILENT register -- see this file's "
              "docstring for the measured table.")
        return 1
    n = len(TOOL_PATH_CONSTANTS)
    print(f"OK: {n} declared tool paths resolve; every census booking prefix matches "
          f"({len(CENSUS_ALLOWED_EMPTY)} named empty).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
