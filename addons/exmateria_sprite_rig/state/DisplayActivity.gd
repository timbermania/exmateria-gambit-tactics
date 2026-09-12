# THIS FILE IS GENERATED -- DO NOT EDIT.
# Source of truth: tools/activity_taxonomy.yaml
# Regenerate: (cd tools && uv run python gen_activity_taxonomy.py)
#
# Reference enum members by name (DisplayActivity.Activity.IDLE), not by
# integer value -- the values are declaration-order and not a contract.
#
# NO `class_name` (#746, ADR-0212 dec. 1). addons/exmateria_sprite_rig puts
# exactly ONE global in a consumer's project and it is the facade, so this
# enum is reached as `ExMateriaSpriteRig.DisplayActivity.Activity.*` -- or,
# in the 22 host files that alias it, spelled exactly as it was before.
# Said HERE, at the generator, because that is where the regression would
# be reintroduced: a hand-fix to the .gd is overwritten by the next run.
extends RefCounted

enum Activity {
	IDLE,
	WALKING,
	USING_ITEM,
	ATTACKING,
	SPELL_CASTING,
	SPELL_CHARGING,
	DYING,
	CELEBRATING,
	AWAITING_IMPACT,
	IDLE_LOW_HEALTH,
	DEAD,
	JUMPING,
	LANDING,
	GETTING_UP,
}
