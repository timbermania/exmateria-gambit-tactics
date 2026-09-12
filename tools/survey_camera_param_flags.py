#!/usr/bin/env python3
"""Survey which E###.BIN effects set a non-zero camera command-word ``param_index``
(bits 3-4, mask 0x0018) or ``flags`` (bits 13-15, mask 0xE000).

Both fields are parsed and byte-preserved by the effect-studio pipeline but the
GDScript runtime (``CameraSubsystem.gd``) ignores them, and no reverse-engineering
has yet proven what the PSX does with them. This tool makes the *data* footprint
visible and repeatable: it reports, per effect file, every camera keyframe carrying
a non-zero param/flags along with the context that scopes an RE / dynamic-validation
target — which phase table, which sub-channels the keyframe activates
(angle/position/zoom via ``channel_mask``), its source_mode and interpolation.

The aggregate totals at the bottom are the cross-check that the scan is correct
(compare against a prior manual scan). See
``research/working_documents/`` for the RE writeup this feeds.

Run (from the package dir):
    cd tools && uv run python survey_camera_param_flags.py
    cd tools && uv run python survey_camera_param_flags.py --json out.json

Guard:
    cd tools && uv run python -m unittest survey_camera_param_flags_test
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional

import parse_effect

# channel_mask bit -> sub-channel name (mirror CameraChannel._CHANNEL_NAME).
_CHANNEL_NAME = {1: "angle", 2: "position", 4: "zoom"}

# Default asset locations, resolved relative to this file so the tool works from
# any cwd (the effect-studio worktree reaches these via its project-assets symlink).
_PKG_ROOT = Path(__file__).resolve().parent.parent          # godot-learning/
# ROM-derived binaries live at the worktree root's project-assets (a symlink to the
# canonical copy), not under godot-learning/.
_ASSETS = _PKG_ROOT.parent / "project-assets" / "fft-extract"
_DEFAULT_EFFECT_DIR = _ASSETS / "EFFECT"
_DEFAULT_BATTLE_BIN = _ASSETS / "BATTLE.BIN"


def sub_channels(channel_mask: int) -> List[str]:
    """Decode a channel_mask into the sub-channel names it activates."""
    return [name for bit, name in _CHANNEL_NAME.items() if channel_mask & bit]


@dataclass
class Hit:
    """One camera keyframe carrying a non-zero param and/or flags."""
    file: str
    phase: str            # phase1 / for_each / phase2
    kf_index: int
    channels: List[str]   # sub-channels the kf activates (angle/position/zoom)
    source_mode: str
    interpolation: str
    param: int
    flags: int
    command_raw: int
    # True when the command word decodes to an UNDEFINED source_mode or interpolation
    # enum — the hallmark of a misparsed/padding table (e.g. 0xFFFF junk) rather than an
    # authored camera keyframe. Suspect hits should be excluded from any semantic claim.
    suspect: bool


@dataclass
class SurveyResult:
    hits: List[Hit]
    files_scanned: int
    files_empty: List[str]               # 0-byte unused effect slots (not real failures)
    files_failed: List[str]
    camera_keyframes_total: int          # every parsed camera kf across all files
    param_histogram: Dict[int, int]      # param value -> count of camera kfs
    flags_histogram: Dict[int, int]      # flags value -> count of camera kfs


def _iter_camera_keyframes(parsed: Dict[str, Any]):
    """Yield (phase_name, keyframe_dict) for every camera keyframe in a parse."""
    camera = parsed.get("camera") or {}
    for phase in ("phase1", "for_each", "phase2"):
        table = camera.get(phase)
        if not table:
            continue
        for kf in table.get("keyframes", []):
            yield phase, kf


def survey(effect_dir: Path, battle_bin: Path) -> SurveyResult:
    """Scan every E###.BIN in ``effect_dir`` for non-zero camera param/flags."""
    hits: List[Hit] = []
    empty: List[str] = []
    failed: List[str] = []
    scanned = 0
    kf_total = 0
    param_hist: Counter = Counter()
    flags_hist: Counter = Counter()

    for bin_path in sorted(effect_dir.glob("E*.BIN")):
        # 0-byte files are unused effect slots, not parse failures — skip cleanly.
        if bin_path.stat().st_size == 0:
            empty.append(bin_path.name)
            continue
        vfx_id = parse_effect.vfx_id_from_filename(bin_path.name)
        header_offset = (
            parse_effect.load_vfx_header_offset(str(battle_bin), vfx_id)
            if vfx_id is not None
            else None
        )
        try:
            parsed = parse_effect.parse_effect_file(str(bin_path), header_offset=header_offset)
        except Exception:  # noqa: BLE001 - a malformed effect must not abort the sweep
            failed.append(bin_path.name)
            continue

        scanned += 1
        for phase, kf in _iter_camera_keyframes(parsed):
            kf_total += 1
            param = int(kf.get("param_index", 0))
            flags = int(kf.get("flags", 0))
            param_hist[param] += 1
            flags_hist[flags] += 1
            if param == 0 and flags == 0:
                continue
            source_mode = str(kf.get("source_mode", "?"))
            interpolation = str(kf.get("interpolation", "?"))
            hits.append(Hit(
                file=bin_path.name,
                phase=phase,
                kf_index=int(kf.get("index", -1)),
                channels=sub_channels(int(kf.get("channel_mask", 0))),
                source_mode=source_mode,
                interpolation=interpolation,
                param=param,
                flags=flags,
                command_raw=int(kf.get("command_raw", 0)),
                suspect=source_mode.startswith("UNKNOWN") or interpolation.startswith("UNKNOWN"),
            ))

    return SurveyResult(
        hits=hits,
        files_scanned=scanned,
        files_empty=empty,
        files_failed=failed,
        camera_keyframes_total=kf_total,
        param_histogram=dict(sorted(param_hist.items())),
        flags_histogram=dict(sorted(flags_hist.items())),
    )


