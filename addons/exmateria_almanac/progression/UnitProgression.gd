extends Resource

## FFT-style unit progression component
##
## Tracks a unit's level, accumulated raw stats, current job, and job levels.
## Raw stats grow on level-up based on the current job's growth constants.
## Effective stats are calculated from raw stats and current job's multipliers.
##
## Usage:
##   var prog = $UnitProgression
##   prog.initialize(BaseStatType.MALE, "4a")  # Male Squire
##   prog.level_up()  # Grow stats based on current job
##   var hp = prog.get_effective_hp()  # Get displayed HP

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const AbilityDatabase = preload("res://addons/exmateria_almanac/abilities/AbilityDatabase.gd")
const AbilityType = preload("res://addons/exmateria_almanac/abilities/AbilityType.gd")
const BaseStatsDatabase = preload("res://addons/exmateria_almanac/progression/BaseStatsDatabase.gd")
const ItemDatabase = preload("res://addons/exmateria_almanac/items/ItemDatabase.gd")
const JobDatabase = preload("res://addons/exmateria_almanac/jobs/JobDatabase.gd")
const JobLevelsDatabase = preload("res://addons/exmateria_almanac/jobs/JobLevelsDatabase.gd")
const StatCalculator = preload("res://addons/exmateria_almanac/progression/StatCalculator.gd")


# ADR-0118 dec. 1's TWELFTH schema row (ADR-0294 dec. 2) — `EquipSlot`,
# `BaseStatType` and `Zodiac` are the SHARED KERNEL's, not this member's. All
# three were nested here because this is where the state they describe is kept,
# and nesting is what made a caller compile against a 900-line `Resource` in order
# to say "head slot" or "female". They are value sets: a caller of one learns no
# ordering, no invariant and no error mode, which is the tenth row's test
# (`Facing`, `SpriteLayer`, `ClockOwner`, `UnitMaterialVariant`, `UnitActivity`)
# and the eleventh's (`UnitRole`). Reaching the kernel is FREE in every direction
# (ADR-0202 dec. 2), so the catalogue, this addon and `src/` all pay nothing.
#
# 🔴 RE-EXPORTED, NOT RENAMED. Every `UnitProgression.EquipSlot.*`,
# `.BaseStatType.*` and `.Zodiac.*` site in the tree is unchanged, and each
# re-export is usable as a TYPE annotation exactly as the inline enum was — which
# is what keeps the five `slot: EquipSlot` signatures, the `equipment_changed`
# signal and `@export var base_stat_type` compiling. #1123 probed that on the fork
# for `EquipSlot`; the other two are the same construct.
const EquipSlotVocab = ExMateriaSchema.EquipSlot
const EquipSlot = EquipSlotVocab.Slot
const BaseStatTypeVocab = ExMateriaSchema.BaseStatType
const BaseStatType = BaseStatTypeVocab.Type
const ZodiacVocab = ExMateriaSchema.Zodiac
const Zodiac = ZodiacVocab.Sign

# Exported for editor visibility
@export var level: int = 1
@export var experience: int = 0
@export var base_stat_type: BaseStatType = BaseStatType.MALE
@export var current_job_id: String = "4a"  # Default: Squire

# Brave and Faith (unit-level, not job-level)
# Range: 0-100, affects damage calculations and ability success rates
@export var brave: int = 50  # Affects physical damage, reaction success
@export var faith: int = 50  # Affects magic damage (dealt AND received)

# A unit's tropical zodiac sign — `Zodiac` above, 0..12 (ADR-0294 dec. 2 moved the
# VOCABULARY to the kernel; the VALUE is this unit's and stays here). Drives the
# formation info-panel zodiac glyph (faithfulness rule: FFT visuals, OUR data —
# §14.3).
#
# The default ARIES is a fallback for a unit with NO sourced birthday (a bare
# constructor, or a generic whose ENTD birthday is the Random/None sentinel — the
# game rolls that at recruit; we hold the fallback). A unit built from a concrete
# ENTD birthday overrides it via `ExMateriaSchema.Zodiac.zodiac_from_birthday` at
# the materialization seam (`Character.from_entd_slot` / `AllTemplatesSeeder` for
# uniques). SERPENTARIUS (12) is never date-derived.
@export var zodiac: int = Zodiac.ARIES

