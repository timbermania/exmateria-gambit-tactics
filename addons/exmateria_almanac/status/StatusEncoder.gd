extends RefCounted

## FFTPatcher CamelCase status name -> StatusRegistry bit translation (#98).
##
## The single encode-boundary site for converting parser-emitted
## [code]inflict_statuses[/code] arrays (from [code]effects.json[/code] /
## [code]items.json[/code]) into a 32-bit mask the compute shader can OR onto
## a target's [code]STATUS_FLAGS_LO[/code]. Used by:
##
##   - [code]GPUAbilityLoader[/code] — packs ability inflict mask + mode into
##     the ability buffer (AB_INFLICT_MASK / AB_INFLICT_MODE).
##   - [code]GPUCombatPacker._extract_unit_config[/code] — packs the
##     equipped weapon's inflict mask + mode into U_WEAPON_INFLICT_MASK /
##     U_WEAPON_INFLICT_MODE.
##
## Translation rules (ADR-0013 — bit decoding stays at the parser, but the
## consumer owns the name -> shader-bit mapping):
##
##   - 23 names round-trip to [code]StatusRegistry[/code] snake_case directly.
##   - [code]DontMove[/code] -> [code]immobilize[/code] (issue #98 synonym).
##   - [code]DontAct[/code]  -> [code]disable[/code]    (issue #98 synonym).
##   - Charm / Reflect / DeathSentence / Innocent / Crystal — unmapped this
##     slice; logged once on first sighting and skipped. Issue #99 adds bits
##     for these.
##
## Mode constants mirror the shader's INFLICT_MODE_* — see
## combat_common.glslinc.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const ItemDatabase = preload("res://addons/exmateria_almanac/items/ItemDatabase.gd")
const StatusRegistry = preload("res://addons/exmateria_almanac/status/StatusRegistry.gd")


const MODE_NONE = 0
const MODE_ALL = 1
const MODE_RANDOM = 2
const MODE_SEPARATE = 3
const MODE_CANCEL = 4

const MODE_BY_NAME: Dictionary = {
	&"all": MODE_ALL,
	&"random": MODE_RANDOM,
	&"separate": MODE_SEPARATE,
	&"cancel": MODE_CANCEL,
}

# FFTPatcher CamelCase -> StatusRegistry snake_case StringName. Built on
# first use from StatusRegistry.NAMES_TO_BITS plus the two documented
# synonyms; rebuilding from the registry keeps the table from drifting when
# StatusRegistry gains new bits. Lazy (rather than a static-var initializer)
# because the global class cache build runs static initializers and a cross-
# class lookup during that pass can SIGSEGV.
static var _FFT_TO_REGISTRY_NAME: Dictionary = {}
static var _table_built: bool = false

# Names known to be unmapped this slice (slated for issue #99). Used to keep
# the warning quiet and one-shot per name.
const UNMAPPED_NAMES: Array[StringName] = [
	&"Charm", &"Reflect", &"DeathSentence", &"Innocent", &"Crystal",
]

static var _warned: Dictionary = {}


static func mode_from_string(mode: Variant) -> int:
	"""Translate effects.json / items.json `inflict_mode` (null|"all"|...) to
	the shader's INFLICT_MODE_* int."""
	if mode == null:
		return MODE_NONE
	return MODE_BY_NAME.get(StringName(mode), MODE_NONE)


static func inflict_for_record(names: Array, mode: Variant, what: String) -> Dictionary:
	"""Translate ONE ROM inflict record — an `inflict_statuses` name array plus
	its `inflict_mode` string — into the {mask, mode} pair the GPU buffers carry.

	🔴 THE PAIR IS THE UNIT, WHICH IS THE WHOLE REASON THIS EXISTS (#1117). A
	non-zero mask sitting beside MODE_NONE is an ability that lists statuses and
	inflicts nothing: [code]apply_inflict_all[/code] returns on it with no
	warning, at apply time, once per cast forever. Both halves used to be
	resolved by separate calls, so neither site could see the contradiction.

	Measured over the committed assets — 155 status-bearing abilities and 34
	items — there are ZERO such records, and the ROM's own 128-entry
	[code]InflictStatusList[/code] has none either (no entry sets statuses with a
	zero mode byte, and none sets two mode bits at once). So this is a ratchet on
	a clean tree, not a tolerated class. [param what] names the record so the
	error says which one."""
	var mask := mask_from_fft_names(names)
	var mode_id := mode_from_string(mode)
	if mode != null and not MODE_BY_NAME.has(StringName(mode)):
		push_error(("[StatusEncoder] %s: inflict_mode '%s' is not one of %s. " +
			"It decodes to MODE_NONE and the kernel inflicts nothing.")
			% [what, mode, MODE_BY_NAME.keys()])
	elif mask != 0 and mode_id == MODE_NONE:
		push_error(("[StatusEncoder] %s: inflict_statuses %s carry no " +
			"inflict_mode. The kernel needs a mode to apply a mask and " +
			"inflicts nothing.") % [what, names])
	return {"mask": mask, "mode": mode_id}


