extends Node
# test-kind: logic
# seeded-break: drop the `catalog_id != "" and not is_panel_enabled(...)` refusal from
#   DebugOverlay.register_panel and replace `UniversalDebugPanels.mount(self)` in
#   ScenarioPlayerScene._register_debug_panels with `pass` — i.e. restore the state this
#   fixed. Measured: 10 of 16 assertions red (both OFF panels mount anyway; five ON panels
#   never appear; ARM 4 does not run because its subject is absent).
## The F3 Catalogue's on/off switches govern [NavigatorMain], not just the combat hosts.
##
## [b]The defect this pins.[/b] The catalogue's gate used to live inside
## `CombatPanelCatalog._wanted()` — one host-specific mount, called by the two scenes that
## `extends CombatHost` and by nothing else. `NavigatorMain extends ScenarioPlayerScene`,
## never reaches that mount, and hand-registered its panels through
## `DebugOverlay.register_panel` with NO catalogue id (repo-wide, 39 call sites passed one
## from a single file). So on this scene both directions of the switch were dead:
##
##   - switched OFF did nothing — the Skirts panel came up with `map` unchecked, because
##     nothing between `.new()` and the dashboard ever asked, and `set_panel_enabled(id,
##     false)` can only unregister a panel carrying a matching id;
##   - switched ON did nothing either — `simulation` is on by default and no code path on
##     this scene mounted it, so the box was ticked and the panel was never there.
##
## [b]Both arms are load-bearing and neither is sufficient.[/b] A change that suppressed
## the whole registration would pass the OFF arm alone; a change that mounted everything
## unconditionally would pass the ON arm alone. Only together do they say the switch is
## what decides.
##
## ARM 3 pins the id META, because that meta is the ONLY handle
## `DebugOverlay.set_panel_enabled` has to unregister a live panel — a mounted panel with
## no id is a checkbox that will silently no-op the moment someone unticks it, which is
## precisely the original bug in its unmounting direction.
##
## ARM 4 pins the REMOUNT HOOK. Turning an entry back on while standing on a scene has to
## rebuild it there and then; `CombatPanelCatalog.mount` installs that hook for a combat
## host, and until `ScenarioPlayerScene` installed one too, ticking a box on this scene
## only recorded a preference for the next boot.
##
## 🔴 THE SEED MUST NOT REACH `res://user_settings.json`, AND KEEPING IT OUT TAKES THREE
## THINGS, NOT ONE. That file is the developer's own live settings AND one file shared by
## all eight workers of the parallel suite, so a seed that lands in it fails somebody
## else's test: the first version of this test leaked `map` into `disabled_panels` and
## `MapDebugPanelMountTest` went red two hundred tests later, having registered 0 of its 2
## panels for a reason nothing in its own output could name.
##
##   1. Seed in MEMORY. `UserSettings.debug_window`'s getter hands back `_debug_window`
##      itself, so mutating it never calls `_write_to_file`. Going through
##      `DebugOverlay.set_panel_enabled` would, which is also why ARM 4 drives the remount
##      hook directly rather than through that setter.
##   2. SHUT THE WRITER. `_write_to_file` still happens behind your back:
##      `DebugDashboard`'s `size_changed` → `UserSettings.save_debug_window` persists the
##      WHOLE `debug_window` dict, seeded `disabled_panels` and all, on any WM resize of a
##      shown dashboard. `--iteration-debug` leaves `was_visible: true` in the file, so on
##      a developer's tree the dashboard comes up and that resize arrives. Forcing
##      `debug_overlay_visible = false` means no window, so no resize, so no writer.
##   3. RESTORE, BOTH WAYS. The in-memory list goes back the moment the seeded arms are
##      done — not at `_finish`, so the arms that follow cannot be read as depending on it
##      — and the file's original bytes are rewritten on the way out regardless.
##
## HEADFUL — run standalone:
##   godot --path . --quit-after 900 res://tests/NavigatorPanelCatalogGateTest.tscn

