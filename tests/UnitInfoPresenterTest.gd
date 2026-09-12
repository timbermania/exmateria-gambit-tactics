extends Node

## UnitInfoPresenter test — pure GDScript, no GPU / no nodes.
##
## Guards the field-inspect info-window data mapping (#91): a unit's
## UnitStats/snapshot view -> formatted display rows + bar fill fractions.
## The window node reads this live each frame; the presenter is pure so the
## HP/MP/CT/Brave/Faith/status logic is testable without rendering.

const UnitInfoPresenter = preload("res://src/ui3/UnitInfoPresenter.gd")


func _approx(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001


func _ready() -> void:
	var failed := false

	# A typical mid-fight unit view.
	var view := {
		"name": "Ramza", "job": "Squire", "level": 5,
		"current_hp": 80, "max_hp": 100,
		"current_mp": 20, "max_mp": 50,
		"ct": 60, "brave": 70, "faith": 55,
		"statuses": ["Haste", "Protect"],
	}
	var m: Dictionary = UnitInfoPresenter.build(view)

	# 1. Identity passes through.
	if m["name"] != "Ramza" or m["job"] != "Squire" or m["level"] != 5:
		print("[FAIL] identity: %s" % m); failed = true

	# 1b. sprite_id (portrait source) passes through; defaults to -1 (no portrait).
	if UnitInfoPresenter.build({"sprite_id": 0x07})["sprite_id"] != 0x07:
		print("[FAIL] sprite_id passthrough"); failed = true
	if m["sprite_id"] != -1:
		print("[FAIL] sprite_id default: %s" % m["sprite_id"]); failed = true

	# 1c. template_folder (preferred OWNED portrait source, #205) passes through;
	# defaults to "" (no folder -> the flat sprite_id path stays load-bearing).
	var folder := "res://assets/characters/templates/ramza_3/"
	if UnitInfoPresenter.build({"template_folder": folder})["template_folder"] != folder:
		print("[FAIL] template_folder passthrough"); failed = true
	if m["template_folder"] != "":
		print("[FAIL] template_folder default: %s" % m["template_folder"]); failed = true

	# 2. HP row: cur/max text + fill fraction.
	if m["hp"]["text"] != "80/100" or not _approx(m["hp"]["frac"], 0.8):
		print("[FAIL] hp row: %s" % m["hp"]); failed = true
	if m["mp"]["text"] != "20/50" or not _approx(m["mp"]["frac"], 0.4):
		print("[FAIL] mp row: %s" % m["mp"]); failed = true

	# 3. CT is out of 100.
	if m["ct"]["text"] != "60/100" or not _approx(m["ct"]["frac"], 0.6):
		print("[FAIL] ct row: %s" % m["ct"]); failed = true

	# 4. Brave / Faith pass through.
	if m["brave"] != 70 or m["faith"] != 55:
		print("[FAIL] brave/faith: %d/%d" % [m["brave"], m["faith"]]); failed = true

	# 5. Statuses pass through in order.
	if m["statuses"] != ["Haste", "Protect"]:
		print("[FAIL] statuses: %s" % str(m["statuses"])); failed = true

	# 6. Fractions clamp to [0,1] (overheal / over-CT never overflow the bar).
	var over: Dictionary = UnitInfoPresenter.build({
		"current_hp": 150, "max_hp": 100, "ct": 130})
	if not _approx(over["hp"]["frac"], 1.0) or not _approx(over["ct"]["frac"], 1.0):
		print("[FAIL] clamp high: hp=%s ct=%s" % [over["hp"]["frac"], over["ct"]["frac"]])
		failed = true

	# 7. Zero / missing max never divides by zero (dead or unspawned unit).
	var dead: Dictionary = UnitInfoPresenter.build({"current_hp": 0, "max_hp": 0})
	if not _approx(dead["hp"]["frac"], 0.0) or dead["hp"]["text"] != "0/0":
		print("[FAIL] zero-max: %s" % dead["hp"]); failed = true

	# 8. Missing fields fall back to sane defaults (partial snapshot).
	var partial: Dictionary = UnitInfoPresenter.build({"name": "Mob"})
	if partial["name"] != "Mob" or partial["statuses"] != [] or partial["brave"] != 0:
		print("[FAIL] partial defaults: %s" % partial); failed = true

	if failed:
		print("[FAIL] UnitInfoPresenter test")
	else:
		print("[PASS] UnitInfoPresenter: HP/MP/CT rows, brave/faith, statuses, clamping, defaults")
	get_tree().quit()
