#!/usr/bin/env python3
"""Guard for the event-asset derivation (wayfinder #204, ADR-0072 dec.5).

Replays a hand-built miniature event corpus and asserts the recovered
`character -> (segment, frame_id)` / `(row, col)` binding, plus the skip rules
for the references that must NOT resolve (broadcast anims, non-cinematic anims,
generic units, hidden portraits).

Run:  uv run python -m unittest test_event_asset_derivation
"""

from __future__ import annotations

import unittest

import event_asset_derivation as ead
from resolve_sprite import resolve_sprite


def _inst(opcode: int, **params) -> dict:
    return {"opcode": opcode, "params": [{"name": k, "value": v}
                                         for k, v in params.items()]}


def _msg(speaker_unit_byte: int, name: str, **params) -> dict:
    """A `{10} Display Message` carrying a decoded dialogue block (speaker byte +
    a `{Color 08}<name>` header) -- the source for the unit->cutscene-face bridge."""
    inst = _inst(0x10, **params)
    inst["dialogue"] = {"speaker_unit_byte": speaker_unit_byte,
                        "raw_text": f"{{Color 08}}{name}{{Newline}}{{Color 00}}hi."}
    return inst


# A miniature cinematic_seq: segments 1 and 2, each with local anims that draw a
# frame (segment 2 exists so a two-segments-resident chunk can be built).
CINEMATIC_SEQ = {
    "1": {
        "0": [{"op_code_name": "LoadFrameWait", "op_code_param_0": 0xD2},
              {"op_code_name": "PauseAnimation", "op_code_param_0": None}],
        "1": [{"op_code_name": "LoadFrameWait", "op_code_param_0": 0xD5}],
    },
    "2": {
        "0": [{"op_code_name": "LoadFrameWait", "op_code_param_0": 0xE0}],
    },
}
# Segment 1, local 2: a mixed anim -- an EVTCHR pose (>=0xD2) then a flip to the
# unit's own TYPE1.SHP body frame (<0xD2), like Agrias's reaction anim 0x25C.
CINEMATIC_SEQ["1"]["2"] = [
    {"op_code_name": "LoadFrameWait", "op_code_param_0": 0xE7},  # EVTCHR
    {"op_code_name": "LoadFrameWait", "op_code_param_0": 0x08},  # TYPE1.SHP body
]

# ENTD record 419: unit_id 128 is a unique (special_name 12 -> ovelia_12),
# unit_id 129 is a generic (special_name 255).
ENTD = {
    "419": {"slots": [
        {"unit_id": 128, "special_name": 12},
        {"unit_id": 129, "special_name": 255},
    ]},
}
SCENARIOS = {7: {"entd_idx": 419}}
RESIDUE = {"12": "ovelia_12"}


class DeriveChrTest(unittest.TestCase):
    def test_load_evtchr_then_cinematic_anim_binds_frames_to_the_unit(self):
        # {58} makes segment 1 resident in block 0; {11} anim 0x1F4 (mid band,
        # local 0) on unit 128 draws frame 0xD2; anim 0x1F5 (local 1) draws 0xD5.
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F5),
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertIn("ovelia_12", res.tokens)
        self.assertEqual(res.tokens["ovelia_12"].chr,
                         [(1, 0xD2, None), (1, 0xD5, None)])  # single-seg tier: row unknown
        self.assertEqual(res.tokens["ovelia_12"].anims,
                         [(1, 0, 0x1F4), (1, 1, 0x1F5)])

    def test_sub_0xd2_frame_ids_are_not_attributed_as_evtchr_frames(self):
        # anim 0x1F6 (local 2) draws [0xE7 (EVTCHR), 0x08 (TYPE1.SHP body)]; only
        # the >=0xD2 frame is an EVTCHR cinematic frame -- the low id belongs to the
        # unit's own body sheet (the dispatcher's 0xD2 threshold, FRAME_RESOLUTION §9).
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F6),
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertEqual(res.tokens["ovelia_12"].chr, [(1, 0xE7, None)])

    def test_high_band_uses_0x258_zero_point(self):
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x11, Units=128, Multi=0, Animation=0x258),  # high band -> local 0
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertEqual(res.tokens["ovelia_12"].chr, [(1, 0xD2, None)])

    def test_duplicate_frame_across_anims_is_deduped_in_first_seen_order(self):
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F5),  # 0xD5
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),  # 0xD2
            _inst(0x11, Units=128, Multi=0, Animation=0x1F5),  # 0xD5 again
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertEqual(res.tokens["ovelia_12"].chr,
                         [(1, 0xD5, None), (1, 0xD2, None)])


