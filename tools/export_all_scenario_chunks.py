"""Batch-export every TEST.EVT event as a ScenarioVM chunk JSON.

Reads TEST.EVT once and disassembles each of the 500 events, writing
``assets/scenarios/chunks/scenario_%03d_chunk.json`` (text baked, matching the
RAM-sourced shape the ScenarioPlayer's default cinematic uses).

The event index == the canonical scenario id (the ScenarioDatabase key / the
BC opcode 0x0019 Run Scenario operand / current_scenario_id at 0x8016A014), so
the F3 scenario picker resolves a chunk purely from the selected id:
``chunks/scenario_%03d_chunk.json``.

``scenario_1_chunk.json`` (= the cinematic = event 2, misnamed: scenario 1 is
the Setup) is ALSO written here, as a byte-identical copy of
``chunks/scenario_002_chunk.json``. It stays committed because ``chunks/`` is
gitignored at 212 MiB and `ScenarioPlayerScene.DEFAULT_CHUNK_FALLBACK` needs
the default cinematic to play on a fresh clone; 16 test files pin that path and
hardcode instruction indices against it. Writing it here rather than leaving it
alone is the point: this docstring used to CLAIM the two were byte-identical
while the flat file was a stale hand-export, 8 opcode names and 6 param name
lists behind (``Unknown`` where the catalogue now resolves ``End Sound`` /
``Set Unit Event Hold`` / ``Camera Speed Curve``). Now the claim holds by
construction. Opcodes and instruction COUNT were never affected, so the pinned
indices are stable.

``scenario_0001_setup_chunk.json`` (event 1) was deleted, not regenerated: no
scene, script or test ever read it, and it was a command-only export whose text
region had been scrubbed to zeros, so the walker disassembled the padding. Its
2,737 instructions were 7 real ones — ending at ``Event End`` (0xDB) — plus
2,730 phantoms, 1,253 of them ``Unknown``. Event 1's real script is those 7.

Usage:
    uv run python tools/export_all_scenario_chunks.py
"""

from __future__ import annotations

import json
from pathlib import Path

import _repo_paths as rp
from _repo_paths import event_dir
from extract_event import list_events, read_event, to_chunk_json

# Event 2 is the chapel cinematic `ScenarioPlayerScene` boots by default, and its
# chunk is committed under this legacy flat name as the fresh-clone fallback.
LEGACY_CINEMATIC_EVENT = 2
LEGACY_CINEMATIC_NAME = "scenario_1_chunk.json"
LEGACY_CINEMATIC_RAW_NAME = "scenario_1_chunk.raw.json"


def _scenario_id_to_size_z() -> dict[int, int]:
    """Map scenario_id -> its map's depth in tiles (PSX size_z), so each chunk
    can be pre-flipped with the SAME size_z the runtime resolves from the
    scenario's map (ADR-0057). The chunk file index == scenario_id == event
    index in this pipeline (chunks/scenario_%03d_chunk.json), so we key by that.
    Missing map assets (gitignored) simply leave that chunk raw."""
    scenarios = json.loads(
        (rp.almanac_dir("encounters/scenarios.json")).read_text()   # ADR-0251 dec. 2
    )["scenarios"]
    size_z_by_map: dict[int, int] = {}
    out: dict[int, int] = {}
    for sid, sc in scenarios.items():
        map_id = int(sc["map_id"])
        if map_id not in size_z_by_map:
            terrain = rp.assets_dir("maps/MAP%03d/terrain.json" % map_id)
            if not terrain.exists():
                continue
            size_z_by_map[map_id] = int(
                json.loads(terrain.read_text())["terrain"]["size_z"]
            )
        if map_id in size_z_by_map:
            out[int(sid)] = size_z_by_map[map_id]
    return out


def main() -> int:
    in_path = event_dir() / "TEST.EVT"
    out_dir = (
        Path(__file__).resolve().parent.parent
        / "assets" / "scenarios" / "chunks"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    size_z_by_scenario = _scenario_id_to_size_z()

    wrote = 0
    empty = 0
    no_size_z = 0
    total_bytes = 0
    for idx in list_events(in_path):
        ev = read_event(in_path, idx)
        # The chunk file index == scenario_id (the runtime loads
        # chunks/scenario_%03d_chunk.json by scenario id), so pre-flip with that
        # scenario's map size_z (ADR-0057). Events with no matching scenario /
        # missing map asset stay raw.
        size_z = size_z_by_scenario.get(idx)
        if size_z is None:
            no_size_z += 1

        # Prefer the text-baked shape (dialogue resolves for Display Message).
        # A handful of events have malformed / absent string tables that trip
        # the text walker — fall back to the command-only shape rather than
        # dropping the whole event.
        def build(size_z_arg):
            try:
                return to_chunk_json(
                    ev, source_label=f"TEST.EVT event {idx}", with_text=True,
                    placement_size_z=size_z_arg,
                )
            except Exception:
                return to_chunk_json(
                    ev, source_label=f"TEST.EVT event {idx}", with_text=False,
                    placement_size_z=size_z_arg,
                )

        doc = build(size_z)  # Godot-native consumed chunk (pre-flipped)
        n = len(doc["instructions"])
        if n == 0:
            empty += 1
        text = json.dumps(doc, indent=2)
        (out_dir / f"scenario_{idx:03d}_chunk.json").write_text(text)
        total_bytes += len(text)
        wrote += 1

        # Raw byte-faithful sidecar (ADR-0057 RE-diff data). Only meaningful when
        # the consumed chunk was actually flipped; skip when already raw.
        raw_text = None
        if size_z is not None:
            raw_doc = build(None)
            raw_text = json.dumps(raw_doc, indent=2)
            (out_dir / f"scenario_{idx:03d}_chunk.raw.json").write_text(raw_text)

        # The committed fresh-clone fallback is the same bytes under its legacy
        # name (see the module docstring). Written from the SAME doc so the two
        # cannot drift apart again.
        if idx == LEGACY_CINEMATIC_EVENT:
            legacy_dir = out_dir.parent
            (legacy_dir / LEGACY_CINEMATIC_NAME).write_text(text)
            if raw_text is not None:
                (legacy_dir / LEGACY_CINEMATIC_RAW_NAME).write_text(raw_text)
            print(f"  also wrote {LEGACY_CINEMATIC_NAME} (+ .raw) "
                  f"= event {idx}, the committed fresh-clone fallback")

    print(f"wrote {wrote} chunk files to {out_dir}")
    print(f"  empty (0 instructions): {empty}")
    print(f"  no size_z (left raw): {no_size_z}")
    print(f"  total size: {total_bytes / 1024 / 1024:.1f} MiB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
