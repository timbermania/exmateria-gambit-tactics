#!/usr/bin/env python3
"""Character-alignment transform -- the folder-emitting step (wayfinder #201).

A post-processing pass ON TOP OF the existing flat extract (it extends the bake
pipeline, does not replace it). For each UNIQUE character in the residue set it
slices a folder-per-key template packet out of the flat `assets/sprites/textures/`
store, per the LOCKED schema in `docs/TEMPLATE_JSON_SCHEMA.md` (ADR-0072 dec.3):

    <TEMPLATE_ROOT>/<token>/
        body.tga            body.palette.tga       # byte-identical copy of the flat sheet
        portrait.tga        portrait.palette.tga    # 48x32 portrait crop + its own palette
        template.json                               # body + portrait + animation ref + scalars

Uniques get a slug-token folder (`ramza_3`); generics/monsters get a legibly
named folder in the SAME tree (`male_knight`, `40_year_old_woman`, `elidibs`) --
one template root, no separate generics tree (#222). ADR-0072 always specified a
template per `(job,gender)`/`(job)`; the derivation pools cinematic frames by
resolved SPR (the identifier that always exists -- a `(job,gender)` key exists
only for recruitable humans, not story-townsperson sprites or monster sheets
shared across monster jobs), so the folder is keyed by SPR internally but *named*
from JobDatabase's sprite names. The runtime resolver still returns the flat store
for generics today (`CharacterTemplateResolver.resolve()` -> `{body_sprite_id}`);
the generic folder's net-new value is its recovered EVTCHR frames + being the
moddable read surface (the runtime folder-read is a coordinated follow-up).

Two authored inputs, kept separate so #202's locked runtime artifact is untouched:
  - `template_residue.json`  -- IDENTITY: special_name -> folder token (#202).
  - `template_assets.json`   -- ASSET: special_name -> flat-store body sprite_id.

Carve-outs:
  - `formation.*` is OMITTED -- which UNIT.BIN cell maps to a template is an
    undecoded RE gap (FORMATION_SCREEN.md). The schema slot is locked; contents wait.
  - `events.*` (face/chr) is DERIVED + sliced by the event-corpus pass (#204,
    event_asset_derivation + event_asset_slicing), included when the gitignored
    event corpus + EVTCHR/EVTFACE atlases are present. Absent them, folders emit
    without events (flat-store assets are unaffected).
  - animation TYPE is REFERENCED by name (the sole genuinely-shared asset), never
    copied; `seq` and `shp` families are independent and named separately.

The output tree is generated + gitignored (`/assets/characters/templates/`) and
regenerated on a fresh checkout by running this transform, then `godot --import`.

Run:
    uv run python tools/align_character_templates.py            # emit all uniques
    uv run python tools/align_character_templates.py --output /tmp/t   # elsewhere
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import struct
from pathlib import Path

import event_asset_derivation as ead
import event_asset_slicing as eas
import evtface_identity as efi
import palette_fingerprint as pf
from _repo_paths import almanac_dir, assets_dir, catalogue_dir
from extract_spr import should_decompress, write_tga

# --- geometry, from extract_spr_indexed's layout of the 256x488 sheet ---
# A compressed sprite lays out rows [0,256) top, [256,456) decompressed,
# [456,488) portrait band; an uncompressed one lays out [0,256) top,
# [256,288) portrait band. The portrait itself is the X:80..127 window.
SHEET_W = 256
PORTRAIT_X = 80
PORTRAIT_W = 48
PORTRAIT_H = 32
PORTRAIT_Y0_COMPRESSED = 456
PORTRAIT_Y0_UNCOMPRESSED = 256

# --- authored inputs + flat-store roots ---
RESIDUE_PATH = catalogue_dir("templates/template_residue.json")  # ADR-0251 dec. 2, #1025 pass 3
ASSETS_PATH = assets_dir("scenarios/template_assets.json")
SPRITE_TYPES_PATH = almanac_dir("sprites/sprite_types.json")   # ADR-0251 dec. 2
SPRITE_FILES_PATH = assets_dir("sprites/sprite_files.json")
TEXTURES_DIR = assets_dir("sprites/textures")
# Mirrors `ResidueManifest.TEMPLATE_ROOT`, which is no longer a literal: the addon
# reads it from the host through `exmateria_catalogue/content_root` (ADR-0202 dec. 5,
# #1025 pass 3). This tool WRITES the tree the host then supplies, so it keeps the
# concrete path -- an emitter is the one caller that must know where it emits.
DEFAULT_OUT_ROOT = assets_dir("characters/templates")
# Retired root: #222's first cut emitted generics under a separate SPR-hex tree.
# They now live in the shared template tree with legible names, so this is only
# swept away on regen (a fresh checkout never has it).
LEGACY_GENERIC_ROOT = assets_dir("characters/generics")

# --- event-asset derivation inputs (#204) ---
CHUNKS_DIR = assets_dir("scenarios/chunks")
SCENARIOS_PATH = almanac_dir("encounters/scenarios.json")      # ADR-0251 dec. 2
ENTD_PATH = assets_dir("scenarios/entd.json")
UNIT_NAMES_PATH = catalogue_dir("identity/unit_names.json")      # ADR-0251 dec. 2, #1025 pass 3
CUTSCENE_FACES_PATH = assets_dir("scenarios/cutscene_faces.json")
CINEMATIC_SEQ_PATH = assets_dir("sprites/animations/cinematic_seq.json")
EVTCHR_FRAMES_PATH = assets_dir("sprites/animations/evtchr_frames.json")
EVTCHR_DIR = assets_dir("sprites/textures/evtchr")
FACES_DIR = assets_dir("scenarios/faces")
# Transform-internal provenance: the recovered segment->character residue the ROM
# never stored. NOT read at runtime -- template.json stays coord-free (#200).
EVENT_MAP_PATH = assets_dir("scenarios/event_asset_map.json")


class EventAssetContext:
    """Slicing inputs for the event assets, with a segment-atlas read cache so a
    segment shared by several uniques is decoded once."""

    def __init__(self, evtchr_dir: Path, evtchr_frames: dict, faces_dir: Path):
        self.evtchr_dir = evtchr_dir
        self.frames = evtchr_frames
        self.faces_dir = faces_dir
        self._atlas_cache: dict = {}

    def atlas(self, segment: int):
        if segment not in self._atlas_cache:
            p = self.evtchr_dir / f"segment_{segment:03d}.tga"
            self._atlas_cache[segment] = eas.read_tga_bgra(p) if p.exists() else None
        return self._atlas_cache[segment]

    def segment_palette(self, segment: int) -> Path:
        return self.evtchr_dir / f"segment_{segment:03d}.palette.tga"

    def face_png(self, row: int, col: int) -> Path:
        return self.faces_dir / f"face_r{row}_c{col}.png"


def build_spr_to_token(residue: dict, assets: dict) -> dict:
    """`{resolved SPR (int) -> template token}` -- the sprites-list routing index.

    Inverts each unique's `template_assets` body sprite_id to its token. When two
    special_names share one SPR (the flagged decoys 0x16 Gafgarion->Mustadio-guest,
    0x34 Agrias-F1->Agrias-guest) the lowest special_name wins deterministically;
    both folders are the same character, so a frame fingerprinting to that SPR lands
    on a faithful home either way (the collision is noted in the assets JSON)."""
    spr_to_token: dict = {}
    for sn_str in sorted(residue, key=int):
        entry = assets.get(sn_str)
        if entry is None or entry.get("body_sprite_id") is None:
            continue
        spr = int(entry["body_sprite_id"], 16)
        spr_to_token.setdefault(spr, residue[sn_str])   # first (lowest sn) wins
    return spr_to_token


def derive_event_assets() -> ead.DerivationResult:
    """Run the event-asset derivation over the on-disk corpus (#204).

    Keys each cinematic frame's owner on the RESOLVED SPR (palette fingerprint via
    `SegmentOwnerResolver`, ENTD `sprite_set` fallback) rather than `special_name`,
    so an event-puppet's frames route to their real character. Streams the
    gitignored `chunks/` dir one file at a time. Raises FileNotFoundError if the
    corpus is absent so the caller can decide whether to proceed without events."""
    if not CHUNKS_DIR.exists():
        raise FileNotFoundError(
            f"{CHUNKS_DIR} absent -- run `uv run python tools/export_all_scenario_chunks.py` "
            f"to generate the event corpus before deriving event assets")
    scenarios_raw = json.loads(SCENARIOS_PATH.read_text())["scenarios"]
    items = scenarios_raw.values() if isinstance(scenarios_raw, dict) else scenarios_raw
    scenarios_by_sid = {int(s["scenario_id"]): s for s in items}
    entd_records = json.loads(ENTD_PATH.read_text())["records"]
    residue = json.loads(RESIDUE_PATH.read_text())["residue"]
    assets = json.loads(ASSETS_PATH.read_text())["assets"]
    cinematic_seq = json.loads(CINEMATIC_SEQ_PATH.read_text())

    spr_to_token = build_spr_to_token(residue, assets)
    owner_resolver = pf.SegmentOwnerResolver(
        EVTCHR_DIR, pf.load_sprite_palettes(TEXTURES_DIR))

    # {display name -> cutscene-face slug} (cutscene_faces.json inverted): the bridge
    # that homes a SPR-less named identity's {7F}-bound cinematic frames to its slug
    # instead of the ENTD decoy sprite (Balbanes' deathbed frames were mis-filing
    # under Alma). SPR-less, so the palette fingerprint can't rescue them.
    cutscene_faces = (json.loads(CUTSCENE_FACES_PATH.read_text())["faces"]
                      if CUTSCENE_FACES_PATH.exists() else {})
    name_to_slug = {name: slug for slug, name in cutscene_faces.items()}

    loaders: dict = {}
    for path in CHUNKS_DIR.glob("scenario_*_chunk.json"):
        if path.name.endswith(".raw.json"):
            continue
        sid = int(path.stem.split("_")[1])
        loaders[sid] = (lambda p=path: json.loads(p.read_text()).get("instructions", []))
    result = ead.derive_corpus_streaming(
        loaders, scenarios_by_sid, entd_records, residue, cinematic_seq,
        spr_to_token=spr_to_token, owner_resolver=owner_resolver,
        name_to_slug=name_to_slug)

    # EVTFACE dialogue portraits are attributed on the identity axis (the `{Color
    # 08}` speaker name of the message that shows each cell -- evtface_identity.py),
    # NOT the ENTD-speaker axis the replay used to use. Fold the SPR-backed uniques'
    # cells into their template folders; SPR-less / generic cells stay unhomed (the
    # global EVTFACE grid serves them, and Balbanes et al. await a minted folder).
    unit_names = json.loads(UNIT_NAMES_PATH.read_text())["names"]
    id_table = efi.derive_evtface_identities(
        {sid: (lambda l=ldr: {"instructions": l()}) for sid, ldr in loaders.items()})
    attributed, unhomed = efi.face_attributions(
        id_table, efi.build_name_to_token(unit_names, residue))
    for tok, cells in attributed.items():
        te = result.token(tok)
        for cell in cells:
            te.add_face(cell)
    result.face_unhomed = unhomed
    return result


def emit_event_assets(folder: Path, token_events: ead.TokenEvents,
                      ctx: EventAssetContext) -> dict:
    """Slice a unique's derived event frames/cells into `folder/events/` and
    return the `events` block for its template.json (per #200's schema). Entries
    are re-numbered densely in first-seen order; a frame that can't be sourced
    (absent atlas / empty block list) is skipped, never left as a dangling index."""
    events: dict = {}

    chr_entries: list = []
    for segment, frame_id, palette_row in token_events.chr:
        atlas = ctx.atlas(segment)
        if atlas is None:
            continue
        blocks = ctx.frames.get(str(segment), {}).get(str(frame_id))
        if not blocks:
            continue
        idx = len(chr_entries)
        if eas.emit_chr_frame(folder / "events" / "chr", idx, atlas, blocks,
                              ctx.segment_palette(segment), palette_row):
            chr_entries.append({"index": idx,
                                "sprite": f"events/chr/{idx:02d}.tga",
                                "palette": f"events/chr/{idx:02d}.palette.tga"})
    if chr_entries:
        events["chr"] = chr_entries

    face_entries: list = []
    for row, col in token_events.face:
        png = ctx.face_png(row, col)
        if not png.exists():
            continue
        idx = len(face_entries)
        eas.emit_face_cell(folder / "events" / "face", idx, png)
        face_entries.append({"index": idx,
                             "sprite": f"events/face/{idx:02d}.tga",
                             "palette": f"events/face/{idx:02d}.palette.tga"})
    if face_entries:
        events["face"] = face_entries

    return events


def emit_generic_store(result: ead.DerivationResult | None,
                       ctx: EventAssetContext | None,
                       out_root: Path, sprite_files: dict, *,
                       textures_dir: Path = TEXTURES_DIR,
                       sprite_types: dict | None = None,
                       taken_tokens: set | None = None,
                       skip_hexids: set | None = None) -> list:
    """Emit a self-contained generic/monster template packet per SPR (#222).

    Sweeps the **full sprite table** (`sprite_files`, ids 0x01-0x9A), not just the
    event-resolved SPRs: every sprite id that isn't already owned by a unique
    (`skip_hexids`) gets a body(+human portrait)-only folder, with the derivation's
    pooled cinematic frames attached when it has them. This realizes ADR-0072's
    "a template per (job,gender)/(job)" for the whole roster -- #201 deferred the
    generics, and the earlier build only emitted the ones the event corpus happened
    to resolve. `result`/`ctx` may be None (a no-corpus run) -- the folder still
    ships its body/portrait, just no events.

    ADR-0072 always specified a template per `(job,gender)` (human) / `(job)`
    (monster) mapping to a SPR; #201 only deferred them. The derivation pools
    cinematic frames by *resolved SPR* -- the lowest common denominator that
    ALWAYS exists (the palette fingerprint recovers a sprite, and a `(job,gender)`
    key exists only for recruitable humans, not the story-townsperson sprites or
    monster sheets shared across several monster jobs). So the folder is keyed by
    SPR, but *named* legibly (`male_knight`, `40_year_old_woman`, `funeral_priest`)
    via `generic_template_token`, and lives in the SAME `out_root` as the uniques
    -- one template tree, no separate root.

    For each resolved SPR with pooled frames (`result.generic`), emit
    `<out_root>/<token>/`:
      - `body.tga`/`body.palette.tga` -- byte-identical copy of the flat sheet;
      - `portrait.tga`/`portrait.palette.tga` -- the 48x32 crop, HUMAN sprites only
        (a monster has no menu portrait -- "portrait where one exists");
      - `events/chr/NN.tga` (+ palettes) -- the SPR-pooled cinematic frames;
      - `template.json` -- schema-shaped, `category` generic-human/generic-monster,
        `template_key` = SPR (resolver key), `name` = the legible display name.

    `taken_tokens` are folder names already claimed (the unique tokens) so a
    generic slug that would collide is suffixed with its hex. Quality gate: a SPR
    whose frames all composite empty (garbled/false-positive poses the slicer
    drops) yields no events and is skipped, so no empty folders ship."""
    if sprite_types is None:
        sprite_types = load_sprite_types()
    taken = set(taken_tokens or ())
    skip = {h.upper() for h in (skip_hexids or ())}
    generic_events = result.generic if result is not None else {}
    emitted: list = []
    for hexkey in sorted(sprite_files, key=lambda x: int(x, 16)):
        hexid = hexkey.upper()
        if hexid in skip:                        # already owned by a unique folder
            continue
        spr_name = sprite_files.get(hexid, {}).get("filename", "")
        src_body = textures_dir / f"{hexid}.tga"
        src_pal = textures_dir / f"{hexid}.palette.tga"
        te = generic_events.get(int(hexid, 16))
        # Nothing to emit if there's neither a flat body nor recovered frames.
        if not (src_body.exists() and src_pal.exists()) and te is None:
            continue
        token = generic_template_token(hexid, spr_name)
        if token in taken:                       # collision w/ a unique / another SPR
            token = f"{token}_{hexid.lower()}"
        folder = out_root / token
        shutil.rmtree(folder, ignore_errors=True)   # regenerated wholesale
        category = _generic_category(sprite_types, hexid)

        # Cinematic frames when the derivation resolved this SPR (needs the corpus).
        events: dict = {}
        if te is not None and ctx is not None:
            events = emit_event_assets(folder, te, ctx)

        # Owned body + (human) portrait, byte-identical from the flat store. A SPR
        # with no flat body degrades to an events-only folder rather than losing the
        # recovered frames; if it has neither we skipped it above.
        has_portrait = False
        if src_body.exists() and src_pal.exists():
            compressed = should_decompress(spr_name) if spr_name else True
            has_portrait = _emit_owned_body_portrait(
                folder, src_body, src_pal, compressed=compressed,
                portrait=(category == "generic-human"))

        tj = build_generic_template_json(hexid, spr_name, category, sprite_types,
                                         events, has_portrait)
        (folder / "template.json").write_text(json.dumps(tj, indent=2) + "\n")
        taken.add(token)
        emitted.append(folder)
    return emitted


def load_sprite_types() -> dict:
    """The per-sprite_id animation family + scalars (SpriteDatabase's source)."""
    return json.loads(SPRITE_TYPES_PATH.read_text())


def _read_tga(path: Path) -> tuple[int, int, bytes]:
    """(width, height, pixel_bytes) for one of our 32bpp BGRA top-left TGAs."""
    data = path.read_bytes()
    w, h = struct.unpack("<HH", data[12:16])
    return w, h, data[18:]


def _crop_portrait(src_body: Path, y0: int) -> tuple[int, int, list]:
    """Crop the PORTRAIT_W x PORTRAIT_H window at (PORTRAIT_X, y0) out of the
    body sheet, returning (w, h, pixels) as (r, g, b, a) tuples for write_tga."""
    w, _h, px = _read_tga(src_body)
    pixels: list = []
    for y in range(y0, y0 + PORTRAIT_H):
        for x in range(PORTRAIT_X, PORTRAIT_X + PORTRAIT_W):
            i = (y * w + x) * 4
            b, g, r, a = px[i], px[i + 1], px[i + 2], px[i + 3]
            pixels.append((r, g, b, a))
    return PORTRAIT_W, PORTRAIT_H, pixels


def _emit_owned_body_portrait(folder: Path, src_body: Path, src_pal: Path, *,
                              compressed: bool, portrait: bool) -> bool:
    """Copy the byte-identical owned body sheet + palette into `folder`, and
    (when `portrait`) slice the 48x32 portrait crop + its own palette. Returns
    True if a portrait was written.

    Shared by uniques and generic-HUMAN folders; a generic-MONSTER passes
    portrait=False -- monster sheets carry no menu-portrait band to own, so the
    y456 window there is body tiles, not a face.
    """
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src_body, folder / "body.tga")
    shutil.copyfile(src_pal, folder / "body.palette.tga")
    if not portrait:
        return False
    # Portrait: its own sliced sheet + its own (currently identical) palette file.
    shutil.copyfile(src_pal, folder / "portrait.palette.tga")
    y0 = PORTRAIT_Y0_COMPRESSED if compressed else PORTRAIT_Y0_UNCOMPRESSED
    pw, ph, pixels = _crop_portrait(src_body, y0)
    write_tga(str(folder / "portrait.tga"), pw, ph, pixels)
    return True


def _append_sprite_scalars(tj: dict, st: dict) -> dict:
    """Append the shared animation TYPE reference + flying/height scalars onto a
    template.json in-place. `animation` names seq/shp independently (lowercased to
    match the animations store filenames); the sole genuinely-shared asset, always
    referenced, never copied."""
    seq = str(st.get("seq", "")).lower()
    shp = str(st.get("shp", "")).lower()
    if seq or shp:
        tj["animation"] = {"seq": seq, "shp": shp}
    if "flying" in st:
        tj["flying"] = bool(st["flying"])
    if "height" in st:
        tj["height"] = int(st["height"])
    return tj


# Human animation families (TYPE1/2/3); anything else (MON, boss singletons) is a
# monster -- the axis that decides generic-human vs generic-monster and whether a
# menu portrait exists to own.
HUMAN_SHP_FAMILIES = {"TYPE1", "TYPE2", "TYPE3"}


def _generic_category(sprite_types: dict, hexid: str) -> str:
    """`generic-human` | `generic-monster` for a resolved SPR, keyed off its
    animation family (SpriteDatabase's `shp`). Defaults to human when the family
    is unknown (the common generic case is a job sheet)."""
    st = sprite_types.get(hexid.upper()) or sprite_types.get(hexid.lower()) or {}
    fam = str(st.get("shp", "")).upper()
    return "generic-monster" if fam and fam not in HUMAN_SHP_FAMILIES else "generic-human"


# Legible ShiShi / JobDatabase.SPRITE_NAMES display name per SPR file id, so the
# generic/monster folder gets a readable slug (`male_knight`) not an opaque hex
# (`64`). Sourced from JobDatabase.SPRITE_NAMES (jobs 0x60-0x85, monsters
# 0x86-0x9A) + the story-townsperson block (0x4A-0x56), whose NN[MW].SPR
# filenames self-describe age+gender (20W = 20-year-old Woman; user-confirmed
# 4D/4E/4F, funeral priest = SOURYO/0x56). A SPR absent here falls back to its
# slugified filename, then its hex -- so every emitted folder still gets a name.
GENERIC_SPRITE_NAMES = {
    # story / townsperson NPCs -- age + gender read off the NN[MW].SPR filename
    0x4A: "10 year old man",   0x4B: "10 year old woman",
    0x4C: "20 year old man",   0x4D: "20 year old woman",
    0x4E: "40 year old man",   0x4F: "40 year old woman",
    0x50: "60 year old man",   0x51: "60 year old woman",
    0x56: "funeral priest",
    # generic job sprites
    0x60: "Male Squire",     0x61: "Female Squire",
    0x62: "Male Chemist",    0x63: "Female Chemist",
    0x64: "Male Knight",     0x65: "Female Knight",
    0x66: "Male Archer",     0x67: "Female Archer",
    0x68: "Male Monk",       0x69: "Female Monk",
    0x6A: "Male Priest",     0x6B: "Female Priest",
    0x6C: "Male Wizard",     0x6D: "Female Wizard",
    0x6E: "Male Time Mage",  0x6F: "Female Time Mage",
    0x70: "Male Summoner",   0x71: "Female Summoner",
    0x72: "Male Thief",      0x73: "Female Thief",
    0x74: "Male Mediator",   0x75: "Female Mediator",
    0x76: "Male Oracle",     0x77: "Female Oracle",
    0x78: "Male Geomancer",  0x79: "Female Geomancer",
    0x7A: "Male Lancer",     0x7B: "Female Lancer",
    0x7C: "Male Samurai",    0x7D: "Female Samurai",
    0x7E: "Male Ninja",      0x7F: "Female Ninja",
    0x80: "Male Calculator", 0x81: "Female Calculator",
    0x82: "Male Bard",       0x83: "Female Dancer",
    0x84: "Male Mime",       0x85: "Female Mime",
    # monsters
    0x86: "Chocobo",   0x87: "Goblin",    0x88: "Bomb",      0x89: "Coeurl",
    0x8A: "Squid",     0x8B: "Skeleton",  0x8C: "Ghost",     0x8D: "Ahriman",
    0x8E: "Cockatrice", 0x8F: "Uribo",    0x90: "Treant",    0x91: "Minotaur",
    0x92: "Malboro",   0x93: "Behemoth",  0x94: "Dragon",    0x95: "Tiamat",
    0x96: "Apanda",    0x97: "Elidibs",   0x98: "Holy Dragon", 0x99: "Archaic Demon",
    0x9A: "Steel Giant",
}


def _slug(text: str) -> str:
    """Lowercase, non-alphanumeric-runs -> single underscore, trimmed."""
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def generic_template_token(hexid: str, spr_name: str) -> str:
    """The legible folder token for a generic/monster SPR: its ShiShi display
    name slugified (`male_knight`, `40_year_old_woman`, `funeral_priest`), else
    the slugified SPR filename (`hebi`), else the hex. Deterministic, so a regen
    is stable and the flat-store-input tree stays clean."""
    name = GENERIC_SPRITE_NAMES.get(int(hexid, 16))
    if name:
        return _slug(name)
    if spr_name:
        return _slug(spr_name.rsplit(".", 1)[0])
    return hexid.lower()


def build_generic_template_json(hexid: str, spr_name: str, category: str,
                                sprite_types: dict, events: dict | None,
                                has_portrait: bool) -> dict:
    """The template.json for a generic/monster SPR-pooled folder (#222).

    Same schema as a unique (docs/TEMPLATE_JSON_SCHEMA.md) with `category` =
    `generic-human`/`generic-monster`. `template_key` is the resolver key = the
    resolved SPR (the granularity the derivation pools at -- one job sheet serves
    many (job,gender) keys; the folder itself is named by the legible `name`).
    `portrait` is present only when one was sliced (humans). `name`/`sprite_id`/
    `sprite` are kept for legibility + provenance."""
    st = sprite_types.get(hexid.upper()) or sprite_types.get(hexid.lower()) or {}
    tj: dict = {
        "template_key": hexid,
        "category": category,
        "name": GENERIC_SPRITE_NAMES.get(int(hexid, 16), spr_name),
        "sprite_id": hexid,
        "sprite": spr_name,
        "body": {"sprite": "body.tga", "palette": "body.palette.tga"},
    }
    if has_portrait:
        tj["portrait"] = {"sprite": "portrait.tga", "palette": "portrait.palette.tga"}
    if events:
        tj["events"] = events
    return _append_sprite_scalars(tj, st)


def build_cutscene_face_template_json(slug: str, name: str,
                                      events: dict | None) -> dict:
    """The template.json for a cutscene-face identity (ADR-0072 addendum).

    A portrait-only packet: `category` = `cutscene-face`, `template_key` = the
    slug (the ONE key shape where the slug IS the key -- no SPR/special_name), the
    `events.face` cells doubling as the portrait. Deliberately carries **no** body
    or sprite scalars -- these identities have no SPR sheet / animation family."""
    tj: dict = {
        "template_key": slug,
        "category": "cutscene-face",
        "name": name,
    }
    if events:
        tj["events"] = events
    return tj


def emit_cutscene_faces(face_unhomed: dict, cutscene_faces: dict,
                        ctx: EventAssetContext, out_root: Path, *,
                        taken_tokens: set | None = None,
                        cutscene_chr: dict | None = None) -> list:
    """Mint a portrait-only template folder per authored cutscene-face identity.

    `cutscene_faces` is `{slug -> identity-table display name}` (cutscene_faces.json
    -- the human identity call); `face_unhomed` is `{display name -> [(row,col)]}`
    from the derivation (the un-homed EVTFACE cells); `cutscene_chr` is
    `{slug -> TokenEvents}` (the derivation's SPR-less cinematic frames -- Balbanes'
    deathbed poses homed by dialogue-name slug, `DerivationResult.cutscene`). For
    each authored identity we slice its grid cells into `events/face/NN.tga` AND its
    cinematic frames into `events/chr/NN.tga`, then write a body-less `template.json`
    (category `cutscene-face`). A slug that collides with an already-emitted folder
    is suffixed `_face`; an identity with neither un-homed cells nor cinematic frames
    (renamed, or already homed to a unique) is skipped with a note."""
    taken = set(taken_tokens or ())
    cutscene_chr = cutscene_chr or {}
    emitted: list = []
    for slug, name in sorted(cutscene_faces.items()):
        cells = face_unhomed.get(name) or []
        chr_te = cutscene_chr.get(slug)
        chr_pairs = list(chr_te.chr) if chr_te else []
        if not cells and not chr_pairs:
            print(f"[align] cutscene-face {slug!r} ({name!r}): no un-homed cells/frames -- skipped")
            continue
        token = slug if slug not in taken else f"{slug}_face"
        folder = out_root / token
        shutil.rmtree(folder, ignore_errors=True)   # regenerated wholesale
        te = ead.TokenEvents(face=[tuple(c) for c in cells],
                             chr=[tuple(p) for p in chr_pairs])
        events = emit_event_assets(folder, te, ctx)
        if not events:
            shutil.rmtree(folder, ignore_errors=True)
            print(f"[align] cutscene-face {slug!r}: all cells/frames failed to slice -- skipped")
            continue
        taken.add(token)
        tj = build_cutscene_face_template_json(token, name, events)
        (folder / "template.json").write_text(json.dumps(tj, indent=2) + "\n")
        emitted.append(folder)
    return emitted


def build_template_json(special_name: int, body_sprite_id: str,
                        sprite_types: dict, events: dict | None = None) -> dict:
    """The template.json for one unique, per docs/TEMPLATE_JSON_SCHEMA.md.

    animation TYPE is referenced by name (lowercased to match the animations
    store filenames <name>_seq.json / <name>_shp.json); seq/shp are independent.
    `formation` is omitted (RE gap). `events` is included when the derivation
    (#204) supplies sliced frames/cells, omitted otherwise (see module docstring).
    """
    st = sprite_types.get(body_sprite_id.upper()) or sprite_types.get(body_sprite_id.lower()) or {}
    tj: dict = {
        "template_key": str(special_name),
        "category": "unique",
        "body": {"sprite": "body.tga", "palette": "body.palette.tga"},
        "portrait": {"sprite": "portrait.tga", "palette": "portrait.palette.tga"},
    }
    if events:
        tj["events"] = events
    return _append_sprite_scalars(tj, st)


def emit_unique(*, special_name: int, token: str, body_sprite_id: str,
                textures_dir: Path, out_root: Path, compressed: bool = True,
                sprite_types: dict | None = None,
                token_events: ead.TokenEvents | None = None,
                event_ctx: EventAssetContext | None = None) -> Path:
    """Emit one unique's template folder; returns the folder path.

    body.tga/body.palette.tga are byte-identical copies of the flat sheet (the
    template *owns* self-contained files, but the pixels are unchanged so parity
    with the flat store is exact). portrait.palette.tga is the same 16x16 CLUT as
    a self-contained, independently-moddable file (the portrait region uses row 8
    per unit_portrait_3d.gdshader; keeping the full CLUT loses no color).
    """
    if sprite_types is None:
        sprite_types = load_sprite_types()

    src_body = textures_dir / f"{body_sprite_id.upper()}.tga"
    src_pal = textures_dir / f"{body_sprite_id.upper()}.palette.tga"
    if not src_body.exists() or not src_pal.exists():
        raise FileNotFoundError(
            f"flat-store body for sprite 0x{body_sprite_id.upper()} not found "
            f"({src_body} / {src_pal}) -- run the extract first"
        )

    folder = out_root / token
    # Owned body sheet + palette (byte-identical slices of the flat store) + the
    # 48x32 portrait crop with its own palette. Uniques always own a portrait.
    _emit_owned_body_portrait(folder, src_body, src_pal,
                              compressed=compressed, portrait=True)

    # Owned, sliced event collections (#204) -- only when the derivation supplied
    # coordinates and a slicing context (the corpus/atlas are gitignored). Wipe any
    # prior events/ first so a unique that USED to derive frames but now derives none
    # (all false positives, e.g. delita_6) doesn't keep stale slices on disk; only
    # when an event context is present (a no-corpus run must leave good events alone).
    events: dict = {}
    if event_ctx is not None:
        shutil.rmtree(folder / "events", ignore_errors=True)
        if token_events is not None:
            events = emit_event_assets(folder, token_events, event_ctx)

    tj = build_template_json(special_name, body_sprite_id, sprite_types, events)
    (folder / "template.json").write_text(json.dumps(tj, indent=2) + "\n")
    return folder


def _write_event_map(result: ead.DerivationResult,
                     sprite_files: dict | None = None) -> None:
    """Persist the transform-internal segment->character residue (#204/#206).

    This is the recovered mapping the ROM never stored -- kept for provenance,
    debugging and re-slicing, deliberately OUT of template.json (coord-free per
    #200). Each `chr` entry is `[segment, frame_id, palette_row|null]` (the row is
    the `{7F}` binding or the fingerprint-recovered single-resident row, null when
    neither is known). `generics` is the shared store (#206): a resolved SPR with no
    unique token -> its pooled frames (a job-class generic / non-residue sprite).
    `unresolved` records references we skipped -- `anim:<sn>` / `face:<sn>` are
    identity-less (no resolvable sprite at all). `dropped` records cinematic anims
    dropped by the residency tiers (>=2 resident & unbound, or 0 resident), keyed
    `token:tier` -- so the sparsity is explicit, not silent
    (EVTCHR_CHARACTER_ATTRIBUTION.md)."""
    sprite_files = sprite_files or {}
    out = {
        "_note": ("Transform-internal event-asset derivation (#204/#206). Recovered "
                  "segment->character binding; NOT a runtime read surface."),
        "tokens": {tok: {"chr": [list(p) for p in te.chr],
                         "face": [list(p) for p in te.face],
                         "anims": [list(a) for a in te.anims]}
                   for tok, te in sorted(result.tokens.items())},
        "generics": {f"{spr:02X}": {
                        "sprite": sprite_files.get(f"{spr:02X}", {}).get("filename", ""),
                        "chr": [list(p) for p in te.chr],
                        "anims": [list(a) for a in te.anims]}
                     for spr, te in sorted(result.generic.items())},
        # SPR-less cutscene-face identities (Balbanes et al.): {7F}-bound cinematic
        # frames homed by dialogue-name slug (no flat-store SPR palette matched), so
        # they don't mis-file under the ENTD decoy sprite. slug -> chr frames + anims.
        "cutscene_faces": {slug: {"chr": [list(p) for p in te.chr],
                                  "anims": [list(a) for a in te.anims]}
                           for slug, te in sorted(result.cutscene.items())},
        "unresolved": {f"{kind}:{ref}": n
                       for (kind, ref), n in sorted(result.unresolved.items(),
                                                    key=lambda kv: -kv[1])},
        "dropped": {f"{tok}:{tier}": n
                    for (tok, tier), n in sorted(result.dropped.items(),
                                                 key=lambda kv: -kv[1])},
        # EVTFACE cells whose identity owns no unique template token: SPR-less named
        # identities (to be minted) + pure generics the global grid serves. Kept for
        # provenance so the coverage is explicit, not silently dropped.
        "faces_unhomed": {name: [list(c) for c in cells]
                          for name, cells in sorted(result.face_unhomed.items())},
    }
    EVENT_MAP_PATH.write_text(json.dumps(out, indent=2) + "\n")


def _cleanup_legacy_generic_root() -> None:
    """Remove the retired `characters/generics/` SPR-hex tree if a prior build
    left one (generics now live in the shared template tree, named legibly)."""
    shutil.rmtree(LEGACY_GENERIC_ROOT, ignore_errors=True)


def run(out_root: Path = DEFAULT_OUT_ROOT, textures_dir: Path = TEXTURES_DIR,
        with_events: bool = True) -> list[Path]:
    """Emit every unique's template folder. Compression (hence the portrait band
    location) is derived per sprite from its SPR filename via should_decompress.

    When `with_events` and the (gitignored) event corpus + EVTCHR/EVTFACE atlases
    are present, also derives (#204) and slices each unique's `events/{chr,face}`
    collection, emits the generic/monster template packets (#222) into the SAME
    `out_root` (one template tree -- named legibly, e.g. `male_knight`), and writes
    the transform-internal `event_asset_map.json`. If the corpus is absent the
    folders are emitted without events (the flat-store / non-event assets are
    unaffected)."""
    residue = json.loads(RESIDUE_PATH.read_text())["residue"]
    assets = json.loads(ASSETS_PATH.read_text())["assets"]
    sprite_types = load_sprite_types()
    sprite_files = json.loads(SPRITE_FILES_PATH.read_text())

    event_result: ead.DerivationResult | None = None
    event_ctx: EventAssetContext | None = None
    if with_events:
        try:
            event_result = derive_event_assets()
        except FileNotFoundError as exc:
            print(f"[align] event assets skipped: {exc}")
        else:
            _write_event_map(event_result, sprite_files)
            evtchr_frames = json.loads(EVTCHR_FRAMES_PATH.read_text())
            event_ctx = EventAssetContext(EVTCHR_DIR, evtchr_frames, FACES_DIR)

    emitted: list[Path] = []
    for sn_str, token in sorted(residue.items(), key=lambda kv: int(kv[0])):
        entry = assets.get(sn_str)
        if entry is None:
            raise SystemExit(
                f"template_assets.json is missing special_name {sn_str} ({token}); "
                f"the identity and asset residues must agree"
            )
        body_id = entry["body_sprite_id"]
        spr_name = sprite_files.get(body_id.upper(), {}).get("filename", "")
        compressed = should_decompress(spr_name) if spr_name else True
        token_events = event_result.tokens.get(token) if event_result else None
        folder = emit_unique(
            special_name=int(sn_str), token=token, body_sprite_id=body_id,
            textures_dir=textures_dir, out_root=out_root, compressed=compressed,
            sprite_types=sprite_types,
            token_events=token_events, event_ctx=event_ctx,
        )
        emitted.append(folder)

    # Generic/monster template packets (#222): one legibly-named folder per sprite id
    # in the full table (0x01-0x9A) that a unique doesn't already own -- an owned
    # body/palette (+ human portrait), plus the SPR-pooled cinematic frames when the
    # derivation resolved them. In the SAME template tree as the uniques (no separate
    # root). Pass the unique folder names so a generic slug never overwrites a
    # unique's folder, and the unique-owned sprite ids so we don't re-emit their body.
    _cleanup_legacy_generic_root()
    unique_ids = {assets[sn]["body_sprite_id"].upper()
                  for sn in residue if sn in assets}
    generics = emit_generic_store(event_result, event_ctx, out_root,
                                  sprite_files, textures_dir=textures_dir,
                                  sprite_types=sprite_types,
                                  taken_tokens={f.name for f in emitted},
                                  skip_hexids=unique_ids)
    if generics:
        print(f"[align] generic/monster templates: {len(generics)} folders")
    emitted.extend(generics)

    # Cutscene-face identities (ADR-0072 addendum): portrait-only folders for
    # SPR-less named identities (Balbanes et al.) the global grid can't attribute
    # to a unique. Authored in cutscene_faces.json; cells from the derivation's
    # un-homed EVTFACE table. Pure generics stay un-minted (global grid serves).
    if event_result is not None and event_ctx is not None and CUTSCENE_FACES_PATH.exists():
        cutscene_faces = json.loads(CUTSCENE_FACES_PATH.read_text())["faces"]
        taken = {f.name for f in emitted}
        faces = emit_cutscene_faces(event_result.face_unhomed, cutscene_faces,
                                    event_ctx, out_root, taken_tokens=taken,
                                    cutscene_chr=event_result.cutscene)
        if faces:
            print(f"[align] cutscene-face templates: {len(faces)} folders "
                  f"({', '.join(sorted(f.name for f in faces))})")
        emitted.extend(faces)
    return emitted


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--output", type=Path, default=DEFAULT_OUT_ROOT,
                    help="template tree root (default: assets/characters/templates)")
    ap.add_argument("--textures", type=Path, default=TEXTURES_DIR,
                    help="flat-store textures dir (default: assets/sprites/textures)")
    ap.add_argument("--no-events", action="store_true",
                    help="skip the #204 event-asset derivation/slicing (faster; "
                         "emits body/portrait only)")
    args = ap.parse_args()

    emitted = run(out_root=args.output, textures_dir=args.textures,
                  with_events=not args.no_events)
    print(f"Emitted {len(emitted)} template folder(s) under {args.output}:")
    for f in sorted(emitted, key=lambda p: p.name):
        print(f"  {f.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
