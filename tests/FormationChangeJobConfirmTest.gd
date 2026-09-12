extends Node3D
# test-kind: logic
# seeded-break: disabled the _finish_changejob_commit() apply (and-false on the change_job guard); the cutscene no longer writes the new job, so current_job_id stays the old one and the 'last frame did not apply the job' / 'Lv line' asserts red

## The Change-Job wheel OWNS its pad, and ○/Enter starts the COMMIT CUTSCENE (§15.24 +
## CHANGE_JOB_COMMIT.md).
##
## The commit half was re-pinned against the ROM (RE rounds 50/51). What the port did before —
## apply the job on the press frame and leave to the roster — was wrong in three ways at once,
## and each is now a case below: the ROM applies on frame 240, never leaves the screen, and
## answers ○ on the job you are ALREADY in with a deny cue rather than a silent success.
##
## Two faults this also pins, both reported from the running scene:
##   - ○ on the wheel opened the Status OVERLAY on top of it. The wheel's `_input` branch claimed
##     △/←/→ and nothing else, so ○ fell through to the COVERED roster grid, which emitted
##     `unit_activated` → a DETAIL enter stacked on CHANGE_JOB. The ADR-0084 gate does not catch this
##     one: DETAIL ≠ CHANGE_JOB, so the request is not redundant — it is simply not the covered
##     roster's to make.
##   - the same leak carried ↑/↓ and L2/R2, which moved the hidden roster selection and re-paged its
##     sort behind the wheel — invisibly, since the grid is off-screen at the time.
##
## Driven through the REAL viewport (`push_input`), because the leak IS the viewport chain: `_input`
## declines, `_unhandled_input` acts. A test calling either directly cannot see it.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobLevelsDatabase = ExMateriaAlmanac.JobLevelsDatabase


const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const FormationDevBootScript = preload("res://src/ui3/formation/FormationDevBoot.gd")
const State = FormationDetailTransition.State

var _failed := false


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	# ...and open the job gate. This test COMMITS a job change and then re-locks one by hand to
	# prove the gate bites (`_locked_job_is_refused` below), so it needs the gate open first.
	# Was implicit in `FormationDetailTransition._resolve_roster` until ADR-0181 moved the whole
	# fixture into the boot; the boot now publishes it rather than the test growing a copy.
	FormationDevBootScript.unlock_every_job(CharacterCatalog.owned_units())
	await _wheel_owns_the_pad()
	await _accept_starts_the_cutscene_and_stays()
	await _the_skip_collapses_the_cutscene()
	await _the_incoming_body_is_spotlight_immune()
	await _the_changed_body_is_not_orphaned_by_a_rebuild()
	await _current_job_is_denied()
	await _locked_job_is_refused()

	if _failed:
		print("[FAIL] FormationChangeJobConfirm test")
	else:
		print("[PASS] FormationChangeJobConfirm: the wheel owns its pad (○/↑↓/L2R2 never reach the covered roster), ○ starts a 240-frame cutscene that applies on the LAST frame and never leaves the wheel, the incoming body is spotlight-immune and is not orphaned by the next grid rebuild, ○/× skips it, the current job is denied and a locked job is refused")
	get_tree().quit()


## ○ must not open the Status overlay, and ↑/↓ + L2/R2 must not reach the grid underneath.
func _wheel_owns_the_pad() -> void:
	var host := await _host_on_the_wheel()
	if host == null:
		return
	var cell_before: Vector2i = host._formation.selected_cell

	await _tap(KEY_UP, 4)
	await _tap(KEY_DOWN, 4)
	_expect(host._formation.selected_cell == cell_before,
		"↑/↓ moved the roster selection behind the wheel (was %s, now %s)"
		% [cell_before, host._formation.selected_cell])

	await _tap(KEY_ENTER, 20)   # a leak would have opened the overlay within a couple of frames
	_expect(host.detail_overlay() == null or host.current_state() != State.DETAIL,
		"○ on the wheel opened the Status overlay (stack=%s)" % [host._stack])
	_expect(not host._stack.has(State.DETAIL),
		"○ on the wheel pushed DETAIL onto the Change-Job screen (stack=%s)" % [host._stack])

	host.queue_free()
	await get_tree().process_frame