class DeriveChrSkipTest(unittest.TestCase):
    def test_broadcast_multi_nonzero_is_not_attributed_to_a_unit(self):
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x11, Units=128, Multi=1, Animation=0x1F4),  # SET selector
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertNotIn("ovelia_12", res.tokens)

    def test_non_cinematic_anim_below_band_is_ignored(self):
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x11, Units=128, Multi=0, Animation=0x10),  # per-unit SHP anim
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertNotIn("ovelia_12", res.tokens)

    def test_generic_unit_is_skipped_and_counted(self):
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x11, Units=129, Multi=0, Animation=0x1F4),  # special_name 255
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertEqual(res.tokens, {})
        self.assertEqual(res.unresolved[("anim", 255)], 1)


class DeriveTierTest(unittest.TestCase):
    """The confidence-tiered per-unit attribution (EVTCHR_CHARACTER_ATTRIBUTION.md):
    {7F}-bound wins (segment + palette row) > single resident segment (row unknown)
    > drop (>=2 resident & unbound, or 0 resident)."""

    def test_7f_binding_wins_and_supplies_the_palette_row(self):
        # {58} makes segment 1 resident in VRAM block 1; {7F} binds unit 128 to
        # block 1 at palette row 4; the cinematic anim draws 0xD2 with THAT row.
        chunk = [
            _inst(0x58, Block=1, Slot=1),
            _inst(0x7F, Unit=128, Block=1, Palette=4),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertEqual(res.tokens["ovelia_12"].chr, [(1, 0xD2, 4)])

    def test_single_resident_segment_is_kept_with_no_known_row(self):
        # One segment resident, no {7F} -> trustworthy single-seg tier, row None.
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertEqual(res.tokens["ovelia_12"].chr, [(1, 0xD2, None)])

    def test_two_resident_unbound_segments_are_dropped(self):
        # segments 1 and 2 both resident, no {7F} for unit 128 -> ambiguous -> DROP.
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x58, Block=1, Slot=2),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertNotIn("ovelia_12", res.tokens)
        self.assertEqual(res.dropped[("ovelia_12", "multiseg")], 1)

    def test_zero_resident_segments_are_dropped(self):
        # No {58} at all -> nothing resident -> pure false positive -> DROP.
        chunk = [
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertNotIn("ovelia_12", res.tokens)
        self.assertEqual(res.dropped[("ovelia_12", "zeroseg")], 1)

    def test_7f_to_a_non_resident_block_falls_through_to_the_single_seg_tier(self):
        # {7F} points unit 128 at block 1, but only block 0 is resident -> the
        # binding is stale; one segment resident -> single-seg tier keeps it.
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x7F, Unit=128, Block=1, Palette=4),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertEqual(res.tokens["ovelia_12"].chr, [(1, 0xD2, None)])

    def test_clearing_a_block_disambiguates_a_two_load_chunk(self):
        # Two segments load, but block 1 is cleared ({5A}) before the anim, so only
        # ONE is resident at anim time -> single-seg tier keeps it (residency, not
        # cumulative loads, is what counts -- VRAM holds only two slots).
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x58, Block=1, Slot=2),
            _inst(0x5A, Block=1),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertEqual(res.tokens["ovelia_12"].chr, [(1, 0xD2, None)])


