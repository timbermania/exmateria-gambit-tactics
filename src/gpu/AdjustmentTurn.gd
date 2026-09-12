class_name AdjustmentTurn
extends RefCounted
## The ADJUSTMENT TURN — the contract that makes an open turn an EDITING window (#894, design §4).
##
## [TurnDirector] freezes the world and announces a taker; this is what the player may do with
## that freeze. Pure and scene-free, exactly as [DeploymentAssignment] is (ADR-0242): it holds no
## node, mounts nothing, and every question it answers is a function of a [Character], a
## [GPUBatchSimulator] and a taker index. The host wires it to the director's three signals; it
## never sees the director.
##
## === THE PRE-TURN IMAGE HAS TWO HALVES ======================================================
##
## ADR-0235's snapshot covers the GPU: the battle slice, the cooldowns, the gambit SSBO. That is
## the whole of the future *as the kernel sees it* — and it is only half of what an adjustment
## turn can change. The formation screen's Equip / Ability / Change-Job flows write straight
## through to the durable [Character] (ADR-0005: one representation, no writeback), which lives on
## the CPU and is in no SSBO. So [method TurnDirector.cancel] restores a GPU that has forgotten the
## edit while the Character still remembers it, and the two diverge silently and permanently.
##
## This class owns the second half: [method open] takes the CPU image, [method cancel] puts it
## back, [method commit] is the one place it crosses to the GPU. The halves are deliberately NOT
## merged into the director's snapshot — the director mounts on a bare [CombatLoop] with no host
## and no roster (ADR-0239), and a Character is a thing only a host has.
##
## === EDITS ARE MADE EAGERLY AND LAND LATE ===================================================
##
## The edit is applied to the Character the instant the player makes it, and reaches the GPU only
## at commit. That asymmetry is forced, not chosen: staging the edits would mean the Equip,
## Ability and Change-Job flows all writing into an overlay instead of the Character — a fork of
## the formation screen, which #894 forbids in as many words. Holding the undo instead of the redo
## costs one `to_dict()` per turn and touches none of them.
##
## === STEERABILITY IS NOT OWNERSHIP ==========================================================
##
## The formation screen already asks one question before it lights its action rows: is this
## selection OWNED (ADR-0137 — an enemy gets the same screen, read-only). A turn adds a second,
## transient term, and [method steerable] is the conjunction. Ownership is a property of the unit;
## steerability is a property of the MOMENT. Keeping them separate words is what stops "the enemy's
## screen is read-only" and "it is not your turn" from collapsing into one flag that is wrong for
## whichever case it was not written for.

const Character = ExMateriaCatalogue.Character
const GambitEncoder = preload("res://src/gpu/GambitEncoder.gd")

const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const Gambit = ExMateriaAlmanac.Gambit
const JobDatabase = ExMateriaAlmanac.JobDatabase


## The CPU-side pre-turn image of the taker, `Character.to_dict()`. Empty when no turn is open,
## which is also what makes [method cancel] a no-op outside one rather than an error.
var _image: Dictionary = {}
## Which unit index the image belongs to. `-1` when no turn is open. Deliberately paired with the
## image and cleared with it: an image without its index is a restore aimed at nobody.
var _taker: int = -1
## Whether anything opened the edit surface on this turn. The commit push is skipped when nothing
## did — see [method commit] for why that is an optimisation and not a correctness condition.
var _touched: bool = false


## Open the editing window on `taker`, whose durable state is `character`.
##
## Called from the host's `turn_opened` handler, and ONLY for a taker the player may steer: an
## enemy's turn opens no window, so the enemy's rollout driver (#897) can reconfigure at will
## without a stale player image sitting behind it.
##
## Takes the image BEFORE any edit, which is the same instant the director takes its GPU snapshot
## and for the same reason.
func open(taker: int, character) -> void:
	_taker = taker
	_touched = false
	_image = character.to_dict() if character != null else {}


## Is `unit` editable right now?
##
## `owned` is the formation screen's own answer (ADR-0137) and is passed in rather than recomputed:
## this class does not know what a battlefield [Unit] is, and the screen's answer is the one that
## must not be second-guessed. `deployment` is the phase where the whole squad is editable at once
## — no battle exists yet, so there is no GPU state for an edit to diverge from and no turn for it
## to belong to.
##
## Between turns the answer is NO for everybody. That is the design's central rule, not a
## restriction bolted onto it: a turn IS the reconfiguration, so being able to reconfigure while
## the world plays would make the turn order decorative.
func steerable(unit_index: int, owned: bool, deployment: bool) -> bool:
	if not owned:
		return false
	if deployment:
		return true
	return _taker >= 0 and unit_index == _taker


## The player touched the edit surface on this turn — the host calls this when the adjustment
## screen opens on the taker.
func touch() -> void:
	if _taker >= 0:
		_touched = true


func is_open() -> bool:
	return _taker >= 0


func taker() -> int:
	return _taker


func was_touched() -> bool:
	return _touched


