extends Node

## The UI3 element registry (ADR-0088) — an INDEX of live UI3Elements + signals, and
## (as slices land) the host for the shared engines (clip, transition, metrics).
## The scene tree IS the registry: this autoload never stores a parallel hierarchy —
## parenthood is resolved by each element on _enter_tree and queried live here.
## Autoloaded after Tune (elements mint Tune binds at construction).
##
## Read surface (the UI3 dashboard page's entire dependency): roots() /
## children_of() / the two signals.

signal element_registered(e: UI3Element)
signal element_unregistered(e: UI3Element)

# Live registered elements, in registration order. Elements register on _enter_tree
# and unregister on _exit_tree, so membership follows the tree exactly.
var _elements: Array[UI3Element] = []

# The shared clip engine (ADR-0088 §4) — internal; reached through push_clip and the
# forwarded SceneTree.node_added mount-time coverage.
var _clip_engine: UI3ClipEngine
# The shared transition engine (the extracted ADR-0084 beat player) — internal;
# elements reach it through open()/close(), guards through the *_step/advance seams.
var _transition_engine: UI3TransitionEngine


func _ready() -> void:
	_clip_engine = UI3ClipEngine.new(self)
	get_tree().node_added.connect(_clip_engine.on_node_added)
	_transition_engine = UI3TransitionEngine.new()
	_transition_engine.register_beat(UI3Element.Transition.BOX_OPEN, UI3BoxOpenBeat.new())
	_transition_engine.register_beat(UI3Element.Transition.FADE, UI3FadeBeat.new())
	_transition_engine.register_move_beat(UI3Element.Move.SLIDE, UI3MoveSlideBeat.new())


func _process(delta: float) -> void:
	_transition_engine.advance(delta)


## Called by UI3Element._enter_tree. Idempotent (a reparented element re-enters).
func register_element(e: UI3Element) -> void:
	if _elements.has(e):
		return
	_elements.append(e)
	# Cover payload that existed before registration (built in _init / reparented in).
	_clip_engine.schedule_push(e)
	element_registered.emit(e)


## Synchronous fresh-walk clip push for `e` (and its nested elements) — the element's
## _set_aperture/refresh_payload funnel.
func push_clip(e: UI3Element) -> void:
	_clip_engine.push(e)


## Re-push every registered element's clip BASIS (not its clip_world) — for a screen root that
## MOVES while clipped payload is on screen. The camera-child map host does exactly that while its
## entry pan zooms (ADR-0137 Amendment 3); on any screen that owns its own camera this is a no-op
## in effect, because the basis it recomputes is the one already there.
func refresh_clip_basis() -> void:
	_clip_engine.refresh_basis()


## Deferred-flush target for the engine's coalesced mount-time pushes.
func _flush_clip_pushes() -> void:
	_clip_engine.flush()


## The fresh payload discovery for `e` (own subtree, nested elements excluded) —
## the guard/host surface behind UI3Element.payload_materials().
func payload_materials(e: UI3Element) -> Array:
	return _clip_engine.payload_materials(e)


## The fresh own-payload MESH discovery for `e` (own subtree, nested elements excluded)
## — the ownership map's swap/mute surface (ADR-0088 Amendment 6), sibling of
## payload_materials. Behind UI3Element.payload_meshes().
func payload_meshes(e: UI3Element) -> Array:
	return _clip_engine.payload_meshes(e)


## UI3Element.open()/close() funnel. Returns false when the element's kind has no
## playback (NONE / RIDE_PARENT / unregistered) — the element settles instantly.
func play_transition(e: UI3Element, reversed: bool,
		cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> bool:
	return _transition_engine.play(e, reversed, cadence)


## Register (or unregister, with null) the beat implementing a Transition kind.
func register_beat(kind: int, beat: UI3Beat) -> void:
	_transition_engine.register_beat(kind, beat)


## The beat implementing a Transition kind (null when none registered) — the UI3 page's
## read seam for asking a declared beat its precondition (ADR-0088 Amendment 3 §5).
func beat_for(kind: int) -> UI3Beat:
	return _transition_engine.beat_for(kind)


## UI3Element.place_at() funnel (ADR-0097 §5). Returns false when the element declares no
## move beat — place_at then snaps, which is what it has always done.
func play_move(e: UI3Element, cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> bool:
	return _transition_engine.play_move(e, cadence)


## Guard seam: is a MOVE play live on this element?
func transition_engine_is_moving(e: UI3Element) -> bool:
	return _transition_engine.is_moving(e)


## Register (or unregister, with null) the beat implementing a Move kind (ADR-0097 §5).
func register_move_beat(kind: int, beat: UI3Beat) -> void:
	_transition_engine.register_move_beat(kind, beat)


## The beat implementing a Move kind (null when none registered / Move.NONE = snap).
func move_beat_for(kind: int) -> UI3Beat:
	return _transition_engine.move_beat_for(kind)


## Guard seam: is a transition play live on this element? (An IMMEDIATE cadence must leave
## none behind — it settles inside play().)
func transition_engine_is_playing(e: UI3Element) -> bool:
	return _transition_engine.is_playing(e)


## Guard seam: hand-step every active transition play one beat frame.
func transition_engine_step() -> void:
	_transition_engine.step()


## Guard seam: accumulate `delta` into the active plays (the _process drive, callable
## directly so a guard can feed a synthetic spike).
func transition_engine_advance(delta: float) -> void:
	_transition_engine.advance(delta)


## The boot-time reversibility audit over every live registered element (ADR-0084
## invariant 1 / ADR-0088 §7.4). Empty = every named beat exists and reverses.
func transition_reversibility_errors() -> Array:
	return _transition_engine.reversibility_errors(_elements)


## The boot-time per-beat CADENCE audit over every live registered element (ADR-0097 §1).
## Empty = every authored cadence names a curve its declared beat actually has.
func transition_cadence_errors() -> Array:
	return _transition_engine.cadence_errors(_elements)


## Called by UI3Element._exit_tree.
func unregister_element(e: UI3Element) -> void:
	if _elements.has(e):
		_elements.erase(e)
		_clip_engine.forget(e)
		_transition_engine.forget(e)
		element_unregistered.emit(e)


## Every live registered element, in registration order.
func elements() -> Array[UI3Element]:
	return _elements.duplicate()


## Registered elements with no registered ancestor — the screens.
func roots() -> Array[UI3Element]:
	var out: Array[UI3Element] = []
	for e in _elements:
		if e.parent_element() == null:
			out.append(e)
	return out


## The registered elements whose nearest registered ancestor is `parent`.
func children_of(parent: UI3Element) -> Array[UI3Element]:
	var out: Array[UI3Element] = []
	for e in _elements:
		if e.parent_element() == parent:
			out.append(e)
	return out
