extends Control

## Test scene: lists every .SMD file in the game's music assets and plays the
## one you click, through the MusicPlayer autoload.
##   Godot --path . res://assets/scenes/SMDTest.tscn

const MUSIC_DIR := "res://assets/music"

@onready var _song_list: ItemList = $Margin/VBox/SongList
@onready var _now_playing: Label = $Margin/VBox/NowPlaying
@onready var _stop_button: Button = $Margin/VBox/Controls/StopButton

var _paths: Array[String] = []


func _ready() -> void:
	_populate()
	_song_list.item_clicked.connect(_on_item_clicked)
	_stop_button.pressed.connect(_on_stop)
	_set_status("Stopped")


func _populate() -> void:
	_paths.clear()
	_song_list.clear()
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		_song_list.add_item("(cannot open %s — run tools/sync_exmateria_sound.sh)" % MUSIC_DIR)
		return
	var names := dir.get_files()
	names.sort()
	for n in names:
		if not n.to_upper().ends_with(".SMD"):
			continue
		var path := "%s/%s" % [MUSIC_DIR, n]
		var title := _song_title(path)
		_song_list.add_item("%s  —  %s" % [n, title] if title != "" else n)
		_paths.append(path)
	if _paths.is_empty():
		_song_list.add_item("(no .SMD files found in %s)" % MUSIC_DIR)


func _song_title(path: String) -> String:
	var smd := ExMateriaSound.SMDParser.load_from_file(path)
	if smd == null:
		return ""
	return smd.song_title.strip_edges()


func _on_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if index < 0 or index >= _paths.size():
		return
	var path := _paths[index]
	if MusicPlayer.play_file(path):
		_set_status("Now playing: " + path.get_file())
	else:
		_set_status("FAILED to play: " + path.get_file())


func _on_stop() -> void:
	MusicPlayer.stop()
	_set_status("Stopped")


func _set_status(text: String) -> void:
	_now_playing.text = text
