class_name ImperativeGambits
extends RefCounted
## IMPERATIVE GAMBITS — the one-shot, top-priority order a player issues on their own turn
## (#1006, design §5), its finite charges, its watchdog, and the refund a cancel owes it.
##
## Pure and scene-free, exactly as [AdjustmentTurn] and [DeploymentAssignment] are (ADR-0252,
## ADR-0242): it holds no node, mounts nothing, reads no simulator, and every question it answers
## is a function of a unit index, a tick and a [Gambit]. The host wires it to the director's three
## signals beside the adjustment turn, and to [signal CombatLoop.action_committed]; it never sees
## the director, the loop or the GPU.
##
## === AN IMPERATIVE IS NOT A SLOT ============================================================
##
## A [GambitList] has four fixed slots (`ensure_fixed_size`), and an imperative occupies none of
## them: it is a LEAD entry encoded ahead of the standing list, so the shader — which walks slots
## ascending and takes the first match (`evaluate_gambits_up_to`) — reaches it before every rule
## the unit already had. The buffer has exactly the room for it and no more:
## `MAX_USER_GAMBITS` is 5 against `GambitList.VISIBLE_SLOTS` of 4, with ADR-0048's safety net
## after both. So "above the standing list" costs no slot, no buffer growth and no shader change.
##
## === THE CHARGES ARE BATTLE STATE, AND THAT IS WHY THEY ARE HERE =============================
##
## Charges are per unit PER BATTLE. The durable [Character] is the wrong home for them twice over:
## it is persisted (ADR-0005), so a lock-on issued at Gariland would still be armed in the next
## battle, and it is what the adjustment turn's image already restores — a charge inside it would
## be refunded by the Character restore rather than by a rule anyone wrote. They live here, on the
## CPU, beside the battle rather than inside the roster.
##
## === THE REFUND IS A THIRD HALF OF THE PRE-TURN IMAGE ========================================
##
## ADR-0252 dec. 1 splits the pre-turn image in two — the director's GPU snapshot and the
## [AdjustmentTurn]'s `Character.to_dict()`. Neither covers a charge, because a charge is in no
## SSBO and on no Character. Design §4 requires that "cancel must refund any imperative charge
## spent that turn, or cancel becomes a trap", so this class holds the third half: [method open]
## remembers what stood before the turn, [method cancel] puts it back, [method close] lets it
## stand. Its edges are the SAME three the adjustment turn is wired to, and for the same reason.
##
## === THE WATCHDOG CANNOT DISAGREE WITH ANYTHING ==============================================
##
## Design §5 rules out a cleverer removal predicate in as many words: reachability, LOS and
## affordability all duplicate shader logic on the CPU, and the two copies will disagree. So an
## unconsumed imperative is removed by exactly two things — a deadline in TICKS, and the target
## pool going empty, which is the design's "target dead/removed" under the one constraint the GPU
## imposes on it (see [method expire]). Neither is a re-derivation of anything the kernel decides.

const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector

# --- Tunables (ADR-0068) -----------------------------------------------------

const CHARGES_SLUG := "gambit.imperative_charges"

## How many imperatives one unit may issue in one battle. A `static var` home and not a `const`,
## because a `const` is frozen at parse time and a scrub could never reach its readers (ADR-0068
## dec. 13) — and design §5 names this value's own successor: "from a `Tune` constant now,
## job-derived later", which is map #886's standing refinement and not this ticket.
##
## Two, because the charge IS the scarcity. Design §5 makes the imperative deliberately
## independent of the turn's gambit edit — "double-taxing makes the imperative feel bad to use at
## all" — so this number is the only thing standing between a lock-on and a universal remote.
static var charges_per_battle: int = 2
const CHARGES_HINT := {"min": 0, "max": 9, "step": 1}

const WATCHDOG_SLUG := "gambit.imperative_watchdog_ticks"

## How many world TICKS an unconsumed imperative may stand before the watchdog takes it.
##
## Counted in ticks and not in turns, because ticks are the only clock that runs while the
## imperative is exposed: the world is FROZEN for the whole of a turn (ADR-0239), so a deadline in
## turns would be a deadline in frozen time.
##
## Priced in ABILITY COOLDOWNS, and deliberately not in turns. An imperative is spent by an
## ACTION — `CombatLoop.action_committed`, which a move does not raise (ADR-0259 dec. 10) — so the
## clock this deadline races is the action cycle, not the meter. All 512 rows of `effects.json`
## carry `cooldown_ticks` 300, which is what makes it the one non-arbitrary unit of measure here
## (ADR-0260 dec. 2). Two of them is 600: long enough that the unit gets two whole chances to
## spend the order, and — since ADR-0260's dwell is also two cooldowns — it lapses exactly when
## the player next gets to re-issue it, so an unconsumed order never outlives the turn that could
## have replaced it. Short enough that a forgotten one does not stand for the battle: Gariland
## runs ~1,750 ticks, about three dwells.
##
## It was 120, derived from the meter back when `TURN_METER_FULL` was 100 ("about eight of a
## Speed-7 unit's own turns"). ADR-0260 widened the meter to 3600 and that derivation inverted:
## 120 ticks is a FIFTH of one turn and less than half of one cooldown, so an order would
## routinely expire before its unit could act on it even once — and expiry does not refund
## (ADR-0259 dec. 11), so the charge would be spent on nothing.
static var watchdog_ticks: int = 600
const WATCHDOG_HINT := {"min": 15, "max": 1200, "step": 15}


