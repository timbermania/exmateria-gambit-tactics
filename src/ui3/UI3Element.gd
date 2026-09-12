class_name UI3Element
extends Node3D

## The registered-element carrier (ADR-0088; interfaces in docs/ui3-element-interfaces.md).
## An element is a named logical part with its own origin — anything moved, animated,
## clipped, or cited against the oracle AS A UNIT. Everything inside it is payload.
##
## The spec is ONE Dictionary literal at the construction site (ADR-0068 E2/M5 — the
## materialise-rewritable home for every authored field):
##
##     var header := UI3Element.new({
##         "id": "picker.header",
##         "rect": Rect2(76, 135, 174, 24),
##         "transition": UI3Element.Transition.RIDE_PARENT,
##         "frame": UI3Element.Frame.NONE,
##         "clip": UI3Element.Clip.PARENT_APERTURE,
##     })
##     parent_element.add_child(header)
##
## The movable-origin two-model split is built in ONCE (the EquipPickerMenu
## FRAME_HOME / DetailScene STATS_FRAME0 idiom): the live rect places THIS node's
## transform; content mounts through rel_world(), which subtracts the FROZEN
## authored_home — so "move the frame, content rides" stops being a per-class idiom.
## Parent = nearest registered ancestor, resolved on _enter_tree; the scene tree IS
## the registry (UI3Registry holds only an index, never a parallel hierarchy).
##
## Widgets (UIComponent subclasses) construct with NO spec and answer criteria per
## field at class level via _register_criteria()/answer(); validation then runs at
## _enter_tree instead of _init. Either way an unanswered question cannot boot
## silently: collect-all push_error + assert.

const TunePort = ExMateriaPlatform.TunePort

## The role criterion (ADR-0088 Amendment 5) — elementhood is per-instance, not per-class.
## ELEMENT = a named part with its own origin: registers in UI3Registry, mints its id slug,
## REQUIRES id+rect, gets a UI3-page row. PAYLOAD = interior/templated content that rides its
## parent: no registration, no slug, and validate_spec does NOT require id/rect. The default
## depends on the construction path — a code-built `new({spec})` element is ELEMENT (the
## construction-site dict names a real element); the widget path (empty spec, answers
## accumulate) defaults PAYLOAD, which is what makes the UIComponent base-swap boot-safe (the
## ~9 un-migrated subclasses ride PAYLOAD until individually migrated).

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

enum Role { ELEMENT, PAYLOAD }
## The transition criterion — names the beat the TransitionEngine plays on open/close.
##
## APPEND-ONLY. These ints are authored as literals in construction-site specs AND persisted
## as Tune overrides for the F3 criterion knobs, so a new kind goes on the END — inserting one
## would silently re-point every stored answer at a different beat.
enum Transition { NONE, BOX_OPEN, SLIDE, RIDE_PARENT, FADE }
## The move criterion (ADR-0097 §5) — names the beat `place_at()` plays, the WHERE verb's
## own beat slot. NONE (and an absent field) = SNAP, which is what place_at did before this
## existed, so every caller is unchanged until a move is opted into.
##
## Its OWN enum rather than a second `transition` slot, deliberately: a move needs no
## reverse (the reverse of place_at("centre") is place_at("docked") — self-inverse by
## argument, not by polarity), so an open/close beat in this slot would be a beat whose
## reverse_drive is meaningless, and a move beat in the transition slot would be one with no
## reverse at all. One enum per slot makes both nonsense states unrepresentable instead of
## catchable by a runtime precondition.
enum Move { NONE, SLIDE }
## The frame criterion — which UIFrame chrome variant the element builds (NONE = no chrome).
enum Frame { NONE, MENU_TILE, STRIPE }
## The clip criterion — how the ClipEngine apertures this element's payload.
enum Clip { PARENT_APERTURE, OWN_APERTURE, UNCLIPPED }
## Where a criterion's value comes from, for the UI3 page (interfaces §6): AUTHORED =
## a literal in this element's spec (has a minted slug); INHERITED = resolved through
## the ancestor chain; DERIVED = computed from driver tunables (mints no slug);
## AT_LOCATION (Amendment 3 §1) = a SHARED key-location bind owned by another class
## that this element answers with — distinct from AUTHORED (that class owns the slug,
## many elements can ride it), so the page can name it + offer re-home.
## SCREEN_ANCHORED (Amendment 4 §1) = the element is a screen-anchored assembly (origin
## pinned at screen 0,0, every payload mounted at absolute display px) — it has NO
## independent placement, so the page renders an honest knob-less row instead of a
## read-only (derived) dead-end, and the no-empty-DERIVED audit (§3) exempts it.
enum Source { AUTHORED, INHERITED, DERIVED, AT_LOCATION, SCREEN_ANCHORED, HOST_DERIVED }

## Root-of-chain defaults for the inherited-defaulted criteria (ADR-0088 §3) — the ONE
## home that kills the six per-class PIXELS_PER_UNIT copies.
const DEFAULT_PPU := 0.04
const DEFAULT_DEPTH_RUNG := 0

## The per-VERB cadence criteria (ADR-0097 §2): an element that declares a beat must name a
## cadence for each verb that beat serves. `transition` serves open+close, `move` serves the
## one WHERE verb. The VALUES belong to the beat's own vocabulary (there is deliberately no
## global curve enum) — these are only the field names the audits and the F3 mint agree on.
const OPEN_CADENCE := "open_cadence"
const CLOSE_CADENCE := "close_cadence"
const MOVE_CADENCE := "move_cadence"

## "No call-site override — use this element's authored cadence" (ADR-0097 §4). Every
## vocabulary's members are >= 0, so a negative sentinel cannot collide with a real answer,
## and DEFAULT (0) stays a legal thing to pass: overriding TO the house rule is meaningful.
const NO_CADENCE_OVERRIDE := -1

## Emitted when this element's OWN aperture changes (transition drive or rect scrub).
signal aperture_changed(rect: Rect2i)
## Emitted once when an open() transition settles (immediately for NONE/RIDE_PARENT).
signal opened
## Emitted once when a close() transition finishes (immediately for NONE/RIDE_PARENT).
signal closed
## Emitted once when a place_at() move finishes (immediately for Move.NONE — the snap).
signal moved

# The criteria spec: the construction-site dict (code-built path) or the accumulated
# answer() fields (widget path). Literal-authored fields in here are what auto-binds mint.
var _spec: Dictionary = {}
# True once the spec has been validated + captured (at _init when a spec was passed,
# else at _enter_tree after _register_criteria).
var _adopted := false
# True once _register_criteria() ran (widget path answers; once per element).
var _criteria_registered := false

