class_name WorldMapDebugPanel
extends BaseDebugPanel

const TuneField = preload("res://src/debug/TuneField.gd")

## The world-map screen's knobs, in the SCENARIO tab of the F3 overlay.
##
## THIS PANEL EXISTS BECAUSE ADR-0051 SAYS IT MUST. The screen used to read `FIXTURE`,
## `ZOOM` and `SHOT` out of the process environment, which is the exact pattern that ADR
## bans -- invisible config, action at a distance from another shell. It also made
## `tests/run_all_tests.sh` abort at its `check_no_env_vars.py` pre-flight, so on trunk
## the whole suite ran zero tests (#444).
##
## A THIN VIEW, not a source of truth. `fixture`, `zoom` and `capture_path` are properties
## of [WorldMapScene] -- ADR-0051's "toggles persist as scene-level vars, not autoload
## globals" -- and this panel reads and writes them there.
##
## WHAT IS LIVE AND WHAT IS NOT, said out loud rather than implied by a control that
## looks live and is not:
##   - Capture IS live. It is the ADR's own named example ("the screenshot-capture env
##     vars want a 'Capture Viewport' button on a debug panel") and the button shoots
##     the current frame without taking the session down with it.
##   - Fixture and zoom are NOT. Both are read once in `WorldMapScene._ready()`, so they
##     apply to the next standalone boot; the durable place to change them is the
##     Inspector, since they are `@export`s. The panel says so on the label rather than
##     pretending otherwise.
##
## Category is `SCENARIO`, following [NavigatorDebugPanel] -- the navigator is what mounts
## this screen, and `GENERAL` is documented as a junk drawer to avoid. There is no
## `WORLD_MAP` category and adding one is the world-map line's call, not this fix's.

## The scene this panel is a view onto. Set by `WorldMapScene._register_debug_panel()`.
var _scene: Node = null

var _fixture_picker: OptionButton   # tune-exempt: a per-run capture-rig choice on the scene, not persisted state (ADR-0051)
var _zoom_spin: SpinBox            # tune-exempt: a per-run capture-rig choice on the scene, not persisted state (ADR-0051)
var _menu_picker: OptionButton     # tune-exempt: a per-run capture-rig choice on the scene, not persisted state (ADR-0051)
var _path_edit: LineEdit           # tune-exempt: a destination path, owned by the caller of capture_to()
var _status: Label

const FIXTURES: Array[String] = ["ss1", "ss2"]
## `WorldMapScene.boot_menu`. "" is the normal interactive boot; the last three render
## CONTACT SHEETS rather than one frame, which is why they are boot-time and cannot be a
## button (ADR-0051 dec. 5). The labels are the values — a rig passes them verbatim
## as `-- --menu=<value>`.
const BOOT_MENUS: Array[String] = ["", "1", "move", "townopen", "screenin", "town"]
const DEFAULT_SHOT_PATH := "/tmp/world_map.png"


## Bind before registering; the panel is useless without its subject.
func bind(scene: Node) -> void:
	_scene = scene


