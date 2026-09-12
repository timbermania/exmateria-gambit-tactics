class_name UnitAssets
extends RefCounted
## The HOST's address for the authored unit material — the one place four call sites
## used to spell for themselves (ADR-0217 dec. 12).
##
## [code]assets/materials/unit.tres[/code] is the authored base every unit material starts
## from: the texture atlases, the atlas sizes, the calibrated [code]ambient_brightness[/code]
## and the zeroed tile arrays. It is [b]not[/b] the rig's to address. `Sprite Rig` publishes
## [method UnitMaterial.for_variant], which now takes the base as a PARAMETER — the same
## shape as the nine gitignored content injections ADR-0215 classes B — so the addon holds
## no [code]res://assets/[/code] address for it and the host says which file it is.
##
## ADR-0215 dec. 7 ruled the other way, [i]publish, do not move[/i], on the ground that a
## move trades one outbound reference for four inbound ones. ADR-0217 dec. 12 overturns it:
## injection removes the address without paying that cost, and it fixes something dec. 7
## did not notice — [code]Unit.gd[/code] and three [code]tests/[/code] each [code]load()[/code]d
## this path independently, so there were four spellings of one fact and nothing tying them
## together.
##
## [b]One exception, deliberately.[/b] [code]tests/UnitMaterialVariantTest.gd[/code] keeps its
## own literal. It reads the file as TEXT to enumerate the [code]shader_parameter/[/code] keys
## the shaders must declare — it is the independent oracle for that block, and routing it
## through this constant would let a repoint here move the oracle silently. Same argument
## ADR-0189 dec. 8 makes for [code]ScenarioDeadUnitFadeTest[/code].
##
## [b]The shader line is NOT injectable, and this is the note that saves you the day.[/b]
## ADR-0222 predicted this material's last addon reference would drain, and the shape
## settled on was the one above: drop its shader declaration, load the file here, and set
## [code]mat.shader[/code] before returning. Measured on 2026-09-03 by [code]tools/probe_unitres_shader_drain.gd[/code]
## and it does not work — [code]ShaderMaterial[/code] only accepts a
## [code]shader_parameter/x[/code] assignment while it already holds a valid shader, so a
## material that names none loses every one of its thirty-nine authored parameters at
## PARSE time. All thirty-nine read back null before the injection and all thirty-nine
## after it. Saving in that state is worse: the property list is enumerated from the
## current shader's uniforms, so a round trip writes back none of them and says nothing.
## The declaration is what makes the rest of the file mean anything, and the reference is
## a declared mount now (ADR-0222 dec. 4) rather than debt.

## The authored base material. The host's address, named once.
const BASE_MATERIAL := "res://assets/materials/unit.tres"


## The authored base, loaded. Callers that want their own copy still [code]duplicate()[/code]
## it — this hands back the shared resource, exactly as a bare [code]load()[/code] did at each
## of the four sites it replaces, so nothing about lifetime or caching changes.
static func base_material() -> ShaderMaterial:
	var mat := load(BASE_MATERIAL) as ShaderMaterial
	if mat == null:
		push_error("[UnitAssets] %s is missing or is not a ShaderMaterial" % BASE_MATERIAL)
	return mat
