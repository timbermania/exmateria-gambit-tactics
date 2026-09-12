class_name ScenarioPathApplier
extends RefCounted

## The scene-side executor for a [Path] plan produced by [ScenarioPath].
##
## The world has already been booted ONCE from the group root (map + ENTD + music
## live, units spawned) by the time this runs. Per plan step it: verifies the step's
## [ForcedDirectorState] isolates the intended member against the [ScenarioDirector]
## (logging any first-match-wins preemption instead of lying), loads that member's
## event-script chunk onto the SAME live world, and `start()`s the VM. Intermediate
## members are run to end-of-script (combat between them is skipped — ADR-0054); the
## final target member is left playing.
##
## Faithfulness note: each member `start(fresh=false)` reruns the VM's per-scenario
## execution resets (event-var clear, {22} track toggle, dialog/context state) but
## PRESERVES the persistent scene overlays (weather, ambient BG sound, dark screen,
## background) that an earlier member armed — the ROM keeps that in map-state across
## scenario boundaries within a group, so tearing it down here dropped the rain on a
## 4→6 walk. The members' opcode streams concatenate on one persistent world exactly
## as the ROM would replay them, without byte-fusing the chunks (which would corrupt
## PC-indexed jumps).

## Safety cap: max host frames to wait for an intermediate member's fast-forward to
## finish before advancing anyway (the VM's own fast-play frame cap already bounds
## it; this is a belt-and-braces guard against a stuck `_ff_active`). ~35 s at 60fps.
const _MAX_FF_FRAMES := 2100

## Speed multiplier for fast-forwarding intermediate members — their opcode stream
## is replayed on the shared world along the real trajectory, just fast, so member
## side effects (Sprite Move, Warp, facing) land before the next member's chunk.
const _FF_SPEED := 30.0

## Host frames the main PC may sit unchanged before we treat the intermediate member
## as stalled on its combat barrier (a path never fights) and proceed. ~2.5 s at
## 60fps = ~75 s of scaled scenario time at _FF_SPEED — well past any real cutscene
## wait, short enough that the walk doesn't idle for the VM's full frame cap.
const _STALL_FRAMES := 150

## How the last fast-forward ENDED, and how many host frames it spent getting there.
##
## `_MAX_FF_FRAMES` is a SILENT cap: when it runs out the member is left wherever it got
## to, and for a battle opener "wherever it got to" is an earlier `{19}` — a camera pose
## that looks authored because it IS authored, just not the one the battle opens on
## (ADR-0264). A caller that cannot tell CAPPED from ENDED cannot report that, and the
## margin cannot be measured. `tools/sweep_opener_fast_forward.gd` reads both across all
## 72 battle openers; [method NavigatorMain._settle_world_via_opener] reads the outcome to
## fail loud on the live seek.
enum FfOutcome {
	NONE,     ## no fast-forward has run on this applier
	ENDED,    ## the member's main context reached Event End — the settled case
	STALLED,  ## no PC progress for `_STALL_FRAMES` (parked on a combat barrier a path never fights)
	CAPPED,   ## `_MAX_FF_FRAMES` ran out with the member still playing
}
var last_ff_outcome: int = FfOutcome.NONE
var last_ff_frames: int = 0

var _vm: Node
var _tree: SceneTree
var _load_member: Callable  # func(scenario_id: int) -> bool

## `vm` is the live ScenarioVM; `load_member` loads one member's chunk onto it
## (returns false on failure); `tree` drives the per-frame idle await.
func _init(vm: Node, load_member: Callable, tree: SceneTree) -> void:
	_vm = vm
	_load_member = load_member
	_tree = tree


