#!/usr/bin/env python3
"""Generate the OWNED event / BattleConditional opcode catalogs.

The disassembler used to read FFTPatcher's `EventCommands.xml` /
`BattleConditionalCommands.xml` **verbatim** straight from the parser path —
the one place in the repo that broke the ISO-derived-data + in-housed-authored
annotation pattern (ADR-0001; precedent `parse_scenarios.py:37-48`). The XMLs
are FFTPatcher's reverse-engineering, not ROM facts: opcode names, parameter
byte-widths, and opcode width are all *authored*. So we own them.

This tool transcribes the (now reference-only, relocated to `data/vendor/`)
XMLs into owned JSON catalogs co-located with the other authored label tables
under `assets/scenarios/`:

    assets/scenarios/event_instructions.json         (1-byte event script)
    assets/scenarios/battle_conditional_opcodes.json (2-byte BattleConditionals)

The owned catalogs add per-opcode `verified` flags + `handler` cross-refs that
the vendored XML can't carry. The **core** of each entry (name + param
name/bytes/type/mode) is still a byte-for-byte transcription of the XML, and
`--check` enforces BOTH that the committed JSON's core matches the XML and
that the committed file is byte-for-byte what this generator writes (so a
hand-edited overlay can no longer be deleted by the next run) until we
intentionally diverge.

Usage:
    uv run python tools/gen_opcode_catalog.py           # (re)write both catalogs
    uv run python tools/gen_opcode_catalog.py --check    # fail if committed JSON
                                                         # core drifts from the XML
"""

from __future__ import annotations

import argparse
import json
import re
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

TOOLS = Path(__file__).parent

# --- EventInstruction enum (Option-A slug rule; ADR-0059 / issue #145) ------
#
# The event-script interpreter dispatches on a generated `EventInstruction`
# enum whose member is the Option-A slug of the catalog display name and whose
# value is the opcode byte. Slug rule:
#   - UPPER_SNAKE the display name; unique slug used verbatim.
#   - A colliding slug gets `_0XNN` (the opcode hex) appended to EVERY sharer,
#     so the 48 `Unknown` bytes become UNKNOWN_0X12, UNKNOWN_0X14, ...
#   - The six `Variable <=/>=/==/!=/</>` comparison ops (which would all slug to
#     VARIABLE) render meaningfully via a symbol map -> VARIABLE_LE/GE/EQ/... .
#   - Uniqueness is re-asserted AFTER disambiguation as a backstop.
_COMPARISON_TOKENS = {"<=": "LE", ">=": "GE", "==": "EQ", "=": "EQ",
                      "!=": "NE", "<": "LT", ">": "GT"}


def _upper_snake(s: str) -> str:
    """Collapse non-alphanumeric runs to a single underscore, uppercase, and
    strip edge underscores. 'No-op' -> 'NO_OP', 'Face Unit 2' -> 'FACE_UNIT_2'."""
    return re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_").upper()


def event_slug(name: str) -> str:
    """Base slug for one display name (pre-collision-disambiguation).

    A two-token `<word> <comparison-operator>` name (the Variable family)
    renders the operator through the symbol map so `Variable <=` becomes
    `VARIABLE_LE` rather than the bare, colliding `VARIABLE`."""
    parts = name.split()
    if len(parts) == 2 and parts[1] in _COMPARISON_TOKENS:
        return f"{_upper_snake(parts[0])}_{_COMPARISON_TOKENS[parts[1]]}"
    return _upper_snake(name)


def event_enum_members(names_by_op: dict[int, str], width: int = 1) -> dict[int, str]:
    """Map {opcode_int: display_name} -> {opcode_int: enum member identifier},
    applying the Option-A disambiguation. Raises ValueError if two members
    still collide after hex-suffixing (a backstop that should never fire since
    opcode bytes are unique)."""
    base = {op: event_slug(name) for op, name in names_by_op.items()}
    counts = Counter(base.values())
    members: dict[int, str] = {}
    for op in sorted(base):
        slug = base[op]
        if counts[slug] > 1:
            slug = f"{slug}_0X{op:0{width * 2}X}"
        members[op] = slug
    seen: dict[str, int] = {}
    for op in sorted(members):
        m = members[op]
        if not m.isidentifier():
            raise ValueError(f"opcode 0x{op:X}: member {m!r} is not a valid identifier")
        if m in seen:
            raise ValueError(
                f"slug collision after disambiguation: {m!r} claimed by "
                f"0x{seen[m]:X} and 0x{op:X}"
            )
        seen[m] = op
    return members