# Accumulated raw stats (fixed-point × 16384, grow on level-up)
var raw_hp: int = 0
var raw_mp: int = 0
var raw_speed: int = 0
var raw_pa: int = 0
var raw_ma: int = 0

# Job progression
var job_levels: Dictionary = {}  # {job_id: 0-8}
var job_jp: Dictionary = {}      # {job_id: SPENDABLE jp — abilities decrement this}
## Lifetime JP EARNED per job — the Learn job picker's "Total" column
## (LEARN_PICKER.md round 10 #5). Accrues with every `add_jp*` and is NEVER
## decremented, so learning an ability moves `job_jp` down while this stands
## still. DISPLAY-ONLY: job LEVEL and the "Next" column keep deriving from the
## spendable `job_jp`, so no progression behaviour changes.
var job_jp_total: Dictionary = {}  # {job_id: lifetime_earned_jp}

# Learned abilities (permanent, usable on any job)
var learned_abilities: Dictionary = {}  # {ability_id: true}

# Equipment slots (item IDs, -1 means empty)
var equipment: Dictionary = {
	EquipSlot.RIGHT_HAND: -1,  # Weapon or shield
	EquipSlot.LEFT_HAND: -1,   # Shield or second weapon (with Two Swords)
	EquipSlot.HEAD: -1,        # Helmet, hat, or hair adornment
	EquipSlot.BODY: -1,        # Armor, clothing, or robe
	EquipSlot.ACCESSORY: -1,   # Accessory (shoes, ring, mantle, etc.)
}

# Equipped ability slots
var sub_job_id: String = ""           # Secondary job for action abilities
var equipped_reaction: int = -1       # Equipped reaction ability ID (-1 = none)
var equipped_support: int = -1        # Equipped support ability ID (-1 = none)
var equipped_movement: int = -1       # Equipped movement ability ID (-1 = none)

# Signals
signal level_changed(old_level: int, new_level: int)
signal job_changed(old_job_id: String, new_job_id: String)
signal stats_changed()
signal ability_learned(ability_id: int, ability_name: String)
signal equipment_changed(slot: EquipSlot, old_item_id: int, new_item_id: int)


func _initialize_from_base_stats() -> void:
	"""Initialize raw stats from base stat type."""
	var stat_type_name = _get_stat_type_name()
	raw_hp = BaseStatsDatabase.get_base_stat(stat_type_name, "hp")
	raw_mp = BaseStatsDatabase.get_base_stat(stat_type_name, "mp")
	raw_speed = BaseStatsDatabase.get_base_stat(stat_type_name, "speed")
	raw_pa = BaseStatsDatabase.get_base_stat(stat_type_name, "pa")
	raw_ma = BaseStatsDatabase.get_base_stat(stat_type_name, "ma")

	# Initialize job levels and JP
	job_levels[current_job_id] = 1
	job_jp[current_job_id] = 0


func initialize(stat_type: BaseStatType, job_id: String = "4a") -> void:
	"""Initialize progression with specified base type and starting job.

	Args:
		stat_type: MALE, FEMALE, or MONSTER
		job_id: Starting job ID (hex string, default '4a' for Squire)
	"""
	base_stat_type = stat_type
	current_job_id = job_id
	level = 1
	experience = 0
	job_levels.clear()
	job_jp.clear()
	learned_abilities.clear()
	# Clear equipment
	for slot in equipment:
		equipment[slot] = -1
	_initialize_from_base_stats()


