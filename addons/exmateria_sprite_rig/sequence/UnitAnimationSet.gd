extends RefCounted

## Frozen per-sprite-type bundle of SEQ / SHP / layer-priority / name JSON
## the layer playbacks read from. Built once by `AnimationDatabase` and
## shared across every `Unit` of the same `(seq_type, shp_type)` pair.
##
## Fields are populated at construction by the database and treated as
## read-only afterward (GDScript has no true const fields — the contract
## is enforced by convention and the `_Avoid_` block in CONTEXT.md).
##
## See ADR-0034 and CONTEXT.md "### Animation playback".

const ANIMATION_FRAMERATE: float = 45.0

var type1_seq: Dictionary
var type1_shp: Dictionary
var wep_seq: Dictionary
var wep_shp: Dictionary
var eff1_seq: Dictionary
var eff1_shp: Dictionary
var layer_priority: Dictionary

var is_type2: bool = false

# Per-slot human-readable labels are NOT a field of the set. They live in the
# `AnimationNames` static loader (`<content_root>/sprites/animation_names.json`,
# built by `tools/build_animation_names.py` from TacticsEngineG), keyed by
# `sprite_type` (e.g. "type1", "mon", "wep1", "eff1"). Call
# `AnimationNames.get_label(sprite_type, slot)` — never a `*_names` field on
# this set. See ADR-0034.
