#!/usr/bin/env python3
"""Extract FFT's two global SFX banks into game assets (JSON + .feds blob).

These are the battle/system sound effects that are NOT tied to a visual
effect file (E###.BIN) — the unit death cry, melee/physical hit noises,
menu/cursor blips, etc. At runtime FFT loads them off the disc into a
linked list of "feds" bank nodes (head at DAT_80032a00); the bytes are
stored verbatim on disc as two standalone files in SOUND/:

    SYSTEM.SED  -> category 0x0000, 168 sound ids (death = id 0x45)
    ENV.SED     -> category 0x0001,  27 sound ids

Both are plain `feds` blobs, the SAME opcode language as E### effect-sound
channels — only the header/table layout differs from the per-effect FEDS:

    +0x00  "feds" magic
    +0x04  u32  total size (== file size)
    +0x08  u16  entry_count (number of sound ids)
    +0x0A  u16  category_key  (sound_id >> 16 selects the bank at runtime)
    +0x0C  u32  volume/seed table offset (= 0x14 + 4*entry_count)
    +0x10  u32  next-bank pointer (0 on disc; a live pointer at runtime)
    +0x14  per-sound-id table: two u16 bytecode offsets (pair slot 0/1)

So each sound id = one playable pair (two channels = two voices). The
gain byte at volume_table[sound_id] seeds the chan+0x92 voice gain
(FedsBank.chan_92_for) — a fixed multiplier on the envelope, exactly as
for E### effects.

Output (one folder, mirroring assets/effects/E###/{feds.bin,feds.json}):

    assets/audio/sfx_banks/<name>.feds   raw bank blob (FedsBank-loadable)
    assets/audio/sfx_banks/<name>.json   decoded: per-sound-id channels+opcodes
    assets/audio/sfx_banks/index.json    bank list for the test scene

    uv run python tools/parse_sfx_banks.py

Runtime note: Godot's FedsBank parser reads the offset table as a stride-2
view starting at +0x18, so FFT sound_id N maps to FedsBank pair_idx N-1.
The decoded JSON below indexes by the real FFT sound_id and also records
pair_idx for playback. See exmateria-sound/workspace/harness/render_effect_sound.gd
(_bank_for / pair_idx = id_value - 1) and research GLOBAL_SFX_BANK_*.md.
"""
import json
import shutil
from pathlib import Path
from typing import Any, Dict, List

import parse_effect as pe
from _repo_paths import sound_dir as _sound_dir

# Input path — resolves to <repo>/project-assets/fft-extract/SOUND via shared helper.
SOUND_SRC = _sound_dir()
OUT_DIR = Path(__file__).parent.parent / "assets" / "audio" / "sfx_banks"

# (source filename, output stem, category_key, human note)
BANKS = [
    ("SYSTEM.SED", "system", 0x0000, "system/status SFX (death cry = id 0x45)"),
    ("ENV.SED", "env", 0x0001, "environment/ambient SFX"),
]

# Sound ids we can name from RE notes; everything else is left generic.
KNOWN_IDS = {
    0x0000: {0x45: "death cry"},
}


def _channel_ends(data: bytes, table: int, entry_count: int, size: int) -> List[int]:
    """All distinct nonzero bytecode offsets, sorted — used to bound channels."""
    offs = set()
    for sid in range(entry_count):
        for half in (0, 2):
            o = pe.read_u16(data, table + sid * 4 + half)
            if o:
                offs.add(o)
    return sorted(offs)


def parse_bank(data: bytes, category: int) -> Dict[str, Any]:
    if len(data) < 0x18 or data[0:4] != b"feds":
        raise ValueError("not a feds blob")
    size = pe.read_u32(data, 0x04)
    entry_count = pe.read_u16(data, 0x08)
    cat = pe.read_u16(data, 0x0A)
    voltbl_off = pe.read_u32(data, 0x0C)
    table = 0x14
    all_offs = _channel_ends(data, table, entry_count, size)
    blob_end = min(size, len(data))

    def ch_end(start: int) -> int:
        end = blob_end
        for o in all_offs:
            if o > start:
                end = o
                break
        return min(end, len(data))

    names = KNOWN_IDS.get(category, {})
    sounds: List[Dict[str, Any]] = []
    for sid in range(entry_count):
        a = pe.read_u16(data, table + sid * 4)
        b = pe.read_u16(data, table + sid * 4 + 2)
        if not a and not b:
            continue  # empty slot (sound_id 0 and a few holes)
        # Per-sound byte from the bank's volume table. Seeds the chan+0x92
        # voice gain: chan_92 = min((0x6000 * gain_byte) >> 7, 0x7FFF), a
        # fixed multiplier applied to the (Dynamics + LFO) envelope — NOT the
        # Dynamics level itself. See FedsBank.chan_92_for / compute_vol_lr.gd.
        gain = data[voltbl_off + sid] if voltbl_off + sid < len(data) else 0
        channels: List[Dict[str, Any]] = []
        for slot, off in ((0, a), (1, b)):
            if not off:
                continue
            end = ch_end(off)
            channels.append({
                "slot": slot,
                "offset": off,
                "size": max(0, end - off),
                "opcodes": pe._decode_feds_track(data[off:end]),
            })
        entry: Dict[str, Any] = {
            "sound_id": sid,
            "pair_idx": sid - 1,  # FedsBank stride-2 view: pair_idx = sound_id - 1
            "gain_byte": gain,
            "channels": channels,
        }
        if sid in names:
            entry["note"] = names[sid]
        sounds.append(entry)

    return {
        "category": cat,
        "feds_size": size,
        "entry_count": entry_count,
        "voltbl_offset": voltbl_off,
        "num_sounds": len(sounds),
        "sounds": sounds,
    }


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    index: List[Dict[str, Any]] = []
    for src_name, stem, category, note in BANKS:
        src = SOUND_SRC / src_name
        if not src.is_file():
            print(f"  {src_name}: MISSING at {src} — skipped")
            continue
        data = src.read_bytes()
        try:
            doc = parse_bank(data, category)
        except Exception as e:
            print(f"  {src_name}: ERROR — {e}")
            continue
        doc["source"] = f"SOUND/{src_name}"
        doc["name"] = stem
        doc["note"] = note

        (OUT_DIR / f"{stem}.feds").write_bytes(data)
        (OUT_DIR / f"{stem}.json").write_text(json.dumps(doc, indent=2))
        index.append({
            "name": stem,
            "category": doc["category"],
            "source": doc["source"],
            "num_sounds": doc["num_sounds"],
            "entry_count": doc["entry_count"],
            "feds": f"{stem}.feds",
            "json": f"{stem}.json",
            "note": note,
        })
        print(f"  {src_name} -> {stem}.feds + {stem}.json "
              f"(cat 0x{doc['category']:04x}, {doc['num_sounds']}/{doc['entry_count']} sounds)")

    (OUT_DIR / "index.json").write_text(json.dumps({"banks": index}, indent=2))
    print(f"SFX banks: {len(index)} written to {OUT_DIR}")


if __name__ == "__main__":
    main()