## ○ starts the 240-frame cutscene. The job is NOT applied on the press frame, and the screen is
## still the Change-Job wheel when the beat ends — with the cursor exactly where it was left, so
## the committed job is still the highlighted one (§11 / §11b: "two Chemists on screen").
func _accept_starts_the_cutscene_and_stays() -> void:
	var host := await _host_on_the_wheel()
	if host == null:
		return
	var character = host._formation.selected_character()
	var was: String = character.progression.current_job_id

	# Rotate one step so the front job genuinely differs from the one the unit is already in.
	await _tap(KEY_RIGHT, 2)
	await _wait_until(func(): return not host._changejob_rot_active, 200)
	var front: String = host._formation.changejob_highlighted_job_id()
	_expect(front != "" and front != was,
		"the ring did not rotate off the current job (front=%s, current=%s)" % [front, was])

	await _tap(KEY_ENTER, 2)
	_expect(host.is_changejob_committing(), "○ did not start the commit cutscene")
	_expect(character.progression.current_job_id == was,
		"the job was applied on the PRESS frame (ROM applies on frame 240, not frame 0)")
	_expect(host.current_state() == State.CHANGE_JOB,
		"the commit left the Change-Job screen (state %d) — the ROM never leaves it" % host.current_state())
	# The chrome CUT is instant, and the band close is its consequence off the same clock (§6).
	_expect(not host.detail_overlay().panels_visible(),
		"the vitals/nameplate chrome was not CUT on the press frame")

	# Hand-drive the clock rather than waiting four real seconds — the cadence itself is pinned in
	# ChangeJobCommitCutsceneTest; what matters here is WHERE the apply lands. Drive to a CONDITION,
	# not a count: the host's own _process has been ticking since the press (and under the
	# MAX_CATCHUP clamp a slow test frame is worth several ticks), so a fixed loop overshoots.
	while host.is_changejob_committing() \
			and host.changejob_commit_frame() < ChangeJobCommitCutscene.DURATION - 1:
		host.changejob_commit_step()
	_expect(host.is_changejob_committing(), "the cutscene ended before frame 240")
	_expect(character.progression.current_job_id == was,
		"the job was applied EARLY (at frame %d)" % host.changejob_commit_frame())
	host.changejob_commit_step()

	_expect(not host.is_changejob_committing(), "the cutscene did not end at frame 240")
	_expect(character.progression.current_job_id == front,
		"the last frame did not apply the job (job is %s, want %s)" % [character.progression.current_job_id, front])
	_expect(host.current_state() == State.CHANGE_JOB,
		"the screen left after committing (state %d) — the ROM stays on the wheel" % host.current_state())
	_expect(host._formation.changejob_highlighted_job_id() == front,
		"the cursor moved across the commit (highlighted %s, want %s)"
		% [host._formation.changejob_highlighted_job_id(), front])
	_expect(host.detail_overlay().panels_visible(), "the chrome was not RESTORED after the apply")
	_expect(is_equal_approx(host.detail_overlay().vitals_band_factor(), 1.0),
		"the band did not come back to full (%f)" % host.detail_overlay().vitals_band_factor())
	# §11b consequence 3: the highlighted job IS the current job now, so the plate drops its Lv line.
	_expect(host._changejob.job_level() == 0,
		"the title plate kept its Lv. line after the job became the current one (level %d)"
		% host._changejob.job_level())

	host.queue_free()
	await get_tree().process_frame


## §10: ○ or × during the beat fast-forwards the clock to 220. Driven through the real viewport,
## because the skip is a PAD read — the cutscene owns the pad and only these two buttons act.
func _the_skip_collapses_the_cutscene() -> void:
	var host := await _host_on_the_wheel()
	if host == null:
		return
	await _tap(KEY_RIGHT, 2)
	await _wait_until(func(): return not host._changejob_rot_active, 200)
	await _tap(KEY_ENTER, 2)
	_expect(host.is_changejob_committing(), "○ did not start the commit cutscene")
	# Get the clock inside the skip window without waiting for it.
	while host.changejob_commit_frame() < 60:
		host.changejob_commit_step()

	await _tap(KEY_BACKSPACE, 2)   # ✕ — `ui_cancel` is BACKSPACE since ADR-0137 Amendment 4 moved
	                               # Esc to SELECT/pause. Escape reaches nothing here.
	_expect(host.changejob_commit_frame() >= ChangeJobCommitCutscene.SKIP_WINDOW_HI
			or not host.is_changejob_committing(),
		"× did not skip the cutscene (frame %d)" % host.changejob_commit_frame())

	host.queue_free()
	await get_tree().process_frame