func level_up() -> void:
	"""Apply level-up stat growth based on current job.

	Uses FFT formula: stat += stat / (job_constant + level)
	"""
	var job = JobDatabase.get_job(current_job_id)
	if job.is_empty():
		push_warning("[UnitProgression] Job not found: %s" % current_job_id)
		return

	var old_level = level

	# Apply growth to each stat
	raw_hp = StatCalculator.grow_stat(raw_hp, job.get("hp_constant", 10), level)
	raw_mp = StatCalculator.grow_stat(raw_mp, job.get("mp_constant", 10), level)
	raw_speed = StatCalculator.grow_stat(raw_speed, job.get("speed_constant", 10), level)
	raw_pa = StatCalculator.grow_stat(raw_pa, job.get("pa_constant", 10), level)
	raw_ma = StatCalculator.grow_stat(raw_ma, job.get("ma_constant", 10), level)

	level += 1
	level_changed.emit(old_level, level)
	stats_changed.emit()


func change_job(new_job_id: String) -> bool:
	"""Change to a different job.

	Args:
		new_job_id: Job ID to change to (hex string)

	Returns:
		true if job change succeeded, false if job not found
	"""
	var job = JobDatabase.get_job(new_job_id)
	if job.is_empty():
		push_warning("[UnitProgression] Cannot change to unknown job: %s" % new_job_id)
		return false

	var old_job_id = current_job_id
	current_job_id = new_job_id

	# Initialize job level/JP if first time in this job
	if not job_levels.has(new_job_id):
		job_levels[new_job_id] = 1
		job_jp[new_job_id] = 0

	job_changed.emit(old_job_id, new_job_id)
	stats_changed.emit()
	return true


func add_jp(amount: int) -> void:
	"""Add JP to current job.

	Args:
		amount: JP to add
	"""
	if not job_jp.has(current_job_id):
		job_jp[current_job_id] = 0

	var old_jp = job_jp[current_job_id]
	job_jp[current_job_id] += amount
	job_jp_total[current_job_id] = int(job_jp_total.get(current_job_id, 0)) + amount

	# Calculate new job level from total JP using JobLevelsDatabase
	var old_level = job_levels.get(current_job_id, 1)
	var new_level = JobLevelsDatabase.get_job_level_from_jp(job_jp[current_job_id])
	job_levels[current_job_id] = new_level

	if new_level > old_level:
		# Job level increased
		stats_changed.emit()


func add_jp_to_all_jobs(job_ids, amount: int) -> void:
	"""Add JP to all provided jobs in a single batch, emitting stats_changed only once.

	Args:
		job_ids: Array or Dictionary of job IDs to add JP to (Dictionary iterates keys)
		amount: JP to add to each job
	"""
	for job_id in job_ids:
		if not job_jp.has(job_id):
			job_jp[job_id] = 0
		if not job_levels.has(job_id):
			job_levels[job_id] = 1
		job_jp[job_id] += amount
		job_jp_total[job_id] = int(job_jp_total.get(job_id, 0)) + amount
		var new_level = JobLevelsDatabase.get_job_level_from_jp(job_jp[job_id])
		job_levels[job_id] = new_level
	stats_changed.emit()


func add_experience(amount: int) -> bool:
	"""Add experience and potentially level up.

	Args:
		amount: Experience to add

	Returns:
		true if unit leveled up
	"""
	experience += amount
	var leveled = false

	# FFT uses 100 exp per level
	while experience >= 100:
		experience -= 100
		level_up()
		leveled = true

	return leveled


## Effective Stat Getters (apply job multipliers)

func get_effective_hp() -> int:
	"""Get effective HP after job multiplier and equipment bonuses."""
	var job = JobDatabase.get_job(current_job_id)
	var multiplier = job.get("hp_multiplier", 100)
	var base = StatCalculator.get_effective_stat(raw_hp, multiplier)
	var bonuses = get_equipment_stat_bonuses()
	return base + bonuses.get("hp", 0)


func get_effective_mp() -> int:
	"""Get effective MP after job multiplier and equipment bonuses."""
	var job = JobDatabase.get_job(current_job_id)
	var multiplier = job.get("mp_multiplier", 100)
	var base = StatCalculator.get_effective_stat(raw_mp, multiplier)
	var bonuses = get_equipment_stat_bonuses()
	return base + bonuses.get("mp", 0)


