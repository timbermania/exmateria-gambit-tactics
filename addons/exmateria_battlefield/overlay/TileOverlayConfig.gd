extends Node
## TileOverlayConfig — single source of truth for the range-overlay tile look.
##
## The range-overlay tile graphic is ROM-derived (parse_range_tiles.py), but its
## FFT *meaning* is fully decoupled from our placement semantics — see
## godot-learning/CONTEXT.md "Battle range-overlay tile". FFT's blue=move /
## red=attack / yellow=selected do NOT carry over; we just pick a look per
## `CellMarking.Kind`.
##
## A `class_name` with a lazily-created singleton, NOT an autoload (ADR-0183 dec. 1/2):
## an `[autoload]` line can only be written by the consuming game's `project.godot`, so
## `Battlefield` cannot publish one and still ship. Reached as `TileOverlayConfig.of()`.
## Unlike SkirtConfig this cannot be a static class — it carries a `changed` signal, the
## transient `paused`/`scrub_phase` inspect state, and `_types`/`_uv_*` seeded from a
## manifest read; a signal needs an Object.
##
## It holds the shippable per-type defaults (the values you bake in
## after dialing them in) plus the global knobs, and `apply_to_material()` pushes
## them onto a tile's ShaderMaterial. The Tiles debug panel mutates this config
## and every live `Tile` listens to `changed` and re-applies — so twisting a knob
## updates all currently-highlighted tiles with no central registry.
##
## Persistence is deliberate: runtime edits evaporate on quit. Dial the look in
## the panel, hit "Print Values", and paste the result back into the defaults
## below (and the UV crop into RANGETILE.json). No user-file auto-save — the
## source of truth stays in committed code.
## Vault: [[Color Screen Opcode]]
## Vault: [[Tile Overlay]]

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const TunePort = ExMateriaPlatform.TunePort

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const CellMarking = ExMateriaSchema.CellMarking

# ADR-0211 dec. 2 — this file referenced its OWN `class_name`, which the
# façade pass deleted. A self-preload restores the spelling with no body edit.
const TileOverlayConfig = preload("res://addons/exmateria_battlefield/overlay/TileOverlayConfig.gd")

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const BattlefieldContent = preload("res://addons/exmateria_battlefield/install/BattlefieldContent.gd")


const TEX_SIZE: float = 256.0  # fallback if RANGETILE.json is missing/unreadable
## RANGETILE.json is the single source of truth for the sheet layout (written by
## tools/parse_range_tiles.py). The crop + sheet dims below are SEEDED from it at
## _ready() so a re-parse that moves/resizes the atlas (e.g. taller sheet to grab
## the fonts on top) propagates automatically — no hand-syncing GDScript to it.
## ⚠️ Was a `res://assets/…` const. Now composed from the host-injected content root —
## ADR-0202 dec. 5 Class B: a bare project silently got un-seeded defaults rather than an
## error, which is the failure mode dec. 5 names. See `BattlefieldContent`.

## Blend-mode -> IN-SCENE shader. Only the modes that still draw in-scene remain: 0 (average, 50/50 —
## PLACEMENT_UNAVAILABLE) and 4 (opaque, ABE off — SELECTED, the last member since CURSOR_ACTIVE
## left for additive on 2026-09-08). The additive/subtractive ABR modes
## 1/2/3 now ROUTE through the display-space compositor (TileOverlayCompositor) as world_quad decals,
## so their shaders were deleted and a routed type never reaches apply_to_material (Tile.set_highlight_
## type returns early for is_routed). Keyed by blend_mode (a dict, not a dense array) since the routed
## slots no longer exist. Godot's `render_mode blend_*` is compile-time static, so each mode is its own
## shader; apply_to_material() swaps the tile material's `shader`, params persisting across the swap.
const MODE_SHADERS := {
	0: preload("res://addons/exmateria_battlefield/overlay/tile_overlay_mode0.gdshader"),   # average (50/50) — in-scene
	4: preload("res://addons/exmateria_battlefield/overlay/tile_overlay_opaque.gdshader"),  # opaque (ABE off) — in-scene
}

## Emitted whenever any param changes, so live tiles can re-apply.
signal changed


## The live singleton. Created on first touch and parented to `/root`, so its lifetime
## matches the autoload it replaces. It carries ONLY the `changed` signal and the transient
## inspect state; every tunable is bound statically at class load, so nothing here is on the
## boot path. Deferred `add_child` because first touch is typically inside another node's
## `_ready`, where the tree is busy.
static var _inst: TileOverlayConfig = null


