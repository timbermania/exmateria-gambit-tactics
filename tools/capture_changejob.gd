extends SceneTree

## Throwaway capture for the START-"Change Job" full-screen (§15.24, RE round 28) — clones
## tools/capture_ability_slide.gd but chooses row 2 ("Change Job"). Grabs the settled Change-Job
## screen so the port can be eyeballed against tmp/changejob_dest/fb.png (the oracle).
##
## Run (NOT headless):
##   godot --path . -s res://tools/capture_changejob.gd -- --out=/tmp/changejob_port

var _host: Node
var _out := "/tmp/changejob_port"
var _pf := 0
var _state := 0
var _settle_wait := 0
var _quit := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--out="):
			_out = a.substr("--out=".length())
	_host = load("res://assets/scenes/FormationDev.tscn").instantiate()
	root.add_child(_host)
	# ADR-0181: `FormationDev.tscn`'s root is the SEEDING boot ([FormationDevBoot]) — this rig
	# needs its `_unlock_every_job` for the ring to be committable. The coordinator it drives is
	# that boot's child, added during `_ready`, which `add_child` above has already run.
	_host = _host.get_node("FormationDetailTransition")
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[changejob-cap] booting host, out prefix -> %s" % _out)


func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _grab(tag: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s_%s.png" % [_out, tag]
	img.save_png(path)
	print("[changejob-cap] grabbed %s -> %s" % [tag, path])


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
		2:  # menu open; nav to row 2 = "Change Job", confirm → Change-Job transition begins
			if _pf > 55:
				_host.action_menu().move_down()   # row 0 → row 1
				_host.action_menu().move_down()   # row 1 → row 2
				_host.action_menu().confirm()
				_state = 3
		3:  # step the split slide by hand to completion; _finish_changejob starts the ring entry + box-open
			if _host.is_changejob_sliding():
				_host.changejob_step()
			if not _host.is_changejob_sliding():
				_settle_wait = 0
				_state = 4
		4:  # let REAL frames drive the entry contraction + plate box-open (host._process); grab a few
			_settle_wait += 1
			if _settle_wait % 2 == 1 and _settle_wait <= 24:
				_grab("entry_%02d" % _settle_wait)
			if _settle_wait > 28:
				_grab("settled")
				# gap 3: press RIGHT to rotate the ring, then let it glide
				var ev := InputEventAction.new(); ev.action = "ui_right"; ev.pressed = true
				_host._input(ev)
				_settle_wait = 0
				_state = 5
		5:  # let the rotation glide settle, then grab the rotated screen
			_settle_wait += 1
			if _settle_wait > 20:
				_grab("rotated")
				_quit = true