func get_effective_speed() -> int:
	"""Get effective Speed after job multiplier and equipment bonuses."""
	var job = JobDatabase.get_job(current_job_id)
	var multiplier = job.get("speed_multiplier", 100)
	var base = StatCalculator.get_effective_stat(raw_speed, multiplier)
	var bonuses = get_equipment_stat_bonuses()
	return base + bonuses.get("speed", 0)


func get_effective_pa() -> int:
	"""Get effective Physical Attack after job multiplier and equipment bonuses."""
	var job = JobDatabase.get_job(current_job_id)
	var multiplier = job.get("pa_multiplier", 100)
	var base = StatCalculator.get_effective_stat(raw_pa, multiplier)
	var bonuses = get_equipment_stat_bonuses()
	return base + bonuses.get("pa", 0)


func get_effective_ma() -> int:
	"""Get effective Magic Attack after job multiplier and equipment bonuses."""
	var job = JobDatabase.get_job(current_job_id)
	var multiplier = job.get("ma_multiplier", 100)
	var base = StatCalculator.get_effective_stat(raw_ma, multiplier)
	var bonuses = get_equipment_stat_bonuses()
	return base + bonuses.get("ma", 0)


func get_move() -> int:
	"""Get movement range from current job and equipment bonuses."""
	var job = JobDatabase.get_job(current_job_id)
	var base = job.get("move", 4)
	var bonuses = get_equipment_stat_bonuses()
	return base + bonuses.get("move", 0)


func get_jump() -> int:
	"""Get jump height from current job and equipment bonuses."""
	var job = JobDatabase.get_job(current_job_id)
	var base = job.get("jump", 3)
	var bonuses = get_equipment_stat_bonuses()
	return base + bonuses.get("jump", 0)


func get_c_evade() -> int:
	"""Get class evasion from current job."""
	var job = JobDatabase.get_job(current_job_id)
	return job.get("c_evade", 0)


## Raw Stat Getters (for display/debugging)

## Job Info

func get_current_job_name() -> String:
	"""Get name of current job."""
	var job = JobDatabase.get_job(current_job_id)
	return job.get("name", "Unknown")


func get_job_level(job_id: String = "") -> int:
	"""Get level for a job (default: current job)."""
	var id = job_id if not job_id.is_empty() else current_job_id
	return job_levels.get(id, 0)


func get_job_jp(job_id: String = "") -> int:
	"""Get SPENDABLE JP for a job (default: current job)."""
	var id = job_id if not job_id.is_empty() else current_job_id
	return job_jp.get(id, 0)


func get_job_jp_total(job_id: String = "") -> int:
	"""Get LIFETIME JP earned in a job (default: current job).

	The Learn job picker's "Total" column. Never decremented by ability learning, so it
	stands still while get_job_jp() falls — that difference IS the column's information.
	"""
	var id = job_id if not job_id.is_empty() else current_job_id
	return job_jp_total.get(id, 0)


## Job Unlocking

func is_job_unlocked(job_id: String) -> bool:
	"""Check if a job is unlocked based on current job levels.

	Args:
		job_id: Job ID to check (e.g., '4c' for Knight)

	Returns:
		True if all prerequisites are met
	"""
	return JobLevelsDatabase.is_job_unlocked(job_id, job_levels)


func get_unlocked_jobs() -> Array:
	"""Get list of all unlocked generic job IDs.

	Returns:
		Array of job IDs that this unit has unlocked
	"""
	var unlocked: Array = []
	for job_id in JobLevelsDatabase.get_all_generic_job_ids():
		if is_job_unlocked(job_id):
			unlocked.append(job_id)
	return unlocked


func get_locked_jobs() -> Array:
	"""Get list of all locked generic job IDs.

	Returns:
		Array of job IDs that this unit has NOT unlocked
	"""
	var locked: Array = []
	for job_id in JobLevelsDatabase.get_all_generic_job_ids():
		if not is_job_unlocked(job_id):
			locked.append(job_id)
	return locked