var _id := ""
# Live rect (display px). Starts at the authored literal; a rect scrub (auto-bind,
# slice 4) moves it — and only the element's transform, never the content offsets.
var _rect := Rect2()
# The FROZEN content anchor: the authored rect literal's position (or the spec's
# explicit "authored_home") — NOT the live rect. Subtracted by rel_world().
var _home := Vector2.ZERO
# Nearest registered ancestor, resolved on _enter_tree (null for a top-level element).
var _parent_element: UI3Element = null
# The live aperture (display px; OWN_APERTURE elements). Settled default = the live
# rect; a transition beat drives it via _set_aperture.
var _aperture := Rect2i()
# The element-built chrome (the `frame` criterion's UIFrame; null for Frame.NONE).
var _chrome: UIFrame = null
# False while the TransitionEngine is playing this element's beat.
var _settled := true
# The call-site cadence override in force for the CURRENT play (ADR-0097 §4), or -1 for
# "none — use the authored value". Set/cleared by UI3TransitionEngine around a play, never
# authored: it is situational (a whole screen unwinding wants its open picker to snap) and
# so must not become a standing element property.
var _cadence_override := -1
# The move play's own override. TWO slots, not one: a move can play CONCURRENTLY with an open
# (the reason move is a second beat slot rather than a third direction), so a shared slot would
# let the two re-cadence each other.
var _move_cadence_override := -1
# The move play's endpoints, captured by place_at: where the element stood, and the rect the
# new key location evaluates to. The beat reads them off the element because they are per-PLAY
# state (a destination argument), not authored criteria.
var _move_from := Rect2()
var _move_to := Rect2()
# False while the TransitionEngine is playing this element's MOVE beat.
var _move_settled := true
# Spec fields whose auto-bind was already minted (answer() mints at its own line for
# the M2 capture; _mint_binds must not add a SECOND on_update for those).
var _bound_fields: Dictionary = {}
# Rect-driver slugs already subscribed (derived/at answers + place_at re-homes):
# Tune has no unsubscribe short of tree exit, so repeated re-homing dedups here.
var _rect_driver_subs: Dictionary = {}


## A derived placement (interfaces §5): rect = f(driver tunables). Mints NO slug —
## the drivers are ordinary pinnable binds in the owner (E3, R7 "derive, don't
## duplicate"); the element re-evaluates + re-places on every driver scrub and the
## page renders it read-only.
class DerivedRect:
	extends RefCounted
	## The Tune slugs whose scrubs re-evaluate this placement.
	var drivers: Array
	## `func() -> Rect2` — the placement, computed from the drivers' live values.
	var eval: Callable
	## Non-empty only for the at-location answer form (set by `at()`): the shared
	## key-location slug this placement reads. Empty for a plain `derived()` — the field,
	## not a subclass, tells the two forms apart (Amendment 3 §1).
	var location_slug: String = ""
	## True only for the host-derived answer form (set by `host_derived()`): the element's
	## geometry is RECOMPUTED BY ITS HOST on every build, so it has no authored value for
	## ANY field and mints no `<id>.*` knob at all (see `host_derived` for why).
	var host_derived: bool = false
	## True only for the screen-anchored answer form (set by `screen_anchored()`): the
	## element is an assembly pinned at screen origin with no independent placement, so
	## `criteria()` reports Source.SCREEN_ANCHORED and the no-empty-DERIVED audit exempts
	## it — a field, not a subclass, keeps the three derived forms one class (Amendment 4 §1).
	var screen_anchored: bool = false

	func _init(p_drivers: Array, p_eval: Callable) -> void:
		drivers = p_drivers
		eval = p_eval


## Author a derived placement: `"rect": UI3Element.derived(["picker.rows.row0_y",
## "picker.rows.pitch"], func() -> Rect2: ...)`. A bare Callable is also accepted as
## the rect answer (re-evaluated only on explicit refresh) — the drivers form is the
## recommended one; it removes the last hand-wired refresh path.
static func derived(drivers: Array, f: Callable) -> DerivedRect:
	return DerivedRect.new(drivers, f)


## Author an at-location placement (ADR-0088 Amendment 2): the THIRD rect answer
## form (literal | derived | at-location) — sugar for a DerivedRect whose single
## driver is the key-location slug and whose eval reads the location's LIVE value,
## so scrubbing the location re-places every element that answers with it through
## the existing driver machinery. The slug must be bound by its OWNER class before
## the element constructs (a `static var` home + bind-on-first-instance — class
## statics exist before any element boots); a typo'd slug fails loudly in
## Tune.get_value's bind assert (no declared candidate set — the owner's
## static-var block documents the legal homes).
static func at(location_slug: String) -> DerivedRect:
	var d := DerivedRect.new([location_slug],
		func() -> Rect2: return Rect2(TunePort.get_value(location_slug, Rect2())))
	d.location_slug = location_slug
	return d


## Author a screen-anchored placement (ADR-0088 Amendment 4 §1): the FOURTH rect answer
## form (literal | derived | at-location | screen-anchored) for an assembly with no
## independent placement — origin pinned at screen (0,0), every payload mounted at
## absolute display px under it. Replaces the `derived([], func: Rect2(0,0,SCREEN))`
## sentinel whose width/height meant nothing: it mints no slug (an authored size would be
## a lying knob), reports Source.SCREEN_ANCHORED so the page renders an honest knob-less
## row, and is exempt from the no-empty-DERIVED audit (§3) — the marker that separates an
## INTENTIONALLY-unplaced element from an author who forgot to declare its drivers.
static func screen_anchored() -> DerivedRect:
	var d := DerivedRect.new([], func() -> Rect2: return Rect2())
	d.screen_anchored = true
	return d


## Author a HOST-DERIVED placement (the FIFTH rect answer form) for an element whose whole
## geometry its host recomputes on every build — the gambit CHOICE list, which opens under
## whichever column the cursor is on and is torn down and rebuilt on the next press.
##
## === WHY THIS IS A FORM AND NOT A LITERAL ===================================================
##
## A literal rect mints `<id>.rect`, and `Tune._register` is FIRST-WRITE-WINS: a second bind on
## a live slug keeps the original default and `on_update` immediately calls the new element
## back with it. So an element rebuilt under the SAME id with different geometry silently
## snaps to the FIRST build's rect — while `authored_home` (never a knob) stays correct. The
## two then disagree, `rel_world` compounds the delta, and the payload lands outside the
## element's own `OWN_APERTURE` scissor: it renders as a perfectly drawn, completely EMPTY
## frame at the previous instance's position. No error, no failing assert. That is the defect
## this form exists to make unauthorable, measured on the gambit choice list where the FIRST
## part opened drew and every later one did not (#1081).
##
## === SO IT MINTS NOTHING, AND THAT IS THE POINT =============================================
##
## Not just `rect`: every `<id>.<field>` knob on such an element is a LYING knob, because the
## host recomputes the field on the next build and a scrub is overwritten by the next open.
## `screen_anchored()` makes the same argument one step smaller ("an authored size would be a
## lying knob"); this makes it about the whole spec. An author who wants these dialable gives
## the element an authored home and uses `at()` — which is what the gambit ROW menu does.
##
## Exempt from the no-empty-`DERIVED` audit (Amendment 4 §3) for the same reason
## `screen_anchored()` is: it reports its own `Source`, so it is a DECLARED answer and not an
## author who forgot to name this rect's drivers.
static func host_derived(f: Callable) -> DerivedRect:
	var d := DerivedRect.new([], f)
	d.host_derived = true
	return d


