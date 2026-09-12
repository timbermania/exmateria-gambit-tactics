extends Node3D

## TDD guard for threading the resolved template folder to the LIVE portrait UI
## call sites (ADR-0072, issue #205).
##
## #203 built the folder read surface (`UIPortrait.display_from_template`), but the
## in-game callers still passed a bare `sprite_id`, so portraits rendered from the
## flat sprite sheet. This guards that the two self-contained menu/battle callers
## now front the flat store with a unit's OWNED `portrait.tga` when it has one:
##   - `UIRosterBar.set_frame_sprite_id` — reads `template_folder` off the frame's
##     bound unit and drives `display_from_template`.
##   - `UIUnitInfoWindow._apply_view` — forwards the view's `template_folder`
##     (threaded through `view_from_unit` + `UnitInfoPresenter`).
## The flat fallback stays load-bearing: a unit with no folder renders from the
## sheet exactly as before.
##
## The observable is the portrait's `portrait_region` shader parameter:
##   - template mode -> Vector4(0, 0, 48, 32)   (the OWNED 48x32 crop)
##   - flat sheet    -> Vector4(80, 456, 48, 32) (a window into the 256x488 sheet)
##
## Uses the real emitted unique folder (ramza_3) — run the #201 transform +
## `godot --path . --import` first if `assets/characters/templates/` is absent.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/PortraitCallSiteRoutingTest.tscn

const TEMPLATE_FOLDER := "res://assets/characters/templates/ramza_3/"
const FALLBACK_SPRITE_ID := 1  # -> 01.tga in the flat store
const TEMPLATE_REGION := Vector4(0, 0, 48, 32)
const FLAT_REGION := Vector4(80, 456, 48, 32)

var _failed: int = 0
var _passed: int = 0


## A minimal stand-in for a spawned Unit: the call sites only read `template_folder`
## (and `body_sprite_id` for the vitals view path). No `stats_changed` signal so the
## roster bar's bind is a no-op beyond storing the reference.
class FakeUnit extends Node:
	var template_folder := ""
	var body_sprite_id := FALLBACK_SPRITE_ID


func _ready() -> void:
	await _test_roster_bar_fronts_folder_over_sprite_id()
	await _test_roster_bar_falls_back_to_flat_without_folder()
	await _test_info_window_fronts_folder_from_view()

	print("\n=== PortraitCallSiteRoutingTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] PortraitCallSiteRoutingTest")
		get_tree().quit(1)
	else:
		print("[PASS] PortraitCallSiteRoutingTest")
		get_tree().quit(0)


# --- UIRosterBar.set_frame_sprite_id -------------------------------------------

func _test_roster_bar_fronts_folder_over_sprite_id() -> void:
	var bar := UIRosterBar.new()
	add_child(bar)
	bar.frame_count = 1
	await get_tree().process_frame

	var unit := FakeUnit.new()
	unit.template_folder = TEMPLATE_FOLDER
	bar.set_frame_unit(0, unit)
	bar.set_frame_sprite_id(0, FALLBACK_SPRITE_ID)
	await get_tree().process_frame

	var region = _frame_portrait_region(bar, 0)
	_assert_eq(region, TEMPLATE_REGION,
		"roster bar fronts the flat sheet with the bound unit's OWNED portrait crop")
	bar.queue_free()


func _test_roster_bar_falls_back_to_flat_without_folder() -> void:
	var bar := UIRosterBar.new()
	add_child(bar)
	bar.frame_count = 1
	await get_tree().process_frame

	var unit := FakeUnit.new()  # template_folder == "" -> flat path load-bearing
	bar.set_frame_unit(0, unit)
	bar.set_frame_sprite_id(0, FALLBACK_SPRITE_ID)
	await get_tree().process_frame

	var region = _frame_portrait_region(bar, 0)
	_assert_eq(region, FLAT_REGION,
		"a unit with no template folder still renders from the flat sprite sheet")
	bar.queue_free()


# --- UIUnitInfoWindow._apply_view ----------------------------------------------

func _test_info_window_fronts_folder_from_view() -> void:
	var win := UIUnitInfoWindow.new()
	add_child(win)
	await get_tree().process_frame

	win.set_unit_view({
		"name": "Ramza", "sprite_id": FALLBACK_SPRITE_ID,
		"template_folder": TEMPLATE_FOLDER,
		"current_hp": 80, "max_hp": 100,
	})
	await get_tree().process_frame

	var portrait := _window_portrait(win)
	_assert(portrait != null, "info window built a portrait")
	if portrait:
		_assert_eq(portrait._material.get_shader_parameter("portrait_region"),
			TEMPLATE_REGION,
			"info window fronts the flat sheet with the view's OWNED portrait crop")
	win.queue_free()


# --- helpers -------------------------------------------------------------------

func _frame_portrait_region(bar: UIRosterBar, index: int):
	var frame: UIPortraitFrame = bar._frames[index]
	var portrait: UIPortrait = frame._portrait
	return portrait._material.get_shader_parameter("portrait_region")


func _window_portrait(win: UIUnitInfoWindow) -> UIPortrait:
	var frame: UIPortraitFrame = win._portrait_frame
	return frame._portrait if frame else null


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)


func _assert_eq(a, b, msg: String) -> void:
	if a == b:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s (got %s, expected %s)" % [msg, str(a), str(b)])
