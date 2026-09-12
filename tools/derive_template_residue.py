#!/usr/bin/env python3
"""Auto-derive the unique-character residue for the resolvable story cast (ADR-0072).

The two authored bridges that promote a special_name to a template -- IDENTITY
(`template_residue.json`: special_name -> folder token) and ASSET
(`template_assets.json`: special_name -> flat-store body sprite_id) -- began as an
11-unit *pilot*. Every remaining named story character (`unit_names.json`) is a
first-class template too; it just wasn't authored yet. This tool derives their
entries mechanically so the pilot can be expanded to the whole cast:

  * TOKEN   = `<lowercased unit name>_<special_name>` (matches the pilot's
    `ramza_1` / `agrias_52` scheme; each Form is a distinct folder).
  * BODY    = the ENTD *dominant* `sprite_set` across the character's slots,
    ignoring null (0x00) and the generic-soldier sheets (0x80..0x8A) that appear
    as one-off scene extras. That is literally the SPR the ROM loads for the
    slot, so it is the faithful body in all but a few decoy cases.

Nothing here touches the EVTCHR *event* frames: those are recovered by the
corpus replay in `event_asset_derivation.py` (independent of the body sprite),
so a flagged/imperfect body does not affect a promoted unique's cinematic frames.

FLAGS surfaced for human eyes (mirrors the pilot's two hand-overrides -- Gafgarion
23 and Agrias 30 -- where the ENTD sprite was a scene decoy, not the identity):
  * NO_CHAR_SHEET -- only generic/null sprite_sets -> cannot derive a body.
  * LOWCONF(n)    -- dominant appears < 3x; low confidence (usually still correct,
    e.g. an alt-Form using an H-series slot).
  * SHARED:X      -- another named character's dominant is the same sheet.
  * VERIFY        -- the dominant SPR's mnemonic is semantically surprising for the
    name (a Gafgarion-type decoy); keep the faithful body but eyeball it.

Run:
    uv run python tools/derive_template_residue.py            # report only
    uv run python tools/derive_template_residue.py --write    # merge into both JSONs
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict

from _repo_paths import assets_dir, catalogue_dir

RESIDUE_PATH = catalogue_dir("templates/template_residue.json")   # ADR-0251 dec. 2, #1025 pass 3
ASSETS_PATH = assets_dir("scenarios/template_assets.json")
UNIT_NAMES_PATH = catalogue_dir("identity/unit_names.json")      # ADR-0251 dec. 2, #1025 pass 3
ENTD_PATH = assets_dir("scenarios/entd.json")
SPRITE_FILES_PATH = assets_dir("sprites/sprite_files.json")

# null + the generic-soldier sheets that show up as one-off scene extras; never a
# story character's identity body.
GENERIC_SPRITE_SETS = {0x00} | set(range(0x80, 0x8B))

# special_names whose dominant sheet is semantically surprising for the name (the
# ENTD slot genuinely loads another character's/placeholder sheet). Body kept
# faithful to the ENTD; flagged so the folder's body.tga is eyeballed. EVTCHR
# frames are unaffected. Extend as headful verification resolves them.
VERIFY_BODY = {17, 22}


def _entd_slots(entd: dict) -> list:
    recs = entd["records"]
    return list(recs.values() if isinstance(recs, dict) else recs)


def sprite_set_distribution(entd: dict) -> dict:
    """{special_name -> {sprite_set -> count}} over every ENTD slot."""
    dist: dict = defaultdict(lambda: defaultdict(int))
    for rec in _entd_slots(entd):
        for slot in rec.get("slots", []):
            sn = slot.get("special_name")
            ss = slot.get("sprite_set")
            if sn is not None and ss is not None:
                dist[sn][ss] += 1
    return dist


def dominant_char_sprite(dist_for_sn: dict) -> tuple[int | None, int]:
    """(sprite_set, count) of the most-used non-generic sheet, or (None, 0)."""
    ranked = sorted(((n, ss) for ss, n in dist_for_sn.items()
                     if ss not in GENERIC_SPRITE_SETS), reverse=True)
    if not ranked:
        return None, 0
    n, ss = ranked[0]
    return ss, n


def derive_candidates() -> list[dict]:
    """One record per resolvable story special_name not already a template."""
    names = json.loads(UNIT_NAMES_PATH.read_text())["names"]
    residue = json.loads(RESIDUE_PATH.read_text())["residue"]
    entd = json.loads(ENTD_PATH.read_text())
    sprite_files = json.loads(SPRITE_FILES_PATH.read_text())
    dist = sprite_set_distribution(entd)

    # existing dominant per name, to detect shared-sheet collisions
    dom_by_sn = {sn: dominant_char_sprite(d)[0] for sn, d in dist.items()}

    out: list[dict] = []
    for sn_str, name in names.items():
        sn = int(sn_str)
        if sn_str in residue or sn not in dist:
            continue
        ss, count = dominant_char_sprite(dist[sn])
        token = f"{name.lower()}_{sn}"
        flags: list[str] = []
        if ss is None:
            body = None
            flags.append("NO_CHAR_SHEET")
            spr_name = "(none)"
        else:
            body = f"{ss:02X}"
            spr_name = sprite_files.get(body, {}).get("filename", "?")
            if count < 3:
                flags.append(f"LOWCONF({count})")
            sharers = sorted({names[str(o)] for o, d_ss in dom_by_sn.items()
                              if o != sn and d_ss == ss and str(o) in names
                              and names[str(o)] != name})
            if sharers:
                flags.append("SHARED:" + "/".join(sharers))
            if sn in VERIFY_BODY:
                flags.append("VERIFY")
        out.append({"special_name": sn, "name": name, "token": token,
                    "body_sprite_id": body, "spr": spr_name, "flags": flags})
    out.sort(key=lambda c: c["special_name"])
    return out


def _write_merged(candidates: list[dict]) -> tuple[int, int]:
    """Merge derived entries into both authored JSONs (idempotent: only adds
    missing special_names, preserves existing entries + comments)."""
    residue_doc = json.loads(RESIDUE_PATH.read_text())
    assets_doc = json.loads(ASSETS_PATH.read_text())
    res = residue_doc["residue"]
    ass = assets_doc["assets"]

    for c in candidates:
        if c["body_sprite_id"] is None:
            continue
        sn_str = str(c["special_name"])
        if sn_str in res:
            continue
        res[sn_str] = c["token"]
        note = f"{c['spr']} ({c['name']}) [auto: ENTD dominant sprite_set]"
        if "VERIFY" in c["flags"]:
            note += (" -- VERIFY body identity (surprising sheet for name; "
                     "EVTCHR frames unaffected)")
        ass[sn_str] = {"body_sprite_id": c["body_sprite_id"], "_spr": note}

    residue_doc["residue"] = {str(k): res[str(k)] for k in sorted(map(int, res))}
    assets_doc["assets"] = {str(k): ass[str(k)] for k in sorted(map(int, ass))}
    RESIDUE_PATH.write_text(json.dumps(residue_doc, indent=1) + "\n")
    ASSETS_PATH.write_text(json.dumps(assets_doc, indent=2) + "\n")
    return len(residue_doc["residue"]), len(assets_doc["assets"])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true",
                    help="merge derived entries into template_residue.json + "
                         "template_assets.json (idempotent)")
    args = ap.parse_args()

    candidates = derive_candidates()
    print(f"{'sn':>3} {'name':<11} {'token':<15} {'body':<5} {'SPR':<14} flags")
    for c in candidates:
        print(f"{c['special_name']:>3} {c['name']:<11} {c['token']:<15} "
              f"{str(c['body_sprite_id']):<5} {c['spr']:<14} {' '.join(c['flags'])}")
    flagged = sum(1 for c in candidates if c["flags"])
    print(f"\n{len(candidates)} candidates; {flagged} flagged")

    if args.write:
        nres, nass = _write_merged(candidates)
        print(f"merged -> residue={nres} entries, assets={nass} entries")
        print("regenerate folders: uv run python tools/align_character_templates.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
