@tool
extends Node

## Manages sprite layers and shader parameters for multi-layer sprite rendering
## Handles type1 (base character), wep1 (weapon), eff1 (effects)
## Vault: [[Cinematic Palette Pipeline]]
## Vault: [[Damage Number Popup System]]
## Vault: [[EVTCHR CLUT Resolution]]
## Vault: [[EVTCHR Frame Resolution]]
## Vault: [[Unit Sprite Render Pipeline]]

# ADR-0212 dec. 1 — the class is INTERNAL to this addon: no global `class_name`,
# so an in-addon consumer preloads the file it wants.
const UnitAnimationSet = preload("res://addons/exmateria_sprite_rig/sequence/UnitAnimationSet.gd")

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the three composed layers are a VALUE SET
## and are now the kernel's; this 888-line Node keeps its class name and all of its
## behaviour and names the kernel for its own control flow. `SpriteLayer`, not the
## bare word: `addons/exmateria_schema/colour_model/ColorStack.gd` already declares
## `class Layer`, so the bare spelling collided inside the destination.
const RigDebug = preload("res://addons/exmateria_sprite_rig/install/RigDebug.gd")
const SpriteLayer = ExMateriaSchema.SpriteLayer.Kind

## `ContentPort` is `addons/exmateria_sprite_rig`'s, published on the addon's one
## global name; this aliases it back so the call sites below stay a verb rather
## than a façade walk (ADR-0211 dec. 4, ADR-0217 dec. 9). The port replaces a
## direct name for a host content store: this file no longer compiles against one.
const ContentPort = ExMateriaSpriteRig.ContentPort

## 🔴 `TunePort`, NOT `Tune` (#847). `Tune` is `res://src/core/Tune.gd`, a HOST
## autoload, and an `[autoload]` line can only be written by the consuming game:
## naming it here made this file fail to parse in a project that did not declare
## it, which `tests/stranger/exmateria_sprite_rig/` measured as a compile error
## and `check_addon_portability.py` arm 2 had already printed as standalone-parse
## debt. `ExMateriaPlatform.TunePort` is the port ADR-0175 dec. 2 built for exactly
## this, with a DEFINED ABSENT BEHAVIOUR per verb; `install/RigDebug.gd` and
## `addons/exmateria_battlefield/terrain/SkirtConfig.gd` are the precedents for
## both the alias and the two call shapes below.
##
## The alias spelling is load-bearing beyond taste: `tools/materialize_tunables.py`'s
## `CALLS` table keys on `TunePort.bind`, so the fully-qualified
## `ExMateriaPlatform.TunePort.bind` would go QUIET rather than red in R6's codemod
## (the companion-change rule ADR-0151 set, and TunePort's own docstring names it).
const TunePort = ExMateriaPlatform.TunePort

const LAYER_NAMES: Dictionary = {
	SpriteLayer.TYPE1: "type1",
	SpriteLayer.WEP1: "wep1",
	SpriteLayer.EFF1: "eff1",
}

# Shader material reference (set by parent)
var material: ShaderMaterial

# Sprite layer data — held by reference (ADR-0034). The UnitAnimationSet
# already TYPE2-resolves `wep_shp`, so this manager no longer carries its
# own copies of type1_shp/wep1_shp/wep2_shp/uses_wep2.
var anims: UnitAnimationSet

# Composed whole-sprite flip actually bound to the shader (`global_reversion`).
# PSX mirror: the flip word `unit_sprite_render_dispatch` hands the packet builder
# is `render_flags(+0x12) ^ flip_xor_mask(+0x13F)` (`xor` @0x80086764 — see
# `research/working_documents/MIRROR_SPRITE_OPCODE_68.md` §2.2). Keep the two
# halves separate so neither can clobber the other; `_push_reversion` recomposes.
var apply_reversion: bool = false

# The facing/camera-derived half — PSX `unit[+0x12]` render_flags bit 1. Written
# every paint by whoever resolved the camera variant (UnitDisplay's painters, the
# scenario VM's cinematic walker).
var _base_reversion: bool = false

# The persistent per-unit half — PSX `unit[+0x13F]` flip_xor_mask, latched by event
# opcode {68} Mirror Sprite (`Mirror=1` -> 0x02, `Mirror=0` -> 0x00) and zeroed at
# unit-add. It XORs with `_base_reversion` rather than overriding it, so a mirrored
# unit stays mirrored as its facing/camera flip is recomputed each frame.
var mirror_xor: bool = false

# Constants
const SPRITE_CENTER_OFFSET_X: float = 100.0
const SPRITE_CENTER_OFFSET_Y: float = 100.0

# Single source of truth for the sprite-layer centering (`shared_loc_offset`),
# per ADR-0036's no-"third-home" principle. It CANNOT live in project.godot
# `[shader_globals]` like `pixel_aspect`/`unit_stretch` because it is mutated
# per-unit at runtime (Unit._on_move_offset_changed adds the movement pixel
# offset), which a `global uniform` can't express — so the one home is this
# shared slot. Unit applies it to the material at init; both scenario debug panels
# read it as their base. X=27 is the flip-relative centering (see
# research/working_documents/EVTCHR_FRAME_RESOLUTION.md).
#
# A `static var` (not a `const`) is the tunable HOME for `render.loc_offset`
# (ADR-0068 R1): a `const` is frozen at parse time, so a scrub could never
# reach its direct readers; a `static` is the single SHARED slot every reader hits,
# so a scrub is seen structurally. Its initializer is the materializable literal.
static var shared_loc_offset := Vector2(27.0, 26.0)

# OT depth sample point (ADR-0009): the unit billboard samples its flat depth at
# the body sprite's VISUAL CENTER, not its feet, so it sorts fairly against wall
# mid-height centroids. We derive the center from the body (TYPE1) pieces instead
# of a magic constant, so it auto-scales for taller monster sprites.
# Mapping (traced from unit.gdshader): a body pixel at center_loc_y maps to a
# world-Y offset above the mesh origin of DEPTH_CENTER_BIAS - center_loc_y/DEPTH_CENTER_DIV,
# from 8*(0.5 - (center_loc_y + loc_offset.y + shared.y)/256). Tunable if a sprite
# set sits visibly wrong; verify in-game (units vs walls).
const DEPTH_CENTER_DIV: float = 32.0
const DEPTH_CENTER_BIAS: float = 0.0625

