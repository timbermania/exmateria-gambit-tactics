class_name Projectile3D
extends Node3D

## Projectile with Parabolic Arc Flight
##
## Handles projectile visualization and physics for ranged weapons:
## - Parabolic arc trajectory (FFT-style)
## - Different visual types (arrow, bullet, shuriken, ball, potion)
## - Arrow rotation to face velocity direction

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const WeaponAnimationSelector = ExMateriaSpriteRig.WeaponAnimationSelector

enum ProjectileType { ARROW, BULLET, SHURIKEN, BALL, POTION, ITEM, STONE, WEAPON_SPRITE }

# PSX projectile model constants
const PROJECTILE_JSON_PATH := "res://assets/projectiles/projectile_models.json"
const PROJECTILE_MATERIAL_PATH := "res://assets/materials/projectile_vertex_color.tres"
## Thrown-weapon/item spin rate (deg/CombatLoop-tick) — the code default + single home
## for the `projectile.spin_deg_per_tick` Tune tunable (ADR-0068), read at the use-site
## below. Placeholder until the PSX-authentic rate is RE'd from BATTLE.BIN.
## A `static var` (not `const`) so it is the materializable home the bind's follower can
## rewrite (ADR-0068 R1) — a `const` is frozen at parse time and a scrub can never reach it.
static var SPIN_DEG_PER_TICK_DEFAULT := 24.0
const SPIN_SLUG := "projectile.spin_deg_per_tick"


## Register the shared spin slug ONCE at class load (ADR-0068 R2), so every projectile's
## per-frame pull-read (`get_value`, below) resolves without a per-instance bind, and the
## dashboard enumerates it before any projectile spawns. Editor-guarded defensively (Tune is
## a non-@tool placeholder in the editor should the class ever load there).
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## The spin bind, split out from _static_init as this owner's named registration entry point
## (ADR-0173): _static_init calls it at class load — the ONLY thing that does — and the guards
## call it to read back which slugs this owner binds. Editor-guarded by the caller.
static func register_tunables() -> void:
	Tune.bind(SPIN_SLUG, SPIN_DEG_PER_TICK_DEFAULT, {"min": 0.0, "max": 90.0, "step": 1.0})

const ARROW_SCALE := 0.064  # Scale 12.51 unit model to ~0.8 units
const STONE_SCALE := 0.1    # Scale 1.6 unit model to ~0.16 units
const SHURIKEN_SCALE := 0.1  # Larger for visibility

# PSX stone tumble — original constants were per-CombatLoop-tick at 60 Hz
# (halved for 60 fps vs PSX 30 fps). Converted to per-second so Projectile3D
# can drive them from _process(delta), which inherits Engine.time_scale.
# Raw PSX angle → rad routes through the shared full-turn base (ADR-0091); a const
# can't call PsxMagnitude.angle_to_rad, so reference PsxMagnitude.FULL_TURN (= 4096) directly.
const STONE_TUMBLE_Y_RATE_PER_SEC: float = 256.0 / PsxMagnitude.FULL_TURN * TAU * 0.5 * 60.0
const STONE_TUMBLE_X_RATE_PER_SEC: float = 128.0 / PsxMagnitude.FULL_TURN * TAU * 0.5 * 60.0

# Static cache for shared resources
static var _cached_json: Dictionary
static var _cached_material: Material
static var _cached_wep1_shp: Dictionary  # Cache for WEP1 SHP frame data
static var _cached_sprite_shader: Shader  # Cache for projectile_sprite.gdshader
static var _cached_solid_shader: Shader  # Cache for solid_ot.gdshader

const PROJECTILE_SPRITE_SHADER_PATH := "res://assets/shaders/projectile_sprite.gdshader"
const SOLID_SHADER_PATH := "res://assets/shaders/solid_ot.gdshader"

# WEP1 weapon sprite constants
const WEP1_TEXTURE_PATH := "res://assets/sprites/textures/WEP1.tga"
const WEP1_PALETTE_PATH := "res://assets/sprites/textures/WEP1.palette.tga"
const WEP1_SHP_PATH := "res://assets/sprites/animations/wep1_shp.json"
const WEP1_TEXTURE_WIDTH := 256
const WEP1_TEXTURE_HEIGHT := 488

signal flight_completed

