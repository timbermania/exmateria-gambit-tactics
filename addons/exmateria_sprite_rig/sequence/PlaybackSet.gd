extends RefCounted

## A unit's {BODY, WEP1, EFF1} animation triple (ADR-0025). Each unit has two:
## the normal set and the React set. They are structurally identical — the clock
## pumps both, and the body-lead cascade is the same shape in each (a BODY
## side-effect starts THIS set's WEP1/EFF1; WEP1 can cascade into THIS set's
## EFF1). The only difference is `is_react`, which flips the paint gate (the
## React set paints while `_react_active`, the normal set paints otherwise) and
## selects the shield-vs-weapon-remap branch. Instantiating one implementation
## twice with this flag is what collapses the old six near-duplicate handlers.
##
## C1c keeps the painters + cascade wiring on Unit (they move into UnitDisplay in
## C2a); this object is the grouping the clock pumps and the handlers key off.

# ADR-0212 dec. 1 — the class is INTERNAL to this addon: no global `class_name`,
# so an in-addon consumer preloads the file it wants.
const AnimationPlayback = preload("res://addons/exmateria_sprite_rig/sequence/AnimationPlayback.gd")

var body: AnimationPlayback
var wep1: AnimationPlayback
var eff1: AnimationPlayback
var is_react: bool


func _init(body_pb: AnimationPlayback, wep1_pb: AnimationPlayback,
		eff1_pb: AnimationPlayback, react: bool) -> void:
	body = body_pb
	wep1 = wep1_pb
	eff1 = eff1_pb
	is_react = react


## Step every layer in the set by one frame.
func advance_frame() -> void:
	body.advance_frame()
	wep1.advance_frame()
	eff1.advance_frame()
