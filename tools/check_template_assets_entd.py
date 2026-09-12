#!/usr/bin/env python3
"""Guard: every `template_assets.json` body sprite agrees with the ROM's ENTD.

    uv run python tools/check_template_assets_entd.py

WHAT IT IS FOR. `assets/scenarios/template_assets.json` maps an ENTD
`special_name` (a unique character) to the flat-store BODY sprite id whose sheet
`tools/align_character_templates.py` slices that unique's `body.tga` and
`portrait.tga` out of. Most rows were DERIVED from the ENTD and say so
(`[auto: ENTD dominant sprite_set]`). A few were hand-authored from the SPR
FILENAME — and the romanized filename reads like the character while naming a
different one:

  * `GARU.SPR` (0x16) sounds like GAfgarion and is **Mustadio's** sheet. sn 23
    carried `"16"` with the note `GARU.SPR (Gafgarion)`; the ENTD says 0x17 in
    9/9 slots. The chapel (scenario 2) painted Mustadio's portrait on Gafgarion
    for as long as that entry stood, and nothing failed.
  * `AGURI.SPR` (0x34) sounds like AGRIAS and is Agrias **Form 2's** sheet. sn 30
    (Form 1) carried `"34"`; the ENTD says 0x1E (KANBA.SPR) in 7/7 slots.

Those were 2 of 59, and BOTH were hand-authored — the auto-derived rows are all
correct. The defect is not arithmetic, it is a source-of-truth substitution, so
the guard re-derives from the source of truth and diffs.

WHY THE READER NEVER RESCUED IT. `UIPortrait.display_from_template` PREFERS the
baked `templates/<token>/portrait.tga` and only falls back to a sprite id when
the folder is absent. The spawned `Unit.body_sprite_id` was right the whole time
and was never consulted. A wrong id here is baked into a gitignored artifact,
which is exactly the shape no test sees.

ARMS.

  arm 1  ENFORCING. Each entry's `body_sprite_id` must equal the DOMINANT
         `sprite_set` its `special_name` carries across every ENTD slot.
  arm 2  ENFORCING. Each entry's `special_name` must appear in at least one ENTD
         slot — an id nothing spawns is a row addressed to nobody.
  arm 3  ENFORCING, always. A self-test re-seeds the two historical defects and
         requires arm 1 to name both. `check_guard_registry.py` records that an
         invoked guard whose seeded-red arms nobody runs can silently stop
         firing (#876); this arm runs on every invocation so it cannot.

WHAT IT CANNOT SEE. Only the BODY sheet id. The portrait CROP within that sheet,
the palette row, and the EVTCHR/EVTFACE event frames are other channels.
`gafgarion_17` and `gafgarion_23` are byte-identical sheets on the retail disc
(0x11 BARUNA is 0x17 H61), so this guard passing does not prove two rows
pointing at a duplicate pair were meant to.
"""
import collections
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ENTD = ROOT / "assets/scenarios/entd.json"
ASSETS = ROOT / "assets/scenarios/template_assets.json"
SPRITE_FILES = ROOT / "assets/sprites/sprite_files.json"

# A slot with no unique in it. 0 = generic, 255 = the empty/monster marker.
NO_SPECIAL_NAME = (0, 255)
# `sprite_set` 0 is an unfilled slot, and >= 0x80 selects a GENERIC job sheet
# rather than a unique's own (Delita sn 6 carries one 0x80 slot beside three
# 0x06s). Neither says anything about which unique sheet the template wants.
GENERIC_SPRITE_SET = 0x80


def entd_census(entd: dict) -> dict:
    """special_name -> Counter of the UNIQUE sprite_sets its slots carry."""
    census = collections.defaultdict(collections.Counter)
    for record in entd["records"].values():
        for slot in record["slots"]:
            name = slot["special_name"]
            sprite_set = slot["sprite_set"]
            if name in NO_SPECIAL_NAME:
                continue
            if sprite_set == 0 or sprite_set >= GENERIC_SPRITE_SET:
                continue
            census[name][sprite_set] += 1
    return census


def _spr_name(sprite_files: dict, sprite_id: int) -> str:
    entry = sprite_files.get(f"{sprite_id:02X}")
    return entry["filename"] if entry else "<no SPR>"


def disagreements(assets: dict, census: dict, sprite_files: dict) -> list:
    """Arms 1 and 2, as a list of problem lines (empty == clean)."""
    problems = []
    for key, entry in sorted(assets.items(), key=lambda kv: int(kv[0])):
        name = int(key)
        have = int(entry["body_sprite_id"], 16)
        counts = census.get(name)
        if not counts:  # arm 2
            problems.append(
                f"special_name {name}: no ENTD slot spawns it — "
                f"`body_sprite_id` {have:02X} is unverifiable against the ROM."
            )
            continue
        want, hits = counts.most_common(1)[0]
        if have == want:
            continue
        total = sum(counts.values())
        spread = ", ".join(f"0x{s:02X}x{n}" for s, n in counts.most_common())
        problems.append(  # arm 1
            f"special_name {name}: `body_sprite_id` is \"{have:02X}\" "
            f"({_spr_name(sprite_files, have)}) but the ENTD says 0x{want:02X} "
            f"({_spr_name(sprite_files, want)}) in {hits}/{total} slots [{spread}]."
        )
    return problems


# The two rows that stood wrong, kept as the seed for arm 3 rather than as prose.
SEEDED = {"23": "16", "30": "34"}


def self_test(assets: dict, census: dict, sprite_files: dict) -> list:
    """Arm 3 — re-seed the historical defects; arm 1 must name both."""
    seeded = {k: dict(v) for k, v in assets.items()}
    for key, bad in SEEDED.items():
        if key not in seeded:
            return [f"self-test: special_name {key} is gone from template_assets.json — "
                    f"re-point the seed or drop it, do not leave arm 3 vacuous."]
        seeded[key]["body_sprite_id"] = bad
    named = disagreements(seeded, census, sprite_files)
    missed = [k for k in SEEDED if not any(f"special_name {int(k)}:" in p for p in named)]
    if missed:
        return [f"self-test: arm 1 did NOT flag seeded-wrong special_name {k} "
                f"(= \"{SEEDED[k]}\") — the arm has stopped firing." for k in missed]
    return []


def main() -> int:
    entd = json.loads(ENTD.read_text(encoding="utf-8"))
    assets = json.loads(ASSETS.read_text(encoding="utf-8"))["assets"]
    sprite_files = json.loads(SPRITE_FILES.read_text(encoding="utf-8"))
    census = entd_census(entd)

    broken_arm = self_test(assets, census, sprite_files)
    if broken_arm:
        print("template_assets.json ENTD guard is BROKEN:")
        for p in broken_arm:
            print(f"  {p}")
        return 1

    problems = disagreements(assets, census, sprite_files)
    if problems:
        print("template_assets.json disagrees with the ROM's ENTD:")
        for p in problems:
            print(f"  {p}")
        print(
            "\nFix: the ENTD `sprite_set` census is the referee — an SPR FILENAME is "
            "not the character (GARU.SPR is Mustadio, AGURI.SPR is Agrias Form 2). "
            "Correct assets/scenarios/template_assets.json, then re-run "
            "`uv run python tools/align_character_templates.py` to re-bake the "
            "affected templates/ folders."
        )
        return 1

    print(f"OK: all {len(assets)} template body sprites match the ENTD dominant sprite_set.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
