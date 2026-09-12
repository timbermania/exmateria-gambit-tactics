extends Control

## Test scene: lists every effect that has a parsed FEDS section (feds.bin) and
## auditions the selected effect's sound pair through the one always-on
## ExMateriaEffectSfx (the same engine the game uses), or through the Music path.
##   Godot --path . res://assets/scenes/FEDSTest.tscn
## Click an effect to play pair 0; use the Pair spinner to audition other pairs.

const EFFECTS_DIR := "res://assets/effects"

enum PlayMode { SFX, MUSIC_PATH }

@onready var _list: ItemList = $Margin/VBox/EffectList
@onready var _now: Label = $Margin/VBox/NowPlaying
@onready var _pair_spin: SpinBox = $Margin/VBox/Controls/PairSpin
@onready var _stop: Button = $Margin/VBox/Controls/StopButton
@onready var _engine: OptionButton = $Margin/VBox/Controls/EngineOption

var _paths: Array[String] = []
var _names: Array[String] = []
var _suppress_pair_signal := false
var _sfx_token := 0


func _ready() -> void:
	_engine.add_item("SFX (continuous engine)", PlayMode.SFX)
	_engine.add_item("Music path (synthetic SMD)", PlayMode.MUSIC_PATH)

	_populate()
	_list.item_clicked.connect(_on_effect_clicked)
	_pair_spin.value_changed.connect(_on_pair_changed)
	_stop.pressed.connect(_on_stop)
	_set_status("Stopped")


func _populate() -> void:
	_paths.clear()
	_names.clear()
	_list.clear()
	var dir := DirAccess.open(EFFECTS_DIR)
	if dir == null:
		_list.add_item("(cannot open %s)" % EFFECTS_DIR)
		return
	var subs := dir.get_directories()
	subs.sort()
	for effect_name in subs:
		var feds := "%s/%s/feds.bin" % [EFFECTS_DIR, effect_name]
		if FileAccess.file_exists(feds):
			_list.add_item(effect_name)
			_paths.append(feds)
			_names.append(effect_name)
	if _paths.is_empty():
		_list.add_item("(no feds.bin found — run tools/parse_all_feds.py)")


func _pairs_for(path: String) -> int:
	var fb := ExMateriaSound.FedsBank.load_from_file(path)
	return fb.num_pairs if fb != null else 0


func _on_effect_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if index < 0 or index >= _paths.size():
		return
	_list.select(index)
	var pairs := _pairs_for(_paths[index])
	_suppress_pair_signal = true
	_pair_spin.max_value = maxi(0, pairs - 1)
	_pair_spin.value = clampi(int(_pair_spin.value), 0, int(_pair_spin.max_value))
	_suppress_pair_signal = false
	_play(index, int(_pair_spin.value), pairs)


func _on_pair_changed(value: float) -> void:
	if _suppress_pair_signal:
		return
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var idx: int = sel[0]
	_play(idx, int(value), _pairs_for(_paths[idx]))


func _on_stop() -> void:
	MusicPlayer.stop()
	ExMateriaEffectSfx.end_effect(_sfx_token)  # ring-out; tail decays on the SPU clock
	_sfx_token = 0
	_set_status("Stopped")


func _play(index: int, pair: int, pairs: int) -> void:
	var path := _paths[index]
	var mode: int = _engine.get_selected_id()
	# End the previous audition; the other engine too.
	MusicPlayer.stop()
	ExMateriaEffectSfx.end_effect(_sfx_token)
	_sfx_token = 0
	var ok := false
	var label := ""
	match mode:
		PlayMode.SFX:
			_sfx_token = ExMateriaEffectSfx.audition(path, pair)
			ok = _sfx_token != 0
			label = "SFX"
		PlayMode.MUSIC_PATH:
			ok = MusicPlayer.play_feds(path, pair)
			label = "music-path"
	if ok:
		_set_status("%s — pair %d (of %d)  [%s]" % [_names[index], pair, pairs, label])
	else:
		_set_status("FAILED: %s pair %d  [%s]" % [_names[index], pair, label])


func _set_status(text: String) -> void:
	_now.text = text
