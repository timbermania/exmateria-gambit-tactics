extends Node

## The PUBLISHED cursor port — ADR-0164 dec. 4 criterion 1, closed by ADR-0206.
##
## A host that wants a roam cursor names THIS and nothing else. It owns the pair the
## four cursor hosts used to assemble by hand — a `TileCursor` node and a
## `CursorController` — and re-exports the six members those hosts actually reached:
## four signals, `grid_pos`, and `SEMI_MODE_LABELS`. Measured, not guessed: the union
## of every member `src/` reads off a cursor handle is exactly that list.
##
## 🔴 WHY `TileCursor` AND `CursorController` LOST THEIR `class_name`s, and why that is
## the decision rather than a rename (ADR-0192 dec. 4, applied a second time). Criterion 1
## scans `class_name`s, so a type without one CANNOT be in the published set — and a door
## on a class nobody can name is not a door. The runner-up was leaving both names in place
## and asking hosts politely to use the rig; that makes *published* a NAMING CONVENTION,
## which is exactly what criterion 1 exists to replace. `TileCursor.tscn` still carries the
## script by path, and everything inside this addon `preload`s it.
##
## ⚠️ This is not the forwarder ADR-0170 dec. 1 refused. That refusal was about the
## RECEIVER being untypeable — `$ProceduralMap` infers `Node`, so a forwarder leaves every
## consumer duck-typed. Consumers name `CursorRig` BY TYPE, which is what the forwarder
## could not give: `BattlefieldWiring.wire_cursor(rig: CursorRig)`,
## `FormationMapHost.bind_map(rig: CursorRig, …)` and
## `CursorDebugPanel.setup(rig: CursorRig)` are all statically typed, where they used to
## take a `TileCursor`. Delegation was never the objection.
##
## 🔴 TWO MEMBERS WERE ADDED FOR THE TURN-OPEN BEAT (`docs/TURN-OPEN-BEAT-DESIGN.md`), and
## the minimality rule above is the reason to say so rather than to quietly grow. "Measured,
## not guessed" measured what hosts read in 2026-08; it is a rule about how a member EARNS its
## place, not a claim that the list can never grow. Each of these two is a thing a host now
## genuinely does and could not say any other way:
##
##   `move_to(cell)`        the HOST placing the cursor, as distinct from the player walking it.
##                          `seed_from_map` was the only programmatic placement on this façade
##                          and it is the wrong shape here — it move_to's and then SNAPS the
##                          camera, which is exactly the second lurch a travel exists to avoid.
##   `input_enabled`        the cursor deaf for the length of a host beat. Not expressible as a
##                          camera TAKEOVER: that mode blanks the dagger and makes
##                          `PlayerCamera._process` skip `_execute_cursor_follow`, so the travel
##                          the beat is showing would not animate at all.
##
## ⚠️ `input_enabled` gates THIS RIG and nothing else — it is not a global input mute and no
## member here can make it one. The battlefield's device input is TWO surfaces, not one:
## `camera_up/down/left/right` walk the cursor (`TileCursor.CURSOR_ACTIONS`) and are gated here,
## while Q/E and F are `PlayerCamera._input`'s and are gated by the twin flag on that file. A
## host silencing a beat sets both, and its own handler is a third.

## Two ways in, because the hosts genuinely differ and ADR-0204's lesson was that changing
## scene structure to suit a register is the expensive mistake:
##
##   `bind()`   the cursor is AUTHORED IN THE SCENE (`$TileCursor` — GPUArena,
##              EffectViewerScene, FireCastReproScene). The node path stays byte-identical
##              and is a scene-tree coupling, not a type reference (ADR-0196 dec. 2).
##   `mount()`  the host has no cursor node and wants one built (NavigatorMain's command
##              cursor). Instantiates `TileCursor.tscn`, sets the two exported NodePaths
##              BEFORE `add_child` so `_ready` reads them, and owns the result — so
##              `dispose()` frees the cursor here and does not there.

# ADR-0211 dec. 2 — this file referenced its OWN `class_name`, which the
# façade pass deleted. A self-preload restores the spelling with no body edit.
const CursorRig = preload("res://addons/exmateria_battlefield/cursor/CursorRig.gd")

const TileCursorScene := preload("res://addons/exmateria_battlefield/cursor/TileCursor.tscn")
const TileCursorScript := preload("res://addons/exmateria_battlefield/cursor/TileCursor.gd")
const CursorControllerScript := preload("res://addons/exmateria_battlefield/cursor/CursorController.gd")

## Re-exported from the cursor so a host reading the outline-blend labels — today only
## `CursorDebugPanel` — names the port instead of the implementation. Four of criterion 1's
## twenty-one sites were reads of this one constant.
const SEMI_MODE_LABELS: Array[String] = TileCursorScript.SEMI_MODE_LABELS