class _FakeOwnerResolver:
    """Stand-in for SegmentOwnerResolver: `owner_of` maps (segment,row)->SPR from a
    table; `row_for_sprite` inverts it (first matching row)."""

    def __init__(self, table: dict):
        self.table = table  # {(segment, row): spr}

    def owner_of(self, segment, row):
        return self.table.get((segment, row))

    def row_for_sprite(self, segment, spr, rows=16):
        for (seg, row), s in self.table.items():
            if seg == segment and s == spr:
                return row
        return None


class DeriveSprOwnerTest(unittest.TestCase):
    """The redesign: a cinematic frame's owner is the RESOLVED SPR (palette
    fingerprint / ENTD sprite_set), not the slot's special_name. This is what
    routes an event-puppet's frames to their real character."""

    # Composite segment 1: row 1 = SPR 0x05 (Delita), row 3 = SPR 0x0C (Ovelia).
    RESOLVER = _FakeOwnerResolver({(1, 1): 0x05, (1, 3): 0x0C})
    # ENTD 500: a real Delita (uid5) and two event-puppets (uid128/129) that carry
    # sprite_set 0x05 (Delita) as a DECOY but render Ovelia's art via {7F} row 3.
    ENTD = {"500": {"slots": [
        {"unit_id": 5, "special_name": 5, "sprite_set": 0x05, "job": 0x05},
        {"unit_id": 128, "special_name": 5, "sprite_set": 0x05, "job": 0x05},
    ]}}
    SCENARIOS = {9: {"entd_idx": 500}}
    RESIDUE = {"5": "delita_5"}
    SPR_TO_TOKEN = {0x05: "delita_5", 0x0C: "ovelia_12"}

    def _run(self, chunk):
        return ead.derive_corpus({9: chunk}, self.SCENARIOS, self.ENTD, self.RESIDUE,
                                 CINEMATIC_SEQ, spr_to_token=self.SPR_TO_TOKEN,
                                 owner_resolver=self.RESOLVER)

    def test_7f_puppet_frame_routes_to_the_fingerprinted_owner_not_special_name(self):
        # uid128 is tagged special_name 5 (Delita) but its {7F} binds palette row 3,
        # which fingerprints to SPR 0x0C = Ovelia. The frame must land in ovelia_12.
        chunk = [
            _inst(0x58, Block=1, Slot=1),
            _inst(0x7F, Unit=128, Block=1, Palette=3),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),
        ]
        res = self._run(chunk)
        self.assertNotIn("delita_5", res.tokens)           # NOT the decoy identity
        self.assertEqual(res.tokens["ovelia_12"].chr, [(1, 0xD2, 3)])

    def test_real_unit_on_the_same_sheet_stays_its_own_identity(self):
        # uid5 (real Delita, {7F} row 1) fingerprints to 0x05 -> delita_5, row 1.
        chunk = [
            _inst(0x58, Block=1, Slot=1),
            _inst(0x7F, Unit=5, Block=1, Palette=1),
            _inst(0x11, Units=5, Multi=0, Animation=0x1F4),
        ]
        res = self._run(chunk)
        self.assertEqual(res.tokens["delita_5"].chr, [(1, 0xD2, 1)])

    def test_single_seg_tier_recovers_the_palette_row_from_the_entd_sprite(self):
        # No {7F}: single resident segment 1. uid5's ENTD sprite_set 0x05 resolves
        # to SPR 0x05; the matching CLUT row (1) is recovered -> row is no longer None.
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x11, Units=5, Multi=0, Animation=0x1F4),
        ]
        res = self._run(chunk)
        self.assertEqual(res.tokens["delita_5"].chr, [(1, 0xD2, 1)])

    def test_owner_spr_with_no_token_accumulates_into_the_generic_store(self):
        # A generic whose {7F} row fingerprints to SPR 0x65 (Female Knight), which
        # has no token and no residue nominal -> its frames land in the shared
        # generic store keyed by SPR 0x65 (#206 emit-only decision), NOT a unique.
        entd = {"501": {"slots": [
            {"unit_id": 130, "special_name": 255, "sprite_set": 0x81, "job": 0x4C},
        ]}}
        resolver = _FakeOwnerResolver({(1, 5): 0x65})
        chunk = [
            _inst(0x58, Block=1, Slot=1),
            _inst(0x7F, Unit=130, Block=1, Palette=5),
            _inst(0x11, Units=130, Multi=0, Animation=0x1F4),
        ]
        res = ead.derive_corpus({9: chunk}, {9: {"entd_idx": 501}}, entd, {},
                                CINEMATIC_SEQ, spr_to_token={}, owner_resolver=resolver)
        self.assertEqual(res.tokens, {})
        self.assertIn(0x65, res.generic)
        self.assertEqual(res.generic[0x65].chr, [(1, 0xD2, 5)])

    def test_identity_less_unit_with_no_resolvable_sprite_stays_unresolved(self):
        # No sprite_set at all -> no SPR, no token -> identity-less, counted (not
        # emitted, not routed to the generic store).
        entd = {"502": {"slots": [{"unit_id": 131, "special_name": 255}]}}
        chunk = [
            _inst(0x58, Block=0, Slot=1),
            _inst(0x11, Units=131, Multi=0, Animation=0x1F4),
        ]
        res = ead.derive_corpus({9: chunk}, {9: {"entd_idx": 502}}, entd, {},
                                CINEMATIC_SEQ, spr_to_token={}, owner_resolver=None)
        self.assertEqual(res.tokens, {})
        self.assertEqual(res.generic, {})
        self.assertEqual(res.unresolved[("anim", 255)], 1)


