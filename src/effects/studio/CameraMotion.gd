extends RefCounted
## The tagged-union AUTHORING VIEW of the camera command word's interpolation field
## (bits 9-12, mask 0x1E00). That ONE 4-bit ROM field encodes both a motion KIND — a track
## either moves toward a target OR shakes, never both, because it is the same field — and a
## per-kind PROFILE (Move → an easing curve; Shake → a decay). The runtime, writer, and
## storage keep the single field; this module is purely how the inspector presents and edits
## it: a "Motion" binary + a kind-scoped "Profile" enum, both writing the interp bits.
##
## Mirrors CameraChannel._INTERPOLATIONS / parse_effect.CAMERA_INTERPOLATIONS — the ONE ROM
## layout. Pure static, no runtime deps (no `class_name` per ADR-0004).

const MOVE := "Move"
const SHAKE := "Shake"

# The interp bit where SHAKE begins — 0x1000 (SHAKE_DAMPED) and up are shakes; the seven
# lower mapped values (0x0200..0x0E00) are move-to-target easings.
const _SHAKE_FLOOR := 0x1000

# Per-kind PROFILE enum entries. VALUE is the full positioned interp bits so the enum cell
# fans it straight to the "interpolation" field. Move keeps the ROM easing names; Shake drops
# the "SHAKE_" prefix (the Motion row already says "Shake") — Damped/Direct/Damped B.
const _MOVE_PROFILES := [
	{"value": 0x0200, "label": "IMMEDIATE"}, {"value": 0x0400, "label": "COSINE_A"},
	{"value": 0x0600, "label": "COSINE_B"}, {"value": 0x0800, "label": "LINEAR"},
	{"value": 0x0A00, "label": "COSINE_C"}, {"value": 0x0C00, "label": "ADDITIVE"},
	{"value": 0x0E00, "label": "ADDITIVE_B"},
]
const _SHAKE_PROFILES := [
	{"value": 0x1000, "label": "Damped"}, {"value": 0x1200, "label": "Direct"},
	{"value": 0x1400, "label": "Damped B"},
]

# The Motion binary's two choices. VALUE is each kind's DEFAULT interp bits, so flipping the
# selector writes that kind's default profile (Move → LINEAR, Shake → SHAKE_DAMPED). This same
# value is what the Motion row SEEDS to (see representative), so the enum highlights the current
# kind for any active profile.
const KIND_CHOICES := [
	{"value": 0x0800, "label": "Move (to target)"},
	{"value": 0x1000, "label": "Shake"},
]


## The motion kind of a (positioned) interpolation bit value. 0x1000+ ⇒ Shake; anything
## below (including unmapped/zero) ⇒ Move — the safe default that never reinterprets the
## value rows as amplitude.
static func kind_of(interp_bits: int) -> String:
	return SHAKE if (interp_bits & 0x1E00) >= _SHAKE_FLOOR else MOVE


## The PROFILE enum entries for a kind — the second inspector row, scoped so the author only
## sees the profiles that apply (easings under Move, decays under Shake).
static func profile_choices(kind: String) -> Array:
	return _SHAKE_PROFILES if kind == SHAKE else _MOVE_PROFILES


## The representative interp bits for a kind — the value the Motion row SEEDS to so it
## highlights the right binary regardless of which profile is active, and the default profile
## a kind-flip writes. It is the KIND_CHOICES value for that kind.
static func representative(kind: String) -> int:
	return 0x1000 if kind == SHAKE else 0x0800
