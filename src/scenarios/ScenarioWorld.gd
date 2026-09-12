class_name ScenarioWorld
extends RefCounted
## The injected capability object the event-script apply layer mutates (ADR-0058).
##
## [ScenarioDecode] turns opcode operands into a pure intent; [ScenarioApply]
## turns an intent into world mutation — but only by calling *verbs* on this
## facade (`place_unit_on_tile`, `set_unit_facing`, …), never by reaching into a
## node directly. In production the facade wraps the live scene the [ScenarioVM]
## already holds (its unit registry, map composer, actor registry, overlays); in a
## test the same [ScenarioApply] code runs against a [FakeScenarioWorld] that
## records the verb calls, so an apply is unit-testable without booting a scene.
## That is the whole point of the seam: one code path, real world vs. fake world.
##
## The facade is a THIN verb surface grown family-by-family as opcodes migrate off
## the VM — deliberately not a mirror of the god-Node's getters (that would just
## move the coupling here). It reads the VM's collaborators LIVE at call time (the
## host scene wires `units_by_id` / `map_composer` onto the VM *after* `_ready`), so
## it holds the VM reference rather than snapshotting the refs — but per the
## base-class member-drop trap in CLAUDE.md it uses a plain field + methods, never
## getter-only forwarding properties.

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

## The owning [ScenarioVM]. Untyped to avoid a cyclic `class_name` dependency
## (the VM holds a `ScenarioWorld`). Null in a [FakeScenarioWorld].
var _vm = null


func _init(vm = null) -> void:
	_vm = vm

# ---------------------------------------------------------------------------
# Verb surface — grown family-by-family as behavioral opcodes migrate off the
# VM. Each verb wraps one live-scene mutation the apply layer needs; the whole
# surface is what a [FakeScenarioWorld] mirrors.
# ---------------------------------------------------------------------------

# --- Unit placement & facing ({24} Warp Unit) ------------------------------

## Is a spawned unit registered under `uid`? Handlers skip (with a warning) when
## a Warp / Move / anim opcode names a unit the scene never spawned.
func has_unit(uid: int) -> bool:
	return _vm.units_by_id.has(uid)


## Place unit `uid` on tile (`psx_x`, `psx_y`) — the cinematic spawn/warp
## placement. Returns false (no mutation) when there is no map composer to resolve
## the tile against, so the caller can bail exactly as the inline handler did. The
## event-Y row is already Godot-native (pre-flipped by the parser, ADR-0057), so it
## is consumed raw.
func place_unit_on_tile(uid: int, psx_x: int, psx_y: int) -> bool:
	if _vm.map_composer == null:
		push_warning("[ScenarioWorld] no map_composer ref, cannot place unit 0x%02X" % uid)
		return false
	ScenarioVM.cinematic_place(_vm.units_by_id[uid], psx_x, psx_y, _vm._lattice())
	return true


## Drop unit `uid`'s captured Sprite-Move home so the next move re-captures it.
## Warp re-places the base (zeroing the +0x60 offset on hardware) with the same
## node, which the owner_iid guard can't detect — this forces the recapture.
func clear_actor_home(uid: int) -> void:
	var a = _vm.peek_actor(uid)  # _vm untyped (cyclic class dep) -> Variant
	if a != null:
		a.clear_home()


## The single facing writer (#752). `scenario_set_facing` takes the 12-bit ORIENTATION
## angle and writes `facing_angle`, the source of truth ADR-0057 names; the cardinal
## enum follows as a derived view. There is deliberately no second path: writing the
## enum slot instead would be ADR-0057's backward arrow, and the `facing_direction`
## fallback that used to sit here wrote the raw ANGLE into a slot declared 0..3.
## Guarded because a dispatch-only mock may carry no facing surface at all — such a
## unit is left unfaced rather than faced wrongly.
func _set_facing(unit, facing_12bit: int) -> void:
	if unit != null and unit.has_method("scenario_set_facing"):
		unit.scenario_set_facing(facing_12bit)


## Set unit `uid`'s facing to the raw 12-bit PSX world angle (the renderer composes
## the camera yaw). Warp/cinematic-spawn facing — ROM-faithful (0x80087c1c `<<10`).
## Also the {8C} instant snap.
func set_unit_facing(uid: int, angle_12bit: int) -> void:
	_set_facing(_vm.units_by_id[uid], angle_12bit)


# --- Unit lifecycle ({45} Add / {44} Draw / {46} Erase / {3D} Remove) -------

## {45} Add Unit graphic-commit (SHP/SEQ). Marks the unit PRESENT (allocated in the
## sprite list / broadcast roster); the render reveal itself is set by the caller
## (ScenarioApply.add_unit, from the Draw byte). Still the seam point for future
## SHP/SEQ stat-commit work.
func commit_unit_graphic(uid: int) -> void:
	# {45} Add Unit introduces the unit into the scene (PSX: allocates its sprite
	# object / roster slot). Mark it PRESENT so team-broadcast opcodes target it
	# even while its Draw byte holds it hidden. Render visibility stays governed by
	# {44}/{46}. See _unit_roster.
	var u = _vm.units_by_id.get(uid)
	if u != null and is_instance_valid(u) and "scenario_present" in u:
		u.scenario_present = true


