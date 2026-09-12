#!/usr/bin/env python3
"""Add/refresh feds.bin + feds.json + sound_containers.json + sound.json in each
already-parsed effect dir.

Surgical sound-only pass: writes ONLY the effect-sound artifacts into existing
assets/effects/E###/ folders, leaving every other JSON and the textures
untouched. feds.bin / feds.json are the FEDS blob + decoded opcodes;
sound_containers.json / sound.json are the EffectSoundController's TIER-2 resolver
config + TIER-1 sound-subsystem keyframes (consumed by EffectJSONLoader).
(For a full re-extract use parse_all_effects_py.py --force, which now also
emits all four via parse_effect.)

    uv run python tools/parse_all_feds.py
"""
import json
from pathlib import Path

import parse_effect as pe
from _repo_paths import effect_dir as _effect_dir, battle_bin as _battle_bin

# Inputs resolve from the repo via _repo_paths (host-agnostic).
EFFECT_SRC = _effect_dir()
ASSETS = Path(__file__).parent.parent / "assets" / "effects"
BATTLE_BIN = _battle_bin()


def _remove_sound_files(out_dir: Path) -> None:
    """Remove any stale sound artifacts from a soundless effect dir."""
    for leftover in ("feds.bin", "feds.json", "sound_def.json",
                     "sound_config.json", "sound_containers.json",
                     "sound_tracks.json", "sound.json"):
        p = out_dir / leftover
        if p.exists():
            p.unlink()


def main() -> None:
    bins = sorted(EFFECT_SRC.glob("E*.BIN"))
    added = no_sound = missing_dir = errored = 0
    for b in bins:
        out_dir = ASSETS / b.stem
        if not out_dir.is_dir():
            missing_dir += 1
            continue
        data = b.read_bytes()
        if len(data) < 0x28:  # empty / placeholder effect slot — no header, no sound
            no_sound += 1
            _remove_sound_files(out_dir)
            continue
        try:
            vfx_id = pe.vfx_id_from_filename(b.name)
            base = pe.load_vfx_header_offset(str(BATTLE_BIN), vfx_id) if vfx_id is not None else None
            if base is None:
                base = pe.find_header_offset(data)
            header = pe.parse_header(data, base)
            doc, raw = pe.parse_feds(data, header)
        except Exception as e:
            print(f"  {b.stem}: ERROR - {e}")
            errored += 1
            continue
        if doc is not None and raw:
            (out_dir / "feds.bin").write_bytes(raw)
            (out_dir / "feds.json").write_text(json.dumps(doc, indent=2))
            # EffectSoundController inputs: TIER-2 config + TIER-1 sound-subsystem keyframes.
            sound_containers = pe.parse_sound_containers(data, header["effect_flags_ptr"])
            sound = pe.parse_sound_keyframes(data, header["timeline_section_ptr"])
            if sound_containers is not None:
                (out_dir / "sound_containers.json").write_text(json.dumps(sound_containers, indent=2))
            if sound is not None:
                (out_dir / "sound.json").write_text(json.dumps(sound, indent=2))
            added += 1
        else:
            no_sound += 1
            _remove_sound_files(out_dir)
    print(f"FEDS: {added} effects with sound, {no_sound} without, "
          f"{missing_dir} missing effect dir, {errored} errors "
          f"(of {len(bins)} E*.BIN)")


if __name__ == "__main__":
    main()