func get_missing_prerequisites(job_id: String) -> Array:
	"""Get list of prerequisites not yet met for a job.

	Args:
		job_id: Job ID to check

	Returns:
		Array of strings like ["Squire Lv2 (have Lv1)", "Knight Lv3 (have Lv0)"]
	"""
	return JobLevelsDatabase.get_missing_prerequisites(job_id, job_levels)


## Ability Learning

func learn_ability(ability_id: int) -> bool:
	"""Learn an ability by spending JP from current job.

	Args:
		ability_id: ID of ability to learn

	Returns:
		True if ability was learned, false if not enough JP or already learned
	"""
	if has_learned_ability(ability_id):
		return false  # Already learned

	var ability := AbilityDatabase.get_ability_view(ability_id)
	if ability.is_empty():
		return false  # Invalid ability

	var jp_cost = ability.jp_cost
	var current_jp = job_jp.get(current_job_id, 0)

	if current_jp < jp_cost:
		return false  # Not enough JP

	# Spend JP and learn ability
	job_jp[current_job_id] = current_jp - jp_cost
	learned_abilities[ability_id] = true

	# Recalculate job level after spending JP
	var new_level = JobLevelsDatabase.get_job_level_from_jp(job_jp[current_job_id])
	job_levels[current_job_id] = new_level

	ability_learned.emit(ability_id, ability.name)
	return true


func learn_ability_from_job(ability_id: int, job_id: String) -> bool:
	"""Learn an ability by spending JP from a specific job.

	Unlike learn_ability(), this allows spending JP from any job's pool,
	not just the current job. Used by the ability learning panel.

	Args:
		ability_id: ID of ability to learn
		job_id: Job ID to spend JP from

	Returns:
		True if ability was learned, false if not enough JP or already learned
	"""
	if has_learned_ability(ability_id):
		return false  # Already learned

	var ability := AbilityDatabase.get_ability_view(ability_id)
	if ability.is_empty():
		return false  # Invalid ability

	var jp_cost = ability.jp_cost
	var available_jp = job_jp.get(job_id, 0)

	if available_jp < jp_cost:
		return false  # Not enough JP

	# Spend JP and learn ability
	job_jp[job_id] = available_jp - jp_cost
	learned_abilities[ability_id] = true

	# Recalculate job level for the job we spent JP from
	var new_level = JobLevelsDatabase.get_job_level_from_jp(job_jp[job_id])
	job_levels[job_id] = new_level

	ability_learned.emit(ability_id, ability.name)
	return true


func has_learned_ability(ability_id: int) -> bool:
	"""Check if an ability has been learned.

	Args:
		ability_id: ID of ability to check

	Returns:
		True if ability is learned
	"""
	return learned_abilities.has(ability_id)


func get_learned_abilities() -> Array:
	"""Get list of all learned ability IDs.

	Returns:
		Array of ability IDs
	"""
	return learned_abilities.keys()


func get_learnable_abilities() -> Array:
	"""Get abilities that can be learned from current job.

	Returns:
		Array of {id, name, jp_cost, category, can_afford, learned} dictionaries
	"""
	var abilities := AbilityDatabase.get_learnable_abilities_for_job(current_job_id)
	var current_jp = job_jp.get(current_job_id, 0)

	var result: Array = []
	for ability in abilities:
		result.append({
			"id": ability.id,
			"name": ability.name,
			"jp_cost": ability.jp_cost,
			"category": ability.category,
			"can_afford": current_jp >= ability.jp_cost,
			"learned": has_learned_ability(ability.id)
		})

	return result


## Equipment System

func equip_item(slot: EquipSlot, item_id: int) -> bool:
	"""Equip an item to a slot.

	Args:
		slot: Equipment slot (RIGHT_HAND, LEFT_HAND, HEAD, BODY, ACCESSORY)
		item_id: Item ID to equip (-1 to unequip)

	Returns:
		True if item was equipped successfully
	"""
	if item_id >= 0 and not can_equip_item(slot, item_id):
		return false

	var old_item_id = equipment[slot]
	equipment[slot] = item_id
	equipment_changed.emit(slot, old_item_id, item_id)
	stats_changed.emit()
	return true


