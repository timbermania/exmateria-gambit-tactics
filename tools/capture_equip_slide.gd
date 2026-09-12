extends SceneTree

## Throwaway capture for the Formation Item→Equip slide (§15.23, RE round 22). Boots the
## real FormationDetailTransition host (fold active, added to root), ○-presses a unit to
## open the Status overlay, opens the START menu, chooses "Item" to start the Equip
## transition, then steps the slide by hand grabbing a PNG at a set of frames so the port
## can be eyeballed against tmp/equip_re/png/step/ (oracle f00..f29).
##
## Run (NOT headless):
##   godot --path . -s res://tools/capture_equip_slide.gd -- --out=/tmp/equip_port

var _host: Node
var _out := "/tmp/equip_port"
var _pf := 0
var _state := 0
var _shots := [0, 8, 15]   # slide frames to grab (15 = near-settle, panel still closed)
var _shot_i := 0
var _settle_wait := 0
var _quit := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--out="):
			_out = a.substr("--out=".length())
	_host = load("res://assets/scenes/FormationDetailTransition.tscn").instantiate()
	root.add_child(_host)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[equip-cap] booting host, out prefix -> %s" % _out)


func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _grab(tag: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s_%s.png" % [_out, tag]
	img.save_png(path)
	print("[equip-cap] grabbed %s -> %s" % [tag, path])


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
		2:  # menu open; choose "Item" (row 0) → Equip transition begins
			if _pf > 55:
				_host.action_menu().confirm()
				_grab("f00")
				_shot_i = 0
				_state = 3
		3:  # step the slide by hand, grabbing at the requested frames
			# advance one logical slide frame per post-draw
			if _host.is_equip_sliding():
				_host.equip_step()
			if _shot_i < _shots.size() and _host._equip_frame >= _shots[_shot_i]:
				_grab("f%02d" % _host._equip_frame)
				_shot_i += 1
			if not _host.is_equip_sliding():
				# slide done → _finish_equip ran (Eqp-only panel rebuilt + 4-item menu box-opening).
				# Let the menu box-open settle, then grab the FINAL Equip sub-screen (vs current.png).
				_settle_wait = 24
				_state = 4
		4:  # wait for the panel rebuild + menu box-open, then grab the settled screen
			_settle_wait -= 1
			if _settle_wait <= 0:
				_grab("final")
				_quit = true
