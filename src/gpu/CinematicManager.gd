class_name CinematicManager
extends RefCounted
## Owns the cinematic-spell lifecycle.
##
## Sibling of EffectManager / ProjectileManager — the third manager CombatLoop
## composes (ADR-0018 cluster). Drives:
##
##   - Edge detection on the GPU snapshot's per-unit `cinematic_timer` field
##     (issue #118: simultaneous cinematics each carry their own timer, so
##     the spotlight pick scans every unit instead of reading a single battle
##     header). ADR-0031: battle state is GPU-authoritative; the edge is a
##     snapshot diff, not a CPU latch.
##   - The cinematic EffectInstance lifecycle — spawn on -1 -> N edge via
##     EffectManager.spawn_cinematic_effect, teardown on N -> -1 edge.
##   - PlayerCamera takeover: request_takeover on camera_started, push the
##     EffectInstance.camera_controller's output per host frame via
##     apply_camera(), release_takeover on camera_finished.
##
## Emits per-event signals (cinematic_began / cinematic_ended) so CombatLoop
## composes side-effects (debug-probe routing, combat_visuals freeze refresh)
## without the manager reaching back into the loop for them.
##
## Spotlight pick under concurrent cinematics: the CPU side picks the
## lowest-unit_id caster with `cinematic_timer >= 0` and treats that single
## unit as "the" cinematic for camera + UI purposes. Other concurrent
## cinematics still run their GPU orchestrators (damage, MP, AoE stamps
## etc. all stay correct) but don't drive the camera until the primary
## tears down. Splitscreen / multi-cam is out of scope (#118 outcome).
##
## Cross-cutting: `combat_visuals` group freeze. CombatLoop owns
## `_refresh_combat_visuals_freeze()` and every axis that feeds it, and re-fires it
## on both signal edges. The manager does not touch the group itself; it just
## exposes `is_active()` and `active_caster_idx()` so the loop's predicate has the
## cinematic axis and its spotlight carve-out. See ADR-0037 dec. 7.

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude
const CameraCalibration = ExMateriaPlatform.CameraCalibration
const PsxChirality = ExMateriaPlatform.PsxChirality


# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


signal cinematic_began(caster_idx: int, target_idx: int)
signal cinematic_ended(prev_caster_idx: int)

const CinematicFacingResolverClass = ExMateriaEffects.CinematicFacingResolver

var _base  # CombatLoop (untyped: avoids the new-class-cache + preload-cycle issue)

# Caster/target Unit nodes for the live cinematic, stashed in _handle_began so
# _on_camera_started can inject them into the camera controller's facing
# resolver — camera_started fires DURING the spawn's initialize(), before
# EffectInstance.set_unit_targets() has run, so the effect's own WeakRefs aren't
# populated yet at that point.
var _pending_caster = null
var _pending_target = null

# Lazily built once a cinematic with a PlayerCamera runs (ADR-0039).
var _facing_resolver_inst = null

# Previous-tick spotlight caster (lowest unit_id with cinematic_timer >= 0),
# used to fire one-shot edge handlers on -1 -> N and N -> -1 transitions.
var _prev_caster_idx: int = -1

# Currently-playing cinematic spell EffectInstance. The one EffectInstance
# exempt from combat_visuals (ADR-0037) so its particles keep playing while
# the rest of the world is frozen. Cleared in _handle_ended.
var _active_effect = null


func _init(base) -> void:
	_base = base


## Lowest unit_id with `cinematic_timer >= 0` in the current snapshot, or -1
## if none. Issue #118: per-unit timer replaces the battle-scoped header pair
## so simultaneous casters can each drive their own orchestrator; the CPU side
## still wants ONE focused caster for camera + UI purposes, so pick
## deterministically by unit_id.
func _pick_spotlight_caster() -> int:
	# Reads the lean per-tick CINEMATIC_TIMER column (CombatLoop refreshes it every
	# tick without building the full _all_states snapshot — perf). Same values the
	# old `_all_states[i].cinematic_timer` read, just without the dict build.
	var timers: PackedInt32Array = _base._tick_cinematic_timer
	for i in range(timers.size()):
		if timers[i] >= 0:
			return i
	return -1