## Show ({44} Draw) or hide ({46} Erase) unit `uid`'s sprite.
func set_unit_visible(uid: int, visible: bool) -> void:
	var u = _vm.units_by_id[uid]
	# A hidden->visible flip is a REVEAL: tell the VM so the end-of-tick drain can
	# land a same-tick {11} pose on the reveal frame itself, instead of showing the
	# unit's stale pre-reveal pose for one frame (scenario 29 pc76; ScenarioVM
	# `_paint_revealed_unit_anims`). A redundant {44} on an already-visible unit is
	# NOT a reveal — it must not pull that unit's latch forward.
	var was_visible: bool = bool(u.visible)
	u.visible = visible
	if visible and not was_visible:
		_vm.note_unit_revealed(uid)
	# {44} Draw introduces/keeps the unit present in the broadcast roster; {46}
	# Erase clears only the render flag (+0xa) — the unit stays allocated, so it is
	# NOT removed from presence here (only {3D} Remove deallocates).
	if visible and "scenario_present" in u:
		u.scenario_present = true


## Resolve a u16 chunk unit id to a live registry key (falling back to the low byte
## for u8-keyed ENTD spawns), or -1 if no unit matches.
func resolve_unit_key(chunk_unit_id: int) -> int:
	return _vm._resolve_unit_key(chunk_unit_id)


## Resolve a Units/Multi target selector to the live registry keys it addresses
## (the shared multi-unit broadcast — EVENT_UNIT_SET_RESOLUTION.md). Multi=0 → the
## single unit `resolve_unit_key` finds (preserving the u16→u8 / special-id ≥0x80
## path), as a 0- or 1-element list. Multi≠0 → a team-set BROADCAST: every present
## unit whose team matches the mode, in roster (spawn) order. Empty when nothing
## matches. The apply layer loops the result, so ONE code path serves both single and
## broadcast, and a [FakeScenarioWorld] inherits this by overriding only the two data
## providers (`resolve_unit_key`, `_unit_roster`).
func resolve_unit_set(units: int, multi: int) -> Array:
	var mode := ScenarioDecode.unit_set_mode(units, multi)
	if mode == ScenarioDecode.UnitSetMode.SINGLE:
		var k := resolve_unit_key(units)
		return [k] if k >= 0 else []
	var keys: Array = []
	for entry in _unit_roster():
		if ScenarioDecode.unit_set_member(mode, entry["team_color"], entry["alive"]):
			keys.append(entry["key"])
	return keys


## The broadcast candidate roster: one `{key, team_color, alive}` per PRESENT scenario
## unit, in spawn order. Presence gates on `scenario_present` — the ROM's membership
## predicate is "resolves to a live node in unit_sprite_list" (FUN_8008cbb4) = the
## unit is ALLOCATED, which is INDEPENDENT of the `+0xa` render flag. A held-but-
## allocated principal (ENTD `always_present`, awaiting its {44} Draw) IS in the list,
## so it must be a broadcast target while still `visible=false` — this is scn6 Ovelia
## at the pc31 player-team rotate (she used to be caught only because the old
## `.visible` filter happened to include her when she spawned visible; the
## chunk-derived visibility fix made her spawn hidden and the `.visible` filter then
## wrongly dropped her). Not-yet-added units (scn6 0x01/0x04, {45} Add at pc434) have
## `scenario_present=false` and stay excluded. `scenario_present` is set at spawn for
## always_present units and by {45}/{44}/{47} (see commit_unit_graphic /
## set_unit_visible / _spawn_ghost_actor). `team_color` is the ENTD flags2 team
## (0 = blue/player). `alive` is present-and-valid — cutscenes have no deaths.
## Overridden by [FakeScenarioWorld] with a canned roster so `resolve_unit_set`'s
## broadcast logic is testable without a scene.
##
## PSX-CONFIRMED (2026-07-09): the held-but-allocated principal case is correct.
## Captured on real hardware at scn6 pc31 (scenario-event-debugger, base
## scenario6_letgo_full_base): Ovelia's facing field +0x70 changes 0xC00->0x800
## across the [Units=1,Multi=1,Facing=8] rotate while she reads +0xa(show)=0
## (undrawn; her {44} Draw is at pc104) and +0x204(primitive)!=0 (allocated) — so
## the mode-3 broadcast turns her independent of the render flag. Presence, not
## +0xa, is the roster key. See EVENT_UNIT_SET_RESOLUTION.md §5.1 re-validation.
## STILL PROVISIONAL: whether a {46}-Erased unit (stays `scenario_present=true`
## here) remains a broadcast target was NOT exercised by this capture (pc31 is
## before any Erase; scn6 Erases Agrias at pc71) — leave as-is pending a capture.
func _unit_roster() -> Array:
	var roster: Array = []
	for uid in _vm.units_by_id:
		var unit = _vm.units_by_id[uid]
		if unit == null or not is_instance_valid(unit):
			continue
		if "scenario_present" in unit and not unit.scenario_present:
			continue  # not yet added to the scene (ROM sprite-list absent)
		var team_color: int = unit.scenario_team_color if "scenario_team_color" in unit else 0
		roster.append({"key": uid, "team_color": team_color, "alive": true})
	return roster


