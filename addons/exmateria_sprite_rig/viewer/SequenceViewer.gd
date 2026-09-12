extends Node3D

## Standalone scene for testing all unit sequences.
## Displays sprite animations head-on with UI to browse and control playback
## across all 3 layers (type1, wep1, eff1).

# ADR-0212 dec. 1 — the class is INTERNAL to this addon: no global `class_name`,
# so an in-addon consumer preloads the file it wants.
const WeaponAnimationSelector = preload("res://addons/exmateria_sprite_rig/layers/WeaponAnimationSelector.gd")
const SpriteLayerManager = preload("res://addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd")
const UnitAnimationSet = preload("res://addons/exmateria_sprite_rig/sequence/UnitAnimationSet.gd")
const AnimationDatabase = preload("res://addons/exmateria_sprite_rig/sequence/AnimationDatabase.gd")
const AnimationPlayback = preload("res://addons/exmateria_sprite_rig/sequence/AnimationPlayback.gd")
const AnimationFrameCalculator = preload("res://addons/exmateria_sprite_rig/sequence/AnimationFrameCalculator.gd")
const AnimationNames = preload("res://addons/exmateria_sprite_rig/sequence/AnimationNames.gd")

## `AnimationOpcodes` is `addons/exmateria_sprite_rig`'s now, published on the
## addon's one global name; this aliases it back so every use site below keeps
## the spelling it had (ADR-0211 dec. 4, ADR-0217 dec. 6).
const ContentRoot = preload("res://addons/exmateria_sprite_rig/install/SpriteRigContentRoot.gd")
const AnimationOpcodes = ExMateriaSpriteRig.AnimationOpcodes

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const SpriteLayer = ExMateriaSchema.SpriteLayer.Kind

# Node references (set in _ready)
var sprite_mesh: MeshInstance3D
var layer_tabs: TabBar
var sequence_list: ItemList
var play_pause_button: Button
var step_back_button: Button
var step_forward_button: Button
var reset_button: Button
var frame_slider: HSlider
var speed_slider: HSlider
var info_label: Label
var show_weapon_check: CheckBox
var show_effect_check: CheckBox
var sprite_type_dropdown: OptionButton
var sprite_id_input: LineEdit
var load_sprite_button: Button
var weapon_type_dropdown: OptionButton
var weapon_graphic_spinbox: SpinBox
var offset_info_label: Label

# Animation components
var animation_set: UnitAnimationSet
var sprite_layers: SpriteLayerManager
var type1_playback: AnimationPlayback
var wep1_playback: AnimationPlayback
var eff1_playback: AnimationPlayback

# State
var current_layer: SpriteLayer = SpriteLayer.TYPE1
var current_seq_id: String = ""
var is_playing: bool = true
var playback_speed: float = 1.0
# Fixed-step delta accumulator. AnimationClock owns this for a game unit; the
# viewer keeps its own because it pumps only the layers the user toggled on and
# has no React set (ADR-0020 stripped the accumulator from AnimationPlayback).
var _viewer_accum: float = 0.0
var current_sprite_type: String = "type1"
var current_sprite_id: String = "01"

# Weapon offset state
var current_weapon_type_id: int = 0
var current_weapon_graphic: int = 0
var wep1_frame_offset: int = 0
var eff1_frame_offset: int = 0  # Current active EFF1 offset (changes based on trigger source)

# Ball item_type_id for TYPE1 → EFF1 direct triggers (thrown projectiles)
const BALL_ITEM_TYPE_ID: int = 33

# Layer values for tab indexing
const LAYERS: Array[SpriteLayer] = [SpriteLayer.TYPE1, SpriteLayer.WEP1, SpriteLayer.EFF1]

# Available sprite types
const SPRITE_TYPES: Array[String] = ["type1", "type2", "type3", "type4", "mon", "cyoko", "arute", "kanzen", "other"]