## §4 row 2: ○ on the job the unit is ALREADY in is a DENY — a cue and nothing else. No commit, no
## cutscene, and emphatically not the old "commit nothing and leave anyway".
func _current_job_is_denied() -> void:
	var host := await _host_on_the_wheel()
	if host == null:
		return
	var character = host._formation.selected_character()
	var was: String = character.progression.current_job_id
	# On entry the CURRENT job is the front-bottom ring member, so ○ without rotating hits it.
	_expect(host._formation.changejob_highlighted_job_id() == was,
		"the current job was not at the front on entry (%s vs %s)"
		% [host._formation.changejob_highlighted_job_id(), was])

	var started: bool = host.confirm_changejob()
	_expect(not started, "○ on the CURRENT job started a commit cutscene")
	_expect(not host.is_changejob_committing(), "the current job began animating")
	_expect(host.current_state() == State.CHANGE_JOB,
		"the deny LEFT the Change-Job screen (state %d)" % host.current_state())
	_expect(character.progression.current_job_id == was, "the deny changed the job anyway")

	host.queue_free()
	await get_tree().process_frame


## The ring draws every generic job for the unit's sex, so the unlock gate is `confirm_changejob`'s.
## Re-lock the front job under the harness's blanket unlock and the commit must refuse — and, having
## refused, must leave the screen up rather than falling through to anything else.
func _locked_job_is_refused() -> void:
	var host := await _host_on_the_wheel()
	if host == null:
		return
	var character = host._formation.selected_character()
	await _tap(KEY_RIGHT, 2)
	await _wait_until(func(): return not host._changejob_rot_active, 200)
	var front: String = host._formation.changejob_highlighted_job_id()
	var prereqs: Dictionary = JobLevelsDatabase.get_prerequisites(front)
	if prereqs.is_empty():
		host.queue_free()
		await get_tree().process_frame
		return                          # Squire/Chemist are unlockable by definition — nothing to test
	for required_job_id in prereqs:
		character.progression.job_levels[required_job_id] = 0   # re-lock it
	var was: String = character.progression.current_job_id

	var started: bool = host.confirm_changejob()
	_expect(not started, "a LOCKED job (%s) was committed" % front)
	_expect(not host.is_changejob_committing(), "a LOCKED job started the commit cutscene")
	_expect(character.progression.current_job_id == was,
		"a locked job changed current_job_id anyway (%s)" % character.progression.current_job_id)
	_expect(host.current_state() == State.CHANGE_JOB,
		"the refused commit left the Change-Job screen (state %d)" % host.current_state())

	host.queue_free()
	await get_tree().process_frame


## The incoming job's body must be lit exactly like the avatar that replaces it at the end.
##
## Its cell key (`CHANGEJOB_COMMIT_CELL`) is synthetic and sits 2000 columns off the grid, so the
## per-frame spotlight sweep computed a falloff for it and clamped to `ORB_MIN_LEVEL` — the new job
## dissolved in at 0.625x and then JUMPED to 1.0x the moment the teardown swapped in the rebuilt
## avatar. Measured against the ROM (savestate `ss0_prepress`, poked): the ROM's own residual tint
## is consumed by NOTHING after the last frame, so both sides snap to neutral — the port's extra
## brightness step was the whole of the "the new job comes over dark, then it goes binary" report.
func _the_incoming_body_is_spotlight_immune() -> void:
	var host := await _host_on_the_wheel()
	if host == null:
		return
	var form = host._formation
	var settled_mat: ShaderMaterial = form._body_mats_by_cell.get(form.selected_cell)
	var settled_level: float = settled_mat.get_shader_parameter("ambient_brightness") \
		if settled_mat != null else -1.0

	await _tap(KEY_RIGHT, 2)
	await _wait_until(func(): return not host._changejob_rot_active, 200)
	await _tap(KEY_ENTER, 2)
	_expect(host.is_changejob_committing(), "○ did not start the commit cutscene")

	# Real frames, so the sweep actually runs — a one-shot check right after the mount cannot see it.
	for _i in 4:
		await get_tree().process_frame

	var mat: ShaderMaterial = form._body_mats_by_cell.get(form.CHANGEJOB_COMMIT_CELL)
	_expect(mat != null, "no material for the commit cutscene's target-job body")
	if mat != null:
		var level: float = mat.get_shader_parameter("ambient_brightness")
		_expect(is_equal_approx(level, 1.0),
			"the incoming job's body is lit at %f, not 1.0 — the spotlight sweep is re-driving it"
			% level)
		_expect(is_equal_approx(level, settled_level),
			"the incoming body (%f) is lit differently from the avatar that replaces it (%f) — the swap will POP"
			% [level, settled_level])

	host.queue_free()
	await get_tree().process_frame