## {3D} Remove Unit teardown: erase the registry entry (the scene shares this dict,
## so the scene registry clears too), forget the unit's ScenarioActor bookkeeping,
## and free the sprite node. Idempotent-safe on an already-freed node.
func remove_unit(uid: int) -> void:
	var unit = _vm.units_by_id[uid]
	_vm.units_by_id.erase(uid)
	_vm.forget(uid, unit)
	if is_instance_valid(unit):
		unit.queue_free()


## uids that a {92} Inflict Status (Status=0) marked "block later event HP-restore"
## for, scoped to the running event (PSX global DAT_80165FB4). No in-scenario opcode
## restores HP yet, so nothing consumes this — it is recorded, not enforced (issue
## #154 / decode §4.1). Cleared implicitly when the VM (and thus this world) is
## rebuilt for a new event.
var _hp_restore_blocked: Dictionary = {}


## {92} Inflict Status, Status=0: revive unit `uid` to 1 HP IF it is dead, force a
## clean Standing pose (the sprite pipeline auto-picks the Critical variant when HP
## is low), play the revive SFX only when it was actually dead, and record the
## per-event "block later event HP-restore" flag. Guarded for dispatch-only test
## mocks / freed nodes (no-op). NOT a status bit and NOT body removal.
func revive_and_normalise(uid: int) -> void:
	var unit = _vm.units_by_id.get(uid)
	if unit == null or not is_instance_valid(unit):
		return
	var was_dead := false
	if unit.has_method("scenario_revive_and_normalise"):
		was_dead = unit.scenario_revive_and_normalise(1)
	# The PSX task body plays a sound ONLY if the unit was dead (FUN_80148E88 SS=0).
	# The exact sound id isn't decoded and scenario 6's targets are living, so this
	# stays a documented hook rather than a fabricated id (assets must come from the
	# ISO). Revisit under issue #154 with the SS=1/2 branches.
	if was_dead:
		print("[ScenarioWorld] Inflict Status: unit 0x%02X was dead → revived to 1 HP (revive SFX TODO, issue #154)" % uid)
	_hp_restore_blocked[uid] = true


## {92} Inflict Status, Status=2: Poison + Critical. Adds the Poison status +
## forces the Critical kneel pose on the unit (its PSX-faithful half is
## Unit.scenario_inflict_poison_critical), then applies poison's green sprite
## recolor: a STATIC per-channel palette scale (green preserved, red/blue
## suppressed) baked once and held — the PSX bakes a green CLUT into VRAM at
## apply-time and holds it (no pulse; live-measured, inflict_status_op92_decode.md
## §12). Reuses the {32} Color Unit tint engine with a snap (no ramp/tick). Guarded
## for dispatch-only test mocks / freed nodes (no-op).
func inflict_poison_critical(uid: int) -> void:
	var unit = _vm.units_by_id.get(uid)
	if unit == null or not is_instance_valid(unit):
		return
	if unit.has_method("scenario_inflict_poison_critical"):
		unit.scenario_inflict_poison_critical()
	# Green poison recolor — ROM-derived affine (halve all channels, add green
	# 8/31), snapped and held (not a {32} ramp). See ScenarioColorTint §POISON_*.
	var tint := get_or_create_unit_tint(uid)
	tint.set_static(ScenarioColorTint.POISON_SCALE, ScenarioColorTint.POISON_GREEN_BIAS)
	push_unit_tint(uid, tint)
	print("[ScenarioWorld] Inflict Status: unit 0x%02X → Poison + Critical (green tint + kneel)" % uid)


## {92} Inflict Status, Status=1: Crystal. The unit "turns to crystal" — its body
## sprite is replaced by an animated diamond billboard (Unit.scenario_inflict_crystal).
## Unlike poison there is NO palette recolor: live SS=1 probe showed the poison-style
## FUN_800927bc recolor does NOT fire; only the near-identity palette load runs, and
## the crystal is a dedicated graphic keyed on the crystal bit (+0x58 & 0x40). The
## 8-frame animation cadence (forward loop, 4 vblanks/frame) was RE'd live per-vblank
## (inflict_status_op92_decode.md §12.7/§12.8). Guarded for dispatch-only test mocks /
## freed nodes (no-op).
func inflict_crystal(uid: int) -> void:
	var unit = _vm.units_by_id.get(uid)
	if unit == null or not is_instance_valid(unit):
		return
	if unit.has_method("scenario_inflict_crystal"):
		unit.scenario_inflict_crystal()
	print("[ScenarioWorld] Inflict Status: unit 0x%02X → Crystal (body → animated diamond)" % uid)


## Was unit `uid` marked HP-restore-blocked by a {92} Status=0 this event? (No
## consumer yet; exposed so a future event HP-restore opcode + a test can read it.)
func is_hp_restore_blocked(uid: int) -> bool:
	return _hp_restore_blocked.get(uid, false)


