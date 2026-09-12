extends RefCounted

## A Character = identity, the catalog record above the battle roster (ADR-0066).
##
## Carries a unit's durable *identity* — a canonical, human-authored [slug]
## (stable cross-system key), optional aliases, and a display name — plus its
## *name provenance* (where the name comes from and whether it is editable).
## It also holds refs to the durable *functional* objects the codebase already
## has (`UnitProgression`, `GambitList`); those are optional in this prefactor
## slice (issue #158) and get populated as Forms/Profiles land.
##
## This is the thing a live `Unit` is spawned from and that dialogue + scenario
## actors point at — never itself the in-scene node. It groups one-or-more
## `Form`s (chapter/job incarnations); the active Catalog resolves which Form is
## active. (Forms/Profiles are a later slice — not modelled here yet.)
##
## RefCounted for now; a later slice promotes it to a serializable record when
## persistent Characters land (`UnitProgression` is already a `Resource`).

## Where a Character's name comes from, and whether it is editable — ADR-0066
## decision 11. One field drives two behaviours:
##   FIXED  — canonical, seeded from ROM (`UnitNames.xml`); NOT player-editable
##            (Agrias is always "Agrias"); a re-import may overwrite it.
##   PLAYER — player-authored, editable via the naming UI; NEVER clobbered by a
##            re-import. Generics, and the protagonist (Player-with-canonical-
##            default "Ramza" — the one story character you can rename).

# SIBLING MEMBERS of this addon, by path. A member declares no `class_name` — the
# folder-named facade holds the addon's ONE global (ADR-0212 dec. 1) — so an
# intra-addon reference preloads its sibling, which is `exmateria_almanac`'s own
# idiom (`items/EquipStatDelta.gd:33`). Outside the addon the same names come
# off `ExMateriaCatalogue`; inside it there is no facade to go through.
const UnitNames = preload("res://addons/exmateria_catalogue/identity/UnitNames.gd")

# 🔴 THE SELF-REFERENCE, AND IT IS A REAL EDGE THAT ONLY THE STRANGER RIG COULD SEE.
# Four members below are static factories declared `-> Character`, and one calls
# `Character.new(...)`. While this file carried `class_name Character` that name was an
# engine global and the reference resolved to itself for free; shedding it (ADR-0212
# dec. 1) took the name away and left nine lines naming a type that no longer exists.
# The host tree does NOT report this — a warm `.godot` global-class cache still holds
# the pre-shed registration, so every host suite parses. A fresh project has no cache,
# which is exactly the failure ADR-0262 S4 said no static instrument in `tools/` could
# reach: no arm scores it, no test reds, and the first person to see it would have been
# whoever installed the addon. Self-preload is the corpus idiom for it
# (`exmateria_schema/colour_model/ColorRecipe.gd`, `exmateria_render/fold_bracket/
# FoldSurface.gd`, four battlefield members), spelled with the bare name here so the
# nine use sites keep their spelling.
const Character = preload("res://addons/exmateria_catalogue/identity/Character.gd")

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const GambitList = ExMateriaAlmanac.GambitList
const JobDatabase = ExMateriaAlmanac.JobDatabase
const UnitProgression = ExMateriaAlmanac.UnitProgression

# ADR-0118 dec. 1's TWELFTH schema row (ADR-0294 dec. 2). These three used to be
# spelled `UnitProgression.EquipSlot` / `.BaseStatType` / `.zodiac_from_birthday`,
# and those 22 lines were 61% of this addon's whole arm-5 debt — a package of
# identity records naming a package of rule tables in order to say "head slot" and
# "female". The VALUE SETS are the kernel's now and reaching the kernel is free
# (ADR-0202 dec. 2); `UnitProgression` above is still named, on the six lines that
# actually hold or construct one, which is the debt this addon really carries and
# which ADR-0241 dec. 3 says does not split.
const EquipSlot = ExMateriaSchema.EquipSlot.Slot
const BaseStatType = ExMateriaSchema.BaseStatType.Type
const Zodiac = ExMateriaSchema.Zodiac