# Weapon type names and IDs for dropdown
const WEAPON_TYPES: Array[Dictionary] = [
	{"name": "Bare Fist", "id": 0},
	{"name": "Knife", "id": 1},
	{"name": "Ninja Blade", "id": 2},
	{"name": "Sword", "id": 3},
	{"name": "Knight Sword", "id": 4},
	{"name": "Katana", "id": 5},
	{"name": "Axe", "id": 6},
	{"name": "Rod", "id": 7},
	{"name": "Staff", "id": 8},
	{"name": "Flail", "id": 9},
	{"name": "Gun", "id": 10},
	{"name": "Crossbow", "id": 11},
	{"name": "Bow", "id": 12},
	{"name": "Instrument", "id": 13},
	{"name": "Book", "id": 14},
	{"name": "Polearm", "id": 15},
	{"name": "Pole", "id": 16},
	{"name": "Bag", "id": 17},
	{"name": "Cloth", "id": 18},
	{"name": "Shield", "id": 19},
	{"name": "Shuriken", "id": 32},
	{"name": "Ball", "id": 33},
	{"name": "Consumable", "id": 34},
]


## `false` until `_initialize_animation_system()` has built the layer manager and the
## three playbacks. It cannot, in a project whose host declares no
## `SpriteRigContentRoot.ROOT_SETTING`: `AnimationDatabase.get_set` resolves every SEQ/SHP
## path through the content root, the root refuses, and the set comes back empty.
##
## 🔴 FOUND BY `tests/stranger/exmateria_sprite_rig/` ON ITS FIRST RUN (ADR-0229). The
## refusal itself was already specified and already correct — `SpriteRigContentRoot.resolve()`
## pushes it once, in words that name the setting, and `_initialize_animation_system` pushed
## its own `Failed to load animation data` beside it. What was NOT specified is what the
## viewer does AFTERWARDS: that function bare-`return`ed at the empty check, leaving
## `sprite_layers` and the three `AnimationPlayback`s null, and `_ready` carried straight on
## into `_update_offset_info()` (`sprite_layers.wep1_v_offset_pixels` on Nil) while `_process`
## called `_get_active_playback().advance_frame()` on Nil EVERY FRAME, forever. Three throws
## on frame one and two more per frame after that.
##
## Nothing in the host could ever see it — `godot-learning/project.godot` always declares the
## root, so the empty branch is unreachable there. A stranger project is the only project that
## takes it, which is the entire argument for the rig. The gate below is one flag rather than
## a null-guard at each of the ~30 deref sites: the object is either fully wired or it does
## not drive at all, and "does not drive" is what the content-root contract already promises
## in words ("Until then no unit sprite will composite").
var _drivable: bool = false


func _ready() -> void:
	_setup_node_references()
	_initialize_animation_system()
	if not _drivable:
		_refuse_undrivable()
		return
	_connect_signals()
	_populate_sprite_type_dropdown()
	_populate_weapon_type_dropdown()
	_populate_sequence_list(SpriteLayer.TYPE1)
	_update_offset_info()

	# Auto-select first sequence
	if sequence_list.item_count > 0:
		sequence_list.select(0)
		_on_sequence_selected(0)


## The viewer's whole behaviour when its content is absent: say so where a user is looking,
## and STOP. `set_process(false)` is the load-bearing half — without it `_process` throws on
## Nil twice a frame for the life of the run, which is a crash report rather than a refusal.
## The node stays in the tree and stays valid; `tests/stranger/exmateria_sprite_rig/`'s arm
## asserts exactly that, because "came up and refused" and "came up and died" are the two
## outcomes goal #5 has to be able to tell apart.
func _refuse_undrivable() -> void:
	set_process(false)
	var why := ("No sprite content. This viewer needs a host to declare `%s` in project.godot, "
		% ContentRoot.ROOT_SETTING + "pointing at the directory holding its `%s` and `%s` trees. "
		% [ContentRoot.ANIMATIONS_SUBPATH, ContentRoot.TEXTURES_SUBPATH]
		+ "Nothing will composite until it does.")
	if info_label:
		info_label.text = why
	if offset_info_label:
		offset_info_label.text = "—"


