extends Node

## SfxCatalog semantic-label test — pure GDScript, no GPU / SPU playback
## dependency. Guards the hand-authored global-SFX label set
## (assets/audio/sfx_banks/sfx_bank_names.json).
##
## Why it matters: the labels are the only thing giving the system/env banks
## semantic meaning. A typo'd slug, a shifted id, or a broken catalog load
## would silently route the wrong sound (or none). We assert known anchors —
## the unit-death triplet (male_death 0x44 / female_death 0x45 / monster_death
## 0x46), gun_shot_loud_1 = 0x5B, the env rain_1 loop — plus the full bank
## counts. SfxRouter behavior is covered separately in SfxRouterTest.

const SfxCatalog = preload("res://src/audio/SfxCatalog.gd")


func _ready() -> void:
	var failed := false

	# 1. Unit-death triplet — adjacent slots 0x44/0x45/0x46. The catalog
	#    `name` field stays wiki-faithful ("Male Scream") even though the
	#    slug is the role-symmetric `male_death`.
	if SfxCatalog.slot_for("system", "male_death") != 0x44:
		print("[FAIL] system 'male_death' -> %d, expected 0x44" % SfxCatalog.slot_for("system", "male_death"))
		failed = true
	if SfxCatalog.name_for("system", 0x44) != "Male Scream":
		print("[FAIL] system slot 0x44 -> '%s', expected 'Male Scream'" % SfxCatalog.name_for("system", 0x44))
		failed = true
	if SfxCatalog.slot_for("system", "female_death") != 0x45:
		print("[FAIL] system 'female_death' -> %d, expected 0x45" % SfxCatalog.slot_for("system", "female_death"))
		failed = true
	if SfxCatalog.name_for("system", 0x45) != "Female Death":
		print("[FAIL] system slot 0x45 -> '%s', expected 'Female Death'" % SfxCatalog.name_for("system", 0x45))
		failed = true
	if SfxCatalog.slot_for("system", "monster_death") != 0x46:
		print("[FAIL] system 'monster_death' -> %d, expected 0x46" % SfxCatalog.slot_for("system", "monster_death"))
		failed = true

	# 2. Other system anchor.
	if SfxCatalog.slot_for("system", "gun_shot_loud_1") != 0x5B:
		print("[FAIL] system 'gun_shot_loud_1' -> %d, expected 0x5B" % SfxCatalog.slot_for("system", "gun_shot_loud_1"))
		failed = true

	# 3. Env anchor + loop flag.
	if SfxCatalog.slot_for("env", "rain_1") != 0x01:
		print("[FAIL] env 'rain_1' -> %d, expected 0x01" % SfxCatalog.slot_for("env", "rain_1"))
		failed = true
	if not SfxCatalog.is_loop("env", 0x01):
		print("[FAIL] env 'rain_1' (0x01) should be a looping sound")
		failed = true

	# 4. Unknown slug returns -1, not a bogus slot.
	if SfxCatalog.slot_for("system", "does_not_exist") != -1:
		print("[FAIL] unknown slug should resolve to -1")
		failed = true

	# 5. Full bank coverage (167 system ids 0x01-0xA7, 27 env ids 0x01-0x1B).
	if SfxCatalog.bank_sounds("system").size() != 167:
		print("[FAIL] system bank has %d labels, expected 167" % SfxCatalog.bank_sounds("system").size())
		failed = true
	if SfxCatalog.bank_sounds("env").size() != 27:
		print("[FAIL] env bank has %d labels, expected 27" % SfxCatalog.bank_sounds("env").size())
		failed = true

	if failed:
		print("[FAIL] SfxCatalog test")
	else:
		print("[PASS] SfxCatalog: death triplet 0x44/0x45/0x46 + other anchors resolve")
	get_tree().quit()
