class_name StateDebugPanel
extends BaseDebugPanel
## F3 "State" panel — the live STATE census, ONE ROW PER MECHANISM (ADR-0177 Amendment 3).
##
## [b]The value is the rows DISAGREEING.[/b] ADR-0177 decision 1's finding is that the states
## which may accept input live at four levels that do not know about each other, and
## Amendment 3 records what that cost: four player-visible bugs on Orbonne (2026-09-08) found
## at the keyboard while 745 of 757 tests were green. A panel showing only [method
## Focus.describe] would have read `game: (nobody)` through all four of them — the focus stack
## is the mechanism that was never told, so it is the one row that cannot report the defect.
##
## So every row is read WHERE ITS MECHANISM KEEPS IT, and deliberately not derived from any
## other row:
##
## [codeblock]
## runner    NavigatorRunner.current_state       host seam
## focus     Focus.describe()                    the autoload, both channels
## camera    camera_mode + free_camera()         the PlayerCamera node, found in the tree
## combat    combat_active / pre_battle / survey host seam (three separate flags)
## director  state + taker + commandable count   host seam
## clocks    n SELF / n SCENARIO / n COMBAT      the "units" group, counted here
## cursor    rig alive? + input_enabled          the CursorRig node, found in the tree
## screen    FormationMapScreen mounted?         the node, found in the tree
## [/codeblock]
##
## FIVE of those eight never ask the host — three are found in the live tree by node name and
## one is counted off the `units` group. That is the point: a host that believes it freed the
## cursor, with a `CursorRig` still standing under it, is exactly the first Orbonne report, and
## a panel that asked the host would have agreed with the host. The remaining three go through
## [code]debug_battle_state()[/code], duck-typed — a scene without one still shows the five.
##
## [b]READ-ONLY.[/b] No control on this panel writes anything. It is the instrument ADR-0177
## Amendment 3 requires be built BEFORE the battlefield's focus-mode conversion, and an
## instrument that can move the thing it measures is not one.
##
## Registered by [DebugOverlay] itself rather than by a host, so it is present in EVERY scene:
## the census is most useful exactly where nobody thought to wire a panel.

## Row order is fixed and is the reading order — the disagreements this panel exists to show
## are between ADJACENT rows (focus vs. cursor, combat vs. clocks), so shuffling it costs
## legibility. `key` is the lookup into `_rows`; `label` is what the reader sees.
const _ROWS: Array[Dictionary] = [
	{"key": "runner", "label": "runner"},
	{"key": "focus", "label": "focus"},
	{"key": "camera", "label": "camera"},
	{"key": "combat", "label": "combat"},
	{"key": "director", "label": "director"},
	{"key": "clocks", "label": "clocks"},
	{"key": "cursor", "label": "cursor"},
	{"key": "screen", "label": "screen"},
]

## Node names the tree is searched for. They are set by the mounts that build them
## (`CursorRig.mount` names the rig, `FormationDetailTransition.mount_over_map` names the
## screen), so a rename over there silently blinds a row here — which is why each row prints
## "(none)" rather than an empty string: an absent row and a missing name must not look alike.
const _CURSOR_RIG_NODE := "CursorRig"
const _FORMATION_SCREEN_NODE := "FormationMapScreen"
const _PLAYER_CAMERA_NODE := "PlayerCamera"

## Repaint every Nth frame. A poll rather than an edge because there is no one signal to hang
## this on — that is the whole premise (eight mechanisms, no shared transition) — and three of
## the eight rows are `find_child` walks of a live battlefield. Frames, never wall-clock.
const _REFRESH_EVERY_FRAMES := 6

var _rows: Dictionary = {}
## The last census printed under `--state-census`, so only CHANGES reach stdout. A poll that
## printed every tick would bury the one transition a reader is looking for.
var _last_logged: Dictionary = {}
## Starts AT the threshold so the first `_process` after the panel becomes visible paints
## immediately rather than showing six frames of placeholder.
var _frames_since_refresh: int = _REFRESH_EVERY_FRAMES