static func weapon_inflict_for_item(weapon_id: int) -> Dictionary:
	"""Translate the equipped weapon's items.json `weapon` block to {mask,
	mode}. Returns zero / MODE_NONE for an unequipped slot (-1), non-weapon
	items, or weapons that don't inflict. Single accessor for both encode
	sites -- GPUCombatPacker._extract_unit_config (arena, live Unit) and
	GPUCombatTestBase._build_gpu_config (test cfg dict)."""
	if weapon_id < 0:
		return {"mask": 0, "mode": MODE_NONE}
	var item = ItemDatabase.get_item(weapon_id)
	var weapon_block = item.get("weapon", {})
	if not weapon_block:
		return {"mask": 0, "mode": MODE_NONE}
	return inflict_for_record(
		weapon_block.get("inflict_statuses", []),
		weapon_block.get("inflict_mode", null),
		"weapon item %d" % weapon_id)


static func mask_from_fft_names(names: Array) -> int:
	"""OR-combine StatusRegistry bits for each FFT-name in [param names].
	Unknown names (Charm/Reflect/DeathSentence/Innocent/Crystal etc.) warn
	once and contribute 0. DontMove/DontAct are aliased to immobilize/disable."""
	_ensure_table()
	var mask := 0
	for raw in names:
		var fft := StringName(raw)
		if not _FFT_TO_REGISTRY_NAME.has(fft):
			_warn_unmapped(fft)
			continue
		var reg_name: StringName = _FFT_TO_REGISTRY_NAME[fft]
		var b := StatusRegistry.bit(reg_name)
		if b >= 0 and b < 32:
			mask |= (1 << b)
	return mask


static func _ensure_table() -> void:
	if _table_built:
		return
	_FFT_TO_REGISTRY_NAME = _build_fft_name_table()
	_table_built = true


static func _build_fft_name_table() -> Dictionary:
	# StatusRegistry stores snake_case StringNames; FFTPatcher emits CamelCase
	# with a couple of irregulars (DontMove, DontAct, BloodSuck). Build the
	# inverse map by snake_case -> registry name, then add synonyms.
	var table: Dictionary = {}
	for reg_name in StatusRegistry.NAMES_TO_BITS:
		var fft_name := _snake_to_camel(String(reg_name))
		table[StringName(fft_name)] = reg_name
	# DontMove / DontAct — FFT spells "immobilize" / "disable" with the
	# behavioral verb, and the StatusRegistry adopted those verbs. Keep both
	# encode names valid so #98 doesn't need to rename either.
	table[&"DontMove"] = &"immobilize"
	table[&"DontAct"] = &"disable"
	# BloodSuck -> blood_suck. The default _snake_to_camel emits "BloodSuck"
	# which is the FFTPatcher name, so no override needed — sanity-check
	# captures this implicit alignment in the test.
	return table


static func _snake_to_camel(s: String) -> String:
	# poison -> Poison; blood_suck -> BloodSuck; death_sentence -> DeathSentence.
	var parts := s.split("_")
	var out := ""
	for p in parts:
		if p.length() == 0:
			continue
		out += p.substr(0, 1).to_upper() + p.substr(1)
	return out


static func _warn_unmapped(name: StringName) -> void:
	if _warned.has(name):
		return
	_warned[name] = true
	push_warning("[StatusEncoder] FFT status '%s' has no StatusRegistry bit yet (issue #99). Skipped." % name)
