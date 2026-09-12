class_name CursorDebugPanel
extends BaseDebugPanel
## F3 "Cursor" panel — live-tunes the floating tile-cursor dagger's height, size,
## bob animation, palette, and STP-outline blend mode. Every row is a shared
## TuneField bound to a `cursor.*` slug (ADR-0068 move 2): TileCursor OWNS these
## values (it binds each slug in _ready), so this panel is just a VIEW (decision 12)
## — a scrub here writes the slug, TileCursor re-applies it, and the same knob moves
## in any scene / on the generated dashboard. No writes onto the TileCursor node.
##
## Heights/scales here are world units; the bob is the ROM step table (ADR-0046)
## played on the mesh's local Y under `cursor_height` — no amplitude/period knob,
## only `vblanks_per_tick` (pace) and `bob_scale` (exaggeration).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const CursorRig = ExMateriaBattlefield.CursorRig


const TuneField = preload("res://src/debug/TuneField.gd")

# The four POSE scalar rows are pure VIEWS — TileCursor owns their default + hint (read from
# the registry). palette_row / blend_mode stay registrant rows here (they pass a default + the
# _PAL_HINT / enum meta): their default is material-sourced (.tres shader_parameter, per ADR M5),
# registered per-instance by TileCursor's bind_update, so this panel supplies their affordance.
const _PAL_HINT := {"min": 0, "max": 8, "step": 1}


## `rig` is unused now that the cursor owns every value (it binds the slugs
## itself); the param stays for call-site compatibility (GPUArena passes it).
func setup(_rig: CursorRig) -> void:
	panel_title = "Cursor"
	panel_category = Category.CURSOR
	_build_ui()


func _build_ui() -> void:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(250, 0)
	add_child(vb)

	var sec := create_collapsible_section(vb, "FLOATING DAGGER POSE")
	# Height is the fixed distance above the active tile's surface; the cursor
	# follows tile elevation (no more constant ground anchor).
	TuneField.add(sec, "Height", "cursor.height")
	TuneField.add(sec, "Scale", "cursor.scale")

	# The bob is the ROM step table (ADR-0046) — no amplitude/period knob exists.
	# `vblanks_per_tick` is the frame-skip divider (effective rate = 60/N; N=1 is
	# normal play); `bob_scale` exaggerates the ROM offset for visual inspection.
	var bob := create_collapsible_section(vb, "BOB (ROM step table)")
	TuneField.add(bob, "vblanks/tick", "cursor.vblanks_per_tick")
	TuneField.add(bob, "Bob scale", "cursor.bob_scale")

	# Palette selection. The cursor is drawn like a particle — two STP passes
	# (opaque body idx 7..15 + semi-trans outline idx 1..6). palette_row picks the
	# BATTLE.BIN CLUT slot (4 = the cursor's gold ramp); written to both passes.
	var pal := create_collapsible_section(vb, "PALETTE")
	TuneField.add(pal, "Palette row", "cursor.palette_row", 4, _PAL_HINT)

	# Outline blend mode — the PSX ABR rate for the STP=1 outline pixels. Average
	# (mode0) blends 50/50 and so LIGHTENS dark texels; Subtractive (mode2, the
	# default) darkens → drop-shadow look. The enum value IS the mode index.
	var blend := create_collapsible_section(vb, "BLEND (STP=1 outline)")
	var blend_enum := {}
	for i in CursorRig.SEMI_MODE_LABELS.size():
		blend_enum[CursorRig.SEMI_MODE_LABELS[i]] = i
	TuneField.add(blend, "Mode", "cursor.blend_mode", 2, {"enum": blend_enum})

	# Cursor width stretch (Cursor PAR) now lives in the Display debug panel as the
	# shared psx_cursor_stretch global — see ADR-0044.

	add_separator(vb)
	add_print_values_button(vb)


func _on_print_values() -> void:
	# Read the live coalesced values off the slugs (override ?? code default), not
	# the node — the slug IS the source of truth now.
	print("# paste into TileCursor.gd @export defaults:")
	print("cursor_height          = %.3f" % Tune.get_value("cursor.height"))
	print("cursor_scale           = %.3f" % Tune.get_value("cursor.scale"))
	print("vblanks_per_tick       = %d" % Tune.get_value("cursor.vblanks_per_tick"))
	print("bob_scale              = %.3f" % Tune.get_value("cursor.bob_scale"))
	print("# paste into tile_cursor_opaque.tres shader_parameter:")
	print("palette_row            = %d" % Tune.get_value("cursor.palette_row"))
	var bm: int = Tune.get_value("cursor.blend_mode")
	if bm >= 0 and bm < CursorRig.SEMI_MODE_LABELS.size():
		# The outline routes through the compositor now (no semi material) — the blend mode is a
		# runtime value; print the label so a chosen default can be set as TileCursor.CURSOR_DEFAULT_BLEND_MODE.
		print("# outline blend mode (cursor.blend_mode): %s" % CursorRig.SEMI_MODE_LABELS[bm])