var projectile_type: ProjectileType = ProjectileType.ARROW
var start_pos: Vector3
var end_pos: Vector3
var flight_duration: float
var arc_height: float
var elapsed: float = 0.0

# ADR-0038: target tracking. While alive, end_pos updates each frame from
# target_node.global_position; once the node becomes invalid, end_pos sticks
# at its last seen value (death-resilient — projectile completes flight to
# the target's last position rather than stranding mid-air).
var target_node: Node3D
const TARGET_OFFSET: Vector3 = Vector3(0, 0.5, 0)

# Tumble (STONE / BALL) and spin (WEAPON_SPRITE / ITEM) state. Advanced from
# _process(delta) so combat_visuals freeze halts them on every axis.
var _tumble_x: float = 0.0
var _tumble_y: float = 0.0
var _spin_angle: float = 0.0

# Set true at landing to prevent double-emit of flight_completed.
var _landed: bool = false

var _mesh_instance: MeshInstance3D

# Item projectile settings
var item_graphic: int = 0  # Graphic index from item data
var item_palette: int = 0  # Palette index from item data

# Weapon sprite projectile settings
var throw_item_type_id: int = 0  # Item type ID for WEP1 frame lookup

# TRAP effect element for hit cloud (0-8)
# 0=None, 1=Fire, 2=Lightning, 3=Ice, 4=Wind, 5=Earth, 6=Water, 7=Holy, 8=Dark
var trap_element_index: int = 0

# Item icon spritesheet constants
# ITEM.BIN from EVENT folder - 256x256 texture
# Icon size TBD based on inspection - trying 16x16 first (16 icons per row)
const ITEM_ICON_SIZE := 16  # Each icon is 16x16 pixels
const ITEM_SHEET_WIDTH := 256  # Spritesheet width in pixels
const ITEM_ICONS_PER_ROW := 16  # 256 / 16 = 16 icons per row
const ITEM_SHEET_HEIGHT := 256  # 256x256 texture from ITEM.BIN


func _ready() -> void:
	# ADR-0037 / ADR-0038: projectile-in-flight is a combat-visual.
	# Spacebar pause and cinematic spell halt _process (via the group's
	# process_mode flip), which freezes spin / tumble; post-victory leaves
	# it running so the projectile still finishes spinning while it lands.
	add_to_group("combat_visuals")


func _process(delta: float) -> void:
	# Per-frame visual effects only (spin / tumble / arrow rotation tangent).
	# Flight POSITION advancement lives in `advance_tick()` so it stays
	# perfectly tick-synchronized with the GPU damage tick — see ADR-0038.
	if _landed:
		return
	if projectile_type == ProjectileType.STONE or projectile_type == ProjectileType.BALL:
		_tumble_x += STONE_TUMBLE_X_RATE_PER_SEC * delta
		_tumble_y += STONE_TUMBLE_Y_RATE_PER_SEC * delta
		if _mesh_instance:
			_mesh_instance.basis = Basis.from_euler(Vector3(_tumble_x, _tumble_y, 0.0))
			_mesh_instance.scale = Vector3.ONE * STONE_SCALE
	elif projectile_type == ProjectileType.WEAPON_SPRITE or projectile_type == ProjectileType.ITEM:
		# Per-tick knob preserved (open RE follow-up: pin the PSX-authentic
		# rate from BATTLE.BIN). Multiply by TICKS_PER_SECOND so a per-tick
		# knob value yields the same visual rate as the legacy tick-driven
		# path at 60 Hz.
		# Spin rate owned by Tune (ADR-0068): re-read at the use-site each frame so a
		# scrub/pin drives every projectile live in any scene. Default is the code home.
		var spin: float = Tune.get_value(SPIN_SLUG)
		_spin_angle += deg_to_rad(spin) * delta * 60.0
		if _mesh_instance and _mesh_instance.material_override:
			_mesh_instance.material_override.set_shader_parameter("spin_angle", _spin_angle)


