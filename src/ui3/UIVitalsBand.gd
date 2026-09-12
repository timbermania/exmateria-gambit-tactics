class_name UIVitalsBand
extends RefCounted
## The FFT menu "black gradient stripe" (FORMATION_SCREEN.md §14.6.6) — the SUBTRACTIVE
## band the vitals / info panels sit on, reproducing the ROM's `FUN_80112c88` iter 2. ONE
## shared UI element across the formation roster, the unit-detail / Status screen, and the
## battle HUD (extracted 2026-08-05 from FormationScene._build_band_backdrop).
##
## A trapezoid fg/255 grey subtracted in DISPLAY space from whatever is behind it, feathered
## at the band edges. It feathers on EITHER axis: the wide vitals stripe fades top/bottom
## (y feather); a narrow Eqp/Ability column band (§15.19) fades left/right (x feather) — the
## same element rotated, the same shader. On the fork it routes through the engine fold
## (Fold.add → the display-space scratch subtract); off-fork it re-samples an optional floor
## (the formation cobble) so the subtract stays a faithful clamp(floor − fg, 0).
##
## Usage: `var mat := UIVitalsBand.build(parent, spec, ppu, screen)` — returns the
## ShaderMaterial so the caller can keep pushing per-frame uniforms (e.g. formation's floor
## spotlight). See DetailScene (stripe + column bands) and FormationScene (the bottom band).

## Preloaded `Shader` objects, not paths — ADR-0191 dec. 2. This producer was MISSED by the
## 0191 build (its census claimed "19 shader-path String consts on the pick -> 0" while these two
## survived), and it was the exact hazard the decision names: `load()` of a mistyped path returns
## null, a null shader does not raise, and the fold "just stops, with no error". `preload` makes
## the same typo a parse error.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

const _FOLD_SHADER := preload("res://src/ui3/shaders/formation_band_fold.gdshader")
const _SCENE_SHADER := preload("res://src/ui3/shaders/formation_band.gdshader")


## Build the band under `parent`; returns its ShaderMaterial. `spec` fields:
##   x0, x1                                    — the quad's left/right (display px)
##   y_top_out, y_top_in, y_bot_in, y_bot_out  — the quad's top/bottom + the y trapezoid (px)
##   x_left_out, x_left_in, x_right_in, x_right_out — optional x trapezoid (px; omit ⇒ no x feather)
##   full_sub                                  — body fg/255 (oracle grey / 255)
##   rung                                      — fold depth rung; the band sits BEHIND the
##                                               panels/icons whose real Z occludes it
##   name                                      — node name (default "VitalsBand")
##   floor                                     — optional {index_atlas, palette_tex, tile_px,
##                                               screen_px} for the off-fork cobble re-sample
static func build(parent: Node3D, spec: Dictionary, ppu: float,
		screen: Vector2) -> ShaderMaterial:
	var x0: float = spec["x0"]
	var x1: float = spec["x1"]
	var y0: float = spec["y_top_out"]
	var y1: float = spec["y_bot_out"]
	var rung: int = int(spec.get("rung", 1))
	# This producer ASKS the predicate; it is no longer handed the answer (ADR-0191 dec. 13).
	# The four callers all passed Fold.owns() and nothing ever passed anything else, so the
	# parameter had exactly one reachable value and bought only the illusion of a test seam — the
	# off-fork half was never exercised through it. It is exercised now, through the same
	# `Fold._owns_cache` mutate-and-restore lever Amendment 2 kept for precisely this shape
	# (tests/FormationFoldRoutingTest.gd section 5), which is the lever that catches a producer
	# asking the predicate wrongly at its REAL call site — the thing a parameter cannot catch.
	var folded := Fold.owns()
	var band_z: float = DepthMode.rung_z(rung) if folded else 0.0

	var holder := Node3D.new()
	holder.name = String(spec.get("name", "VitalsBand"))
	holder.position = Vector3(x0 * ppu, -y0 * ppu, band_z)
	parent.add_child(holder)

	var mi := _quad(Vector2(x1 - x0, y1 - y0), ppu)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := ShaderMaterial.new()
	# THE two-way pick, in the one spelling ADR-0191 dec. 2 publishes. `folded` above is the same
	# cached build property this reads, asked twice in one function — the census counts SPELLINGS of
	# the pick, not asks, and the post-build census already records that asks rose (14 → ~48) and
	# calls that the honest number.
	mat.shader = Fold.shader(_FOLD_SHADER, _SCENE_SHADER)
	mat.set_shader_parameter("y_top_out", spec["y_top_out"])
	mat.set_shader_parameter("y_top_in", spec["y_top_in"])
	mat.set_shader_parameter("y_bot_in", spec["y_bot_in"])
	mat.set_shader_parameter("y_bot_out", spec["y_bot_out"])
	mat.set_shader_parameter("x_left_out", float(spec.get("x_left_out", 0.0)))
	mat.set_shader_parameter("x_left_in", float(spec.get("x_left_in", 0.0)))
	mat.set_shader_parameter("x_right_in", float(spec.get("x_right_in", 0.0)))
	mat.set_shader_parameter("x_right_out", float(spec.get("x_right_out", 0.0)))
	mat.set_shader_parameter("full_sub", spec["full_sub"])
	mat.set_shader_parameter("screen_h", screen.y)
	mat.set_shader_parameter("screen_w", screen.x)
	# The quad's screen rect — the fold shader reads the feather from the quad's OWN UV
	# (aspect-independent) using this + y_top_out/y_bot_out, not a full-screen FRAGCOORD.
	mat.set_shader_parameter("band_x0", x0)
	mat.set_shader_parameter("band_x1", x1)

	if folded:
		# Display-space fold like every other PSX add/sub prim: the scratch already holds the
		# scene behind the band (Pass A seed), so the fold shader subtracts the fg trapezoid.
		mi.material_override = mat
		holder.add_child(mi)
		Fold.add(mi, mat, band_z)
	else:
		# Off-fork fallback RE-SAMPLES an optional floor (formation cobble) to recover the true
		# per-pixel background and subtract fg from THAT — a principled subtract, no guessed floor.
		var floor: Dictionary = spec.get("floor", {})
		if not floor.is_empty():
			mat.set_shader_parameter("index_atlas", floor["index_atlas"])
			mat.set_shader_parameter("palette_tex", floor["palette_tex"])
			mat.set_shader_parameter("tile_px", floor.get("tile_px", Vector2(128.0, 32.0)))
			mat.set_shader_parameter("screen_px", floor.get("screen_px", screen))
		mat.render_priority = rung
		mi.material_override = mat
		holder.add_child(mi)
	return mat


