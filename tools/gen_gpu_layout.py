#!/usr/bin/env python3
"""Generate the combat buffer layout constants in GDScript from the
authoritative compute shader.

The shader (`src/gpu/shaders/combat_common.glslinc`) is the single source of
truth for the combat buffer layout — the integer field offsets, struct sizes,
and (in a later step) the shared action/target/condition enums. This tool
parses the shader's `const int NAME = value;` declarations and rewrites the
delimited GENERATED regions in the GDScript that mirrors them.

Authoritative from the shader: member NAMES, VALUES, ORDER and MEMBERSHIP.
Carried forward (not authoritative): trailing `#` comments — they are
documentation, preserved across regeneration by member name so the GDScript
docs survive even though the shader carries none.

See docs/adr/0001-gpu-combat-buffer-layout-is-shader-authoritative.md.

Usage:
    uv run python tools/gen_gpu_layout.py           # rewrite generated regions
    uv run python tools/gen_gpu_layout.py --check    # exit 1 if any region is stale
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHADER = ROOT / "src" / "gpu" / "shaders" / "combat_common.glslinc"

BEGIN = "# === BEGIN GENERATED: combat buffer layout (tools/gen_gpu_layout.py) ==="
END = "# === END GENERATED ==="
HEADER_LINES = [
    "# Source of truth: src/gpu/shaders/combat_common.glslinc",
    "# Names/values/order are generated - DO NOT edit them here.",
    "# Trailing # comments ARE preserved across regeneration; edit them freely.",
    "# Regenerate: uv run python tools/gen_gpu_layout.py",
]

# Each target = one GDScript file with one generated region. A target emits
# some mix of:
#   "consts"       standalone consts pulled by exact shader name
#   "enums"        (GDScript enum name, shader prefix) — strip prefix to member
#   "const_groups" (section label, shader prefix) — emit `const FULLNAME = v`,
#                  keeping the full prefixed name (callers use GPUConstants.ACTION_*)
TARGETS = [
    {
        "file": "src/gpu/GPUCombatPacker.gd",
        "consts": ["UNIT_SIZE", "BATTLE_HEADER_SIZE", "SHADER_VERSION", "TURN_METER_FULL",
                   "RESULT_SIZE"],
        "enums": [
            ("UnitField", "U_"),
            ("BattleHeaderField", "BH_"),
            ("GambitField", "GM_"),
            ("AbilityField", "AB_"),
            # The per-battle RESULT RECORD (#896). It was a GD-only `RESULT_SIZE = 4`
            # in GPUBatchSimulator sitting opposite a literal `battle_id * 4` in
            # stage_victory.glsl — one number written twice, with nothing holding
            # the copies together. Generating it makes the shader authoritative
            # here the same way it already is for every other layout (ADR-0001).
            ("ResultField", "R_"),
        ],
        # (const name, enum name, prefix) -> emit `const NAME := {"member_lower":
        # EnumName.MEMBER, ...}` covering every field. get_battle_unit_states()
        # loops over this, so every field is always in the snapshot (no key can
        # silently go missing) and the string keys can't drift from the offsets.
        "key_maps": [
            ("SNAPSHOT_FIELDS", "UnitField", "U_"),
            ("BATTLE_STATE_FIELDS", "BattleHeaderField", "BH_"),
        ],
    },
    {
        # GPUConstants is the GD-side aggregator callers reference as
        # GPUConstants.ACTION_* / TARGET_* / COND_* / STATE_* (flat consts, full
        # name kept). Generated here so it stops drifting from the shader.
        "file": "src/gpu/GPUConstants.gd",
        # Buffer sizes/strides that exist in the shader (MAX_ANIMATIONS is GD-only,
        # not in the shader, so it stays hand-authored outside the region).
        "consts": ["MAX_GAMBITS", "GAMBIT_SIZE", "ABILITY_SIZE", "MAX_ABILITIES"],
        "const_groups": [
            # STATE_* retired in PR2 -- LOGICAL_ACTIVITY_* (tools/gen_activity_taxonomy.py)
            # is now the source of truth for unit-activity constants.
            ("Action types", "ACTION_"),
            ("Target types", "TARGET_"),
            ("Condition types", "COND_"),
        ],
    },
]

# const int NAME = <int literal> ;   [// comment]
_INT_CONST = re.compile(
    r"^\s*const\s+int\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(-?\d+)\s*;\s*(?://\s*(.*\S))?\s*$"
)
# const int NAME = <non-literal> ;   (used to detect would-be-exported expressions)
_ANY_CONST = re.compile(r"^\s*const\s+int\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*;")


class GenError(Exception):
    pass


# Generated GDScript must be ASCII: the Windows console build emits
# "Unicode parsing error ... cannot represent as ASCII/Latin-1" for non-ASCII,
# and the rest of the codebase keeps source ASCII. Transliterate the common
# punctuation that shows up in comments; leave letters/digits untouched.
_ASCII_MAP = {
    "—": "-", "–": "-", "‒": "-",  # em/en/figure dash
    "→": "->", "←": "<-",               # arrows
    "×": "x", "·": "*", "•": "*",   # times, middot, bullet
    "‘": "'", "’": "'", "“": '"', "”": '"',  # smart quotes
    "…": "...", "§": "S", "°": "deg",
}


def asciify(text):
    if text is None:
        return None
    return "".join(_ASCII_MAP.get(ch, ch) for ch in text)


def parse_shader():
    """Return {name: (int_value, comment_or_None)} for every integer-literal
    `const int` in the shader, plus the set of names whose value is NOT an
    integer literal (so we can refuse to export those)."""
    literals = {}
    non_literal = set()
    for raw in SHADER.read_text().splitlines():
        m = _INT_CONST.match(raw)
        if m:
            name, value, comment = m.group(1), int(m.group(2)), m.group(3)
            literals[name] = (value, comment)
            continue
        m2 = _ANY_CONST.match(raw)
        if m2:
            non_literal.add(m2.group(1))
    return literals, non_literal


def preserved_comments(region_text):
    """Map name -> existing trailing comment, scraped from the current generated
    region so docs survive regeneration.

    An enum member is keyed `EnumName.MEMBER`, NOT bare `MEMBER`. Two enums may
    hold the same member name -- `BattleHeaderField.RESULT` is the battle
    header's verdict word and `ResultField.RESULT` is the result record's, both
    stripping to `RESULT` -- and a flat map makes one of them inherit the
    other's comment. That is not only wrong documentation: it makes the
    generator NON-IDEMPOTENT, because the bled comment is scraped back on the
    next pass and written where the shader never put it, so `--check` reports
    STALE immediately after a successful regeneration.
    """
    out = {}
    enum_open = re.compile(r"^\s*enum\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{")
    member = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*-?\d+\s*,?\s*#\s*(.*\S)\s*$")
    const = re.compile(r"^\s*const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*-?\d+\s*#\s*(.*\S)\s*$")
    scope = None
    for line in region_text.splitlines():
        opened = enum_open.match(line)
        if opened:
            scope = opened.group(1)
            continue
        if line.strip() == "}":
            scope = None
            continue
        mc = const.match(line)
        if mc:
            out[mc.group(1)] = mc.group(2)
            continue
        mm = member.match(line)
        if mm:
            key = f"{scope}.{mm.group(1)}" if scope else mm.group(1)
            out[key] = mm.group(2)
    return out


def emit_region(target, literals, non_literal, comments):
    def comment_for(shader_name, member_name, shader_comment, scope=None):
        # `scope` is the enclosing enum, and the lookup is scoped to it — see
        # `preserved_comments` for why an unscoped member key does not converge.
        scoped = f"{scope}.{member_name}" if scope else member_name
        c = shader_comment or comments.get(scoped) or comments.get(shader_name)
        return asciify(c)

    def prefixed(label, prefix):
        # refuse to silently drop a prefixed const that isn't an int literal
        bad = sorted(n for n in non_literal if n.startswith(prefix))
        if bad:
            raise GenError(
                f"{label}: shader consts {bad} match prefix {prefix!r} "
                f"but are not integer literals"
            )
        items = sorted(
            ((n, v, c) for n, (v, c) in literals.items() if n.startswith(prefix)),
            key=lambda t: t[1],
        )
        if not items:
            raise GenError(f"{label}: no shader consts with prefix {prefix!r}")
        return items

    lines = [BEGIN, *HEADER_LINES, ""]

    for name in target.get("consts", []):
        if name not in literals:
            if name in non_literal:
                raise GenError(f"{name} is not an integer literal in the shader")
            raise GenError(f"const {name} not found in shader")
        value, scomment = literals[name]
        c = comment_for(name, name, scomment)
        lines.append(f"const {name} = {value}" + (f"  # {c}" if c else ""))
    if target.get("consts"):
        lines.append("")

    for enum_name, prefix in target.get("enums", []):
        lines.append(f"enum {enum_name} {{")
        for name, value, scomment in prefixed(enum_name, prefix):
            member = name[len(prefix):]
            c = comment_for(name, member, scomment, scope=enum_name)
            lines.append(f"\t{member} = {value}," + (f"  # {c}" if c else ""))
        lines.append("}")
        lines.append("")

    for label, prefix in target.get("const_groups", []):
        lines.append(f"# {label} (generated from shader {prefix}* - see header)")
        for name, value, scomment in prefixed(label, prefix):
            c = comment_for(name, name, scomment)
            lines.append(f"const {name} = {value}" + (f"  # {c}" if c else ""))
        lines.append("")

    for const_name, enum_name, prefix in target.get("key_maps", []):
        lines.append(f"# {const_name}: snake_case key -> {enum_name} offset, every field.")
        lines.append(f"const {const_name} := {{")
        for name, value, scomment in prefixed(const_name, prefix):
            member = name[len(prefix):]
            lines.append(f'\t"{member.lower()}": {enum_name}.{member},')
        lines.append("}")
        lines.append("")

    lines.append(END.rstrip())
    return "\n".join(lines)


def replace_region(file_text, new_region, path):
    begin_marker = BEGIN.strip()
    end_marker = END.strip()
    lines = file_text.splitlines()
    bi = next((i for i, l in enumerate(lines) if l.strip() == begin_marker), None)
    ei = next((i for i, l in enumerate(lines) if l.strip() == end_marker), None)
    if bi is None or ei is None or ei < bi:
        raise GenError(
            f"{path}: generated-region sentinels not found "
            f"(expected lines '{begin_marker}' .. '{end_marker}')"
        )
    return "\n".join(lines[:bi] + new_region.splitlines() + lines[ei + 1:]) + "\n"


def main(argv):
    check = "--check" in argv[1:]
    literals, non_literal = parse_shader()
    stale = []
    for target in TARGETS:
        path = ROOT / target["file"]
        text = path.read_text()
        begin_marker, end_marker = BEGIN.strip(), END.strip()
        cur = text.splitlines()
        bi = next((i for i, l in enumerate(cur) if l.strip() == begin_marker), None)
        ei = next((i for i, l in enumerate(cur) if l.strip() == end_marker), None)
        if bi is None or ei is None:
            raise GenError(f"{target['file']}: generated-region sentinels not found")
        region_now = "\n".join(cur[bi:ei + 1])
        comments = preserved_comments(region_now)
        region_new = emit_region(target, literals, non_literal, comments)
        updated = replace_region(text, region_new, target["file"])
        if updated != text:
            stale.append(target["file"])
            if not check:
                path.write_text(updated)

    if check:
        if stale:
            print("STALE combat buffer layout — regenerate with:")
            print("  uv run python tools/gen_gpu_layout.py")
            for f in stale:
                print(f"  - {f}")
            return 1
        print("combat buffer layout: up to date")
        return 0

    if stale:
        print("Regenerated combat buffer layout in:")
        for f in stale:
            print(f"  - {f}")
    else:
        print("combat buffer layout: already up to date")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except GenError as e:
        print(f"gen_gpu_layout: ERROR: {e}", file=sys.stderr)
        sys.exit(2)