func advance_tick() -> void:
	"""Advance flight progress by one GPU tick. Called from
	`ProjectileManager.update()` inside CombatLoop's per-tick pump, so it
	stays tick-locked with the GPU damage tick (`_last_damage_tick` set by
	`_read_tick_columns`).

	Death-resilient: while target Node is alive, end_pos updates to its
	live position; once freed, end_pos sticks at its last seen value so
	the projectile completes flight to the target's death-tile (ADR-0038)."""
	if _landed or flight_duration <= 0.0:
		return

	if is_instance_valid(target_node):
		end_pos = target_node.global_position + TARGET_OFFSET

	elapsed += 1.0 / 60.0  # CombatLoop's TICK_INTERVAL
	var progress: float = clampf(elapsed / flight_duration, 0.0, 1.0)

	# XZ linear, Y parabolic arc peaking at the midpoint.
	var pos: Vector3 = start_pos.lerp(end_pos, progress)
	var arc_offset: float = arc_height * (1.0 - pow(2.0 * progress - 1.0, 2.0))
	pos.y += arc_offset
	global_position = pos

	if projectile_type == ProjectileType.ARROW:
		_update_arrow_rotation(progress)

	if progress >= 1.0:
		_landed = true
		flight_completed.emit()


func _get_projectile_json() -> Dictionary:
	"""Load and cache projectile model JSON data."""
	if _cached_json.is_empty():
		var file := FileAccess.open(PROJECTILE_JSON_PATH, FileAccess.READ)
		if file:
			var json := JSON.new()
			json.parse(file.get_as_text())
			_cached_json = json.data
	return _cached_json


func _get_projectile_material() -> Material:
	"""Load and cache projectile vertex color material."""
	if not _cached_material:
		_cached_material = load(PROJECTILE_MATERIAL_PATH)
	return _cached_material


func _get_sprite_shader() -> Shader:
	"""Load and cache projectile sprite shader."""
	if not _cached_sprite_shader:
		_cached_sprite_shader = load(PROJECTILE_SPRITE_SHADER_PATH)
	return _cached_sprite_shader


func _create_sprite_shader_material(texture: Texture2D) -> ShaderMaterial:
	"""Create a ShaderMaterial using the projectile sprite shader (RGBA path)."""
	var mat = ShaderMaterial.new()
	mat.shader = _get_sprite_shader()
	mat.set_shader_parameter("albedo_texture", texture)
	mat.set_shader_parameter("spin_angle", 0.0)
	mat.set_shader_parameter("alpha_scissor_threshold", 0.1)
	mat.set_shader_parameter("use_palette", false)
	return mat


func _create_paletted_sprite_material(texture: Texture2D, palette: Texture2D, palette_row: int) -> ShaderMaterial:
	"""Create a ShaderMaterial for WEP1 indexed-grayscale + palette swap.

	WEP1.tga has been indexed-grayscale (R=G=B=index*17, A=255) with a sidecar
	WEP1.palette.tga since the ADR-0022 sprite-extract refactor. Sampling it as
	straight RGBA paints index-0 (FFT-transparent) pixels as opaque black —
	that was the "black background" on thrown ninja weapons.
	"""
	var mat = ShaderMaterial.new()
	mat.shader = _get_sprite_shader()
	mat.set_shader_parameter("albedo_texture", texture)
	mat.set_shader_parameter("spin_angle", 0.0)
	mat.set_shader_parameter("alpha_scissor_threshold", 0.1)
	mat.set_shader_parameter("use_palette", true)
	mat.set_shader_parameter("palette_texture", palette)
	mat.set_shader_parameter("palette_row", palette_row)
	return mat


func _create_solid_material(color: Color) -> ShaderMaterial:
	"""Solid-color material that writes OT depth (object-origin), for placeholder
	primitives and load fallbacks — keeps every battle mesh inside the OT model
	(ADR-0009) instead of StandardMaterial3D's true per-fragment depth."""
	if not _cached_solid_shader:
		_cached_solid_shader = load(SOLID_SHADER_PATH)
	var mat = ShaderMaterial.new()
	mat.shader = _cached_solid_shader
	mat.set_shader_parameter("solid_color", Vector3(color.r, color.g, color.b))
	return mat


func initialize(type: ProjectileType, from: Vector3, to: Vector3, height: float, duration: float) -> void:
	"""Initialize projectile with flight parameters.

	Args:
		type: Visual type of projectile
		from: Starting world position
		to: Target world position
		height: Peak height of arc above straight line
		duration: Total flight time in seconds
	"""
	projectile_type = type
	start_pos = from
	end_pos = to
	arc_height = height
	flight_duration = maxf(duration, 0.1)  # Minimum flight time

	global_position = start_pos
	_create_visual()

	# Initial rotation for arrows
	if projectile_type == ProjectileType.ARROW:
		_update_arrow_rotation(0.0)