## Frames, not milliseconds: charter clause 14b — a test that is not a `perf` test must not
## read a wall clock, and the thing being waited for is a scene boot measured in frames
## anyway. Generous, because the wait ends the moment the panel appears.
const BOOT_FRAMES := 3600
const SEEK_ROOT := 7   # Military Academy — a linear group, the cheapest world to boot

## Switched OFF for this run. One from each mounting path, or the arm only proves the path
## it happens to cover: `perf` comes from the shared [UniversalDebugPanels] mount, `map`
## from `MapDebugPanels.register_map_panels` (two panels, one id), and `story_timeline`
## from `NavigatorMain`'s own hand-written registration.
const DISABLED := ["perf", "map", "story_timeline"]

## Left ON, and every one of them was absent from this scene before the fix — they had no
## mount here at all. `navigator` is the control: it was always mounted, so if it were the
## only ON assertion the arm would pass without the fix.
const ENABLED_CLASSES := {
	"SimulationDebugPanel": "simulation",
	"LoggingDebugPanel": "logging",
	"TilesDebugPanel": "tiles",
	"CursorDebugPanel": "cursor",
	"CameraFeelDebugPanel": "camera_feel",
	"NavigatorDebugPanel": "navigator",
}

const SETTINGS_PATH := "res://user_settings.json"

var _passed := 0
var _failed := 0
var _nav: Node = null
var _settings_backup := ""
var _disabled_backup: Array = []
var _overlay_visible_backup := false


func _ready() -> void:
	_settings_backup = FileAccess.get_file_as_string(SETTINGS_PATH)
	_disabled_backup = Array(UserSettings.debug_window.get("disabled_panels", [])).duplicate()
	# Step 2 above: no shown dashboard, so no WM resize, so nothing persists the seed.
	# Restored in `_finish` because the dashboard writes ONE more time on the way out and
	# `was_visible` is a preference of the developer's, not of this test's.
	_overlay_visible_backup = DebugConfig.debug_overlay_visible
	DebugConfig.debug_overlay_visible = false

	# Seed BEFORE the scene instantiates — the gate is read at mount time.
	UserSettings.debug_window["disabled_panels"] = DISABLED.duplicate()

	ScenarioDebugSession.navigator_start_root = SEEK_ROOT
	ScenarioDebugSession.navigator_stop_root = SEEK_ROOT
	ScenarioDebugSession.navigator_start_action = 0

	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	add_child(_nav)

	# Panels register inside `_boot_scenario_world`, i.e. only once the walk's first action
	# has booted a world — so wait for one to appear rather than sampling an empty overlay
	# and reading every "absent" assertion as a pass. This is the positive control for the
	# whole OFF arm: without it, a scene that registered NOTHING would score 3/3 on it.
	var waited := 0
	while _find("NavigatorDebugPanel") == null and waited < BOOT_FRAMES:
		await get_tree().process_frame
		waited += 1

	_true("the navigator booted and registered panels", _find("NavigatorDebugPanel") != null)
	if _find("NavigatorDebugPanel") == null:
		print("  (gave up after %d frames — nothing below could report)" % BOOT_FRAMES)
		_finish()
		return

	# ARM 1 — switched OFF means absent, on all three mounting paths.
	_true("`perf` off: PerfDebugPanel is not registered", _find("PerfDebugPanel") == null)
	_true("`map` off: SkirtDebugPanel is not registered", _find("SkirtDebugPanel") == null)
	_true("`map` off: MapRenderDebugPanel is not registered",
			_find("MapRenderDebugPanel") == null)
	_true("`story_timeline` off: StoryTimelineDebugPanel is not registered",
			_find("StoryTimelineDebugPanel") == null)
	for id: String in DISABLED:
		_true("`%s` off leaves no mounted-id claim behind" % id,
				not DebugOverlay.has_catalog_id(id))

	# ARM 2 — switched ON means present. Five of these six had no mount on this scene at
	# all before the gate moved to the seam; `navigator` is the one that always did.
	for ident: String in ENABLED_CLASSES:
		_true("`%s` on: %s is registered" % [ENABLED_CLASSES[ident], ident],
				_find(ident) != null)

	# ARM 3 — every mounted panel carries its id, or unticking its box is a silent no-op.
	for ident: String in ENABLED_CLASSES:
		var panel = _find(ident)
		if panel == null:
			continue
		var id: String = ENABLED_CLASSES[ident]
		_true("%s carries the `%s` catalogue id" % [ident, id],
				panel.has_meta(DebugOverlay.CATALOG_ID_META) \
					and String(panel.get_meta(DebugOverlay.CATALOG_ID_META)) == id)

	# The seeded arms are done. Put the switch set back NOW rather than at `_finish`, so
	# that if a write does slip through the remaining arms it writes the user's own list.
	UserSettings.debug_window["disabled_panels"] = _disabled_backup.duplicate()

	# ARM 4 — the remount hook this scene installed actually rebuilds. Driven directly
	# rather than through `set_panel_enabled`, which would write the settings file.
	var sim = _find("SimulationDebugPanel")
	if sim != null:
		DebugOverlay.unregister_panel(sim)
		_true("unregistering by id clears the mounted claim",
				_find("SimulationDebugPanel") == null \
					and not DebugOverlay.has_catalog_id("simulation"))
		_true("the scenario host installed a remount hook",
				DebugOverlay._catalog_remount.is_valid())
		if DebugOverlay._catalog_remount.is_valid():
			DebugOverlay._catalog_remount.call()
			_true("the remount rebuilt the entry on THIS scene",
					_find("SimulationDebugPanel") != null)
			# And rebuilt only what was missing — a remount that stacked a second copy of
			# everything is the failure idempotence exists to stop.
			_true("the remount did not stack a second Logging panel",
					_count("LoggingDebugPanel") == 1)

	# ARM 5 — the id space knows every id this scene actually mounted, or the Catalogue
	# page renders a window containing a panel it has no switch for.
	var unknown: Array = []
	for cat: int in DebugOverlay._panels.keys():
		for panel in DebugOverlay._panels[cat]:
			if is_instance_valid(panel) and panel.has_meta(DebugOverlay.CATALOG_ID_META):
				var id := String(panel.get_meta(DebugOverlay.CATALOG_ID_META))
				if not DebugPanelIds.IDS.has(id) and not unknown.has(id):
					unknown.append(id)
	_true("every mounted id is in DebugPanelIds (unknown: %s)" % str(unknown),
			unknown.is_empty())

	_finish()