static func of() -> TileOverlayConfig:
	if _inst == null or not is_instance_valid(_inst):
		var n := new()
		_inst = n
		n.name = "TileOverlayConfig"
		Engine.get_main_loop().root.add_child.call_deferred(n)
		# Any Tune write to a tile.* slug — a panel scrub, the registry page, a boot-load —
		# must re-apply on live tiles, so bridge Tune.value_changed -> `changed` (the tiles'
		# refresh hook). Connected once per instance, here rather than in _bind_slugs(), so
		# a re-entry into _bind_slugs() does not stack a second bridge.
		TunePort.on_any_change(func(slug: String, _v: Variant) -> void:
			if slug.begins_with("tile.") and _inst != null and is_instance_valid(_inst):
				_inst.changed.emit())
	return _inst

# --- Global params (shared across all types) ----------------------------------

## UV crop into the RANGETILE sheet, in TEXELS. The in-game tile is a small
## sub-rect of the sheet. Each is a Tune tunable (`tile.uv_*`, ADR-0068): the getter
## coalesces the override over the manifest-seeded default; set_global routes writes
## through Tune. The `_*_default` vars are the DEFAULT home — SEEDED from RANGETILE.json's
## `tile_uv` at _ready() (see MANIFEST_PATH); the literals below are only the fallback if
## the manifest can't be read. Tune by eye in the F3 Tiles panel, then re-bake into
## RANGETILE.json (which is the authority, not these).
static var _uv_offset_x_default: float = 0.0
static var _uv_offset_y_default: float = 160.0
static var _uv_size_w_default: float = 14.0
static var _uv_size_h_default: float = 14.0

static var uv_offset_x: float:
	get: return TunePort.get_value("tile.uv_offset_x", _uv_offset_x_default)
	set(v): TunePort.set_value("tile.uv_offset_x", v)
static var uv_offset_y: float:
	get: return TunePort.get_value("tile.uv_offset_y", _uv_offset_y_default)
	set(v): TunePort.set_value("tile.uv_offset_y", v)
static var uv_size_w: float:
	get: return TunePort.get_value("tile.uv_size_w", _uv_size_w_default)
	set(v): TunePort.set_value("tile.uv_size_w", v)
static var uv_size_h: float:
	get: return TunePort.get_value("tile.uv_size_h", _uv_size_h_default)
	set(v): TunePort.set_value("tile.uv_size_h", v)

## Sheet dimensions (texels) used to normalize the crop to [0,1] UV. Seeded from
## RANGETILE.json's `texture_size` so a non-square / resized re-parse stays correct.
static var tex_size: Vector2 = Vector2(TEX_SIZE, TEX_SIZE)

## Debug inspection: freeze the barber-pole on one discrete phase to scrub it.
var paused: bool = false
var scrub_phase: int = 0


# --- Per-type params ----------------------------------------------------------
# Keyed by CellMarking.Kind. Each value is a Dictionary of shader params.
# All five placement highlight types are independently tunable.

static var _types: Dictionary = {}


## Seed + bind at CLASS LOAD, not `_ready()`. The tunable half of this class carries no
## tree state at all — `_types`, `tex_size` and the `_uv_*_default` vars are code defaults
## and a JSON read — so it is static, exactly like SkirtConfig, and ADR-0068 R5's "the
## dashboard enumerates them without a prior read (ADR-0068 R5) survives losing the autoload. Only the
## `changed` signal and the transient `paused`/`scrub_phase` inspect state need `of()`.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	_seed_defaults()
	_load_uv_from_manifest()
	# `register_tunables()`, not `_bind_slugs()` directly: ADR-0173's rule is that a
	# class-load owner calls its NAMED entry point from `_static_init`, so a reader — and
	# `tools/check_tune_owner_self_registration.py` — can see the owner self-register.
	# Calling the helper worked and was invisible, which is the failure that rule exists for.
	register_tunables()


