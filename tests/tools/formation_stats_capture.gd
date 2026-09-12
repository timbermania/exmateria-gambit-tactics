extends Node3D
## Formation equip-screen STATS-PANEL oracle-diff CAPTURE (§15.29 dev tool, round 48).
##
## Sibling of formation_picker_capture.gd, stopped one beat EARLIER: it drives
## Formation→detail→Item→Equip and captures the settled equip screen with the stats
## panel in its FULL-stats state (values shown, no picker preview) — the state the
## pcsx-redux oracle `SCUS94221.sstate1` freezes. Same ortho-camera 1:1 framing.
##
## Run (headful, from godot-learning/):
##   godot --path . --quit-after 120 res://tests/tools/formation_stats_capture.tscn
## then diff:
##   uv run python tests/tools/oracle_diff.py <OUT_PNG> <oracle fb.png>

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const PPU := 0.04
const OUT_PNG := "/tmp/stats_re/port_stats.png"

func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev

func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] an oracle-diff CAPTURE tool (dev tool, round 48) — it renders the settled equip screen for pixel-diffing")
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	for _i in 6:
		await get_tree().process_frame
	var form = host._formation
	if form == null:
		push_error("[capture] no formation"); get_tree().quit(1); return
	# Match the oracle Ramza loadout (see formation_picker_capture.gd for the rationale).
	var sel = form.selected_character()
	if sel != null and sel.progression != null:
		var ES = UnitProgression.EquipSlot
		sel.progression.equipment[ES.RIGHT_HAND] = 19    # Broad Sword
		sel.progression.equipment[ES.LEFT_HAND] = -1     # empty (matches oracle)
		sel.progression.equipment[ES.HEAD] = 157         # Leather Hat
		sel.progression.equipment[ES.BODY] = 186         # Clothes
		sel.progression.equipment[ES.ACCESSORY] = 208    # Battle Boots
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	host.open_action_menu()
	host.action_menu().confirm()
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	# STOP here: equip screen settled, stats panel full-stats (no picker). This is sstate1.
	print("[capture] equip settled  stats_panels=", d.stats_panel_count())

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = 240.0 * PPU
	cam.position = Vector3(128.0 * PPU, -120.0 * PPU, 50.0)
	cam.near = 0.01
	cam.far = 200.0
	add_child(cam)
	cam.make_current()
	for _i in 20:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_PNG.get_base_dir())
	img.save_png(OUT_PNG)
	print("[capture] saved ", OUT_PNG, " ", img.get_width(), "x", img.get_height(),
		"  (display px = capture / ", float(img.get_height()) / 240.0, ")")
	get_tree().quit(0)