## True iff at least one unit is driving a cinematic orchestrator this tick.
## ADR-0031 read rule: snapshot, not CPU flag.
func is_active() -> bool:
	return _pick_spotlight_caster() != -1


## Index of the spotlight caster currently driving the cinematic, or -1 if
## none. Under concurrent cinematics (#118), the lowest unit_id with an
## active per-unit timer wins the camera focus.
func active_caster_idx() -> int:
	return _pick_spotlight_caster()


## Last-seen spotlight caster_idx (this tick OR the most recent if the
## cinematic just ended). The debug probe uses this to find the AoE target
## during the inter-cinematic gap where active_caster_idx() has already gone
## to -1.
func prev_caster_idx() -> int:
	return _prev_caster_idx


## Per-IRQ edge detection. Called from CombatLoop.tick() after the GPU
## snapshot refresh. Compares this tick's spotlight caster to the stored
## prior value and dispatches began/ended handlers on the transition.
func update_edge(tick: int) -> void:
	var current_idx: int = _pick_spotlight_caster()
	if current_idx == _prev_caster_idx:
		return
	if _prev_caster_idx == -1 and current_idx >= 0:
		if DebugConfig.iteration_debug_enabled:
			var name = _base.units[current_idx].name if current_idx < _base.units.size() else "?"
			print("[Tick %d] [CINEMATIC] BEGAN caster=%d (%s)" % [tick, current_idx, name])
		_handle_began(current_idx)
	elif _prev_caster_idx >= 0 and current_idx == -1:
		if DebugConfig.iteration_debug_enabled:
			print("[Tick %d] [CINEMATIC] ENDED prev_caster=%d" % [tick, _prev_caster_idx])
		_handle_ended()
	else:
		# Spotlight handoff: caster A's cinematic ended while caster B's still
		# runs. Tear down A's EffectInstance and spawn B's so the camera stays
		# with a live cinematic. Damage / MP / AoE stamps are GPU-driven and
		# unaffected either way. Splitscreen / multi-cam camera is out of
		# scope (#118).
		if DebugConfig.iteration_debug_enabled:
			print("[Tick %d] [CINEMATIC] HANDOFF prev=%d -> caster=%d" % [
				tick, _prev_caster_idx, current_idx])
		_handle_ended()
		_handle_began(current_idx)
	_prev_caster_idx = current_idx