VENDOR = TOOLS / "data" / "vendor"
ASSETS_SCENARIOS = TOOLS.parent / "assets" / "scenarios"
SCENARIOS_SRC = TOOLS.parent / "src" / "scenarios"
# The generated dispatch enums live beside the interpreters they key (the ISA of
# the event-script VM / the BattleConditionals mini-ISA), not under src/data/
# (ADR-0059).
EVENT_INSTRUCTION_GD = SCENARIOS_SRC / "EventInstruction.gd"
BATTLE_CONDITIONAL_GD = SCENARIOS_SRC / "BattleConditionalOpcode.gd"

# Per-catalog generated-enum spec: the same Option-A slug transform applied to a
# second, smaller language (ADR-0059 Consequences — "can adopt the same pattern
# on its own later"). Keyed by the CATALOGS key.
ENUM_OUTPUTS = {
    "event": {
        "class_name": "EventInstruction",
        "out": EVENT_INSTRUCTION_GD,
        "source": "event_instructions.json",
        "doc": [
            "# Dispatch key for the event-script interpreter (ADR-0059). The member",
            "# name is the Option-A slug of the catalog display name; the underlying",
            "# int value IS the opcode byte. Reference members by name",
            "# (EventInstruction.FACE_UNIT_2), never by a literal byte.",
        ],
    },
    "bc": {
        "class_name": "BattleConditionalOpcode",
        "out": BATTLE_CONDITIONAL_GD,
        "source": "battle_conditional_opcodes.json",
        "doc": [
            "# Dispatch key for the BattleConditionals mini-ISA (ADR-0059). The member",
            "# name is the Option-A slug of the catalog display name; the underlying",
            "# int value IS the 2-byte opcode. Reference members by name",
            "# (BattleConditionalOpcode.RUN_SCENARIO), never by a literal opcode. The",
            "# ScenarioDirector reads each requirement's operands through the shared",
            "# EventInstructionArgs reader (BattleConditionalSet.args).",
        ],
    },
}

