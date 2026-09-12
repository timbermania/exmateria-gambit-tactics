extends Node
## Regression guard (masonry layout): a debug panel hosted in a [DebugMasonryContainer]
## must never report a combined minimum WIDTH greater than the container's
## `max_column_width`. The masonry sizes every column to the widest visible cell,
## clamped into [min_column_width, max_column_width]; if a panel's own minimum exceeds
## that clamp, `fit_child_in_rect` still honours the panel's (larger) minimum and the
## panel BURSTS out of its column, overlapping the neighbour and "totally breaking" the
## layout. (Derivation: a burst happens iff some panel's min width > max_column_width —
## otherwise col_min >= that panel's min, so column_width >= its min and it fits.)
##
## This bit [NavigatorDebugPanel] when a ~113-char intro paragraph went through the
## non-wrapping [BaseDebugPanel.add_label], driving the panel's min width to ~800px.
## Each panel below is built exactly as the scenes build it (instantiate -> add to the
## live tree so fonts/theme resolve -> setup()) and measured against the REAL container
## bound, so a future too-wide panel fails here instead of on screen.
##
## Add any new masonry-hosted panel to PANEL_SCRIPTS.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/DebugPanelMasonryWidthTest.tscn

# The masonry panels the NavigatorMain / scenario dashboards host. Keyed by a display
# name; value is the panel script. Standalone-constructible (setup() only needs the
# ScenarioGroupDatabase autoload) — the property that lets this stay a pure guard.
const PANEL_SCRIPTS := {
	"NavigatorDebugPanel": "res://src/debug/NavigatorDebugPanel.gd",
	"ScenarioPathDebugPanel": "res://src/debug/ScenarioPathDebugPanel.gd",
	"StoryTimelineDebugPanel": "res://src/debug/StoryTimelineDebugPanel.gd",
}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()

	print("\n=== DebugPanelMasonryWidthTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] DebugPanelMasonryWidthTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] DebugPanelMasonryWidthTest")
		get_tree().quit(1)
	else:
		print("[PASS] DebugPanelMasonryWidthTest")
		get_tree().quit(0)


func _run() -> void:
	# Read the real bound off a live container rather than hardcoding 600, so the guard
	# tracks the container if that ceiling is ever retuned.
	var masonry := DebugMasonryContainer.new()
	var max_col_width: float = float(masonry.max_column_width)
	masonry.free()
	_true(max_col_width > 0.0, "masonry max_column_width is positive (%.0f)" % max_col_width)

	for panel_name in PANEL_SCRIPTS:
		await _check_panel_fits(panel_name, PANEL_SCRIPTS[panel_name], max_col_width)


func _check_panel_fits(panel_name: String, script_path: String, max_col_width: float) -> void:
	var panel = load(script_path).new()
	add_child(panel)          # into the live tree so labels get a font to measure against
	panel.setup()
	# Let the layout settle so nested combined minimum sizes resolve.
	await get_tree().process_frame
	await get_tree().process_frame

	var min_w: float = panel.get_combined_minimum_size().x
	_true(min_w > 0.0, "%s builds with a positive min width" % panel_name)
	if min_w <= max_col_width:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s min width %.0f > masonry max_column_width %.0f — would burst its column"
			% [panel_name, min_w, max_col_width])

	panel.queue_free()
	await get_tree().process_frame


func _true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)