func initialize_item(from: Vector3, to: Vector3, height: float, duration: float, graphic: int, palette: int = 0) -> void:
	"""Initialize item projectile with sprite from item spritesheet.

	Args:
		from: Starting world position
		to: Target world position
		height: Peak height of arc above straight line
		duration: Total flight time in seconds
		graphic: Item graphic index for sprite lookup
		palette: Item palette index (currently unused, for future enhancement)
	"""
	item_graphic = graphic
	item_palette = palette
	initialize(ProjectileType.ITEM, from, to, height, duration)


func initialize_weapon_sprite(from: Vector3, to: Vector3, height: float, duration: float, weapon_type_id: int) -> void:
	"""Initialize weapon sprite projectile from WEP1 spritesheet.

	Args:
		from: Starting world position
		to: Target world position
		height: Peak height of arc above straight line
		duration: Total flight time in seconds
		weapon_type_id: Item type ID for WEP1 frame lookup (via WeaponAnimationSelector.get_wep_frame_offset)
	"""
	throw_item_type_id = weapon_type_id
	initialize(ProjectileType.WEAPON_SPRITE, from, to, height, duration)


func _update_arrow_rotation(t: float) -> void:
	"""Rotate arrow to face velocity direction (tangent to arc)."""
	if not _mesh_instance:
		return

	# Calculate velocity direction (tangent to arc, including height slope)
	var delta = end_pos - start_pos
	var xz_delta = Vector3(delta.x, 0.0, delta.z)
	var xz_dist = xz_delta.length()
	if xz_dist < 0.001:
		return
	var xz_dir = xz_delta / xz_dist
	var slope_y = delta.y / xz_dist
	var arc_deriv = -4.0 * arc_height * (2.0 * t - 1.0) / xz_dist
	var velocity = Vector3(xz_dir.x, slope_y + arc_deriv, xz_dir.z)

	if velocity.length_squared() > 0.001:
		var forward = velocity.normalized()
		# Use appropriate up vector to avoid gimbal lock when shooting near-vertical
		var up = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		# Basis.looking_at makes -Z face forward direction
		# PSX arrow tip is at -Y, so multiply by base rotation (+90° around X)
		# This transforms model's -Y axis to align with the velocity direction
		_mesh_instance.basis = Basis.looking_at(forward, up) * Basis(Vector3.RIGHT, PI / 2.0)
		# Restore scale after setting basis (basis overwrites scale)
		_mesh_instance.scale = Vector3.ONE * ARROW_SCALE


