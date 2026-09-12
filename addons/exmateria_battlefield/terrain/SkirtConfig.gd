@tool

## Runtime-mutable skirt configuration for debug panel experimentation.
##
## Single source of truth for skirt geometry parameters. Each parameter is a Tune
## tunable (ADR-0068): the property getter coalesces the `skirt.*` override over the
## code default, the setter routes writes through Tune, and SkirtDebugPanel is a pure
## TuneField VIEW (decision 12). Readers keep using `SkirtConfig.<prop>` unchanged — the
## value now persists + applies at boot in any scene, not only while the panel is open.
##
## A `class_name`, NOT an autoload (ADR-0183 dec. 1/2). An `[autoload]` line can only be
## written by the consuming game's `project.godot` — an install step, not an interface —
## so `Battlefield` could not publish one and still ship. This class holds NO instance
## state: the three consts plus getters that are pure `Tune` reads, so the static shape
## costs nothing and its own `_static_init` registers every slug at class load — exactly
## like `SkirtGeometryGenerator`, and with no central replay naming either of them
## (ADR-0173 deleted `Tune.register_all()` and its list of owner script paths).
##
## `PROPERTY_META` is the single home for each parameter's code default AND its
## affordance metadata, so the panel + the getters share one source.

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const TunePort = ExMateriaPlatform.TunePort

# Property metadata for data-driven debug panel + Tune defaults (the "default" key is
# the code default's single home, read by both the getters below and the panel).
const PROPERTY_META = {
	"water_skirt_enabled": {"label": "Enabled", "type": "bool", "default": false, "group": "water"},
	"water_skirt_depth": {"label": "Depth", "type": "float", "default": 0.15, "min": 0.0, "max": 1.0, "step": 0.01, "group": "water"},
	"water_skirt_inset": {"label": "Inset", "type": "float", "default": 0.001, "min": -0.1, "max": 0.1, "step": 0.001, "group": "water"},
	# BOTH `*_skirt_enabled` default to FALSE. The land skirt mirrors geometry the map
	# does not ask for, and the skirts were removed together as one decision, so the
	# generator now emits nothing unless a `skirt.*` override turns it back on.
	#
	# Read the measurement below with that in mind: at `water_surface_offset` 0.0 the
	# water skirt WAS closing the water/land join (11,217 px), so shipping it off can
	# reopen a seam there. That was accepted knowingly. If a join crack shows up on a
	# water map, `skirt.water_skirt_enabled = true` is the first thing to try, and the
	# code path is kept — not deleted — precisely so that stays a one-line experiment.
	# `water_surface_offset` defaults to 0.0 and the knob survives only for diagnosis.
	# A lift applied to the water materials and to NOTHING ELSE opens a see-through
	# crack along every edge where a water triangle meets a non-water one, because only
	# one side of that shared edge moves. Measured on MAP009 (Citadel of Igros): the
	# crack is 1 px at 0.01 and ~3 px at 0.03 — linear in the lift — and it shows the
	# sky or the stone behind. Its old "covers skirt tops" rationale is the reverse of
	# what it did: at 0.01, disabling the water skirt entirely changes 44 px of a
	# 983,040 px frame, so the skirt is covering nothing; at 0.0 it changes 11,217, so
	# the skirt is what closes the join. See `SkirtGeometryGenerator`.
	"water_surface_offset": {"label": "Surface Offset", "type": "float", "default": 0.0, "min": -0.1, "max": 0.1, "step": 0.001, "group": "water"},
	"land_skirt_enabled": {"label": "Enabled", "type": "bool", "default": false, "group": "land"},
	"head_on_slope_tolerance": {"label": "Slope Tolerance", "type": "float", "default": 0.05, "min": 0.0, "max": 0.5, "step": 0.01, "group": "detection"},
	"head_on_drop_depth": {"label": "Drop Depth", "type": "float", "default": 0.25, "min": 0.0, "max": 1.0, "step": 0.01, "group": "detection"},
	"head_on_inset": {"label": "Inset", "type": "float", "default": 0.001, "min": -0.1, "max": 0.1, "step": 0.001, "group": "detection"},
}

const GROUP_TITLES = {
	"water": "Water Skirt",
	"land": "Land Skirt (Mirrored)",
	"detection": "Flat/Sloped Detection",
}

# Group ordering for debug panel
const GROUP_ORDER = ["water", "land", "detection"]


## Bind at class load — the replacement for the autoload's `_ready()`. Editor-guarded for
## the same reason the getters are: this script is @tool and `Tune` is a non-@tool
## placeholder in the editor. Mirrors `SkirtGeometryGenerator._static_init`.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## Register every `skirt.*` slug from PROPERTY_META (ADR-0068 R5), so `_tget` PULL-reads
## via Tune.get_value and the dashboard enumerates them without a prior read. Static so
## `_static_init` calls it at class load; a test that wants the binds standing after a clear
## uses `Tune.reset_overrides()`, which never removes them (ADR-0173).
static func register_tunables() -> void:
	if Engine.is_editor_hint():
		return
	for prop: String in PROPERTY_META:
		TunePort.bind("skirt." + prop, PROPERTY_META[prop]["default"])


## Coalesce a parameter's `skirt.*` override over its PROPERTY_META default (ADR-0068).
## @tool-guarded: Tune.gd is not @tool, so in the editor it is a placeholder that can't
## be called — fall back to the code default there.
static func _tget(prop: String) -> Variant:
	if Engine.is_editor_hint():
		return PROPERTY_META[prop]["default"]
	return TunePort.get_value("skirt." + prop, PROPERTY_META[prop]["default"])


## Route a parameter write through Tune (no-op in the @tool editor).
static func _tset(prop: String, value: Variant) -> void:
	if Engine.is_editor_hint():
		return
	TunePort.set_value("skirt." + prop, value)


# Water skirt parameters — Tune-backed (see PROPERTY_META for defaults + ranges).
static var water_skirt_enabled: bool:
	get: return _tget("water_skirt_enabled")
	set(v): _tset("water_skirt_enabled", v)
static var water_skirt_depth: float:
	get: return _tget("water_skirt_depth")
	set(v): _tset("water_skirt_depth", v)
static var water_skirt_inset: float:
	get: return _tget("water_skirt_inset")
	set(v): _tset("water_skirt_inset", v)
static var water_surface_offset: float:
	get: return _tget("water_surface_offset")
	set(v): _tset("water_surface_offset", v)

# Land skirt parameters. Land skirts use mirrored geometry, so depth/inset are
# determined by the original triangle's shape rather than configurable values.
static var land_skirt_enabled: bool:
	get: return _tget("land_skirt_enabled")
	set(v): _tset("land_skirt_enabled", v)

# Head-on boundary detection parameters. Head-on/flat = land that doesn't slope down
# toward water (mirror would create horizontal geometry); Sloped = land that descends
# toward water (mirror extends geometry downward, works well).
static var head_on_slope_tolerance: float:  # v2 more than this above the edge ⇒ "sloped" (use mirror)
	get: return _tget("head_on_slope_tolerance")
	set(v): _tset("head_on_slope_tolerance", v)
static var head_on_drop_depth: float:  # how far below water surface to extend the vertical drop skirt
	get: return _tget("head_on_drop_depth")
	set(v): _tset("head_on_drop_depth", v)
static var head_on_inset: float:  # inset from edge to avoid z-fighting
	get: return _tget("head_on_inset")
	set(v): _tset("head_on_inset", v)
