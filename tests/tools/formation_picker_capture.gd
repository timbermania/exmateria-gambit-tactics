extends Node3D
## Formation equip-PICKER oracle-diff CAPTURE (§15.26 dev tool, round 38).
##
## Renders the REAL composited picker screen so it can be pixel-diffed against the pcsx-redux oracle
## framebuffer (fb4.png). This is the self-verify loop that pins frame geometry by MEASUREMENT instead
## of eyeballing: it drives the actual Formation→detail→Item→Equip→slot→picker flow, then captures
## through an ORTHOGONAL camera aligned 1:1 with the PSX 256×240 framebuffer.
##
## Key trick (why an earlier attempt came back blank): the formation flow builds its UI in world space
## but sets up NO camera when instanced bare — you MUST add an ortho camera. Display px (px,py) maps to
## world (px*PPU, -py*PPU); a keep-HEIGHT ortho of size 240*PPU covers display-y 0..240, so the capture's
## Y axis is PAR-free and lines up with fb4 row-for-row (X carries the frame PAR, so trust Y for vertical
## edges). The window comes out HiDPI-scaled (e.g. 1280×960 = 4× or 5×) — a clean integer multiple that
## tools/oracle_diff.py area-downscales back to 256×240.
##
## Run (headful, from godot-learning/):
##   godot --path . --quit-after 120 res://tests/tools/formation_picker_capture.tscn
## then diff:
##   uv run python tests/tools/oracle_diff.py <this OUT_PNG> <oracle fb4.png>
##
## The oracle framebuffer is ROM-derived (kept local, e.g. /tmp/picker_re2/fb4.png or the project-assets
## pcsx rig) — regenerate it from pcsx-redux at the settled-picker savestate; do NOT commit it.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const PPU := 0.04
const OUT_PNG := "/tmp/picker_re2/port_full.png"

func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev

func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] an oracle-diff CAPTURE tool (dev tool, round 38) — it renders the picker screen for pixel-diffing")
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
	# Equip the selected unit to MATCH the oracle's Ramza (Broad Sword / Leather Hat / Clothes / Battle
	# Boots, L.Hand empty) so the §15.13 per-slot equipped-item NAME column is comparable — the harness
	# unit is otherwise a bare Squire (nothing to render). Set BEFORE the detail opens (its set_stats_view
	# reads prog.equipment). The equipped-item ICONS are deferred (worklist #7: no item→ITEM.BIN-icon-cell
	# map yet), so only the names appear — that's the faithful state, not a bug. Portrait/level also
	# differ (test data) — likewise not a bug.
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
	host.action_menu().confirm()
	host._input(_action("ui_accept"))
	var p = host.equip_picker()
	print("[capture] picker=", p, " stats_panels=", d.stats_panel_count(),
		" equip_names=", d.equip_item_name_count(), " equip_icons=", d.equip_item_icon_count(), " (icons deferred #7)")

	# Ortho camera framed on the full 256×240 display space (keep-height): center = display (128,120).
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