enum Provenance { FIXED, PLAYER }

## Canonical, stable, human-authored identity key. Unique within a Catalog.
## Not the event-local `unit_id`, not the raw ROM `special_name`.
var slug: String

## "No special name" — a generic unit. The ROM reserves `special_name` 0 for
## exactly this, so it doubles as the field's default (a Character built off the
## roster factory carries no story identity).
const SPECIAL_NAME_NONE := 0

## The materialized ROM `special_name` — an asset parameter for the [template]
## [resolver] (ADR-0072 #202), NOT an identity key. For a *unique* it is the
## WHOLE unique [template key] (#199): one token packing identity + [Form], so
## the resolver stays a pure function of this stamped value (the active Form was
## chosen from story context upstream, at the seeding seam). A generic carries
## `SPECIAL_NAME_NONE`; the [ResidueManifest] decides which values are unique.
var special_name: int = SPECIAL_NAME_NONE

## A *unique* Character's **Form set** — its chapter incarnations, ROM-derived
## and seeded at mint (ADR-0079). Each Form is 1:1 with a ROM `special_name`
## (Ramza's Ch1 `RAMZA`=1, Ch2-3 `RAMZA2`=2, Ch4 `RAMZA3`=3 — see
## `template_residue.json`). The active Form is NOT stored here: it is SELECTED
## from story context and materialized as `special_name` at the seeding seam, so
## a later chapter re-stamps it. A generic carries an empty set and job-routes.
##
## Shape — an Array of `{"chapter": int, "special_name": int}` — hand-authored now
## for the Ch1 spine, in the shape a future character-alignment transform will emit.
var forms: Array = []

## The appearance-type [template] handle (ADR-0081) — a semantic token that is the
## folder's own name (`"40_year_old_woman"`). Set ONLY on an *appearance-type*: a
## sheet reachable by neither a `special_name` (it is not an identity) nor a job (no
## job's body points at it) — the story-townsperson sheets and a few specials. When
## present it is the WHOLE [template key] (the [resolver] routes `TEMPLATE_ROOT +
## token → template_folder`); a unique / generic carries "" and dispatches as before.
## Distinct from `slug`: the slug is identity, the token is a shared appearance.
var template_token: String = ""

## Optional alternate keys that resolve to this same identity.
var aliases: PackedStringArray

## Current display name (the thing dialogue renders).
var display_name: String

## Where the name comes from / whether it is editable.
var provenance: Provenance

## Durable functional attributes this identity references (may be null in the
## prefactor slice; wired as Forms/Profiles are built).
var progression: UnitProgression = null
var gambits: GambitList = null

## Raw *authored* gender bit, as persisted in the save file and consumed by the
## sprite path (`JobDatabase.get_sprite_id`). Distinct from the *stat* gender: a
## female-flagged monster is `is_female == true` here, yet its progression's
## base_stat_type is MONSTER (gender is meaningless for its stats). Only generic
## humans + Mime have distinct M/F sprites; for everything else the flag is inert
## for rendering but still round-trips faithfully through the save.
var is_female: bool = false


func _init(p_slug: String, p_display_name: String,
		p_provenance: Provenance = Provenance.PLAYER,
		p_aliases: PackedStringArray = PackedStringArray()) -> void:
	slug = p_slug
	display_name = p_display_name
	provenance = p_provenance
	aliases = p_aliases


## True if the player may rename this Character via the naming UI (Player only).
func is_renameable() -> bool:
	return provenance == Provenance.PLAYER