## The committed unit's rebuilt body must not survive the next grid rebuild as a second, static
## sprite. Reported from the running game: "a stale sprite — or like 2 overlapping sprites — in the
## main page, and it doesn't scroll on and off screen."
##
## Body holders are detached ROOT siblings of FormationScene (see `_build_cell_body`), tracked only
## by `_body_holders_by_cell` and repositioned by code. Two things chained: `rebuild_selected_body`
## queue_free'd the old holder — deferred, so it still owned the "Body_<x>_<y>" name when the new
## one was added over the same anchor, and Godot renamed the newcomer `@Node3D@<id>`; then
## `rebuild_cells`'s stale sweep matched on `begins_with("Body_")` and missed it, so
## `_populate_cells`'s dict `.clear()` left it in the tree at its last position forever.
func _the_changed_body_is_not_orphaned_by_a_rebuild() -> void:
	var host := await _host_on_the_wheel()
	if host == null:
		return
	var form = host._formation

	await _tap(KEY_RIGHT, 2)
	await _wait_until(func(): return not host._changejob_rot_active, 200)
	await _tap(KEY_ENTER, 2)
	_expect(host.is_changejob_committing(), "○ did not start the commit cutscene")
	while host.is_changejob_committing():
		host.changejob_commit_step()

	host.leave()                              # × back to the roster
	await _wait_until(func(): return host.current_state() == State.IDLE, 300)
	for _i in 6:
		await get_tree().process_frame

	var before := _body_nodes(form)
	_expect(before.size() == form._body_holders_by_cell.size(),
		"the roster already has %d body nodes for %d tracked holders before any rebuild"
		% [before.size(), form._body_holders_by_cell.size()])

	form.rebuild_cells()                      # what a scroll does
	for _i in 3:
		await get_tree().process_frame

	var after := _body_nodes(form)
	_expect(after.size() == form._body_holders_by_cell.size(),
		"%d body nodes are in the tree but only %d are tracked — the committed unit's body was ORPHANED by the rebuild (it will sit still while the grid scrolls under it)"
		% [after.size(), form._body_holders_by_cell.size()])

	host.queue_free()
	await get_tree().process_frame


## Every body holder actually mounted under FormationScene, found by SHAPE (a root-sibling Node3D
## owning a MeshInstance3D) rather than by name — the name is exactly what the bug corrupts.
func _body_nodes(form) -> Array:
	var out: Array = []
	var anchors := {}
	for a in form._cells.values():
		anchors[a.get_instance_id()] = true
	for c in form.get_children():
		if not (c is Node3D) or anchors.has(c.get_instance_id()):
			continue
		if String(c.name) in ["Background", "PillarboxLeft", "PillarboxRight"]:
			continue
		for gc in c.get_children():
			if gc is MeshInstance3D:
				out.append(c)
				break
	return out


## A LIVE host (own _process, real frames) parked on a settled Change-Job wheel.
func _host_on_the_wheel() -> FormationDetailTransition:
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "LiveHost"
	add_child(host)
	for _i in 6:
		await get_tree().process_frame
	if host._formation == null or host._formation.selected_character() == null:
		_expect(false, "no formation/selection")
		host.queue_free()
		return null
	host.enter(State.CHANGE_JOB)          # onto the screen via the seam; the PAD is what's under test
	for _i in 200:
		if host._formation.changejob_wheel_body_count() > 0 and not host._is_changejob_entry():
			break
		await get_tree().process_frame
	_expect(host.current_state() == State.CHANGE_JOB,
		"never reached the Change-Job screen (state %d)" % host.current_state())
	return host


## Wait on a CONDITION, not a frame count — a fixed budget that is ample standalone starves when the
## suite runs back-to-back, and the guard then fails for load rather than for the behavior.
func _wait_until(done: Callable, max_frames: int) -> void:
	for _i in max_frames:
		if done.call():
			return
		await get_tree().process_frame


func _tap(keycode: int, frames: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		get_viewport().push_input(e)
	for _i in frames:
		await get_tree().process_frame


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