## Land this turn's edits on the GPU and close the window. Called from the host's `turn_committed`
## handler, which the director emits AFTER `consume_turn` and BEFORE it drains into the next turn —
## and the drain recomputes its ready list precisely so a `reconfigure_unit` landing here is seen
## (ADR-0239, `TurnDirector.commit`).
##
## TWO writes, because the state is in two buffers. `reconfigure_unit_from` moves job / equipment /
## ability slots through `UNIT_CONFIG_SCHEMA`'s recompute/clamp/carry column (ADR-0235); the gambit
## list is not in the unit block at all but in its own SSBO, so it goes separately through
## `set_unit_gambits`. Omitting either half would land half an edit.
##
## `lead` is the taker's IMPERATIVE if it issued one this turn ([ImperativeGambits], #1006) — an
## entry that is in no slot of the unit's list and is encoded ahead of all four. It is a parameter
## and not a third write: an imperative is a gambit-list edit, so it lands through the SAME second
## buffer, and a host that pushed it separately would write that buffer twice per commit with only
## the ordering of the two calls deciding which order the kernel actually reads.
##
## Skipped entirely when the surface was never opened. That is a COST saving and not a correctness
## condition — ADR-0235's no-op identity arm proves an unedited reconfigure is a bit-exact no-op —
## so a host that calls this unconditionally is still correct, just slower.
func commit(sim, battle_id: int, unit, lead = null) -> bool:
	var spent := _taker
	_taker = -1
	_image = {}
	if spent < 0 or not _touched:
		_touched = false
		return false
	_touched = false
	if sim == null or unit == null:
		return false
	var ok: bool = sim.reconfigure_unit_from(battle_id, spent, unit)
	# No log label, and none is reachable: `encode_for_unit` is the unlabelled half of the pair.
	# `encode_for_units` warns per unit with an empty list, and #892 measured that every
	# scenario-booted unit starts with one — a labelled call here would push a warning on every
	# committed turn of every battle for a condition that is normal.
	sim.set_unit_gambits(battle_id, spent, GambitEncoder.encode_for_unit(unit, lead))
	return ok


## Throw this turn's edits away, restoring the Character to its pre-turn image.
##
## The GPU half is the director's ([method TurnDirector.cancel] restores the battle slice); this is
## the CPU half, and the host runs it on `turn_cancelled`, which the director emits BEFORE it
## re-opens the same turn. So the re-opened turn's fresh image is taken from a restored Character,
## and cancelling twice in a row is idempotent rather than cumulative.
##
## Restores IN PLACE. `Character.from_dict` mints a new instance, and the roster, the catalogue's
## owned overlay and the battlefield [Unit] all hold the OLD reference — swapping the object would
## leave three holders pointing at the pre-cancel edit. [method Character.restore_mutable_from]
## replaces the mutable composition (`progression`, `gambits`) on the instance every holder
## already has.
func cancel(character) -> bool:
	var had := _taker >= 0 and not _image.is_empty()
	_taker = -1
	_touched = false
	var image := _image
	_image = {}
	if not had or character == null:
		return false
	character.restore_mutable_from(image)
	return true


## Drop the gambit slots the unit can no longer perform, and SAY which — design §4's rule for a job
## change, applied to whatever the unit's job and sub-job are right now.
##
## Returns the pruned [Gambit] rows, so the caller can show them. The list is the report; an empty
## return means nothing was pruned and there is nothing to say.
##
## Prunes rather than refuses or no-ops, in that order of preference and for stated reasons:
## refusing makes the UI argue with the player over a job change it has no business vetoing, and a
## silent no-op slot is worse than either — a gambit list that LOOKS armed and is not is the most
## confusing failure this design can produce.
##
## Only `ABILITY` rows can go stale. ATTACK, MOVE and WAIT are job-independent verbs every unit
## always has, so a prune that touched them would be deleting the player's work over nothing.
static func prune_unusable_gambits(character) -> Array:
	if character == null or character.gambits == null:
		return []
	var usable := usable_ability_ids(character)
	var pruned: Array = []
	var kept: Array[Gambit] = []
	for g in character.gambits.gambits:
		if g != null and g.action_kind == Gambit.ActionKind.ABILITY \
				and g.ability_id >= 0 and not usable.has(g.ability_id):
			pruned.append(g)
			continue
		kept.append(g)
	if pruned.is_empty():
		return []
	character.gambits.gambits = kept
	character.gambits.ensure_fixed_size()
	return pruned


## Every action-ability id this character can currently perform: its job's skillset plus its
## sub-job's, which is the ROM's own model of where a unit's action abilities come from
## (`AbilityLoadout` — slot 0 is the job-fixed primary skillset, slot 1 the secondary job whose
## skillset is equipped).
##
## Deliberately NOT filtered by `learned_abilities`. A gambit naming an unlearned ability of a job
## you are still in is a slot the player is working toward, and deleting it on an unrelated equip
## change would be the silent-destruction failure this whole function exists to avoid. The question
## here is "can this JOB do it", not "can it do it yet".
static func usable_ability_ids(character) -> Dictionary:
	var out: Dictionary = {}
	if character == null or character.progression == null:
		return out
	for job_id in [character.progression.current_job_id, character.progression.sub_job_id]:
		for ability_id in _skillset_actions(job_id):
			out[int(ability_id)] = true
	return out


static func _skillset_actions(job_id: String) -> Array:
	if job_id == null or job_id.is_empty():
		return []
	var job = JobDatabase.get_job(job_id)
	if job == null or job.is_empty():
		return []
	var skill_set = AbilityDatabase.get_skill_set(int(job.get("skill_set_id", 0)))
	if skill_set == null or skill_set.is_empty():
		return []
	return skill_set.get("actions", [])