func setup() -> void:
	panel_title = "State"
	panel_category = Category.STATE
	# `--state-census` routes this instrument's output to STDOUT, and stdout is not something
	# `is_visible_in_tree()` can speak for — the reader is the RUN LOG, and the F3 window is
	# very often closed in exactly the sessions worth logging. This is the second legitimate
	# use of `BaseDebugPanel`'s opt-out and it is the same argument the first one makes: the
	# work is not the on-screen reader's, so it must not stop when they look away.
	processes_while_hidden = DebugConfig.state_census_enabled
	_build_ui()


func _build_ui() -> void:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(360, 0)
	add_child(vb)

	var sec := create_collapsible_section(vb, "ONE ROW PER MECHANISM")
	for row in _ROWS:
		var line := HBoxContainer.new()
		sec.add_child(line)
		var name_label := Label.new()
		name_label.text = String(row["label"])
		name_label.custom_minimum_size.x = 70
		line.add_child(name_label)
		var value := Label.new()
		value.text = "—"
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(value)
		_rows[String(row["key"])] = value

	add_separator(vb)
	add_print_values_button(vb, "Print census")
	# NOT a first paint here. Every panel is built by `new()` + `setup()` BEFORE
	# `register_panel` puts it in a tree (`BaseDebugPanel`'s process-gate note says the same
	# about `set_process`), and `census_lines` walks `get_tree()` — which is null out of tree
	# and reports it as an engine error, once per row, on every boot.


func _process(_delta: float) -> void:
	_frames_since_refresh += 1
	if _frames_since_refresh < _REFRESH_EVERY_FRAMES:
		return
	_frames_since_refresh = 0
	_refresh()


func _refresh() -> void:
	var census := census_lines()
	for key in _rows.keys():
		var label: Label = _rows[key]
		label.text = String(census.get(key, "—"))
	if DebugConfig.state_census_enabled:
		_log_changes(census)


## Print each row that MOVED since the last poll, one line per row, `[state]`-tagged. Row
## granularity and not whole-census granularity on purpose: eight rows reprinted because one
## of them changed is how a log stops being read.
func _log_changes(census: Dictionary) -> void:
	for row in _ROWS:
		var key := String(row["key"])
		var line := String(census.get(key, "—"))
		if _last_logged.get(key, "") == line:
			continue
		_last_logged[key] = line
		print("[state] %-9s %s" % [String(row["label"]), line])


## The whole census as `key -> one line of text`.
##
## PUBLIC and pure-ish (it reads the live tree and writes nothing), so a test can assert what
## the reader would be told without owning an F3 window — the same shape
## `NavigatorMain.stop_badge_text` uses for the badge.
func census_lines() -> Dictionary:
	var host := _battle_host()
	var state: Dictionary = host.call("debug_battle_state") if host != null else {}
	# An EMPTY stack is the reading that matters here — it is what the navigator's battlefield
	# reports today — and `describe()` renders no channel at all when nothing has ever pushed
	# one, which would print as a blank row. Say it out loud instead.
	var focus_line := Focus.describe()
	return {
		"runner": _runner_line(state),
		"focus": focus_line if not focus_line.is_empty() else "(no channel pushed)",
		"camera": _camera_line(),
		"combat": _combat_line(state),
		"director": _director_line(state),
		"clocks": _clock_line(),
		"cursor": _cursor_line(),
		"screen": _screen_line(),
	}


## The current scene when it carries the read seam, else null. Deliberately NOT a tree search:
## a scene that does not answer `debug_battle_state` has no battle state to report, and
## inventing a host by walking for one would make "which host am I looking at" a guess.
func _battle_host() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null or not is_instance_valid(scene):
		return null
	return scene if scene.has_method("debug_battle_state") else null


func _runner_line(state: Dictionary) -> String:
	if not state.has("runner_state"):
		return "— (no host seam)"
	# -1 is `NavigatorRunner`'s own pre-first-transition value AND what the seam reports for
	# "there is no runner", which are two different facts. The seam distinguishes them.
	if not bool(state.get("has_runner", false)):
		return "— (no runner)"
	return "%s (%s)" % [
		String(state.get("runner_state_name", "?")), String(state.get("host", "?"))]