# --- Authored metadata overlaid on the XML transcription ------------------
#
# Verified handler cross-refs, live-confirmed against the BATTLE.BIN dispatcher
# (SCENARIO_LOADING.md §3.2.1; research/wiki_articles/event_instructions.md §2-3).
# `verified: true` means the dispatcher case for that opcode was statically
# grounded; everything else defaults to `verified: false`.
EVENT_HANDLERS = {
    0x10: {"handler": "FUN_801308c0",
           "notes": "evt0x10 Display Message; see event_instruction_10_display_message.md"},
    0x11: {"handler": "0x80149398", "notes": "evt0x11_unit_anim_handler"},
    0x19: {"handler": "0x80146110", "notes": "camera_immediate_non_fusion_step"},
    0x1E: {"handler": "0x8013db9c",
           "notes": "camera_fusion_end_queue_build (+ spline 0x8013dfb0)"},
    0x2D: {"handler": "0x80148284",
           "notes": "evt0x2D_rotate_unit_handler (16-dir 22.5deg wheel)"},
    0x53: {"handler": "0x80148084",
           "notes": "evt0x53_face_unit_handler (case body 0x8013ec18)"},
    0x63: {"handler": "0x80144ca0",
           "notes": "Camera Speed Curve: stores the byte to global 0x80166054; the "
                    "{19} task body reads it at 0x80146118 (intensity hi-nibble, "
                    "A=byte&3 shape, B=(byte>>2)&3 field-gate). Ease = "
                    "(16-I)/16*t + I/16*easeQuad(t), bit-exact for 0xAA. See "
                    "CAMERA_ROTATION_OPCODES_63_73_19_INVESTIGATION.md §4.7."},
    0x73: {"handler": "0x801474a4",
           "notes": "Camera Move (relative): FUN_801474a4 pre-patches the FOLLOWING "
                    "{19} Camera's 7 pose operands to live_pose+delta (Time left; "
                    "sentinel 0x2710=keep). Sibling of {1F} Focus. See "
                    "CAMERA_ROTATION_OPCODES_63_73_19_INVESTIGATION.md §3.3/§4.4."},
    0x7F: {"handler": "0x8014a3f8",
           "notes": "evt0x7f_evtchr_palette_handler (timing-wait on FUN_8013b590(Block) >= Palette)"},

# Recovered 2026-09-11: FOUR MORE hand-added JSON entries the table never
# learned — same failure as the 2026-08-22 batch below, so that was not a
# one-off. {68} came from b9a8d2282 and {76}/{77}/{78} from ac89cbaed; both
# commits edited assets/scenarios/event_instructions.json directly, so running
# this generator DELETED three CONFIRMED 2026-09-10 decodes and reverted {76}
# to a retracted attribution.
    0x68: {"handler": "0x8013E65C",
           "notes": "evt0x68_mirror_sprite_handler. Operand size table [0x68]=3 -> 4-byte instruction {u16 Unit; u8 Mirror}. Single unit (unit_id_validate_resolve 0x80133158, 0x7d0 = not deployed -> no-op), never the {2D}/{11} multi-selector. Mirror==1 -> unit[+0x13F]=0x02 via unit_set_flip_xor_mask (0x8008CC50); any other value -> 0x00 via unit_clear_flip_xor_mask (0x8008CC80). unit[+0x13F] is the sprite flip_xor_mask: the render dispatch computes flip = render_flags(+0x12) ^ flip_xor_mask (xor @0x80086764), so {68} XORs with the facing/camera-derived horizontal flip instead of overriding it. Dispatch 0x80144868 (main) / 0x8013EAF4 (block). See research/working_documents/MIRROR_SPRITE_OPCODE_68.md."},
    0x76: {"handler": "0x8013BD94 -> 0x801CA664",
           "notes": "CONFIRMED 2026-09-10: {76} IS Dark Screen, not Set Text Speed. The 0x76 arm of the interpreter's bne chain at 0x80145280 spawns the trampoline 0x8013BD94, which writes task kind 0x36 and calls the results overlay's entry 0x801CA664 — and a sweep of all 2 MB of RAM for lui+addiu pairs, for jal targets and for any word equal to 0x8013BD94 returns exactly ONE code site, so that arm is the only way in. The earlier FUN_8013da00 'text-throttle writer' attribution is retracted. research/working_documents/DARKSCREEN_OPCODE_76_INVESTIGATION.md §13, BATTLE_RESULTS_SCREEN.md §13."},
    0x77: {"handler": None,
           "notes": "CONFIRMED 2026-09-10: {77} does not re-enter the {76} body — it re-labels that task's kind 0x37 -> 0x36, which is what asks the one coroutine already running the dim to run its frame loop backwards. DARKSCREEN_OPCODE_76_INVESTIGATION.md §13."},
    0x78: {"handler": "0x8013BD6C -> 0x801CAFD4",
           "notes": "CONFIRMED 2026-09-10. ⚠️ THE FIRST OPERAND IS A MODE, NOT A CONDITIONS ID — the name 'Conditions' is FFTPatcher's and is kept for catalogue compatibility. 0x801CAFD4 dispatches it: 0 = READY!, 1 = dead (no event emits it), 2 = the victory text, 3 = BONUS MONEY + the gil reel, 4 = WAR TROPHIES, 5 = WARNING, 6 = PARTING SHOT!!, 7 = the recruit flow, >= 8 = the victory-condition banner for EVENT/BONUS.BIN page mode-8. 'Time' reaches ONLY mode 0 and modes >= 8; modes 1-7 are spawned with all three params zero and hard-code their own durations. A census of all 500 events finds the six outro modes emitted unconditionally and in order in all 64 outro scripts. BATTLE_RESULTS_SCREEN.md §13."},

# Recovered 2026-08-22: these eleven were hand-added to the committed JSON but never
# to this table, so any regeneration silently DELETED them.  Folded back in so the
# generator is idempotent again -- `python3 tools/gen_opcode_catalog.py` now
# reproduces the committed artifact byte for byte.
    0x22: {"handler": "0x801453c4",
           "notes": "evt0x22 Switch Track; toggles between ATTACK.OUT song one/two (track byte param '1' is a set-gate, value unused), ramps master vol to FUN_8012db90(Volume)=clamp(Volume*127/96) over Time*4 ticks. RE: HANDOFF_switch_track_opcode.md"},
    0x2C: {"handler": "0x80148084",
           "notes": "Same ROM handler as {53} Face Unit (evt0x53_face_unit), dispatched with a1=0 (scenario interp 0x80144dec _clear a1). a1=0 also rotates the FACED unit 180 deg back to look at the affected unit -> mutual face-each-other. See scenario_1_captures/face_unit_decode.md section 11."},
    0x3B: {"handler": "0x80149c48",
           "notes": "dispatched from FUN_80143bd8 @0x80144fa0 (beq s4,0x3b); confirmed live (priest walk). NOTE (2026-06-28 static decode): 0x80149c48 is the cooperative-task SLOT ALLOCATOR, not the mover. The dispatcher registers a worker (FUN_80146ee4 for {3B}, FUN_80146f20 for {6E}; kind tag 0xb) via FUN_8014c8a0 (sets slot+0x48=1 ACTIVE); the worker runs interpolator FUN_80146940 @0x80146940 which steps one frame per scheduler tick (FUN_8014ca80) for Time ({3B}) or distance/Speed ({6E}) frames, then self-terminates (FUN_8014c958 clears slot+0x48). 'Unknown' param = easing WEIGHT (operand+9, w; curve uses w and 0x10-w). Type (operand+8) selects 4 curves: 0 linear, 1 weighted ease, 2 piecewise sym ease-in/out, 3 cubic-like. {6F} (FUN_80146f5c) polls slot liveness. VERIFIED (2026-06-28, live per-frame position trace): all 4 Type curves + weight reproduce hardware BIT-EXACT (Type 0 priest 0->28/T=40; Types 1/2/3 via operand-patch at w=1 and w=16). The +X/+Z/+Y operand is the ABSOLUTE value of the unit's POSITION-OFFSET field (unit_struct +0x60, via FUN_8008ca48/FUN_8008c9c4), which the renderer ADDS to the base/home position (+0x40): draw_pos = base[0x40] + offset[0x60]. So a move's endpoint is home+operand, NOT a world coordinate and NOT a cumulative delta (three-actor walk-in offsets to -28 then back to 0=home; the interpolator slides offset from its current value to the operand). Offset 0x60 is zeroed by opcode 0x70 Jump (FUN_8013e708) and re-placement. Live struct read: priest base[0x40]=(154,-84,154), offset[0x60]=0 at move start. {6E} frame count = sqrt(Sum d^2 * 0x10)/Speed = 4*dist/Speed. See SPRITE_MOVE_INVESTIGATION.md."},
    0x66: {"handler": "_op_commit_palette",
           "notes": "Bakes the live {33} Color Field field-tint into the map base palette (the scenario-3/4/5/6 map-hue fix). Modeled in Godot: ScenarioVM._op_commit_palette. See MAP_HUE_WEATHER_STATE_CLUT_BAKE.md."},
    0x6C: {"handler": "FUN_8014968c",
           "notes": "CLEARs bit 0x04000000 (bit 26) at unit node+0x80 (shared handler with {6D}, a1=0; clearer FUN_8008cce8). Bit 26 gates the per-frame unit update FUN_80082468 (skips FUN_800822bc when set) = 'hold unit under event control'. Godot no-op: cinematic units are already VM-driven (is_cinematic_unit), so the suppressed auto-update has no analogue. See SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_INVESTIGATION.md \u00a72."},
    0x6D: {"handler": "FUN_8014968c",
           "notes": "SETs bit 0x04000000 (bit 26) at unit node+0x80 (shared handler with {6C}, a1=1; setter FUN_8008ccac). Bit 26 gates the per-frame unit update FUN_80082468 (skips FUN_800822bc when set) = 'hold unit under event control', set before Reset Palette / Warp Unit. Godot no-op: cinematic units are already VM-driven (is_cinematic_unit). See SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_INVESTIGATION.md \u00a72."},
    0x6E: {"handler": "0x80149c48",
           "notes": "dispatched from FUN_80143bd8 @0x80144fa0 (beq s4,0x3b); confirmed live (priest walk). NOTE (2026-06-28 static decode): 0x80149c48 is the cooperative-task SLOT ALLOCATOR, not the mover. The dispatcher registers a worker (FUN_80146ee4 for {3B}, FUN_80146f20 for {6E}; kind tag 0xb) via FUN_8014c8a0 (sets slot+0x48=1 ACTIVE); the worker runs interpolator FUN_80146940 @0x80146940 which steps one frame per scheduler tick (FUN_8014ca80) for Time ({3B}) or distance/Speed ({6E}) frames, then self-terminates (FUN_8014c958 clears slot+0x48). 'Unknown' param = easing WEIGHT (operand+9, w; curve uses w and 0x10-w). Type (operand+8) selects 4 curves: 0 linear, 1 weighted ease, 2 piecewise sym ease-in/out, 3 cubic-like. {6F} (FUN_80146f5c) polls slot liveness. VERIFIED (2026-06-28, live per-frame position trace): all 4 Type curves + weight reproduce hardware BIT-EXACT (Type 0 priest 0->28/T=40; Types 1/2/3 via operand-patch at w=1 and w=16). The +X/+Z/+Y operand is the ABSOLUTE value of the unit's POSITION-OFFSET field (unit_struct +0x60, via FUN_8008ca48/FUN_8008c9c4), which the renderer ADDS to the base/home position (+0x40): draw_pos = base[0x40] + offset[0x60]. So a move's endpoint is home+operand, NOT a world coordinate and NOT a cumulative delta (three-actor walk-in offsets to -28 then back to 0=home; the interpolator slides offset from its current value to the operand). Offset 0x60 is zeroed by opcode 0x70 Jump (FUN_8013e708) and re-placement. Live struct read: priest base[0x40]=(154,-84,154), offset[0x60]=0 at move start. {6E} frame count = sqrt(Sum d^2 * 0x10)/Speed = 4*dist/Speed. See SPRITE_MOVE_INVESTIGATION.md."},
    0x6F: {"handler": "0x80146f5c",
           "notes": "Barrier for {3B}/{6E}. Handler FUN_80146f5c @0x80146f5c, dispatched from FUN_80143bd8 @0x80145018 (ori v0,0x6f @0x80144f9c; bne s4,v0 @0x80145010). Static-decoded 2026-06-28: scans the 16 cooperative-task slots (PTR_DAT_80165f98, stride 0x400) and yields (FUN_8014ca80) one frame at a time while any slot is ACTIVE (slot+0x48!=0) with kind tag DAT_801698b8==0xb and unit DAT_801698bc==resolve(Unit); returns when none remain. Waits for ALL sprite-move tasks on that unit. See SPRITE_MOVE_INVESTIGATION.md."},
    0x71: {"handler": "FUN_8007a7b8",
           "notes": "Unlinks the unit's node and re-inserts it at the head of the PSX sprite draw-order list unit_sprite_list_head (0x80098A54) = raise to topmost draw priority, done right before a Sprite Move so the unit layers on top. Dispatch 0x80144898 (id->index FUN_80133158, 0x7d0=not loaded). Godot no-op: 3D depth sort (ADR-0009 CUSTOM0) already orders sprites by real depth; revisit only if carry-scene z-fighting. See SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_INVESTIGATION.md \u00a73."},
    0x7C: {"handler": "SUB_800440cc",
           "notes": "EndSound: zeroes the active-sound handle DAT_8004599c and calls FUN_80012860 (8-voice teardown) = stop the currently-playing event SFX/BGM. Placed at the scenario tail before the battle hand-off. Godot: SfxRouter.stop_all_event_sound() (stop all tracked bg/event voices + clear tracked handle). See SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_INVESTIGATION.md \u00a74."},
    0x82: {"handler": "FUN_8013e81c",
           "notes": "NOT an independently-dispatched opcode: a sub-token of the {49} AddUnitStart..{4A} AddUnitEnd block. {49} spawns block processor FUN_8013edd8 and skips the main PC past {4A}; that task, on token 0x82, calls FUN_8013e81c (Catmull-Rom control-point / midpoint geometry setup for the freshly-added units). Godot no-op: add-unit + ScenarioPathMotion already cover path/geometry init. See SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_INVESTIGATION.md \u00a75."},
}