class DeriveFaceTest(unittest.TestCase):
    """EVTFACE face attribution was REMOVED from the replay: the ENTD-speaker axis
    mis-attributed cells (a cell's identity is its (row,col) grid slot, recovered
    from the dialogue speaker name -- see evtface_identity.py + its guard). The
    replay must no longer bind faces off the speaking Unit."""

    def test_display_message_binds_no_face(self):
        chunk = [
            _inst(0x50, Row=3),
            _inst(0x10, Unit=128, Dialog=0x10, Portrait=1),
        ]
        res = ead.derive_corpus({7: chunk}, SCENARIOS, ENTD, RESIDUE, CINEMATIC_SEQ)
        self.assertNotIn("ovelia_12", res.tokens)
        self.assertFalse(any(te.face for te in res.tokens.values()))
        self.assertFalse(any(k[0] == "face" for k in res.unresolved))


class UnitCutsceneFaceBridgeTest(unittest.TestCase):
    """The `{10}` speaker header names the speaking unit; when that name is an
    authored cutscene-face, the message's `speaker_unit_byte` is that identity's
    (scene-local) unit id -- the EVTCHR sibling of evtface_identity's per-cell
    name recovery. Only cutscene-face names produce an entry."""

    def test_maps_speaker_byte_to_slug_for_a_cutscene_face_name(self):
        insts = [
            _msg(128, "Balbanes"),
            _msg(1, "{Ramza}"),           # not a cutscene-face -> ignored
        ]
        got = ead.unit_cutscene_faces(insts, {"Balbanes": "balbanes"})
        self.assertEqual(got, {128: "balbanes"})

    def test_first_binding_wins_and_non_messages_ignored(self):
        insts = [
            _inst(0x58, Block=1, Slot=3),
            _msg(128, "Balbanes"),
            _msg(128, "Balbanes"),
        ]
        self.assertEqual(ead.unit_cutscene_faces(insts, {"Balbanes": "balbanes"}),
                         {128: "balbanes"})


