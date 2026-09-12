extends Node
## Pure StatusEncoder test (#98). No GPU / RenderingDevice / scene setup.
## Witnesses:
##   1. Every FFTPatcher CamelCase name for a StatusRegistry bit round-trips
##      to the right bit (23 names).
##   2. DontMove and DontAct synonyms map to immobilize / disable.
##   3. The five unmapped names (Charm, Reflect, DeathSentence, Innocent,
##      Crystal) are skipped (mask contributes 0) and don't crash.
##   4. mode_from_string maps "all"/"random"/"separate"/"cancel"/null to the
##      INFLICT_MODE_* constants.
##   5. mask_from_fft_names combines names via OR and a mixed mapped+unmapped
##      array returns only the mapped bits.
##   6. inflict_for_record resolves the mask and the mode TOGETHER (#1117), and
##      weapon_inflict_for_item is one of its callers rather than a second
##      resolver — the pair is the unit, because a non-zero mask beside
##      MODE_NONE is an ability that lists statuses and inflicts nothing.
##   7. THE RATCHET: no committed ability or item record is that contradiction.
##      Every record with a non-empty mask names one of the four modes, and no
##      record names a mode outside them. Measured at zero violations when #1117
##      landed, and the ROM's own 128-entry InflictStatusList has none either —
##      no entry sets statuses with a zero mode byte, and none sets two mode bits
##      — so this is a clean tree held clean, not a threshold.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusEncoder = ExMateriaAlmanac.StatusEncoder
const StatusRegistry = ExMateriaAlmanac.StatusRegistry
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const ItemDatabase = ExMateriaAlmanac.ItemDatabase


var _failed := false


func _ready() -> void:
	_test_round_trip_all_registry_names()
	_test_dontmove_dontact_synonyms()
	_test_unmapped_names_skipped()
	_test_mode_from_string()
	_test_mask_combines()
	_test_inflict_for_record_pairs_mask_and_mode()
	_test_no_record_carries_a_mask_without_a_mode()
	if _failed:
		print("[FAIL] StatusEncoder test")
	else:
		print("[PASS] StatusEncoder: 23 round-trip + synonyms + unmapped skip + mode + combine + record pairing + mask-without-mode ratchet OK")
	get_tree().quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("[FAIL] %s" % msg)


func _test_round_trip_all_registry_names() -> void:
	# For every StatusRegistry bit, build the FFTPatcher CamelCase name and
	# verify mask_from_fft_names([name]) lights only that bit.
	for reg_name in StatusRegistry.NAMES_TO_BITS:
		var fft_name := _to_camel(String(reg_name))
		var mask := StatusEncoder.mask_from_fft_names([fft_name])
		var expected := 1 << StatusRegistry.bit(reg_name)
		_expect(mask == expected,
			"FFT %s -> registry %s: got mask %d, expected %d" % [fft_name, reg_name, mask, expected])


func _test_dontmove_dontact_synonyms() -> void:
	var dm_mask := StatusEncoder.mask_from_fft_names(["DontMove"])
	var im_bit := 1 << StatusRegistry.bit(&"immobilize")
	_expect(dm_mask == im_bit, "DontMove -> immobilize bit (got %d, want %d)" % [dm_mask, im_bit])

	var da_mask := StatusEncoder.mask_from_fft_names(["DontAct"])
	var dis_bit := 1 << StatusRegistry.bit(&"disable")
	_expect(da_mask == dis_bit, "DontAct -> disable bit (got %d, want %d)" % [da_mask, dis_bit])


func _test_unmapped_names_skipped() -> void:
	for n in StatusEncoder.UNMAPPED_NAMES:
		var mask := StatusEncoder.mask_from_fft_names([String(n)])
		_expect(mask == 0, "unmapped %s contributes 0 (got %d)" % [n, mask])

	# Mixed: mapped + unmapped returns only the mapped bit.
	var mixed := StatusEncoder.mask_from_fft_names(["Poison", "Charm"])
	var poison_bit := 1 << StatusRegistry.bit(&"poison")
	_expect(mixed == poison_bit,
		"mixed [Poison, Charm] -> poison bit only (got %d, want %d)" % [mixed, poison_bit])


func _test_mode_from_string() -> void:
	_expect(StatusEncoder.mode_from_string(null) == StatusEncoder.MODE_NONE, "null -> MODE_NONE")
	_expect(StatusEncoder.mode_from_string("all") == StatusEncoder.MODE_ALL, "all -> MODE_ALL")
	_expect(StatusEncoder.mode_from_string("random") == StatusEncoder.MODE_RANDOM, "random -> MODE_RANDOM")
	_expect(StatusEncoder.mode_from_string("separate") == StatusEncoder.MODE_SEPARATE, "separate -> MODE_SEPARATE")
	_expect(StatusEncoder.mode_from_string("cancel") == StatusEncoder.MODE_CANCEL, "cancel -> MODE_CANCEL")
	_expect(StatusEncoder.mode_from_string("bogus") == StatusEncoder.MODE_NONE, "unknown mode -> MODE_NONE")