func _setup_node_references() -> void:
	sprite_mesh = $SpriteMesh
	layer_tabs = $CanvasLayer/UI/LeftPanel/VBox/LayerTabs
	sequence_list = $CanvasLayer/UI/LeftPanel/VBox/SequenceList
	play_pause_button = $CanvasLayer/UI/RightPanel/VBox/PlaybackControls/PlayPauseButton
	step_back_button = $CanvasLayer/UI/RightPanel/VBox/PlaybackControls/StepBackButton
	step_forward_button = $CanvasLayer/UI/RightPanel/VBox/PlaybackControls/StepForwardButton
	reset_button = $CanvasLayer/UI/RightPanel/VBox/PlaybackControls/ResetButton
	frame_slider = $CanvasLayer/UI/RightPanel/VBox/FrameSlider
	speed_slider = $CanvasLayer/UI/RightPanel/VBox/SpeedSlider
	info_label = $CanvasLayer/UI/RightPanel/VBox/InfoLabel
	show_weapon_check = $CanvasLayer/UI/RightPanel/VBox/OptionsPanel/ShowWeaponCheck
	show_effect_check = $CanvasLayer/UI/RightPanel/VBox/OptionsPanel/ShowEffectCheck
	sprite_type_dropdown = $CanvasLayer/UI/LeftPanel/VBox/SpriteTypeDropdown
	sprite_id_input = $CanvasLayer/UI/LeftPanel/VBox/SpriteIDInput
	load_sprite_button = $CanvasLayer/UI/LeftPanel/VBox/LoadSpriteButton
	weapon_type_dropdown = $CanvasLayer/UI/RightPanel/VBox/OptionsPanel/WeaponTypeDropdown
	weapon_graphic_spinbox = $CanvasLayer/UI/RightPanel/VBox/OptionsPanel/WeaponGraphicSpinbox
	offset_info_label = $CanvasLayer/UI/RightPanel/VBox/OptionsPanel/OffsetInfoLabel


func _initialize_animation_system() -> void:
	# Resolve the animation set via the shared database
	animation_set = AnimationDatabase.get_set("TYPE1", "type1")
	if animation_set.type1_seq.is_empty():
		push_error("SequenceViewer: Failed to load animation data")
		return

	# Get shader material from mesh and duplicate it
	var quad_mesh = sprite_mesh.mesh as QuadMesh
	var material = quad_mesh.material.duplicate() as ShaderMaterial
	quad_mesh.material = material

	# Initialize sprite layer manager
	sprite_layers = SpriteLayerManager.new()
	sprite_layers.initialize(animation_set, material)

	# Create playback instances for all 3 layers
	type1_playback = AnimationPlayback.new()
	wep1_playback = AnimationPlayback.new()
	eff1_playback = AnimationPlayback.new()

	# Connect playback signals
	type1_playback.frame_changed.connect(_on_type1_frame_changed)
	type1_playback.side_effect.connect(_on_side_effect)
	type1_playback.animation_complete.connect(_on_animation_complete)

	wep1_playback.frame_changed.connect(_on_wep1_frame_changed)
	wep1_playback.side_effect.connect(_on_wep1_side_effect)
	wep1_playback.animation_complete.connect(_on_wep1_complete)

	eff1_playback.frame_changed.connect(_on_eff1_frame_changed)
	eff1_playback.animation_complete.connect(_on_eff1_complete)

	_drivable = true

	print("SequenceViewer: Animation system initialized")
	print("  type1 sequences: %d" % animation_set.type1_seq.size())
	print("  wep sequences: %d" % animation_set.wep_seq.size())
	print("  eff1 sequences: %d" % animation_set.eff1_seq.size())