func unequip_item(slot: EquipSlot) -> int:
	"""Unequip item from a slot.

	Args:
		slot: Equipment slot to unequip

	Returns:
		Item ID that was unequipped (-1 if slot was empty)
	"""
	var old_item_id = equipment[slot]
	if old_item_id >= 0:
		equipment[slot] = -1
		equipment_changed.emit(slot, old_item_id, -1)
		stats_changed.emit()
	return old_item_id


func get_equipped_item(slot: EquipSlot) -> int:
	"""Get the item ID equipped in a slot.

	Args:
		slot: Equipment slot to check

	Returns:
		Item ID or -1 if empty
	"""
	return equipment.get(slot, -1)


func can_equip_item(slot: EquipSlot, item_id: int) -> bool:
	"""Check if an item can be equipped to a slot.

	Uses item category to determine valid slots:
	- RIGHT_HAND: weapons
	- LEFT_HAND: shields (or weapons with Two Swords)
	- HEAD: armor items with head item_type (Helmet, Hat, HairAdornment)
	- BODY: armor items with body item_type (Armor, Clothing, Robe)
	- ACCESSORY: accessory items

	Args:
		slot: Target equipment slot
		item_id: Item to check

	Returns:
		True if item is valid for this slot
	"""
	if item_id < 0:
		return true  # Can always unequip

	var category = ItemDatabase.get_item(item_id).get("category", "")

	match slot:
		EquipSlot.RIGHT_HAND:
			return category == "weapon"
		EquipSlot.LEFT_HAND:
			# Left hand can hold shields, or weapons with Two Swords ability (not implemented yet)
			return category == "shield"
		EquipSlot.HEAD:
			return ItemDatabase.is_head_armor(item_id)
		EquipSlot.BODY:
			return ItemDatabase.is_body_armor(item_id)
		EquipSlot.ACCESSORY:
			return category == "accessory"

	return false


func get_equipment_stat_bonuses() -> Dictionary:
	"""Get total stat bonuses from all equipped items.

	Returns:
		Dictionary with pa, ma, speed, move, jump, hp, mp bonuses
	"""
	var totals = {"pa": 0, "ma": 0, "speed": 0, "move": 0, "jump": 0, "hp": 0, "mp": 0}

	for slot in equipment:
		var item_id = equipment[slot]
		if item_id >= 0:
			var bonuses = ItemDatabase.get_stat_bonuses(item_id)
			for key in totals:
				totals[key] += bonuses.get(key, 0)

	return totals


func get_weapon_power() -> int:
	"""Get weapon power from equipped right-hand weapon.

	Returns:
		Weapon power value or 0 if no weapon equipped
	"""
	var weapon_id = equipment[EquipSlot.RIGHT_HAND]
	if weapon_id >= 0 and ItemDatabase.is_weapon(weapon_id):
		return ItemDatabase.get_weapon_power(weapon_id)
	return 0


func get_weapon_range() -> int:
	"""Get attack range from equipped weapon.

	Returns:
		Weapon range or 1 if no weapon equipped
	"""
	var weapon_id = equipment[EquipSlot.RIGHT_HAND]
	if weapon_id >= 0 and ItemDatabase.is_weapon(weapon_id):
		return ItemDatabase.get_weapon_range(weapon_id)
	return 1


func get_physical_evade() -> int:
	"""Get physical evade from equipped shield.

	Returns:
		Physical block percentage or 0 if no shield
	"""
	var shield_id = equipment[EquipSlot.LEFT_HAND]
	if shield_id >= 0 and ItemDatabase.is_shield(shield_id):
		return ItemDatabase.get_physical_block(shield_id)
	return 0


func get_magic_evade() -> int:
	"""Get magic evade from equipped shield.

	Returns:
		Magic block percentage or 0 if no shield
	"""
	var shield_id = equipment[EquipSlot.LEFT_HAND]
	if shield_id >= 0 and ItemDatabase.is_shield(shield_id):
		return ItemDatabase.get_magic_block(shield_id)
	return 0


