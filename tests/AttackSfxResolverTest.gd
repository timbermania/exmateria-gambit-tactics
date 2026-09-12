extends Node

## AttackSfxResolver test — pure GDScript, no GPU / SPU playback.
##
## Guards the weapon_graphic -> sound_class -> {swing,hit,block} resolution that
## drives basic-melee attack SFX. PROVEN LIVE IN PCSX (2026-06-11): FFT keys the
## basic-attack sound off the EQUIPPED WEAPON's `graphic` id (unit+0x1ab), NOT
## the unit sprite/job. A Ninja's Dagger (graphic 1) and Mythril Knife (graphic
## 2) each produced their own key -> both class 1; a Rune Blade (graphic 0x13)
## -> class 3. So an archer holding a sword slashes (sword graphic), it does not
## twang. The graphic comes from items.json `graphic` per weapon.

const AttackSfxResolver = preload("res://src/audio/AttackSfxResolver.gd")


func _ready() -> void:
	var failed := false

	# 1. PCSX-confirmed: Dagger (graphic 1) and Mythril Knife (graphic 2) -> class 1.
	for g in [1, 2]:
		if AttackSfxResolver.sound_class_for_weapon(g) != 1:
			print("[FAIL] knife graphic %d -> class %d, expected 1" % [g, AttackSfxResolver.sound_class_for_weapon(g)])
			failed = true
	var knife: Dictionary = AttackSfxResolver.attack_sounds_for_weapon(1)
	if knife.get("swing", "") != "light_weapon_swing" or knife.get("hit", "") != "slash":
		print("[FAIL] knife class-1 slugs wrong: %s" % knife)
		failed = true

	# 2. PCSX-confirmed: Rune Blade (graphic 0x13) -> class 3 -> medium swing / slash.
	if AttackSfxResolver.sound_class_for_weapon(0x13) != 3:
		print("[FAIL] Rune Blade 0x13 -> class %d, expected 3" % AttackSfxResolver.sound_class_for_weapon(0x13))
		failed = true
	var rune: Dictionary = AttackSfxResolver.attack_sounds_for_weapon(0x13)
	if rune.get("swing", "") != "medium_weapon_swing" or rune.get("hit", "") != "slash" \
			or rune.get("block", "") != "shield_block_light":
		print("[FAIL] Rune Blade class-3 slugs wrong: %s" % rune)
		failed = true

	# 3. A basic Sword (graphic 0x0C) is class 2 — distinct key from the rune
	#    blade but a lighter swing. Confirms the table differentiates weapon tiers.
	if AttackSfxResolver.sound_class_for_weapon(0x0C) != 2:
		print("[FAIL] Sword 0x0C -> class %d, expected 2" % AttackSfxResolver.sound_class_for_weapon(0x0C))
		failed = true

	# 4. Unarmed (graphic 0 = fists) -> class 0 -> light swing / BLUNT hit / cloth block.
	#    This is how a Monk's bare-handed attack resolves.
	if AttackSfxResolver.sound_class_for_weapon(0) != 0:
		print("[FAIL] fists graphic 0 -> class %d, expected 0" % AttackSfxResolver.sound_class_for_weapon(0))
		failed = true
	var fists: Dictionary = AttackSfxResolver.attack_sounds_for_weapon(0)
	if fists.get("hit", "") != "blunt_weapon_hit" or fists.get("block", "") != "punch_bag_cloth_blocked":
		print("[FAIL] fists class-0 slugs wrong: %s" % fists)
		failed = true

	# 5. A gun (graphic 0x2C) and a bow (graphic 0x31) get their own families.
	if AttackSfxResolver.sound_class_for_weapon(0x2C) != 5:
		print("[FAIL] gun 0x2C -> class %d, expected 5" % AttackSfxResolver.sound_class_for_weapon(0x2C))
		failed = true
	if AttackSfxResolver.sound_class_for_weapon(0x31) != 6:
		print("[FAIL] bow 0x31 -> class %d, expected 6" % AttackSfxResolver.sound_class_for_weapon(0x31))
		failed = true

	if failed:
		print("[FAIL] AttackSfxResolver test")
	else:
		print("[PASS] AttackSfxResolver: weapon graphic -> class -> swing/hit/block (knife=1, sword=2, rune=3, fists=0, gun=5, bow=6)")
	get_tree().quit()