def _fmt_histogram(hist: Dict[int, int]) -> str:
    return "{" + ", ".join(f"{k}: {v}" for k, v in hist.items()) + "}"


def print_report(result: SurveyResult) -> None:
    print("=" * 78)
    print("CAMERA COMMAND-WORD param/flags SURVEY")
    print("=" * 78)
    print(f"Files scanned: {result.files_scanned}"
          f"  (empty slots skipped: {len(result.files_empty)}"
          + (f", parse-failed: {len(result.files_failed)}" if result.files_failed else "")
          + ")")
    if result.files_failed:
        print("  parse-failed: " + ", ".join(result.files_failed))
    print(f"Camera keyframes parsed: {result.camera_keyframes_total}")
    print(f"param_index histogram: {_fmt_histogram(result.param_histogram)}")
    print(f"flags       histogram: {_fmt_histogram(result.flags_histogram)}")

    legit = [h for h in result.hits if not h.suspect]
    suspect = [h for h in result.hits if h.suspect]
    print(f"Keyframes with non-zero param OR flags: {len(result.hits)}  "
          f"(legit: {len(legit)}, suspect/misparsed: {len(suspect)})")
    print()

    def _table(rows: List[Hit]) -> None:
        print(f"{'file':<9} {'phase':<8} {'kf':>2}  {'param':>5} {'flags':>5}  "
              f"{'source_mode':<13} {'interp':<15} channels")
        print("-" * 78)
        for h in rows:
            chans = ",".join(h.channels) if h.channels else "-"
            print(f"{h.file:<9} {h.phase:<8} {h.kf_index:>2}  "
                  f"{h.param:>5} {h.flags:>5}  {h.source_mode:<13} "
                  f"{h.interpolation:<15} {chans}")

    if legit:
        print("-" * 78)
        print("LEGIT hits (known source_mode + interpolation — authored camera keyframes):")
        print("-" * 78)
        _table(legit)
        print()
    if suspect:
        print("-" * 78)
        print("SUSPECT hits (UNDEFINED source/interp enum — misparsed/padding, NOT authored):")
        print("-" * 78)
        _table(suspect)
        print()

    # The exact file list per field, restricted to LEGIT hits (the real footprint).
    param_files = sorted({h.file for h in legit if h.param})
    flags_files = sorted({h.file for h in legit if h.flags})
    print("Files that set a non-zero param_index on a LEGIT keyframe (%d):" % len(param_files))
    print("  " + (", ".join(param_files) if param_files else "(none)"))
    print("Files that set a non-zero flags on a LEGIT keyframe (%d):" % len(flags_files))
    print("  " + (", ".join(flags_files) if flags_files else "(none)"))
    suspect_files = sorted({h.file for h in suspect})
    if suspect_files:
        print("Files whose hits are ALL suspect/misparsed (%d): %s"
              % (len(suspect_files), ", ".join(suspect_files)))

    # Cross-tabs (LEGIT only) that surface the source_mode clustering lead.
    param_by_src = Counter((h.param, h.source_mode) for h in legit if h.param)
    flags_by_src = Counter((h.flags, h.source_mode) for h in legit if h.flags)
    print()
    print("param x source_mode (legit):")
    for (p, src), n in sorted(param_by_src.items()):
        print(f"  param={p}  {src:<12} x{n}")
    print("flags x source_mode (legit): "
          + ("(none — flags is never set on an authored keyframe)" if not flags_by_src else ""))
    for (f, src), n in sorted(flags_by_src.items()):
        print(f"  flags={f}  {src:<12} x{n}")


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--effect-dir", type=Path, default=_DEFAULT_EFFECT_DIR,
                    help="directory of E###.BIN effect files")
    ap.add_argument("--battle-bin", type=Path, default=_DEFAULT_BATTLE_BIN,
                    help="BATTLE.BIN (authoritative per-effect header offsets)")
    ap.add_argument("--json", type=Path, default=None,
                    help="also write the full survey (hits + histograms) as JSON here")
    args = ap.parse_args(argv)

    if not args.effect_dir.is_dir():
        print(f"ERROR: effect dir not found: {args.effect_dir}", file=sys.stderr)
        return 2

    result = survey(args.effect_dir, args.battle_bin)
    print_report(result)

    if args.json:
        payload = asdict(result)
        payload["hits"] = [asdict(h) for h in result.hits]
        args.json.write_text(json.dumps(payload, indent=2))
        print(f"\nwrote {args.json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