# Live up/down tuning offset (world units) added to the derived center. Owned by
# Tune as `render.center_bias` (ADR-0068 move 2) and re-read at the use-site each
# depth update, so one knob moves all units live in any scene — no static to fan out
# from a panel. 0 = pure derived.
const CENTER_BIAS_SLUG := "render.center_bias"
## A `static var` (not `const`) so it is the materializable home the bind's follower can
## rewrite (ADR-0068 R1) — a `const` is frozen at parse time and a scrub can never reach it.
static var CENTER_BIAS_DEFAULT := 0.0
## The tuning range/step — the SINGLE home for center_bias's hint (ADR-0068 move 3), so the
## pure view reads min/max/step back from the registry instead of declaring a rival that drifts.
## (Was split across the owner's inline bind AND the panel's _BIAS_HINT; this is the panel's
## displayed range, kept so the control's headroom is unchanged.)
const CENTER_BIAS_HINT := {"min": -3.0, "max": 3.0, "step": 0.05}


## Register `render.center_bias` ONCE at class load (ADR-0068 R2) so `_update_depth_center`
## can pull-read it via Tune.get_value and the dashboard can enumerate it before any sprite
## exists. Editor-guarded like Unit._static_init — SpriteLayerManager is @tool and Tune is a
## non-@tool placeholder in the editor.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## The center_bias bind, split out from _static_init as this owner's named registration entry
## point (ADR-0173): _static_init calls it at class load — the ONLY thing that does — and the
## guards call it to read back which slugs this owner binds. Editor-guarded by the caller.
static func register_tunables() -> void:
	TunePort.bind(CENTER_BIAS_SLUG, CENTER_BIAS_DEFAULT, CENTER_BIAS_HINT)

# Per-frame cache of the derived body-sprite center (loc_x, loc_y), keyed by a
# frame signature. The center is a pure function of the frame's tile geometry +
# the bound atlas pixels, so we compute the (expensive) non-transparent pixel
# scan once per distinct frame and reuse it. Keyed per-instance (each unit has
# its own SpriteLayerManager, so the atlas identity is stable within the key).
var _center_cache: Dictionary = {}
# Decoded atlas images, keyed by resource_path, so we read each atlas TGA once.
var _atlas_image_cache: Dictionary = {}

func initialize(anim_set: UnitAnimationSet, shader_material: ShaderMaterial) -> void:
	"""Initialize with animation set and shader material"""
	material = shader_material
	anims = anim_set
	if Engine.is_editor_hint():
		return
	RigDebug.log_animation("SpriteLayerManager initialized with %d frames (is_type2=%s)" % [anims.type1_shp.size(), anims.is_type2])

func set_global_reversion(reversion: bool) -> void:
	"""Set the facing/camera-derived half of the whole-sprite flip.

	This is PSX `unit[+0x12]` render_flags bit 1 — recomputed from (camera yaw +
	unit facing) on every paint. It is NOT the final flip: {68} Mirror Sprite's
	`mirror_xor` is XORed in by `_push_reversion`."""
	_base_reversion = reversion
	_push_reversion()


func set_mirror_xor(mirrored: bool) -> void:
	"""{68} Mirror Sprite: latch the persistent per-unit flip XOR delta.

	PSX `unit[+0x13F]` (`unit_set_flip_xor_mask` @0x8008CC50 writes 0x02,
	`unit_clear_flip_xor_mask` @0x8008CC80 writes 0x00). Survives every
	subsequent `set_global_reversion` because the two compose by XOR, which is
	exactly why the ROM keeps them in separate fields."""
	mirror_xor = mirrored
	_push_reversion()


func _push_reversion() -> void:
	"""Recompose the flip and bind it. Mirrors the ROM's single XOR site."""
	apply_reversion = _base_reversion != mirror_xor
	if material:
		material.set_shader_parameter("global_reversion", apply_reversion)

func enable_layer(layer: SpriteLayer, enabled: bool) -> void:
	"""Enable or disable a sprite layer"""
	if layer == SpriteLayer.WEP1:
		material.set_shader_parameter("wep_enable", enabled)
	elif layer == SpriteLayer.EFF1:
		material.set_shader_parameter("eff_enable", enabled)

## ADR-0022: BODY palette row uniform — picks which row of the per-sprite
## palette table the BODY shader looks up at runtime. Default 0 matches
## humanoid sprites' default-color baked palette. Monster jobs set this
## from jobs.json's body_palette_row (Yellow Chocobo=0, Black=1, Red=2).
func set_body_palette_row(row: int) -> void:
	if material:
		material.set_shader_parameter("body_palette_row", row)

## Per-item WEP1 / EFF1 palette rows (BATTLE.BIN 0x2d3e4). Set after
## load_weapon_texture from the WEP1 graphic table's per-item palette fields /
## get_eff1_palette(item_id). 0 = sword/default baseline; non-zero rows give
## per-weapon held-sprite + effect-overlay colors.
func set_wep1_palette_row(row: int) -> void:
	if material:
		material.set_shader_parameter("wep1_palette_row", row)

func set_eff1_palette_row(row: int) -> void:
	if material:
		material.set_shader_parameter("eff1_palette_row", row)

const ContentRoot = preload("res://addons/exmateria_sprite_rig/install/SpriteRigContentRoot.gd")

# Cached weapon / effect textures (shared across all units — same source pixels)
static var _wep1_texture: Texture2D = null
static var _wep1_palette: Texture2D = null
static var _eff1_texture: Texture2D = null
static var _eff1_palette: Texture2D = null


# Per-unit weapon v_offset (Y pixels to add to wep1 tile coordinates)
# Different weapons within the same type have sprites arranged vertically.
# This offset selects the correct variant (e.g., Broad Sword vs Mythril Sword).
var wep1_v_offset_pixels: int = 0


