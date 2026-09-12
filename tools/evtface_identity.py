#!/usr/bin/env python3
"""Derive the EVTFACE `(row, col) -> identity` authority from the ROM script.

The EVTFACE.BIN portrait grid is global and fixed (8x8, addressed by
`(row, col)` -- see `EvtFaceCatalog.gd` / `parse_evtface.py`), but the grid
carries no identities. This module recovers them from the game's OWN dialogue:
every scripted event portrait is shown by a `{10} Display Message` whose decoded
text opens with a highlighted speaker header, `{Color 08}<NAME>{Newline}{Color 00}...`.
That header names the speaker whose portrait is being drawn, so:

    cell (row, col)  <-  the `{Color 08}` name of every message that shows it

This is ground truth from the script -- not pixel similarity, not fuzzy naming --
and it resolves the SPR-less identities (Balbanes speaker 0x80, Draclau, Goltana,
Flower Girl, ...) that have no ENTD/SPR footprint and would never resolve on the
old "attribute to the ENTD speaking unit" axis. (That axis is demonstrably wrong:
the ENTD `Unit` byte is scene-local -- e.g. cell (1,2) Mustadio is spoken with
speaker byte 130 in one scene and 129 in another -- while the text name is stable.)

A cell is genuinely shown by EVTFACE (not the speaker's own unit-sheet portrait)
only when the `Dialog` bit-4 EVTFACE flag is set (`Dialog & 0x10`) AND the
`Portrait` byte is in `[1, 8]` AND a `{50} Portrait Row` is active. `col =
Portrait - 1`. NB: bit 4 is the gate, not the exact value `0x10` -- one message
(Elidibs, scn112, cell (3,6)) carries `Dialog=0x70` (bits 4/5/6) and still shows
its EVTFACE portrait, so the stricter `(Dialog&0x70)==0x10` that the runtime pool
comment quotes drops it. Bit 4 alone reproduces the hand-authored §9 table 43/43.

Run (writes `assets/scenarios/faces/evtface_identities.json`):

    uv run python -m evtface_identity

Or import `derive_evtface_identities(chunks)` for the pure table.
"""

from __future__ import annotations

import collections
import glob
import json
import os
import re

# `{Color 08}<name>{Newline}` -- the speaker header the box renders in highlight.
_NAME_RE = re.compile(r"^\s*\{Color 08\}(.*?)\{Newline\}")
# A bare name-variable token, e.g. `{Ramza}` / `{Delita}` (the player-named hero).
_VAR_RE = re.compile(r"^\{([A-Za-z]+)\}$")

OP_DISPLAY_MESSAGE = 16
OP_PORTRAIT_ROW = 80


def extract_speaker_name(raw_text: str) -> str | None:
    """Return the `{Color 08}` speaker header of a decoded message, or None.

    Strips the highlight/newline markup and normalises a lone name-variable
    (`{Ramza}` -> `Ramza`). Honorific-prefixed forms ("Lord Dycedarg") are
    returned verbatim; the aggregator folds them into a canonical identity.
    """
    if not raw_text:
        return None
    m = _NAME_RE.match(raw_text)
    if not m:
        return None
    name = m.group(1).strip()
    var = _VAR_RE.match(name)
    if var:
        name = var.group(1)
    return name or None


def _params(inst: dict) -> dict:
    return {p["name"]: p["value"] for p in inst.get("params", [])}


def _canonical(counter: "collections.Counter") -> str:
    """Pick the canonical identity from observed name spellings: most frequent,
    breaking ties toward the shorter form (base name over an honorific)."""
    return sorted(counter.items(), key=lambda kv: (-kv[1], len(kv[0]), kv[0]))[0][0]