## Put `user_settings.json` back byte for byte. Belt to the braces above: nothing in this
## test should have written it, and if something did, the developer's file still ends the
## run as it started. An empty backup means the file did not exist, and creating one here
## would itself be the change we are avoiding.
func _restore_settings() -> void:
	if _settings_backup == "":
		return
	if FileAccess.get_file_as_string(SETTINGS_PATH) == _settings_backup:
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(_settings_backup)
		f.close()
		print("  (restored %s — something persisted mid-run)" % SETTINGS_PATH)


## The registered panel of the named class, in ANY category — a category-scoped lookup
## would read "absent" for a panel that merely moved cells.
func _find(class_ident: String):
	for cat in DebugOverlay._panels.keys():
		for panel in DebugOverlay._panels[cat]:
			if is_instance_valid(panel) and panel.get_script() != null \
					and panel.get_script().get_global_name() == class_ident:
				return panel
	return null


func _count(class_ident: String) -> int:
	var n := 0
	for cat in DebugOverlay._panels.keys():
		for panel in DebugOverlay._panels[cat]:
			if is_instance_valid(panel) and panel.get_script() != null \
					and panel.get_script().get_global_name() == class_ident:
				n += 1
	return n


func _true(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  [ok] %s" % label)
	else:
		_failed += 1
		print("  [XX] %s" % label)


func _finish() -> void:
	DebugConfig.debug_overlay_visible = _overlay_visible_backup
	_restore_settings()
	print("\n=== NavigatorPanelCatalogGateTest: %d passed, %d failed ===" % [_passed, _failed])
	# Zero assertions is a FAIL, not a pass: every arm below the boot gate is an
	# absence check, and a scene that never booted would run none of them and report
	# nothing rather than reporting the reds it earned.
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorPanelCatalogGateTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorPanelCatalogGateTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorPanelCatalogGateTest")
		get_tree().quit(0)