## Select the active [Form] for `story_chapter` and return its materialized ROM
## `special_name` — the deploy-seam materialization (ADR-0079). A unique carries
## its Form set (seeded at mint); the seam passes the current story context and
## this SELECTS the matching Form. A miss (no Form for that context, or a generic's
## empty set) returns `SPECIAL_NAME_NONE`, which the resolver job-routes — that is
## how a generic stays generic. This is selection, not story context: the resolver
## downstream never reads the chapter, only the stamped `special_name`.
func active_special_name(story_chapter: int) -> int:
	for form in forms:
		if int(form.get("chapter", -1)) == story_chapter:
			return int(form.get("special_name", SPECIAL_NAME_NONE))
	return SPECIAL_NAME_NONE


## Factory ---------------------------------------------------------------------

static func _base_stat_type_for(job_id: String, female: bool) -> int:
	"""Map a job + authored gender to a BaseStatType.

	Monster jobs are MONSTER regardless of the gender bit (gender is meaningless
	for their stats); humans split FEMALE/MALE. Shared by create_default and
	from_dict so the rule lives in one place.
	"""
	if JobDatabase.is_monster(job_id):
		return BaseStatType.MONSTER
	return BaseStatType.FEMALE if female else BaseStatType.MALE


static func create_default(p_name: String, job_id: String, female: bool = false,
		p_provenance: Provenance = Provenance.PLAYER) -> Character:
	"""Build a Character with a base-stat progression for the given job.

	The roster-seeding factory: seeds the durable progression from base stats +
	job, sets the job's default weapon, and an empty gambit list. The slug is
	left empty — it is assigned at Catalog promotion from the roster index.

	Args:
		p_name: display name
		job_id: starting job ID (hex string, e.g. '4a' for Squire)
		female: raw authored gender (drives the F sprite / base stats)
		p_provenance: name provenance (roster entries are Player-owned)
	"""
	var c := Character.new("", p_name, p_provenance)
	c.is_female = female

	# Build the durable progression, seeded from base stats + job. Monster jobs
	# get BaseStatType.MONSTER regardless of `female` — gender is meaningless for
	# non-human units (the raw is_female bit is still kept for the save schema).
	var p := UnitProgression.new()
	p.initialize(_base_stat_type_for(job_id, female), job_id)

	# Seed the job's default weapon if any (set the slot directly — avoids
	# equip_item's ItemDatabase validation during autoload-time roster creation)
	var weapon := get_starting_weapon(job_id)
	if weapon >= 0:
		p.equipment[EquipSlot.RIGHT_HAND] = weapon

	c.progression = p
	c.gambits = GambitList.new()
	return c


## ENTD sentinel bytes (ENTD_FORMAT.md): 0xFE = "randomise / use story value",
## 0xFF = "empty slot". Equipment id 0 is also treated as empty (monsters carry 0
## in every equipment slot — they have no equipment).
const ENTD_RANDOMISE := 0xFE
const ENTD_EMPTY := 0xFF

## FFT's own level bounds. The ROM clamps a resolved level into [1, 99] at
## SCUS `0x8005ae4c`–`0x8005ae70` — 0 becomes 1, anything >= 100 becomes 99 —
## so no ENTD unit can reach the field outside this range.
const ENTD_LEVEL_MIN := 1
const ENTD_LEVEL_MAX := 99

## The stand-in for the ROM's `DAT_80066308`: the level an ENTD sentinel scales to
## when the record itself authors no level (godot-learning ADR-0289, #1179).
##
## In the ROM this is a property of the PLAYER'S SAVE — the highest level in the
## 20-entry roster at `0x80057F74`, recomputed at every battle load
## (`0x8005cbd0`). A corpus rig has no save, so the ceiling is a declared
## parameter instead, and a run that changes it is not comparable to one that
## did not (ADR-0284 dec. 5): #1110 records it alongside the roster.
##
## 23 is the ROM's own median: the median of the 336 explicit 1..99 level bytes
## across the 847 slots `EntdBattle.combatant_slots` deploys (mean 22.2).
static var entd_level_ceiling: int = 23