## Register every tile.* slug at boot (ADR-0068 R5), so the uv_* getters and get_param
## PULL-read them via Tune.get_value and the dashboard can enumerate them without a prior
## read. Static so `_static_init` calls it at class load; a test that wants these standing
## after a clear uses `Tune.reset_overrides()` (ADR-0173). Defaults: the manifest-seeded UV vars + the per-type `_types` store (hand-baked via
## the panel's "Print Values", NOT materialize targets, so a per-type bind forwards a
## `_types[type][key]` value rather than an inline literal — deliberate here). Public so a
## test that cleared the registry outright can re-establish the binds by calling it.
static func register_tunables() -> void:
	_bind_slugs()


## Bind every `tile.*` slug from the seeded defaults.
static func _bind_slugs() -> void:
	TunePort.bind("tile.uv_offset_x", _uv_offset_x_default)
	TunePort.bind("tile.uv_offset_y", _uv_offset_y_default)
	TunePort.bind("tile.uv_size_w", _uv_size_w_default)
	TunePort.bind("tile.uv_size_h", _uv_size_h_default)
	for type: int in _types:
		var params: Dictionary = _types[type]
		for key: String in params:
			TunePort.bind(param_slug(type, key), params[key])


## Seed the UV crop + sheet dims from RANGETILE.json (the parse_range_tiles.py
## output), so the runtime tracks the atlas layout instead of duplicating it as
## hardcoded constants. Leaves the fallbacks in place if the manifest is absent.
static func _load_uv_from_manifest() -> void:
	var manifest_path: String = BattlefieldContent.range_manifest_path()
	if manifest_path.is_empty():
		return   # `BattlefieldContent.resolve` already reported the unset root, once
	if not FileAccess.file_exists(manifest_path):
		push_warning("TileOverlayConfig: %s missing — using fallback tile UV crop (run tools/parse_range_tiles.py)" % manifest_path)
		return
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("TileOverlayConfig: %s unreadable — using fallback tile UV crop" % manifest_path)
		return
	var data: Dictionary = json.data
	var uv: Dictionary = data.get("tile_uv", {})
	if uv.has("x") and uv.has("y") and uv.has("w") and uv.has("h"):
		# Seed the DEFAULTS (not the Tune-backed properties — a manifest value is the
		# code default, not a committed override).
		_uv_offset_x_default = float(uv["x"])
		_uv_offset_y_default = float(uv["y"])
		_uv_size_w_default = float(uv["w"])
		_uv_size_h_default = float(uv["h"])
	var ts: Array = data.get("texture_size", [])
	if ts.size() == 2 and float(ts[0]) > 0.0 and float(ts[1]) > 0.0:
		tex_size = Vector2(float(ts[0]), float(ts[1]))


## Seed the shippable per-type defaults — dialed in via the F3 Tiles panel and
## baked here (Print Values). All flat-fill barber-pole; `tint` is the per-primitive
## modulation color, `mono` collapses the CLUT shade to brightness so the tint is
## the only hue (used to fake colors we have no real CLUT for).
static func _seed_defaults() -> void:
	_types = {
		CellMarking.Kind.PLACEMENT_PLAYER: _params(0, true, 1, 1, Color("17e600"), false, 10.0),
		CellMarking.Kind.PLACEMENT_ENEMY: _params(1, true, 1, 1, Color("ad0015"), false, 10.0),
		# ADDITIVE (blend 1), and ROUTED — 2026-09-08. The ROM draws the range/cursor tile
		# panels with a literal tpage 0x3F (FUN_8007DB1C), whose ABR field decodes to mode 1 =
		# additive; the old blend 4 (opaque) was a port choice that was never parity, and it
		# painted OVER the unit shadow overlapping the tile. It is the one routed type with
		# flat_fill = false, so it folds through TileOverlayCompositor's TEXTURED carrier
		# (tile_overlay_add_fold.gdshader) rather than the batched flat-colour one.
		CellMarking.Kind.CURSOR_ACTIVE: _params(0, false, 1, 1, Color("ffffff"), false, 10.0, 1.3),
		CellMarking.Kind.PLACEMENT_UNAVAILABLE: _params(1, true, 1, 0, Color("8a7028"), true, 16.5),
		# The cursor's own shape, dimmed: same palette row, same clock — it reads as the trail
		# the cursor left rather than as a new kind of thing. It KEEPS blend 4, so it is now the
		# only opaque overlay and the last in-scene user of tile_overlay_opaque.gdshader:
		# CURSOR_ACTIVE went additive + routed on 2026-09-08 and SELECTED deliberately did not
		# follow it. Nothing OVERLAPS a selected tile the way a unit's shadow overlaps the
		# cursored one, so it has no blend-order to get wrong and no reason to pay for a carrier.
		CellMarking.Kind.SELECTED: _params(0, false, 1, 4, Color("8c8c8c"), false, 10.0, 1.3),
	}


