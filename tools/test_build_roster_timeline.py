"""Tests for tools/build_roster_timeline.py.

The generator's job is to REPLACE the hand-authored Ch1/Gariland mutation tables
with the ROM's own answer, so the tests that matter are the ones that pin the
places the hand-authored version was WRONG:

  - the generic intake is at root 7 (Military Academy), NOT root 9 (Gariland)
  - there are SIX of them, not four
  - Gariland itself grants nobody; it merely deploys what the Academy granted

Plus the invariants a Seek depends on: a total story order, and a `roster_before`
that excludes the group's own joins (you do not have Orlandu before Bethla).

The APPEARANCE half has its own section: who each battle's ENTD spawns, bound once at
the slug's first battle so a later re-bind cannot clobber a levelled Character, and the
`recruited_red_conflicts` register that declares the one contradiction the ENTD flags
cannot resolve (Rafa) instead of authoring a guess around it.

Uses stdlib unittest. Run from tools/:
    uv run python -m unittest test_build_roster_timeline
"""

from __future__ import annotations

import json
import unittest

import build_roster_timeline as b


class RosterTimelineGeneratorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = b.build()
        cls.groups = cls.data["groups"]
        cls.order = cls.data["order"]

    def group(self, root: int) -> dict:
        return self.groups[str(root)]

    # --- the corrections over the hand-authored table ----------------------

    def test_generic_intake_is_the_academy_not_gariland(self):
        """The authored GarilandMutationScript seeded 4 generics at root 9. The ROM
        grants them at root 7 and Gariland grants nothing."""
        academy = [j for j in self.group(7)["joins"] if not j["canonical"]]
        self.assertEqual(len(academy), 6, "the Academy grants six generics")
        self.assertEqual(self.group(9)["joins"], [], "Gariland grants nobody")

    def test_academy_generics_are_four_squires_and_two_chemists(self):
        jobs = sorted(j["job"] for j in self.group(7)["joins"] if not j["canonical"])
        self.assertEqual(jobs, [0x4A, 0x4A, 0x4A, 0x4A, 0x4B, 0x4B])
        females = sorted(j["female"] for j in self.group(7)["joins"] if not j["canonical"])
        self.assertEqual(females, [False, False, False, True, True, True])

    def test_delita_joins_at_the_academy(self):
        canonical = [j["display_name"] for j in self.group(7)["joins"] if j["canonical"]]
        self.assertEqual(canonical, ["Delita"])

    def test_gariland_arrives_with_the_academy_roster(self):
        before = self.group(9)["roster_before"]
        self.assertIn("delita", before)
        self.assertEqual(len([s for s in before if s.startswith("entd392_")]), 6)

    def test_the_protagonist_is_seeded_at_the_first_group(self):
        """Ramza is never RECRUITED -- he is the player. His only join_after_event is at
        root 116, whose scenario is named "Chapter 2 Start": that is the chapter-FORM
        re-bind (special_name 1 -> 2), and reading it as a recruitment left him out of
        the roster for all of Chapter 1."""
        seeded = [(r, j) for r in self.order for j in self.group(r)["joins"]
                  if j.get("protagonist")]
        self.assertEqual(len(seeded), 1, "exactly one protagonist seed")
        root, delta = seeded[0]
        self.assertEqual(self.group(root)["position"], 0, "seeded at the story's first group")
        self.assertEqual(delta["slug"], "ramza")
        self.assertTrue(delta["recruit"])
        self.assertIsInstance(delta["slot"], dict)
        self.assertIn(delta["special_name"], (1, 2, 3))

    def test_ramza_is_in_the_roster_from_the_very_first_battle(self):
        """He is in almost every battle -- 283 of the 305 scenarios that deploy a squad
        set `ramza_mandatory` -- so he must be present before the first one."""
        for root in (9, 59, 116, 373):
            self.assertIn("ramza", self.group(root)["roster_before"],
                          "root %d must have the protagonist" % root)

    def test_chapter_2_start_is_a_form_rebind_not_a_recruit(self):
        ramza = [(r, j) for r in self.order for j in self.group(r)["joins"]
                 if j["display_name"] == "Ramza"]
        self.assertEqual([r for r, _ in ramza], [1, 116])
        self.assertEqual([j["recruit"] for _, j in ramza], [True, False])

    def test_only_ramza_and_delita_have_consecutive_form_ids(self):
        """The rule that separates a chapter FORM from a role variant: consecutive
        special_name ids. Agrias 30/52 and Mustadio 22/34 are not forms."""
        import json as _json
        # #1025 pass 3: the payload travelled into the addon beside its reader
        # (ADR-0251 dec. 2). Reached through the generator's own second loader so
        # this test cannot drift away from what the generator reads.
        with b.catalogue_dir("identity/unit_names.json").open() as f:
            names = _json.load(f)["names"]
        runs = {}
        for key, name in names.items():
            runs.setdefault(name, []).append(int(key))
        consecutive = {n for n, ids in runs.items()
                       if len(ids) > 1 and sorted(ids) == list(range(min(ids), min(ids) + len(ids)))}
        self.assertEqual(consecutive, {"Ramza", "Delita"})

    # --- ordering ----------------------------------------------------------

    def test_order_is_a_total_order_over_every_group(self):
        self.assertEqual(len(self.order), len(self.groups))
        self.assertEqual(len(set(self.order)), len(self.order), "no duplicate roots")
        positions = [self.group(r)["position"] for r in self.order]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(positions, list(range(len(self.order))))

    def test_overrides_are_applied(self):
        self.assertEqual(self.order[-1], 111, '"END" is placed last')
        self.assertGreater(
            self.group(218)["position"], self.group(373)["position"],
            "Cloud (Zarghidas) is a late Chapter 4 recruit, after Bethla")

    def test_the_pre_map_prologue_is_derived_not_guessed(self):
        """Roots 1-9 precede the world map, so no `enter` emit dates them. They are
        ordered only because scenario 1/2 seed the walk; without that seed they fall
        back to id order and the Academy's position stops being load-bearing."""
        for root in (1, 3, 7, 9):
            self.assertEqual(self.group(root)["order_source"], "derived",
                             "root %d must be reached from the prologue seed" % root)
        positions = [self.group(r)["position"] for r in (1, 3, 7, 9)]
        self.assertEqual(positions, sorted(positions), "the prologue chains in order")

    def test_story_recruits_land_in_story_order(self):
        """A spot-check chain the derivation must not scramble."""
        expected = [7, 15, 116, 128, 139, 225, 261, 297, 373, 426, 488]
        got = sorted(expected, key=lambda r: self.group(r)["position"])
        self.assertEqual(got, expected)

    # --- roster fold -------------------------------------------------------

    def test_roster_before_excludes_the_groups_own_joins(self):
        """You do not have Orlandu when you arrive AT Bethla Garrison."""
        self.assertNotIn("orlandu", self.group(373)["roster_before"])
        self.assertIn("orlandu", self.group(426)["roster_before"])

    def test_roster_before_grows_monotonically(self):
        seen = 0
        for root in self.order:
            size = len(self.group(root)["roster_before"])
            self.assertGreaterEqual(size, seen, "roster never shrinks along the story")
            seen = size

    def test_every_canonical_recruit_appears(self):
        self.assertEqual(
            self.data["_coverage"]["canonical_recruits"],
            ["Agrias", "Algus", "Alma", "Beowulf", "Cloud", "Delita", "Gafgarion",
             "Malak", "Meliadoul", "Mustadio", "Orlandu", "Ovelia", "Rafa", "Ramza",
             "Reis"])

    # --- slugs -------------------------------------------------------------

    def test_generic_slugs_are_unique_and_address_their_slot(self):
        generics = [j for r in self.order for j in self.group(r)["joins"] if not j["canonical"]]
        slugs = [j["slug"] for j in generics]
        self.assertEqual(len(set(slugs)), len(slugs), "generic slugs are collision-free")
        for j in generics:
            self.assertEqual(j["slug"], "entd%d_%d" % (j["entd_idx"], j["slot_index"]))

    def test_canonical_slugs_match_unit_names_lowercased(self):
        for root in self.order:
            for j in self.group(root)["joins"]:
                if j["canonical"]:
                    self.assertEqual(j["slug"], j["display_name"].lower())

    # --- deltas are what CatalogueReplay consumes --------------------------

    def test_op_splits_canonical_from_generic(self):
        """A canonical unit is PROMOTED into the Catalog; a generic is MINTED."""
        for root in self.order:
            for j in self.group(root)["joins"]:
                self.assertEqual(j["op"], "join" if j["canonical"] else "create",
                                 "%s at root %d" % (j["slug"], root))

    def test_deltas_carry_an_entd_slot_and_a_valid_op(self):
        for root in self.order:
            for j in self.group(root)["joins"]:
                self.assertIn(j["op"], ("join", "create"))
                self.assertIn("repeat", j)
                self.assertIsInstance(j["slot"], dict)
                self.assertIn("job", j["slot"])

    def test_repeat_joins_are_marked_not_collapsed(self):
        """Mustadio carries join_after_event at three groups, with his special_name
        changing 34 -> 22. The first puts him in the roster; the rest are marked so a
        consumer can tell a guest re-appearance from a first recruit."""
        occurrences = [(r, j) for r in self.order for j in self.group(r)["joins"]
                       if j["display_name"] == "Mustadio"]
        self.assertEqual([r for r, _ in occurrences], [139, 166, 169])
        self.assertEqual([j["special_name"] for _, j in occurrences], [34, 22, 22])
        # RECRUIT_AT names Goug (166) as the permanent join; Zaland is a guest appearance.
        self.assertEqual([j["recruit"] for _, j in occurrences], [False, True, False])
        self.assertEqual([j["repeat"] for _, j in occurrences], [True, False, True])

    def test_a_guest_is_absent_until_the_authored_recruit(self):
        """Mustadio guests at Zaland and joins at Goug, so a Seek to Zaland must NOT
        arrive with him and a Seek after Goug must."""
        self.assertNotIn("mustadio", self.group(139)["roster_before"])
        self.assertIn("mustadio", self.group(169)["roster_before"])
        self.assertNotIn("agrias", self.group(116)["roster_before"])
        self.assertIn("agrias", self.group(225)["roster_before"])

    def test_recruit_at_names_exactly_one_occurrence(self):
        """Every unit that appears at all is recruited exactly once — an override must
        not silently miss its group and leave the unit unrecruited forever."""
        from collections import defaultdict
        recruits = defaultdict(int)
        appears = set()
        for root in self.order:
            for j in self.group(root)["joins"]:
                appears.add(j["slug"])
                if j["recruit"]:
                    recruits[j["slug"]] += 1
        for slug in appears:
            self.assertEqual(recruits[slug], 1, "%s recruited %d times" % (slug, recruits[slug]))
        for slug, root in b.RECRUIT_AT.items():
            self.assertTrue(any(j["slug"] == slug for j in self.group(root)["joins"]),
                            "RECRUIT_AT[%s]=%d names a group that never grants it" % (slug, root))

    def test_deployability_is_not_asserted(self):
        """Every join slot has `control` clear, so the data does not say these units are
        player-controlled. The generator must not invent an `own` claim -- on a recruit
        or on an appearance (ADR-0078: catalogue membership is not owned membership)."""
        for root in self.order:
            for j in self.group(root)["joins"]:
                self.assertNotIn("own", j)
                self.assertFalse(j["control"])
            for a in self.group(root)["appearances"]:
                self.assertNotIn("own", a)

    # --- appearances: who the battle SPAWNS (ADR-0201 dec.6/7) -------------

    def test_the_orbonne_trio_is_derived_not_authored(self):
        """The three names StoryMutationScript.APPEARANCES used to hand-type. They carry
        `join_after_event` nowhere, so only the always-present scan reaches them."""
        orbonne = self.group(3)
        self.assertEqual([a["slug"] for a in orbonne["appearances"]],
                         ["agrias", "gafgarion", "ovelia"])
        self.assertEqual([a["job"] for a in orbonne["appearances"]], [0x34, 0x17, 0x0C])
        self.assertEqual(orbonne["opener_scenario_id"], 4,
                         "the key StoryMutationScript folds them under")

    def test_ramza_is_not_re_bound_by_the_battle_he_is_already_in(self):
        """ENTD 387 slot 0 is a present, named Ramza -- his CH2 cinematic form. He is
        already seeded at position 0, so re-binding him would overwrite the authored
        new-game protagonist with a special_name-2 slot (ADR-0079)."""
        self.assertNotIn("ramza", [a["slug"] for a in self.group(3)["appearances"]])

    def test_dormant_slots_are_not_a_cast(self):
        """ENTD 387 also carries a Red Delita and a lv1 Ramza/Delita pair with
        `always_present` clear -- rows the battle never spawns. Binding those would be
        binding units that are not there."""
        self.assertNotIn("delita", [a["slug"] for a in self.group(3)["appearances"]])

    def test_an_appearance_binds_once_across_the_whole_story(self):
        """A second bind would re-register a slug from a different ENTD slot, clobbering
        a Character the player has been levelling -- the same hazard `repeat` guards."""
        from collections import Counter
        seen = Counter(a["slug"] for r in self.order for a in self.group(r)["appearances"])
        self.assertEqual([s for s, n in seen.items() if n > 1], [])

    def test_an_already_recruited_unit_never_appears_afterwards(self):
        """Delita is recruited at the Academy and spawned by Gariland's own ENTD; the
        appearance must be suppressed, not fold over the recruited Character."""
        for root in self.order:
            before = set(self.group(root)["roster_before"])
            for a in self.group(root)["appearances"]:
                self.assertNotIn(a["slug"], before,
                                 "%s re-bound at root %d after joining" % (a["slug"], root))

    def test_appearances_are_battle_scoped(self):
        """`team_color` is noise in a cinematic record and a linear group has no plan
        action that lands at its START, so the derivation does not reach into one."""
        for root in self.order:
            group = self.group(root)
            if group["node_kind"] == "battle":
                self.assertIsNotNone(group["opener_scenario_id"],
                                     "battle root %d has no opener key" % root)
            else:
                self.assertEqual(group["appearances"], [])
                self.assertIsNone(group["opener_scenario_id"])

    def test_opener_keys_are_unique(self):
        """Two groups sharing an opener scenario id would collide in the one mutation
        table, and the second would silently overwrite the first."""
        openers = [self.group(r)["opener_scenario_id"] for r in self.order
                   if self.group(r)["opener_scenario_id"] is not None]
        self.assertEqual(len(set(openers)), len(openers))

    def test_appearance_deltas_carry_a_real_entd_slot(self):
        """A HIT must not fight WORSE than the raw-ENTD fallback: the bound Character is
        built from the slot, so the slot has to be the real one."""
        for root in self.order:
            for a in self.group(root)["appearances"]:
                self.assertEqual(a["op"], "join")
                self.assertTrue(a["canonical"])
                self.assertEqual(a["slug"], a["display_name"].lower())
                self.assertIsInstance(a["slot"], dict)
                self.assertEqual(a["slot"]["job"], a["job"])
                self.assertTrue(a["slot"]["flags2_decoded"]["always_present"])

    def test_named_enemies_are_catalogued_too(self):
        """The catalogue is the ONE population (ADR-0078) -- it holds guests and
        per-battle enemies, and `classify` derives the role. Wiegraf must be in it."""
        reds = {a["slug"] for r in self.order for a in self.group(r)["appearances"]
                if a["team_color_name"] == "Red"}
        self.assertIn("wiegraf", reds)
        self.assertIn("elmdor", reds)

    def test_the_appearance_census_is_stated(self):
        cov = self.data["_coverage"]
        self.assertEqual(cov["battle_groups"], 72)
        self.assertEqual(cov["groups_with_appearances"], 23)
        self.assertEqual(cov["appearance_binds"], 28)
        self.assertEqual(cov["appearance_slots_scanned"], 77,
                         "77 named+present battle slots collapse to 28 first binds")

    # --- the recruited-and-Red contradiction -------------------------------

    def test_the_recruited_red_register_is_exactly_three_rows(self):
        """Declared, not guessed around. Algus and Gafgarion are canon -- they turn on
        you and are never owned -- so the consumer's narrowing leaves Rafa alone."""
        rows = self.data["_coverage"]["recruited_red_conflicts"]
        self.assertEqual([r["slug"] for r in rows], ["algus", "gafgarion", "rafa"])
        rafa = rows[-1]
        self.assertEqual((rafa["root"], rafa["entd_idx"], rafa["special_name"]),
                         (291, 433, 41))
        self.assertIn("rafa", self.group(rafa["root"])["roster_before"])

    def test_the_same_record_spawns_rafa_on_both_teams(self):
        """Why the register scans slots directly instead of reusing the appearance
        scan: that one dedupes by slug and keeps the FIRST row. ENTD 433 carries Rafa
        twice, both always-present -- Blue at slot 0, Red at slot 1 -- so a dedup would
        keep the Blue one and report zero conflicts. It also says something about the
        ROM: which of the two is spawned cannot be an ENTD fact, since both are flagged
        present, so it is decided by the event script."""
        with (b.ASSETS / "scenarios" / "entd.json").open() as f:
            slots = json.load(f)["records"]["433"]["slots"]
        rafa = [(i, s) for i, s in enumerate(slots)
                if int(s.get("special_name", 0xFF)) == 41
                and s["flags2_decoded"]["always_present"]]
        self.assertEqual([i for i, _ in rafa], [0, 1])
        self.assertEqual([s["team_color_name"] for _, s in rafa], ["Blue", "Red"])
        rows = [r for r in self.data["_coverage"]["recruited_red_conflicts"]
                if r["slug"] == "rafa"]
        self.assertEqual([r["slot_index"] for r in rows], [1], "the RED row is the finding")

    def test_the_register_is_in_story_order(self):
        rows = self.data["_coverage"]["recruited_red_conflicts"]
        self.assertEqual([r["position"] for r in rows],
                         sorted(r["position"] for r in rows))

    def test_cinematic_team_colour_is_noise_which_is_why_the_scope_is_battles(self):
        """The reason the register and the appearance scan are battle-scoped: Ramza --
        definitionally the player -- reads Red in 17 cinematic records. Widen the scope
        and the register fills with rows that are not fights."""
        with (b.ASSETS / "scenarios" / "entd.json").open() as f:
            entd = json.load(f)
        # #1025 pass 3: the payload travelled into the addon beside its reader
        # (ADR-0251 dec. 2). Reached through the generator's own second loader so
        # this test cannot drift away from what the generator reads.
        with b.catalogue_dir("identity/unit_names.json").open() as f:
            names = json.load(f)["names"]
        cinematic_red_ramza = 0
        for root in self.order:
            group = self.group(root)
            if group["node_kind"] == "battle":
                continue
            record = entd["records"].get(str(group["entd_idx"]))
            if record is None:
                continue
            for slot in record["slots"]:
                if not slot["flags2_decoded"]["always_present"]:
                    continue
                if slot["team_color_name"] != "Red":
                    continue
                if names.get(str(int(slot.get("special_name", 0xFF)))) == "Ramza":
                    cinematic_red_ramza += 1
        self.assertEqual(cinematic_red_ramza, 17)
        self.assertNotIn("ramza",
                         [r["slug"] for r in self.data["_coverage"]["recruited_red_conflicts"]])

    # --- the world-map seek state (Ask C) ----------------------------------

    def test_the_reported_runaway_case_has_a_seek_state(self):
        """Seeking root 59 (Mandalia Plains) left the store at story counter 1, so the
        map offered node 6 -> Beoulve Residence and the walk chained through the whole
        game. The table must say what to install instead."""
        enter = self.group(59)["enter"]
        self.assertIsNotNone(enter)
        self.assertEqual(enter["story_counter"], 10)
        self.assertEqual(enter["vars"], {"110": 10})
        self.assertTrue(enter["exclusive"], "installing these vars offers node 59 alone")
        self.assertEqual(enter["live_with_these_vars"], [59])

    def test_enter_state_is_exclusive_for_almost_every_enterable_group(self):
        cov = self.data["_coverage"]
        self.assertEqual(cov["groups_enterable_from_world_map"], 55)
        self.assertEqual(cov["groups_with_exclusive_enter"], 48)

    def test_non_exclusive_groups_declare_why(self):
        """A group whose vars do not isolate it must say so — either an unmodelled
        `party has job` condition (nothing goes live) or a genuine ambiguity."""
        for root in self.order:
            enter = self.group(root)["enter"]
            if enter is None or enter["exclusive"]:
                continue
            live = enter["live_with_these_vars"]
            self.assertTrue(
                enter["unmodelled_conditions"] > 0 or len(live) > 1,
                "root %d is non-exclusive for no declared reason" % root)

    def test_chained_groups_have_no_enter_state(self):
        """Bethla Garrison is reached by chaining, never offered by the map."""
        self.assertIsNone(self.group(373)["enter"])
        self.assertIsNotNone(self.group(59)["enter"])

    # --- the recruitment gap that was a team_color filter -------------------

    def test_worker_8_carries_an_entd_join_flag(self):
        """ADR-0216 said "Worker 8 carries no ENTD join flag anywhere; he arrives through
        the Goug side quest's script." He does carry one: ENTD 291 slot 3.

        The three Besrodio's House cinematics are an A/B/A control -- same slot, same
        Steel Giant (job 0x91), same tile -- and the flag is set in exactly one of them.
        This test reads the ENTD directly, NOT the generator's output, so it still fails
        if `_joins_for` regains a filter that hides the slot."""
        recs = b._load("scenarios/entd.json")["records"]
        flags = {}
        for idx in (290, 291, 292):
            slot = recs[str(idx)]["slots"][3]
            self.assertEqual(slot["job"], 0x91, "ENTD %d slot 3 is a Steel Giant" % idx)
            flags[idx] = bool(int(slot["flags1"]) & b.JOIN_AFTER_EVENT)
            self.assertEqual(slot["team_color_name"], "Red")
        self.assertEqual(flags, {290: False, 291: True, 292: False})

    def test_worker_8_is_recruited_at_the_activation_cinematic(self):
        """The flag reaches the timeline: a NEW roster member at position 94, from the
        group whose scenarios are named "Worker 8 Activated"."""
        delta = [(r, j) for r in self.order for j in self.group(r)["joins"]
                 if j["entd_idx"] == 291 and j["slot_index"] == 3]
        self.assertEqual(len(delta), 1)
        root, j = delta[0]
        self.assertEqual(self.group(root)["position"], 94)
        self.assertEqual(self.group(root)["node_kind"], "cinematic_latch")
        self.assertTrue(j["recruit"], "he is a recruit, not a repeat")
        self.assertEqual(j["team_color_name"], "Red")
        self.assertFalse(j["canonical"], "special_name 117 is outside unit_names.json")
        self.assertEqual(j["slug"], "entd291_3")
        # And he stays in the roster from the next group on.
        after = [r for r in self.order if self.group(r)["position"] == 95][0]
        self.assertIn("entd291_3", self.group(after)["roster_before"])

    def test_byblos_was_never_missing(self):
        """The other half of the same ADR sentence -- "Byblos is likely the same shape" --
        was also false: he is derived, as the generic delta at the Elidibs group."""
        delta = [j for r in self.order for j in self.group(r)["joins"]
                 if j["entd_idx"] == 402 and j["slot_index"] == 10]
        self.assertEqual(len(delta), 1)
        self.assertEqual(delta[0]["job"], 0x90, "job 0x90 is Byblos")
        self.assertTrue(delta[0]["recruit"])

    def test_no_parsed_event_opcode_is_roster_shaped(self):
        """The premise named event opcodes as the mechanism. All 176 are catalogued and
        none of them mints a roster join -- every *Unit* opcode is scene placement."""
        opcodes = b._load("scenarios/event_instructions.json")["opcodes"]
        self.assertEqual(len(opcodes), 176)
        hits = sorted(v["name"] for v in opcodes.values()
                      if any(w in v["name"].lower()
                             for w in ("join", "party", "recruit", "member", "roster",
                                       "formation")))
        self.assertEqual(hits, [])

    def test_join_slots_are_not_filtered_by_team_color(self):
        """The regression this closes. Exactly two flagged-but-Red slots reach a group;
        both are cinematics, where this generator documents team_color as noise."""
        red = self.data["_coverage"]["red_join_slots"]
        self.assertEqual(
            [(r["entd_idx"], r["slot_index"], r["position"], r["recruit"]) for r in red],
            [(291, 3, 94, True), (434, 1, 108, False)])
        for r in red:
            self.assertEqual(r["node_kind"], "cinematic_latch")

    def test_every_flagged_slot_in_a_group_reaches_the_timeline(self):
        """No slot is dropped for ANY reason. Counts the ENTD directly against the
        emitted deltas, so a future filter of any kind fails here."""
        recs = b._load("scenarios/entd.json")["records"]
        want = set()
        for root in self.order:
            idx = self.group(root)["entd_idx"]
            for i, slot in enumerate(recs[str(idx)]["slots"]):
                if int(slot["flags1"]) & b.JOIN_AFTER_EVENT:
                    want.add((idx, i))
        got = {(j["entd_idx"], j["slot_index"]) for r in self.order
               for j in self.group(r)["joins"] if not j.get("protagonist")}
        self.assertEqual(got, want)

    # --- the gap that is left: identity, not recruitment --------------------

    def test_the_identity_gap_is_declared_not_hidden(self):
        """`unit_names.json` is sourced from UnitNames.xml, which stops at 0x48, so
        special_name 115..127 can never resolve to a name. Those slots are real recruits
        and they mint as generics. State it in the artifact rather than lose it."""
        self.assertIn("above 72", self.data["_coverage"]["known_gap"])
        names = b._load_catalogue("identity/unit_names.json")["names"]
        self.assertEqual(max(int(k) for k in names), 72)
        unnamed = sorted({j["special_name"] for r in self.order
                          for j in self.group(r)["joins"]
                          if not j["canonical"] and j["special_name"] != 0xFF})
        self.assertEqual(unnamed, [117, 118, 120, 121, 127])

    # --- the committed artifact is current ---------------------------------

    def test_committed_asset_matches_the_generator(self):
        with b.OUT.open() as f:
            self.assertEqual(json.load(f), self.data,
                             "assets/scenarios/roster_timeline.json is stale — regenerate")


if __name__ == "__main__":
    unittest.main()