def derive_evtface_identities(chunk_loaders: dict) -> dict:
    """Replay every chunk and return the `(row,col) -> identity` table.

    `chunk_loaders` maps `scenario_id -> callable returning that chunk's dict`
    (so a 500-chunk corpus need not be held in memory at once). Returns a dict:

        { "R_C": { row, col, identity, aliases, occurrences,
                   speaker_bytes: {byte: n}, scenarios: [id, ...],
                   sample_text } }

    keyed by `"<row>_<col>"` to mirror `evtface.json`'s `faces` map.
    """
    names: dict = collections.defaultdict(collections.Counter)
    speakers: dict = collections.defaultdict(collections.Counter)
    scenarios: dict = collections.defaultdict(set)
    samples: dict = {}

    for sid in sorted(chunk_loaders, key=lambda s: (len(str(s)), str(s))):
        chunk = chunk_loaders[sid]()
        row = None
        for inst in chunk.get("instructions", []):
            op = inst.get("opcode")
            if op == OP_PORTRAIT_ROW:
                row = _params(inst).get("Row")
            elif op == OP_DISPLAY_MESSAGE:
                ps = _params(inst)
                if (int(ps.get("Dialog", 0)) & 0x10) == 0:
                    continue
                portrait = int(ps.get("Portrait", 0)) & 0xFF
                if portrait < 1 or portrait > 8 or row is None:
                    continue
                col = portrait - 1
                dlg = inst.get("dialogue", {}) or {}
                text = dlg.get("raw_text", "") or ""
                name = extract_speaker_name(text)
                cell = (int(row), int(col))
                if name is not None:
                    names[cell][name] += 1
                speakers[cell][dlg.get("speaker_unit_byte")] += 1
                scenarios[cell].add(sid)
                samples.setdefault(cell, text[:120])

    table: dict = {}
    for cell in sorted(set(names) | set(speakers)):
        r, c = cell
        name_counter = names.get(cell, collections.Counter())
        identity = _canonical(name_counter) if name_counter else None
        aliases = sorted(n for n in name_counter if n != identity)
        table[f"{r}_{c}"] = {
            "row": r,
            "col": c,
            "identity": identity,
            "aliases": aliases,
            "occurrences": sum(name_counter.values()) or sum(speakers[cell].values()),
            "speaker_bytes": {str(k): v for k, v in sorted(speakers[cell].items(),
                                                           key=lambda kv: (-kv[1],))},
            "scenarios": sorted(scenarios[cell], key=lambda s: (len(str(s)), str(s))),
            "sample_text": samples.get(cell, ""),
        }
    return table


def build_name_to_token(unit_names: dict, residue: dict) -> dict:
    """`{display_name -> template token}` for identities that own a template folder.

    `unit_names` is `unit_names.json`'s `names` map (`{special_name_str -> name}`);
    `residue` is `template_residue.json`'s `residue` map (`{special_name_str ->
    token}`). Only names whose special_name has a residue token are included -- the
    SPR-backed uniques (path A). SPR-less / generic names are absent (they resolve to
    None and are left for minting / the global grid)."""
    out: dict = {}
    for sn, name in unit_names.items():
        tok = residue.get(str(sn))
        if tok:
            out.setdefault(name, tok)
    return out


def face_attributions(table: dict, name_to_token: dict) -> tuple:
    """Split the identity table into `(attributed, skipped)`.

    `attributed` is `{token -> [(row,col), ...]}` for cells whose identity resolves
    to an existing template token (path A). `skipped` is `{display_name ->
    [(row,col), ...]}` for cells with no token -- the SPR-less named identities to be
    minted (Balbanes, Besrodio, Gelwan, Kanbabrif, Flower Girl, ...) and the pure
    generics the global EVTFACE grid already serves (Knight, Priest, Bar Patron,
    Prisoner, Executioner, ...). Cells are emitted in stable (row, col) order.
    """
    attributed: dict = {}
    skipped: dict = {}
    for ent in sorted(table.values(), key=lambda e: (e["row"], e["col"])):
        cell = (int(ent["row"]), int(ent["col"]))
        name = ent.get("identity")
        tok = name_to_token.get(name) if name is not None else None
        if tok:
            attributed.setdefault(tok, []).append(cell)
        else:
            skipped.setdefault(name or "(no-name)", []).append(cell)
    return attributed, skipped


def _load_corpus(chunks_dir: str) -> dict:
    loaders = {}
    for path in glob.glob(os.path.join(chunks_dir, "scenario_*_chunk.json")):
        sid = os.path.basename(path).split("_")[1]
        loaders[sid] = (lambda p=path: json.load(open(p)))
    return loaders


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)  # godot-learning/
    chunks_dir = os.path.join(root, "assets", "scenarios", "chunks")
    out_path = os.path.join(root, "assets", "scenarios", "faces",
                            "evtface_identities.json")

    table = derive_evtface_identities(_load_corpus(chunks_dir))
    covered = sorted(tuple(v["row"] * 8 + v["col"] for v in table.values()))
    missing = [f"{i // 8}_{i % 8}" for i in range(64)
               if (i // 8) * 8 + (i % 8) not in covered]
    doc = {
        "source": "derived from {10} Display Message {Color 08} speaker headers "
                  "across EVENT/*.BIN scenario scripts (evtface_identity.py)",
        "method": "cell (row, Portrait-1) shown iff (Dialog & 0x10) [bit 4] and "
                  "Portrait in [1,8] and a {50} row is active; identity = the "
                  "highlighted {Color 08} name of the message that shows it",
        "coverage": {"cells_shown": len(table), "cells_total": 64,
                     "cells_never_shown": missing},
        "identities": table,
    }
    with open(out_path, "w") as fh:
        json.dump(doc, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print(f"wrote {out_path}: {len(table)}/64 cells identified, "
          f"{len(missing)} never shown")


if __name__ == "__main__":
    main()