## The level an ENTD sentinel scales to for one record's worth of slots.
##
## Prefers the record's OWN authored levels — the highest explicit 1..99 `level`
## byte among `slots` — because those track the chapter the fight belongs to (a
## Gariland record ceilings at 4, a Riovanes one at 75). Only 75 of the 174
## records with deployed slots author one at all, so the rest fall back to
## [member entd_level_ceiling]. Pure; `slots` are ENTD slot dicts.
static func level_ceiling_for_slots(slots: Array) -> int:
	var authored := 0
	for slot in slots:
		var raw := int(slot.get("level", 0))
		if raw >= ENTD_LEVEL_MIN and raw <= ENTD_LEVEL_MAX:
			authored = maxi(authored, raw)
	return authored if authored > 0 else entd_level_ceiling


## Resolve an ENTD `level` byte into a real level (godot-learning ADR-0289, #1179).
##
## The byte is a THREE-BRANCH field, not a number — SCUS `0x8005add4`:
##   - `0` or `0xFE` — scale to the party. The ROM draws UNIFORMLY at random from
##     the `ceiling/8 + 1` levels in `[ceiling - ceiling/8, ceiling]`; the port
##     takes that window's MIDPOINT, a deterministic sample of the same draw, for
##     the reason ADR-0284 dec. 3 already fixed for equipment — a rig whose
##     rosters change run to run cannot referee a lever.
##   - `1..99` — the authored level, verbatim.
##   - `>= 100` — party-RELATIVE: `ceiling + (raw - 100)`. Five deployed slots use
##     it (101, 105, 105, 110, 115).
## Then the ROM's clamp: 0 becomes 1, >= 100 becomes 99.
static func resolve_entd_level(raw: int, ceiling: int) -> int:
	var cap := clampi(ceiling, ENTD_LEVEL_MIN, ENTD_LEVEL_MAX)
	var resolved: int
	if raw == 0 or raw == ENTD_RANDOMISE:
		var span := cap >> 3
		resolved = cap - span + (span >> 1)
	elif raw >= 100:
		resolved = cap + raw - 100
	else:
		resolved = raw
	return clampi(resolved, ENTD_LEVEL_MIN, ENTD_LEVEL_MAX)


## Grow a progression from its level-1 base stats up to `target`.
##
## Setting `progression.level` alone moves NOTHING: the raw stats are seeded at
## base by `create_default` and only [method UnitProgression.level_up] grows them,
## so before #1179 every ENTD unit reached the kernel at base stats no matter what
## its level byte said. The ROM does the same climb — SCUS `0x8005b880` iterates
## `raw += raw / (constant + L - 1)` for `L = 2..level` over the same 16384ths
## fixed point — which is exactly `level_up()` repeated, so N-1 calls reproduce it.
static func _grow_progression_to(p, target: int) -> void:
	var guard := ENTD_LEVEL_MAX
	while p.level < target and guard > 0:
		p.level_up()
		guard -= 1