# Verified against the ROM but with no single handler address to cite -- inline case
# bodies inside event_scenario_interpreter, or opcodes whose RE landed as a living-doc
# section rather than a function. Recovered 2026-08-22 from the committed JSON, where
# they had been hand-set and would have been erased by the next regeneration.
EVENT_VERIFIED_NO_HANDLER = {
    0x3E,  # Color Screen        COLOR_SCREEN_OPCODE_3E.md
    0x47,  # Add Ghost Unit      ADD_GHOST_UNIT_OPCODE_47.md
    0x48,  # Wait Add Unit       FACE_TILE_UNIT_SHADOW_WAIT_ADD_UNIT.md
    0x4E,  # Unit Shadow         FACE_TILE_UNIT_SHADOW_WAIT_ADD_UNIT.md
    0x50,  # Portrait Row        PORTRAIT_ROW_OPCODE_50_EVTFACE.md
    0x60,  # Fade Sound          FADESOUND_OPCODE_60_INVESTIGATION.md
    0x69,  # Face Tile           FACE_TILE_UNIT_SHADOW_WAIT_ADD_UNIT.md
}

# Opcodes with a known-unresolved discrepancy: seed the cross-ref but leave
# `verified: false` so it reads as provisional. {76} lived here until the
# 2026-09-10 decode resolved it; it is now in EVENT_HANDLERS and this table is
# empty. Keep the shape — the next UNRECONCILED opcode belongs here.
EVENT_PROVISIONAL: dict[int, dict] = {}