## {47} Add Ghost Unit — instantiate a sprite-only ghost actor and register it under
## `control_id`. A ghost has no ENTD record, so (unlike every normal unit) it is not
## pre-spawned by `ScenarioPlayerScene._spawn_units`; this delegates the actual node
## creation to the host `ghost_spawn_fn` callback (which mirrors `_spawn_unit_at`:
## `body_sprite_id = sprite_set`, `cinematic_place`, seed facing, set visibility, and
## register into the shared `units_by_id`). Returns true iff a ghost was created.
##
## Idempotency (PSX gate `FUN_8007a6e4(slot)==0`): a re-add of a control-id that
## already has a live unit is a no-op — matching the ROM's "only spawn if the slot has
## no sprite yet". A missing host callback (VM-only context) is also a no-op.
func spawn_ghost_unit(control_id: int, sprite_set: int, psx_x: int, psx_y: int,
		elevation: int, facing_12bit: int, visible: bool) -> bool:
	if _vm.units_by_id.has(control_id):
		return false  # already spawned — idempotency gate
	if not _vm.ghost_spawn_fn.is_valid():
		push_warning("[ScenarioWorld] Add Ghost Unit ctrl 0x%02X — no host ghost_spawn_fn wired; skipping" % control_id)
		return false
	var unit = _vm.ghost_spawn_fn.call(control_id, sprite_set, psx_x, psx_y,
		elevation, facing_12bit, visible)
	return unit != null


# --- Unit motion ({3B}/{6E} Sprite Move) -----------------------------------

## Can unit `uid` slide? False for a resolved-away node or a non-spatial test mock
## (no `global_position`) — the apply skips those silently.
func can_slide(uid: int) -> bool:
	var unit = _vm.units_by_id.get(uid)
	return unit != null and is_instance_valid(unit) and ("global_position" in unit)


## Unit `uid`'s current world position (the motion start point).
func unit_position(uid: int) -> Vector3:
	return _vm.units_by_id[uid].global_position


## Capture (or re-capture) unit `uid`'s Sprite-Move home = its base position, and
## return it. Sticky per node; re-captures when a new node rebinds the uid.
func capture_unit_home(uid: int) -> Vector3:
	return _vm.actor(uid).capture_home(_vm.units_by_id[uid])


## Register `motion` (a [ScenarioMotion] slide or a [ScenarioPathMotion] walk) as unit
## `uid`'s in-flight motion. The VM's `_advance_motions` steps it and writes the node
## each frame; the {6F}/{29} Wait barriers poll `motion_done(uid)`. Untyped so both
## sibling value objects arm through the one verb.
func arm_motion(uid: int, motion) -> void:
	_vm.actor(uid).motion = motion


## Cancel unit `uid`'s in-flight [ScenarioMotion] (no-op if none / no actor). A {24}
## Warp re-places the base AND zeroes the +0x60 offset on hardware, so a Sprite-Move
## slide that was still animating when the warp lands must be dropped — otherwise the
## stale motion keeps lerping the unit to its pre-warp target, dragging it back off
## the new base (scn6 Delita ride-off: pc302's slide survived the pc303 warp and
## walked him back up the stairs). research/working_documents/SCENARIO6_RIDE_OFF_CHOCOBO.md
## §Changelog 2026-07-05 s3.
func disarm_motion(uid: int) -> void:
	var a = _vm.peek_actor(uid)
	if a != null:
		a.motion = null


# --- Walk To ({28}) --------------------------------------------------------

## Plan unit `uid`'s Walk To route to the cell (`tx`, `tz`, `level`): pathfind
## (terrain-only — units don't block, stops short only of a terrain-sealed target)
## and resolve the endpoint's world position. Returns
## `{start, target, endpoint}`, or `{}` when there's no map composer or no tile. The
## pathfinding is genuinely VM/scene machinery (the EventWalkNav inner class, the map
## composer), so the verb delegates to the VM — a [FakeScenarioWorld] returns a canned
## plan so the apply is testable without a scene.
##
## `level` is the `{28} Walk To` opcode's `Z` operand (ADR-0219 dec. 7). It is NOT a
## height — it selects which of the target column's up-to-two tiles is meant, and it
## is the byte that decides whether Algus crosses the Igros bridge or wades the moat
## under it. `endpoint` comes back as a `Vector3i` carrying the level actually
## reached, which need not be the one asked for.
## `flat_cost` is the opcode's OWN cost switch — its last operand byte, `0` meaning
## "every surface costs 1". 20 of the 561 shipped `{28}`s set it, and it is how a
## scenario walks a unit straight across water the movement-cost row would otherwise
## route it around (research README §20.1).
func plan_walk(uid: int, tx: int, tz: int, level: int = 0,
		flat_cost: bool = false) -> Dictionary:
	return _vm._plan_walk_route(uid, tx, tz, level, flat_cost)