func _create_visual() -> void:
	"""Create mesh visual based on projectile type."""
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

	var mesh: Mesh
	var color: Color

	match projectile_type:
		ProjectileType.ARROW:
			# Load PSX arrow model
			var json_data := _get_projectile_json()
			if not json_data.is_empty() and json_data.has("models") and json_data["models"].has("arrow"):
				mesh = ProjectileMeshBuilder.build_mesh(json_data["models"]["arrow"])
				_mesh_instance.mesh = mesh
				_mesh_instance.material_override = _get_projectile_material()
				# Base rotation: PSX arrow tip is at -Y, rotate +90° around X to point tip along -Z
				# (looking_at makes -Z face forward, so tip will face velocity direction)
				_mesh_instance.basis = Basis(Vector3.RIGHT, PI / 2.0)
				# Scale must be set AFTER basis (basis overwrites scale)
				_mesh_instance.scale = Vector3.ONE * ARROW_SCALE
				return  # Skip the generic material setup below
			else:
				# Fallback to cylinder if PSX model fails to load
				var cylinder = CylinderMesh.new()
				cylinder.top_radius = 0.02
				cylinder.bottom_radius = 0.02
				cylinder.height = 0.3
				mesh = cylinder
				color = Color.WHITE
				_mesh_instance.rotation_degrees = Vector3(0, 0, 90)

		ProjectileType.BULLET:
			# Small yellow sphere
			var sphere = SphereMesh.new()
			sphere.radius = 0.03
			sphere.height = 0.06
			mesh = sphere
			color = Color.YELLOW

		ProjectileType.SHURIKEN:
			# Load PSX shuriken model (stored as "unknown" in JSON)
			var json_data := _get_projectile_json()
			if not json_data.is_empty() and json_data.has("models") and json_data["models"].has("unknown"):
				mesh = ProjectileMeshBuilder.build_mesh(json_data["models"]["unknown"])
				_mesh_instance.mesh = mesh
				_mesh_instance.material_override = _get_projectile_material()
				_mesh_instance.scale = Vector3.ONE * SHURIKEN_SCALE
				return
			else:
				# Fallback to box
				var box = BoxMesh.new()
				box.size = Vector3(0.1, 0.02, 0.1)
				mesh = box
				color = Color.SILVER

		ProjectileType.BALL:
			# Load PSX stone model
			var json_data := _get_projectile_json()
			if not json_data.is_empty() and json_data.has("models") and json_data["models"].has("stone"):
				mesh = ProjectileMeshBuilder.build_mesh(json_data["models"]["stone"])
				_mesh_instance.mesh = mesh
				_mesh_instance.material_override = _get_projectile_material()
				_mesh_instance.scale = Vector3.ONE * STONE_SCALE
				return
			else:
				# Fallback to sphere
				var sphere = SphereMesh.new()
				sphere.radius = 0.08
				sphere.height = 0.16
				mesh = sphere
				color = Color.ORANGE

		ProjectileType.POTION:
			# Green cylinder for potion bottle
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = 0.04
			cylinder.bottom_radius = 0.06
			cylinder.height = 0.12
			mesh = cylinder
			color = Color.GREEN

		ProjectileType.ITEM:
			# Billboarded item sprite from spritesheet
			_create_item_sprite_visual()
			return  # Early return - _create_item_sprite_visual handles everything

		ProjectileType.STONE:
			# Load PSX stone model (same as BALL)
			var json_data := _get_projectile_json()
			if not json_data.is_empty() and json_data.has("models") and json_data["models"].has("stone"):
				mesh = ProjectileMeshBuilder.build_mesh(json_data["models"]["stone"])
				_mesh_instance.mesh = mesh
				_mesh_instance.material_override = _get_projectile_material()
				_mesh_instance.scale = Vector3.ONE * STONE_SCALE
				return
			else:
				# Fallback to sphere
				var sphere = SphereMesh.new()
				sphere.radius = 0.08
				sphere.height = 0.16
				mesh = sphere
				color = Color.GRAY

		ProjectileType.WEAPON_SPRITE:
			# Billboarded weapon sprite from WEP1 spritesheet
			_create_weapon_sprite_visual()
			return

	_mesh_instance.mesh = mesh

	# Solid bright color via the OT-depth shader (was an emissive StandardMaterial3D;
	# that wrote true per-fragment depth and mis-sorted against flat-CUSTOM0 terrain).
	_mesh_instance.material_override = _create_solid_material(color)


