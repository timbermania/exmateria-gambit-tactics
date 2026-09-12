#!/usr/bin/env python3
"""Generate feds_param_stats.json — the empirical usage range behind ADR-0085's
opcode-param honesty amendment (2026-08-12).

Scans every shipped effect's FEDS blob and, per (opcode, param_index), records a
signed-aware min / max / median / mode / n. This is the honest substitute for a
physical unit on a param that has none: it answers "is 2 a lot?" by showing what
real effects actually do with that byte, and lets the inspector warn when the
author leaves the envelope of real data.

The committed JSON is the SHARED source for the empirical range AND per-param
signedness — the GDScript descriptor (FedsParamStats.gd) reads this same file, so
Python and GDScript can't disagree. The hand-authored signed-param list below is
the generator's single input (source: the `sb` / signed-16 comments in
addons/exmateria_sound/runtime/sound_opcodes.gd).

Run from the package root:  uv run --project tools python tools/generate_feds_param_stats.py
"""
import json
from collections import Counter
from pathlib import Path

import parse_effect as pe

HERE = Path(__file__).resolve().parent
EFFECTS_DIR = HERE.parent / "assets" / "effects"
STATS_PATH = HERE.parent / "assets" / "feds_param_stats.json"

# Hand-authored signed-param list — the ONE input. Maps (opcode, param_index) to
# the signed width in bits; everything else is an unsigned u8. 0xD3 folds its two
# param bytes into ONE signed 16-bit word at param_index 0 (value = high<<8|low),
# matching the single s16 cell the projector shows for it.
SIGNED_PARAMS = {
    (0xAD, 0): 8,    # Byte76_Adjust — slot+0x76 sign-extended add
    (0xD1, 0): 8,    # AddPitchBend  — chan+0x86 += sb*32
    (0xD2, 0): 8,    # PitchBendRel
    (0xD6, 0): 8,    # Detune
    (0xE1, 0): 8,    # Dynamics_Add  — chan+0x98 += (sb<<24)
    (0xD3, 0): 16,   # PitchBend_Add_16bit — chan+0x86 += signed 16-bit (high<<8|low)
}


def _s8(b: int) -> int:
    return b - 256 if b >= 128 else b


def _s16(hi: int, lo: int) -> int:
    v = (hi << 8) | lo
    return v - 65536 if v >= 32768 else v


INSTRUMENT_OP = 0xAC   # Instrument — sets the track's active waveset


def _iter_events():
    """Yield (opcode, [param_bytes], active_instrument) for every CONTROL opcode.

    `active_instrument` is the last 0xAC's value earlier in the SAME track (None
    before the first 0xAC) — the runtime's per-TrackState instrument, never
    crossing tracks. The 0xAC event itself reports the PRIOR instrument (the state
    is "< this event"), matching the projector's backward scan; the update lands
    after the yield.
    """
    for effect_dir in sorted(EFFECTS_DIR.glob("E*")):
        feds_bin = effect_dir / "feds.bin"
        if not feds_bin.exists():
            continue
        doc = pe.parse_feds_blob(feds_bin.read_bytes())
        if doc is None:
            continue
        for track in doc["tracks"]:
            current_instrument = None
            for ev in track["opcodes"]:
                op = ev.get("opcode")
                if op is None or op < 0x80:   # skip Note events
                    continue
                params = ev.get("params")
                if params is None and "value" in ev:
                    params = [ev["value"]]
                params = params or []
                yield op, params, current_instrument
                if op == INSTRUMENT_OP and params:
                    current_instrument = params[0]


def _collect() -> tuple:
    """Return (global, by_instrument):
      global:        key '0xNN:idx' -> list of signed-aware samples (all corpus)
      by_instrument: key '0xNN:idx' -> {instrument_id -> list of samples}

    A sample joins the per-instrument bucket ONLY when an instrument is active
    (a 0xAC preceded it in-track); the pre-0xAC samples feed the global stats
    alone (there is nothing to condition on).
    """
    samples: dict = {}
    by_inst: dict = {}

    def add(op: int, idx: int, val: int, inst) -> None:
        key = "0x%02X:%d" % (op, idx)
        samples.setdefault(key, []).append(val)
        if inst is not None:
            by_inst.setdefault(key, {}).setdefault(inst, []).append(val)

    for op, params, inst in _iter_events():
        # A signed 16-bit word: fold both bytes into one sample at index 0.
        if SIGNED_PARAMS.get((op, 0)) == 16:
            if len(params) >= 2:
                add(op, 0, _s16(params[0], params[1]), inst)
            continue
        for i, b in enumerate(params):
            width = SIGNED_PARAMS.get((op, i))
            add(op, i, _s8(b) if width == 8 else int(b), inst)
    return samples, by_inst


def _summarize(vals: list) -> dict:
    s = sorted(vals)
    n = len(s)
    counts = Counter(vals)
    top = max(counts.values())
    mode = min(v for v, c in counts.items() if c == top)   # ties -> smallest
    return {"min": s[0], "max": s[-1], "median": s[(n - 1) // 2], "mode": mode, "n": n}


def build_doc() -> dict:
    samples, by_inst = _collect()
    stats = {}
    for key in sorted(samples):
        op = int(key.split(":")[0], 16)
        idx = int(key.split(":")[1])
        width = SIGNED_PARAMS.get((op, idx))
        entry = {"signed": width is not None, "bits": width or 8}
        entry.update(_summarize(samples[key]))
        # Emit-for-all, show-selectively (ADR-0085 §4): every entry carries a
        # per-instrument bucket keyed by the active-instrument id (as a string, for
        # JSON), each summarized the SAME way as the global stats. The UI reads only
        # the buckets it needs; one table, no second "which ops" list to drift.
        buckets = by_inst.get(key, {})
        entry["by_instrument"] = {
            str(inst): _summarize(buckets[inst]) for inst in sorted(buckets)
        }
        stats[key] = entry
    return {
        "_comment": (
            "Per-(opcode, param_index) FEDS param stats across the shipped effect "
            "corpus — the empirical usage range (ADR-0085, 2026-08-12). Signed "
            "params are scanned in signed space; 0xD3 folds its two bytes into one "
            "signed word at param_index 0. Shared source for range AND signedness. "
            "Regenerate: uv run --project tools python tools/generate_feds_param_stats.py"
        ),
        "stats": stats,
    }


def render(doc: dict) -> str:
    return json.dumps(doc, indent=2, sort_keys=True) + "\n"


def main() -> None:
    STATS_PATH.write_text(render(build_doc()))
    print("wrote %s" % STATS_PATH)


if __name__ == "__main__":
    main()