## Build a per-type param dict. `palette_row` 0..8 (BATTLE.BIN slot N —
## 0=blue, 1=red, 3=yellowA, 4=cursor, 8=yellowB; others unnamed);
## `flat_fill` textured-sheet vs uniform fill; `anim_mode` 0 static / 1 barber-pole;
## `blend_mode` 0 average / 1 additive / 2 subtractive / 3 additive-1/4 / 4 opaque
## (selects the shader, see MODE_SHADERS); `tint` per-primitive modulation color;
## `mono` collapse the CLUT shade to brightness so `tint` is the only hue (fakes a
## color we have no real CLUT for); `phase_rate` CLUT-rotation speed (phases/sec).
static func _params(palette_row: int, flat_fill: bool, anim_mode: int, blend_mode: int, tint: Color, mono: bool = false, phase_rate: float = 16.5, srgb_gamma: float = 2.2) -> Dictionary:
	return {
		"palette_row": palette_row,
		"flat_fill": flat_fill,
		"anim_mode": anim_mode,
		"blend_mode": blend_mode,
		"tint": tint,
		"mono": mono,
		"phase_rate": phase_rate,  # CLUT-rotation speed in phases/sec
		"flat_index": 2,           # fixed CLUT hue for flat tiles
		"srgb_gamma": srgb_gamma,  # palette linearization exponent (per-type; 2.2 legacy)
	}


# --- Access ------------------------------------------------------------------
# STATIC below: schema + Tune-backed values, no tree state. INSTANCE further down:
# `changed`, `paused`/`scrub_phase` and the two functions that read them. The split is
# ADR-0183 dec. 3 — one concern, two lifetimes.
# --- (was) Access -------------------------------------------------------------------

## Ordered list of the five tunable highlight types (panel iteration order).
static func tunable_types() -> Array:
	return [
		CellMarking.Kind.PLACEMENT_PLAYER,
		CellMarking.Kind.PLACEMENT_ENEMY,
		CellMarking.Kind.CURSOR_ACTIVE,
		CellMarking.Kind.PLACEMENT_UNAVAILABLE,
		CellMarking.Kind.SELECTED,
	]


## Human-readable label for a highlight type (panel + Print Values).
static func type_label(type: int) -> String:
	match type:
		CellMarking.Kind.PLACEMENT_PLAYER: return "Friendly"
		CellMarking.Kind.PLACEMENT_ENEMY: return "Enemy"
		CellMarking.Kind.CURSOR_ACTIVE: return "Active Cursor"
		CellMarking.Kind.PLACEMENT_UNAVAILABLE: return "Unavailable"
		CellMarking.Kind.SELECTED: return "Selected"
	return "Type %d" % type


## GDScript enum-key name for a type (for Print Values output).
##
## 🔴 `find_key`, NOT `keys()[type]`. The old spelling indexed the NAMES array by the
## VALUE, which is only correct while the enum is densely numbered — and `Kind` has a
## hole at 3 since ADR-0258 retired `PLACEMENT_CONTESTED`. Under the old spelling every
## member above the hole would have resolved to its neighbour's name, silently, and the
## slug below would have re-pointed each surviving tunable at the wrong marking.
static func type_enum_name(type: int) -> String:
	return "CellMarking.Kind.%s" % CellMarking.Kind.find_key(type)


## The `tile.<type>.<key>` Tune slug for a per-type param (ADR-0068).
static func param_slug(type: int, key: String) -> String:
	return "tile.%s.%s" % [str(CellMarking.Kind.find_key(type)).to_lower(), key]


## Coalesce a per-type param's Tune override over its seeded default. The `_types`
## dict is the DEFAULT store now; the live value is override-over-default. Returns
## `default` verbatim for an unknown type/key (no slug registered).
static func get_param(type: int, key: String, default = null):
	var p: Dictionary = _types.get(type, {})
	if not p.has(key):
		return default
	return TunePort.get_value(param_slug(type, key), p[key])


## Set one per-type param — routes through Tune so it persists + shows in the registry.
## The Tune.value_changed→changed bridge (see _ready) notifies live tiles to re-apply.
static func set_param(type: int, key: String, value) -> void:
	if not _types.has(type):
		return
	TunePort.set_value(param_slug(type, key), value)