## Latch unit `uid`'s logical cell to `cell` — the seat a `{28} Walk To` route ends on.
##
## 🔴 THIS IS THE WRITER ADR-0219 dec. 6 SPECIFIED AND NOBODY BUILT. "A mover
## interpolates world position and LATCHES level at the seat tile" needs something to
## latch it INTO, and `grep -rn current_cell src/scenarios/` returned zero writers —
## the level operand went in through `plan_walk` and came back out of nothing. The
## read side, `ScenarioVM._unit_cell`, then fell through to `TerrainCell.ground(x, z)`
## for every actor in every scenario, so a unit's start level was hardcoded 0 no matter
## where it was standing.
##
## What that cost, measured: scenario 29 pc 34 walks Algus onto MAP009 `(4,11)` LEVEL 1,
## the one selectable level-1 tile on the map — the Igros bridge deck. pc 164 asks him
## for `(3,11)` level 0, the deck's own west end, orthogonally adjacent and the same
## height 7. Planned from the deck the route is ONE step. Planned from `(4,11)` level 0
## — the Waterway `h1` UNDER the bridge, which is what the missing latch made the
## planner believe — the climb gate correctly refuses to let him haul himself 6
## half-steps out of the moat onto either bank, so the flood wades him 13 tiles north
## up the channel, out at `(1,7)`, and back down the stone bank: `waypts=14`, 7.3 s of
## visible wandering to reach the tile he was standing next to.
##
## Latched when the walk is ARMED, not when it lands. The value is the seat tile's
## level either way — dec. 6's "latches ... at the seat tile" is about WHAT is latched
## (the seat's own level, never one blended out of a height), and the armed route
## already names the seat. Arming is also the only moment every terminating path shares:
## `_advance_motions`' `is_done`, `_drain_motions_to_target`' `snap_to_end`, and the
## `{24}` warp's `disarm_motion` do not, and a latch hung off completion would be
## silently skipped by two of the three. The in-flight window this opens is closed on
## the read side, which is where it always was: `_unit_cell` only trusts a held cell
## whose `(x, z)` matches the unit's live transform, so a unit part-way along a route —
## or one a warp yanked off it — falls back to the column ground exactly as before.
func seat_unit_cell(uid: int, cell: Vector3i) -> void:
	var unit = _vm.units_by_id.get(uid)
	if unit == null or not is_instance_valid(unit):
		return
	var mc = unit.get("movement_component")
	if mc == null or not is_instance_valid(mc):
		return
	mc.current_cell = cell


## Put unit `uid` into the movement-walk state: orient it to `facing_12bit` (a 12-bit
## ORIENTATION angle) and set its animation to `anim_id` (the FFT movement-walk SEQ).
## The facing goes through `scenario_set_facing` so the walk writes the source of truth
## (`facing_angle`, what the VM renderer reads) — not just the derived enum, which left
## the unit rendering its stale pre-walk facing (the chocobo sideways-walk, ADR-0057).
## The facing goes through `_set_facing`, the one writer (#752). The anim is guarded
## separately for dispatch-only test mocks that lack `play_body`.
func set_walking(uid: int, facing_12bit: int, anim_id: int) -> void:
	var unit = _vm.units_by_id[uid]
	_set_facing(unit, facing_12bit)
	if unit.has_method("play_body"):
		unit.play_body(anim_id)
	# Drop any still-pending {11} Unit Anim latch on this unit. A Walk To that
	# follows a {11} with no Wait between them (scenario-6 Agrias pc263 {11}
	# anim(2) → pc264 {28} Walk To) would otherwise let the stale latch paint an
	# idle pose OVER the walk on the next consume tick — she'd glide in a frozen
	# idle ("walking but isn't"). The walk is the newer authoritative body anim
	# (last-write-wins on the PSX +0x0C slot; real FFT shows her walking), so the
	# pending {11} is superseded. No-op when nothing is pending (the two Agrias
	# walks that carry a Wait clear the latch before this via the normal consume).
	var a = _vm.peek_actor(uid)  # _vm untyped (cyclic class dep) -> Variant
	if a != null:
		a.pending_anim = -1


## Update unit `uid`'s facing ONLY (no anim replay) — a Walk To route turn re-faces
## the body mid-walk without restarting the movement-walk SEQ clock. `facing_12bit` is
## a 12-bit ORIENTATION angle; `scenario_set_facing` writes the source of truth
## (`facing_angle`) and derives the enum, so a turning route re-faces the octant the
## renderer actually reads. The write goes through the repaint-only path
## (Unit._on_facing_angle_changed / _on_facing_direction_changed), so this doesn't
## re-resolve the body from activity and clobber the walk (the Gafgarion door-exit
## clobber; see project memory). Goes through `_set_facing`, the one writer (#752).
func set_walk_facing(uid: int, facing_12bit: int) -> void:
	var unit = _vm.units_by_id.get(uid)
	if unit == null or not is_instance_valid(unit):
		return
	_set_facing(unit, facing_12bit)


# --- Facing & animation ({11}/{8C}/{2D}/{53}/{2C}) -------------------------

## Is unit `uid` a live, valid node? (Not a freed instance.)
func has_valid_unit(uid: int) -> bool:
	var unit = _vm.units_by_id.get(uid)
	return unit != null and is_instance_valid(unit)


## Can unit `uid` be a face-rotation participant? Valid node with a spatial
## transform (the look-at reads its position).
func can_face(uid: int) -> bool:
	var unit = _vm.units_by_id.get(uid)
	return unit != null and is_instance_valid(unit) and ("global_position" in unit)


## Play event-script animation `anim_id` on unit `uid` (idle / SEQ / EVTCHR-range
## dispatch + cinematic-walker spawn — the scene machine on the VM). Returns false
## (skip) when the unit's sprite pipeline isn't ready.
func play_unit_anim(uid: int, anim_id: int) -> bool:
	return _vm._apply_unit_animation(_vm.units_by_id[uid], uid, anim_id)


## {80} March release — return unit `uid` to its combat-idle "march in place" pose.
## The port mirror of the ROM re-running the status-anim selector FUN_80082eec @0x80082EEC
## on the addressed unit (MARCH_OPCODE_80_SEMANTICS.md §2): drop the cinematic freeze
## (`is_cinematic_unit = false`) and re-resolve the natural idle so a unit HELD in a
## cinematic pose (the {11} talk pose) resumes marching. Keeps the anim clock VM-tick
## driven. An already-marching unit re-resolves to the same idle SEQ = a no-op repaint.
func release_to_combat_idle(uid: int) -> void:
	var unit = _vm.units_by_id.get(uid)
	if unit == null or not is_instance_valid(unit):
		return
	if "is_cinematic_unit" in unit:
		unit.is_cinematic_unit = false
	if "clock_owner" in unit:
		unit.clock_owner = ClockOwner.SCENARIO
	if unit.has_method("update_animation"):
		unit.update_animation()