# BattleConditionals: the whole 22-case ladder is `bc_predicate` (0x80142694), so
# the cross-ref names the ladder's per-opcode HANDLER address, read out of the ROM
# 2026-08-22 (WITHIN_GROUP_MEMBER_TRANSITION.md §7.5, and
# research/working_documents/battle_end_captures/bceval.py `walker` prints this map).
# `verified: true` here means the case body was read and its comparison matches the
# XML's name and operand order.
BC_HANDLERS = {
    0x01: {"handler": "0x801426D4", "notes": "var(p1) == p2"},
    0x02: {"handler": "0x801426F0", "notes": "var(p1) >= p2"},
    0x03: {"handler": "0x8014270C", "notes": "var(p1) <= p2"},
    0x04: {"handler": "0x80142B1C",
           "notes": "the unit lookup 0x80142508(p1) resolved; shares its prologue "
                    "with opcodes 0x05..0x0A"},
    0x05: {"handler": "0x80142754", "notes": "unit+0x28 (HP) >= p2"},
    0x06: {"handler": "0x80142770", "notes": "unit+0x28 (HP) <= p2"},
    0x07: {"handler": "0x8014278C",
           "notes": "100*HP/(maxHP+1) >= p2 -- integer div, maxHP is unit+0x2A and the "
                    "+1 is the ROM's, not a rounding guess"},
    0x08: {"handler": "0x801427D0", "notes": "100*HP/(maxHP+1) <= p2"},
    0x09: {"handler": "0x80142814", "notes": "unit+0x2C (MP) >= p2"},
    0x0A: {"handler": "0x80142830", "notes": "unit+0x2C (MP) <= p2"},
    0x0B: {"handler": "0x80142850",
           "notes": "acting-unit word 0x8015D304 != 0xFF and the acting unit matches p1"},
    0x0D: {"handler": "0x801428CC",
           "notes": "scans units 1..3 for p1 among the 7 bytes at unit+0x1A -- the "
                    "equip slots"},
    0x0E: {"handler": "0x80142924",
           "notes": "var(0x2C) >= p2. p1 really is unused, as the XML says -- an "
                    "independent corroboration of the operand order. var 0x2C is GIL: "
                    "event_set_script_variable clamps that one index to 99,999,999"},
    0x0F: {"handler": "0x80142940", "notes": "var(0x2C) <= p2"},
    0x12: {"handler": "0x801429DC", "notes": "var(0x62) >= p1"},
    0x13: {"handler": "0x801429F8", "notes": "var(0x62) <= p1"},
    0x16: {"handler": "0x80142A14",
           "notes": "battle_outcome_census (0x80183374) == 0. Zero operands, which is "
                    "the entry of the operand table most able to falsify it"},
    0x18: {"handler": "0x80142A2C",
           "notes": "unit+0x47 == X, unit+0x48 == Y, (unit halfword 0x48 >> 15) == Z. "
                    "Z is a single BIT, not an elevation -- and it is 0 in all 5 "
                    "retail uses"},
    0x19: {"handler": "0x80142B24",
           "notes": "event_set_script_variable(0x27, p1) then return 2 -- the only "
                    "case that fires. One operand in the file (sentinel) even though "
                    "the ROM operand table says two; the walker returns first"},
    0x25: {"handler": "0x80142A80",
           "notes": "same three fields as 0x18, over the first of unit slots 0..20 "
                    "whose byte +0x04 == Team ID"},
}