## Reshape an ALREADY-BUILT band in place (no free/rebuild): resize the quad to the new x/y
## extent and push the new y-trapezoid feather params onto the SAME MeshInstance3D + material.
## This is the live-scrub path — the carrier is enrolled in the compositor render layer
## (build's `Fold.add` → FOLD_LAYER), and freeing a member while that layer is actively
## compositing corrupts the engine heap on the 4.8 fork, so a knob edit must MUTATE, never
## recreate. Membership + fold order are untouched (rung is unchanged by a top/bottom scrub),
## so the carrier stays put. `spec` uses build()'s x0/x1/y_* fields; only extent + feather move.
static func update_extent(mi: MeshInstance3D, mat: ShaderMaterial, spec: Dictionary, ppu: float) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var x0: float = spec["x0"]
	var x1: float = spec["x1"]
	var y0: float = spec["y_top_out"]
	var y1: float = spec["y_bot_out"]
	var q := mi.mesh as QuadMesh
	if q != null:
		# The holder sits at the top-left corner; recenter the quad so its TOP edge stays pinned
		# there and the height grows downward (matches _quad's top-left anchor idiom).
		q.size = Vector2(x1 - x0, y1 - y0) * ppu
		mi.position = Vector3(q.size.x * 0.5, -q.size.y * 0.5, 0.0)
	if mat != null:
		mat.set_shader_parameter("y_top_out", spec["y_top_out"])
		mat.set_shader_parameter("y_top_in", spec["y_top_in"])
		mat.set_shader_parameter("y_bot_in", spec["y_bot_in"])
		mat.set_shader_parameter("y_bot_out", spec["y_bot_out"])


## A TOP-LEFT-anchored quad of `size_px` (holder position = the top-left corner), the same
## idiom FormationScene/DetailScene use so the band aligns with the rest of the screen.
static func _quad(size_px: Vector2, ppu: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size_px * ppu
	mi.mesh = q
	mi.position = Vector3(q.size.x * 0.5, -q.size.y * 0.5, 0.0)
	return mi
