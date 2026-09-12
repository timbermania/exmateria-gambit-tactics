extends SceneTree

## Throwaway capture for the Change-Job COMMIT cutscene (CHANGE_JOB_COMMIT.md). Clones the boot
## sequence of tools/capture_changejob.gd, then rotates one step off the current job, presses ○,
## and grabs the beat at the frames the oracle savestates were taken at — so the port can be
## eyeballed side by side with the ROM rather than against an expectation.
##
## The clock is HAND-DRIVEN (host.changejob_commit_step) with one grab per rendered frame, so a
## capture at "c92e = 127" really is frame 127 and not whatever the wall clock drifted to.
##
## Run (NOT headless):
##   godot --path . -s res://tools/capture_changejob_commit.gd -- --out=/tmp/cjc
##   godot --path . -s res://tools/capture_changejob_commit.gd -- --out=/tmp/cjc --slug=generic:4a:m
##
## `--slug=` selects a specific owned unit before the ○-press (scrolling the row window to it).
## WITHOUT it the default cell is a TRUE appearance-type (`10_year_old_man`) — a sheet no job
## reaches, so its body is job-invariant BY DESIGN and the dissolve legitimately has identical
## art on both sides. To see the dissolve do real work, select a generic-WARDROBE unit
## (`generic:<job>:m|:f`), whose sheet follows its job (ADR-0072 dec.1).

var _host: Node
var _out := "/tmp/cjc"
var _slug := ""
var _pf := 0
var _state := 0
var _wait := 0
var _quit := false
## The frames worth looking at: the chrome cut + band close, the tint peak, the two oracle
## midpoints, the cylinder's exit, and the settled screen after the apply.
const GRABS := [1, 3, 5, 8, 10, 20, 40, 80, 127, 175, 219, 221, 230, 239]
var _next := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--out="):
			_out = a.substr("--out=".length())
		elif a.begins_with("--slug="):
			_slug = a.substr("--slug=".length())
	_host = load("res://assets/scenes/FormationDev.tscn").instantiate()
	root.add_child(_host)
	# ADR-0181: `FormationDev.tscn`'s root is the SEEDING boot ([FormationDevBoot]) — this rig
	# needs its `_unlock_every_job` for the ring to be committable. The coordinator it drives is
	# that boot's child, added during `_ready`, which `add_child` above has already run.
	_host = _host.get_node("FormationDetailTransition")
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[cjc] booting host, out prefix -> %s" % _out)


func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _grab(tag: String) -> void:
	var path := "%s_%s.png" % [_out, tag]
	root.get_texture().get_image().save_png(path)
	print("[cjc] grabbed %s -> %s" % [tag, path])


