extends Node
# test-kind: logic
# seeded-break: Character._entd_value's 0xFE randomise-sentinel check inverted to ENTD_EMPTY (0xFF) — 'brave 0xFE -> default 50' + 'faith 0xFE -> default 50' RED (got 254, want 50 — the sentinel passes through as a raw stat); the real-value pass-through arms (brave 61 / faith 62), the identity slices, the special_name stamp, and the team split stay green; GREEN unbroken on the reverted tree
# seeded-break: in Character.resolve_entd_level, drop the `raw == 0` half of the sentinel test — 'level byte 0 is the SAME sentinel as 0xFE' goes RED (got 1, want 93: 0 falls through the verbatim branch and the ROM's 0->1 clamp catches it), and every other arm of _test_level_sentinel plus the rest of the file stays green
# seeded-break: drop the `item_id != ENTD_RANDOMISE` clause from Character._seed_equipment_from_slot — the three 0xFE arms of _test_equipment_sentinels go RED (right_hand got 254, want 19 / want 1), and the 0xFF arm plus every other slice stays green

## Pure-logic guard (no scene/VM/GPU) for the ENTD battle-init layer that the game
## navigator uses to build the Orbonne battle (HANDOFF_navigator_run_1to7.md T3):
##   - [UnitNames]: special_name -> canonical story name (sourcing key, decision #181)
##   - [Character.from_entd_slot]: one ENTD slot -> a Character (canonical vs factory)
##   - team split by ENTD team_color (Blue -> team0, Red -> team1)
## Data-driven against the real ENTD-387 (Orbonne) record; no rendering.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/EntdBattleInitTest.tscn

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression
const Character = ExMateriaCatalogue.Character
const ResidueManifest = ExMateriaCatalogue.ResidueManifest
const UnitNames = ExMateriaCatalogue.UnitNames

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_unit_names_resolver()
	_test_factory_generic_slot()
	_test_factory_female_and_monster()
	_test_canonical_slot()
	_test_stamps_special_name()
	_test_equipment_sentinels()
	_test_level_sentinel()
	_test_team_split()

	print("\n=== EntdBattleInitTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] EntdBattleInitTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] EntdBattleInitTest")
		get_tree().quit(1)
	else:
		print("[PASS] EntdBattleInitTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


# --- Slice A: special_name -> canonical name; unknown ids do NOT resolve ---
func _test_unit_names_resolver() -> void:
	# The 7 Orbonne canonical story ids (independent source: UnitNames.xml).
	_eq(UnitNames.resolve(1), "Ramza", "special_name 1 -> Ramza")
	_eq(UnitNames.resolve(4), "Delita", "special_name 4 -> Delita")
	_eq(UnitNames.resolve(12), "Ovelia", "special_name 12 -> Ovelia")
	_eq(UnitNames.resolve(23), "Gafgarion", "special_name 23 -> Gafgarion")
	_eq(UnitNames.resolve(52), "Agrias", "special_name 52 -> Agrias")
	_true(UnitNames.has(1), "has(1) canonical")
	# Factory generics (120+/0xFF) are NOT in the table -> not canonical.
	_true(not UnitNames.has(126), "has(126) factory -> false")
	_true(not UnitNames.has(255), "has(255)=0xFF -> false")
	_eq(UnitNames.resolve(126), "", "unknown id -> empty")
	# A blank XML entry (hex 35 = 53) carries no name -> must not resolve.
	_true(not UnitNames.has(53), "has(53) blank entry -> false")
	# Slug is the lower-cased canonical name (matches CharacterCatalog slugs).
	_eq(UnitNames.slug_of(52), "agrias", "slug_of(52) -> agrias")


## The real ENTD-387 slot dict for a given slot index (the true battle data).
func _slot(idx: int) -> Dictionary:
	var records: Dictionary = JsonAsset.load_dict("res://assets/scenarios/entd.json").get("records", {})
	var rec: Dictionary = records.get("387", {})
	return rec.get("slots", [])[idx]


# --- Slice B: a factory (generic) slot -> a PLAYER Character seeded from ENTD ---
func _test_factory_generic_slot() -> void:
	# Slot 5: generic MALE (sprite_set 0x80), job 0x4c (Knight), level 9, Red team,
	# brave/faith 0xFE (randomise -> default 50), right_hand item 21.
	var c := Character.from_entd_slot(_slot(5))
	_eq(c.provenance, Character.Provenance.PLAYER, "generic -> PLAYER provenance")
	_eq(c.is_female, false, "sprite_set 0x80 -> male")
	_true(c.progression != null, "generic has progression")
	_eq(c.progression.current_job_id, "4c", "job 76 -> job_id '4c'")
	_eq(c.progression.level, 9, "level seeded from ENTD (9)")
	_eq(c.progression.brave, 50, "brave 0xFE -> default 50")
	_eq(c.progression.faith, 50, "faith 0xFE -> default 50")
	# Equipment from ENTD overrides the job's default weapon.
	_eq(c.progression.equipment.get(UnitProgression.EquipSlot.RIGHT_HAND, -1), 21,
		"right_hand item seeded (21)")
	_eq(c.progression.equipment.get(UnitProgression.EquipSlot.HEAD, -1), 146,
		"head item seeded (146)")


# --- Slice C: sprite_set marker drives gender / monster; real brave/faith pass thru ---
func _test_factory_female_and_monster() -> void:
	# Slot 3: generic FEMALE (sprite_set 0x81), job 0x4c, level 8, real brave 61 / faith 62.
	var f := Character.from_entd_slot(_slot(3))
	_eq(f.is_female, true, "sprite_set 0x81 -> female")
	_eq(f.progression.level, 8, "level 8 seeded")
	_eq(f.progression.brave, 61, "real brave 61 passes through (not 0xFE)")
	_eq(f.progression.faith, 62, "real faith 62 passes through")

	# Slot 13: MONSTER (sprite_set 0x82), job 0x5e. Monster base-stat type regardless
	# of the gender bit; all-zero equipment leaves no gear.
	var m := Character.from_entd_slot(_slot(13))
	_eq(m.is_female, false, "sprite_set 0x82 monster -> not female-flagged")
	_eq(m.progression.base_stat_type, UnitProgression.BaseStatType.MONSTER,
		"monster job -> MONSTER base stats")
	_eq(m.progression.equipment.get(UnitProgression.EquipSlot.RIGHT_HAND, -1), -1,
		"monster carries no weapon (id 0 skipped)")


# --- Slice D: a canonical (story) slot -> a named identity (decision #181) ---
func _test_canonical_slot() -> void:
	# Slot 14: Ramza (special_name 1). Ramza is registered in CharacterCatalog as the
	# renameable protagonist (PLAYER provenance) -> identity comes from the catalog.
	var ramza := Character.from_entd_slot(_slot(14))
	_eq(ramza.display_name, "Ramza", "special_name 1 -> Ramza")
	_eq(ramza.slug, "ramza", "canonical slug ramza")
	_eq(ramza.provenance, Character.Provenance.PLAYER, "catalog Ramza -> PLAYER")
	_true(ramza.progression != null, "canonical has progression")
	_eq(ramza.progression.level, 1, "Ramza level 1 (Orbonne)")

	# Slot 15: Delita (special_name 4). Not in the catalog -> FIXED identity built
	# straight from the name table.
	var delita := Character.from_entd_slot(_slot(15))
	_eq(delita.display_name, "Delita", "special_name 4 -> Delita")
	_eq(delita.slug, "delita", "canonical slug delita")
	_eq(delita.provenance, Character.Provenance.FIXED, "name-table Delita -> FIXED")

	# Slot 2: Gafgarion (special_name 23) — another name-table-only canonical.
	var gaf := Character.from_entd_slot(_slot(2))
	_eq(gaf.display_name, "Gafgarion", "special_name 23 -> Gafgarion")
	_eq(gaf.provenance, Character.Provenance.FIXED, "name-table Gafgarion -> FIXED")


# --- Slice D2: the seeding seam materializes `special_name` onto the Character ---
# (ADR-0072 #202). The resolver is a pure function of the Character's materialized
# params, so `from_entd_slot` must STAMP the ROM special_name (the whole unique
# template key) — the raw byte, canonical or not; the residue decides uniqueness.
func _test_stamps_special_name() -> void:
	# Slot 14: Ramza (special_name 1) — a unique. The byte lands on the Character.
	var ramza := Character.from_entd_slot(_slot(14))
	_eq(ramza.special_name, 1, "Ramza slot stamps special_name 1")
	# Slot 5: a generic (no special name) stamps the sentinel, so it is NOT unique.
	var generic := Character.from_entd_slot(_slot(5))
	_true(not ResidueManifest.has(generic.special_name),
		"a generic slot's stamped special_name is not a residue unique")
	# A Character built off the roster factory carries the "none" sentinel.
	_eq(Character.create_default("Marcus", "4a").special_name, Character.SPECIAL_NAME_NONE,
		"create_default leaves special_name at the none sentinel")


# --- Slice D3: the THREE equipment sentinels, none of which is an item id (#1121) ---
# The item table is 0..0xFD. ENTD-387 carries only `0xFF` (empty) and `0` (monster),
# so this slice reads ENTD-**258** for the third one, `0xFE` — the "the game fills
# this in" sentinel the level/brave/faith bytes already use, and the MAJORITY case:
# 506 of the 720 human slots `combatant_slots` deploys carry it on `right_hand`.
#
# 258 is not an arbitrary pick. It is the record dynamically closed against a live
# PCSX savestate (`reference-assets/just_before_last_enemy_magic_city.sstate`): its
# 0xFE slots reach the battle unit table at `0x801908CC + n*0x1C0` holding REAL gear
# (`+0x1A..+0x1E` = head/body/accessory/right/left, `0xFF` = empty) — Leather Hat,
# Clothes, and a Dagger or Broad Sword in hand. So 0xFE must resolve to SOMETHING;
# what it must never do is land in the slot as item id 254.
func _test_equipment_sentinels() -> void:
	# ENTD-258 slot 2: generic Squire (job 0x4a), level 1, all five bytes 0xFE.
	var fe := Character.from_entd_slot(_slot_of("258", 2))
	var rh: int = fe.progression.equipment.get(UnitProgression.EquipSlot.RIGHT_HAND, -1)
	_true(rh != 0xFE, "0xFE is NOT written through as item id 254")
	_eq(rh, 19, "0xFE right_hand falls back to the Squire job default (Broad Sword 19)")
	_eq(fe.progression.equipment.get(UnitProgression.EquipSlot.HEAD, -1), -1,
		"0xFE head falls back — the job table covers weapons only")
	# ENTD-258 slot 6: generic Chemist (job 0x4b) -> Dagger, which is what the ROM
	# put in that unit's hand in the savestate above.
	_eq(Character.from_entd_slot(_slot_of("258", 6)).progression.equipment.get(
			UnitProgression.EquipSlot.RIGHT_HAND, -1), 1,
		"0xFE right_hand on a Chemist -> Dagger 1")

	# 0xFF (empty) behaves the same way — the job default survives. ENTD-387 slot 15
	# is Delita, job 0x04, which the table does not cover -> bare fist.
	_eq(Character.from_entd_slot(_slot(15)).progression.equipment.get(
			UnitProgression.EquipSlot.RIGHT_HAND, -1), -1,
		"0xFF right_hand + uncovered job -> bare fist (-1)")

	# The job-default table IS the port's substitute resolver, so its ids have to be
	# weapons. Four were not: 129 (Ninja) is Buckler, a SHIELD, and `is_weapon`
	# rejects it outright. Every covered job must now hand back a weapon id.
	for job_id in ["4a", "4b", "4c", "4d", "4f", "50", "51", "52", "53", "57", "58", "59"]:
		var w := Character.get_starting_weapon(job_id)
		_true(w >= 0 and w < 128, "job %s default %d is a weapon id" % [job_id, w])
	_eq(Character.get_starting_weapon("4e"), -1, "Monk stays bare-fisted")


# --- The level byte is a three-branch field, not a number (ADR-0289, #1179) ---
func _test_level_sentinel() -> void:
	# The pure resolver, arm by arm. ROM: SCUS 0x8005add4.
	# Sentinel -> the MIDPOINT of the ROM's random window [C - C/8, C].
	_eq(Character.resolve_entd_level(0xFE, 99), 93, "0xFE @99 -> 93 (window [87,99] midpoint)")
	_eq(Character.resolve_entd_level(0, 99), 93, "level byte 0 is the SAME sentinel as 0xFE")
	_eq(Character.resolve_entd_level(0xFE, 8), 7, "0xFE @8 -> 7 (window [7,8])")
	_eq(Character.resolve_entd_level(0xFE, 1), 1, "0xFE @1 -> 1 — the degenerate ceiling")
	# An authored level passes through; a party-RELATIVE byte (>=100) is ceiling-anchored.
	_eq(Character.resolve_entd_level(42, 99), 42, "an authored 1..99 level is verbatim")
	_eq(Character.resolve_entd_level(105, 50), 55, "105 @50 -> ceiling + 5")
	_eq(Character.resolve_entd_level(115, 99), 99, "115 @99 clamps to 99, FFT's cap")
	_eq(Character.resolve_entd_level(101, 1), 2, "101 @1 -> 2")

	# The ceiling belongs to the RECORD: ENTD-387 (Orbonne) authors levels 1..10, so a
	# sentinel there scales to 10 — not to the corpus parameter.
	_eq(Character.level_ceiling_for_slots(_slots_387()), 10, "ENTD-387 ceiling is its own max (10)")
	# ENTD-384 authors NO level at all (every deployed slot is 0xFE), so it falls back.
	var slots_384 := EntdBattle.combatant_slots(EntdBattle.record("384"))
	_eq(Character.level_ceiling_for_slots(slots_384), Character.entd_level_ceiling,
		"a record with no authored level falls back to the corpus ceiling")

	# The whole point of #1179: a 0xFE slot no longer lands at level 1...
	var scaled := Character.from_entd_slot(_slot_of("384", 2), null, 99)
	_eq(scaled.progression.level, 93, "an ENTD 0xFE slot scales to the ceiling, not to 1")
	# ...and the level is not decorative — the raw stats CLIMBED to it. Setting
	# `progression.level` alone moves nothing; only the growth walk does.
	var base := Character.create_default("base", "%02x" % int(_slot_of("384", 2).get("job", 0)))
	_true(scaled.progression.raw_hp > base.progression.raw_hp,
		"a scaled unit's raw HP grew past the level-1 base")
	_true(scaled.progression.get_effective_hp() > base.progression.get_effective_hp(),
		"...and the growth reaches effective HP, which is what the kernel reads")
	# An authored level grows too — before #1179 a level-9 Knight fought at base stats.
	var lv9 := Character.from_entd_slot(_slot(5))
	_eq(lv9.progression.level, 9, "authored level still seeds verbatim")
	_true(lv9.progression.raw_hp > Character.create_default("k", "4c").progression.raw_hp,
		"an authored level-9 slot also climbs off the base")


## One slot of an arbitrary ENTD record, by record key.
func _slot_of(record_key: String, idx: int) -> Dictionary:
	var records: Dictionary = JsonAsset.load_dict("res://assets/scenarios/entd.json").get("records", {})
	return records.get(record_key, {}).get("slots", [])[idx]


## The full ENTD-387 slot list.
func _slots_387() -> Array:
	var records: Dictionary = JsonAsset.load_dict("res://assets/scenarios/entd.json").get("records", {})
	return records.get("387", {}).get("slots", [])


# --- Slice E: partition the cast by ENTD team_color (Blue->team0, Red->team1) ---
func _test_team_split() -> void:
	# color -> team index mapping (Blue=0 -> team0, Red=1 -> team1).
	_eq(EntdBattle.team_index_for_color(0), 0, "Blue color -> team0")
	_eq(EntdBattle.team_index_for_color(1), 1, "Red color -> team1")

	var split := EntdBattle.split_slots(_slots_387())
	# ENTD-387 (Orbonne): 9 Blue (3 control + 6 AI allies) / 7 Red (HANDOFF decision #181).
	_eq(split["team0"].size(), 9, "9 Blue -> team0")
	_eq(split["team1"].size(), 7, "7 Red -> team1")
	# The three player-control units (unit_ids 1/2/4) are on team0.
	var team0_uids: Array = []
	for s in split["team0"]:
		team0_uids.append(int(s.get("unit_id", -1)))
	for uid in [1, 2, 4]:
		_true(team0_uids.has(uid), "control uid %d on team0" % uid)