## Set a global param by name and notify listeners.
func set_global(key: String, value) -> void:
	set(key, value)
	changed.emit()


## The shader's manual_phase: a frozen phase while paused, else -1 (animate).
func manual_phase() -> int:
	return scrub_phase if paused else -1


# --- Application --------------------------------------------------------------

## Push every param (per-type + global) onto a tile's ShaderMaterial. Called by
## Tile.set_highlight_type() and on every live `changed` refresh.
func apply_to_material(mat: ShaderMaterial, type: int) -> void:
	if mat == null:
		return
	# Resolve the type (fall back to PLACEMENT_PLAYER) then read each param Tune-coalesced.
	var rtype: int = type if _types.has(type) else CellMarking.Kind.PLACEMENT_PLAYER
	# PSX ABR blend mode = which shader (render_mode is compile-time static). Swap
	# only when it actually changes; params persist by uniform name across the swap.
	# Routed additive modes (1/2/3) never reach here — Tile routes them to the compositor. For the
	# in-scene modes (0 average / 4 opaque) pick the shader; fall back to opaque defensively.
	var bm: int = int(get_param(rtype, "blend_mode"))
	var shader: Shader = MODE_SHADERS.get(bm, MODE_SHADERS[4])
	if mat.shader != shader:
		mat.shader = shader
	apply_params_to_material(mat, rtype)


## The uniform half of apply_to_material — every per-type + global param, and NO shader swap.
## Split out for the ROUTED textured carrier (TileOverlayCompositor's cursor carrier), which
## wears the monomorphic `tile_overlay_add_fold` shader: MODE_SHADERS holds only the IN-SCENE
## shaders, so calling the full apply_to_material there would swap the fold shader away and the
## carrier would silently stop folding. Takes an already-resolved type.
func apply_params_to_material(mat: ShaderMaterial, rtype: int) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("palette_row", get_param(rtype, "palette_row"))
	mat.set_shader_parameter("flat_fill", get_param(rtype, "flat_fill"))
	mat.set_shader_parameter("anim_mode", get_param(rtype, "anim_mode"))
	mat.set_shader_parameter("tint", get_param(rtype, "tint"))
	mat.set_shader_parameter("mono", get_param(rtype, "mono"))
	mat.set_shader_parameter("phase_rate", get_param(rtype, "phase_rate"))
	mat.set_shader_parameter("flat_index", get_param(rtype, "flat_index"))
	# Global UV crop (texels -> normalized UV) + inspection knobs.
	mat.set_shader_parameter("tile_uv_offset", Vector2(uv_offset_x, uv_offset_y) / tex_size)
	mat.set_shader_parameter("tile_uv_size", Vector2(uv_size_w, uv_size_h) / tex_size)
	mat.set_shader_parameter("manual_phase", manual_phase())
	mat.set_shader_parameter("srgb_gamma", get_param(rtype, "srgb_gamma"))


## Emit GDScript that reproduces the current config — paste into _seed_defaults()
## and update RANGETILE.json's tile_uv with the crop. (Panel "Print Values".)
static func print_values() -> void:
	print("")
	print("=".repeat(60))
	print("# TileOverlayConfig — paste into _seed_defaults()")
	print("=".repeat(60))
	for type in tunable_types():
		var c: Color = get_param(type, "tint")
		print("%s: _params(%d, %s, %d, %d, Color(\"%s\"), %s, %.1f, %.2f),  # flat_index=%d" % [
			type_enum_name(type), get_param(type, "palette_row"), get_param(type, "flat_fill"),
			get_param(type, "anim_mode"), get_param(type, "blend_mode"),
			c.to_html(false), get_param(type, "mono"), get_param(type, "phase_rate"),
			get_param(type, "srgb_gamma"), get_param(type, "flat_index")])
	print("# Global:")
	print("uv_offset_x=%.2f  uv_offset_y=%.2f  uv_size_w=%.2f  uv_size_h=%.2f" % [
		uv_offset_x, uv_offset_y, uv_size_w, uv_size_h])
	print("# -> RANGETILE.json tile_uv: {\"x\": %d, \"y\": %d, \"w\": %d, \"h\": %d}" % [
		int(round(uv_offset_x)), int(round(uv_offset_y)), int(round(uv_size_w)), int(round(uv_size_h))])
	print("=".repeat(60))
	print("")