static func from_entd_slot(slot: Dictionary, catalog = null, level_ceiling: int = -1) -> Character:
	"""Build a Character from one ENTD battle-cast slot (HANDOFF T3, decision #181).

	`catalog` is duck-typed and must provide `get_character(slug)` — the live
	[CharacterCatalog] autoload, or a test fake. It DEFAULTS to the live autoload, and a
	`null` there is not an error: a canonical unit with no registered entry takes the
	FIXED identity below, which is the same branch an unregistered slug already took.

	Sourcing key is `special_name`: a slot whose special_name is a known story id
	([UnitNames]) is CANONICAL — a FIXED identity carrying the canonical name/slug;
	otherwise it is a FACTORY-derived generic (Player provenance, name = job).
	Either way the ENTD seeds job / level / brave / faith / equipment; the raw
	authored gender comes from the sprite_set marker (0x81 = female). Turn order,
	sprite art and tile placement are resolved elsewhere (the engine / the scene).

	`level_ceiling` is what a `0xFE` / `0` level byte SCALES TO — the port's stand-in
	for the ROM's highest-roster-level global (godot-learning ADR-0289, #1179). It
	belongs to the RECORD, so a caller holding the whole cast should pass
	[method level_ceiling_for_slots]; `-1` (the default) falls back to the corpus
	parameter [member entd_level_ceiling].
	"""
	var special := int(slot.get("special_name", ENTD_EMPTY))
	var sprite_set := int(slot.get("sprite_set", 0))
	var female := sprite_set == 0x81
	var job_id := "%02x" % int(slot.get("job", 0))
	var canonical := UnitNames.has(special)

	# create_default seeds the durable progression from base stats + job (and the
	# job's default weapon). We then overlay the ENTD-authored fields.
	#
	# Identity (decision #181): a canonical unit takes its slug/name/provenance from
	# CharacterCatalog when registered there (so the renameable protagonist Ramza
	# keeps PLAYER provenance), else a FIXED identity built straight from the name
	# table (Delita, Agrias, ...). A generic is Player-owned, named for its job.
	var name: String
	var provenance: Provenance
	var slug := ""
	if canonical:
		slug = UnitNames.slug_of(special)
		if catalog == null:
			# `registry/CharacterCatalog.live()` is the same two lines behind a name, and
			# this file cannot call it: that script preloads THIS one for `Character.new`,
			# so a preload back would be a cycle. Inlined for the reason
			# `display_port/DisplayPort.gd:104` and `debug/spu_audio_debug_panel.gd:71`
			# inline theirs — the node path, never the bare identifier.
			var loop := Engine.get_main_loop()
			catalog = loop.root.get_node_or_null(^"CharacterCatalog") if loop != null else null
		var existing = catalog.get_character(slug) if catalog != null else null
		if existing != null:
			name = existing.display_name
			provenance = existing.provenance
		else:
			name = UnitNames.resolve(special)
			provenance = Provenance.FIXED
	else:
		name = _generic_display_name(job_id)
		provenance = Provenance.PLAYER

	var c := create_default(name, job_id, female, provenance)
	if canonical:
		c.slug = slug

	# Materialize the ROM special_name as a template-resolver param (ADR-0072
	# #202) — the raw byte, canonical or not; the ResidueManifest decides which
	# values are unique. This is the seeding seam where a unit's active Form is
	# fixed, so the resolver downstream stays a pure function of the Character.
	c.special_name = special

	# Level is a sentinel on 506 of the 847 deployed slots, and `0xFE` there means
	# "scale to the party", not "1" (godot-learning ADR-0289, #1179). Resolve it,
	# then GROW to it — the number on its own is decorative.
	var ceiling := level_ceiling if level_ceiling > 0 else entd_level_ceiling
	_grow_progression_to(
		c.progression, resolve_entd_level(int(slot.get("level", ENTD_RANDOMISE)), ceiling))
	c.progression.brave = _entd_value(int(slot.get("bravery", ENTD_RANDOMISE)), 50)
	c.progression.faith = _entd_value(int(slot.get("faith", ENTD_RANDOMISE)), 50)
	# Zodiac is DERIVED from the ENTD birthday (bytes 4/5) — FFT stores no zodiac
	# byte. A concrete month (1..12) yields a sign; the Random/None/unset sentinels
	# return -1, leaving the progression's default (the game rolls Random at recruit).
	var zsign := Zodiac.zodiac_from_birthday(
		int(slot.get("month", ENTD_RANDOMISE)), int(slot.get("day", 0)))
	if zsign >= 0:
		c.progression.zodiac = zsign
	_seed_equipment_from_slot(c.progression, slot)
	return c


## Resolve an ENTD stat byte: the 0xFE "randomise / use story value" sentinel
## falls back to `default`; any real value passes through.
static func _entd_value(raw: int, default: int) -> int:
	return default if raw == ENTD_RANDOMISE else raw


## A generic unit's display name is its job's name ("Knight"), or "Unit".
static func _generic_display_name(job_id: String) -> String:
	return JobDatabase.get_job(job_id).get("name", "Unit")