class DeriveCutsceneFaceChrTest(unittest.TestCase):
    """Balbanes' deathbed frames: a {7F}-bound unit whose palette matches NO
    flat-store SPR (owner_of -> None) but whose dialogue names a cutscene-face must
    home its cinematic frames to that identity's SLUG, not fall through to the ENTD
    decoy sprite (which mis-filed Balbanes' frames under Alma)."""

    # No (segment,row) is a known SPR -> owner_of always None (Balbanes is SPR-less).
    RESOLVER = _FakeOwnerResolver({})
    # ENTD: unit 128's decoy sprite_set 0x30 (Alma) -- the wrong home we must avoid.
    ENTD = {"600": {"slots": [
        {"unit_id": 128, "special_name": 200, "sprite_set": 0x30, "job": 0x00},
    ]}}
    SCENARIOS = {14: {"entd_idx": 600}}
    RESIDUE = {"200": "alma_48"}                 # the decoy's nominal/residue token
    SPR_TO_TOKEN = {0x30: "alma_48"}
    NAME_TO_SLUG = {"Balbanes": "balbanes"}

    def _run(self, chunk):
        return ead.derive_corpus({14: chunk}, self.SCENARIOS, self.ENTD, self.RESIDUE,
                                 CINEMATIC_SEQ, spr_to_token=self.SPR_TO_TOKEN,
                                 owner_resolver=self.RESOLVER,
                                 name_to_slug=self.NAME_TO_SLUG)

    def test_spr_less_cutscene_face_frames_route_to_the_slug_not_the_decoy(self):
        chunk = [
            _inst(0x58, Block=1, Slot=1),
            _inst(0x7F, Unit=128, Block=1, Palette=0),
            _msg(128, "Balbanes"),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),
        ]
        res = self._run(chunk)
        self.assertIn("balbanes", res.cutscene)
        self.assertEqual(res.cutscene["balbanes"].chr, [(1, 0xD2, 0)])  # {7F} row 0
        self.assertNotIn("alma_48", res.tokens)                # NOT the decoy
        self.assertEqual(res.generic, {})

    def test_without_name_table_frames_still_mis_file_to_the_decoy(self):
        # No name_to_slug -> the bridge is inert and the old (buggy) decoy path stands.
        # Guards that the diversion is opt-in and back-compatible.
        chunk = [
            _inst(0x58, Block=1, Slot=1),
            _inst(0x7F, Unit=128, Block=1, Palette=0),
            _msg(128, "Balbanes"),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),
        ]
        res = ead.derive_corpus({14: chunk}, self.SCENARIOS, self.ENTD, self.RESIDUE,
                                CINEMATIC_SEQ, spr_to_token=self.SPR_TO_TOKEN,
                                owner_resolver=self.RESOLVER)
        self.assertEqual(res.cutscene, {})
        self.assertIn("alma_48", res.tokens)

    def test_matched_spr_wins_over_the_bridge(self):
        # If the {7F} palette DOES fingerprint an SPR, that owner wins even for a
        # cutscene-face-named unit -- the diversion is only for the SPR-less signal.
        resolver = _FakeOwnerResolver({(1, 0): 0x30})   # row 0 now matches Alma SPR
        chunk = [
            _inst(0x58, Block=1, Slot=1),
            _inst(0x7F, Unit=128, Block=1, Palette=0),
            _msg(128, "Balbanes"),
            _inst(0x11, Units=128, Multi=0, Animation=0x1F4),
        ]
        res = ead.derive_corpus({14: chunk}, self.SCENARIOS, self.ENTD, self.RESIDUE,
                                CINEMATIC_SEQ, spr_to_token=self.SPR_TO_TOKEN,
                                owner_resolver=resolver, name_to_slug=self.NAME_TO_SLUG)
        self.assertEqual(res.cutscene, {})
        self.assertEqual(res.tokens["alma_48"].chr, [(1, 0xD2, 0)])