## Relayed from the bound cursor, once each, in `_relay`. There is exactly ONE emit site
## per signal and it is that connection: a second `emit` anywhere here would make a
## consumer see the same step twice and no test could tell which one fired.
##
## FIVE since #941, not four. `cursor_cancelled` is the third of the act/look/cancel triple; it
## was a `ui_cancel` test in `GambitBattle._unhandled_input` while its two twins were signals, so
## the port published two thirds of one intent and the host re-derived the rest. The docstring
## above this class still says "four signals" about the MEASURED union that closed criterion 1 —
## that measurement was of the members hosts read in 2026-08, and it stays true of what it
## measured.
signal cursor_moved(grid_pos: Vector2i)
signal cursor_stepped(grid_pos: Vector2i)
signal cursor_confirmed(grid_pos: Vector2i)
signal cursor_inspected(grid_pos: Vector2i)
signal cursor_cancelled(grid_pos: Vector2i)

var _cursor: TileCursorScript = null
var _controller: CursorControllerScript = null
## True only when `mount()` built the cursor. `dispose()` frees what this rig created and
## nothing else — a scene-authored `$TileCursor` outlives the rig.
var _owns_cursor: bool = false


## Bind a cursor the host's scene already authors. `cursor` is whatever `$TileCursor`
## resolved to; it is a node, not a named type, which is the whole point.
static func bind(parent: Node, cursor: Node, camera) -> CursorRig:
	if cursor == null or not is_instance_valid(cursor):
		return null
	var rig := CursorRig.new()
	rig.name = "CursorRig"
	rig._cursor = cursor
	parent.add_child(rig)
	rig._build(camera)
	return rig


## Build a cursor and bind it. `map_path` / `camera_path` are resolved by the cursor's
## `_ready` RELATIVE TO ITS PARENT, so they are the parent's own sibling paths — set
## before `add_child` or `_ready` reads empty ones.
static func mount(parent: Node, camera, map_path: NodePath, camera_path: NodePath) -> CursorRig:
	var cursor = TileCursorScene.instantiate()
	if cursor == null:
		push_warning("[CursorRig] mount: TileCursor.tscn did not instantiate")
		return null
	cursor.procedural_map_path = map_path
	cursor.player_camera_path = camera_path
	parent.add_child(cursor)
	var rig := bind(parent, cursor, camera)
	if rig != null:
		rig._owns_cursor = true
	return rig


func _build(camera) -> void:
	_controller = CursorControllerScript.new()
	add_child(_controller)
	_controller.setup(_cursor, camera)
	_relay()


func _relay() -> void:
	if _cursor == null:
		return
	_cursor.cursor_moved.connect(func(p): cursor_moved.emit(p))
	_cursor.cursor_stepped.connect(func(p): cursor_stepped.emit(p))
	_cursor.cursor_confirmed.connect(func(p): cursor_confirmed.emit(p))
	_cursor.cursor_inspected.connect(func(p): cursor_inspected.emit(p))
	_cursor.cursor_cancelled.connect(func(p): cursor_cancelled.emit(p))


## The cursor's current grid cell. `Vector2i.ZERO` before a cursor is bound — the same
## value a fresh `TileCursor` reports, so a host cannot tell "unbound" from "at origin"
## and must not try to.
var grid_pos: Vector2i:
	get:
		return _cursor.grid_pos if _cursor != null and is_instance_valid(_cursor) else Vector2i.ZERO


## Seed the cursor onto the map once its tiles exist. Timing is the host's — it
## legitimately differs per scene — which is why this is a call and not part of `bind`.
func seed_from_map(map, cell: Vector2i = Vector2i.ZERO, snap_camera: bool = true) -> void:
	if _controller != null:
		_controller.seed_from_map(map, cell, snap_camera)


## Place the cursor on `cell`. The HOST's hand on the cursor — `cursor_moved` fires and
## `cursor_stepped` does NOT, which is the whole of #589's distinction: a listener that wants
## "the player moved it" stays silent through a beat, and one that wants "where is it now"
## repaints. The docked hover pair is the second kind, which is why parking the cursor on a
## unit brings its portrait in for free.
##
## No-op off-grid rather than an error: `TileCursor._refresh_mesh(null)` hides the dagger, so a
## column with no tile leaves the cursor nameless instead of crashing the host mid-beat.
func move_to(cell: Vector2i) -> void:
	if _cursor != null and is_instance_valid(_cursor):
		_cursor.move_to(cell)


## Is the cursor listening to the device? See the 🔴 note in the class docstring for what this
## does NOT cover. `true` when no cursor is bound, so a host that never bound one cannot read
## "deaf" off an empty rig and conclude a beat is running.
var input_enabled: bool:
	get:
		return _cursor.input_enabled if _cursor != null and is_instance_valid(_cursor) else true
	set(value):
		if _cursor != null and is_instance_valid(_cursor):
			_cursor.input_enabled = value


## Tear the rig down. Frees the cursor ONLY if `mount()` built it.
func dispose() -> void:
	if _owns_cursor and _cursor != null and is_instance_valid(_cursor):
		_cursor.queue_free()
	_cursor = null
	_controller = null
	queue_free()