## Spawn the cinematic spell EffectInstance for the caster's current ability
## and emit cinematic_began. The instance opts out of combat_visuals (ADR-0037
## dec. 7) so its particles keep playing while the rest of the world is frozen by
## the freeze refresh.
func _handle_began(caster_idx: int) -> void:
	if caster_idx < 0 or caster_idx >= _base.units.size():
		return
	var caster = _base.units[caster_idx]
	if not is_instance_valid(caster):
		return
	# This fires on a (rare) cinematic-begin edge mid-tick-loop, where _all_states
	# holds only lean columns / last frame's snapshot. It needs field-heavy state
	# (casting_ability_id / flags / cast_target …), so refresh the full snapshot on
	# demand — cheap because it's rare and served off the version cache.
	_base.refresh_all_states_now()
	var caster_state: Dictionary = _base._all_states[caster_idx] if caster_idx < _base._all_states.size() else {}
	var ability_id: int = caster_state.get("casting_ability_id", -1)
	var effect_id
	var target_idx: int

	if ability_id <= 0:
		# Issue #107 -- reraise cinematic. Stage A in stage_damage.glsl clears
		# U_CASTING_ABILITY_ID so the GPU dispatcher can route to its own
		# orchestrator; the CinematicManager has to recognize the shape here
		# because AbilityDatabase has no entry to consult. The marker is
		# FLAG_DEAD + STATUS_RERAISE on the caster; bail otherwise so the
		# old "stale ability id, drop the spawn" guard still fires.
		var flags: int = int(caster_state.get("flags", 0))
		var status_lo: int = int(caster_state.get("status_flags_lo", 0))
		var reraise_mask: int = 1 << StatusRegistry.bit(&"reraise")
		if (flags & 1) == 0 or (status_lo & reraise_mask) == 0:
			return
		effect_id = 5  # E005 -- Raise (#108). E007 is the status-sparkle
		# indicator and has no get-up pose cue; Raise's particle channel
		# flags drive the carrier visibly rising. See stage_spell.glsl.
		ability_id = 5  # Raise ability id -- used only by _rlog.log_effect downstream.
		target_idx = caster_idx
	else:
		var ability := AbilityDatabase.get_ability_view(ability_id)
		if ability.is_empty() or not ability.has_effect_file:
			return
		effect_id = ability.effect_id
		if effect_id == null or not (effect_id is int) or effect_id <= 0:
			return
		target_idx = caster_state.get("cast_target", -1)
		if target_idx < 0 or target_idx >= _base.units.size():
			return

	var target = _base.units[target_idx]
	if not is_instance_valid(target):
		return

	# Replace any stale instance defensively — back-to-back cinematics shouldn't
	# happen on the GPU side, but the spawn here is the only owner of this seat.
	if _active_effect and is_instance_valid(_active_effect):
		_active_effect.queue_free()

	# Stash the focused units BEFORE the spawn: spawn_cinematic_effect's
	# initialize() synchronously fires camera_started -> _on_camera_started,
	# which injects these into the facing resolver before the caster pre-pan.
	_pending_caster = caster
	_pending_target = target

	# Hand the spawn the camera-takeover callbacks so they're connected BEFORE
	# the EffectInstance's initialize() — that's where camera_started fires, and
	# connecting afterwards misses it entirely.
	var on_started := Callable(self, "_on_camera_started") if _base.player_camera else Callable()
	var on_finished := Callable(self, "_on_camera_finished") if _base.player_camera else Callable()
	_active_effect = _base.effect_manager.spawn_cinematic_effect(
		caster, target, ability_id, effect_id, on_started, on_finished)

	cinematic_began.emit(caster_idx, target_idx)


## Tear down the cinematic EffectInstance on the -> -1 edge. The instance's
## _exit_tree emits camera_finished, which our hook routes to PlayerCamera's
## release_takeover(), so no explicit camera restore is needed here.
func _handle_ended() -> void:
	var prev_caster_idx: int = _prev_caster_idx
	if _active_effect and is_instance_valid(_active_effect):
		_active_effect.queue_free()
	_active_effect = null
	cinematic_ended.emit(prev_caster_idx)


## Drive the PlayerCamera from the cinematic EffectInstance's camera controller.
## Called each host frame (outside the GPU pump gate) while the cinematic is
## live, so the camera advances at visual frame rate even though combat_active
## is effectively paused for the rest of the world.
func apply_camera() -> void:
	if not _base.player_camera:
		return
	if not _active_effect or not is_instance_valid(_active_effect):
		return
	var ctrl = _active_effect.camera_controller
	if not ctrl or not ctrl.is_active():
		return
	if _base.player_camera.camera_mode != _base.player_camera.CameraMode.TAKEOVER:
		return
	var pos = PsxChirality.psx_position_to_godot(ctrl.current_position)
	var rot = PsxChirality.psx_angles_to_godot_rotation(
		ctrl.current_angles.x, ctrl.current_angles.y, ctrl.current_angles.z)
	var ortho_size = CameraCalibration.zoom_to_ortho_size(ctrl.current_zoom)
	_base.player_camera.apply_takeover(pos, rot, ortho_size)


