extends RefCounted
## `Sprite Rig`'s unit-sprite material, published as a VARIANT (ADR-0189 dec. 3).
##
## Every unit sprite in the game — battle, formation roster, cutscene — is drawn by one
## compositor. What differs between the three is the BLEND, and `render_mode` has to sit
## in the entry `.gdshader` because Godot has no runtime blend switch. So there are three
## shader files, and the question a consumer actually has is not "which file" but "which
## variant".
##
## Before this module, the only answer available was to reach into a `ShaderMaterial` and
## overwrite its `.shader` with a path the consumer named itself — `FormationScene` and
## `ScenarioVM` each did exactly that, in one line, and one of them grew a 1,018-line
## fork of the compositor to have a path worth naming. `SpriteLayerManager.initialize`
## takes its material from the caller; that parameter is the hole this closes from the
## other side. **No file outside `Sprite Rig` names a unit shader path.**
##
## The authored base — texture atlases, atlas sizes, the calibrated `ambient_brightness`,
## and the zeroed tile arrays — is INJECTED, not addressed. `for_variant` takes it as a
## parameter and hands back a DUPLICATE of it: a unit's tile parameters are per-instance and
## pushed every frame, so sharing one material would put one unit's pose on every other unit
## on screen.
##
## 🔴 THE BASE IS A PARAMETER BECAUSE THE ADDRESS IS NOT THIS MODULE'S (ADR-0217 dec. 12).
## A `const BASE_MATERIAL` naming the host's authored `.tres` used to sit here, which is an
## address into the host's asset tree from inside what becomes
## `addons/exmateria_sprite_rig/` — and the extraction predicts zero of those. The literal
## is deliberately NOT quoted in this note: `check_lattice_scene.py` scores comments
## (ADR-0208 dec. 7), so a paragraph quoting a paid path re-creates the row it describes. ADR-0215 dec. 7 had ruled *publish, do not move* on the
## ground that moving the file trades one outbound reference for four inbound ones; injection
## removes the address without paying that, and it also gives the four call sites that
## `load()`d the path independently a single source (`UnitAssets.base_material()`, host-side).
## The variant table below stays: those three files ARE this module's, and they move with it.

## The blend a consumer is asking for — ADR-0215 dec. 2 / ADR-0217 dec. 7 move the
## VALUE SET into the kernel; this module keeps its class name and the table below,
## because *which shader file* is `Sprite Rig`'s to know and *which variant* is the
## vocabulary. Spelled `UnitMaterialVariant` and NOT the bare tail `Variant`, which
## is Godot's own type name — `src/ui3/formation/FormationScene.gd` annotates seven
## live values with the builtin, so a local `const Variant` there would silently
## re-type them to this enum.
const UnitMaterialVariant = ExMateriaSchema.UnitMaterialVariant.Kind

## The variant table. These paths are `Sprite Rig`'s to know; that is the whole point.
const _SHADERS := {
	UnitMaterialVariant.OPAQUE: "res://addons/exmateria_sprite_rig/render/unit.gdshader",
	UnitMaterialVariant.ADDITIVE: "res://addons/exmateria_sprite_rig/render/unit_additive.gdshader",
	UnitMaterialVariant.FLAT: "res://addons/exmateria_sprite_rig/render/unit_flat.gdshader",
}


## A configured material for `variant` — a fresh duplicate of `base`, so the caller owns it
## and may push its own per-unit parameters into it. `base` is the host's authored material
## (`UnitAssets.base_material()`); this module does not know where it lives.
static func for_variant(variant: UnitMaterialVariant, base: ShaderMaterial) -> ShaderMaterial:
	if base == null:
		push_error("[UnitMaterial] for_variant(%s) needs a base material — the host injects it"
			% str(variant))
		return null
	var mat: ShaderMaterial = base.duplicate()
	mat.shader = shader_for(variant)
	return mat


## The shader alone. For a consumer that already owns a live material and is changing only
## the blend mid-animation — every uniform it has pushed carries over, which is what
## `tests/UnitMaterialVariantTest.gd` pins.
static func shader_for(variant: UnitMaterialVariant) -> Shader:
	var path: String = _SHADERS.get(variant, "")
	if path.is_empty():
		push_error("[UnitMaterial] Unknown variant %s" % str(variant))
		return null
	return load(path)
