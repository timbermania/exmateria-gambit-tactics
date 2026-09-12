extends Node
## TDD guard for the SPACER = INVISIBLE EMPTY SPACE treatment (ADR-0087 FIFTH amendment):
## a colour-lane tween the SpacerVerdicts fold deems inert AND that is still ENABLED renders
## as NOTHING (like an emitter-lane gap) and is unselectable; a DELIBERATELY-DISABLED event
## (Enable bit cleared) is the opposite — it stays drawn (dimmed, hatched, selectable). The
## SELECTED event always draws, even if its bytes make it a spacer. The single source of that
## decision is the pure predicate EffectScoreTimeline.is_hidden_spacer(span, selected_id),
## consulted by BOTH the painter (skip) and the hit-test (not selectable → clicks fall through
## to empty-space seek / gap context).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectSpacerVisibilityTest.tscn

const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_enabled_inert_spacer_is_hidden()
	_test_disabled_event_is_drawn()
	_test_selected_spacer_always_draws()
	_test_live_event_is_drawn()
	_test_non_colour_span_is_never_hidden()

	print("\n=== EffectSpacerVisibilityTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSpacerVisibilityTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSpacerVisibilityTest")
		get_tree().quit(0)


## An enabled, verdict-inert tween is EMPTY SPACE — hidden (decision 1). This is the only
## automatic disappearance; the author never chose it, the fold detected it.
func _test_enabled_inert_spacer_is_hidden() -> void:
	var span := _span("palette:for_each:caster#3", true, true)
	_assert_true(Timeline.is_hidden_spacer(span, ""),
		"an enabled inert spacer is hidden (invisible empty space)")


## A deliberately-disabled event (Enable bit cleared by a human) is NOT hidden — "muted,
## not gone" (decision 4). It stays drawn so its Enabled knob is reachable.
func _test_disabled_event_is_drawn() -> void:
	var span := _span("palette:for_each:caster#3", true, false)
	_assert_true(not Timeline.is_hidden_spacer(span, ""),
		"a deliberately-disabled event stays drawn (not empty space)")


## The selected event always draws, even when its bytes make it an enabled spacer — so a
## just-added / just-enabled-not-yet-coloured stub never blinks out mid-edit (decision 5).
func _test_selected_spacer_always_draws() -> void:
	var span := _span("palette:for_each:caster#3", true, true)
	_assert_true(not Timeline.is_hidden_spacer(span, "palette:for_each:caster#3"),
		"the selected span draws even if it is an enabled spacer")


## A real (non-spacer) event is drawn regardless of enabled/selection.
func _test_live_event_is_drawn() -> void:
	var span := _span("palette:for_each:caster#3", false, true)
	_assert_true(not Timeline.is_hidden_spacer(span, ""),
		"a live colour event is drawn")


## The predicate is scoped to colour lanes: a span with no `spacer` field (particle / camera /
## sound) is never hidden by it.
func _test_non_colour_span_is_never_hidden() -> void:
	var span := {"id": "particle:for_each:0#2", "fields": {"disabled": false}}
	_assert_true(not Timeline.is_hidden_spacer(span, ""),
		"a non-colour span (no spacer field) is never hidden")


func _span(id: String, spacer: bool, enabled: bool) -> Dictionary:
	return {"id": id, "fields": {"spacer": spacer, "enabled": enabled}}


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