func _connect_signals() -> void:
	layer_tabs.tab_changed.connect(_on_tab_changed)
	sequence_list.item_selected.connect(_on_sequence_selected)
	play_pause_button.pressed.connect(_on_play_pause)
	step_back_button.pressed.connect(_on_step_back)
	step_forward_button.pressed.connect(_on_step_forward)
	reset_button.pressed.connect(_on_reset)
	frame_slider.value_changed.connect(_on_frame_slider_changed)
	speed_slider.value_changed.connect(_on_speed_slider_changed)
	show_weapon_check.toggled.connect(_on_show_weapon_toggled)
	show_effect_check.toggled.connect(_on_show_effect_toggled)
	load_sprite_button.pressed.connect(_on_load_sprite_pressed)
	weapon_type_dropdown.item_selected.connect(_on_weapon_type_changed)
	weapon_graphic_spinbox.value_changed.connect(_on_weapon_graphic_changed)


func _process(delta: float) -> void:
	if not is_playing:
		return

	# Fixed-step advance (AnimationPlayback no longer self-accumulates). Step the
	# shown layer, plus the toggled secondaries when viewing the body layer.
	_viewer_accum += delta * playback_speed
	while _viewer_accum >= AnimationPlayback.FRAME_DURATION:
		_viewer_accum -= AnimationPlayback.FRAME_DURATION
		_get_active_playback().advance_frame()
		if current_layer == SpriteLayer.TYPE1:
			if show_weapon_check.button_pressed:
				wep1_playback.advance_frame()
			if show_effect_check.button_pressed:
				eff1_playback.advance_frame()

	_update_ui()


func _get_active_playback() -> AnimationPlayback:
	match current_layer:
		SpriteLayer.TYPE1: return type1_playback
		SpriteLayer.WEP1: return wep1_playback
		SpriteLayer.EFF1: return eff1_playback
		_: return type1_playback


func _get_sequences(layer: SpriteLayer) -> Dictionary:
	match layer:
		SpriteLayer.TYPE1: return animation_set.type1_seq
		SpriteLayer.WEP1: return animation_set.wep_seq
		SpriteLayer.EFF1: return animation_set.eff1_seq
		_: return {}


func _get_shp(layer: SpriteLayer) -> Dictionary:
	# SHP shape data is keyed by frame_id; each value is an array of part
	# rectangles. `wep_shp` is already TYPE2-resolved by the database.
	match layer:
		SpriteLayer.TYPE1: return animation_set.type1_shp
		SpriteLayer.WEP1: return animation_set.wep_shp
		SpriteLayer.EFF1: return animation_set.eff1_shp
		_: return {}


func _sprite_key_for(layer: SpriteLayer) -> String:
	# Keys into AnimationNames (`<content_root>/sprites/animation_names.json`):
	# body layer uses the live sprite_type (type1/mon/cyoko/…); weapon layer
	# uses wep1/wep2 per is_type2; effect layer uses eff1.
	match layer:
		SpriteLayer.TYPE1:
			return current_sprite_type
		SpriteLayer.WEP1:
			return "wep2" if (animation_set and animation_set.is_type2) else "wep1"
		SpriteLayer.EFF1:
			return "eff1"
		_:
			return ""


func _populate_sequence_list(layer: SpriteLayer) -> void:
	var sequences = _get_sequences(layer)
	var sprite_key := _sprite_key_for(layer)

	sequence_list.clear()
	# Skip meta keys (e.g. "_timings") whose values are not opcode arrays.
	var seq_ids: Array = sequences.keys().filter(func(k): return not String(k).begins_with("_"))
	seq_ids.sort_custom(func(a, b): return int(a) < int(b))

	for seq_id in seq_ids:
		var label := AnimationNames.get_label(sprite_key, int(seq_id))
		if label.is_empty():
			label = "Unknown"
		sequence_list.add_item("%s: %s" % [seq_id, label])
		sequence_list.set_item_metadata(sequence_list.item_count - 1, seq_id)