## Overlay the ENTD slot's five equipment ids onto the progression, setting the
## slots directly (no ItemDatabase validation — matches create_default's load-time
## seeding).
##
## THE ITEM TABLE IS 0..0xFD. All three of `0`, `0xFE` and `0xFF` are OUTSIDE it and
## none of them is an item id, so all three are skipped and the job default survives
## (#1121, godot-learning ADR-0284):
##   - `0xFF` — the slot is empty.
##   - `0`    — `<Nothing>`; what monsters carry in all five slots.
##   - `0xFE` — [constant ENTD_RANDOMISE], the same "the game fills this in" sentinel
##     the level / brave / faith bytes use, resolved at load by the ROM's level-gated
##     enemy-equipment picker. It used to be written through verbatim, which put item
##     id **254** in the slot: `ItemDatabase.is_weapon(254)` is false, so the unit
##     reached the kernel with WP 0 / range 1 / weapon_type 0 — worse than the job
##     default it overwrote, and silently (`get_item(254)` returns `{}`). It is the
##     MAJORITY sentinel: 506 of the 720 human slots `EntdBattle.combatant_slots`
##     deploys carry it on `right_hand`.
static func _seed_equipment_from_slot(p: UnitProgression, slot: Dictionary) -> void:
	var map := {
		EquipSlot.HEAD: int(slot.get("head", ENTD_EMPTY)),
		EquipSlot.BODY: int(slot.get("body", ENTD_EMPTY)),
		EquipSlot.ACCESSORY: int(slot.get("accessory", ENTD_EMPTY)),
		EquipSlot.RIGHT_HAND: int(slot.get("right_hand", ENTD_EMPTY)),
		EquipSlot.LEFT_HAND: int(slot.get("left_hand", ENTD_EMPTY)),
	}
	for eslot in map:
		var item_id: int = map[eslot]
		if item_id != ENTD_EMPTY and item_id != ENTD_RANDOMISE and item_id != 0:
			p.equipment[eslot] = item_id


static func get_starting_weapon(job_id: String) -> int:
	"""Default weapon ID for a job, or -1 for bare fist.

	This table IS the port's substitute for the ROM's level-gated enemy-equipment
	picker: every ENTD slot whose weapon byte is a sentinel falls through to it
	(#1121, ADR-0284). Four ids were audited against `items.json` by NAME and were
	wrong — each comment named the right item and the number named another one:
	Archer 81 is Hunting Bow not Long Bow (83), Lancer 97 is Papyrus Plate not
	Javelin (99), Samurai 113 is Octagon Rod not Asura Knife (38), and Ninja 129 is
	**Buckler — a shield**, which `ItemDatabase.is_weapon` rejects outright, so a
	Ninja reached the kernel bare-handed. Every id below is now the id whose
	`items.json` `name` matches its comment.
	"""
	match job_id:
		"4a":  # Squire
			return 19   # Broad Sword
		"4b":  # Chemist
			return 1    # Dagger
		"4c":  # Knight
			return 19   # Broad Sword
		"4d":  # Archer
			return 83   # Long Bow
		"4e":  # Monk
			return -1   # Bare fist
		"4f":  # Priest
			return 59   # Oak Staff
		"50":  # Wizard
			return 51   # Rod
		"51":  # Time Mage
			return 51   # Rod
		"52":  # Summoner
			return 51   # Rod
		"53":  # Thief
			return 1    # Dagger
		"57":  # Lancer (Dragoon)
			return 99   # Javelin
		"58":  # Samurai
			return 38   # Asura Knife (katana)
		"59":  # Ninja
			return 12   # Ninja Knife
		_:
			return -1   # Bare fist


## Serialization ---------------------------------------------------------------
##
## Character owns the flat save schema. It is still the committed fixture format
## (`assets/roster/unit_animation_viewer_roster.json`); the per-side roster saves it
## also served — `user://{roster,enemy_roster}.json` — were orphaned by ADR-0180, which
## removes a save path without adding one on purpose (owned-overlay persistence is
## ADR-0201 §8's deferred work). The identity keys (slug/aliases/provenance) are
## intentionally NOT serialized: they are assigned when the Character is registered in
## the Catalog, not read from the file.