func setup() -> void:
	panel_title = "World map"
	panel_category = Category.SCENARIO
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	add_child(vbox)

	add_section_title(vbox, "Capture")
	add_label(vbox, "Writes the framebuffer at the current zoom. Stays in the session.")

	var path_row := HBoxContainer.new()
	vbox.add_child(path_row)
	add_label(path_row, "Path:", 50)
	_path_edit = LineEdit.new()  # tune-exempt: a filesystem destination for one capture, owned by the caller of capture_to()
	_path_edit.text = DEFAULT_SHOT_PATH
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(_path_edit)

	var shoot := Button.new()
	shoot.text = "Capture viewport"
	shoot.pressed.connect(_on_capture)
	vbox.add_child(shoot)

	_status = add_label(vbox, "")

	add_separator(vbox)

	add_section_title(vbox, "Transition")
	add_label(vbox, "Fade the map out when it hands off, instead of cutting.\nLIVE — it is read when the screen leaves, not at boot.")
	# A TuneField and not a CheckBox: ADR-0068 says a debug panel's value controls are built
	# through it (tools/check_debug_panel_tunables.py enforces exactly that), and the accent
	# label plus the pin gesture come for free. The default lives on WorldMapScreenOut --
	# the mechanism this switch turns off -- and NOT on WorldMapScene, which is ADR-0188's
	# third Decision: the scene is a declared root's assembler and `tools/check_root_set.py`
	# check 4 forbids anything CALLING one, so a row naming a member on the scene reds that
	# guard. This row is a view onto the owner named on the line below it.
	TuneField.add(vbox, "Fade out on leave", WorldMapScreenOut.SCREEN_OUT_SLUG,
		WorldMapScreenOut.SCREEN_OUT_DEFAULT)

	add_separator(vbox)

	add_section_title(vbox, "Boot settings (next standalone run)")
	add_label(vbox, "Read once in _ready(). For a durable change use the Inspector —\nall three are @export on WorldMapScene.")

	var fx_row := HBoxContainer.new()
	vbox.add_child(fx_row)
	add_label(fx_row, "Fixture:", 60)
	_fixture_picker = OptionButton.new()  # tune-exempt: see the declaration above
	for f in FIXTURES:
		_fixture_picker.add_item(f)
	_fixture_picker.item_selected.connect(_on_fixture_selected)
	fx_row.add_child(_fixture_picker)

	var z_row := HBoxContainer.new()
	vbox.add_child(z_row)
	add_label(z_row, "Zoom:", 60)
	_zoom_spin = SpinBox.new()  # tune-exempt: see the declaration above
	_zoom_spin.min_value = 1
	_zoom_spin.max_value = 8
	_zoom_spin.step = 1
	_zoom_spin.value_changed.connect(_on_zoom_changed)
	z_row.add_child(_zoom_spin)

	var m_row := HBoxContainer.new()
	vbox.add_child(m_row)
	add_label(m_row, "Open with:", 60)
	_menu_picker = OptionButton.new()  # tune-exempt: see the declaration above
	for m in BOOT_MENUS:
		_menu_picker.add_item("(none)" if m.is_empty() else m)
	_menu_picker.item_selected.connect(_on_boot_menu_selected)
	m_row.add_child(_menu_picker)

	_sync_from_scene()


## The panel can be opened long after the scene moved on, so re-read rather than trust
## whatever the last edit left in the controls.
func on_shown() -> void:
	_sync_from_scene()


func _sync_from_scene() -> void:
	if _scene == null:
		return
	var idx := FIXTURES.find(String(_scene.get("fixture")))
	if idx >= 0 and _fixture_picker != null:
		_fixture_picker.select(idx)
	if _zoom_spin != null:
		_zoom_spin.value = int(_scene.get("zoom"))
	var m := BOOT_MENUS.find(String(_scene.get("boot_menu")))
	if m >= 0 and _menu_picker != null:
		_menu_picker.select(m)


func _on_fixture_selected(index: int) -> void:
	if _scene != null and index >= 0 and index < FIXTURES.size():
		_scene.set("fixture", FIXTURES[index])


func _on_boot_menu_selected(index: int) -> void:
	if _scene != null and index >= 0 and index < BOOT_MENUS.size():
		_scene.set("boot_menu", BOOT_MENUS[index])


func _on_zoom_changed(value: float) -> void:
	if _scene != null:
		_scene.set("zoom", maxi(1, int(value)))


func _on_capture() -> void:
	if _scene == null or not _scene.has_method("capture_to"):
		_say("no world-map scene bound")
		return
	var path := _path_edit.text.strip_edges()
	if path.is_empty():
		_say("give it a path first")
		return
	# `false` = do not quit. The rig's default is to shoot and exit; a button inside a
	# live session must not.
	_scene.capture_to(path, false)
	_say("capturing -> %s" % path)


func _say(text: String) -> void:
	if _status != null:
		_status.text = text
	print("[world map panel] %s" % text)