func _play_sequence(layer: SpriteLayer, seq_id: String) -> void:
	current_seq_id = seq_id
	var sequences = _get_sequences(layer)

	# Stop secondary layers when starting new animation
	if layer == SpriteLayer.TYPE1:
		wep1_playback.stop()
		eff1_playback.stop()
		sprite_layers.enable_layer(SpriteLayer.WEP1, false)
		sprite_layers.enable_layer(SpriteLayer.EFF1, false)

	# Start playback
	var playback = _get_active_playback()
	playback.start(seq_id, sequences)

	# Update slider max based on animation duration
	var duration = AnimationFrameCalculator.get_duration(seq_id, sequences)
	frame_slider.max_value = max(duration - 1, 0)
	frame_slider.value = 0

	# Load first frame immediately
	var frame_id = playback.get_current_frame()
	sprite_layers.load_frame_by_id(layer, frame_id, true)

	is_playing = true
	_update_play_button()
	_update_ui()


func _update_ui() -> void:
	if current_seq_id.is_empty():
		info_label.text = "No sequence selected"
		return

	var playback = _get_active_playback()
	var sequences = _get_sequences(current_layer)

	var sprite_key := _sprite_key_for(current_layer)
	var display_name := AnimationNames.get_label(sprite_key, int(current_seq_id))
	if display_name.is_empty():
		display_name = "Unknown"
	var loops = AnimationFrameCalculator.is_looping(current_seq_id, sequences)
	var duration = AnimationFrameCalculator.get_duration(current_seq_id, sequences)
	var duration_seconds = duration / UnitAnimationSet.ANIMATION_FRAMERATE

	# The SHP shape currently on screen: the frame_id the playback resolves
	# for this anim_frame, keyed into the layer's SHP data for a part count.
	var frame_id := playback.get_current_frame()
	var shp := _get_shp(current_layer)
	var shp_key := str(frame_id)
	var shp_status: String
	if shp.has(shp_key):
		var parts: Array = shp[shp_key]
		shp_status = "#%d (%d parts)" % [frame_id, parts.size()]
	else:
		shp_status = "#%d (missing)" % frame_id

	# Update frame slider without triggering signal
	frame_slider.set_value_no_signal(playback.anim_frame)

	info_label.text = """Layer: %s
Sequence: %s (%s)
Frame: %d / %d
SHP: %s
Duration: %.2fs @ 45fps
Loops: %s
Speed: %.1fx""" % [
		SpriteLayerManager.LAYER_NAMES[current_layer].to_upper(),
		current_seq_id,
		display_name,
		playback.anim_frame,
		duration,
		shp_status,
		duration_seconds,
		"Yes" if loops else "No",
		playback_speed
	]


func _update_play_button() -> void:
	play_pause_button.text = "Pause" if is_playing else "Play"


# Signal handlers

func _on_tab_changed(tab_index: int) -> void:
	current_layer = LAYERS[tab_index]
	_populate_sequence_list(current_layer)

	# Auto-select first sequence
	if sequence_list.item_count > 0:
		sequence_list.select(0)
		_on_sequence_selected(0)


func _on_sequence_selected(index: int) -> void:
	var seq_id = sequence_list.get_item_metadata(index)
	_play_sequence(current_layer, seq_id)


func _on_play_pause() -> void:
	is_playing = not is_playing
	_update_play_button()


func _on_step_back() -> void:
	is_playing = false
	_update_play_button()

	var playback = _get_active_playback()
	playback.anim_frame = max(0, playback.anim_frame - 1)

	var frame_id = playback.get_current_frame()
	sprite_layers.load_frame_by_id(current_layer, frame_id)
	_update_ui()


func _on_step_forward() -> void:
	is_playing = false
	_update_play_button()

	var playback = _get_active_playback()
	var sequences = _get_sequences(current_layer)
	var duration = AnimationFrameCalculator.get_duration(current_seq_id, sequences)
	playback.anim_frame = min(duration - 1, playback.anim_frame + 1)

	var frame_id = playback.get_current_frame()
	sprite_layers.load_frame_by_id(current_layer, frame_id)
	_update_ui()