# 0x10/0x11: the case bodies ARE read, but the XML's names are backwards relative to
# them, so the cross-ref is seeded and `verified` left false rather than blessing a
# name the ROM contradicts.
BC_PROVISIONAL = {
    0x10: {"handler": "0x8014295C",
           "notes": "ROM: TRUE iff (var 0x2E, var 0x2F) <= (Month, Day) -- it returns "
                    "true the moment var 0x2E < Month. The XML names this 'Date >='. "
                    "0x02/0x03, 0x0E/0x0F and 0x12/0x13 all match their names under "
                    "the same reading, so the pair looks SWAPPED in the catalog. "
                    "Unobservable in retail data: neither 0x10 nor 0x11 is used. "
                    "See WITHIN_GROUP_MEMBER_TRANSITION.md §7.5."},
    0x11: {"handler": "0x8014299C",
           "notes": "ROM: TRUE iff (var 0x2E, var 0x2F) >= (Month, Day). The XML names "
                    "this 'Date <='. Sibling of 0x10 -- see its note."},
}

CATALOGS = {
    "event": {
        "xml": VENDOR / "EventCommands.xml",
        "out": ASSETS_SCENARIOS / "event_instructions.json",
        "provenance": (
            "seeded from FFTPatcher EntryEdit/EntryData/PSX/EventCommands.xml "
            "(176 opcodes, FFTorama wiki labels); OWNED here. Names + param "
            "byte-widths + opcode width are authored RE, not ROM facts — verified "
            "against the BATTLE.BIN dispatcher per-opcode as we go (`verified` flag)."
        ),
        "handlers": EVENT_HANDLERS,
        "provisional": EVENT_PROVISIONAL,
        "verified_no_handler": EVENT_VERIFIED_NO_HANDLER,
    },
    "bc": {
        "xml": VENDOR / "BattleConditionalCommands.xml",
        "out": ASSETS_SCENARIOS / "battle_conditional_opcodes.json",
        "provenance": (
            "seeded from FFTPatcher EntryEdit/EntryData/PSX/BattleConditionalCommands.xml; "
            "OWNED here. 2-byte opcodes (BTLEVT.BIN, RAM 0x80049A18). Authored RE — "
            "verified against the ROM per-opcode as we go (`verified` flag)."
        ),
        "handlers": BC_HANDLERS,
        "provisional": BC_PROVISIONAL,
        "verified_no_handler": set(),
    },
}