func _init(spec: Dictionary = {}) -> void:
	_spec = spec
	if not spec.is_empty():
		# A code-built element (construction-site dict) is an ELEMENT unless it says otherwise;
		# the widget path (empty spec here) defaults PAYLOAD, injected at _enter_tree instead.
		if not _spec.has("role"):
			_spec["role"] = Role.ELEMENT
		_adopt_spec()


## The declared role (ADR-0088 Amendment 5). Defaults PAYLOAD for the widget path (empty spec
## until answers accumulate); a code-built spec has ELEMENT injected at _init.
func role() -> int:
	return int(_spec.get("role", Role.PAYLOAD))


func _enter_tree() -> void:
	if not _criteria_registered:
		_criteria_registered = true
		_register_criteria()
	if not _spec.has("role"):
		_spec["role"] = Role.PAYLOAD   # widget path default — before validation reads it
	if not _adopted:
		_adopt_spec()   # widget path: answers are in by now; validate collect-all
	# PAYLOAD rides its parent: no registration, no slug, no origin placement (which would
	# clobber a widget's externally-managed position), no chrome. The base-swap is inert for it.
	if role() != Role.ELEMENT:
		return
	_parent_element = _find_parent_element()
	_place_self()
	_ensure_chrome()
	var registry := get_node_or_null("/root/UI3Registry")
	if registry != null:
		registry.register_element(self)


func _exit_tree() -> void:
	var registry := get_node_or_null("/root/UI3Registry")
	if registry != null:
		registry.unregister_element(self)


# -----------------------------------------------------------------------------
# Spec validation — loud, collect-all-then-fail (ADR-0088 §2).
# -----------------------------------------------------------------------------