func _on_reset() -> void:
	if current_seq_id.is_empty():
		return
	_play_sequence(current_layer, current_seq_id)


func _on_frame_slider_changed(value: float) -> void:
	is_playing = false
	_update_play_button()

	var playback = _get_active_playback()
	playback.anim_frame = int(value)

	var frame_id = playback.get_current_frame()
	sprite_layers.load_frame_by_id(current_layer, frame_id)
	_update_ui()


func _on_speed_slider_changed(value: float) -> void:
	playback_speed = value
	_update_ui()


func _on_show_weapon_toggled(enabled: bool) -> void:
	sprite_layers.enable_layer(SpriteLayer.WEP1, enabled)
	if not enabled:
		wep1_playback.stop()


func _on_show_effect_toggled(enabled: bool) -> void:
	sprite_layers.enable_layer(SpriteLayer.EFF1, enabled)
	if not enabled:
		eff1_playback.stop()


# Playback signal handlers

func _on_type1_frame_changed(frame_id: int) -> void:
	sprite_layers.load_frame_by_id(SpriteLayer.TYPE1, frame_id)


func _on_wep1_frame_changed(frame_id: int) -> void:
	var actual_frame = frame_id + wep1_frame_offset
	sprite_layers.load_frame_by_id(SpriteLayer.WEP1, actual_frame)


func _on_eff1_frame_changed(frame_id: int) -> void:
	var actual_frame = frame_id + eff1_frame_offset
	sprite_layers.load_frame_by_id(SpriteLayer.EFF1, actual_frame)


func _on_side_effect(effect_type: int, params: Dictionary) -> void:
	if effect_type == AnimationOpcodes.SideEffect.QUEUE_SPRITE_ANIM:
		var layer: SpriteLayer = params.get("layer", SpriteLayer.TYPE1)
		var anim_id = params.get("anim_id", "")

		if layer == SpriteLayer.WEP1 and show_weapon_check.button_pressed:
			wep1_playback.start(anim_id, animation_set.wep_seq)
			sprite_layers.enable_layer(SpriteLayer.WEP1, true)
			print("QueueSpriteAnim: wep1 -> %s" % anim_id)
		elif layer == SpriteLayer.EFF1 and show_effect_check.button_pressed:
			eff1_frame_offset = WeaponAnimationSelector.get_eff1_frame_offset(BALL_ITEM_TYPE_ID)
			eff1_playback.start(anim_id, animation_set.eff1_seq)
			sprite_layers.enable_layer(SpriteLayer.EFF1, true)
			print("QueueSpriteAnim: eff1 -> %s (Ball offset: %d)" % [anim_id, eff1_frame_offset])
	elif effect_type == AnimationOpcodes.SideEffect.SET_LAYER_PRIORITY:
		var priority_idx = params.get("priority", 0)
		var priority_array = animation_set.layer_priority.get(str(priority_idx), [0, 1, 2, 3])
		var material = (sprite_mesh.mesh as QuadMesh).material as ShaderMaterial
		material.set_shader_parameter("priority", priority_array)
		print("SetLayerPriority: %d -> %s" % [priority_idx, priority_array])


func _on_animation_complete() -> void:
	# For non-looping animations, pause at end
	is_playing = false
	_update_play_button()


func _on_wep1_side_effect(effect_type: int, params: Dictionary) -> void:
	if effect_type == AnimationOpcodes.SideEffect.QUEUE_SPRITE_ANIM:
		var layer: SpriteLayer = params.get("layer", SpriteLayer.TYPE1)
		var anim_id = params.get("anim_id", "")

		if layer == SpriteLayer.EFF1 and show_effect_check.button_pressed:
			# WEP1 → EFF1 uses the selected weapon's offset
			eff1_frame_offset = WeaponAnimationSelector.get_eff1_frame_offset(current_weapon_type_id)
			eff1_playback.start(anim_id, animation_set.eff1_seq)
			sprite_layers.enable_layer(SpriteLayer.EFF1, true)
			print("QueueSpriteAnim (from wep1): eff1 -> %s (offset: %d)" % [anim_id, eff1_frame_offset])