## Unit `uid`'s current 12-bit facing baseline for a {2D} relative rotation: its live
## `facing_angle` if set, else its cardinal-derived seed (VM read).
func rotate_baseline_12bit(uid: int) -> int:
	return _vm._rotate_baseline_12bit(uid)


## Arm unit `uid`'s facing stepper toward `target_12bit` over a
## Direction/Speed/Delay-shaped duration (Unit-side stepper, ADR-0055). Guarded for
## mocks lacking the method.
func arm_rotate(uid: int, target_12bit: int, direction: int, speed: int, delay: int) -> void:
	var unit = _vm.units_by_id[uid]
	if unit.has_method("scenario_rotate"):
		unit.scenario_rotate(target_12bit, direction, speed, delay)


## PSX 12-bit look-at angle from unit `aff_uid` toward unit `faced_uid` (reads both
## positions + map depth — VM/scene machinery).
func face_look_at_12bit(aff_uid: int, faced_uid: int) -> int:
	return _vm._face_unit_look_at_12bit(_vm.units_by_id[aff_uid], _vm.units_by_id[faced_uid])


## {69} Face Tile look-at: PSX 12-bit angle from unit `aff_uid` toward a map tile
## (tile_x, tile_y) — the tile-target analogue of face_look_at_12bit.
func face_tile_look_at_12bit(aff_uid: int, tile_x: int, tile_y: int) -> int:
	return _vm._face_tile_look_at_12bit(_vm.units_by_id[aff_uid], tile_x, tile_y)


## {4E} Unit Shadow: toggle a unit's ground drop-shadow via the per-unit
## UnitShadow (Unit._shadow.set_enabled). `enabled` false hides it regardless of
## ground contact — the event-script's way of dropping the shadow of a lifted /
## airborne / ridden-off unit.
func set_unit_shadow(uid: int, enabled: bool) -> void:
	var unit = _vm.units_by_id.get(uid)
	if unit == null or not is_instance_valid(unit):
		return
	if "_shadow" in unit and unit._shadow != null:
		unit._shadow.set_enabled(enabled)


## {68} Mirror Sprite: latch unit `uid`'s persistent whole-sprite horizontal flip
## delta. The PSX handler writes `unit[+0x13F]` = 0x02 / 0x00 and the render
## dispatch XORs that byte with the facing/camera-derived `render_flags(+0x12)`
## every frame (`xor` @0x80086764), so this is a TOGGLE relative to the natural
## flip, not an override — see MIRROR_SPRITE_OPCODE_68.md. SpriteLayerManager
## holds the two halves apart and recomposes on either write.
func set_unit_mirror(uid: int, mirrored: bool) -> void:
	var unit = _vm.units_by_id.get(uid)
	if unit == null or not is_instance_valid(unit):
		return
	var slm = unit.get("sprite_layers")
	if slm == null or not slm.has_method("set_mirror_xor"):
		return
	slm.set_mirror_xor(mirrored)


# --- Tint & palette ({32}/{33}/Reset Palette/{1A}) -------------------------

## Unit `uid`'s live {32} Color Unit tint, creating an identity one if none exists
## (so the caller can fold the operand into it).
func get_or_create_unit_tint(uid: int) -> ScenarioColorTint:
	var a = _vm.actor(uid)  # _vm untyped (cyclic class dep) -> Variant
	if a.tint == null:
		a.tint = ScenarioColorTint.new()
	return a.tint


## Push unit `uid`'s tint (composed with the active {33} field tint) to its sprite
## shader.
func push_unit_tint(uid: int, tint: ScenarioColorTint) -> void:
	_vm._apply_unit_tint(uid, tint)


## Drop unit `uid`'s {32} tint sub-state (the actor entry survives).
func clear_unit_tint(uid: int) -> void:
	var a = _vm.peek_actor(uid)  # _vm untyped (cyclic class dep) -> Variant
	if a != null:
		a.tint = null


## The live {33} Color Field broadcast tint, creating an identity one if none.
func get_or_create_field_tint() -> ScenarioColorTint:
	if _vm._field_tint == null:
		_vm._field_tint = ScenarioColorTint.new()
	return _vm._field_tint


## Broadcast the field tint to every unit (composed with each unit's {32} tint) and
## the map palette.
func push_field_tint_to_all() -> void:
	_vm._apply_field_tint_to_all()


## Drop the {33} field tint (units fall back to their own {32} tints, map to base).
func clear_field_tint() -> void:
	_vm._field_tint = null


## {1A} Map Darkness — set the oxide target/start and snap-or-arm the ramp (VM state
## ticked outside the halt gate).
func set_map_darkness(intent: ScenarioDecode.MapDarknessIntent) -> void:
	_vm._set_oxide_from_intent(intent)


# --- Screen & overlay effects ({3C}/{76}/{77}/{78}/{7D}/Reveal) ------------