class UnitCutsceneFaceSiblingTest(unittest.TestCase):
    """A named speaker's cutscene-face identity attaches to their ENTD
    `special_name`, so every event-puppet slot sharing that special_name in the
    scene is the same character. This homes the ANIMATOR puppet's frames when the
    dialogue names a *different* (speaker) puppet of the same identity -- the
    speaker != animator split (Elidibs scn112: speaker 128 names it, animator 129
    carries the {7F}+{11}). The 0xFF generic sentinel is never propagated."""

    def test_propagates_slug_to_siblings_sharing_special_name(self):
        insts = [_msg(128, "Elidibs")]
        uid_slots = {
            128: {"unit_id": 128, "special_name": 119},   # the named speaker
            129: {"unit_id": 129, "special_name": 119},   # the animator sibling
            131: {"unit_id": 131, "special_name": 255},   # generic filler -> excluded
        }
        got = ead.unit_cutscene_faces(insts, {"Elidibs": "elidibs"}, uid_slots)
        self.assertEqual(got, {128: "elidibs", 129: "elidibs"})

    def test_generic_sentinel_speaker_does_not_broadcast(self):
        # A cutscene-face speaker whose ENTD slot is the 0xFF sentinel must not
        # broadcast its identity to every other 0xFF filler in the scene.
        insts = [_msg(128, "Elidibs")]
        uid_slots = {128: {"special_name": 255}, 129: {"special_name": 255}}
        got = ead.unit_cutscene_faces(insts, {"Elidibs": "elidibs"}, uid_slots)
        self.assertEqual(got, {128: "elidibs"})           # only the direct speaker

    def test_without_uid_slots_only_the_direct_speaker(self):
        # Back-compat: omit uid_slots and the propagation is inert (old behaviour).
        insts = [_msg(128, "Balbanes")]
        self.assertEqual(ead.unit_cutscene_faces(insts, {"Balbanes": "balbanes"}),
                         {128: "balbanes"})


class DeriveCutsceneFaceSiblingChrTest(unittest.TestCase):
    """End-to-end (Elidibs scn112): the {7F} binding + {11} cinematic anim sit on
    the ANIMATOR unit (129); the dialogue names a SPEAKER unit (128) of the same
    special_name. The animator's SPR-less frames must home to the speaker's
    identity slug, not pool under the animator's ENTD decoy sprite."""

    RESOLVER = _FakeOwnerResolver({})                # owner_of -> None (host is SPR-less)
    ENTD = {"700": {"slots": [
        {"unit_id": 128, "special_name": 119, "sprite_set": 0x30, "job": 0x00},  # speaker
        {"unit_id": 129, "special_name": 119, "sprite_set": 0x30, "job": 0x00},  # animator
        {"unit_id": 131, "special_name": 255, "sprite_set": 0x30, "job": 0x00},  # filler
    ]}}
    SCENARIOS = {112: {"entd_idx": 700}}
    RESIDUE = {}
    SPR_TO_TOKEN = {}                                # 0x30 has no unique -> would pool generic
    NAME_TO_SLUG = {"Elidibs": "elidibs"}

    def _run(self, chunk, name_to_slug):
        return ead.derive_corpus({112: chunk}, self.SCENARIOS, self.ENTD, self.RESIDUE,
                                 CINEMATIC_SEQ, spr_to_token=self.SPR_TO_TOKEN,
                                 owner_resolver=self.RESOLVER, name_to_slug=name_to_slug)

    CHUNK = [
        _inst(0x58, Block=1, Slot=1),
        _inst(0x7F, Unit=129, Block=1, Palette=0),         # binding on the ANIMATOR
        _msg(128, "Elidibs"),                              # naming on the SPEAKER
        _inst(0x11, Units=129, Multi=0, Animation=0x1F4),
    ]

    def test_animator_sibling_frames_home_to_the_speaker_identity(self):
        res = self._run(self.CHUNK, self.NAME_TO_SLUG)
        self.assertIn("elidibs", res.cutscene)
        self.assertEqual(res.cutscene["elidibs"].chr, [(1, 0xD2, 0)])   # {7F} row 0
        self.assertEqual(res.generic, {})                  # NOT pooled under the decoy SPR

    def test_without_the_bridge_the_frames_pool_to_the_decoy_generic(self):
        # Guards the diversion is opt-in: no name table -> old (muxed) behaviour.
        res = self._run(self.CHUNK, {})
        self.assertEqual(res.cutscene, {})
        self.assertIn(resolve_sprite(0x30, 0), res.generic)


if __name__ == "__main__":
    unittest.main()