static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## This owner's named registration entry point (ADR-0173): `_static_init` calls it at class load —
## the only thing that does — and the guards call it to read back which slugs this owner binds.
static func register_tunables() -> void:
	Tune.bind(CHARGES_SLUG, charges_per_battle, CHARGES_HINT)
	Tune.bind(WATCHDOG_SLUG, watchdog_ticks, WATCHDOG_HINT)


# --- State -------------------------------------------------------------------

## unit index -> charges remaining this battle. Absent means "never asked", which
## [method charges_left] reads as a full allowance rather than as zero — a unit the player has not
## touched has spent nothing.
var _charges: Dictionary = {}
## unit index -> the standing [Gambit], for the at most one imperative a unit may have armed.
var _entries: Dictionary = {}
## unit index -> the tick the watchdog takes it at.
var _deadline: Dictionary = {}

## The unit whose turn is open, or -1. Paired with the three fields below and cleared with them:
## a refund aimed at nobody is a charge minted from nothing.
var _turn_unit: int = -1
## Charges spent SINCE [method open]. The refund is this many, not one — a player who re-aimed
## twice in one turn spent twice, and a cancel owes both back.
var _turn_spent: int = 0
## What stood before the turn opened: the entry (or null) and its deadline. Restored by
## [method cancel] so a cancel that follows a re-aim puts the OLD order back rather than simply
## clearing the new one.
var _turn_prior_entry = null
var _turn_prior_deadline: int = 0


# --- Reads -------------------------------------------------------------------

## Charges `unit_index` has left this battle. A unit that has never issued one has the full
## allowance; the allowance is re-read from the tunable every time, so an F3 scrub reaches a
## battle already in progress.
func charges_left(unit_index: int) -> int:
	if not _charges.has(unit_index):
		return allowance()
	return int(_charges[unit_index])


## The per-battle allowance as it stands right now. A PULL-read (ADR-0068 R5) rather than the
## static var, so an F3 scrub reaches a battle already in progress; the slug is bound by
## [method register_tunables] at class load, which is what makes the read legal.
func allowance() -> int:
	return int(Tune.get_value(CHARGES_SLUG))


## The standing imperative for `unit_index`, or null. This is the LEAD entry the encoder puts
## ahead of the unit's four slots.
func entry_for(unit_index: int):
	return _entries.get(unit_index)


func is_armed(unit_index: int) -> bool:
	return _entries.has(unit_index) and _entries[unit_index] != null


## May `unit_index` issue one right now? Charges only — WHOSE turn it is is the adjustment turn's
## question (`steerable`), already asked by the screen that offers the row, and answering it twice
## is two answers that can only differ by one being wrong (ADR-0255 dec. 11's rule, applied here).
func can_issue(unit_index: int) -> bool:
	return charges_left(unit_index) > 0


## Every unit with an imperative standing. Ordered by unit index so a host's re-push loop is
## deterministic rather than Dictionary-ordered.
func armed_units() -> Array:
	var out: Array = []
	for k in _entries.keys():
		if _entries[k] != null:
			out.append(int(k))
	out.sort()
	return out


## Nothing is armed anywhere. The host's per-frame sweep early-outs on this, which is the common
## case for the whole of every battle nobody issues an order in.
func idle() -> bool:
	return _entries.is_empty()


# --- Writes ------------------------------------------------------------------

## Issue `gambit` as `unit_index`'s imperative, spending one charge. Returns false and changes
## nothing when the unit has none left.
##
## Issuing while one already stands REPLACES it and spends another charge. Re-aiming is a new
## order, and the design prices an order at a charge; the free re-aim would make the first issue
## a draft rather than a decision. Within the turn it was spent on, the cancel refunds both.
##
## The gambit is stored by reference and the caller must not keep editing it — the surface hands
## over a copy for exactly this reason.
func issue(unit_index: int, gambit, now_tick: int) -> bool:
	if gambit == null or unit_index < 0:
		return false
	var left := charges_left(unit_index)
	if left <= 0:
		return false
	_charges[unit_index] = left - 1
	_entries[unit_index] = gambit
	_deadline[unit_index] = now_tick + deadline_span()
	if unit_index == _turn_unit:
		_turn_spent += 1
	return true


## The watchdog span as it stands right now — the same pull-read, for the same reason.
func deadline_span() -> int:
	return int(Tune.get_value(WATCHDOG_SLUG))


## Take `unit_index`'s imperative away without refunding it. Returns true when there was one.
##
## This is BOTH removal edges: the unit committed an action (design §5's "removed host-side on the
## existing `action_committed` signal") and the watchdog. Neither refunds — design §5 is explicit
## that a wasted lock-on is a real mistake, and a watchdog that gave the charge back would make
## issuing one free.
func withdraw(unit_index: int) -> bool:
	if not _entries.has(unit_index):
		return false
	_entries.erase(unit_index)
	_deadline.erase(unit_index)
	return true