## Validate a criteria spec, reporting EVERY problem (never just the first): each
## missing required criterion, wrong-typed field, and out-of-range enum answer is one
## entry. Pure and static — the seam guards drive directly; _init/_enter_tree wrap it
## with push_error + assert. Unknown keys pass (beat params etc. are ordinary fields).
static func validate_spec(spec: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	# Role gates the required criteria (Amendment 5 §3): only an ELEMENT requires id/rect and the
	# enum criteria; a PAYLOAD with neither is valid. The default (no role key) is ELEMENT so the
	# code-built construction surface is unchanged and validate_spec({}) still reports all 5.
	if spec.has("role") and (typeof(spec["role"]) != TYPE_INT or not Role.values().has(spec["role"])):
		errors.append("\"role\" must be a UI3Element.Role.* enum int")
	var is_element := int(spec.get("role", Role.ELEMENT)) == Role.ELEMENT
	# id/rect are type-checked whenever present (a PAYLOAD may carry them), but required only for ELEMENT.
	if not spec.has("id"):
		if is_element:
			errors.append("required criterion \"id\" is missing")
	elif typeof(spec["id"]) != TYPE_STRING or String(spec["id"]).is_empty():
		errors.append("\"id\" must be a non-empty String")
	if not spec.has("rect"):
		if is_element:
			errors.append("required criterion \"rect\" is missing")
	elif typeof(spec["rect"]) != TYPE_RECT2 and typeof(spec["rect"]) != TYPE_RECT2I \
			and typeof(spec["rect"]) != TYPE_CALLABLE and not (spec["rect"] is DerivedRect):
		errors.append("\"rect\" must be a Rect2/Rect2i (display px) or a derived placement")
	_check_enum_criterion(spec, "transition", Transition, errors, is_element)
	_check_enum_criterion(spec, "frame", Frame, errors, is_element)
	_check_enum_criterion(spec, "clip", Clip, errors, is_element)
	# `move` is OPTIONAL (ADR-0097 §5) — absent means NONE means snap — but it is range-checked
	# whenever present, like id/rect on a PAYLOAD.
	_check_enum_criterion(spec, "move", Move, errors, false)
	# Cadence is explicit-required PER VERB, but only for an element that DECLARES A BEAT
	# (ADR-0097 §2) — the same criterion-gated shape as id/rect above: an element whose
	# transition is NONE or RIDE_PARENT names no playback and so has no verb to cadence, which
	# is what leaves the 22 NONE/RIDE_PARENT elements untouched. What the audit can check is
	# only that an answer is PRESENT and is an int: the value belongs to the beat's own
	# vocabulary (§1), so a static, beat-blind function cannot range-check it. That other half
	# is UI3TransitionEngine.cadence_errors().
	var kind: Variant = spec.get("transition")
	var plays: bool = is_element and typeof(kind) == TYPE_INT and Transition.values().has(kind) \
		and kind != Transition.NONE and kind != Transition.RIDE_PARENT
	_check_cadence_criterion(spec, OPEN_CADENCE, errors, plays)
	_check_cadence_criterion(spec, CLOSE_CADENCE, errors, plays)
	var move_kind: Variant = spec.get("move", Move.NONE)
	_check_cadence_criterion(spec, MOVE_CADENCE, errors,
		is_element and typeof(move_kind) == TYPE_INT and Move.values().has(move_kind)
		and move_kind != Move.NONE)
	# Optional (inherited-override / frame-param) fields are type-checked when present.
	if spec.has("authored_home") and typeof(spec["authored_home"]) != TYPE_VECTOR2 \
			and typeof(spec["authored_home"]) != TYPE_VECTOR2I:
		errors.append("\"authored_home\" must be a Vector2 (display px)")
	if spec.has("aperture_pad") and typeof(spec["aperture_pad"]) != TYPE_VECTOR4:
		errors.append("\"aperture_pad\" must be a Vector4 (left/top/right/bottom display px)")
	if spec.has("ppu") and typeof(spec["ppu"]) != TYPE_FLOAT and typeof(spec["ppu"]) != TYPE_INT:
		errors.append("\"ppu\" must be a float")
	if spec.has("depth_rung") and typeof(spec["depth_rung"]) != TYPE_INT:
		errors.append("\"depth_rung\" must be an int")
	if spec.has("frame_center_patch") and typeof(spec["frame_center_patch"]) != TYPE_VECTOR4:
		errors.append("\"frame_center_patch\" must be a Vector4 (atlas px)")
	if spec.has("frame_rp") and typeof(spec["frame_rp"]) != TYPE_INT:
		errors.append("\"frame_rp\" must be an int (the chrome's render priority / fold rung)")
	return errors


## One explicit-required enum criterion: absence fails, a non-int fails, and an int
## outside the enum's values fails — `none` is a valid answer, silence is not.
static func _check_enum_criterion(spec: Dictionary, field: String, enum_dict: Dictionary,
		errors: PackedStringArray, required: bool = true) -> void:
	if not spec.has(field):
		if required:
			errors.append("required criterion \"%s\" is missing" % field)
	elif typeof(spec[field]) != TYPE_INT:
		errors.append("\"%s\" must be an enum int (UI3Element.%s.*)" % [field, field.capitalize()])
	elif not enum_dict.values().has(spec[field]):
		errors.append("\"%s\" = %s is out of enum range" % [field, spec[field]])


## One per-verb cadence (ADR-0097 §2). Required only when a beat is declared for the verb it
## serves — an element that animates nothing answers nothing. `DEFAULT` is a legal answer and
## the point of requiring one at all: it makes "I considered this and chose the house rule"
## and "I never thought about this" different states in the source, without a warning anyone
## has to live with.
static func _check_cadence_criterion(spec: Dictionary, field: String,
		errors: PackedStringArray, required: bool) -> void:
	if not spec.has(field):
		if required:
			errors.append("required criterion \"%s\" is missing (an element that declares a beat must name a cadence for each verb it serves)" % field)
	elif typeof(spec[field]) != TYPE_INT:
		errors.append("\"%s\" must be a cadence enum int from the declared beat's vocabulary" % field)


## Validate + capture the spec. Every gap is push_error'ed individually (prefixed with
## the element id so a guard log names ALL the problems), then one assert stops a
## debug/guard run. In a release build the assert compiles out and the element boots
## visibly broken with the errors logged.
func _adopt_spec() -> void:
	_adopted = true
	var errors := validate_spec(_spec)
	if not errors.is_empty():
		var label := String(_spec.get("id", "<unnamed>"))
		for e in errors:
			push_error("UI3Element %s: %s" % [label, e])
		assert(errors.is_empty(), "UI3Element %s: spec invalid (%d problems — see errors above)"
			% [label, errors.size()])
		return
	# PAYLOAD carries no id/rect/binds — it rides its parent (Amendment 5 §3). Nothing to capture.
	if role() != Role.ELEMENT:
		return
	_id = String(_spec["id"])
	var rect_answer: Variant = _spec["rect"]
	if _rect_is_derived():
		_rect = _eval_rect_answer(rect_answer)
	else:
		_rect = Rect2(rect_answer)
	_home = Vector2(_spec["authored_home"]) if _spec.has("authored_home") else _rect.position
	# Policy: every OWN_APERTURE element exposes an `aperture_pad` knob, always (docs/ui3-guide.md
	# "Aperture padding"). An element that owns an aperture is one whose reveal box is dialable —
	# so we inject the zero default when the spec omits it. This is behaviourally inert (absent ==
	# Vector4.ZERO in padded_rect()) but mints the live F3 knob without a per-call-site declaration.
	# PARENT_APERTURE / UNCLIPPED elements own no aperture, so they get no such knob.
	if clip_mode() == Clip.OWN_APERTURE and not _spec.has("aperture_pad"):
		_spec["aperture_pad"] = Vector4.ZERO
	_aperture = padded_rect()   # settled default; a transition beat drives it live
	if name == StringName(""):
		name = _id.replace(".", "_")   # '.' is not a valid Node name character
	_mint_binds()


# -----------------------------------------------------------------------------
# Auto-bind threading (ADR-0088 §5) — registration feeds ADR-0068. Binds mint in
# _init (the construction site is on the stack, so M2's capture — through the
# UI3Element.gd skip-list entry — lands on the caller's `new({...})` line, the
# exact dict whose literal materialise rewrites).
# -----------------------------------------------------------------------------

## Mint one Tune bind per LITERAL-authored spec field, named by element id. A derived
## rect binds nothing and subscribes its drivers instead; `id` and `authored_home`
## are not live knobs (identity + the frozen content anchor).
func _mint_binds() -> void:
	var rect_answer: Variant = _spec["rect"]
	# A host-derived element mints NOTHING — not the rect, not the layout literals, not the
	# criteria. Every one of them is recomputed by the host on the next build, so every one
	# would be a knob whose scrub the next open discards; and a MINTED one is worse than
	# useless, because Tune is first-write-wins and the stale default is pushed back into the
	# NEW element (see `host_derived`). Returning here is the whole of the fix.
	if rect_answer is DerivedRect and rect_answer.host_derived:
		return
	if rect_answer is DerivedRect and rect_answer.screen_anchored:
		# The group-nudge origin knob (ADR-0088 Amendment 4 §1, Option C): a screen-anchored
		# assembly has no per-piece placement, but ONE editable <id>.origin (Vector2 px)
		# translates the whole element — every payload rides. Default (0,0) is a no-op.
		_bound_fields["rect"] = true
		TunePort.bind_update(self, _id + ".origin", Vector2.ZERO,
			func(v: Variant) -> void: _apply_screen_anchored_origin(v), {"step": 1.0})
	elif rect_answer is DerivedRect:
		for driver: String in rect_answer.drivers:
			_subscribe_rect_driver(driver)
	elif not (rect_answer is Callable) and not _bound_fields.has("rect"):
		_bound_fields["rect"] = true
		TunePort.bind_update(self, _id + ".rect", Rect2(rect_answer),
			func(v: Variant) -> void: _apply_rect(Rect2(v)), {"step": 1.0})
	_mint_criterion_bind("transition", Transition, "UI3Element.Transition")
	_mint_criterion_bind("frame", Frame, "UI3Element.Frame")
	_mint_criterion_bind("clip", Clip, "UI3Element.Clip")
	for field: String in _spec.keys():
		if field in ["id", "rect", "transition", "frame", "clip", "authored_home"]:
			continue
		if field in [OPEN_CADENCE, CLOSE_CADENCE, MOVE_CADENCE]:
			_mint_cadence_bind(field)
			continue
		_mint_field_bind(field, _spec[field])


## Subscribe ONE rect-driver slug, dedup'd (Tune has no per-slug unsubscribe short
## of tree exit). The handler re-evaluates the CURRENT rect answer — so after a
## place_at swap, a scrub on an OLD location re-applies the live answer (a visual
## no-op), never a stale placement.
func _subscribe_rect_driver(slug: String) -> void:
	if _rect_driver_subs.has(slug):
		return
	_rect_driver_subs[slug] = true
	TunePort.on_update(self, slug, func(_v: Variant) -> void:
		_apply_rect(_eval_rect_answer(_spec["rect"])))


## Bind one explicit-required enum criterion as an enum-hinted int (decision 11 —
## chrome/clip/transition become live dropdowns while diagnosing). The hint also
## records the token prefix so materialise can format the int back to its enum token.
func _mint_criterion_bind(field: String, enum_dict: Dictionary, token_prefix: String) -> void:
	if _bound_fields.has(field):
		return
	_bound_fields[field] = true
	var options := {}
	for token: String in enum_dict:
		options[token] = enum_dict[token]
	TunePort.bind_update(self, _id + "." + field, int(_spec[field]),
		func(v: Variant) -> void: _apply_criterion(field, int(v)),
		{"enum": options, "enum_tokens": token_prefix})


## Bind one per-verb cadence (ADR-0097 §2) as an enum-hinted int, exactly like the three
## explicit-required criteria — except the option list comes from the BEAT, since the
## vocabulary is per-beat by design (§1). A beat that declares none falls back to a plain int
## knob. Authoring `DEFAULT` mints a real slug like any other literal, so per-element cadence
## is scrubbable and "chose the house rule" stays visible in the F3 tree.
func _mint_cadence_bind(field: String) -> void:
	if _bound_fields.has(field):
		return
	var beat: UI3Beat = _declared_beat(field == MOVE_CADENCE)
	var options: Dictionary = beat.cadence_enum() if beat != null else {}
	if options.is_empty():
		_mint_field_bind(field, _spec[field])
		return
	_bound_fields[field] = true
	TunePort.bind_update(self, _id + "." + field, int(_spec[field]),
		func(v: Variant) -> void: _apply_field(field, int(v)),
		{"enum": options, "enum_tokens": beat.cadence_enum_tokens()})


## The beat this element declares for its transition (or, with `move`, for its move slot) —
## null when the criterion names no playback or nothing is registered for it.
##
## Reached through the AUTOLOAD IDENTIFIER, not the `get_node_or_null("/root/UI3Registry")`
## the rest of this class uses, because binds mint at _init — before the element is in the
## tree, where an absolute node path resolves to null. Silently getting null here would not
## fail; it would quietly downgrade every cadence knob to an unlabelled int.
func _declared_beat(move: bool) -> UI3Beat:
	return UI3Registry.move_beat_for(move_mode()) if move else UI3Registry.beat_for(transition_mode())


## Bind an ordinary literal spec field (an inherited override like ppu/depth_rung, or
## a beat param). Non-literal values (objects) are not bind homes.
func _mint_field_bind(field: String, literal: Variant) -> void:
	if _bound_fields.has(field):
		return
	match typeof(literal):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_COLOR, \
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_RECT2:
			_bound_fields[field] = true
			TunePort.bind_update(self, _id + "." + field, literal,
				func(v: Variant) -> void: _apply_field(field, v))
		_:
			pass


## Land a scrub on one of the three explicit-required criteria (the engines are the
## on_update consumers — E4; never a panel, decision 12).
func _apply_criterion(field: String, v: int) -> void:
	_spec[field] = v
	match field:
		"clip":
			_push_clip()   # re-resolve with the engine
		"frame":
			if is_inside_tree():
				_ensure_chrome()   # rebuild ONLY the chrome child (a genuine re-mesh);
				                   # pre-tree the _enter_tree build covers it
		_:
			pass           # transition: re-consumed on the next play


## Land a scrub on an inherited-override / beat-param field. Metric changes re-place
## and re-push; chrome params retune the chrome; beat params are consumed on the next
## play (the fast pattern).
func _apply_field(field: String, v: Variant) -> void:
	_spec[field] = v
	if field == "ppu" or field == "depth_rung":
		_place_self()
		_push_clip()
	elif field == "frame_center_patch" and _chrome != null and is_instance_valid(_chrome):
		_chrome.center_region = v
	elif field == "aperture_pad" and clip_mode() == Clip.OWN_APERTURE and _settled:
		_set_aperture(padded_rect())   # re-derive the settled box; mid-beat the engine owns it


# -----------------------------------------------------------------------------
# Chrome (ADR-0088 §4 "Chrome"; interfaces §2) — the frame criterion selects the
# UIFrame variant and the ELEMENT builds it: sized from the live rect, parented
# under itself at local zero, on the frame_rp fold rung, wearing the shared window
# CLUTs. The tribal-knowledge chrome choice becomes one enum answer.
# -----------------------------------------------------------------------------

func _ensure_chrome() -> void:
	if _chrome != null and is_instance_valid(_chrome):
		_chrome.free()   # synchronous: a criterion scrub rebuilds in place
	_chrome = null
	var variant := int(_spec.get("frame", Frame.NONE))
	if variant == Frame.NONE:
		return
	var frame := UIFrame.new()
	frame.opaque = true                # occlude folded prims under the window (ADR-0077)
	frame.pixels_per_unit = ppu()
	frame.pixel_aspect_ratio = 1.0     # display-px-authored windows carry no PSX PAR stretch
	if variant == Frame.STRIPE:
		frame.source_region = UIFrame.STRIPE_SOURCE
		frame.margins = UIFrame.STRIPE_MARGINS
	# MENU_TILE keeps UIFrame's default flat menu-tile crop.
	if _spec.has("frame_center_patch"):
		frame.center_region = _spec["frame_center_patch"]
	frame.frame_size = _rect.size
	var rp := int(_spec.get("frame_rp", 0))
	frame.render_priority = rp
	add_child(frame)
	frame.position = z_for(rp)         # local zero under the origin — the chrome IS the frame
	_chrome = frame
	_arm_chrome_palettes(frame)


## Arm the chrome's §15.21 fg→bg CLUT swap (fg/bg palette pair + palette_count>0, the
## shader's remap gate). UIFrame builds its ShaderMaterial in `_ready`, which does NOT
## run synchronously when `_ensure_chrome`'s add_child(frame) happens during THIS
## element's own _enter_tree batch — `get_material()` is null then, so a plain
## `if mat != null` arm silently dropped and the frame never turned blue on background.
## Arm now if the material already exists (a settled-tree frame-criterion re-mesh), else
## once on the frame's `ready` (the initial build path). backgrounded starts foreground;
## the owner re-asserts state via set_backgrounded after the frame is up.
func _arm_chrome_palettes(frame: UIFrame) -> void:
	if frame == null or not is_instance_valid(frame):
		return
	var mat := frame.get_material()
	if mat == null:
		if not frame.is_node_ready():
			frame.ready.connect(_arm_chrome_palettes.bind(frame), CONNECT_ONE_SHOT)
		return
	# The palette criterion's root default: the shared window fg/bg CLUT pair.
	mat.set_shader_parameter("fg_palette", UIWindowPalettes.FRAME_FG_7C3C)
	mat.set_shader_parameter("bg_palette", UIWindowPalettes.FRAME_BG_7D3C)
	mat.set_shader_parameter("palette_count", 16)
	mat.set_shader_parameter("backgrounded", 0.0)


## The element-built chrome frame (null for Frame.NONE / before tree entry).
func chrome() -> UIFrame:
	return _chrome if _chrome != null and is_instance_valid(_chrome) else null


## The chrome's 9-slice material (null when no chrome) — for guards and CLUT swaps.
func chrome_material() -> ShaderMaterial:
	var c := chrome()
	return c.get_material() if c != null else null


## Every payload ShaderMaterial in this element's own subtree (nested elements
## excluded) — the clip engine's fresh discovery, exposed for guards/hosts.
func payload_materials() -> Array:
	if not is_inside_tree():
		return []
	var registry := get_node_or_null("/root/UI3Registry")
	return registry.payload_materials(self) if registry != null else []


## Every MeshInstance3D carrying UI payload in this element's own subtree (nested
## elements excluded) — the ownership map's swap/mute surface (ADR-0088 Amendment 6),
## sibling of payload_materials().
func payload_meshes() -> Array:
	if not is_inside_tree():
		return []
	var registry := get_node_or_null("/root/UI3Registry")
	return registry.payload_meshes(self) if registry != null else []


func _rect_is_derived() -> bool:
	var ra: Variant = _spec.get("rect")
	return ra is DerivedRect or ra is Callable


func _eval_rect_answer(answer_value: Variant) -> Rect2:
	var f: Callable = answer_value.eval if answer_value is DerivedRect else answer_value
	return Rect2(f.call())


# -----------------------------------------------------------------------------
# Widget path (§7) — criteria answered per field at class level.
# -----------------------------------------------------------------------------

## Overridden by UIComponent widget subclasses to answer the criteria at class level
## (one answer(...) line per criterion, in the widget's own file). Code-built elements
## pass a full spec at new() instead and leave this empty.
func _register_criteria() -> void:
	pass


## Answer one criterion field — the widget path's per-field literal home. The bind is
## minted HERE, at the answer(...) call, so M2's captured stack (through the skip
## list) lands on the widget's own line — a real one-literal home for materialise.
## `answer("id", ...)` must come first: it names the CLASS-scoped slug namespace
## (uibutton.frame — one slug per class, every instance subscribes).
func answer(field: String, literal: Variant) -> void:
	_spec[field] = literal
	if field == "id":
		_id = String(literal)
		return
	if _id.is_empty():
		push_error("UI3Element: answer(\"%s\") before answer(\"id\") — the id names the slug namespace" % field)
		return
	match field:
		"rect":
			if typeof(literal) == TYPE_RECT2 or typeof(literal) == TYPE_RECT2I:
				_bound_fields["rect"] = true
				TunePort.bind_update(self, _id + ".rect", Rect2(literal),
					func(v: Variant) -> void: _apply_rect(Rect2(v)), {"step": 1.0})
			# a derived rect mints nothing; drivers subscribe at _adopt_spec
		"transition":
			_mint_criterion_bind(field, Transition, "UI3Element.Transition")
		"frame":
			_mint_criterion_bind(field, Frame, "UI3Element.Frame")
		"clip":
			_mint_criterion_bind(field, Clip, "UI3Element.Clip")
		"authored_home":
			pass
		_:
			_mint_field_bind(field, literal)


# -----------------------------------------------------------------------------
# Placement — absolute display px in, world out (the _rel_world idiom, absorbed).
# -----------------------------------------------------------------------------

func id() -> String:
	return _id


## The per-row model for the UI3 page (interfaces §6): one entry per criterion —
## field, live value, where it came from (AUTHORED / INHERITED / DERIVED), and the
## minted slug ("" when none was minted: inherited resolutions, derived placements,
## and the frozen authored_home).
func criteria() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ra: Variant = _spec.get("rect")
	if ra is DerivedRect and ra.host_derived:
		# Host-derived: no knob for anything, so the page renders an honest read-only row
		# rather than naming a slug `_mint_binds` deliberately never registered.
		out.append({"field": "rect", "value": _rect, "source": Source.HOST_DERIVED, "slug": ""})
	elif ra is DerivedRect and ra.screen_anchored:
		# Screen-anchored assembly (Amendment 4 §1): no per-piece placement, but ONE editable
		# <id>.origin group-nudge knob (Option C) that translates the whole element — the page
		# renders the honest label + that control. Distinct from a (derived) dead-end; §3-exempt.
		out.append({"field": "rect", "value": _rect, "source": Source.SCREEN_ANCHORED,
			"slug": _id + ".origin"})
	elif ra is DerivedRect and not String(ra.location_slug).is_empty():
		# At-location: the SHARED key-location slug this element rides (Amendment 3 §1) —
		# the page names it + offers re-home, so the slug is carried, not discarded.
		out.append({"field": "rect", "value": _rect, "source": Source.AT_LOCATION,
			"slug": String(ra.location_slug)})
	elif _rect_is_derived():
		# Plain derived: mints no slug; its DRIVERS are the editable knobs (Amendment 3 §4),
		# carried here so the page can expand them.
		var drivers: Array = ra.drivers if ra is DerivedRect else []
		out.append({"field": "rect", "value": _rect, "source": Source.DERIVED, "slug": "",
			"drivers": drivers})
	else:
		out.append({"field": "rect", "value": _rect, "source": Source.AUTHORED,
			"slug": _id + ".rect"})
	for f in ["transition", "frame", "clip"]:
		# `slug` is what the page hands Tune, so it must name a slug that was MINTED — a
		# host-derived element mints none of these and an unbound name would assert on read.
		out.append({"field": f, "value": int(_spec.get(f, 0)), "source": Source.AUTHORED,
			"slug": (_id + "." + f) if _bound_fields.has(f) else ""})
	var inherited_defaults := {"ppu": DEFAULT_PPU, "depth_rung": DEFAULT_DEPTH_RUNG}
	for f: String in inherited_defaults:
		if _spec.has(f):
			out.append({"field": f, "value": _spec[f], "source": Source.AUTHORED,
				"slug": (_id + "." + f) if _bound_fields.has(f) else ""})
		else:
			out.append({"field": f, "value": resolve_criterion(f, inherited_defaults[f]),
				"source": Source.INHERITED, "slug": ""})
	for f: String in _spec.keys():
		if f in ["id", "rect", "transition", "frame", "clip", "ppu", "depth_rung"]:
			continue
		if f == "authored_home":
			out.append({"field": f, "value": _home, "source": Source.AUTHORED, "slug": ""})
		else:
			out.append({"field": f, "value": _spec[f], "source": Source.AUTHORED,
				"slug": (_id + "." + f) if _bound_fields.has(f) else ""})
	return out


## The element's LIVE rect (display px) — the placement the origin follows.
func rect() -> Rect2:
	return _rect


## The FROZEN content anchor all rel_world offsets subtract — the authored rect
## literal's position unless the spec pinned an explicit "authored_home".
func authored_home() -> Vector2:
	return _home


## Nearest registered ancestor (null for a top-level element). Resolved on _enter_tree.
func parent_element() -> UI3Element:
	return _parent_element


# -----------------------------------------------------------------------------
# Transition (ADR-0088 §4; interfaces §4) — the whole authoring surface for
# open/close; the engine owns accumulator/clamp/cadence/reverse mechanics.
# -----------------------------------------------------------------------------

## The declared transition answer (explicit-required).
func transition_mode() -> int:
	return int(_spec.get("transition", Transition.NONE))


## The declared move answer (ADR-0097 §5) — OPTIONAL, unlike the other criteria: absent
## means NONE means snap, so an element says nothing until it wants an animated move.
func move_mode() -> int:
	return int(_spec.get("move", Move.NONE))


## The criteria spec (read by beats for their params, e.g. `aperture_pad`).
func spec() -> Dictionary:
	return _spec


## The cadence in force for one verb THIS play (ADR-0097 §1/§4): the call-site override
## while one is live, else the authored spec field, else 0 — which every beat's Cadence
## vocabulary reserves for DEFAULT ("use the house rule").
##
## Beats resolve cadence through here rather than through `spec()` so a one-invocation
## override (`close(UI3BoxOpenBeat.Cadence.IMMEDIATE)`) reaches drive() and settle_frame()
## alike without minting a second concept: the override is the SAME type as the authored
## value, it just lives on the element for the play's duration instead of in the spec.
func cadence_for(field: String) -> int:
	var override := _move_cadence_override if field == MOVE_CADENCE else _cadence_override
	if override >= 0:
		return override
	return int(_spec.get(field, 0))


## Enter the transition beat (NONE/RIDE_PARENT → instant settle + `opened`).
##
## `_settled` is lowered BEFORE the engine call, never after: an IMMEDIATE cadence settles
## SYNCHRONOUSLY inside play() (ADR-0097 §3), so _transition_finished has already raised the
## flag and emitted by the time _engine_play returns. Writing `_settled = false` afterwards
## would strand the element unsettled forever with its signal already spent.
##
## `cadence` overrides the authored answer FOR THIS INVOCATION ONLY (ADR-0097 §4) — same type
## as the authored value, so there is no second concept, and the engine drops it when the play
## ends. It exists because the need is situational rather than a standing element property:
## when a whole screen unwinds, an open picker should snap rather than play its private close
## over a screen that is sliding away, while a plain cancel on that same picker still animates.
func open(cadence: int = NO_CADENCE_OVERRIDE) -> void:
	_settled = false
	if not _engine_play(false, cadence):
		_settled = true
		opened.emit()


## Re-home a live element onto another key location (ADR-0088 Amendment 2 §4) —
## the WHERE verb, orchestrator-invoked like open()/close() (an element never
## decides which of its legal homes it occupies). Swaps the rect answer to
## at(location_slug) and applies that location's live value now; the authored
## home stays frozen, so mounted content rides the re-home (movable origin), and
## a settled OWN_APERTURE re-derives via _apply_rect. Selection POLICY stays a
## pure static in the owner class — hosts ask policy, then invoke this verb.
func place_at(location_slug: String, cadence: int = NO_CADENCE_OVERRIDE) -> void:
	assert(_adopted, "place_at before the spec was adopted — construct with a rect answer first")
	# `from` is read HERE, before the two lines below, and the order is load-bearing:
	# `_subscribe_rect_driver` goes through `Tune.on_update`, which runs its handler
	# IMMEDIATELY with the current value as well as on every later change — and that handler
	# is `_apply_rect(<the new answer>)`. By the time the subscribe returns, the element has
	# already SNAPPED to the destination, so a `from` read after it equals `to` and the beat
	# plays a zero-length move. It bites only the FIRST place_at to a given slug, because the
	# subscribe dedups, which is exactly the shape that ships.
	var from := _rect
	_spec["rect"] = at(location_slug)
	_subscribe_rect_driver(location_slug)
	_move_onto(from, _eval_rect_answer(_spec["rect"]), cadence)


## Walk to wherever this element's rect answer NOW evaluates — the ANIMATED twin of the snap a
## rect-driver scrub already performs (ADR-0269 dec. 4).
##
## `place_at` is the right verb when the destination is a KEY LOCATION: an authored place, one of
## the element's legal homes, with a slug an F3 scrub can move. A turn-queue card's slot is not
## that. Slot 4 of a strip is `pad + 4 * pitch`, a position that exists only because two other
## knobs have values — so the card answers WHERE with a `derived()` placement over those knobs,
## which is the answer form the system already has for a computed home, and which deliberately
## mints no slug (sixteen per-slot "knobs" that must never be scrubbed independently would be a
## lying knob sixteen times over).
##
## What was missing was only the VERB. `_subscribe_rect_driver` already re-evaluates a derived
## answer and SNAPS to it when a driver moves; this walks the same distance on the declared move
## beat instead. So a card whose slot changed calls this, and Move.SLIDE carries it.
##
## The rect ANSWER is untouched — that is the whole difference from `place_at`, which swaps the
## answer first. Everything downstream is identical: Move.NONE snaps, the frozen authored_home
## keeps mounted content riding, and `moved` fires on settle.
func move_to_answer(cadence: int = NO_CADENCE_OVERRIDE) -> void:
	assert(_adopted, "move_to_answer before the spec was adopted — construct with a rect answer first")
	_move_onto(_rect,
		_eval_rect_answer(_spec["rect"]) if _rect_is_derived() else Rect2(_spec["rect"]),
		cadence)


## The shared tail of the two WHERE verbs: walk (or snap) from `from` to `to`.
##
## `from` is a PARAMETER and not a re-read of `_rect`, because the two verbs do not agree on
## when `_rect` is still the start: `place_at` subscribes a rect driver on the way, and that
## subscription snaps the element before it returns (see the note there). Passing it makes the
## start an argument rather than a timing assumption.
func _move_onto(from: Rect2, to: Rect2, cadence: int) -> void:
	_move_settled = false
	if not _engine_move(from, to, cadence):
		# Move.NONE (or an absent `move`) — the SNAP place_at has always done, so every
		# pre-ADR-0097 caller is unchanged and animating a move stays opt-in.
		_apply_rect(to)
		_move_settled = true
		moved.emit()


## Leave = the same beat reversed (ADR-0084 invariant 1); ends shut + `closed`.
## Sometimes SYNCHRONOUS — see open() — so a `closed` handler may run before this returns.
## `cadence` is the same one-invocation override open() takes.
func close(cadence: int = NO_CADENCE_OVERRIDE) -> void:
	_settled = false
	if not _engine_play(true, cadence):
		_settled = true
		closed.emit()


func is_settled() -> bool:
	return _settled


## False while a place_at() move is walking (always true when the element declares no move
## beat — the snap arrives before place_at returns).
func is_move_settled() -> bool:
	return _move_settled


## The move play's endpoints, for the move beat to interpolate between (ADR-0097 §5): where
## the element stood when place_at was called, and where the new key location puts it.
func move_from() -> Rect2:
	return _move_from


func move_to() -> Rect2:
	return _move_to


## TransitionEngine → element: the play finished (did_open = forward direction).
func _transition_finished(did_open: bool) -> void:
	_settled = true
	if did_open:
		opened.emit()
	else:
		closed.emit()


## TransitionEngine → element: the move play finished.
func _move_finished() -> void:
	_move_settled = true
	moved.emit()


func _engine_move(from: Rect2, to: Rect2, cadence: int) -> bool:
	if not is_inside_tree():
		return false
	var registry := get_node_or_null("/root/UI3Registry")
	if registry == null:
		return false
	_move_from = from
	_move_to = to
	return registry.play_move(self, cadence)


func _engine_play(reversed: bool, cadence: int) -> bool:
	if not is_inside_tree():
		return false
	var registry := get_node_or_null("/root/UI3Registry")
	return registry != null and registry.play_transition(self, reversed, cadence)


# -----------------------------------------------------------------------------
# Clip (ADR-0088 §4; interfaces §3) — the element's surface over the engine.
# -----------------------------------------------------------------------------

## The declared clip answer (explicit-required; UNCLIPPED only for a never-adopted spec).
func clip_mode() -> int:
	return int(_spec.get("clip", Clip.UNCLIPPED))


## The live aperture (display px) — meaningful on OWN_APERTURE elements; settled
## default = padded_rect().
func aperture() -> Rect2i:
	return _aperture


## The box a transition opens over (ADR-0088 amendment §4): the live rect grown by the
## optional `aperture_pad` spec field (Vector4 left/top/right/bottom, display px) — for
## payload that legitimately pokes past the frame yet must still ride the reveal. Pads
## THIS box, never the per-frame reveal, so a finished close still ends fully shut.
## Honesty: the ROM §15.17 scissor IS the container rect — a non-zero pad is a
## deliberate port-side affordance; parity-dialed screens keep it zero.
func padded_rect() -> Rect2i:
	var pad: Vector4 = _spec.get("aperture_pad", Vector4.ZERO)
	return Rect2i(_rect.grow_individual(pad.x, pad.y, pad.z, pad.w))


## Drive the aperture (the TransitionEngine → element seam; a rect scrub re-derives it
## too). Emits + re-pushes the whole subtree synchronously.
func _set_aperture(rect: Rect2i) -> void:
	_aperture = rect
	aperture_changed.emit(rect)
	_push_clip()


## Explicit idempotent verb: re-walk the subtree and re-push the resolved clip — for
## tests and exotic mutations the tree signals can't see (in-place material swaps).
## Also re-evaluates a derived/Callable rect (the bare-Callable form's only refresh).
func refresh_payload() -> void:
	if _adopted and _rect_is_derived():
		_apply_rect(_eval_rect_answer(_spec["rect"]))
		return   # _apply_rect already re-pushed
	_push_clip()


## Land a live-rect change (the auto-bind rect apply, and the seam tests drive): move
## only this transform, then re-derive the aperture from the LIVE rect so the payload
## never keeps the OLD one (the f8442784d stale-clip class). Mid-beat the transition
## engine owns the aperture — the next beat frame re-derives against the new rect.
func _apply_rect(r: Rect2) -> void:
	_rect = r
	_place_self()
	if _chrome != null and is_instance_valid(_chrome):
		_chrome.frame_size = _rect.size
	if clip_mode() == Clip.OWN_APERTURE and _settled:
		_set_aperture(padded_rect())
	else:
		_push_clip()


## Land a group-nudge on a screen-anchored assembly (Option C): the <id>.origin knob
## translates the element's transform in display px — payload is mounted absolute and rides
## the move. Keeps the frozen authored_home at (0,0) so rel_world offsets stay absolute.
func _apply_screen_anchored_origin(v: Variant) -> void:
	var o := Vector2(v)
	_rect = Rect2(o.x, o.y, 0.0, 0.0)
	_place_self()
	_push_clip()


func _push_clip() -> void:
	if not is_inside_tree():
		return
	var registry := get_node_or_null("/root/UI3Registry")
	if registry != null:
		registry.push_clip(self)


## Where payload mounts (== self today; an internal seam so chrome could split out later).
func content_root() -> Node3D:
	return self


## Display px → local under this element, subtracting the resolved authored_home
## (EquipPickerMenu._rel_world): at the authored home the net world position equals
## the plain screen_to_world of the absolute coordinate; when the live rect is
## scrubbed the origin carries the whole group.
func rel_world(px: float, py: float) -> Vector3:
	return _screen_to_world(px - _home.x, py - _home.y)


## Fold-rung Z for a payload render_priority through the resolved depth_rung criterion
## (absorbs the per-class _z_for + fold-predicate copies): rung = depth_rung + rp.
func z_for(rp: int) -> Vector3:
	# TWO guards, and they are different questions. `Fold.owns()` is the build predicate and needs no
	# tree. `is_inside_tree()` is THIS method's own precondition: a rung Z is only meaningful once the
	# element has resolved its criteria against a mounted parent, and callers mount a payload AFTER
	# add_child. The pre-ADR-0191 copy folded both into one `fold_owns()` and the migration dropped the
	# tree half with it — measured: off-tree `z_for(6)` at depth_rung 34 returned Vector3.ZERO before,
	# and (0, 0, 7.6) after. That is a behaviour change ADR-0191's "No behaviour changes" did not
	# survive; see its Amendment 2. The guard belongs here, not in the predicate.
	if not is_inside_tree() or not Fold.owns():
		return Vector3.ZERO
	var rung := int(resolve_criterion("depth_rung", DEFAULT_DEPTH_RUNG)) + rp
	return Vector3(0.0, 0.0, DepthMode.rung_z(rung))


## The resolved pixels-per-unit metric — own override, else the ancestor chain, else
## the one root default (the six per-class PIXELS_PER_UNIT copies retire into this).
func ppu() -> float:
	return float(resolve_criterion("ppu", DEFAULT_PPU))


## Resolve an inherited-defaulted criterion through the ancestor element chain: an
## element's own spec answer wins, else the nearest ancestor that answered, else the
## root default.
func resolve_criterion(field: String, root_default: Variant) -> Variant:
	if _spec.has(field):
		return _spec[field]
	if _parent_element != null:
		return _parent_element.resolve_criterion(field, root_default)
	return root_default


## Place THIS node from its rect against the parent element's authored home (a
## top-level element resolves against a zero home). A rect change moves only this
## transform; payload and nested elements ride for free.
##
## The offset is against the parent's AUTHORED home on purpose: it is a constant of the authored
## layout, so when the parent moves the child rides on the node transform and keeps its designed
## spacing. That holds while a child's own rect is a constant too — which is every child except one
## shape: a child that answers WHERE by reference to the SAME key location its parent does
## (`at(slug)` on both, ADR-0088 Amendment 4 §2 — the START menu's glove cursor). There the child's
## rect is LIVE, so a scrub of that slug moves the parent's transform by the delta AND grows this
## "constant" offset by the same delta: the child moves TWICE. Measured at exactly 2.00x
## (StartMenuLocationSweepTest) — the glove drifted away from its own menu at double the rate.
##
## Sharing the parent's slug means having no independent placement — the two rects are the same
## rect, by construction — so the offset is ZERO and stays zero through both scrubs and re-homes.
func _place_self() -> void:
	var parent_home := Vector2.ZERO
	if _parent_element != null:
		if _shares_parent_location():
			position = _screen_to_world(0.0, 0.0)
			return
		parent_home = _parent_element.authored_home()
	position = _screen_to_world(_rect.position.x - parent_home.x, _rect.position.y - parent_home.y)


## Do this element and its parent element answer WHERE by reference to the SAME key location?
## Only an at(slug)-vs-at(same slug) pair qualifies: a literal, a plain derived rect and a
## DIFFERENT location all keep the authored-home offset (see `_place_self`).
func _shares_parent_location() -> bool:
	if _parent_element == null:
		return false
	var mine := _location_slug_of(self)
	return not mine.is_empty() and mine == _location_slug_of(_parent_element)


static func _location_slug_of(e: UI3Element) -> String:
	var ra: Variant = e._spec.get("rect")
	if ra is DerivedRect:
		return String((ra as DerivedRect).location_slug)
	return ""


func _screen_to_world(px: float, py: float) -> Vector3:
	var p := ppu()
	return Vector3(px * p, -py * p, 0.0)


func _find_parent_element() -> UI3Element:
	var n := get_parent()
	while n != null:
		# Only a registered ELEMENT is an ancestor in the element chain — a PAYLOAD UI3Element
		# (a base-swapped widget) between two ELEMENTs is transparently skipped (Amendment 5 §3).
		if n is UI3Element and (n as UI3Element).role() == Role.ELEMENT:
			return n
		n = n.get_parent()
	return null


## The fold predicate is Fold.owns() (ADR-0191). This class used to publish `fold_owns()`, a copy
## that reached the autopilot autoload by node path and so had to guard `is_inside_tree()` first.
## The METHOD is gone: the kernel's static answers before a node exists at all, so the predicate
## never needed a tree.
##
## The GUARD is NOT gone, and deleting it here the first time was the bug (ADR-0191 dec. 1).
## `is_inside_tree()` was doing two jobs in one function, and only one of them belonged to the
## predicate. The other is `z_for`'s own precondition — a rung Z means nothing until criteria
## resolve against a mounted parent — and it lives on `z_for` now. Do not "simplify" it away.
