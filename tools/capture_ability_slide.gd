extends SceneTree

## Throwaway capture for the START-"Ability" sub-screen (§15.23, RE round 27) — the MIRROR of
## tools/capture_equip_slide.gd but choosing row 1 ("Ability") instead of row 0 ("Item"). Grabs the
## settled Ability screen so the port can be eyeballed against tmp/ss7_re/fb.png (the oracle).
##
## Run (NOT headless):
##   godot --path . -s res://tools/capture_ability_slide.gd -- --out=/tmp/ability_port

var _host: Node
var _out := "/tmp/ability_port"
var _pf := 0
var _state := 0
var _settle_wait := 0
var _quit := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--out="):
			_out = a.substr("--out=".length())
	_host = load("res://assets/scenes/FormationDetailTransition.tscn").instantiate()
	root.add_child(_host)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[ability-cap] booting host, out prefix -> %s" % _out)


func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _grab(tag: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s_%s.png" % [_out, tag]
	img.save_png(path)
	print("[ability-cap] grabbed %s -> %s" % [tag, path])


func _on_post_draw() -> void:
	_pf += 1
	var form = _host._formation
	match _state:
		0:  # let the host seed the roster
			if _pf > 12 and form != null and form.selected_character() != null:
				var ev := InputEventAction.new(); ev.action = "ui_accept"; ev.pressed = true
				form._unhandled_input(ev)
				_state = 1
		1:  # detail overlay opening; let its transition settle, then open the START menu
			if _pf > 40:
				_host.open_action_menu()
				_state = 2
		2:  # menu open; nav to row 1 = "Ability", confirm → Ability transition begins
			if _pf > 55:
				_host.action_menu().move_down()   # row 0 → row 1
				_host.action_menu().confirm()
				_state = 3
		3:  # step the slide by hand to completion
			if _host.is_equip_sliding():
				_host.equip_step()
			if not _host.is_equip_sliding():
				_settle_wait = 24
				_state = 4
		4:  # wait for the panel rebuild + menu box-open, then grab the settled screen
			_settle_wait -= 1
			if _settle_wait <= 0:
				_grab("final")
				_quit = true