func _camera_line() -> String:
	var cam := _find_in_scene(_PLAYER_CAMERA_NODE)
	if cam == null:
		return "(none)"
	var mode := "?"
	if "camera_mode" in cam:
		mode = "TAKEOVER" if cam.camera_mode != cam.CameraMode.CURSOR else "CURSOR"
	# `free_camera()` is the third term in `TileCursor._input_allowed` and is STATIC on the
	# camera script — a global free-pan, not this node's state. Shown beside the mode because
	# a cursor that will not walk is explained by either.
	var free := str(cam.free_camera()) if cam.has_method("free_camera") else "?"
	return "mode=%s free_camera=%s" % [mode, free]


func _combat_line(state: Dictionary) -> String:
	if not state.has("combat_active"):
		return "— (no host seam)"
	return "combat_active=%s pre_battle=%s survey_frozen=%s" % [
		_fmt(state.get("combat_active")),
		_fmt(state.get("pre_battle_active")),
		_fmt(state.get("survey_frozen")),
	]


func _director_line(state: Dictionary) -> String:
	if not state.has("director_state"):
		return "— (no host seam)"
	if state["director_state"] == null:
		return "(not mounted)"
	return "%s taker=%s stops=%s commandable=%d/%d" % [
		String(state.get("director_state_name", "?")),
		_fmt(state.get("director_taker")),
		_fmt(state.get("director_stops")),
		int(state.get("commandable_count", 0)),
		int(state.get("cast_size", 0)),
	]


## A seam value as one word, with `null` — "this mechanism is not standing right now" — kept
## distinct from `false`. `str(null)` renders "<null>", which reads like a bug in the panel.
func _fmt(value) -> String:
	return "—" if value == null else str(value)


## The clock-owner census, counted off the `units` group rather than asked of any host — the
## ADR-0083 Amendment 1 defect is precisely a survivor left `COMBAT`-owned with no `CombatLoop`
## to tick it, and the host that lost the loop is the last thing that could report it.
func _clock_line() -> String:
	var tree := get_tree()
	if tree == null:
		return "(no tree)"
	var counts := [0, 0, 0]
	var total := 0
	for unit in tree.get_nodes_in_group("units"):
		if unit == null or not is_instance_valid(unit) or not ("clock_owner" in unit):
			continue
		total += 1
		var owner_kind := int(unit.clock_owner)
		if owner_kind >= 0 and owner_kind < counts.size():
			counts[owner_kind] += 1
	if total == 0:
		return "(no units)"
	return "%d SELF / %d SCENARIO / %d COMBAT  (%d unit(s))" % [
		counts[0], counts[1], counts[2], total]


func _cursor_line() -> String:
	var rig := _find_in_scene(_CURSOR_RIG_NODE)
	if rig == null:
		return "(none)"
	var enabled := str(rig.input_enabled) if "input_enabled" in rig else "?"
	return "alive  input_enabled=%s  at %s" % [
		enabled, str(rig.grid_pos) if "grid_pos" in rig else "?"]


func _screen_line() -> String:
	return "(none)" if _find_in_scene(_FORMATION_SCREEN_NODE) == null else "MOUNTED"


## The named node anywhere under the current scene, or null. `owned = false` because every one
## of these is built at runtime by a `mount()` and so is owned by nobody.
func _find_in_scene(node_name: String) -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null or not is_instance_valid(tree.current_scene):
		return null
	return tree.current_scene.find_child(node_name, true, false)


func _on_print_values() -> void:
	print("")
	print("=".repeat(60))
	print("# STATE census (ADR-0177 Am. 3) — one row per mechanism")
	print("=".repeat(60))
	var census := census_lines()
	for row in _ROWS:
		print("%-9s %s" % [String(row["label"]), String(census.get(String(row["key"]), "—"))])
	print("=".repeat(60))
	print("")