func get_accessory_evade() -> int:
	"""Get accessory evade from the equipped accessory (A-EV on the Status screen).

	In FFT some accessories (mantles, shoes) grant physical/magic evasion. Our
	items.json does not yet parse an accessory evade field, so this returns 0 for
	current data — the getter is the honest data path (mirrors the shield/weapon
	evade getters), and lights up for free once the field is extracted.

	Returns:
		Accessory evade percentage, or 0 if none / not parsed.
	"""
	var accessory_id = equipment[EquipSlot.ACCESSORY]
	if accessory_id >= 0:
		var item = ItemDatabase.get_item(accessory_id)
		var accessory = item.get("accessory", {})
		return int(accessory.get("evade_percent", 0))
	return 0


func get_weapon_evade() -> int:
	"""Get weapon evade from equipped weapon (W-EV).

	Some weapons (knives, ninja blades) provide evasion.
	This only applies to physical attacks, not magic.

	Returns:
		Weapon evade percentage or 0 if no weapon or weapon has no evade
	"""
	var weapon_id = equipment[EquipSlot.RIGHT_HAND]
	if weapon_id >= 0 and ItemDatabase.is_weapon(weapon_id):
		return ItemDatabase.get_weapon_evade(weapon_id)
	return 0


func get_weapon_formula() -> int:
	"""Get damage formula from equipped weapon.

	Returns:
		Formula ID (1 = PA*WP, 2 = PA*(PA/2), 7 = MA*WP, etc.)
		Returns 2 (bare fist) if no weapon equipped.
	"""
	var weapon_id = equipment[EquipSlot.RIGHT_HAND]
	if weapon_id >= 0 and ItemDatabase.is_weapon(weapon_id):
		return ItemDatabase.get_weapon_formula(weapon_id)
	return 2  # Bare fist formula


func get_weapon_flags() -> Dictionary:
	"""Get weapon attack type flags.

	Returns:
		Dictionary with striking, lunging, direct, arc bools.
		Returns all false (bare fist) if no weapon equipped.
	"""
	var weapon_id = equipment[EquipSlot.RIGHT_HAND]
	if weapon_id >= 0 and ItemDatabase.is_weapon(weapon_id):
		return ItemDatabase.get_weapon_flags(weapon_id)
	return {"striking": false, "lunging": false, "direct": false, "arc": false}


func get_equipment_elements() -> Dictionary:
	"""Get aggregated elemental properties from all equipped items.

	Returns:
		Dictionary with:
		- absorb: Array of element names absorbed
		- cancel: Array of element names nullified
		- half: Array of element names halved
		- weak: Array of element names weak to
		- strengthen: Array of element names strengthened
		- weapon: Array of weapon element names
	"""
	var result = {
		"absorb": [],
		"cancel": [],
		"half": [],
		"weak": [],
		"strengthen": [],
		"weapon": []
	}

	for slot in equipment:
		var item_id = equipment[slot]
		if item_id >= 0:
			var elements = ItemDatabase.get_elements(item_id)
			# Merge arrays (avoiding duplicates)
			for key in ["absorb", "cancel", "half", "weak", "strengthen"]:
				for elem in elements.get(key, []):
					if elem not in result[key]:
						result[key].append(elem)
			# Weapon elements only from right hand
			if slot == EquipSlot.RIGHT_HAND:
				for elem in elements.get("weapon_elements", []):
					if elem not in result["weapon"]:
						result["weapon"].append(elem)

	return result


func get_equipment_statuses() -> Dictionary:
	"""Get aggregated status effects from all equipped items.

	Returns:
		Dictionary with:
		- permanent: Array of status names granted while equipped
		- immunity: Array of status names the unit is immune to
		- starting: Array of status names applied at battle start
	"""
	var result = {
		"permanent": [],
		"immunity": [],
		"starting": []
	}

	for slot in equipment:
		var item_id = equipment[slot]
		if item_id >= 0:
			var statuses = ItemDatabase.get_statuses(item_id)
			# Merge arrays (avoiding duplicates)
			for key in ["permanent", "immunity", "starting"]:
				for status in statuses.get(key, []):
					if status not in result[key]:
						result[key].append(status)

	return result