func _create_item_sprite_visual() -> void:
	"""Create billboarded item sprite from spritesheet."""
	# Calculate frame index using TacticsG formula:
	# - Items start at row 2 (frame 32)
	# - Every 15 icons, skip 1 column (the blank 16th column)
	# Formula: frame = 32 + graphic + (graphic / 15)
	var frame_index = 32 + item_graphic + (item_graphic / 15)
	var icon_col = frame_index % ITEM_ICONS_PER_ROW
	var icon_row = frame_index / ITEM_ICONS_PER_ROW

	# Half-pixel offset for pixel-perfect sampling (sample from center of pixels)
	var half_pixel_u = 0.5 / float(ITEM_SHEET_WIDTH)
	var half_pixel_v = 0.5 / float(ITEM_SHEET_HEIGHT)

	var u_min = float(icon_col * ITEM_ICON_SIZE) / float(ITEM_SHEET_WIDTH) + half_pixel_u
	var u_max = float((icon_col + 1) * ITEM_ICON_SIZE) / float(ITEM_SHEET_WIDTH) - half_pixel_u
	var v_min = float(icon_row * ITEM_ICON_SIZE) / float(ITEM_SHEET_HEIGHT) + half_pixel_v
	var v_max = float((icon_row + 1) * ITEM_ICON_SIZE) / float(ITEM_SHEET_HEIGHT) - half_pixel_v

	if DebugConfig.iteration_debug_enabled:
		print("[Projectile3D] Item sprite UV debug:")
		print("  graphic=%d -> frame=%d -> col=%d, row=%d" % [item_graphic, frame_index, icon_col, icon_row])
		print("  UV: u=[%.4f, %.4f], v=[%.4f, %.4f]" % [u_min, u_max, v_min, v_max])
		print("  Pixels: x=[%d, %d], y=[%d, %d]" % [
			int(u_min * ITEM_SHEET_WIDTH), int(u_max * ITEM_SHEET_WIDTH),
			int(v_min * ITEM_SHEET_HEIGHT), int(v_max * ITEM_SHEET_HEIGHT)
		])

	# Create quad mesh with custom UVs using SurfaceTool
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_size = 0.25  # Half of 0.5 world units (larger for visibility)

	# Quad vertices (centered, facing +Z)
	# Vertex 0: top-left
	st.set_uv(Vector2(u_min, v_min))
	st.add_vertex(Vector3(-half_size, half_size, 0))
	# Vertex 1: bottom-left
	st.set_uv(Vector2(u_min, v_max))
	st.add_vertex(Vector3(-half_size, -half_size, 0))
	# Vertex 2: bottom-right
	st.set_uv(Vector2(u_max, v_max))
	st.add_vertex(Vector3(half_size, -half_size, 0))

	# Vertex 3: top-left (for second triangle)
	st.set_uv(Vector2(u_min, v_min))
	st.add_vertex(Vector3(-half_size, half_size, 0))
	# Vertex 4: bottom-right
	st.set_uv(Vector2(u_max, v_max))
	st.add_vertex(Vector3(half_size, -half_size, 0))
	# Vertex 5: top-right
	st.set_uv(Vector2(u_max, v_min))
	st.add_vertex(Vector3(half_size, half_size, 0))

	_mesh_instance.mesh = st.commit()

	# Load palette-specific item icons texture
	var texture_path = "res://assets/items/item_icons_pal%d.tga" % item_palette
	var texture = load(texture_path)
	if not texture:
		# Fallback to palette 0
		texture = load("res://assets/items/item_icons_pal0.tga")
	if not texture:
		push_warning("[Projectile3D] Failed to load item_icons texture, using fallback")
		_create_fallback_item_visual()
		return

	# Use projectile sprite shader (billboard + spin support + correct sRGB-to-linear)
	_mesh_instance.material_override = _create_sprite_shader_material(texture)


func _get_wep1_shp() -> Dictionary:
	"""Load and cache WEP1 SHP frame data."""
	if _cached_wep1_shp.is_empty():
		var file := FileAccess.open(WEP1_SHP_PATH, FileAccess.READ)
		if file:
			var json := JSON.new()
			json.parse(file.get_as_text())
			_cached_wep1_shp = json.data
	return _cached_wep1_shp


