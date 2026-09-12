@tool
extends Node

## Per-machine UI state (not committed to git).
##
## Works in both runtime and editor (@tool) contexts via lazy loading.
## Loads from user_settings.json; falls back to defaults if the file is absent.
##
## Scope is deliberately limited to display-specific window state. Lighting is
## ROM-derived and validated against PCSX, so it is a version-controlled constant
## (unit.tres / the map manifest), NOT a per-machine override — a per-machine
## lighting knob would silently shadow the faithful values.
##
## Usage: UserSettings.debug_window.ui_scale

const SETTINGS_PATH = "res://user_settings.json"

const DEFAULT_DEBUG_WINDOW = {
	"position_x": 1300,              # OS-pixel x of the BIG debug window
	"position_y": 60,
	"size_x": 1200,                  # OS-pixel size of the BIG debug window
	"size_y": 900,
	"was_visible": false,            # Was it open when the game last quit?
	"ui_scale": 1.0,                 # Window.content_scale_factor for the dashboard
	"collapsed_categories": [],      # Category indices whose cell content is folded away
	"disabled_panels": []            # CombatPanelCatalog ids the user switched OFF
}

# Whole-game volume (0..1 linear). Applied to the Godot Master bus by ExMateriaAudioEngine, where
# music + SFX + UI re-sum. Per-machine, so it lives here — NOT the git-committed Tune
# staging file. 1.0 = unity (the historical default).
const DEFAULT_MASTER_VOLUME := 1.0

# Private backing fields
var _debug_window: Dictionary = DEFAULT_DEBUG_WINDOW.duplicate()
var _master_volume: float = DEFAULT_MASTER_VOLUME
var _settings_loaded: bool = false

# Public property with lazy loading (works in editor!)
var debug_window: Dictionary:
	get:
		_ensure_loaded()
		return _debug_window

# Whole-game linear volume 0..1 (see DEFAULT_MASTER_VOLUME). ExMateriaAudioEngine reads this at
# boot and delegates every live change back here via set_master_volume.
var master_volume: float:
	get:
		_ensure_loaded()
		return _master_volume

func _ready():
	_ensure_loaded()

func _ensure_loaded() -> void:
	"""Ensure settings are loaded (idempotent, safe to call multiple times)"""
	if _settings_loaded:
		return
	_settings_loaded = true
	_load_from_file()

func _load_from_file() -> void:
	"""Load settings from JSON file"""
	if not FileAccess.file_exists(SETTINGS_PATH):
		print("UserSettings: Creating user_settings.json with default values...")
		_write_to_file()
		return

	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		push_error("UserSettings: Failed to open " + SETTINGS_PATH)
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed:
		push_error("UserSettings: Failed to parse " + SETTINGS_PATH)
		return

	# Merge loaded values with defaults (preserves any missing keys)
	if parsed.has("debug_window"):
		var dw_settings = parsed.debug_window
		for key in dw_settings:
			if _debug_window.has(key):
				_debug_window[key] = dw_settings[key]

	if parsed.has("master_volume"):
		_master_volume = clampf(float(parsed.master_volume), 0.0, 1.0)


func save_debug_window(position: Vector2i, size: Vector2i, was_visible: bool, ui_scale: float = -1.0) -> void:
	"""Persist the BIG debug window's pos/size/open-state back to user_settings.json.
	ui_scale < 0 leaves the saved scale unchanged."""
	_ensure_loaded()
	_debug_window.position_x = position.x
	_debug_window.position_y = position.y
	_debug_window.size_x = size.x
	_debug_window.size_y = size.y
	_debug_window.was_visible = was_visible
	if ui_scale >= 0.0:
		_debug_window.ui_scale = ui_scale
	_write_to_file()


func set_category_collapsed(category: int, collapsed: bool) -> void:
	"""Persist a single debug-dashboard category cell's collapsed/expanded state.
	Stored as an array of collapsed category indices in debug_window."""
	_ensure_loaded()
	# Normalize to ints — JSON round-trips numbers back as floats.
	var arr: Array = []
	for v in _debug_window.get("collapsed_categories", []):
		arr.append(int(v))
	if collapsed:
		if not arr.has(category):
			arr.append(category)
	else:
		arr.erase(category)
	_debug_window.collapsed_categories = arr
	_write_to_file()


func set_panel_disabled(id: String, disabled: bool) -> void:
	"""Persist one CombatPanelCatalog entry's on/off state.

	Stores the DISABLED ids, never the enabled ones: a panel added to the catalogue later
	must default ON. Storing the enabled set would make every future panel invisible until
	someone found the checkbox, which is the exact complaint the catalogue page answers."""
	_ensure_loaded()
	var arr: Array = []
	for v in _debug_window.get("disabled_panels", []):
		arr.append(String(v))
	if disabled:
		if not arr.has(id):
			arr.append(id)
	else:
		arr.erase(id)
	_debug_window.disabled_panels = arr
	_write_to_file()


func set_master_volume(v: float, persist: bool = true) -> void:
	"""Store the whole-game volume (clamped 0..1). persist=false updates the in-memory
	value only (live slider drag); persist=true also writes user_settings.json."""
	_ensure_loaded()
	_master_volume = clampf(v, 0.0, 1.0)
	if persist:
		_write_to_file()


func _write_to_file() -> void:
	var config = {
		"debug_window": _debug_window.duplicate(),
		"master_volume": _master_volume,
	}
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if not file:
		push_error("UserSettings: Failed to write %s" % SETTINGS_PATH)
		return
	file.store_string(JSON.stringify(config, "\t"))
	file.close()