## Ability Slot Management

func set_sub_job(job_id: String) -> bool:
	"""Set the secondary job for action abilities.

	Args:
		job_id: Job ID (hex string) or empty string to clear

	Returns:
		True if job was set successfully
	"""
	if not job_id.is_empty():
		var job = JobDatabase.get_job(job_id)
		if job.is_empty():
			push_warning("[UnitProgression] Cannot set unknown sub-job: %s" % job_id)
			return false

	sub_job_id = job_id
	stats_changed.emit()
	return true


func get_sub_job_name() -> String:
	"""Get name of the secondary job."""
	if sub_job_id.is_empty():
		return ""
	var job = JobDatabase.get_job(sub_job_id)
	return job.get("name", "")


func set_equipped_reaction(ability_id: int) -> bool:
	"""Equip a reaction ability.

	Args:
		ability_id: Reaction ability ID, or -1 to unequip

	Returns:
		True if ability was equipped successfully
	"""
	if ability_id >= 0:
		var ability := AbilityDatabase.get_ability_view(ability_id)
		if ability.is_empty():
			push_warning("[UnitProgression] Cannot equip unknown ability: %d" % ability_id)
			return false
		if AbilityType.from_string(ability.ability_type) != AbilityType.Type.REACTION:
			push_warning("[UnitProgression] Ability %d is not a Reaction type" % ability_id)
			return false

	equipped_reaction = ability_id
	stats_changed.emit()
	return true


func get_equipped_reaction_name() -> String:
	"""Get name of equipped reaction ability."""
	if equipped_reaction < 0:
		return ""
	return AbilityDatabase.get_ability_view(equipped_reaction).name



func set_equipped_support(ability_id: int) -> bool:
	"""Equip a support ability.

	Args:
		ability_id: Support ability ID, or -1 to unequip

	Returns:
		True if ability was equipped successfully
	"""
	if ability_id >= 0:
		var ability := AbilityDatabase.get_ability_view(ability_id)
		if ability.is_empty():
			push_warning("[UnitProgression] Cannot equip unknown ability: %d" % ability_id)
			return false
		if AbilityType.from_string(ability.ability_type) != AbilityType.Type.SUPPORT:
			push_warning("[UnitProgression] Ability %d is not a Support type" % ability_id)
			return false

	equipped_support = ability_id
	stats_changed.emit()
	return true


func get_equipped_support_name() -> String:
	"""Get name of equipped support ability."""
	if equipped_support < 0:
		return ""
	return AbilityDatabase.get_ability_view(equipped_support).name


func set_equipped_movement(ability_id: int) -> bool:
	"""Equip a movement ability.

	Args:
		ability_id: Movement ability ID, or -1 to unequip

	Returns:
		True if ability was equipped successfully
	"""
	if ability_id >= 0:
		var ability := AbilityDatabase.get_ability_view(ability_id)
		if ability.is_empty():
			push_warning("[UnitProgression] Cannot equip unknown ability: %d" % ability_id)
			return false
		if AbilityType.from_string(ability.ability_type) != AbilityType.Type.MOVEMENT:
			push_warning("[UnitProgression] Ability %d is not a Movement type" % ability_id)
			return false

	equipped_movement = ability_id
	stats_changed.emit()
	return true


func get_equipped_movement_name() -> String:
	"""Get name of equipped movement ability."""
	if equipped_movement < 0:
		return ""
	return AbilityDatabase.get_ability_view(equipped_movement).name


## Helpers

func _get_stat_type_name() -> String:
	"""Convert BaseStatType enum to string."""
	match base_stat_type:
		BaseStatType.MALE:
			return "male"
		BaseStatType.FEMALE:
			return "female"
		BaseStatType.MONSTER:
			return "monster"
	return "male"