func _on_wep1_complete() -> void:
	sprite_layers.enable_layer(SpriteLayer.WEP1, false)


func _on_eff1_complete() -> void:
	sprite_layers.enable_layer(SpriteLayer.EFF1, false)


# Sprite type selection

func _populate_sprite_type_dropdown() -> void:
	sprite_type_dropdown.clear()
	for sprite_type in SPRITE_TYPES:
		sprite_type_dropdown.add_item(sprite_type.to_upper())


func _populate_weapon_type_dropdown() -> void:
	weapon_type_dropdown.clear()
	for weapon in WEAPON_TYPES:
		weapon_type_dropdown.add_item(weapon["name"])


func _on_weapon_type_changed(index: int) -> void:
	current_weapon_type_id = WEAPON_TYPES[index]["id"]
	_update_weapon_offsets()


func _on_weapon_graphic_changed(value: float) -> void:
	current_weapon_graphic = int(value)
	_update_weapon_offsets()


func _update_weapon_offsets() -> void:
	# Update frame offsets - use WEP2 offsets for TYPE2 sprites (different SHP frame boundaries)
	var uses_wep2 = animation_set.is_type2 if animation_set else false
	wep1_frame_offset = WeaponAnimationSelector.get_wep_frame_offset(current_weapon_type_id, uses_wep2)
	eff1_frame_offset = WeaponAnimationSelector.get_eff1_frame_offset(current_weapon_type_id)

	# Update WEP1 v_offset via SpriteLayerManager (this also loads the weapon texture)
	sprite_layers.load_weapon_texture(current_weapon_type_id, current_weapon_graphic)

	_update_offset_info()

	print("[SequenceViewer] Weapon offsets updated - type: %d, graphic: %d, WEP1: %d, EFF1: %d, v_offset: %d, wep2: %s" % [
		current_weapon_type_id, current_weapon_graphic, wep1_frame_offset, eff1_frame_offset,
		sprite_layers.wep1_v_offset_pixels, uses_wep2])


func _update_offset_info() -> void:
	offset_info_label.text = "WEP1 Frame: +%d  V-Offset: %dpx\nEFF1 Frame: +%d" % [
		wep1_frame_offset,
		sprite_layers.wep1_v_offset_pixels,
		eff1_frame_offset
	]


func _on_load_sprite_pressed() -> void:
	var sprite_type = SPRITE_TYPES[sprite_type_dropdown.selected]
	var sprite_id = sprite_id_input.text.strip_edges()

	print("[SequenceViewer] Load pressed - type: %s, id: '%s'" % [sprite_type, sprite_id])

	if sprite_id.is_empty():
		push_warning("[SequenceViewer] Sprite ID is empty")
		return

	# Load animation data for selected type
	animation_set = AnimationDatabase.get_set(sprite_type, sprite_type)
	if animation_set.type1_seq.is_empty():
		push_error("Failed to load animation data for %s" % sprite_type)
		return

	# Reinitialize sprite_layers with new SHP data
	var material = (sprite_mesh.mesh as QuadMesh).material as ShaderMaterial
	sprite_layers.initialize(animation_set, material)

	# Load texture for sprite ID
	var texture_path = ContentRoot.textures_dir() + "%s.tga" % sprite_id.to_upper()
	print("[SequenceViewer] Loading texture: %s" % texture_path)
	if not sprite_layers.load_sprite_texture(texture_path):
		push_error("Failed to load texture: %s" % texture_path)
		return

	# Update current state
	current_sprite_type = sprite_type
	current_sprite_id = sprite_id

	# Repopulate sequence list
	_populate_sequence_list(current_layer)

	# Auto-select first sequence
	if sequence_list.item_count > 0:
		sequence_list.select(0)
		_on_sequence_selected(0)

	print("[SequenceViewer] Loaded sprite type: %s, ID: %s" % [sprite_type, sprite_id])
