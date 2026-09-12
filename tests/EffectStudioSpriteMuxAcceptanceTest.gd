extends Node
## Real-asset acceptance for the Colour-ribbon sprite mux (CONTEXT.md "Colour ribbon"): on
## the REAL E138, emitter idx0's particle sprite is a pure-green region (texture.tga, R=0/B=0),
## so the multiplicative render (ALBEDO = sprite.rgb * modulate.rgb) can only ever show green —
## no colour curve can add red or blue. The ribbon must reflect that TRUTH: every band R=0/B=0
## with green alive. This is the exact confusion that motivated the mux ("I change the curves
## but it stays green"). White-sprite emitters are unaffected (identity mux) — covered by the
## synthetic wiring test; here we pin the real green case end to end.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioSpriteMuxAcceptanceTest.tscn

const CellColour = preload("res://src/effects/studio/SequenceCellColour.gd")
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")
const ColourRibbonClass = preload("res://src/effects/studio/ColourRibbon.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const SpriteColor = preload("res://src/effects/studio/EmitterSpriteColor.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_e138_emitter0_ribbon_is_green_locked()

	print("\n=== EffectStudioSpriteMuxAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSpriteMuxAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSpriteMuxAcceptanceTest")
		get_tree().quit(0)


func _test_e138_emitter0_ribbon_is_green_locked() -> void:
	var dir := "res://assets/effects/E138"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		print("[SKIP] E138 extract absent — sprite-mux acceptance skipped")
		return
	var ed = EffectDataClass.load_from_directory(dir)

	# The resolver sees emitter idx0 as green-only.
	var rep: Color = SpriteColor.representative(ed, 0)
	_assert_true(rep.r < 0.02 and rep.b < 0.02 and rep.g > 0.2,
		"E138 idx0 representative is green-only (got %s)" % str(rep))

	# The whole STUDIO path mirrors it: compose emitter 0's over-life ribbon the way the
	# player column does and read its bands.
	#
	# The ribbon left the inspector for the player column in the ADR-0089 colour-move
	# amendment, so this drives the page's three production calls rather than a widget tree
	# (the same port EffectStudioColourRibbonWiringTest took, for the same reason).
	var prov: Dictionary = CellColour.for_emitter(ed, 0)
	var ribbon = ColourRibbonClass.new()
	add_child(ribbon)
	ribbon.set_curves(prov.get("r"), prov.get("g"), prov.get("b"), prov.get("r") != null,
		int(LifeWindow.resolve(ed, 0).get("n", -1)), true, rep)
	remove_child(ribbon)
	if not ribbon.visible:
		# Colour is enabled on E138 idx0, so a ribbon must draw; a blank one is a failure.
		_assert_true(false, "E138 idx0 shows a Colour ribbon (colour is enabled)")
		ribbon.free()
		return
	var cols: Array = ribbon.colors()
	_assert_true(cols.size() > 0, "ribbon has bands")
	var green_alive := false
	var red_or_blue_leaked := false
	for c in cols:
		if c.r > 0.02 or c.b > 0.02:
			red_or_blue_leaked = true
		if c.g > 0.02:
			green_alive = true
	_assert_true(not red_or_blue_leaked, "no band shows red/blue — sprite is green-only")
	_assert_true(green_alive, "green is alive across the ribbon (the sprite CAN show green)")
	ribbon.free()


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)
