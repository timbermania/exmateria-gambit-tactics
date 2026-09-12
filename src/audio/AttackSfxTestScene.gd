extends Control

## Test scene: audition the basic-melee attack SFX the way the game derives it.
## You click a WEAPON FAMILY (by its graphic id) and hear what it resolves to —
## swing / hit / block — through AttackSfxResolver (weapon graphic -> sound_class
## -> slugs). This is the FFT-faithful model, proven live in PCSX: the basic
## attack sound follows the EQUIPPED WEAPON's `graphic`, not the unit's sprite.
##   Godot --path . res://assets/scenes/AttackSfxTest.tscn
##
## So a Knife and a Dagger (same family) play the same sound; an Archer holding a
## sword would slash, not twang. Rows are grouped by graphic; each shows its
## weapon family + an example weapon + the resolved sound class.

const AttackSfxResolver = preload("res://src/audio/AttackSfxResolver.gd")
const ItemDatabaseClass = ExMateriaAlmanac.ItemDatabase

@onready var _now: Label = $Margin/VBox/NowPlaying
@onready var _detail: Label = $Margin/VBox/Detail
@onready var _list: ItemList = $Margin/VBox/UnitList
@onready var _swing_btn: Button = $Margin/VBox/Controls/SwingButton
@onready var _hit_btn: Button = $Margin/VBox/Controls/HitButton
@onready var _block_btn: Button = $Margin/VBox/Controls/BlockButton
@onready var _stop_btn: Button = $Margin/VBox/Controls/StopButton

var _rows: Array = []        # row index -> {graphic, label}
var _selected: int = -1      # currently selected weapon graphic
var _sfx_token: int = 0


func _ready() -> void:
	_populate()
	_list.item_selected.connect(_on_row_selected)
	_list.item_clicked.connect(_on_row_clicked)
	_swing_btn.pressed.connect(func(): _play("swing"))
	_hit_btn.pressed.connect(func(): _play("hit"))
	_block_btn.pressed.connect(func(): _play("block"))
	_stop_btn.pressed.connect(_on_stop)
	if not _rows.is_empty():
		_list.select(0)
		_on_row_selected(0)
	_set_status("Stopped")


func _populate() -> void:
	_list.clear()
	_rows.clear()
	# graphic -> {family, example}; graphic 0 is unarmed/fists (no weapon item).
	var by_graphic: Dictionary = {0: {"family": "Unarmed", "example": "fists"}}
	for item in ItemDatabaseClass.get_weapons():
		var g: int = int(item.get("graphic", 0))
		if not by_graphic.has(g):
			by_graphic[g] = {"family": str(item.get("item_type", "?")), "example": str(item.get("name", ""))}
	var graphics: Array = by_graphic.keys()
	graphics.sort()
	for g in graphics:
		var info: Dictionary = by_graphic[g]
		var cls := AttackSfxResolver.sound_class_for_weapon(g)
		_rows.append(g)
		_list.add_item("0x%02X  %-12s class %2d   (%s)" % [g, info["family"], cls, info["example"]])


func _on_row_clicked(index: int, _at: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	_on_row_selected(index)
	_play("swing")  # clicking a weapon auditions its swing


func _on_row_selected(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_selected = _rows[index]
	var s: Dictionary = AttackSfxResolver.attack_sounds_for_weapon(_selected)
	_detail.text = "swing: %s    hit: %s    block: %s" % [
		_slug_label(s.get("swing", "")), _slug_label(s.get("hit", "")), _slug_label(s.get("block", ""))]


func _slug_label(slug: String) -> String:
	return slug if slug != "" else "(silent)"


func _play(kind: String) -> void:
	if _selected < 0:
		return
	_stop_current()
	var slug: String = AttackSfxResolver.attack_sounds_for_weapon(_selected).get(kind, "")
	if slug == "":
		_set_status("graphic 0x%02X  %s: (silent)" % [_selected, kind])
		return
	_sfx_token = SfxRouter.play_system(slug)
	if _sfx_token != 0:
		_set_status("graphic 0x%02X  %s -> %s" % [_selected, kind, slug])
	else:
		_set_status("FAILED: graphic 0x%02X  %s -> %s" % [_selected, kind, slug])


func _on_stop() -> void:
	_stop_current()
	_set_status("Stopped")


func _stop_current() -> void:
	if _sfx_token != 0:
		ExMateriaEffectSfx.end_effect(_sfx_token)  # ring-out on the continuous SPU
		_sfx_token = 0


func _set_status(text: String) -> void:
	_now.text = text
