#!/usr/bin/env python3
"""build_chapel_trace_report.py — fuse static + Godot + PSX chapel traces.

Inputs (under research/working_documents/chapel_opcode_trace/):
  - static_chunk.tsv   (from dump_chapel_opcodes.py): per-PC opcode + decoded
                       params + which units it acts on + what should change.
  - godot_run.jsonl    (from ScenarioVM chapel-trace mode): per-PC snapshot of
                       every spawned unit (facing cardinal + 12-bit, type1
                       anim_id/frame, last painted frame, cinematic walker).
  - pcsx_run.jsonl     (from run_chapel_capture.py): per-slot state-change events
                       from PSX RAM — one row per slot whenever its facing or
                       current_anim_slot changed. Sparse, timestamped in vsync
                       units since probe-arm.

Outputs:
  - report.md          — per-PC side-by-side table for a chosen PC range.
                         Each row: static expectation, Godot unit state,
                         the nearest PSX state for the targeted slot.

Slot↔chunk_unit_id mapping is inferred automatically by matching cinematic
Unit Anim events: when the static chunk says "Unit Anim Units=12 Animation=605
(=0x25D)", whichever PSX slot wrote anim=0x025D around the same time wins
that uid. This works because cinematic anim IDs (0x1F4..0x297) are
chunk-unit-specific and stable, while the `+0x161` ENTD-uid byte we'd
prefer to use is empty in the orbonne_prayer_pre_scenario_load savestate.

Alignment between Godot's PC axis and PSX's vsync axis is approximate: we
walk PSX's anim-change events in the same order the static chunk requests
them (cinematic anim opcodes only), assign each event the matching PC,
then linearly interpolate vsync→pc for non-cinematic rows. This is rough
but good enough to flag "PSX rotated unit X at the right place but Godot
did not."
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TRACE_DIR = REPO / "research/working_documents/chapel_opcode_trace"
DEFAULT_STATIC = TRACE_DIR / "static_chunk.tsv"
DEFAULT_GODOT = TRACE_DIR / "godot_run.jsonl"
DEFAULT_PCSX = TRACE_DIR / "pcsx_run.jsonl"
DEFAULT_REPORT = TRACE_DIR / "report.md"

CARDINAL_FROM_12BIT = {0x000: "S", 0x400: "E", 0x800: "W", 0xC00: "N"}

# Godot's facing enum (current source of truth: `ExMateriaSchema.Facing.Direction`
# in addons/exmateria_schema/unit_vocabulary/Facing.gd, ADR-0217 dec. 7 — the snap
# itself stays in AnimationStateController.gd). Indexed by the integer enum value.
GODOT_CARDINAL_NAMES = ["N", "E", "S", "W"]

# Maps PSX `pose_idx = (angle >> 10) & 3` → the cardinal LABEL Godot's
# current angle_12bit_to_facing assigns at the byte anchors 0x0/0x4/0x8/0xC.
# Use it to expose any per-anchor LABEL mismatch independently of the
# half-sector boundary mismatch this report is hunting.
PSX_POSE_TO_GODOT_CARDINAL = {0: "S", 1: "E", 2: "W", 3: "N"}


def cardinal_from_12bit(angle: int) -> str:
    a = angle & 0xFFF
    nearest = min(CARDINAL_FROM_12BIT, key=lambda k: min(abs(a - k), 0x1000 - abs(a - k)))
    base = CARDINAL_FROM_12BIT[nearest]
    diff = a - nearest
    if diff == 0:
        return base
    return f"{base}{diff:+#x}"


def load_static(path: Path) -> list[dict]:
    rows = []
    with open(path) as f:
        rdr = csv.DictReader(f, delimiter="\t")
        for r in rdr:
            r["pc"] = int(r["pc"])
            rows.append(r)
    return rows


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def infer_slot_to_uid(static_rows: list[dict], pcsx_rows: list[dict]) -> dict[int, int]:
    """Infer slot_idx → chunk_unit_id by matching cinematic Unit Anim events.

    The static chunk emits cinematic Unit Anims like
        Unit Anim Units=12, Animation=605
    Animation 605 (=0x25D) is in the cinematic range 0x258..0x297. PSX
    writes that exact value to one slot's +0x0C. The first PCSX slot we
    see write the matching anim wins that uid.
    """
    slot_to_uid: dict[int, int] = {}
    uid_to_slot: dict[int, int] = {}

    cinematic_requests: list[tuple[int, int]] = []  # (uid, anim_id)
    for r in static_rows:
        if r["opcode"] != "Unit Anim":
            continue
        try:
            anim = int(r["params"].split("Animation=")[1].split()[0])
        except (IndexError, ValueError):
            continue
        if not (0x1F4 <= anim < 0x298):
            continue
        uid_field = r["target_units"]
        if uid_field == "-":
            continue
        try:
            uid = int(uid_field.split(",")[0].strip(), 0)
        except ValueError:
            continue
        cinematic_requests.append((uid, anim))

    # Walk PSX rows chronologically; consume each cinematic-anim write to fill
    # the slot↔uid map.
    expected_idx = 0
    for r in pcsx_rows:
        try:
            anim = int(r["anim"], 16)
        except (KeyError, ValueError):
            continue
        if anim == 0 or not (0x1F4 <= anim < 0x298):
            continue
        slot = r["slot"]
        if slot in slot_to_uid:
            continue
        # Find the first un-consumed request matching this anim.
        for i in range(expected_idx, len(cinematic_requests)):
            uid, want = cinematic_requests[i]
            if want == anim and uid not in uid_to_slot:
                slot_to_uid[slot] = uid
                uid_to_slot[uid] = slot
                expected_idx = i + 1
                break

    return slot_to_uid


def map_slot_to_uid_with_overrides(slot_to_uid: dict[int, int]) -> dict[int, int]:
    """Manual override hook — extend automatic cinematic-match mapping with
    behavioral hints for units the auto-pass missed.

    slot 0 → 0x13 (Simon): in the chapel run, slot 0 starts at facing 0xC00
    and runs a multi-step rotation cascade (0xC00→0xD00→…→0x200 → back),
    which lines up with `pc 97 Rotate Unit Units=19 Facing=2 Direction=1`
    (Facing=2 = North in FFT's 0=S/1=W/2=N/3=E convention). 0x13 is the
    only chunk_unit_id with a `Rotate Unit` event near in time to Agrias'
    rotation, so the assignment is unambiguous.
    """
    extended = dict(slot_to_uid)
    if 0 not in extended:
        extended[0] = 0x13
    return extended


def build_pcsx_slot_index(pcsx_rows: list[dict]) -> dict[int, list[dict]]:
    by_slot: dict[int, list[dict]] = {}
    for r in pcsx_rows:
        by_slot.setdefault(r["slot"], []).append(r)
    for slot in by_slot:
        by_slot[slot].sort(key=lambda r: r["vs"])
    return by_slot


def pcsx_state_for_slot_at_pc(slot_rows: list[dict], vs_at_pc: int) -> dict | None:
    """Return the slot row whose vs is the largest ≤ vs_at_pc (latest state
    on or before that virtual PC time). None if no row qualifies."""
    last = None
    for r in slot_rows:
        if r["vs"] > vs_at_pc:
            break
        last = r
    return last


def build_pc_to_vs_map(static_rows: list[dict], pcsx_rows: list[dict],
                       slot_to_uid: dict[int, int]) -> dict[int, int]:
    """Approximate per-PC vsync timestamps by anchoring on cinematic anim
    events the static chunk asks for. PCs between anchors interpolate."""
    uid_to_slot = {u: s for s, u in slot_to_uid.items()}
    by_slot = build_pcsx_slot_index(pcsx_rows)

    anchors: list[tuple[int, int]] = []  # (pc, vs)
    for r in static_rows:
        if r["opcode"] != "Unit Anim":
            continue
        try:
            anim = int(r["params"].split("Animation=")[1].split()[0])
        except (IndexError, ValueError):
            continue
        if not (0x1F4 <= anim < 0x298):
            continue
        uid_field = r["target_units"]
        try:
            uid = int(uid_field.split(",")[0].strip(), 0)
        except ValueError:
            continue
        slot = uid_to_slot.get(uid)
        if slot is None or slot not in by_slot:
            continue
        # Find the FIRST PSX row for this slot that wrote this anim_id and
        # comes after any prior anchor.
        prev_vs = anchors[-1][1] if anchors else -1
        for ps in by_slot[slot]:
            if ps["vs"] <= prev_vs:
                continue
            try:
                if int(ps["anim"], 16) == anim:
                    anchors.append((r["pc"], ps["vs"]))
                    break
            except ValueError:
                continue

    if not anchors:
        return {}

    # Linear-interpolate between anchors; clamp PCs before the first anchor to
    # 0 vsync, PCs after the last anchor stay at the last anchor's vsync.
    pc_to_vs: dict[int, int] = {}
    n = len(static_rows)
    for i in range(n):
        pc = static_rows[i]["pc"]
        if pc < anchors[0][0]:
            pc_to_vs[pc] = max(anchors[0][1] - (anchors[0][0] - pc), 0)
            continue
        if pc >= anchors[-1][0]:
            pc_to_vs[pc] = anchors[-1][1]
            continue
        for j in range(len(anchors) - 1):
            pc_a, vs_a = anchors[j]
            pc_b, vs_b = anchors[j + 1]
            if pc_a <= pc < pc_b:
                t = (pc - pc_a) / max(pc_b - pc_a, 1)
                pc_to_vs[pc] = int(vs_a + t * (vs_b - vs_a))
                break
    return pc_to_vs


def render_report(args, static_rows, godot_rows, pcsx_rows,
                  slot_to_uid, pc_to_vs) -> str:
    by_slot = build_pcsx_slot_index(pcsx_rows)
    godot_by_pc = {r["pc"]: r for r in godot_rows}
    uid_to_slot = {u: s for s, u in slot_to_uid.items()}

    lines: list[str] = []
    lines.append("# Chapel Cinematic Opcode Trace")
    lines.append("")
    lines.append(f"PC range: **{args.pc_start}–{args.pc_end - 1}** "
                 f"of {len(static_rows)} total opcodes in scenario_1_chunk.")
    lines.append("")
    lines.append("Sources:")
    lines.append(f"- static: `{DEFAULT_STATIC.relative_to(REPO)}`")
    lines.append(f"- godot:  `{DEFAULT_GODOT.relative_to(REPO)}` "
                 f"({len(godot_rows)} rows)")
    lines.append(f"- pcsx:   `{DEFAULT_PCSX.relative_to(REPO)}` "
                 f"({len(pcsx_rows)} state-change rows)")
    lines.append("")

    lines.append("## Slot ↔ chunk_unit_id (inferred from cinematic Unit Anim writes)")
    lines.append("")
    lines.append("| PSX slot | chunk_unit_id |")
    lines.append("|---|---|")
    for slot in sorted(slot_to_uid):
        lines.append(f"| {slot} | 0x{slot_to_uid[slot]:02X} ({slot_to_uid[slot]}) |")
    lines.append("")
    if pc_to_vs:
        lines.append(f"PC→vs anchors used: {len(set(pc_to_vs.values()))} distinct vsync points.")
        lines.append("")

    lines.append("## Per-PC diff")
    lines.append("")
    lines.append("Columns: **PC** • **opcode (params)** • **static expectation** • "
                 "**Godot post-state for target unit(s)** • "
                 "**PCSX state for the same slot at the nearest vsync** • "
                 "**Pose** (cardinal LABEL Godot picked / cardinal LABEL PSX truncate "
                 "would pick — flags when half-sector mismatch flips the pose).")
    lines.append("")
    lines.append("| PC | Opcode | Targets | Static expects | Godot (target unit) | PCSX (slot for target) | Pose Godot→PSX |")
    lines.append("|---|---|---|---|---|---|---|")

    for r in static_rows:
        pc = r["pc"]
        if pc < args.pc_start or pc >= args.pc_end:
            continue

        targets_raw = r["target_units"]
        target_uids: list[int] = []
        if targets_raw and targets_raw != "-":
            for tok in targets_raw.split(","):
                tok = tok.strip()
                if not tok:
                    continue
                try:
                    target_uids.append(int(tok, 0))
                except ValueError:
                    pass

        godot_state = "—"
        godot_pose_by_uid: dict[int, dict] = {}
        gr = godot_by_pc.get(pc)
        if gr is not None and target_uids:
            cells = []
            for uid in target_uids:
                u = next((u for u in gr["units"] if u["uid"] == uid), None)
                if u is None:
                    cells.append(f"0x{uid:02X}: (not spawned)")
                else:
                    f = u["facing"]
                    angle = f.get("angle_12bit", -1)
                    # Show precise 12-bit angle when scenario_rotate set it
                    # (post a Rotate Unit). Cardinal-derived rows just show
                    # the cardinal name — adding 0x000/0x400/0x800/0xC00
                    # there would be noise.
                    if f.get("angle_source") == "scenario_rotate" and angle >= 0:
                        facing_str = f"{f['cardinal_name']}(0x{angle:03X})"
                    else:
                        facing_str = f["cardinal_name"]
                    t1 = u.get("type1", {})
                    cin = u.get("cinematic", {})
                    sp = u.get("sprite_pose", {})
                    vis = "vis" if u.get("visible") else "hid"
                    line = f"0x{uid:02X}: {vis} {facing_str} a={t1.get('anim_id','?')} fr={t1.get('anim_frame','?')}"
                    if cin.get("active"):
                        line += f" cin(fb=0x{cin.get('last_fb', -1):02X})"
                    if sp:
                        line += f" cam_q{sp.get('camera_quad','?')}"
                        line += "/B" if sp.get("use_back") else "/F"
                        if sp.get("revert"):
                            line += "/flip"
                    cells.append(line)
                    godot_pose_by_uid[uid] = {
                        "angle_12bit": angle,
                        "cardinal_name": f.get("cardinal_name", "?"),
                        "pose_idx": f.get("pose_idx", -1),
                    }
            godot_state = "<br>".join(cells)

        psx_state = "—"
        psx_pose_by_uid: dict[int, dict] = {}
        if target_uids and pc in pc_to_vs:
            vs_at_pc = pc_to_vs[pc]
            cells = []
            for uid in target_uids:
                slot = uid_to_slot.get(uid)
                if slot is None or slot not in by_slot:
                    cells.append(f"0x{uid:02X}: (no slot mapped)")
                    continue
                ps = pcsx_state_for_slot_at_pc(by_slot[slot], vs_at_pc)
                if ps is None:
                    cells.append(f"0x{uid:02X}: (no row ≤ vs={vs_at_pc})")
                else:
                    fac = ps["facing"]
                    fac12 = fac & 0xFFF
                    card = cardinal_from_12bit(fac if fac >= 0 else fac + 0x10000)
                    # Recompute pose_idx in case an older probe-run lacks the
                    # field (back-compat with pre-pose-column captures).
                    pose_idx = int(ps.get("pose_idx", (fac12 >> 10) & 0x3))
                    pose_b = ps.get("pose_b", "")
                    extra = f" pose={pose_idx}"
                    if pose_b:
                        extra += f"/{pose_b}"
                    cells.append(
                        f"0x{uid:02X} slot{slot}: {card} (0x{fac12:03X}) "
                        f"anim=0x{ps['anim']}{extra} @vs={ps['vs']}"
                    )
                    psx_pose_by_uid[uid] = {
                        "facing": fac12,
                        "pose_idx": pose_idx,
                    }
            psx_state = "<br>".join(cells)

        pose_cells = []
        for uid in target_uids:
            g = godot_pose_by_uid.get(uid)
            p = psx_pose_by_uid.get(uid)
            if g is None or p is None:
                continue
            godot_label = g["cardinal_name"][:1] if g["cardinal_name"] else "?"
            psx_label = PSX_POSE_TO_GODOT_CARDINAL.get(p["pose_idx"], "?")
            mark = "" if godot_label == psx_label else " ⚠"
            pose_cells.append(
                f"0x{uid:02X}: {godot_label}→{psx_label}"
                f" (g_byte=0x{g['angle_12bit']:03X}, p_byte=0x{p['facing']:03X}){mark}"
            )
        pose_state = "<br>".join(pose_cells) if pose_cells else "—"

        opcode_cell = r["opcode"]
        params_cell = r["params"][:80] if r["params"] else ""
        if params_cell:
            opcode_cell = f"{opcode_cell}<br>`{params_cell}`"

        expect = r["expected_change"]
        if len(expect) > 110:
            expect = expect[:107] + "…"

        lines.append(f"| {pc} | {opcode_cell} | {targets_raw} | {expect} | {godot_state} | {psx_state} | {pose_state} |")

    lines.append("")
    lines.append("## How to read")
    lines.append("")
    lines.append("- **Godot column** is the post-state right after that opcode dispatched.")
    lines.append("- **PCSX column** is the latest PSX RAM state on or before the inferred vsync for that PC. Sparse — only changes are captured, so a row can show 'no change since vs=X'.")
    lines.append("- The PC↔vsync alignment anchors on cinematic Unit Anim writes; non-cinematic opcodes between anchors interpolate. If the Godot row says facing=EAST and the PCSX row says facing=N(0xC00), that's a real divergence regardless of timing slop.")
    lines.append("- **Pose column** shows the cardinal LABEL Godot's center-snap picked (`angle_12bit_to_facing`) on the left, and the cardinal LABEL PSX's truncate (`(angle>>10)&3`) would pick on the right. They match when the byte is in a center-aligned ±0x200 window of an anchor (0x0/0x4/0x8/0xC) AND in the PSX truncate sector for that same anchor. They diverge (⚠) when the byte sits in a half-sector PSX assigns differently — that's the sprite-pose vs arrow desync the rewrite needs to fix.")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pc-start", type=int, default=0)
    ap.add_argument("--pc-end", type=int, default=200)
    ap.add_argument("--static", type=Path, default=DEFAULT_STATIC)
    ap.add_argument("--godot", type=Path, default=DEFAULT_GODOT)
    ap.add_argument("--pcsx", type=Path, default=DEFAULT_PCSX)
    ap.add_argument("--out", type=Path, default=DEFAULT_REPORT)
    args = ap.parse_args()

    static_rows = load_static(args.static)
    godot_rows = load_jsonl(args.godot)
    pcsx_rows = load_jsonl(args.pcsx)

    slot_to_uid = infer_slot_to_uid(static_rows, pcsx_rows)
    slot_to_uid = map_slot_to_uid_with_overrides(slot_to_uid)
    pc_to_vs = build_pc_to_vs_map(static_rows, pcsx_rows, slot_to_uid)

    report = render_report(args, static_rows, godot_rows, pcsx_rows,
                           slot_to_uid, pc_to_vs)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(report + "\n")
    print(f"wrote {args.out}", file=sys.stderr)
    print(f"  slot↔uid map: {slot_to_uid}", file=sys.stderr)
    print(f"  pc→vs anchors: {len(set(pc_to_vs.values()))}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