func to_dict() -> Dictionary:
	"""Flatten this Character's identity + shared progression into the save schema.

	Reads from the composed `progression`, flattening it into today's top-level
	keys. body_sprite_id/portrait_id are NOT serialized — they are derived from
	current_job_id + is_female, preventing desync.
	"""
	# A Character built via the bare constructor has no progression (only
	# create_default / from_dict seed one). Fall back to a default so a save
	# emits a valid dict instead of nil-dereferencing and aborting the whole
	# roster save.
	var p := progression if progression != null else UnitProgression.new()
	var learned: Array[int] = []
	for ability_id in p.learned_abilities.keys():
		learned.append(int(ability_id))

	return {
		"unit_name": display_name,
		# body_sprite_id and portrait_id intentionally omitted - computed from job
		"is_female": is_female,
		"level": p.level,
		"experience": p.experience,
		"current_job_id": p.current_job_id,
		"brave": p.brave,
		"faith": p.faith,
		"raw_hp": p.raw_hp,
		"raw_mp": p.raw_mp,
		"raw_speed": p.raw_speed,
		"raw_pa": p.raw_pa,
		"raw_ma": p.raw_ma,
		"job_levels": p.job_levels.duplicate(),
		"job_jp": p.job_jp.duplicate(),
		"learned_abilities": learned,
		"equipped_action_set": p.sub_job_id,
		"equipped_reaction": p.equipped_reaction,
		"equipped_support": p.equipped_support,
		"equipped_movement": p.equipped_movement,
		"weapon_id": p.equipment.get(EquipSlot.RIGHT_HAND, -1),
		"shield_id": p.equipment.get(EquipSlot.LEFT_HAND, -1),
		"helm_id": p.equipment.get(EquipSlot.HEAD, -1),
		"body_id": p.equipment.get(EquipSlot.BODY, -1),
		"accessory_id": p.equipment.get(EquipSlot.ACCESSORY, -1),
		"gambits_data": gambits.to_array() if gambits else [],
	}


static func _field(data: Dictionary, key: String, default):
	"""Fetch a save field, treating a present-but-null value as absent.

	`Dictionary.get`'s default only applies to a MISSING key; a corrupted or
	hand-edited save can carry the key with an explicit null. Assigning that Nil
	straight onto a typed field (or calling `.duplicate()` on it) crashes
	from_dict mid-build, which silently reverts the whole side's roster to the
	blank starter and discards the loaded party. Coalesce null to the same
	default a missing key would get.
	"""
	var v = data.get(key, default)
	return default if v == null else v