def _transcribe_core(xml_path: Path) -> tuple[int, dict[int, dict]]:
    """Parse the vendored XML into {opcode_int: {name, params}}; the *core*
    that must stay a byte-for-byte transcription. Returns (opcode_width, core)."""
    root = ET.parse(xml_path).getroot()
    width = int(root.attrib.get("bytes", "1"))
    core: dict[int, dict] = {}
    for cmd in root.findall("Command"):
        op = int(cmd.attrib["hex"], 16)
        params = []
        for p in cmd.findall("Parameter"):
            param = {"name": p.attrib.get("name", "Unknown"),
                     "bytes": int(p.attrib["bytes"])}
            # Preserve type/mode — _fft_bytecode carries them into the records
            # (parse_scenarios Camera rewrites, unit-id type="Unit", etc.).
            if p.attrib.get("type"):
                param["type"] = p.attrib["type"]
            if p.attrib.get("mode"):
                param["mode"] = p.attrib["mode"]
            params.append(param)
        core[op] = {"name": cmd.attrib.get("name", "Unknown"), "params": params}
    return width, core


def build_catalog(cfg: dict) -> dict:
    """Full owned catalog = XML core + authored verified/handler/notes overlay."""
    width, core = _transcribe_core(cfg["xml"])
    handlers = cfg["handlers"]
    provisional = cfg["provisional"]
    opcodes: dict[str, dict] = {}
    for op in sorted(core):
        entry = {"name": core[op]["name"], "params": core[op]["params"]}
        if op in handlers:
            entry["verified"] = True
            # `handler: None` = statically confirmed, but the confirmation is not
            # an address of its own. {77} is the case: it re-labels the task {76}
            # already spawned (kind 0x37 -> 0x36) rather than entering a handler.
            if handlers[op]["handler"] is not None:
                entry["handler"] = handlers[op]["handler"]
            entry["notes"] = handlers[op]["notes"]
        elif op in provisional:
            entry["verified"] = False
            entry["handler"] = provisional[op]["handler"]
            entry["notes"] = provisional[op]["notes"]
        elif op in cfg.get("verified_no_handler", ()):
            entry["verified"] = True
        else:
            entry["verified"] = False
        opcodes[f"0x{op:0{width * 2}X}"] = entry
    return {
        "_provenance": cfg["provenance"],
        "_opcode_width": width,
        "opcodes": opcodes,
    }


def _render(catalog: dict) -> str:
    return json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"