func load_weapon_texture(item_type_id: int = 0, item_id: int = 0) -> bool:
	"""Load the WEP1 (weapon) texture for weapon sprite rendering.

	The weapon texture is shared across all units since WEP1.tga contains
	all weapon graphics. Each unit stores its own v_offset for variant selection.

	Args:
		item_type_id: Item type id from ItemDatabase (Knife=1, Sword=3, Rod=7, ...) —
		              used elsewhere for SHP zero_frame selection; informational here.
		item_id: ROM item id (0..0x7F weapon, 0x80..0x8F shield). Keys into
		         BATTLE.BIN's per-item battle-graphic table at 0x2d3e4 to fetch
		         the pixel-y offset into WEP1.tga.

	Returns:
		true if texture loaded successfully, false otherwise
	"""
	if not material:
		push_error("[SpriteLayerManager] Cannot load weapon texture - material not initialized")
		return false

	# Load WEP1 + EFF1 textures and palette companions (cached across all units).
	# WEP1.tga and EFF1.tga are indexed-grayscale (idx*17 in R/G/B); the .palette.tga
	# companions are 16x16 RGBA. The shader does the row lookup at fragment time —
	# the row uniforms come from BATTLE.BIN's per-item table (X nibble = WEP1 row,
	# Y nibble = EFF1 row). See set_wep1_palette_row / set_eff1_palette_row below.
	if not _wep1_texture:
		_wep1_texture = ResourceLoader.load(ContentRoot.resolve(ContentRoot.WEP1_TEX_SUBPATH), "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if not _wep1_texture:
			push_error("[SpriteLayerManager] Failed to load weapon texture: %s" % ContentRoot.resolve(ContentRoot.WEP1_TEX_SUBPATH))
			return false
	if not _wep1_palette:
		_wep1_palette = ResourceLoader.load(ContentRoot.resolve(ContentRoot.WEP1_PALETTE_SUBPATH), "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if not _wep1_palette:
			push_warning("[SpriteLayerManager] Missing WEP1 palette companion: %s" % ContentRoot.resolve(ContentRoot.WEP1_PALETTE_SUBPATH))
	if not _eff1_texture:
		_eff1_texture = ResourceLoader.load(ContentRoot.resolve(ContentRoot.EFF1_TEX_SUBPATH), "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if not _eff1_texture:
			push_warning("[SpriteLayerManager] Missing EFF1 texture: %s" % ContentRoot.resolve(ContentRoot.EFF1_TEX_SUBPATH))
	if not _eff1_palette:
		_eff1_palette = ResourceLoader.load(ContentRoot.resolve(ContentRoot.EFF1_PALETTE_SUBPATH), "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if not _eff1_palette:
			push_warning("[SpriteLayerManager] Missing EFF1 palette companion: %s" % ContentRoot.resolve(ContentRoot.EFF1_PALETTE_SUBPATH))

	# WEP1.tga holds all weapon graphics stacked vertically. The per-item
	# vertical offset comes from BATTLE.BIN's per-item battle-graphic table at
	# 0x2d3e4 (parsed by `tools/parse_weapon_graphic_data.py`). The table is
	# keyed by ROM **item id**, NOT items.json.graphic (which is the menu-icon
	# index — a separate concept). Wrong key samples the wrong row of WEP1.tga.
	wep1_v_offset_pixels = ContentPort.weapon_v_offset(item_id)

	# Update shader parameters
	material.set_shader_parameter("wep1_tex", _wep1_texture)
	material.set_shader_parameter("wep1_tex_size", _wep1_texture.get_size())
	if _wep1_palette:
		material.set_shader_parameter("wep1_palette", _wep1_palette)
	if _eff1_texture:
		material.set_shader_parameter("eff1_tex", _eff1_texture)
		material.set_shader_parameter("eff1_tex_size", _eff1_texture.get_size())
	if _eff1_palette:
		material.set_shader_parameter("eff1_palette", _eff1_palette)

	if not Engine.is_editor_hint():
		RigDebug.log_animation("Loaded weapon texture (size: %s, item_type: %d, item_id: %d, v_offset: %d)" % [
				_wep1_texture.get_size(), item_type_id, item_id, wep1_v_offset_pixels])

	return true


func load_body_sprite(template_folder: String, flat_texture_path: String) -> bool:
	"""Load the BODY sprite, preferring a unit's template folder (ADR-0072 #203).

	The folder-fronting entry the resolver seam feeds: `template_folder` is the
	resolved unique's owned folder (`ResidueManifest.folder_of`, "" for a
	job-routed generic); `flat_texture_path` is the sprite_id-derived path the
	flat pipeline built. When the folder holds a `body.tga`, load it — its
	`body.palette.tga` companion resolves by basename exactly like the flat path,
	because the folder body is a byte-identical copy of the flat sheet. Otherwise
	degrade to the flat store.

	The fallback is **load-bearing**: template folders are generated + gitignored
	(#200), so a unit may resolve to a folder that has not been emitted yet — the
	loader degrades, it never errors on a missing folder.
	"""
	if not template_folder.is_empty():
		var body_path := template_folder + "body.tga"
		if ResourceLoader.exists(body_path):
			return load_sprite_texture(body_path)
	return load_sprite_texture(flat_texture_path)


## Bind ALREADY-LOADED body + palette textures directly (no disk IO). The exact
## shader-param writes `load_sprite_texture` performs on success, minus the load —
## for a caller that holds the texture objects itself (the formation view caches the
## per-folder body sheet so a scroll re-show is a map hit, not a forced re-decode).
## `palette_tex` may be null (mirrors the non-fatal missing-palette path). Immutable
## sheets only: the caller owns invalidation.
func set_body_textures(body_tex: Texture2D, palette_tex: Texture2D) -> void:
	if not material or body_tex == null:
		return
	material.set_shader_parameter("type1_tex", body_tex)
	material.set_shader_parameter("type1_tex_size", body_tex.get_size())
	if palette_tex != null:
		material.set_shader_parameter("type1_palette", palette_tex)


func load_sprite_texture(texture_path: String) -> bool:
	"""Load a new sprite texture for the type1 (character) layer.

	Supports .png, .tga, and other Godot-loadable image formats.
	The texture size is automatically updated for the shader.
	Automatically searches in generated/ subdirectory and tries .tga extension.

	Args:
		texture_path: a resolved resource path, e.g. the content root's
			"sprites/textures/01.tga". (This example named "assets/sprites/02.png"
			until #744; no such file has ever existed — ADR-0215 corrects it.)

	Returns:
		true if texture loaded successfully, false otherwise
	"""
	if not material:
		push_error("[SpriteLayerManager] Cannot load texture - material not initialized")
		return false

	var actual_path = _resolve_sprite_texture_path(texture_path)
	if actual_path.is_empty():
		push_error("[SpriteLayerManager] Body sprite texture not found: %s — binding magenta-checker fallback so the unit is visibly broken in-scene instead of silently transparent" % texture_path)
		_bind_fallback_body_texture()
		return false

	# Force reload to avoid cache issues when changing sprite IDs
	var texture = ResourceLoader.load(actual_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if not texture:
		push_error("[SpriteLayerManager] Failed to load body sprite texture: %s — binding magenta-checker fallback" % actual_path)
		_bind_fallback_body_texture()
		return false

	# Update shader parameters
	material.set_shader_parameter("type1_tex", texture)
	material.set_shader_parameter("type1_tex_size", texture.get_size())

	# ADR-0022: BODY layer is paletted. Load the companion .palette.tga that
	# extract_spr_indexed emits alongside the indexed texture. Failure to
	# load is non-fatal — the shader will sample a default palette texture
	# (transparent) and the BODY layer will render as transparent rather
	# than wrong colors.
	var palette_path = actual_path.get_basename() + ".palette.tga"
	var palette_texture = ResourceLoader.load(palette_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if palette_texture:
		material.set_shader_parameter("type1_palette", palette_texture)
	else:
		push_warning("[SpriteLayerManager] Palette companion not found: %s" % palette_path)

	if not Engine.is_editor_hint():
		RigDebug.log_animation("Loaded sprite texture: %s (size: %s)" % [actual_path, texture.get_size()])

	return true


# Magenta-checker fallback for invalid body sprite IDs (ADR-0027). When the
# requested NN.tga doesn't resolve, we bind these instead of leaving the BODY
# layer unbound — silent transparent rendering hid two missing-sprite bugs
# (00.tga default + missing trap textures) before this safety net existed.
static var _fallback_indexed_tex: Texture2D = null
static var _fallback_palette_tex: Texture2D = null


static func _get_fallback_indexed_texture() -> Texture2D:
	"""4x4 indexed-grayscale where every pixel is palette index 1 (R = 1*17)."""
	if _fallback_indexed_tex:
		return _fallback_indexed_tex
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(17.0 / 255.0, 17.0 / 255.0, 17.0 / 255.0, 1.0))
	_fallback_indexed_tex = ImageTexture.create_from_image(img)
	return _fallback_indexed_tex


static func _get_fallback_palette_texture() -> Texture2D:
	"""16x16 palette table where index 1 of every row is opaque magenta;
	other indices are fully transparent. Paired with the fallback indexed
	texture, the shader's palette lookup lands on magenta regardless of
	the body_palette_row uniform."""
	if _fallback_palette_tex:
		return _fallback_palette_tex
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			if x == 1:
				img.set_pixel(x, y, Color(1.0, 0.0, 1.0, 1.0))
			else:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	_fallback_palette_tex = ImageTexture.create_from_image(img)
	return _fallback_palette_tex


func _bind_fallback_body_texture() -> void:
	"""Bind the magenta-checker fallback on the BODY layer's material so the
	unit renders as a visibly-broken magenta blob instead of silent transparency."""
	if not material:
		return
	var indexed = _get_fallback_indexed_texture()
	var palette = _get_fallback_palette_texture()
	material.set_shader_parameter("type1_tex", indexed)
	material.set_shader_parameter("type1_tex_size", indexed.get_size())
	material.set_shader_parameter("type1_palette", palette)


func _resolve_sprite_texture_path(input_path: String) -> String:
	"""Resolve sprite texture path, trying multiple locations and extensions.

	Search order:
	1. Input path as-is
	2. Input path with .tga extension
	3. Input path in generated/ subdirectory
	4. Input path in generated/ with .tga extension

	Returns: Valid resource path or empty string if not found
	"""
	# Paths to try in order of preference
	var paths_to_try: Array[String] = []

	# Get base filename without extension
	var base_path = input_path
	var extension = input_path.get_extension()
	if not extension.is_empty():
		base_path = input_path.substr(0, input_path.length() - extension.length() - 1)

	# Try direct paths
	paths_to_try.append(input_path)
	if extension != "tga":
		paths_to_try.append(base_path + ".tga")

	# Try in textures/ subdirectory
	var generated_base = base_path.replace("assets/sprites/", "assets/sprites/textures/")
	paths_to_try.append(generated_base + "." + extension)
	if extension != "tga":
		paths_to_try.append(generated_base + ".tga")

	# Find first existing path
	for path in paths_to_try:
		if ResourceLoader.exists(path):
			return path

	return ""

func _get_shp_data(layer: SpriteLayer) -> Dictionary:
	"""Get shape data for layer. `anims.wep_shp` is already TYPE2-resolved
	by the database (ADR-0034); no branching here.

	Both WEP1 and WEP2 use the same texture (WEP1.tga); the SHP layout
	(timing / piece placement) differs.
	"""
	if not anims:
		return {}
	match layer:
		SpriteLayer.TYPE1: return anims.type1_shp
		SpriteLayer.WEP1: return anims.wep_shp
		SpriteLayer.EFF1: return anims.eff1_shp
		_: return {}


# Causal-timeline tracer for the EVTCHR wrong-row detector
# (HANDOFF_ramza_wrong_sprite_detector.md Task 2). Records every BODY-layer
# rect write — `source` is "cinematic" (load_cinematic_frame) or "type1"
# (load_frame_by_id) — tagged with the owning Unit's name and the currently
# bound `type1_tex` atlas basename. The smoking-gun flip the fix author is
# hunting is `(cinematic, …, segment_000)` → `(type1, <idle>, y≈0, segment_000)`:
# a TYPE1 idle frame written while the EVTCHR atlas is still bound. Gated behind
# the detector flag so it costs nothing in normal play.
func _trace_body_rect_write(source: String, frame_id: int, rects: Array) -> void:
	if not RigDebug.evtchr_row_detect():
		return
	var min_y := INF
	for r in rects:
		min_y = min(min_y, (r as Vector2).y)
	var atlas := "<none>"
	if material:
		var tex := material.get_shader_parameter("type1_tex") as Texture2D
		if tex != null and not tex.resource_path.is_empty():
			atlas = tex.resource_path.get_file()
	var owner_name: String = String(get_parent().name) if get_parent() != null else "<orphan>"
	print("[EVTCHR-TL] unit=%s source=%s frame_id=0x%02X rect_y=%s atlas=%s" % [
		owner_name, source, frame_id, str(min_y), atlas])


func load_frame_by_id(layer: SpriteLayer, frame_id: int, is_first_frame: bool = false) -> void:
	"""Load sprite frame by frame ID directly (for new AnimationPlayback system).

	Args:
		layer: which SpriteLayer to load (SpriteLayer.TYPE1, SpriteLayer.WEP1, SpriteLayer.EFF1)
		frame_id: Frame ID to display (from AnimationFrameCalculator)
		is_first_frame: If true, disables wep1/eff1 layers (for type1 layer start)
	"""
	# Invariant: a normal SHP body frame must never sample a stale EVTCHR atlas.
	# A cinematic Unit Anim binds the BODY layer to an EVTCHR segment via
	# enter_cinematic_mode; its walker only restores the unit's own SPR when a
	# `< 0xD2` (TYPE1) byte appears mid-anim. The chapel cinematic anims
	# (e.g. Ramza's 0x261: LoadFrame 0xF1→0xF2→PauseAnimation) drain WITHOUT
	# such a byte, then the chunk's next `Walk To` arms a normal walk animation
	# whose SHP frame would index into the still-bound EVTCHR page — the
	# "row 1 instead of row 5" bug. Rebind the own atlas first; no-op when not
	# in cinematic mode. (HANDOFF_ramza_wrong_sprite_detector.md fix.)
	if layer == SpriteLayer.TYPE1:
		exit_cinematic_mode()

	var shp_data = _get_shp_data(layer)
	var layer_name: String = LAYER_NAMES[layer]
	if shp_data.is_empty():
		push_error("SpriteLayerManager: Invalid layer '%s'" % layer_name)
		return

	var frame_key = str(frame_id)
	var is_wep2 = (layer == SpriteLayer.WEP1 and anims and anims.is_type2)
	if not shp_data.has(frame_key):
		push_warning("SpriteLayerManager: Frame %d not found in %s (wep2=%s, shp_size=%d)" % [frame_id, layer_name, is_wep2, shp_data.size()])
		return

	var tiles: Array = shp_data[frame_key]

	# Build shader parameter arrays
	var rects: Array = []
	var rect_sizes: Array = []
	var locs: Array = []
	var inversions: Array = []
	var reversions: Array = []
	var rotations: Array = []
	var rot_points: Array = []
	var loc_offsets: Array = []

	for tile in tiles:
		var rect_x = tile["rectangle_x"]
		var rect_y = tile["rectangle_y"]

		# Apply weapon graphic offset for wep1 layer
		# Different weapons have different sprites at different Y positions in WEP1.tga
		# The v_offset selects the variant (e.g., Broad Sword vs Mythril Sword)
		if layer == SpriteLayer.WEP1:
			rect_y += wep1_v_offset_pixels

		rects.append(Vector2(rect_x, rect_y))
		rect_sizes.append(Vector2(tile["rectangle_width"], tile["rectangle_height"]))
		locs.append(Vector2(tile["location_x"], tile["location_y"]))
		inversions.append(tile['invert'])
		reversions.append(tile['revert'])
		rotations.append(tile['rotation'])
		rot_points.append(Vector2(SPRITE_CENTER_OFFSET_X, SPRITE_CENTER_OFFSET_Y))
		loc_offsets.append(Vector2(SPRITE_CENTER_OFFSET_X, SPRITE_CENTER_OFFSET_Y))

	# Apply to shader
	material.set_shader_parameter(layer_name + "_rects", rects)
	material.set_shader_parameter(layer_name + "_rect_sizes", rect_sizes)
	material.set_shader_parameter(layer_name + "_locs", locs)
	material.set_shader_parameter(layer_name + "_inversions", inversions)
	material.set_shader_parameter(layer_name + "_reversions", reversions)
	material.set_shader_parameter(layer_name + "_loc_offsets", loc_offsets)
	material.set_shader_parameter(layer_name + "_rotations", rotations)
	material.set_shader_parameter(layer_name + "_rot_points", rot_points)

	# Causal timeline: a TYPE1 write while the EVTCHR atlas is still bound is the
	# wrong-row bug in flight (the detector poll confirms it from the material).
	if layer == SpriteLayer.TYPE1:
		_trace_body_rect_write("type1", frame_id, rects)

	# OT depth sample point (ADR-0009): derive the body sprite's visual center
	# from its own VISIBLE (non-transparent) pixels so the billboard sorts at
	# mid-height (vs a wall's mid-height centroid), auto-scaling for tall
	# sprites. Body layer only. See _update_depth_center.
	if layer == SpriteLayer.TYPE1 and not locs.is_empty():
		_update_depth_center(rects, rect_sizes, locs, "spr:%d" % frame_id)

	# Set global reversion for entire sprite
	material.set_shader_parameter("global_reversion", apply_reversion)

	# Handle layer-specific enable flags
	if layer == SpriteLayer.TYPE1:
		if is_first_frame:
			material.set_shader_parameter("wep_enable", false)
			material.set_shader_parameter("eff_enable", false)
	elif layer == SpriteLayer.WEP1:
		material.set_shader_parameter("wep_enable", true)
	elif layer == SpriteLayer.EFF1:
		material.set_shader_parameter("eff_enable", true)


# === EVTCHR cinematic sprite path ====================================
#
# Cinematic Unit Anims (event-script opcode 0x29 with anim_id ≥ 0x1F4) render
# from EVTCHR.BIN per-segment sprite atlases, not the unit's TYPE1.SPR. The
# Block→Slot→segment indirection is hardcoded today (issue #124); once that
# lands the resolver moves there and these methods take a segment id directly.
#
# `enter_cinematic_mode` swaps the BODY layer's pixel atlas to the segment's
# EVTCHR texture and disables WEP1/EFF1. The unit's existing SPR palette + its
# `body_palette_row` uniform stay bound — FFT renders both combat (TYPE1.SHP)
# and event (EVTCHR) sprite sheets with the unit's own SPR palette indexed by
# the ENTD slot's `palette` byte (V14, 2026-06-27). The `{7F} EVTCHRPalette`
# override (chapel doesn't use it) is the only path that would swap in an
# EVTCHR-embedded palette; not modeled yet. See ADR-0053 + evtchr_palette_pipeline.md.
# `load_cinematic_frame` then writes the block descriptors from `evtchr_frames.json`
# into the same `type1_rects`/`_locs`/`_inversions`/`_reversions` shader arrays
# the normal load_frame_by_id path uses — so the same shader composites
# cinematic frames with no further code change.
# The EVTCHR tree is Class B; both paths resolve against the host content root (#744).

static var _evtchr_frames_db: Dictionary = {}
static var _evtchr_frames_loaded: bool = false

static func _ensure_evtchr_frames_loaded() -> bool:
	if _evtchr_frames_loaded:
		return not _evtchr_frames_db.is_empty()
	_evtchr_frames_loaded = true
	if not FileAccess.file_exists(ContentRoot.resolve(ContentRoot.EVTCHR_FRAMES_SUBPATH)):
		push_error("[SpriteLayerManager] evtchr_frames.json MISSING — EVTCHR cinematic frames cannot render. Run: uv run python tools/parse_evtchr_frames.py (or bash tools/bootstrap_assets.sh)")
		return false
	var f := FileAccess.open(ContentRoot.resolve(ContentRoot.EVTCHR_FRAMES_SUBPATH), FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[SpriteLayerManager] evtchr_frames.json malformed")
		return false
	_evtchr_frames_db = data
	return true


# Snapshot of the unit's pre-cinematic BODY shader params. Populated by
# `enter_cinematic_mode` on the FIRST entry per unit (re-entries while still
# in cinematic mode preserve the original snapshot). Drained by
# `exit_cinematic_mode`. The walker uses these to swap back to the unit's
# own TYPE1.SPR atlas when a cinematic anim's bytecode flips from a
# `frame_byte >= 0xD2` (EVTCHR) to a `frame_byte < 0xD2` (TYPE1.SHP) — anim
# 0x25C (Agrias dialog reaction) is the canonical example. Without this,
# the TYPE1.SHP rects render through the EVTCHR atlas and the unit looks
# like a different character (the "Agrias turns into Ovelia" symptom).
#
# Only `type1_tex` + `type1_tex_size` + the wep/eff enables are snapshotted —
# `type1_palette` and `body_palette_row` stay bound to the unit's SPR
# throughout (V14, 2026-06-27). EVTCHR's pixels sample the same SPR palette
# row the ENTD slot's `palette` byte selected at spawn.
var _cinematic_saved_state: Dictionary = {}


func enter_cinematic_mode(segment_id: int) -> bool:
	"""Swap the BODY pixel atlas to EVTCHR segment `segment_id`.

	Returns true on success. WEP1/EFF1 layers are disabled — cinematic frames
	composite the unit out of EVTCHR's own pixel page, not the equipped-weapon
	and effect sheets. The unit's SPR palette + `body_palette_row` uniform
	stay bound; EVTCHR pixels index into the same palette combat uses. Caller
	restores normal state via `exit_cinematic_mode`.
	"""
	if not material:
		push_error("[SpriteLayerManager] enter_cinematic_mode: no material")
		return false
	var idx_path := "%ssegment_%03d.tga" % [ContentRoot.resolve(ContentRoot.EVTCHR_TEX_SUBPATH), segment_id]
	if not ResourceLoader.exists(idx_path):
		push_error("[SpriteLayerManager] EVTCHR atlas missing: %s — run tools/bake_evtchr_textures.py" % idx_path)
		return false
	var tex := ResourceLoader.load(idx_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
	if tex == null:
		push_error("[SpriteLayerManager] EVTCHR texture load failed: %s" % idx_path)
		return false
	# Snapshot the BODY shader state on FIRST entry so `exit_cinematic_mode`
	# can restore the unit's own TYPE1.SPR atlas. Re-entries skip this so a
	# mid-anim re-bind doesn't overwrite the pre-cinematic snapshot with
	# EVTCHR values. `type1_palette` + `body_palette_row` are NOT snapshotted —
	# they stay bound to the unit's SPR throughout (V14).
	if _cinematic_saved_state.is_empty():
		_cinematic_saved_state = {
			"type1_tex": material.get_shader_parameter("type1_tex"),
			"type1_tex_size": material.get_shader_parameter("type1_tex_size"),
			"wep_enable": material.get_shader_parameter("wep_enable"),
			"eff_enable": material.get_shader_parameter("eff_enable"),
		}
	material.set_shader_parameter("type1_tex", tex)
	material.set_shader_parameter("type1_tex_size", tex.get_size())
	material.set_shader_parameter("wep_enable", false)
	material.set_shader_parameter("eff_enable", false)
	return true


func exit_cinematic_mode() -> void:
	"""Restore the BODY shader state snapshotted by `enter_cinematic_mode`.

	Called by the cinematic walker when a `frame_byte < 0xD2` (TYPE1.SHP) byte
	appears after a `>= 0xD2` (EVTCHR) byte in the same anim — the engine's
	`FUN_80083f18` branch at 0x80083FC8 picks the TYPE1 path for that byte,
	and the BODY layer needs the unit's own atlas back before
	`load_frame_by_id` writes its SHP rects. No-op if not currently in
	cinematic mode (snapshot dict empty).
	"""
	if _cinematic_saved_state.is_empty() or not material:
		return
	# Only restore params we actually captured a non-null value for. A unit
	# spawned mid-scenario reload can have null type1_tex briefly — restoring
	# null would blank the body. The dict is cleared either way so a later
	# enter_cinematic_mode re-snapshots from whatever the live state is then.
	for key in _cinematic_saved_state.keys():
		var v = _cinematic_saved_state[key]
		if v != null:
			material.set_shader_parameter(key, v)
	_cinematic_saved_state.clear()


func load_cinematic_frame(segment_id: int, frame_id: int, atlas_y_offset: int = 0) -> bool:
	"""Write EVTCHR frame `frame_id` of segment `segment_id` to the BODY layer.

	Mirrors `load_frame_by_id` but consumes `evtchr_frames.json` (keyed by
	segment id then frame id, where frame_id is the runtime bytecode byte —
	0xD2..0xF9; see `parse_evtchr_frames.py`'s docstring for the disc-to-
	runtime +7 shift). Returns true if the frame was found and the shader
	was updated.

	`atlas_y_offset` is a signed pixel shift added to each block's
	`rectangle_y` before the shader sees it. Mirrors PSX `FUN_80084214` at
	`0x8008435c` where `unit_struct + 0x7a` is a signed i16 added to each
	block's tile_y * 8 — the engine's per-unit "which row of the shared
	atlas to sample" selector. The chapel EVTCHR segment 0 stacks multiple
	characters in rows of 40 px (see the runtime-byte → src(x,y) table in
	`tools/parse_evtchr_frames.py` output); without a per-unit offset every
	cinematic-anim'd unit reads from the same row, producing the
	"Agrias morphs into Ovelia" symptom. ScenarioVM exposes a per-uid map
	via the F3 debug panel for empirical tuning until the +0x144 bitfield
	source is fully traced.
	"""
	if not material:
		return false
	if not _ensure_evtchr_frames_loaded():
		return false
	var seg_key := str(segment_id)
	if not _evtchr_frames_db.has(seg_key):
		push_warning("[SpriteLayerManager] EVTCHR segment %d not in evtchr_frames.json" % segment_id)
		return false
	var frame_key := str(frame_id)
	var seg_frames: Dictionary = _evtchr_frames_db[seg_key]
	if not seg_frames.has(frame_key):
		push_warning("[SpriteLayerManager] EVTCHR seg %d frame 0x%02X missing" % [segment_id, frame_id])
		return false
	var blocks: Array = seg_frames[frame_key]

	var rects: Array = []
	var rect_sizes: Array = []
	var locs: Array = []
	var inversions: Array = []
	var reversions: Array = []
	var rotations: Array = []
	var rot_points: Array = []
	var loc_offsets: Array = []

	for b in blocks:
		rects.append(Vector2(b["rectangle_x"], b["rectangle_y"] + atlas_y_offset))
		rect_sizes.append(Vector2(b["rectangle_width"], b["rectangle_height"]))
		locs.append(Vector2(b["location_x"], b["location_y"]))
		inversions.append(b["invert"])
		reversions.append(b["revert"])
		rotations.append(b["rotation"])
		rot_points.append(Vector2(SPRITE_CENTER_OFFSET_X, SPRITE_CENTER_OFFSET_Y))
		loc_offsets.append(Vector2(SPRITE_CENTER_OFFSET_X, SPRITE_CENTER_OFFSET_Y))

	material.set_shader_parameter("type1_rects", rects)
	material.set_shader_parameter("type1_rect_sizes", rect_sizes)
	material.set_shader_parameter("type1_locs", locs)
	material.set_shader_parameter("type1_inversions", inversions)
	material.set_shader_parameter("type1_reversions", reversions)
	material.set_shader_parameter("type1_loc_offsets", loc_offsets)
	material.set_shader_parameter("type1_rotations", rotations)
	material.set_shader_parameter("type1_rot_points", rot_points)
	material.set_shader_parameter("global_reversion", apply_reversion)

	_trace_body_rect_write("cinematic", frame_id, rects)

	# OT depth sample point — same convention as load_frame_by_id() above.
	if not locs.is_empty():
		_update_depth_center(rects, rect_sizes, locs,
			"evt:%d:%d:%d" % [segment_id, frame_id, atlas_y_offset])
	return true


# === OT depth-center derivation =====================================
#
# The billboard samples its flat OT depth at the body sprite's VISUAL CENTER
# (ADR-0009), not its feet, so it sorts fairly against a wall's mid-height
# centroid. The center is the midpoint of the smallest box that contains all
# NON-TRANSPARENT body pixels for the current frame — NOT the box of the raw
# piece rectangles. That distinction is load-bearing: a sprite piece can carry
# large transparent margins (FFT monster frames especially — the chocobo's
# resting frame has pieces padded down to location_y≈132 with no visible pixel
# below ≈6). The old piece-rectangle midpoint put the chocobo's sample ~1.44
# world units *below its feet*, mis-sorting it against the ledge terrain. The
# visible-pixel box lands the sample on the bird's body (and, as a bonus, at the
# horizontal center too — the debug "center marker" now sits on the sprite).
#
# A body pixel at loc_y maps to a world-Y offset above the mesh origin of
# DEPTH_CENTER_BIAS - loc_y/DEPTH_CENTER_DIV (traced from unit.gdshader). The
# scan is cached per distinct frame (pixel-exact geometry is deterministic).
func _update_depth_center(rects: Array, rect_sizes: Array, locs: Array, cache_key: String) -> void:
	if not material:
		return
	var center: Vector2 = _derive_visible_center(rects, rect_sizes, locs, cache_key)
	var base_center: float = DEPTH_CENTER_BIAS - center.y / DEPTH_CENTER_DIV
	# @tool-guarded: the registry is a placeholder at edit time (Tune.gd is not
	# @tool), so fall back to the code default in the editor. Belt-and-braces since
	# #847: `TunePort._resolve()` rejects the placeholder on `has_method` too, and
	# names the same fallback when the registry is absent entirely.
	var bias: float = CENTER_BIAS_DEFAULT if Engine.is_editor_hint() \
		else TunePort.get_value(CENTER_BIAS_SLUG, CENTER_BIAS_DEFAULT)
	material.set_shader_parameter("depth_center_height", base_center + bias)


# Returns the (loc_x, loc_y) center of the smallest box containing every
# non-transparent BODY pixel of the frame. Falls back to the piece-rectangle
# bbox when the atlas image is unreadable or the frame has no visible pixels.
func _derive_visible_center(rects: Array, rect_sizes: Array, locs: Array, cache_key: String) -> Vector2:
	var atlas := material.get_shader_parameter("type1_tex") as Texture2D
	var atlas_path := atlas.resource_path if atlas != null else "<none>"
	var key := "%s|%s" % [atlas_path, cache_key]
	if _center_cache.has(key):
		return _center_cache[key]
	var center := compute_body_center(_get_atlas_image(atlas), rects, rect_sizes, locs)
	_center_cache[key] = center
	return center


# Pure geometry — the smallest box containing every non-transparent BODY pixel,
# returned as its (loc_x, loc_y) center. Static + Image-in so it unit-tests
# without a material/atlas resource. Falls back to the piece-rectangle bbox when
# the image is null or the frame has no visible pixels (e.g. an all-transparent
# frame). See _update_depth_center for why the visible-pixel box is what matters.
static func compute_body_center(img: Image, rects: Array, rect_sizes: Array, locs: Array) -> Vector2:
	var bbox := compute_body_bbox(img, rects, rect_sizes, locs)
	return bbox.position + bbox.size * 0.5


# Pure geometry — the smallest box (in loc space) containing every non-transparent
# BODY pixel of the frame, returned as a Rect2. Static + Image-in so it unit-tests
# without a material/atlas resource. Falls back to the piece-rectangle bbox when
# the image is null or the frame has no visible pixels (e.g. an all-transparent
# frame). `compute_body_center` returns this box's centre; the Formation body
# builder uses the box's SIZE to scale the composited sprite to the ROM descriptor
# (Uw×Vh) and its CENTRE to place the sprite at the ROM cell offset. See
# _update_depth_center for why the visible-pixel box (not the raw piece rects) is
# what matters.
static func compute_body_bbox(img: Image, rects: Array, rect_sizes: Array, locs: Array) -> Rect2:
	# Piece-rectangle bbox — the fallback, and the correct answer when a frame is
	# a single fully-opaque piece.
	var pr_top: float = INF
	var pr_bottom: float = -INF
	var pr_left: float = INF
	var pr_right: float = -INF
	for i in range(locs.size()):
		if float(rect_sizes[i].x) <= 0.0:
			continue
		pr_top = min(pr_top, float(locs[i].y))
		pr_bottom = max(pr_bottom, float(locs[i].y) + float(rect_sizes[i].y))
		pr_left = min(pr_left, float(locs[i].x))
		pr_right = max(pr_right, float(locs[i].x) + float(rect_sizes[i].x))
	var piece_bbox := Rect2(pr_left, pr_top, pr_right - pr_left, pr_bottom - pr_top)
	if img == null:
		return piece_bbox

	var iw := img.get_width()
	var ih := img.get_height()
	var vp_top: float = INF
	var vp_bottom: float = -INF
	var vp_left: float = INF
	var vp_right: float = -INF
	var visible := 0
	for i in range(locs.size()):
		if float(rect_sizes[i].x) <= 0.0:
			continue
		var rx := int(rects[i].x)
		var ry := int(rects[i].y)
		var w := int(rect_sizes[i].x)
		var h := int(rect_sizes[i].y)
		var lx0 := float(locs[i].x)
		var ly0 := float(locs[i].y)
		for py in range(h):
			var ay := ry + py
			if ay < 0 or ay >= ih:
				continue
			for px in range(w):
				var ax := rx + px
				if ax < 0 or ax >= iw:
					continue
				# BODY atlas is indexed-grayscale: idx = round(r*15); idx 0 is
				# the FFT magic-transparent color (matches add_tile_paletted).
				if int(img.get_pixel(ax, ay).r * 15.0 + 0.5) == 0:
					continue
				visible += 1
				var lx := lx0 + float(px)
				var ly := ly0 + float(py)
				vp_top = min(vp_top, ly)
				vp_bottom = max(vp_bottom, ly + 1.0)
				vp_left = min(vp_left, lx)
				vp_right = max(vp_right, lx + 1.0)

	if visible == 0:
		return piece_bbox
	return Rect2(vp_left, vp_top, vp_right - vp_left, vp_bottom - vp_top)


# Visible-pixel bbox (loc space) of the CURRENTLY-loaded TYPE1 frame, read back
# off the live material uniforms + atlas image. The Formation body builder calls
# this after load_frame_by_id to size/place the composited sprite against the ROM
# descriptor (FORMATION_ELEMENT_PLACEMENT.md §7). Returns a zero Rect2 if the
# TYPE1 uniforms aren't populated yet.
func current_body_bbox() -> Rect2:
	if material == null:
		return Rect2()
	var rects = material.get_shader_parameter("type1_rects")
	var rect_sizes = material.get_shader_parameter("type1_rect_sizes")
	var locs = material.get_shader_parameter("type1_locs")
	if rects == null or rect_sizes == null or locs == null:
		return Rect2()
	var atlas := material.get_shader_parameter("type1_tex") as Texture2D
	return compute_body_bbox(_get_atlas_image(atlas), rects, rect_sizes, locs)


func _get_atlas_image(atlas: Texture2D) -> Image:
	if atlas == null:
		return null
	var path := atlas.resource_path
	if _atlas_image_cache.has(path):
		return _atlas_image_cache[path]
	var img := atlas.get_image()
	if img != null and img.is_compressed():
		img = img.duplicate()
		img.decompress()
	_atlas_image_cache[path] = img
	return img