## Walk `plan` (from [method ScenarioPath.plan]) against `bc_id`. Awaits — the caller
## should `await applier.walk(...)`. Returns true if every step loaded; false if a
## chunk failed to load (the walk stops there).
##
## `final_rewind_pc >= 0` turns the walk into a rewind-from-root: intermediate members
## still fast-forward to end, but the FINAL (target) member is rewound to that PC and
## left paused (instead of played through), so the user lands on the clicked
## instruction with the whole group's world already built up beneath it.
func walk(plan: Array, bc_id: int, final_rewind_pc: int = -1) -> bool:
	if plan.is_empty():
		push_warning("[ScenarioPathApplier] empty plan — nothing to walk (target is the group root?)")
		return true
	# Event-toggle disables (F3 panel) are keyed by PC into the TARGET member's chunk;
	# the same PC indices mean different opcodes in the intermediate members, so hold
	# them aside and re-arm only for the final member.
	var final_disabled: Dictionary = {}
	if "disabled_pcs" in _vm:
		final_disabled = _vm.disabled_pcs.duplicate()
		_vm.disabled_pcs = {}
	for i in plan.size():
		var step: Dictionary = plan[i]
		var member := int(step["member_scenario_id"])
		var forced: ScenarioDirectorState = step["forced_state"]
		var verified := bool(step.get("verified", false))
		var actual := int(step.get("actual", ScenarioDirector.NONE))

		var guard := "-"
		if forced is ForcedDirectorState:
			guard = (forced as ForcedDirectorState).describe()

		if verified:
			print("[ScenarioPath] step %d/%d → member %d  (director→%d)  forced: %s" %
				[i + 1, plan.size(), member, actual, guard])
		else:
			# First-match-wins preempted this member — report, don't lie. Play it
			# anyway so the debug walk still lands somewhere useful, but the log makes
			# clear the state does not isolate the intended member.
			push_warning("[ScenarioPath] step %d/%d CANNOT isolate member %d — edge %d preempts (forced: %s); playing member anyway" %
				[i + 1, plan.size(), member, int(step.get("preempted_by", actual)), guard])

		if not _load_member.call(member):
			push_error("[ScenarioPathApplier] failed to load member %d chunk; stopping walk" % member)
			return false
		# A prior intermediate fast-play leaves the VM paused at end-of-script; clear
		# it so this member actually advances.
		_vm.paused = false
		var is_final := i == plan.size() - 1
		# Re-arm the target member's event-toggle disables only for the final member.
		if is_final and "disabled_pcs" in _vm:
			_vm.disabled_pcs = final_disabled
		# `fresh=false`: this member concatenates onto the persistent world the earlier
		# members built, so the VM must KEEP the live scene overlays (weather, ambient
		# BG sound, dark screen, background) that a prior member armed instead of tearing
		# them down — the ROM carries that map-state across scenario boundaries within a
		# group. Per-scenario execution state (contexts, dialog, unit cutscene state,
		# track toggle, vars) still resets inside `start()`.
		_vm.start(false)

		if not is_final:
			# Intermediate member: fast-forward its whole opcode stream to end so its
			# world side effects (moves, warps, facing, latches) land before the next
			# member's chunk loads — then advance. The VM's fast-play frame cap bounds
			# this even if a wait never resolves (combat is skipped).
			await _fast_forward_to_end(member)
		elif final_rewind_pc >= 0:
			# Final (target) member with a pending rewind: replay its own chunk from
			# PC 0 up to the clicked instruction, then pause — same trajectory as a
			# single-chunk rewind, but now sitting on the world the earlier members
			# built up. The fast-play drives itself through `_process`.
			print("[ScenarioPathApplier] target member %d → rewind to pc=%d" % [member, final_rewind_pc])
			_vm.set_rewind_target(final_rewind_pc)
		# else: final target member with no rewind — left playing at normal speed.
	return true


## Fast-forward ONE member's whole opcode stream onto the live (already-booted) world
## to end-of-script, then park it. Unlike walk()'s FINAL member (left playing at normal
## speed), this member is fully replayed so ALL its world side effects settle — camera
## framing, committed palette/color, the {Reveal} fade, moves/facing. Used by the
## navigator to settle a battle world via its opener cinematic on a direct combat SEEK
## (the seek skips the opener's normal-speed playback). Awaits; the caller should
## `await`. Returns false if the member chunk fails to load.
func fast_forward_member(member: int) -> bool:
	if not _load_member.call(member):
		push_error("[ScenarioPathApplier] failed to load member %d chunk for fast-forward" % member)
		return false
	# `fresh=false`: preserve any persistent scene overlays already armed (weather,
	# ambient BG, dark screen) — same map-state-carries rule walk() relies on.
	_vm.paused = false
	_vm.start(false)
	await _fast_forward_to_end(member)
	return true


# Fast-forward the currently-loaded (intermediate) member to end-of-script via the
# VM's high-speed replay, then return once it settles. Belt-and-braces frame cap in
# case `_ff_active` never clears.
func _fast_forward_to_end(member: int) -> void:
	_vm.rewind_speed = maxf(_vm.rewind_speed, _FF_SPEED)
	_vm.step(_vm.get_instructions().size())  # step() clamps the target to end-of-chunk
	var frames := 0
	var last_pc: int = _vm.get_pc()
	var stalled := 0
	last_ff_outcome = FfOutcome.NONE
	last_ff_frames = 0
	while frames < _MAX_FF_FRAMES:
		if not _vm.has_method("is_fast_playing") or not _vm.is_fast_playing():
			last_ff_outcome = FfOutcome.ENDED
			last_ff_frames = frames
			return  # reached end-of-script (main context finished)
		# The chunk can FINISH without the fast-play noticing: `_ff_active` clears when the
		# PC reaches the fast-play target, and a chunk whose `Event End` is not its last
		# instruction never gets there. Ask the VM the question the normal-speed walk asks
		# — has the main context ended? — and stop when the answer is yes, instead of
		# spinning out the stall budget on a scenario that is already over.
		if _vm.has_method("is_main_context_finished") and _vm.is_main_context_finished():
			last_ff_outcome = FfOutcome.ENDED
			last_ff_frames = frames
			_vm.cancel_fast_play()
			return
		await _tree.process_frame
		frames += 1
		var pc: int = _vm.get_pc()
		if pc != last_pc:
			last_pc = pc
			stalled = 0
		else:
			stalled += 1
			if stalled >= _STALL_FRAMES:
				# No PC progress → member is parked on the combat barrier a path never
				# fights. Its side effects up to here have applied; cancel and proceed.
				print("[ScenarioPathApplier] member %d fast-forward parked at pc=%d (combat-gated) — proceeding" %
					[member, pc])
				last_ff_outcome = FfOutcome.STALLED
				last_ff_frames = frames
				_vm.cancel_fast_play()
				return
	push_warning("[ScenarioPathApplier] member %d fast-forward did not settle within %d frames — advancing anyway" %
		[member, _MAX_FF_FRAMES])
	last_ff_outcome = FfOutcome.CAPPED
	last_ff_frames = frames
	_vm.cancel_fast_play()
