class_name TilesDebugPanel
extends BaseDebugPanel
## F3 "Tiles" panel — live-tunes the range-overlay tile look per highlight type.
##
## Per-type + UV-crop knobs are shared TuneField rows bound to `tile.*` slugs (ADR-0068
## move 2): TileOverlayConfig OWNS the values (get_param / the uv_* getters coalesce
## Tune.of, and a Tune.value_changed→`changed` bridge re-applies live tiles), so this
## panel is just a VIEW (decision 12). The per-type controls are MULTIPLEXED behind a
## type selector: picking a type rebuilds the per-type section bound to THAT type's slugs
## (`tile.<type>.<param>`). Pause+scrub stay hand-rolled — they're transient inspection
## state, not persistable tunables.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const TileOverlayConfig = ExMateriaBattlefield.TileOverlayConfig


const TuneField = preload("res://src/debug/TuneField.gd")

const PALETTE_NAMES := [
	"Blue (0)", "Red (1)", "Slot2 (2)", "YellowA (3)", "Cursor (4)",
	"Slot5 (5)", "Slot6 (6)", "Slot7 (7)", "YellowB (8)",
]
const TEXTURE_NAMES := ["Textured (sheet)", "Flat fill"]
const ANIM_NAMES := ["Static", "Barber-pole (rotate)"]
# Blend modes — 0..3 = PSX ABR rates, 4 = opaque (ABE off). See MODE_SHADERS.
const BLEND_NAMES := ["0: Average (50/50)", "1: Additive", "2: Subtractive", "3: Additive 1/4", "4: Opaque"]

var _type_opt: OptionButton
var _per_container: VBoxContainer


func setup() -> void:
	panel_title = "Tiles"
	panel_category = Category.TILES
	_build_ui()


func _selected_type() -> int:
	return TileOverlayConfig.tunable_types()[_type_opt.selected]


func _build_ui() -> void:
	var vb := VBoxContainer.new()
	add_child(vb)

	# Type selector — remembers the last-edited type (AUTOSAVE, ADR-0068) so you resume
	# tuning it next launch. The type set is STATIC, so the enum path fits; picking a type
	# both persists it and rebuilds the per-type rows for that type.
	_type_opt = TuneField.add(vb, "Tile type", "tile.selected_type",
		TileOverlayConfig.tunable_types()[0], {"enum": _type_enum()},
		Tune.Persist.AUTOSAVE) as OptionButton
	_type_opt.item_selected.connect(func(_i): _rebuild_per_type())

	var per := create_collapsible_section(vb, "PER-TYPE LOOK")
	_per_container = VBoxContainer.new()
	per.add_child(_per_container)
	_rebuild_per_type()

	# Global UV crop — clean single tunables (fixed slugs).
	var uv := create_collapsible_section(vb, "GLOBAL — UV CROP (texels)")
	TuneField.add(uv, "Offset X", "tile.uv_offset_x", TileOverlayConfig.uv_offset_x, {"min": 0.0, "max": 256.0, "step": 0.25})
	TuneField.add(uv, "Offset Y", "tile.uv_offset_y", TileOverlayConfig.uv_offset_y, {"min": 0.0, "max": 256.0, "step": 0.25})
	TuneField.add(uv, "Size W", "tile.uv_size_w", TileOverlayConfig.uv_size_w, {"min": 1.0, "max": 256.0, "step": 0.25})
	TuneField.add(uv, "Size H", "tile.uv_size_h", TileOverlayConfig.uv_size_h, {"min": 1.0, "max": 256.0, "step": 0.25})

	# Global inspect — transient (freeze + scrub the barber-pole); NOT tunables, so
	# hand-rolled and written through set_global (which emits `changed`).
	var insp := create_collapsible_section(vb, "GLOBAL — INSPECT")
	# tune-exempt: transient inspect state OWNED by TileOverlayConfig.paused (set_global +
	# `changed` bridge re-applies live tiles) — session-only by design, never persisted.
	var pause_cb := CheckBox.new()  # tune-exempt: transient, owned by TileOverlayConfig.paused
	pause_cb.text = "Pause + scrub"
	pause_cb.set_pressed_no_signal(TileOverlayConfig.of().paused)
	pause_cb.toggled.connect(func(on): TileOverlayConfig.of().set_global("paused", on))
	insp.add_child(pause_cb)
	var scrub_row := HBoxContainer.new()
	add_label(scrub_row, "Phase", 96)
	# tune-exempt: transient scrub position owned by TileOverlayConfig.scrub_phase.
	var scrub_sb := SpinBox.new()  # tune-exempt: transient, owned by TileOverlayConfig.scrub_phase
	scrub_sb.min_value = 0
	scrub_sb.max_value = 14
	scrub_sb.step = 1
	scrub_sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrub_sb.set_value_no_signal(TileOverlayConfig.of().scrub_phase)
	scrub_sb.value_changed.connect(func(v): TileOverlayConfig.of().set_global("scrub_phase", int(v)))
	scrub_row.add_child(scrub_sb)
	insp.add_child(scrub_row)

	add_separator(vb)
	add_print_values_button(vb)


## Rebuild the per-type rows for the currently-selected type, bound to THAT type's
## `tile.<type>.<param>` slugs. Freeing the old rows drops their (owner-scoped) Tune
## bindings, so switching types never leaves ghost bindings behind.
func _rebuild_per_type() -> void:
	# free() (not queue_free) so the old rows leave the tree NOW — their owner-scoped
	# Tune bindings drop synchronously on tree_exited, before the new rows bind.
	for child in _per_container.get_children():
		_per_container.remove_child(child)
		child.free()
	var t := _selected_type()
	_row(t, "Palette", "palette_row", _enum_hint(PALETTE_NAMES))
	_row(t, "Flat fill", "flat_fill", {})
	_row(t, "Animation", "anim_mode", _enum_hint(ANIM_NAMES))
	_row(t, "Blend mode", "blend_mode", _enum_hint(BLEND_NAMES))
	_row(t, "Tint (base)", "tint", {})
	_row(t, "Mono (recolor via tint)", "mono", {})
	_row(t, "Speed (Hz)", "phase_rate", {"min": 0.0, "max": 120.0, "step": 0.5})
	_row(t, "Flat hue idx", "flat_index", {"min": 1, "max": 15, "step": 1})
	# Per-type palette-linearization exponent: pow(rgb, gamma). 2.2 = legacy; lower
	# brightens + desaturates (CURSOR_ACTIVE ≈ 1.0 matches the in-game tile).
	_row(t, "Gamma (pow)", "srgb_gamma", {"min": 0.1, "max": 3.0, "step": 0.05})


## One per-type TuneField row: default is the type's live coalesced value, slug is
## `tile.<type>.<key>`.
func _row(type: int, label_text: String, key: String, hint: Dictionary) -> void:
	TuneField.add(_per_container, label_text, TileOverlayConfig.param_slug(type, key),
		TileOverlayConfig.get_param(type, key), hint)


## The type selector's enum map {type_label -> type_value}: metadata is the type value and
## the dict preserves tunable_types() order, so _selected_type()'s index lookup still holds.
func _type_enum() -> Dictionary:
	var e := {}
	for t in TileOverlayConfig.tunable_types():
		e[TileOverlayConfig.type_label(t)] = t
	return e


## Build a TuneField enum hint {label -> index} from an ordered name list.
func _enum_hint(names: Array) -> Dictionary:
	var e := {}
	for i in names.size():
		e[names[i]] = i
	return {"enum": e}


func _on_print_values() -> void:
	TileOverlayConfig.print_values()
