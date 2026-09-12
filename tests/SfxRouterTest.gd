extends Node

## SfxRouter wiring test — pure GDScript, no GPU / RenderingDevice, no SPU
## backend dependency. Catches the failures most likely to silently break
## game-event SFX:
##
##  1. EventBus.unit_died is handler-resolved: the slug (and therefore the
##     bank slot) depends on the dying unit's UnitProgression.base_stat_type.
##     Asserted for MALE (0x44), FEMALE (0x45), MONSTER (0x46).
##  2. cue_requested still carries the cue name ("combat.unit_died") even
##     though the cue is not in the _CUES registry — the observability
##     contract speaks intent, not the resolved sample.
##  3. Unknown cues return 0 and emit nothing — the early-out path stays
##     side-effect-free.
##
## We listen on SfxRouter.cue_requested (fires before the SPU backend) so
## the test works even when ExMateriaEffectSfx isn't actually playing sound
## (e.g. when the C++ FFTSpu GDExtension isn't loaded in CI / a dev env).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression



# Minimal Node-with-progression stub for the unit_died payload. The handler
# reads `unit.unit_progression`; this gives it something to read.
class _FakeUnit extends Node:
	var unit_progression: UnitProgression


func _make_unit(stat_type: int) -> _FakeUnit:
	var u := _FakeUnit.new()
	var p := UnitProgression.new()
	p.base_stat_type = stat_type
	u.unit_progression = p
	add_child(u)
	return u


func _ready() -> void:
	var failed := false
	var observed: Array = []  # of {name, bank, slot}
	var sub := func(n: String, b: String, s: int) -> void:
		observed.append({"name": n, "bank": b, "slot": s})
	SfxRouter.cue_requested.connect(sub)

	# 1. unit_died for each BaseStatType resolves to the right slot.
	var cases := [
		{"stat_type": UnitProgression.BaseStatType.MALE, "slot": 0x44, "label": "MALE"},
		{"stat_type": UnitProgression.BaseStatType.FEMALE, "slot": 0x45, "label": "FEMALE"},
		{"stat_type": UnitProgression.BaseStatType.MONSTER, "slot": 0x46, "label": "MONSTER"},
	]
	for c in cases:
		observed.clear()
		var unit := _make_unit(c["stat_type"])
		EventBus.emit_unit_died(unit)
		await get_tree().process_frame
		if observed.size() != 1:
			print("[FAIL] %s: expected 1 cue_requested, got %d" % [c["label"], observed.size()])
			failed = true
			continue
		var row: Dictionary = observed[0]
		if row["name"] != "combat.unit_died":
			print("[FAIL] %s: cue name '%s', expected 'combat.unit_died'" % [c["label"], row["name"]])
			failed = true
		if row["bank"] != "system" or row["slot"] != c["slot"]:
			print("[FAIL] %s: routed to {bank=%s, slot=0x%02X}, expected {system, 0x%02X}" % [
				c["label"], row["bank"], row["slot"], c["slot"]])
			failed = true

	# 2. Unknown cue: returns 0, no cue_requested emit.
	observed.clear()
	var tok := SfxRouter.play_cue("nonexistent.cue")
	if tok != 0:
		print("[FAIL] play_cue('nonexistent.cue') returned %d, expected 0" % tok)
		failed = true
	if not observed.is_empty():
		print("[FAIL] unknown cue still emitted cue_requested: %s" % str(observed))
		failed = true

	SfxRouter.cue_requested.disconnect(sub)

	if failed:
		print("[FAIL] SfxRouter test")
	else:
		print("[PASS] SfxRouter: unit_died handler resolves MALE/FEMALE/MONSTER slots + unknown-cue fallback")
	get_tree().quit()