## {3C} Weather — latch the rain particle system on/off. Lazily spawns the node on
## the first active latch; an inactive latch with no node yet is a no-op.
func set_weather(active: bool, strength: int) -> void:
	if _vm._weather == null:
		if not active:
			return
		_vm._weather = _vm._make_weather()
	_vm._weather.set_weather(active, strength)


## {76} Dark Screen — lazily create the mosaic overlay and start it from `intent`.
func show_dark_screen(intent: ScenarioDecode.DarkScreenIntent) -> void:
	if _vm._dark_screen == null:
		_vm._dark_screen = _vm._make_dark_screen()
	_vm._dark_screen.start(intent)


## {77} Remove Dark Screen — retract the mosaic overlay if one exists.
func hide_dark_screen() -> void:
	if _vm._dark_screen != null:
		_vm._dark_screen.remove()


## {3E} Color Screen — lazily create the full-screen colour-ramp overlay and start
## it from `intent`.
func show_color_screen(intent: ScenarioDecode.ColorScreenIntent) -> void:
	if _vm._color_screen == null:
		_vm._color_screen = _vm._make_color_screen()
	_vm._color_screen.start(intent)


## {2E} Background — get-or-create the VM's gradient ramp model.
func get_or_create_background() -> ScenarioBackground:
	if _vm._background == null:
		_vm._background = ScenarioBackground.new()
	return _vm._background


## Push the current gradient corners to the background quad (delegates to the VM,
## which owns the ScreenEffectOverlay handle so this verb stays scene-free).
func push_screen_background() -> void:
	_vm._apply_screen_background()


## {78} Display Conditions — lazily create the results/intro screen and run one
## mode on it. The first operand is a MODE (0 = READY!, 2..7 = the outro pipeline,
## >= 8 = the victory-condition banner for BONUS.BIN page mode-8), and `time` is the
## hold — which only modes 0 and >= 8 actually read.
func show_conditions(conditions: int, time: int) -> void:
	if _vm._results_screen == null:
		_vm._results_screen = _vm._make_results_screen()
	_vm._results_screen.run(conditions, time)


## {7D} Show Graphic — lazily create the fullscreen-graphic overlay and start it.
func show_graphic(intent: ScenarioDecode.ShowGraphicIntent) -> void:
	if _vm._show_graphic == null:
		_vm._show_graphic = _vm._make_show_graphic()
	_vm._show_graphic.start(intent)


## {91} Show Map Title — lazily create the map-title overlay and start it. The
## MAPTITLE slot is resolved from the VM's current map_id (context-selected, §3);
## an unknown map resolves to slot -1 → the timing runs but nothing renders.
func show_map_title(intent: ScenarioDecode.MapTitleIntent) -> void:
	if _vm._map_title == null:
		_vm._map_title = _vm._make_map_title()
	var slot := ScenarioMapTitle.slot_for_map(_vm.current_map_id)
	_vm._map_title.start(slot, intent.speed, intent.x, intent.y)


## Reveal — arm the fade-in-from-black ramp for `ticks` frames (VM state, ticked in
## `_tick_once`).
func arm_reveal(ticks: int) -> void:
	_vm._reveal_duration_ticks = ticks
	_vm._reveal_remaining_ticks = ticks


# --- Dialogue ({10} Display Message / Change Dialog) -----------------------
# The advance-gate scheduler state stays on the VM; these verbs are the box-pool /
# overlay access the apply layer needs, so the VM no longer pokes those internals
# across call sites (the review's Card 2 seam).

## Clear any active free-overlay text (a new Display Message replaces it).
func clear_dialogue_overlay() -> void:
	if _vm.dialogue_overlay != null and _vm.dialogue_overlay.has_method("clear"):
		_vm.dialogue_overlay.clear()


## Is a free-text overlay (Dialog 0x09) wired? (Absent in VM-only test contexts.)
func has_dialogue_overlay() -> bool:
	return _vm.dialogue_overlay != null


## Show the free overlay text at the authored placement (non-blocking). `dialog`
## is the raw Dialog byte — its low 2 bits carry valign (1=Top prayer, 3=Center
## narration), which the overlay needs to place + paginate faithfully.
func show_dialogue_overlay(tokens: Array, psx_x: int, psx_y: int, dialog: int = 0x09) -> void:
	_vm.dialogue_overlay.show_overlay(tokens, psx_x, psx_y, 0, dialog)


## Is `dialog` a boxed variant (0x1X/0x9X)? (Box-pool classification.)
func is_boxed_dialog(dialog: int) -> bool:
	return _vm.box_pool._is_boxed_dialog(dialog)


## Is the boxed-dialog renderer wired? (Absent in VM-only test contexts.)
func has_dialogue_box() -> bool:
	return _vm.box_pool.dialogue_box != null


## Render a boxed dialog and return the resulting foreground slot.
func show_dialogue_box(tokens: Array, dialog: int, speaker_uid: int, portrait_row: int,
		open_type: int, psx_x: int, psx_y: int, fine_x60: int) -> int:
	_vm.box_pool._show_dialog_box(tokens, dialog, speaker_uid, portrait_row, open_type,
		psx_x, psx_y, fine_x60)
	return _vm.box_pool._foreground_slot


## Resolve a Change Dialog Target to a live box slot: the target slot if it holds a
## box, else the current foreground slot.
func resolve_dialog_slot(target: int) -> int:
	return target if _vm.box_pool._box_at(target) != null else _vm.box_pool._foreground_slot


