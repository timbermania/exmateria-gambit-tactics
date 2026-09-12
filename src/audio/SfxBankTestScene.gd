extends Control

## Test scene: audition every sound in FFT's global SFX banks (SYSTEM.SED /
## ENV.SED, exported by tools/parse_sfx_banks.py to assets/audio/sfx_banks/).
## These are the battle/system effects NOT tied to a visual effect file — the
## unit death cry (SYSTEM id 0x45), melee/physical hit noises, menu blips, etc.
##   Godot --path . res://assets/scenes/SfxBankTest.tscn
## Pick a bank, click a sound id to play it through the SFX path.

const BANKS_DIR := "res://assets/audio/sfx_banks"
const INDEX_PATH := BANKS_DIR + "/index.json"
const SfxCatalog = preload("res://src/audio/SfxCatalog.gd")

@onready var _bank_opt: OptionButton = $Margin/VBox/Controls/BankOption
@onready var _stop: Button = $Margin/VBox/Controls/StopButton
@onready var _now: Label = $Margin/VBox/NowPlaying
@onready var _list: ItemList = $Margin/VBox/SoundList

var _banks: Array = []          # [{name, feds, json, category, ...}]
var _sounds: Array = []         # sounds for the currently selected bank
var _sfx_token := 0


func _ready() -> void:
	# Auditions route through the one always-on ExMateriaEffectSfx (same as the game).
	var seed_opt := get_node_or_null("Margin/VBox/Controls/SeedOption")
	if seed_opt:
		seed_opt.visible = false  # seed A/B modes retired; synthetic seed is the engine default

	_load_index()
	_bank_opt.item_selected.connect(_on_bank_selected)
	_list.item_clicked.connect(_on_sound_clicked)
	_stop.pressed.connect(_on_stop)

	if not _banks.is_empty():
		_bank_opt.select(0)
		_on_bank_selected(0)
	_set_status("Stopped")


func _load_index() -> void:
	_banks.clear()
	_bank_opt.clear()
	if not FileAccess.file_exists(INDEX_PATH):
		_set_status("missing %s — run tools/parse_sfx_banks.py" % INDEX_PATH)
		return
	var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary and parsed.has("banks")):
		_set_status("bad index.json")
		return
	for b in parsed["banks"]:
		_banks.append(b)
		_bank_opt.add_item("%s  (cat 0x%04x, %d sounds)" % [
				b.get("name", "?"), int(b.get("category", 0)), int(b.get("num_sounds", 0))])


func _on_bank_selected(index: int) -> void:
	_list.clear()
	_sounds.clear()
	if index < 0 or index >= _banks.size():
		return
	var bank: Dictionary = _banks[index]
	var json_path := "%s/%s" % [BANKS_DIR, bank.get("json", "")]
	if not FileAccess.file_exists(json_path):
		_set_status("missing %s" % json_path)
		return
	var f := FileAccess.open(json_path, FileAccess.READ)
	var doc: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (doc is Dictionary and doc.has("sounds")):
		_set_status("bad %s" % json_path)
		return
	# The bank's index name ("system"/"env") is the SfxCatalog key, and each
	# sound's sound_id is its catalog slot — so the hand-authored {21}/{6B} label
	# joins straight onto the parsed bank row (see event_instructions_sound.md).
	var bank_key := str(bank.get("name", ""))
	for s in doc["sounds"]:
		_sounds.append(s)
		var sid := int(s.get("sound_id", 0))
		var name := SfxCatalog.name_for(bank_key, sid)
		var label_name := name if name != "" else str(s.get("note", "(unnamed)"))
		var loop_mark := "  (loop)" if SfxCatalog.is_loop(bank_key, sid) else ""
		var label := "0x%02X (%d)   %s%s" % [sid, sid, label_name, loop_mark]
		_list.add_item(label)
	if _sounds.is_empty():
		_list.add_item("(no sounds in bank)")


func _on_sound_clicked(index: int, _at: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if index < 0 or index >= _sounds.size():
		return
	_list.select(index)
	_play(index)


func _on_stop() -> void:
	ExMateriaEffectSfx.end_effect(_sfx_token)  # ring-out on the continuous SPU
	_sfx_token = 0
	_set_status("Stopped")


func _play(index: int) -> void:
	ExMateriaEffectSfx.end_effect(_sfx_token)
	_sfx_token = 0
	var bank_idx := _bank_opt.get_selected_id()
	if bank_idx < 0 or bank_idx >= _banks.size():
		return
	var bank: Dictionary = _banks[bank_idx]
	var feds_path := "%s/%s" % [BANKS_DIR, bank.get("feds", "")]
	var sound: Dictionary = _sounds[index]
	var sid := int(sound.get("sound_id", 0))
	# A bank's stride-2 offset table starts at +0x18, so FFT sound_id N maps to
	# FedsBank pair_idx N-1; pass the real sid for the chan+0x92 static seed.
	_sfx_token = ExMateriaEffectSfx.audition(feds_path, sid - 1, sid)
	var ok: bool = _sfx_token != 0
	var bank_key := str(bank.get("name", "?"))
	if ok:
		var name := SfxCatalog.name_for(bank_key, sid)
		var loop_mark := "  (loop)" if SfxCatalog.is_loop(bank_key, sid) else ""
		_set_status("%s  id 0x%02X (%d)  %s%s" % [
				bank_key, sid, sid, name if name != "" else str(sound.get("note", "")), loop_mark])
	else:
		_set_status("FAILED: %s id 0x%02X" % [bank_key, sid])


func _set_status(text: String) -> void:
	_now.text = text
