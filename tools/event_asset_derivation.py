#!/usr/bin/env python3
"""Event-asset derivation -- recover the `character -> event frame/cell` binding
the ROM never stored (wayfinder #204, ADR-0072 dec.5).

EVTCHR (137 cinematic segment sheets) and EVTFACE (an 8x8 dialogue-portrait grid)
carry NO character axis in the extract: a segment is keyed `(segment, anim)`, a
face by `(row, col)`. Which character owns which frame/cell exists ONLY in the
event instruction stream, dynamically. This module replays that stream statically
to recover the mapping, so the character-alignment transform can slice each
frame/cell into the owning unique's template folder (`events/chr`, `events/face`).

The derivation, per chunk (one chunk == one scenario_id's TEST.EVT event; the
chunk file is `chunks/scenario_%03d_chunk.json`):

  * `{58} Load EVTCHR {Block, Slot}` makes segment `Slot` resident in VRAM `Block`;
    the last one fired is the active cinematic block. (`Slot` IS the segment id for
    the identity scenarios -- ScenarioVM._resolve_cinematic_segment; the chapel's
    non-identity Slot->segment table is the open #124 gap and rides through here as
    whatever ScenarioVM would resolve, so the slice matches what the runtime draws.)
  * `{11} Unit Anim {Units, Multi, Animation}` with `Multi==0` (single unit; a
    non-zero Multi is a broadcast SET selector, not a unit id -- ScenarioDecode)
    and `Animation >= 0x1F4` (the EVTCHR cinematic band -- ScenarioVM._cinematic_
    band_base) binds the resident segment to that unit. `Units` is the ENTD slot's
    `unit_id`; the FRAME'S TRUE OWNER is the *resolved SPR* (the sprites list), NOT
    the slot's `special_name`. On a shared/composite sheet a unit's `special_name`
    is unreliable (event-puppet slots `unit_id >= 0x80` reuse a story identity --
    e.g. a slot tagged Delita that actually renders Ovelia's art); the palette the
    unit samples is what identifies it. So the owner is resolved by:
      - `{7F}`-bound tier: fingerprint the bound CLUT row against every flat-store
        SPR palette (`SegmentOwnerResolver.owner_of`) -> the exact-match SPR;
      - single-resident tier: the unit's ENTD `sprite_set` -> `resolve_sprite`
        gives the SPR, and the matching segment row recovers its palette row.
    The resolved SPR maps to a template token via `spr_to_token`; `special_name`
    only survives as a fallback (unpromoted SPR) and for the portrait path.
  * The local index into `cinematic_seq.json[segment]` is `Animation - band_base`;
    that anim's `LoadFrameWait` ops name the EVTCHR frame ids (0xD2..0xF9) drawn.

EVTFACE dialogue portraits (`{50}`/`{10}`) are NOT derived here anymore. A face
cell's identity is its `(row,col)` grid slot, and the authority for who each slot
is comes from the dialogue speaker name (`evtface_identity.py`), NOT the ENTD
speaking `Unit` (scene-local, mis-attributes -- see EVTFACE handoffs 2026-07-20).
`align_character_templates.derive_event_assets` folds that identity table into
`result.tokens[tok].face` for the SPR-backed uniques after this replay.

Units are accumulated across the whole corpus and de-duplicated in first-seen
order (a stable ordinal `index` per the #200 schema). Unresolved references --
generic units (`special_name` 0xFF), player-party ids not in the ENTD record,
non-cinematic anims -- are counted and skipped, never guessed.

This is a transform-INTERNAL derivation. The recovered `(segment, frame_id)` /
`(row, col)` coordinates are used only to cut the slice; per #200's locked
coord-free read surface they are NOT emitted into `template.json` (they live in
the transform's own `event_asset_map.json`).
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field

from evtface_identity import extract_speaker_name
from resolve_sprite import resolve_sprite

# --- cinematic anim band split (ScenarioVM._cinematic_band_base) ---
BAND_MID = 0x1F4   # scenario-6 carry table 0x800A77D8
BAND_HIGH = 0x258  # Orbonne chapel table  0x800AED3C
GENERIC_SPECIAL_NAME = 0xFF

# EVTCHR opcodes / EVTFACE opcodes we care about.
OP_DISPLAY_MESSAGE = 0x10
OP_UNIT_ANIM = 0x11
OP_PORTRAIT_ROW = 0x50
OP_LOAD_EVTCHR = 0x58
OP_SAVE_EVTCHR_CLEAR = 0x5A   # frees a VRAM block (evtchr_load_save_decode.md)
OP_LOAD_EVTCHR_CLEAR = 0x5B   # resets the current load state -> block no longer resident
OP_EVTCHR_PALETTE = 0x7F      # {7F} {Unit, Block, Palette}: per-unit block+palette binding

# cinematic_seq op that loads a drawable frame; its param_0 is the frame id.
FRAME_LOAD_OP = "LoadFrameWait"

# The dispatcher's EVTCHR-vs-TYPE1.SHP threshold (FUN_80083f18, `sltiu s2,0xd2`):
# a cinematic anim's frame id >= 0xD2 draws from the EVTCHR segment sheet, < 0xD2
# from the unit's OWN TYPE1.SHP body sheet (the template already owns that as
# body.tga). Some anims mix both (e.g. Agrias's reaction 0x25C flips mid-sequence);
# only the >=0xD2 ids are EVTCHR frames. See EVTCHR_FRAME_RESOLUTION.md §9.
EVTCHR_FRAME_MIN = 0xD2


def band_base(anim_id: int) -> int:
    """The zero-point of the cinematic band `anim_id` falls in, or -1 if the anim
    is below 0x1F4 (a per-unit SHP animation, not an EVTCHR cinematic)."""
    if anim_id >= BAND_HIGH:
        return BAND_HIGH
    if anim_id >= BAND_MID:
        return BAND_MID
    return -1


def frame_ids_for_anim(cinematic_seq: dict, segment: int, local: int) -> list[int]:
    """The EVTCHR frame ids a cinematic anim draws, in play order.

    `cinematic_seq` is `assets/sprites/animations/cinematic_seq.json`
    (`{segment: {local_anim: [instruction, ...]}}`). Returns the `LoadFrameWait`
    param_0 frame ids; empty if the segment/anim is absent (the anim plays no
    EVTCHR frame -- e.g. a body-SEQ fallthrough)."""
    seg = cinematic_seq.get(str(segment))
    if not seg:
        return []
    anim = seg.get(str(local))
    if not anim:
        return []
    out: list[int] = []
    for ins in anim:
        if ins.get("op_code_name") == FRAME_LOAD_OP:
            fid = ins.get("op_code_param_0")
            if fid is not None and int(fid) >= EVTCHR_FRAME_MIN:
                out.append(int(fid))  # < 0xD2 = the unit's TYPE1.SHP body, not EVTCHR
    return out


def uid_to_slot(entd_record: dict) -> dict[int, dict]:
    """{event unit_id -> ENTD slot dict} for one record's 16 slots.

    The slot carries the fields the SPR-keyed attribution needs: `special_name`
    (portrait path + fallback), `sprite_set` + `job` (the resolved SPR)."""
    out: dict[int, dict] = {}
    for slot in entd_record.get("slots", []):
        uid = slot.get("unit_id")
        if uid is not None:
            out[uid] = slot
    return out


# The ENTD "no special name" sentinel: a slot with special_name 0xFF is anonymous
# generic filler, so it must NOT inherit a named identity from a scene sibling.
GENERIC_SPECIAL_NAME = 0xFF


def unit_cutscene_faces(instructions: list, name_to_slug: dict,
                        uid_slots: dict | None = None) -> dict[int, str]:
    """`{unit_id -> cutscene-face slug}` for one chunk, recovered from its dialogue.

    A `{10} Display Message`'s `{Color 08}` speaker header names the speaking unit;
    when that name is an authored cutscene-face (`name_to_slug`, from
    `cutscene_faces.json`) the message's `speaker_unit_byte` IS that identity's unit
    id for this scene. This is scene-local (unit 128 is Balbanes in scn14, someone
    else elsewhere), so the map is built PER CHUNK -- the EVTCHR sibling of
    `evtface_identity.derive_evtface_identities`'s per-cell name recovery. It exists
    to home a SPR-less identity's cinematic frames to its slug instead of the ENTD
    decoy sprite (`derive_chunk` tier-1 owner-None branch).

    A cutscene-face identity attaches to its ENTD `special_name`, not just the one
    puppet slot that speaks: a cinematic often splits the role across two same-
    `special_name` event puppets -- a SPEAKER slot the `{10}` names and a separate
    ANIMATOR slot that carries the `{7F}` palette binding + the `{11}` anims (Elidibs
    scn112: speaker unit 128 names it, animator unit 129 draws it). Given `uid_slots`
    ({unit_id -> ENTD slot}), we propagate each named speaker's slug to every sibling
    slot sharing its `special_name`, so the animator's frames home to the identity
    too. The `0xFF` generic sentinel is never a shared identity, so it is excluded --
    it would otherwise sweep every anonymous filler in the scene into the name."""
    out: dict[int, str] = {}
    if not name_to_slug:
        return out
    for inst in instructions:
        if inst.get("opcode") != OP_DISPLAY_MESSAGE:
            continue
        dlg = inst.get("dialogue", {}) or {}
        name = extract_speaker_name(dlg.get("raw_text", "") or "")
        slug = name_to_slug.get(name) if name else None
        if slug is None:
            continue
        unit = dlg.get("speaker_unit_byte")
        if unit is not None:
            out.setdefault(int(unit), slug)      # first binding wins (stable)

    if uid_slots:
        # {special_name -> slug} from the directly-named speakers (first-named wins).
        sn_to_slug: dict[int, str] = {}
        for unit, slug in out.items():
            slot = uid_slots.get(unit)
            sn = slot.get("special_name") if slot else None
            if sn is None or int(sn) == GENERIC_SPECIAL_NAME:
                continue
            sn_to_slug.setdefault(int(sn), slug)
        for unit, slot in uid_slots.items():
            sn = slot.get("special_name")
            if sn is None:
                continue
            slug = sn_to_slug.get(int(sn))
            if slug is not None:
                out.setdefault(int(unit), slug)
    return out


def resolved_sprite_of(slot: dict) -> int | None:
    """The flat-store SPR a unit renders with, from its ENTD `sprite_set`/`job`.

    Returns None only if the slot has no `sprite_set` (never happens for a real
    ENTD record)."""
    ss = slot.get("sprite_set")
    if ss is None:
        return None
    return resolve_sprite(int(ss), int(slot.get("job", 0) or 0),
                          bool(slot.get("female", False)))


def _params(inst: dict) -> dict:
    return {p["name"]: p["value"] for p in inst.get("params", [])}


@dataclass
class TokenEvents:
    """One unique's derived event assets: ordered, de-duplicated coordinate lists.

    `chr`/`face` are the sliceable units (a frame / a cell); `anims` is the
    `(segment, local, anim_id)` provenance kept for the manifest + debugging.
    A chr entry carries the `{7F}` palette row when the anim was palette-bound,
    else `None` (single-resident-segment tier -- row unknown, keep full CLUT)."""
    chr: list = field(default_factory=list)    # [(segment, frame_id, palette_row|None)]
    face: list = field(default_factory=list)   # [(row, col)]
    anims: list = field(default_factory=list)  # [(segment, local, anim_id)]

    def add_chr(self, pair: tuple) -> None:
        if pair not in self.chr:
            self.chr.append(pair)

    def add_face(self, pair: tuple) -> None:
        if pair not in self.face:
            self.face.append(pair)

    def add_anim(self, triple: tuple) -> None:
        if triple not in self.anims:
            self.anims.append(triple)


@dataclass
class DerivationResult:
    tokens: dict = field(default_factory=dict)      # token -> TokenEvents
    generic: dict = field(default_factory=dict)     # resolved SPR (int) -> TokenEvents
    # SPR-less cutscene-face identities (Balbanes et al.): a dialogue-named identity
    # with no ENTD/SPR footprint whose {7F}-bound cinematic frames would otherwise
    # mis-file under the ENTD decoy sprite. cutscene-face slug -> TokenEvents.
    cutscene: dict = field(default_factory=dict)
    unresolved: Counter = field(default_factory=Counter)  # ("anim"|"face", special_name) -> n
    dropped: Counter = field(default_factory=Counter)     # (token, "multiseg"|"zeroseg") -> n
    # EVTFACE cells whose identity has no unique template token: SPR-less named
    # identities (Balbanes et al., pending a minted portrait-only folder) and pure
    # generics the global EVTFACE grid already serves. display_name -> [(row,col)].
    face_unhomed: dict = field(default_factory=dict)

    def token(self, tok: str) -> TokenEvents:
        return self.tokens.setdefault(tok, TokenEvents())

    def generic_bucket(self, spr: int) -> TokenEvents:
        """The shared generic events store for a resolved SPR with no unique token
        (#206 emit-only): a job-class generic / non-residue sprite whose cinematic
        frames are pooled by SPR rather than invented into a per-unit template."""
        return self.generic.setdefault(spr, TokenEvents())

    def cutscene_bucket(self, slug: str) -> TokenEvents:
        """The event store for a SPR-less cutscene-face identity (Balbanes et al.):
        frames homed by dialogue-name slug because no flat-store SPR palette matches
        (`owner_of` -> None) -- the EVTCHR analog of the EVTFACE identity bridge."""
        return self.cutscene.setdefault(slug, TokenEvents())


def derive_chunk(instructions: list, uid_slots: dict, spr_to_token: dict,
                 residue: dict, cinematic_seq: dict, result: DerivationResult,
                 owner_resolver=None, unit_to_cutscene_face=None) -> None:
    """Replay one chunk's instruction stream into `result`.

    `uid_slots` is `{unit_id -> ENTD slot dict}` for the chunk's scenario;
    `spr_to_token` is `{resolved_SPR (int) -> template token}` (the sprites list);
    `residue` is `{special_name_str -> token}` (portrait path + unpromoted-SPR
    fallback); `owner_resolver` is a `SegmentOwnerResolver` (palette fingerprint)
    or None. Mutates `result`.

    Segment + palette row are confidence-tiered PER UNIT (residency, not a global
    last-loaded block -- the renderer resolves EVTCHR per unit `FUN_80082110`, VRAM
    holds only two slots). The FRAME OWNER is then the resolved SPR, not the slot's
    `special_name`:

      1. `{7F}`-bound to a resident block -> that block's segment + palette row; the
         owner is the SPR whose palette EXACTLY matches that CLUT row (fingerprint)
         -- this is what routes an event-puppet's frames to their real character.
      2. else exactly one segment resident -> that segment; the owner is the unit's
         own ENTD `sprite_set` resolved to an SPR, and the matching CLUT row on the
         resident sheet recovers its palette row.
      3. else (>=2 resident & unbound, or 0 resident) -> DROP as a false positive.

    The owning SPR routes to a token via `spr_to_token`; if that SPR has no unique
    token (a job-class generic / non-residue sprite), the unit's `special_name`
    residue token is the fallback, and if there is none the frames pool into the
    shared generic store `result.generic[SPR]` (#206 emit-only). Only a unit with no
    resolvable SPR at all is recorded `unresolved[("anim", special_name)]`.
    """
    if unit_to_cutscene_face is None:
        unit_to_cutscene_face = {}
    block_to_slot: dict[int, int] = {}
    resident_blocks: set[int] = set()          # VRAM blocks currently holding a segment
    unit_binding: dict[int, tuple] = {}        # unit_id -> (block, palette_row) from {7F}

    def resident_segments() -> set[int]:
        return {block_to_slot[b] for b in resident_blocks if b in block_to_slot}

    for inst in instructions:
        op = inst.get("opcode")
        if op == OP_LOAD_EVTCHR:
            ps = _params(inst)
            block = ps.get("Block")
            block_to_slot[block] = ps.get("Slot")
            resident_blocks.add(block)
        elif op in (OP_SAVE_EVTCHR_CLEAR, OP_LOAD_EVTCHR_CLEAR):
            resident_blocks.discard(_params(inst).get("Block"))
        elif op == OP_EVTCHR_PALETTE:
            ps = _params(inst)
            unit_binding[ps.get("Unit")] = (ps.get("Block"), ps.get("Palette"))
        elif op == OP_UNIT_ANIM:
            ps = _params(inst)
            if int(ps.get("Multi", 0)) != 0:
                continue  # broadcast SET selector, not a single unit id
            anim = int(ps.get("Animation", 0))
            base = band_base(anim)
            if base < 0:
                continue  # per-unit SHP animation, not an EVTCHR cinematic
            unit = ps.get("Units")
            slot = uid_slots.get(unit)
            if slot is None:
                result.unresolved[("anim", None)] += 1
                continue
            sn = slot.get("special_name")
            # nominal identity, for drop labels + the unpromoted-SPR fallback
            nominal = residue.get(str(sn)) if sn is not None else None

            # --- tiered per-unit segment + palette-row resolution (residency) ---
            segment: int | None = None
            palette_row: int | None = None
            bound = unit_binding.get(unit)
            tier1 = (bound is not None and bound[0] in resident_blocks
                     and bound[0] in block_to_slot)
            if tier1:
                segment = int(block_to_slot[bound[0]])   # tier 1: {7F}-bound
                palette_row = int(bound[1])
            else:
                segs = resident_segments()
                if len(segs) == 1:
                    segment = int(next(iter(segs)))      # tier 2: single resident
                else:                                    # tier 3: ambiguous / none
                    label = nominal or f"sn{sn}"
                    result.dropped[(label, "multiseg" if segs else "zeroseg")] += 1
                    continue

            # --- owner = the RESOLVED SPR (not special_name) ---
            spr: int | None = None
            if tier1 and owner_resolver is not None:
                spr = owner_resolver.owner_of(segment, palette_row)

            # SPR-less named identity (cutscene-face): the {7F} palette matched NO
            # flat-store SPR (`owner_of` -> None), but the unit is a dialogue-named
            # cutscene-face (Balbanes et al.). Home its frames to that identity's slug
            # rather than falling through to the ENTD decoy sprite (Balbanes' deathbed
            # frames were mis-filing under Alma's decoy) -- the EVTCHR analog of the
            # EVTFACE identity bridge. Keyed on the tier-1 owner-None signal only: a
            # tier-2 unit always resolves a decoy SPR, never None.
            cutscene_slug = unit_to_cutscene_face.get(unit) if (tier1 and spr is None) else None

            if cutscene_slug is not None:
                te = result.cutscene_bucket(cutscene_slug)
            else:
                if spr is None:
                    spr = resolved_sprite_of(slot)       # ENTD sprite_set -> SPR
                if not tier1 and owner_resolver is not None and spr is not None:
                    r = owner_resolver.row_for_sprite(segment, spr)
                    if r is not None:
                        palette_row = r                  # recover the non-{7F} row

                tok = (spr_to_token.get(spr) if spr is not None else None) or nominal
                if tok:
                    te = result.token(tok)               # a unique template folder
                elif spr is not None:
                    te = result.generic_bucket(spr)      # shared generic store (#206)
                else:
                    result.unresolved[("anim", sn)] += 1 # no SPR -> identity-less
                    continue

            local = anim - base
            te.add_anim((segment, local, anim))
            for fid in frame_ids_for_anim(cinematic_seq, segment, local):
                te.add_chr((segment, fid, palette_row))
        # NB: EVTFACE `{50}`/`{10}` portraits are NOT attributed here. A face cell's
        # identity is its `(row,col)` grid slot, recovered from the dialogue speaker
        # name (`evtface_identity.py`), not from the ENTD speaking Unit (which is
        # scene-local and mis-attributes). `align_character_templates` folds the
        # identity-table faces into `result.tokens[tok].face` after the replay.


def derive_corpus(chunks: dict, scenarios_by_sid: dict, entd_records: dict,
                  residue: dict, cinematic_seq: dict, spr_to_token: dict | None = None,
                  owner_resolver=None, name_to_slug: dict | None = None) -> DerivationResult:
    """Replay every chunk in `chunks` ({scenario_id -> [instruction, ...]}).

    `scenarios_by_sid` is `{scenario_id -> scenario dict (carries entd_idx)}`;
    `entd_records` is entd.json's `records` ({entd_idx_str -> record}); `residue`
    is `{special_name_str -> token}`; `spr_to_token` is `{SPR (int) -> token}`
    (defaults to a residue-derived identity map); `owner_resolver` is the palette
    fingerprint (or None); `name_to_slug` is `{display name -> cutscene-face slug}`
    (cutscene_faces.json inverted) enabling the SPR-less identity bridge. Chunks are
    walked in ascending scenario_id so first-seen ordinal indices are stable."""
    return derive_corpus_streaming(
        {sid: (lambda insts=insts: insts) for sid, insts in chunks.items()},
        scenarios_by_sid, entd_records, residue, cinematic_seq,
        spr_to_token=spr_to_token, owner_resolver=owner_resolver,
        name_to_slug=name_to_slug)


def derive_corpus_streaming(chunk_loaders: dict, scenarios_by_sid: dict,
                            entd_records: dict, residue: dict,
                            cinematic_seq: dict, spr_to_token: dict | None = None,
                            owner_resolver=None,
                            name_to_slug: dict | None = None) -> DerivationResult:
    """Like `derive_corpus`, but `chunk_loaders` maps `scenario_id -> callable`
    that returns that chunk's instruction list on demand -- so the 500-chunk,
    ~200 MiB corpus is read one file at a time, never all held in memory.

    `name_to_slug` (`{display name -> cutscene-face slug}`) enables the per-chunk
    unit->cutscene-face bridge (SPR-less identity homing); omit it and the bridge is
    inert. Chunks are walked in ascending scenario_id so first-seen ordinal indices
    are stable across regenerations."""
    if spr_to_token is None:
        spr_to_token = {}
    if name_to_slug is None:
        name_to_slug = {}
    result = DerivationResult()
    for sid in sorted(chunk_loaders, key=int):
        scenario = scenarios_by_sid.get(int(sid))
        if scenario is None:
            continue
        record = entd_records.get(str(scenario.get("entd_idx")))
        if record is None:
            continue
        uid_slots = uid_to_slot(record)
        instructions = chunk_loaders[sid]()
        u2cf = unit_cutscene_faces(instructions, name_to_slug, uid_slots)
        derive_chunk(instructions, uid_slots, spr_to_token, residue, cinematic_seq,
                     result, owner_resolver=owner_resolver,
                     unit_to_cutscene_face=u2cf)
    return result
