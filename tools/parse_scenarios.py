#!/usr/bin/env python3
"""
FFT Scenario Parser

Extracts the scenario table from EVENT/ATTACK.OUT — the join-row that ties a
map, a song, and a unit deployment into one playable battle. A *scenario* is
the entry point for an encounter; the map is one of its fields (see
CONTEXT.md "Scenario", ADR-0029). It is NOT the FFT "event" (the cutscene
script the scenario's `event_script_id` points at).

Source layout authority: ffhacktics.com/wiki/ATTACK.OUT (cross-checked
against TacticsTemplateG's attack_out_data.gd). Each record is 24 bytes;
the table holds 0x1EA (490) records starting at file offset 0x10938.

Outputs:
- assets/scenarios/scenarios.json: the scenario table, keyed by scenario_id
  (committed extracted artifact — pure-derived from ATTACK.OUT + this source).

Usage:
    uv run python tools/parse_scenarios.py
    uv run python tools/parse_scenarios.py --attack-out /path/to/ATTACK.OUT
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass, asdict
from pathlib import Path

from _repo_paths import almanac_dir as _almanac_dir
from _repo_paths import attack_out as _attack_out

ASSETS = Path(__file__).parent.parent / "assets"
DEFAULT_OUTPUT_DIR = ASSETS / "scenarios"

# Hand-authored wiki label tables (FFTorama, via FFTPatcher EntryEdit). These
# are extractor-side inputs — the parser joins them into the flat scenario
# artifact, the same way parse_abilities bakes names into effects.json. The
# label JSONs are the source of truth; the names baked below regenerate from
# them. (CONTEXT.md "Hand-authored data asset".)
# Co-located under assets/scenarios/ (a tracked dir) — assets/maps and
# assets/music are gitignored regenerable bulk, so the hand-authored label
# tables can't live there. The scenario parser is their only consumer today.
LABEL_FILES = {
    "scenario": ASSETS / "scenarios" / "scenario_names.json",
    "map": ASSETS / "scenarios" / "map_names.json",
    "music": ASSETS / "scenarios" / "music_names.json",
}


def _load_labels(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8")).get("names", {})

# =============================================================================
# ATTACK.OUT scenario-table layout (authority: ffhacktics wiki)
# =============================================================================

SCENARIO_TABLE_OFFSET = 0x10938   # file offset of the first scenario record
SCENARIO_COUNT = 0x1EA            # 490 records
SCENARIO_STRIDE = 24              # bytes per record

# -- enum label tables (hand-authored wiki knowledge; decode at extraction,
#    per ADR-0013 — runtime never carries the byte conventions) --------------

# Weather byte (0x03). These are the SCENARIO-side names and do NOT line up
# label-for-label with the GNS map-state enum (map_resource.py), which has an
# extra NoneAlt slot at index 1 — so the two are OFFSET, not mirrors. The engine
# matches by RAW INT: the scenario weather byte is used directly as the GNS
# weather index (verified static+live, 2026-07-02: weather_raw=2 → GNS index-2
# = Light). So `weather_raw` is authoritative; these names are informational.
# Real data also shows 0x04, 0x10, 0x20 — likely a type/bitfield component not
# yet reverse-engineered; those decode to "Unknown_N". (Deferred.)
WEATHER_NAMES = {
    0: "None",
    1: "Normal",
    2: "Strong",
    3: "VeryStrong",
}

# successor_raw (0x14): which SOURCE names the next scenario. NOT a destination --
# the byte cannot express anything the scene does on its way out (see CONTEXT.md
# "Campaign spine" -> Successor / Scene-out, and tools/scene_out_census.py).
SUCCESSOR_NAMES = {
    0x00: "none",          # not a group's last member
    0x80: "world-map",
    0x81: "next-scenario",
    0x82: "reset",
}

# PRODUCER DUALITY — RESOLVED (ADR-0057, #141): this module is NOT the scenario-
# chunk producer and carries NO chunk flip logic. It emits scenarios.json (the
# ATTACK.OUT map/ENTD/music metadata) only. The authoritative chunk producer is
# tools/extract_event.py (batched by tools/export_all_scenario_chunks.py): it
# now bakes the ADR-0052 depth mirror onto placement Event-Y rows at parse time
# (extract_event._flip_placement_rows), like every other Placement, emitting the
# Godot-native consumed chunk + a raw byte-faithful .raw.json sidecar. The old
# dormant parse-time helpers here (flip_camera_y_q88 / apply_chirality_fix_to_chunk)
# were never wired and are long removed. The runtime consume-boundary flip
# (ScenarioVM._flip_depth_row) is likewise gone — no Placement stays flipped at
# runtime. See docs/adr/0057-*.md, docs/adr/0052-*.md.


@dataclass
class Scenario:
    """One ATTACK.OUT scenario record (24 bytes). A pure join row: every heavy
    asset it names (map, song, units) lives elsewhere and is referenced by id."""

    index: int                # table position 0..489 (stable, index-based xrefs)
    scenario_id: int          # 0x00 u16
    map_id: int               # 0x02 u8  → assets/maps/MAP{map_id:03d}/
    weather: str              # 0x03 u8  → WEATHER_NAMES
    weather_raw: int          # 0x03 raw (kept when the name table has no entry)
    is_nighttime: bool        # 0x04 u8  (==1)
    music_file_one_id: int    # 0x05 u8  → assets/music/MUSIC_{id:02d}.SMD
    music_file_two_id: int    # 0x06 u8  alternate song
    entd_idx: int             # 0x07 u16 → ENTD unit-deployment table (future parser)
    first_squad_deployment_idx: int   # 0x09 u16
    second_squad_deployment_idx: int  # 0x0B u16
    flags: int                # 0x11 u8  (0x01 = Ramza mandatory)
    ramza_mandatory: bool     # decoded flags bit 0
    next_scenario_id: int     # 0x12 u16
    successor_raw: int   # 0x14 u8  raw
    successor: str        # 0x14 → SUCCESSOR_NAMES (or "Unknown_0xNN")
    battle_conditionals_id: int  # 0x16 u16 → BattleConditionals set index (FFTPatcher
                              #            PatchHelper: ScenariosRAM + id*24 + 22).
                              #            (TacticsG called this "event_script_id".)


def parse_scenario(record: bytes, index: int) -> Scenario:
    """Decode one 24-byte scenario record."""
    assert len(record) == SCENARIO_STRIDE, f"bad record length {len(record)}"

    def u8(o: int) -> int:
        return record[o]

    def u16(o: int) -> int:
        return struct.unpack_from("<H", record, o)[0]

    weather_raw = u8(0x03)
    flags = u8(0x11)
    post_raw = u8(0x14)

    return Scenario(
        index=index,
        scenario_id=u16(0x00),
        map_id=u8(0x02),
        weather=WEATHER_NAMES.get(weather_raw, f"Unknown_{weather_raw}"),
        weather_raw=weather_raw,
        is_nighttime=u8(0x04) == 1,
        music_file_one_id=u8(0x05),
        music_file_two_id=u8(0x06),
        entd_idx=u16(0x07),
        first_squad_deployment_idx=u16(0x09),
        second_squad_deployment_idx=u16(0x0B),
        flags=flags,
        ramza_mandatory=bool(flags & 0x01),
        next_scenario_id=u16(0x12),
        successor_raw=post_raw,
        successor=SUCCESSOR_NAMES.get(post_raw, f"unknown_0x{post_raw:02X}"),
        battle_conditionals_id=u16(0x16),
    )


def parse_all(attack_out_path: Path) -> list[Scenario]:
    data = attack_out_path.read_bytes()
    end = SCENARIO_TABLE_OFFSET + SCENARIO_COUNT * SCENARIO_STRIDE
    if len(data) < end:
        raise SystemExit(
            f"ATTACK.OUT too small: {len(data)} bytes, need >= {end} "
            f"(table 0x{SCENARIO_TABLE_OFFSET:X} × {SCENARIO_COUNT})"
        )

    scenarios: list[Scenario] = []
    for i in range(SCENARIO_COUNT):
        start = SCENARIO_TABLE_OFFSET + i * SCENARIO_STRIDE
        record = data[start:start + SCENARIO_STRIDE]
        # The tail of the table is all-zero padding (10 records in retail FFT) —
        # not real scenarios. Skip them so scenario_id stays a unique key.
        if record == b"\x00" * SCENARIO_STRIDE:
            continue
        scenarios.append(parse_scenario(record, i))
    return scenarios


def main() -> None:
    ap = argparse.ArgumentParser(description="Parse FFT ATTACK.OUT scenario table")
    ap.add_argument("--attack-out", type=Path, default=None,
                    help="path to EVENT/ATTACK.OUT (default: project-assets extract)")
    ap.add_argument("--out", type=Path, default=_almanac_dir("encounters/scenarios.json"),
                    help="output JSON path")
    args = ap.parse_args()

    src = args.attack_out or _attack_out()
    if not src.exists():
        raise SystemExit(f"ATTACK.OUT not found: {src}")

    scenarios = parse_all(src)

    # Hand-authored wiki labels, joined in (see LABEL_FILES).
    scen_names = _load_labels(LABEL_FILES["scenario"])
    map_names = _load_labels(LABEL_FILES["map"])
    music_names = _load_labels(LABEL_FILES["music"])

    def music_name(mid: int) -> str:
        return music_names.get(str(mid), "") if mid else "(none)"

    # Keyed by scenario_id (string keys — JSON has no int keys). Empty padding
    # is already dropped, so real scenario_ids are unique; assert it rather
    # than silently overwrite if that ever changes (e.g. a ROM hack).
    table: dict[str, dict] = {}
    for s in scenarios:
        key = str(s.scenario_id)
        if key in table:
            raise SystemExit(
                f"duplicate scenario_id {s.scenario_id} (indices "
                f"{table[key]['index']} and {s.index}) — key by index instead"
            )
        row = asdict(s)
        # Wiki labels (regenerable from the *_names.json sources).
        row["scenario_name"] = scen_names.get(key, "")
        row["map_name"] = map_names.get(str(s.map_id), "")
        row["music_one_name"] = music_name(s.music_file_one_id)
        row["music_two_name"] = music_name(s.music_file_two_id)
        table[key] = row

    payload = {
        "_source": "EVENT/ATTACK.OUT scenario table",
        "_layout": {
            "offset": SCENARIO_TABLE_OFFSET,
            "count": SCENARIO_COUNT,
            "stride": SCENARIO_STRIDE,
        },
        "scenarios": table,
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent="\t") + "\n")

    # Quick sanity summary.
    maps = sorted({s.map_id for s in scenarios})
    songs = sorted({s.music_file_one_id for s in scenarios})
    print(f"Parsed {len(scenarios)} scenarios from {src}")
    print(f"  distinct map_ids:  {len(maps)} (range {maps[0]}..{maps[-1]})")
    print(f"  distinct songs:    {len(songs)} (range {songs[0]}..{songs[-1]})")
    print(f"  -> {args.out}")


if __name__ == "__main__":
    main()