func _test_mask_combines() -> void:
	var mask := StatusEncoder.mask_from_fft_names(["Poison", "Silence", "Haste"])
	var expected := (1 << StatusRegistry.bit(&"poison")) \
		| (1 << StatusRegistry.bit(&"silence")) \
		| (1 << StatusRegistry.bit(&"haste"))
	_expect(mask == expected, "combine [Poison,Silence,Haste]: got %d, expected %d" % [mask, expected])

	var empty := StatusEncoder.mask_from_fft_names([])
	_expect(empty == 0, "empty array -> mask 0 (got %d)" % empty)


static func _to_camel(snake: String) -> String:
	var parts := snake.split("_")
	var out := ""
	for p in parts:
		if p.length() == 0:
			continue
		out += p.substr(0, 1).to_upper() + p.substr(1)
	return out


func _test_inflict_for_record_pairs_mask_and_mode() -> void:
	# The pair, resolved once. A caller that asked mask_from_fft_names and
	# mode_from_string separately could not see the contradiction between them,
	# which is the class #1117 closed.
	var paired: Dictionary = StatusEncoder.inflict_for_record(
		["Poison", "Silence"], "separate", "test record")
	var want_mask: int = (1 << StatusRegistry.bit(&"poison")) \
		| (1 << StatusRegistry.bit(&"silence"))
	_expect(paired["mask"] == want_mask,
		"inflict_for_record mask: got %d, want %d" % [paired["mask"], want_mask])
	_expect(paired["mode"] == StatusEncoder.MODE_SEPARATE,
		"inflict_for_record mode: got %d, want MODE_SEPARATE" % paired["mode"])

	# An empty record is the common case and must stay silent and zero.
	var empty: Dictionary = StatusEncoder.inflict_for_record([], null, "empty record")
	_expect(empty["mask"] == 0 and empty["mode"] == StatusEncoder.MODE_NONE,
		"inflict_for_record on an empty record -> {0, MODE_NONE}")

	# 🔴 THE CONSUMER, NOT JUST THE PREDICATE. Proving inflict_for_record makes
	# the right decision says nothing about whether the encode sites ASK it.
	# Blind Knife (item 3) inflicts Darkness in `all` mode, so a
	# weapon_inflict_for_item that still resolved the two halves itself would
	# return the same numbers — what this pins is that the ONE accessor both
	# encode sites use agrees with the record resolver on the same input.
	var weapon: Dictionary = StatusEncoder.weapon_inflict_for_item(3)
	var direct: Dictionary = StatusEncoder.inflict_for_record(
		["Darkness"], "all", "Blind Knife")
	_expect(weapon["mask"] == direct["mask"] and weapon["mode"] == direct["mode"],
		"weapon_inflict_for_item(3) {%d,%d} != inflict_for_record {%d,%d}" % [
			weapon["mask"], weapon["mode"], direct["mask"], direct["mode"]])
	_expect(weapon["mask"] == (1 << StatusRegistry.bit(&"darkness")),
		"Blind Knife inflicts Darkness (got mask %d)" % weapon["mask"])


func _test_no_record_carries_a_mask_without_a_mode() -> void:
	# Walk every committed record in both databases. A record that lists statuses
	# this kernel can encode but names no mode would encode cleanly and inflict
	# NOTHING, silently, once per cast forever.
	var known: Array = StatusEncoder.MODE_BY_NAME.keys()
	var checked := 0
	var offenders: Array[String] = []

	for id in AbilityDatabase.ability_ids():
		var view = AbilityDatabase.get_ability_view(id)
		var names: Array = view.inflict_statuses
		var mode = view.inflict_mode
		checked += 1
		if mode != null and not StatusEncoder.MODE_BY_NAME.has(StringName(mode)):
			offenders.append("ability %d names inflict_mode '%s'" % [id, mode])
		elif not names.is_empty() and mode == null:
			offenders.append("ability %d lists %s with no inflict_mode" % [id, names])

	# Items carry two inflict-bearing blocks: the weapon's on-hit set and the
	# chemist item's. Both reach the kernel, so both are in the ratchet.
	for item_id in range(0, 256):
		var item: Dictionary = ItemDatabase.get_item(item_id)
		if item.is_empty():
			continue
		for block_key in ["weapon", "chemist"]:
			var block = item.get(block_key, {})
			if not (block is Dictionary) or block.is_empty():
				continue
			var names: Array = block.get("inflict_statuses", [])
			var mode = block.get("inflict_mode", null)
			checked += 1
			if mode != null and not StatusEncoder.MODE_BY_NAME.has(StringName(mode)):
				offenders.append("item %d %s names inflict_mode '%s'" % [item_id, block_key, mode])
			elif not names.is_empty() and mode == null:
				offenders.append("item %d %s lists %s with no inflict_mode" % [item_id, block_key, names])

	# Anti-vacuity: a walk that found no records is not a clean tree.
	_expect(checked > 400,
		"the ratchet walked only %d records; it should see every ability plus both item blocks" % checked)
	_expect(offenders.is_empty(),
		"%d record(s) carry an inflict set the kernel cannot apply (modes are %s): %s" % [
			offenders.size(), known, ", ".join(offenders.slice(0, 5))])