static func from_dict(data: Dictionary) -> Character:
	"""Rebuild a Character (identity + progression) from a flat save dict.

	The flat schema carries no identity keys, so the result is unpromoted: an
	empty slug and Player provenance, both assigned for real at Catalog promotion
	from the roster index (which always overwrites the slug — hence no slug param
	here). Monster jobs override the saved is_female bool for base_stat_type —
	gender is meaningless for their stats.

	Every field is read through `_field` so a corrupted save carrying an explicit
	null (rather than an absent key) falls back to the default instead of
	crashing (see `_field`).
	"""
	var c := Character.new("", _field(data, "unit_name", "Unnamed"))
	c.is_female = _field(data, "is_female", false)
	var job_id: String = _field(data, "current_job_id", "4a")

	# Rebuild the durable progression from the flat saved fields.
	var p := UnitProgression.new()
	p.base_stat_type = _base_stat_type_for(job_id, c.is_female)
	p.current_job_id = job_id
	p.level = _field(data, "level", 1)
	p.experience = _field(data, "experience", 0)
	p.brave = _field(data, "brave", 50)
	p.faith = _field(data, "faith", 50)
	p.raw_hp = _field(data, "raw_hp", 0)
	p.raw_mp = _field(data, "raw_mp", 0)
	p.raw_speed = _field(data, "raw_speed", 0)
	p.raw_pa = _field(data, "raw_pa", 0)
	p.raw_ma = _field(data, "raw_ma", 0)
	p.job_levels = _field(data, "job_levels", {}).duplicate()
	p.job_jp = _field(data, "job_jp", {}).duplicate()

	p.learned_abilities.clear()
	for ability_id in _field(data, "learned_abilities", []):
		p.learned_abilities[int(ability_id)] = true

	# equipped_action_set - legacy saves have int, new saves have String
	var action_set = _field(data, "equipped_action_set", "")
	p.sub_job_id = "" if (action_set is int or action_set is float) else action_set
	p.equipped_reaction = _field(data, "equipped_reaction", -1)
	p.equipped_support = _field(data, "equipped_support", -1)
	p.equipped_movement = _field(data, "equipped_movement", -1)

	# Equipment: discrete saved IDs -> equipment dict (direct set, no validation)
	p.equipment[EquipSlot.RIGHT_HAND] = _field(data, "weapon_id", -1)
	p.equipment[EquipSlot.LEFT_HAND] = _field(data, "shield_id", -1)
	p.equipment[EquipSlot.HEAD] = _field(data, "helm_id", -1)
	p.equipment[EquipSlot.BODY] = _field(data, "body_id", -1)
	p.equipment[EquipSlot.ACCESSORY] = _field(data, "accessory_id", -1)

	c.progression = p
	c.gambits = GambitList.from_array(_field(data, "gambits_data", []))

	return c


## Replace this identity's MUTABLE state from a `to_dict` image, in place (#894).
##
## [method from_dict] mints a new Character, which is right for a load and wrong for an undo: the
## roster index, the catalogue's owned overlay and every battlefield [Unit] hold a reference to
## THIS instance (ADR-0005 — one durable representation, which is only true while there is one
## object), so swapping it would leave three holders looking at the state being undone.
##
## What it restores is exactly what an adjustment turn can change: the composed `progression`
## (job, equipment, stats, ability slots) and the `gambits`, plus the two identity-adjacent fields
## the save schema carries. `slug`, `provenance`, `aliases` and `template_token` are NOT restored —
## they are identity, no editor writes them, and re-deriving them from a flat image is how a
## restored Character would come back unpromoted.
##
## ⚠ THE COMPOSED OBJECTS ARE RESTORED IN PLACE TOO, and that is not a refinement of the rule
## above — it is the same rule one level down. A battlefield [Unit] holds its OWN references to
## these two (`Unit.unit_progression`, `Unit.gambit_list`), bound at spawn and never re-read from
## the Character, so assigning fresh objects here leaves the Character correct and every Unit
## pointing at the state being undone. Measured: `GambitBattleTest` arm 4b cancelled an edit, and
## the GPU — which reconfigures from the UNIT — then committed the cancelled value.
func restore_mutable_from(data: Dictionary) -> void:
	var image := Character.from_dict(data)
	display_name = image.display_name
	is_female = image.is_female
	if progression == null:
		progression = image.progression
	else:
		_copy_script_vars(image.progression, progression)
	if gambits == null:
		gambits = image.gambits
	else:
		gambits.gambits = image.gambits.gambits


## Copy every script-declared property from `src` onto `dst`, in place.
##
## Enumerated rather than listed by hand: `UnitProgression` has 20-odd fields and gains more as
## the progression model fills in, and a hand-written list is a restore that silently stops
## covering whatever was added last. Dictionaries and Arrays are duplicated, so the restored
## object does not share containers with the throwaway image.
static func _copy_script_vars(src, dst) -> void:
	if src == null or dst == null:
		return
	for prop in src.get_property_list():
		if not (int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var value = src.get(prop["name"])
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		dst.set(prop["name"], value)
