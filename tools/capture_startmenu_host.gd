extends SceneTree

## Throwaway capture of the FULL START-sub-menu stack (§15.20): the real
## FormationDetailTransition host — formation roster → detail overlay → action menu —
## with the engine fold ACTIVE (added to `root`). Seeds the roster, opens a unit's detail,
## opens the action menu, lets the box-open settle, screenshots, quits.
##
## Run (NOT headless):
##   godot --path . -s res://tools/capture_startmenu_host.gd -- --shot=/tmp/host.png

var _host: Node
var _f := 0
var _did := false
var _quit := false
var _shot := "/tmp/startmenu_host.png"
var _opened := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--shot="):
			_shot = a.substr("--shot=".length())
	_host = load("res://assets/scenes/FormationDetailTransition.tscn").instantiate()
	root.add_child(_host)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[host-cap] booting FormationDetailTransition, fold-active -> %s" % _shot)


func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _on_post_draw() -> void:
	_f += 1
	# Give the host a few frames to seed the roster, then open a unit's detail + the menu.
	if _f == 10 and not _opened:
		_opened = true
		var form = _host._formation
		var sel = form.selected_character()
		var d = _host.open_detail(sel)
		# Settle the detail box-open immediately so the menu opens over a settled screen.
		d.set_open_frame(d._open_total_frames())
		_host.open_action_menu()
		print("[host-cap] opened detail + action menu for %s" % (sel.display_name if sel else "?"))
	if _f >= 45 and not _did:
		_did = true
		root.get_texture().get_image().save_png(_shot)
		print("[host-cap] ===== CAPTURED f=%d -> %s =====" % [_f, _shot])
		_quit = true