func _create_weapon_sprite_visual() -> void:
	"""Create billboarded weapon sprite from WEP1 spritesheet."""
	# Non-held weapons (shuriken/ball) use item_icons instead of WEP1
	const THROW_ITEM_ICON_GRAPHICS: Dictionary = {
		32: 69,   # Shuriken -> item_icons graphic 69
		33: 70,   # Ball -> item_icons graphic 70
	}
	if throw_item_type_id in THROW_ITEM_ICON_GRAPHICS:
		item_graphic = THROW_ITEM_ICON_GRAPHICS[throw_item_type_id]
		item_palette = 0
		_create_item_sprite_visual()
		return

	# Look up frame offset for this weapon type
	var frame_offset = WeaponAnimationSelector.get_wep_frame_offset(throw_item_type_id)

	# Load SHP data for this frame
	var shp_data = _get_wep1_shp()
	var frame_key = str(frame_offset)
	if not shp_data.has(frame_key):
		push_warning("[Projectile3D] WEP1 SHP missing frame %s for item_type %d" % [frame_key, throw_item_type_id])
		_create_fallback_item_visual()
		return

	var tiles = shp_data[frame_key]
	if tiles.is_empty():
		push_warning("[Projectile3D] WEP1 SHP frame %s has no tiles" % frame_key)
		_create_fallback_item_visual()
		return

	# Use tile 0 (the idle weapon pose)
	var tile = tiles[0]
	var rect_x = int(tile["rectangle_x"])
	var rect_y = int(tile["rectangle_y"])
	var rect_w = int(tile["rectangle_width"])
	var rect_h = int(tile["rectangle_height"])
	var rotation_deg = float(tile.get("rotation", 0.0))

	# Compute UVs on WEP1.tga
	var half_pixel_u = 0.5 / float(WEP1_TEXTURE_WIDTH)
	var half_pixel_v = 0.5 / float(WEP1_TEXTURE_HEIGHT)

	var u_min = float(rect_x) / float(WEP1_TEXTURE_WIDTH) + half_pixel_u
	var u_max = float(rect_x + rect_w) / float(WEP1_TEXTURE_WIDTH) - half_pixel_u
	var v_min = float(rect_y) / float(WEP1_TEXTURE_HEIGHT) + half_pixel_v
	var v_max = float(rect_y + rect_h) / float(WEP1_TEXTURE_HEIGHT) - half_pixel_v

	if DebugConfig.iteration_debug_enabled:
		print("[Projectile3D] Weapon sprite UV debug:")
		print("  item_type=%d -> frame_offset=%d -> rect=(%d,%d,%d,%d) rot=%.1f" % [
			throw_item_type_id, frame_offset, rect_x, rect_y, rect_w, rect_h, rotation_deg])
		print("  UV: u=[%.4f, %.4f], v=[%.4f, %.4f]" % [u_min, u_max, v_min, v_max])

	# Create quad mesh with custom UVs using SurfaceTool
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var max_dim = maxf(rect_w, rect_h)
	var half_size = 0.25 * max_dim / 16.0

	# Apply SHP rotation to the quad vertices
	var rot_rad = deg_to_rad(rotation_deg)
	var cos_r = cos(rot_rad)
	var sin_r = sin(rot_rad)

	# Scale vertices to match aspect ratio of the sprite
	var aspect_x = half_size
	var aspect_y = half_size * float(rect_h) / float(rect_w) if rect_w > 0 else half_size

	# Quad corner positions (before rotation)
	var corners = [
		Vector3(-aspect_x, aspect_y, 0),   # top-left
		Vector3(-aspect_x, -aspect_y, 0),  # bottom-left
		Vector3(aspect_x, -aspect_y, 0),   # bottom-right
		Vector3(aspect_x, aspect_y, 0),    # top-right
	]

	# Apply rotation around Z axis
	for i in corners.size():
		var c = corners[i]
		corners[i] = Vector3(
			c.x * cos_r - c.y * sin_r,
			c.x * sin_r + c.y * cos_r,
			0
		)

	var uvs = [
		Vector2(u_min, v_min),  # top-left
		Vector2(u_min, v_max),  # bottom-left
		Vector2(u_max, v_max),  # bottom-right
		Vector2(u_max, v_min),  # top-right
	]

	# Triangle 1: top-left, bottom-left, bottom-right
	st.set_uv(uvs[0])
	st.add_vertex(corners[0])
	st.set_uv(uvs[1])
	st.add_vertex(corners[1])
	st.set_uv(uvs[2])
	st.add_vertex(corners[2])

	# Triangle 2: top-left, bottom-right, top-right
	st.set_uv(uvs[0])
	st.add_vertex(corners[0])
	st.set_uv(uvs[2])
	st.add_vertex(corners[2])
	st.set_uv(uvs[3])
	st.add_vertex(corners[3])

	_mesh_instance.mesh = st.commit()

	# Load WEP1 indexed-grayscale texture + sidecar palette (ADR-0022).
	var texture = load(WEP1_TEXTURE_PATH)
	var palette = load(WEP1_PALETTE_PATH)
	if not texture or not palette:
		push_warning("[Projectile3D] Failed to load WEP1 texture/palette")
		_create_fallback_item_visual()
		return

	# Palette row matches the unit's held-weapon overlay convention from
	# BATTLE.BIN 0x2d3e4 (WeaponGraphicData). We only have the weapon TYPE
	# id at the projectile (not the specific item_id), so default to row 0 —
	# extract_spr.py notes row 0 reproduces the old RGBA-baked WEP1 colors.
	_mesh_instance.material_override = _create_paletted_sprite_material(texture, palette, 0)


func _create_fallback_item_visual() -> void:
	"""Create fallback visual if texture fails to load."""
	var sphere = SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	_mesh_instance.mesh = sphere
	_mesh_instance.material_override = _create_solid_material(Color.CYAN)