def render_opcode_enum_gd(catalog: dict, spec: dict) -> str:
    """Render a generated GDScript dispatch enum from a catalog dict (the
    build_catalog() shape) per an ENUM_OUTPUTS `spec`. Member = Option-A slug,
    value = opcode (byte or 2-byte per the catalog's `_opcode_width`)."""
    width = catalog["_opcode_width"]
    names_by_op = {int(h, 16): e["name"] for h, e in catalog["opcodes"].items()}
    members = event_enum_members(names_by_op, width=width)
    lines = [
        "# THIS FILE IS GENERATED -- DO NOT EDIT.",
        f"# Source of truth: assets/scenarios/{spec['source']}",
        "# Regenerate: uv run python tools/gen_opcode_catalog.py",
        "#",
        *spec["doc"],
        f"class_name {spec['class_name']}",
        "extends RefCounted",
        "",
        "enum {",
    ]
    for op in sorted(members):
        lines.append(f"\t{members[op]} = 0x{op:0{width * 2}X},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def _core_of(catalog: dict) -> dict:
    """Strip the authored overlay so --check compares only the XML transcription."""
    width = catalog["_opcode_width"]
    out = {}
    for hex_str, entry in catalog["opcodes"].items():
        op = int(hex_str, 16)
        out[op] = {"name": entry["name"], "params": entry["params"]}
    return width, out


def _emit_opcode_enum_gd(catalog: dict, spec: dict, *, check: bool) -> int:
    """Write (or --check) a generated dispatch enum (`spec['out']`) against its
    catalog. Returns 1 if stale under --check, else 0."""
    fresh = render_opcode_enum_gd(catalog, spec)
    out = spec["out"]
    label = spec["class_name"]
    if check:
        if not out.exists():
            print(f"STALE: {out.name} (missing)")
            return 1
        if out.read_text() != fresh:
            print(f"STALE: {out.name} drifted from {spec['source']}")
            return 1
        print(f"{out.name}: {fresh.count(' = 0x')} {label} members, "
              f"matches catalog.")
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(fresh)
    print(f"wrote {out.relative_to(TOOLS.parent)} "
          f"({fresh.count(' = 0x')} {label} members)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="Verify each committed catalog's core (name+params) still "
                         "matches the vendored XML and opcode-width; writes nothing, "
                         "exits 1 on drift.")
    args = ap.parse_args()

    rc = 0
    for key, cfg in CATALOGS.items():
        fresh = build_catalog(cfg)
        if args.check:
            if not cfg["out"].exists():
                print(f"STALE: {cfg['out'].name} (missing)")
                rc = 1
                continue
            committed = json.loads(cfg["out"].read_text())
            xml_width, xml_core = _transcribe_core(cfg["xml"])
            c_width, c_core = _core_of(committed)
            if c_width != xml_width:
                print(f"STALE: {cfg['out'].name} opcode_width {c_width} != XML {xml_width}")
                rc = 1
                continue
            if c_core != xml_core:
                missing = set(xml_core) - set(c_core)
                extra = set(c_core) - set(xml_core)
                changed = {op for op in set(xml_core) & set(c_core)
                           if c_core[op] != xml_core[op]}
                print(f"STALE: {cfg['out'].name} core drifted from "
                      f"{cfg['xml'].name}: "
                      f"missing={sorted(hex(o) for o in missing)} "
                      f"extra={sorted(hex(o) for o in extra)} "
                      f"changed={sorted(hex(o) for o in changed)}")
                rc = 1
                continue
            # The core check above compares ONLY name+params against the XML,
            # which is structurally blind to the authored overlay (`verified`,
            # `handler`, `notes`) — and that overlay is exactly what gets
            # hand-added to the committed JSON and then silently DELETED by the
            # next regeneration. It has happened twice: eleven entries recovered
            # 2026-08-22, four more (0x68/0x76/0x77/0x78) on 2026-09-11, with
            # this guard green through both. So also assert the whole file is
            # what the generator would write.
            if committed != fresh:
                c_ops, f_ops = committed["opcodes"], fresh["opcodes"]
                drifted = sorted(k for k in set(c_ops) | set(f_ops)
                                 if c_ops.get(k) != f_ops.get(k))
                print(f"STALE: {cfg['out'].name} overlay drifted from this "
                      f"generator on {len(drifted)} opcode(s): "
                      f"{', '.join(drifted)}")
                for k in drifted:
                    ce, fe = c_ops.get(k, {}), f_ops.get(k, {})
                    for field in ("verified", "handler", "notes"):
                        if ce.get(field) != fe.get(field):
                            print(f"  {k} {field}: committed="
                                  f"{str(ce.get(field))[:60]!r} generator="
                                  f"{str(fe.get(field))[:60]!r}")
                print("  If the committed value is the RIGHT one, fold it into "
                      "EVENT_HANDLERS / EVENT_PROVISIONAL rather than editing "
                      "the JSON — the JSON is generated output.")
                rc = 1
                continue
            print(f"{cfg['out'].name}: {len(committed['opcodes'])} opcodes, "
                  f"core matches {cfg['xml'].name}, overlay matches this generator.")
            if key in ENUM_OUTPUTS:
                rc |= _emit_opcode_enum_gd(fresh, ENUM_OUTPUTS[key], check=True)
        else:
            cfg["out"].parent.mkdir(parents=True, exist_ok=True)
            cfg["out"].write_text(_render(fresh))
            print(f"wrote {cfg['out'].relative_to(TOOLS.parent)} "
                  f"({len(fresh['opcodes'])} opcodes)")
            if key in ENUM_OUTPUTS:
                _emit_opcode_enum_gd(fresh, ENUM_OUTPUTS[key], check=False)

    if args.check and rc:
        print("Run: uv run python tools/gen_opcode_catalog.py")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
