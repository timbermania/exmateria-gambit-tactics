extends Node3D
# test-kind: capture
## CAPTURE instrument for the turn-queue strip (ADR-0269) — NOT a test, and deliberately not in
## `run_all_tests.sh`'s list. It emits no verdict; it writes PNGs so the layout can be LOOKED at.
##
## Every readability call this widget makes — the portrait scale, the card gap, the team colour,
## the "Enemy" tag's tuck, the title's band height — is a live `Tune` bind, and none of them can
## be settled by an assertion. ADR-0244 learned that the expensive way: its whole layout was
## correct by every test it had while being invisible on screen, and a capture was what found it.
## This is that instrument, kept.
##
##     godot --path . tests/TurnQueueHudShot.tscn
##
## Writes three files to `tests/logs/` (gitignored):
##   turnqueue_full.png     the whole 1024x960 frame
##   turnqueue_crop.png     the strip, 2x nearest, for judging pixels
##   turnqueue_midopen.png   the BAND's scissor part-way across the screen, cards still shut
##   turnqueue_midcards.png  the band settled and each CARD's own box part-way open
##
## Two mid frames and not one, because ADR-0269 dec. 8 made the strip's open two stages: the band
## sweeps out, and only then do the cards scissor open on it. One frame cannot hold both, and
## between them they are the only thing that can tell a working aperture from an absent one.
##
## ⚠️ `UI3Registry` drives the transition engine from `_process`, so the render frames this rig
## must await to get a DRAWN image are themselves beat frames. Hand steps and render frames add
## up, and the mid shots are tuned against the sum rather than against the hand steps alone. That
## is why `_settle_and_shoot` PRINTS the apertures it actually caught: a mid shot that silently
## drifted to 100% looks exactly like a strip with no aperture at all.

const OUT := "res://tests/logs"
## A round-robin with both teams interleaved and unit 0 appearing twice — the shape ADR-0244
## dec. 1 is about, so the capture shows a repeat entry rather than a tidy one-per-unit row.
const ENTRIES := [
	{"index": 0, "team": 0, "ticks_from_now": 0, "turn_meter": 100},
	{"index": 1, "team": 1, "ticks_from_now": 6, "turn_meter": 0},
	{"index": 2, "team": 0, "ticks_from_now": 11, "turn_meter": 0},
	{"index": 3, "team": 1, "ticks_from_now": 17, "turn_meter": 0},
	{"index": 4, "team": 0, "ticks_from_now": 22, "turn_meter": 0},
	{"index": 5, "team": 1, "ticks_from_now": 28, "turn_meter": 0},
	{"index": 0, "team": 0, "ticks_from_now": 33, "turn_meter": 0},
	{"index": 6, "team": 1, "ticks_from_now": 40, "turn_meter": 0},
]

var _hud: TurnQueueHud


class StubUnit extends Node:
	var body_sprite_id: int = 0x80
	var template_folder: String = ""


func _ready() -> void:
	# Declared, not merely absent from the runner's list — #417's guard is right to demand it:
	# "in nobody's list" and "silently dropped" look identical from outside.
	print("[NOT_A_TEST] the turn-queue strip's CAPTURE instrument — it writes PNGs of the settled and mid-open strip for a human to look at, and asserts nothing")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# The battle's own camera metric (PlayerCamera.tscn size 12.6), because UIWindowHost
	# counter-scales by `camera.size / 14.0` — a capture at any other size is a capture of a
	# strip nobody will see.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 12.6
	cam.position = Vector3(0, 0, 10)
	cam.current = true
	add_child(cam)

	var units: Array = []
	for i in range(8):
		var u := StubUnit.new()
		u.body_sprite_id = 0x80 + i
		cam.add_child(u)
		units.append(u)

	_hud = TurnQueueHud.mount(cam, null)
	_hud.bind_units(units)
	_hud.show_entries(ENTRIES)
	await _capture()


func _capture() -> void:
	await _settle_and_shoot("turnqueue_full", 64, true)
	# Re-open from shut and shoot as early as a drawn frame can be had — see the warning at the
	# top for why that is zero hand steps and not four.
	_hud.set_covered(true)
	for _i in range(64):
		UI3Registry.transition_engine_step()
	_hud.set_covered(false)
	_hud.show_entries(ENTRIES)
	await _settle_and_shoot("turnqueue_midopen", 0, false)
	# ...and again once the band has settled and the CARDS are the thing opening. The band's
	# own curve settles at 8; the render frame the shot above awaited has already spent one.
	await _settle_and_shoot("turnqueue_midcards", 7, false)
	get_tree().quit()


func _settle_and_shoot(name: String, steps: int, also_full: bool) -> void:
	for _i in range(steps):
		UI3Registry.transition_engine_step()
	# Beat frames are stepped by hand above; these are RENDER frames, which is a different
	# clock — the viewport has to actually draw the state the steps produced.
	for _i in range(4 if steps >= 64 else 1):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	if also_full:
		img.save_png("%s/%s.png" % [ProjectSettings.globalize_path(OUT), name])
	# The FULL width, not 62% of it: the band now runs edge to edge (dec. 7), so a crop that
	# stopped short would cut off the half of the picture the widening was about.
	var crop := img.get_region(Rect2i(0, 0, w, int(h * 0.22)))
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var suffix := "_crop" if also_full else ""
	crop.save_png("%s/%s%s.png" % [ProjectSettings.globalize_path(OUT), name, suffix])
	# The instrument names its SUBJECT. Percentages of each element's own rect, so a shot that
	# drifted to a settled 100 / 100 announces itself instead of passing as a mid-open frame.
	var band := _hud.bar()
	var card: UI3Element = _hud.cards()[0] if not _hud.cards().is_empty() else null
	print("[SHOT] %s%s.png (%dx%d source) — band aperture %d%% of %d px, head card %s" % [
		name, suffix, w, h,
		roundi(100.0 * float(band.aperture().size.x) / maxf(1.0, band.rect().size.x)),
		roundi(band.rect().size.x),
		"<no cards>" if card == null else "%d%% of %d px" % [
			roundi(100.0 * float(card.aperture().size.x) / maxf(1.0, card.rect().size.x)),
			roundi(card.rect().size.x)]])