# === Camera bridge ============================================================
# The cinematic EffectInstance owns a CameraSubsystem whose current_position /
# angles / zoom advance per-effect-frame. We snapshot the saved PlayerCamera
# state at camera_started, then push the controller's output each tick via
# apply_camera() above — same shape as EffectViewerScene._on_effect_camera_started
# + _process apply.

func _on_camera_started(effect = null) -> void:
	if not _base.player_camera:
		return
	# EffectManager binds the EffectInstance into the callback because the spawn
	# call hasn't returned yet at this point — `_active_effect` is still the
	# prior value, so we read the live one from the bound argument.
	if effect == null:
		effect = _active_effect
	_base.player_camera.request_takeover(self)
	if DebugConfig.iteration_debug_enabled:
		print("[Tick %d] [CINEMATIC] camera_started -> request_takeover (player_pos=%s saved_rot=(%.1f,%.1f) saved_size=%.2f)" % [
			_base.current_tick, str(_base.player_camera.global_position),
			_base.player_camera._saved_x_rot, _base.player_camera._saved_y_rot,
			_base.player_camera._saved_camera_size])
	# Seed the camera controller's SLOT_COPY reference from the live PlayerCamera
	# state so opcodes that copy "current camera" resolve to the strategy view.
	if effect and is_instance_valid(effect) and effect.camera_controller:
		var ctrl = effect.camera_controller
		ctrl.saved_position = PsxChirality.godot_position_to_psx(_base.player_camera.global_position)
		ctrl.saved_angles = Vector3(
			PsxMagnitude.deg_to_angle(-_base.player_camera._saved_x_rot),
			PsxMagnitude.deg_to_angle(_base.player_camera._saved_y_rot + 360.0),
			0.0)
		ctrl.saved_zoom = CameraCalibration.ortho_size_to_zoom(_base.player_camera._saved_camera_size)
		ctrl.current_position = ctrl.saved_position
		ctrl.current_angles = ctrl.saved_angles
		ctrl.current_zoom = ctrl.saved_zoom
		if _base.map and _base.map.has_method("get") and _base.map.dynamic_geo_builder:
			var bounds: Rect2i = _base.map.dynamic_geo_builder.map_bounds
			ctrl.map_center = Vector3(float(bounds.size.x) * 14.0, 0.0, float(bounds.size.y) * 14.0)
		# Inject the facing resolver + focused units (ADR-0039) BEFORE arming the
		# pre-pan, so the caster pre-pan yaw is itself occlusion-resolved.
		if _facing_resolver_inst == null and _base.player_camera:
			_facing_resolver_inst = CinematicFacingResolverClass.new(_base.player_camera, _base.map)
		ctrl.facing_resolver = _facing_resolver_inst
		ctrl.caster_unit = _pending_caster
		ctrl.target_unit = _pending_target
		ctrl.cursor_unit = _pending_target   # no separate cursor unit in GPUArena
		# Arm the pre-phase-1 pan from the saved pose to the caster. Without
		# this, Fire / Cure / etc. would teleport the camera to their TARGET-source
		# first keyframe (target unit, not caster) on host frame 0 of the
		# cinematic — visually disorienting in GPUArena where the strategy-view
		# camera wasn't already on the active unit. See
		# research/wiki_articles/cinematic_camera_pre_pan_to_caster.txt.
		ctrl.arm_pre_phase_pan_to_caster()
		if DebugConfig.iteration_debug_enabled:
			print("  [CAMERA SEED] saved_pos=%s saved_angles=%s saved_zoom=%.1f target_pos=%s caster_pos=%s pre_pan=%d" % [
				str(ctrl.saved_position), str(ctrl.saved_angles), ctrl.saved_zoom,
				str(ctrl.target_position), str(ctrl.caster_position),
				ctrl.PRE_PAN_FRAMES])


func _on_camera_finished() -> void:
	if not _base.player_camera:
		return
	if _base.player_camera.camera_mode == _base.player_camera.CameraMode.TAKEOVER:
		_base.player_camera.release_takeover()