func _on_post_draw() -> void:
	_pf += 1
	var form = _host._formation
	match _state:
		0:
			if _pf == 12:
				_grab("boot")
			if _pf > 12 and form != null and form.selected_character() != null:
				if _slug != "":
					_select_slug(form, _slug)
				var ev := InputEventAction.new(); ev.action = "ui_accept"; ev.pressed = true
				form._unhandled_input(ev)
				_state = 1
		1:
			if _pf > 40:
				_host.open_action_menu()
				_state = 2
		2:
			if _pf > 55:
				_host.action_menu().move_down()
				_host.action_menu().move_down()
				_host.action_menu().confirm()
				_state = 3
		3:
			if _host.is_changejob_sliding():
				_host.changejob_step()
			if not _host.is_changejob_sliding():
				_wait = 0
				_state = 4
		4:   # let the ring entry + plate box-open settle
			_wait += 1
			if _wait > 30:
				var ev := InputEventAction.new(); ev.action = "ui_right"; ev.pressed = true
				_host._input(ev)
				_wait = 0
				_state = 5
		5:   # rotation glide settles, then grab the pre-press screen and commit
			_wait += 1
			if _wait > 24:
				_grab("ss0_prepress")
				var jid: String = _host._formation.changejob_highlighted_job_id()
				var ok: bool = _host.confirm_changejob()
				print("[cjc] commit %s -> started=%s rot=%s entry=%s" % [jid, ok,
					_host._changejob_rot_active, _host._is_changejob_entry()])
				_next = 0
				_wait = 0
				_state = 6
		6:   # one hand-driven tick per rendered frame, grabbing the interesting ones
			if not _host.is_changejob_committing():
				_grab("settled")
				print("[cjc] post-commit job=%s" % _host._formation.selected_character().progression.current_job_id)
				_host.leave()          # × back out to the roster
				_wait = 0
				_state = 7
				return
			# `>=`, not `==`: the host's own _process is ticking too, so the clock can step past a
			# target between rendered frames. Grab the first frame at or after each target.
			while _next < GRABS.size() and _host.changejob_commit_frame() >= GRABS[_next]:
				_grab("f%03d" % GRABS[_next])
				_next += 1
			_host.changejob_commit_step()
		7:   # let the back-out unwind, then grab the docked roster grid
			_wait += 1
			if _wait > 90:
				_grab("roster")
				var f = _host._formation
				var sel = f.selected_character()
				print("[cjc] selected_cell=%s selected=%s job=%s token='%s'" % [
					f.selected_cell, sel.display_name, sel.progression.current_job_id, sel.template_token])
				var units: Array = f._roster_characters()
				for i in mini(3, units.size()):
					var u = units[i]
					print("[cjc]   grid[%d] = %s job=%s hp=%d token='%s'" % [
						i, u.display_name, u.progression.current_job_id, u.progression.get_effective_hp(), u.template_token])
				_wait = 0
				_state = 8
		8:   # walk the cursor DOWN to force a scroll, grabbing as we go
			_wait += 1
			if _wait % 12 == 0 and _wait <= 96:
				var ev := InputEventAction.new(); ev.action = "ui_down"; ev.pressed = true
				_host._formation._unhandled_input(ev)
				_grab("scroll_%02d" % (_wait / 12))
			if _wait > 108:
				_grab("scrolled")
				_wait = 0
				_state = 9
		9:   # walk back UP to the changed unit and grab it again
			_wait += 1
			if _wait % 12 == 0 and _wait <= 96:
				var ev2 := InputEventAction.new(); ev2.action = "ui_up"; ev2.pressed = true
				_host._formation._unhandled_input(ev2)
			if _wait > 108:
				_grab("back")
				var f2 = _host._formation
				var u0 = f2._roster_characters()[0]
				print("[cjc] back: cell=%s grid[0]=%s job=%s hp=%d" % [
					f2.selected_cell, u0.display_name, u0.progression.current_job_id,
					u0.progression.get_effective_hp()])
				_quit = true


## Scroll the row window to the owned unit with `slug` and put the cursor on it. The grid shows
## a ROWS x COLS window into the owned roster (`scroll_window`), so selecting an arbitrary unit
## is two moves: pick the top-row offset that contains it, then the cell within that window.
func _select_slug(form, slug: String) -> void:
	# A `-s` SceneTree script cannot resolve autoload identifiers at compile time — reach the
	# catalog through the tree instead.
	var catalog = root.get_node_or_null("/root/CharacterCatalog")
	if catalog == null:
		print("[cjc] WARNING no CharacterCatalog autoload — keeping default cell")
		return
	var owned: Array = catalog.owned_units()
	var index := -1
	for i in owned.size():
		if owned[i].slug == slug:
			index = i
			break
	if index < 0:
		print("[cjc] WARNING slug '%s' not in the owned roster (%d units) — keeping default cell"
			% [slug, owned.size()])
		return
	var cols: int = form.COLS
	var row: int = index / cols
	form.scroll_offset = form.clamp_scroll(row, owned.size())
	form.set_selected_cell(Vector2i(index % cols, row - form.scroll_offset))
	var sel = form.selected_character()
	print("[cjc] selected slug=%s -> index=%d cell=%s got=%s job=%s token='%s'" % [
		slug, index, form.selected_cell,
		"null" if sel == null else sel.display_name,
		"?" if sel == null else sel.progression.current_job_id,
		"?" if sel == null else sel.template_token])