## Close the box at `slot` and drop its persist flag. Returns true iff it was the
## foreground box (also clearing the foreground slot) — the VM tears down the gate.
func close_dialog_slot(slot: int) -> bool:
	var box = _vm.box_pool._box_at(slot)
	if box != null and box.has_method("close"):
		box.close()
	_vm.box_pool._slot_persists.erase(slot)
	if slot == _vm.box_pool._foreground_slot:
		_vm.box_pool._foreground_slot = 0
		return true
	return false


## The baked message tokens for `msg` (empty when none).
func dialog_tokens_for(msg: int) -> Array:
	return _vm.box_pool._message_tokens.get(msg, [])


## Swap the box at `slot` to `toks` in place, promoting it to foreground. Returns
## false (no-op) when no box occupies the slot. `portrait_byte` is the {51} Portrait
## Column: when it re-picks a valid EVTFACE face (row active, byte in [1,8]) the
## portrait updates in place too; otherwise the current face is left untouched
## (col 0 / no active {50} row). §2.5 — the {50} row/VRAM strip persists across {51}.
func swap_dialog_text(slot: int, toks: Array, portrait_byte: int = 0) -> bool:
	var box = _vm.box_pool._box_at(slot)
	if box == null or not box.has_method("swap_text"):
		return false
	var evtface: Texture2D = null
	if portrait_byte > 0 and box.has_method("dialog_byte"):
		evtface = _vm.box_pool._resolve_evtface(box.dialog_byte(), portrait_byte)
	box.swap_text(toks, evtface)
	if slot >= 1:
		_vm.box_pool._foreground_slot = slot
	return true


# --- Field objects & EVTCHR ({58}/{55}/{54}) -------------------------------

## {58} Load EVTCHR — map an EVTCHR segment slot into a cinematic block.
func load_evtchr(block: int, slot: int) -> void:
	_vm._evtchr_block_to_slot[block] = slot
	# This is now the active cinematic EVTCHR context for subsequent Unit Anims.
	_vm._active_evtchr_block = block


## {55} Use Field Object — attempt the map texture-animation render (falling back to a
## modeled timer + warning when the map can't render it). Returns whether it rendered.
## The render + fallback state is VM/scene machinery; the {57} Wait barrier polls it.
func play_field_object(id: int, arg2: int) -> bool:
	return _vm._play_field_object_render(id, arg2)


## {54} Use 3D Object — latch object #ID to `state` as a modeled-timer record (the
## {56} Wait barrier polls it; the real render is Stage 2).
func play_3d_object(id: int, state: int) -> void:
	_vm._threed_objects[id] = {"ticks_left": _vm._FIELD_OBJ_DEFAULT_TICKS, "state": state}


# --- Sound ({21} Sound Effect / {60} Fade Sound / {22} Switch Track / {6B}/{6A}
# BG Sound). Thin wrappers over the audio autoloads (SfxRouter / MusicPlayer) so
# the SPU + music access sits behind the seam — a [FakeScenarioWorld] records the
# call instead of hitting real hardware. The {6B} ramp REGISTRY and {22} toggle
# stay VM-side scheduler state (ADR-0058 keeps ramp-tick/scheduler state on the
# VM); these verbs are the backend-call surface those handlers + the per-frame
# ramp tick drive. Unlike the other verbs they wrap globals, not `_vm`. ---------

## {21} Sound Effect — play a system SFX by catalog id.
func play_system_sound(sound_id: int) -> void:
	SfxRouter.play_system_by_id(sound_id)


## {6B} BG Sound — start an env-bank ambient (stacking != 0 = an overlay voice);
## returns the backend handle (0 = SPU miss / bad id).
func play_bg_sound(sound_id: int, stacking: int) -> int:
	return SfxRouter.play_bg(sound_id, stacking)


## Push a bg ambient's current ramp volume to its SPU voices — once at trigger and
## per-frame from the VM ramp tick.
func set_bg_sound_volume(handle: int, vol: int) -> void:
	SfxRouter.set_bg_volume(handle, vol)


## Stop a bg ambient's voices (a (re)start / rewind drops every live ambient so the
## replay re-triggers from PC 0 rather than layering a second copy).
func stop_bg_sound(handle: int) -> void:
	SfxRouter.stop_bg_handle(handle)


## {6A} Edit BG Sound — notify listeners a live ambient was re-ramped in place.
func notify_bg_sound_changed(kind: String, sound_id: int, stacking: int, handle: int) -> void:
	SfxRouter.bg_sound_changed.emit(kind, sound_id, stacking, handle)


## {7C} End Sound — stop every currently-playing event SFX/BGM voice (the PSX
## SUB_800440cc 8-voice teardown). Thin wrapper over SfxRouter.
func stop_all_event_sound() -> void:
	SfxRouter.stop_all_event_sound()


## {60} Fade Sound — fade the active music to silence over `ticks` sequencer ticks
## (a no-op if no music is playing).
func fade_music(ticks: int) -> void:
	MusicPlayer.fade_out(ticks)


## {22} Switch Track — cross-fade to `song_id` at `target_vol` over `ticks`.
func switch_music_track(song_id: int, target_vol: int, ticks: int) -> void:
	MusicPlayer.switch_track(song_id, target_vol, ticks)
