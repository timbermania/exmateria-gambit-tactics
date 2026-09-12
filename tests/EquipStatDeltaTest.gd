extends Node
## EquipStatDelta test — pure GDScript, no GPU / scene needed.
##
## Guards the numeric equip stat-DELTA computation (research/working_documents/
## EQUIP_STAT_PREVIEW.md). The ROM runs a dry-run equip into a scratch pseudo-unit
## (unit 0x14) then computes `preview − base` per stat field. In the port that math
## is pure: `contribution(candidate) − contribution(base)` read from items.json,
## with an EMPTY base slot (id -1) contributing 0.
##
## Seam: EquipStatDelta.compute(candidate_id, base_id) -> {wp, wev, hp, mp}. Weapon
## deltas land in wp/wev (the Weap.Power row's two numbers); armor/accessory HP·MP
## land in hp/mp (the vitals numerator sink). A field the item type doesn't drive is
## 0 (→ the panel dashes it), which is how routing falls out: a weapon has hp/mp 0,
## an armor has wp/wev 0.
##
## Expected values are the RE-doc / FFTPatcher-confirmed item constants (independent
## source of truth): Broad Sword id19 WP=4/EV=5; Dagger id1 WP=3/EV=5; Clothes id186
## hp_bonus=5. The three oracle savestates predict every number below.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const EquipStatDelta = ExMateriaAlmanac.EquipStatDelta



var _failed := false


func _ready() -> void:
	# sstate2: Broad Sword (id 19) into an EMPTY R.Hand → WP 0→4 = +4, EV 0→5 = +5.
	_eq(EquipStatDelta.compute(19, -1), {"wp": 4, "wev": 5, "hp": 0, "mp": 0},
		"Broad Sword into empty slot")

	# sstate4: Dagger (id 1) over an EQUIPPED Broad Sword (id 19) → WP 3−4 = −1 (the
	# proof this is a DELTA, not the raw value), EV 5−5 = 0 (→ dash).
	_eq(EquipStatDelta.compute(1, 19), {"wp": -1, "wev": 0, "hp": 0, "mp": 0},
		"Dagger over equipped Broad Sword")

	# sstate3: Clothes (id 186) onto an empty Body slot → hp_bonus 0→5 = +5 on the HP
	# numerator; a body-armor drives no weapon fields, so wp/wev stay 0 (dashed).
	_eq(EquipStatDelta.compute(186, -1), {"wp": 0, "wev": 0, "hp": 5, "mp": 0},
		"Clothes onto empty Body")

	# Routing sanity, the other direction: a weapon (Broad Sword) drives no HP/MP, so
	# hp/mp are 0 even swapping over another weapon — the vitals sink stays dashed.
	var w := EquipStatDelta.compute(19, 1)
	_expect(w.get("hp", 99) == 0 and w.get("mp", 99) == 0,
		"weapon swap must not touch hp/mp, got %s" % w)

	# --- FULL BAND COVERAGE (research/working_documents/EQUIP_STAT_PREVIEW.md "full coverage"):
	# every band field the equip changes previews its delta, not just wp/wev/hp/mp. Values are
	# the items.json / FFTPatcher constants (independent source of truth).

	# SHIELD → S-EV (physical block). Round Shield id131 phys_block 19 into empty L.Hand → +19.
	_eq(EquipStatDelta.compute(131, -1), {"s_ev": 19, "wp": 0, "wev": 0, "hp": 0, "mp": 0},
		"Round Shield into empty L.Hand → S-EV +19")
	# Escutcheon id143 phys_block 75 OVER Round Shield id131 (19) → 75−19 = +56 (proves it's a delta).
	_eq(EquipStatDelta.compute(143, 131), {"s_ev": 56}, "Escutcheon over Round Shield → S-EV +56")

	# SPEED hat. Green Beret id162 speed_bonus +1 into empty → Speed +1 (and no S-EV/wp).
	_eq(EquipStatDelta.compute(162, -1), {"speed": 1, "s_ev": 0, "wp": 0}, "Green Beret → Speed +1")
	# Thief Hat id168 speed +2 OVER Green Beret id162 (+1) → 2−1 = +1.
	_eq(EquipStatDelta.compute(168, 162), {"speed": 1}, "Thief Hat over Green Beret → Speed +1")

	# PA hat → feeds the AT row. Twist Headband id163 pa_bonus +2 into empty → pa +2.
	_eq(EquipStatDelta.compute(163, -1), {"pa": 2, "speed": 0, "s_ev": 0}, "Twist Headband → PA +2")

	# MOVE/JUMP accessory. Germinas Boots id210 move+1 jump+1 into empty → move +1, jump +1.
	_eq(EquipStatDelta.compute(210, -1), {"move": 1, "jump": 1}, "Germinas Boots → Move+1 Jump+1")
	# Battle Boots id208 (move+1, jump 0) OVER Germinas Boots id210 (move+1, jump+1) → move 0, jump −1.
	_eq(EquipStatDelta.compute(208, 210), {"move": 0, "jump": -1}, "Battle Boots over Germinas → Jump −1")

	if _failed:
		print("[FAIL] EquipStatDelta test")
		get_tree().quit(1)
	else:
		print("[PASS] EquipStatDelta: preview−base per field (weapon→wp/wev, armor→hp/mp, empty base=0)")
		get_tree().quit(0)


func _eq(got: Dictionary, want: Dictionary, label: String) -> void:
	for k in want:
		if int(got.get(k, 0x7fffffff)) != int(want[k]):
			print("[FAIL] %s: field %s = %s, expected %s (full %s)" % [label, k, got.get(k), want[k], got])
			_failed = true
			return


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true
