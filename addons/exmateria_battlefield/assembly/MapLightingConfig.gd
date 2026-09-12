extends RefCounted

## PSX-style lighting configuration for procedural maps.
##
## This class handles parsing lighting data from manifest.json and applying it
## to shader materials. Uses GaneshaDx-compatible two-pass lighting system.
## Vault: [[Map Darkness Opcode]]

# Lighting is read directly from each map's manifest.json (ROM-derived,
# GaneshaDx-compatible); there are no per-machine lighting overrides.


## Convert RGB8 (0-255) color to Vector3 (0.0-1.0) for shader uniforms.
static func color8_to_vector3(r: int, g: int, b: int) -> Vector3:
	const RGB8_TO_FLOAT = 1.0 / 255.0
	return Vector3(r * RGB8_TO_FLOAT, g * RGB8_TO_FLOAT, b * RGB8_TO_FLOAT)


## Convert spherical coordinates to Cartesian direction vector (PSX lighting).
##
## IMPORTANT: This matches GaneshaDx's SphereToVector() function exactly.
## Light directions use a DIFFERENT formula than surface normals:
## - Both angles offset by +90 degrees before conversion
## - Uses Sin*Sin, -Cos, Sin*Cos (not the standard Cos*Cos, Sin, Cos*Sin)
##
## Args:
##     elevation_deg: Elevation angle in degrees (from FFT spherical coords)
##     azimuth_deg: Azimuth angle in degrees (from FFT spherical coords)
##
## Returns:
##     Normalized direction vector matching GaneshaDx coordinate system
static func spherical_to_cartesian(elevation_deg: float, azimuth_deg: float) -> Vector3:
	# Match GaneshaDx's SphereToVector() exactly (Utilities.cs lines 220-229)
	# Then negate X to match our coordinate system (positions and normals have X negated)
	var elev_rad = deg_to_rad(elevation_deg + 90.0)  # +90° offset
	var azim_rad = deg_to_rad(azimuth_deg + 90.0)    # +90° offset

	var x = -sin(elev_rad) * sin(azim_rad)  # Negate X to match position/normal coordinate system
	var y = -cos(elev_rad)                   # Negated Y (from GaneshaDx)
	var z = sin(elev_rad) * cos(azim_rad)   # Sin*Cos (not Cos*Cos)

	return Vector3(x, y, z).normalized()


## Extract and convert lighting data from manifest.json for shader uniforms.
##
## Args:
##     manifest_data: Parsed manifest.json dictionary
##
## Returns:
##     Dictionary with keys: ambient, light1_color, light1_direction, etc.
##     Returns default lighting if manifest_data is empty or missing lighting section.
static func load_from_manifest(manifest_data: Dictionary) -> Dictionary:
	var lighting = {}

	# Default lighting (tuned for balanced appearance)
	var default_ambient = Vector3(0.5, 0.5, 0.5)  # High ambient for even lighting
	var default_light1_color = Vector3(0.792157, 0.807843, 0.831373)
	var default_light1_direction = Vector3(0.0, 1.0, 0.0)
	var default_light2_color = Vector3(1.0, 1.0, 0.996078)
	var default_light2_direction = Vector3(0.0, 1.0, 0.0)
	var default_light3_color = Vector3(0.4, 0.533333, 0.752941)
	var default_light3_direction = Vector3(0.0, -1.0, 0.0)

	# Check if manifest has lighting section
	if not manifest_data.has("lighting"):
		push_warning("[MapLightingConfig] manifest missing 'lighting' section, using defaults")
		lighting.ambient = default_ambient
		lighting.light1_color = default_light1_color
		lighting.light1_direction = default_light1_direction
		lighting.light2_color = default_light2_color
		lighting.light2_direction = default_light2_direction
		lighting.light3_color = default_light3_color
		lighting.light3_direction = default_light3_direction
		return lighting

	var lighting_data = manifest_data.lighting

	# Load ambient light (use map value directly like GaneshaDx)
	if lighting_data.has("ambient"):
		var ambient = lighting_data.ambient
		# GaneshaDx uses map ambient directly, multiplies by 1.5 in shader
		lighting.ambient = color8_to_vector3(ambient.r, ambient.g, ambient.b)
	else:
		lighting.ambient = default_ambient

	# Load directional lights (GaneshaDx-compatible)
	# NOTE: GaneshaDx never sets boost uniforms, so they default to (1,1,1) in shader
	# This creates darker shadows + saturated highlights (the "GaneshaDx look")
	if lighting_data.has("directional_lights") and lighting_data.directional_lights.size() >= 3:
		var lights = lighting_data.directional_lights

		# Light 1 (Key)
		var light1 = lights[0]
		lighting.light1_color = color8_to_vector3(light1.color.r, light1.color.g, light1.color.b)
		lighting.light1_direction = spherical_to_cartesian(
			light1.elevation,
			light1.azimuth
		)

		# Light 2 (Rim)
		var light2 = lights[1]
		lighting.light2_color = color8_to_vector3(light2.color.r, light2.color.g, light2.color.b)
		lighting.light2_direction = spherical_to_cartesian(
			light2.elevation,
			light2.azimuth
		)

		# Light 3 (Fill)
		var light3 = lights[2]
		lighting.light3_color = color8_to_vector3(light3.color.r, light3.color.g, light3.color.b)
		lighting.light3_direction = spherical_to_cartesian(
			light3.elevation,
			light3.azimuth
		)
	else:
		push_warning("[MapLightingConfig] manifest has fewer than 3 directional lights, using defaults")
		lighting.light1_color = default_light1_color
		lighting.light1_direction = default_light1_direction
		lighting.light2_color = default_light2_color
		lighting.light2_direction = default_light2_direction
		lighting.light3_color = default_light3_color
		lighting.light3_direction = default_light3_direction

	# Print loaded lighting for debugging

	return lighting


## Apply PSX lighting uniforms to a shader material.
##
## Loads lighting from manifest and sets all light-related shader parameters
## using GaneshaDx-compatible values (map ambient, no UserSettings scaling).
##
## Args:
##     material: The ShaderMaterial to configure
##     manifest_data: Parsed manifest.json dictionary
static func apply_to_material(material: ShaderMaterial, manifest_data: Dictionary) -> void:
	# Load lighting from manifest (GaneshaDx method)
	var lighting = load_from_manifest(manifest_data)

	# Use MAP's ambient color directly (GaneshaDx style)
	# Shader will multiply by 1.5
	material.set_shader_parameter("ambient_light", lighting.ambient)

	# Light colors from map (no scaling - GaneshaDx doesn't scale them)
	material.set_shader_parameter("light1_color", lighting.light1_color)
	material.set_shader_parameter("light1_direction", lighting.light1_direction)
	material.set_shader_parameter("light2_color", lighting.light2_color)
	material.set_shader_parameter("light2_direction", lighting.light2_direction)
	material.set_shader_parameter("light3_color", lighting.light3_color)
	material.set_shader_parameter("light3_direction", lighting.light3_direction)

	# Boost uniforms default to vec3(0) in shader — no need to set them
