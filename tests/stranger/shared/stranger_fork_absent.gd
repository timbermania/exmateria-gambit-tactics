extends Node
## ADR-0194 dec. 7's second arm, and the only one that can go red on GOOD news.
##
## An addon declares its engine in `plugin.cfg`. A `fork` declaration is a claim
## about the world — *"this addon needs primitives stock Godot does not have"* —
## and a claim nothing checks is the thing ADR-0194 exists to stop: `docs/GOALS.tsv`
## scores `Audio` goal #4 open in the words *"a reading is not a guard."*
##
## So the rig boots STOCK once and asserts the primitive is ABSENT. The day the
## fork's compositor primitives land upstream this goes red and reports that the
## addon can be downgraded — a win nobody would otherwise notice.
##
## WRITTEN REFLECTIVELY, AND THAT IS NOT STYLE. ADR-0194 dec. 7 words the arm as
## *"asserts `RenderingServer.is_compositor_layer_supported()` is false"*, and that
## line CANNOT BE WRITTEN: on stock 4.7.1 it is a GDScript **parse error** —
## `Static function "is_compositor_layer_supported()" not found in base
## "GDScriptNativeClass"` — so the script does not load and the arm reports nothing
## at all rather than reporting false. Measured, not guessed. `has_method` is the
## question the arm actually wants: the fork primitive is absent when the METHOD
## does not exist, not when it returns false.

## 🔴 THIS SCENE IS SUBJECT-INDEPENDENT, SO IT MUST NOT NAME WHOSE DECLARATION IT
## CHECKED. It hardcodes the primitives and asks the ENGINE what it has; nothing here
## reads the staged addon. Until #1099 the PASS line ended *"so this addon's
## `engine="fork"` declaration is a checked fact"* — false for any subject whose own
## declaration is `stock` and whose dependency CLOSURE is what needs the fork.
## `exmateria_catalogue` is exactly that, and the sentence asserted a declaration its
## `plugin.cfg` does not make. `rig.sh` holds both values and owns the interpretation;
## this scene reports only what it measured.

const PRIMITIVES := [
	"RenderingServer.is_compositor_layer_supported()",
	"ClassDB CompositorRenderLayer",
]


func _ready() -> void:
	var rs := RenderingServer
	var has_method := rs.has_method("is_compositor_layer_supported")
	var has_class := ClassDB.class_exists("CompositorRenderLayer")
	print("[ok] engine: %s" % Engine.get_version_info().get("string", "?"))
	print("[ok] %s present: %s" % [PRIMITIVES[0], str(has_method)])
	print("[ok] %s present: %s" % [PRIMITIVES[1], str(has_class)])

	if has_method or has_class:
		print("[FAIL] this is meant to be the STOCK engine and it carries the fork's "
			+ "compositor primitives. Either the rig booted the fork by mistake — in "
			+ "which case the arm proved nothing — or the primitives landed upstream "
			+ "and a declaration resting on them can be dropped. Both are reportable; "
			+ "neither is a pass.")
	else:
		print("[PASS] the fork's compositor primitives are absent from stock")
	get_tree().quit()