## Remove every imperative that has become uncompletable, and say which. The host re-pushes each
## returned unit's gambit buffer without its lead entry.
##
## TWO tests and deliberately no third:
##
## 1. THE DEADLINE. `now_tick` has passed the span [method issue] stamped. A clock cannot disagree
##    with the kernel about anything.
## 2. THE POOL IS EMPTY — design §5's "target dead/removed". `pool_alive` is the HOST's answer
##    (`func(unit_index: int, entry) -> bool`), because whether a living enemy remains is a fact
##    about the battlefield and this class holds no battlefield.
##
## The pool, and not a named unit, because the GPU cannot express a named one:
## `TargetSelector.PoolType.SPECIFIC_UNITS` is in `GambitEncoder.UNSUPPORTED_POOL_TYPES`, so an
## imperative that claimed to lock onto Unit 7 would encode as something else and the screen would
## be lying about what it armed. A lock-on here locks onto a RULE ("the weakest foe"), and
## "target dead/removed" is that rule's pool running out.
##
## What is NOT tested is everything design §5 rules out: reachability, line of sight and
## affordability are all shader decisions, and a CPU copy of one is a second opinion that will
## eventually disagree with the kernel that actually acts.
func expire(now_tick: int, pool_alive: Callable) -> Array:
	var taken: Array = []
	for unit_index in armed_units():
		var entry = _entries[unit_index]
		var dead_pool := pool_alive.is_valid() and not bool(pool_alive.call(unit_index, entry))
		var timed_out: bool = now_tick >= int(_deadline.get(unit_index, 0))
		if dead_pool or timed_out:
			withdraw(unit_index)
			taken.append(unit_index)
	return taken


# --- The turn's three edges --------------------------------------------------

## A turn opened on `unit_index` — remember what stood, so a cancel can put it back.
##
## Called from the host's `turn_opened` handler and ONLY for a taker the player may steer, exactly
## as [method AdjustmentTurn.open] is: an enemy's turn opens no window, so nothing it does can be
## cancelled and nothing needs remembering.
func open(unit_index: int) -> void:
	_turn_unit = unit_index
	_turn_spent = 0
	_turn_prior_entry = _entries.get(unit_index)
	_turn_prior_deadline = int(_deadline.get(unit_index, 0))


## The turn was spent — let this turn's order stand and close the window. Returns whether anything
## was issued on it, which is what tells the host the gambit buffer needs the lead entry.
func close() -> bool:
	var issued := _turn_spent > 0
	_turn_unit = -1
	_turn_spent = 0
	_turn_prior_entry = null
	_turn_prior_deadline = 0
	return issued


## The turn's edits were thrown away — refund every charge spent on it and put back whatever order
## stood before it opened. Returns the number of charges refunded.
##
## Runs on `turn_cancelled`, which the director emits BEFORE it re-opens the same turn (ADR-0239),
## so the re-opened turn's fresh image is taken from a restored ledger and cancelling twice in a
## row is idempotent rather than cumulative — the same ordering [method AdjustmentTurn.cancel]
## rests on, for the same reason.
func cancel() -> int:
	var unit_index := _turn_unit
	var spent := _turn_spent
	var prior = _turn_prior_entry
	var prior_deadline := _turn_prior_deadline
	_turn_unit = -1
	_turn_spent = 0
	_turn_prior_entry = null
	_turn_prior_deadline = 0
	if unit_index < 0:
		return 0
	if spent > 0:
		_charges[unit_index] = charges_left(unit_index) + spent
	if prior != null:
		_entries[unit_index] = prior
		_deadline[unit_index] = prior_deadline
	else:
		_entries.erase(unit_index)
		_deadline.erase(unit_index)
	return spent


## Forget everything — a new battle's ledger. Charges are PER BATTLE, so a host that reused this
## object across two battles without calling it would carry the first battle's spending into the
## second.
func reset() -> void:
	_charges.clear()
	_entries.clear()
	_deadline.clear()
	_turn_unit = -1
	_turn_spent = 0
	_turn_prior_entry = null
	_turn_prior_deadline = 0


# --- The default order -------------------------------------------------------

## The order the surface opens on: attack the nearest foe, unconditionally.
##
## Built through the domain's own constructors and never as a raw enum triple (ADR-0255 dec. 3),
## and chosen so the very first press is issuable: a default the player must edit before it means
## anything would make the charge feel like it bought a form.
static func default_order():
	return Gambit.create(
		TargetSelector.enemies().with_resolution(TargetSelector.ResolutionStrategy.NEAREST_FIRST),
		[GambitCondition.always()],
		Gambit.ActionKind.ATTACK,
		-1,
		TargetSelector.triggering(),
	)


## A deep-enough copy of `gambit` for the ledger to own: the surface keeps editing its draft after
## an issue, and a stored reference would let a later edit rewrite an order already spent for.
static func copy_of(gambit):
	if gambit == null:
		return null
	return Gambit.from_dict(gambit.to_dict())
