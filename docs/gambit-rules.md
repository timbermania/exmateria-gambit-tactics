# Gambit Behavior Rules

The behavioral spec for the gambit system. Each rule is testable via the
gambit scenario suite (`tests/gambit_scenarios/`, run by
`tests/GambitScenarioRunnerTest.tscn`). Scenarios reference rules by id
(e.g. `rule: "B6"`); rules reference scenarios by name.

This doc is the **source of truth** for what gambits are supposed to do.
The shader is supposed to match it; when it doesn't, the scenario goes
`XFAIL` until the shader is fixed. **Locking in current behavior is
not the goal** — every rule is what the system *should* do, not what it
happens to do today.

## Architecture quick links

- Domain: [`Gambit`](../addons/exmateria_almanac/gambits/Gambit.gd), [`GambitCondition`](../addons/exmateria_almanac/gambits/GambitCondition.gd), [`TargetSelector`](../addons/exmateria_almanac/gambits/TargetSelector.gd)
- CPU encoder (faithful-or-explicit): [`GambitEncoder`](../src/gpu/GambitEncoder.gd) — ADR-0023
- GPU evaluation: `evaluate_gambits_up_to` in [`stage_compute.glsl`](../src/gpu/shaders/stage_compute.glsl)
- Action execution: [`stage_attack.glsl`](../src/gpu/shaders/stage_attack.glsl), [`stage_spell.glsl`](../src/gpu/shaders/stage_spell.glsl), `stage_pathfind.glsl`
- Existing pure encoder tests: `GambitEncoderTest`, `GambitEncodeSchemaTest`

## Rule index

### A. Slot evaluation order

- **A1** — Lower-index gambit slots are evaluated before higher.
- **A2** — A disabled slot is skipped entirely (no condition eval, no target select).
- **A3** — All conditions on a slot must pass (AND logic) before the action commits.

### B. Fall-through

The category where the most user-visible bugs live.

- **B1** — Slot's `condition_target` resolves to no candidate → fall through to the next slot.
- **B2** — Conditions evaluate false → fall through.
- **B3** — Action is a SPELL/ABILITY whose `mp_cost > current_mp` → fall through (sync; preserved by `spell_pre_validate`).
- **B4** — Silence status vetoes SPELL/ABILITY → fall through. Items still pass.
- **B5** — Immobilize status vetoes MOVE → fall through.
- **B6** — Action target is reachable but the action cannot execute (no cast position, no attack tile, blocked LOS): **the unit MUST NOT loop forever on this slot.** Within K=10 ticks the unit either falls through to the next slot or, if no slot resolves, enters a stable IDLE state without thrashing. (Current behavior on Monk Secret Fist: loops indefinitely. Tracked as XFAIL until fixed.)
- **B7** — NEAREST_ENEMY / NEAREST_ALLY / NEAREST_ALLY_OR_KO gambits — the pool rows the `To` column spells `Foe` / `Ally` — retry: when Pass 1's rank-0 target failed, Pass 2 walks ranks 1, 2, 3 … before falling through to the next slot. Those three types and no others; **B10** is the complement.
- **B8** — Action's per-ability cooldown is still running (`tick < cooldown_ready_at[ability_id]`) → fall through (sync; preserved by `cooldown_pre_validate`). The cooldown is independent of the MP veto (B3): either short-circuits the slot. Set at commit-time, fire-and-forget — an interrupted action does NOT refund the timer, matching the MP model (ADR-0047).
- **B10** — **STRICT depth does NOT retry (ADR-0285).** `NEAREST_ALLY_ONLY` / `NEAREST_ENEMY_ONLY`
  run the identical `find_unit_by_criteria(..., mode=0, ...)` search as B7's types and are
  **absent from Pass 2's retry guard**, so a rank-0 candidate who fails the slot's conditions
  ends the slot for that tick — the walk moves on to the next slot rather than to rank 1. The
  absence IS the rule: there is no per-slot flag, and adding either type to the `target_type !=`
  condition in `evaluate_gambits_up_to` silently turns the surface's `Nearest Ally` row back into
  the pool search it was built to stop being. Witnessed by which SLOT commits, on one unit whose
  two slots differ only in the resolution.

### C. Target resolution

- **C1** — `NEAREST_ENEMY` picks the nearest enemy by **path cost** — `get_distance`, the
  precomputed level-aware distance field — not by Manhattan. A candidate the field reports as
  unreachable (`-1`) is dropped, not ranked far. Ties broken by unit id (stable).
  (This line said "lowest-Manhattan-distance" until #1102; the kernel never did that.
  See **D8** for the three distances and which question each answers.)
- **C2** — `LOWEST_HP_ENEMY` / `LOWEST_HP_ALLY` (the `MOST_CRITICAL` resolution) picks by HP percentage, not absolute HP.
- **C6** — **The pool and the depth are two axes, and the `To` column now spells both
  (ADR-0285).** `Ally` / `Foe` are `NEAREST_FIRST` — the whole team, walked in proximity order,
  which **B7** retries. `Nearest Ally` / `Nearest Foe` are `NEAREST_ONLY` — the same rank-0 unit
  and nobody else, which **B10** does not. `Weakest Ally` / `Weakest Foe` are `MOST_CRITICAL`
  (**C2**), which never retried. So the condition FILTERS a pool on the first and GATES one unit
  on the other two, and the two spellings differ in the encoded `cond_target_type` alone.
- **C7** — **Every nearest-metric pool excludes the caster, strict or not.**
  `find_unit_by_criteria` skips `u == unit_id` when `mode == 0`, and only then — so `Ally`,
  `Nearest Ally`, `Nearest Foe` and `Foe` can never resolve onto the actor, while `Weakest Ally`
  resolves onto them whenever they are the most-hurt friendly. A lone unit's `Ally` and
  `Nearest Ally` rows therefore both take `VERDICT_NO_CANDIDATE`; strict depth changes what
  happens AFTER rank 0 fails, never whether rank 0 exists.
- **C3** — `SELF` resolves to the actor; `TRIGGERING` resolves to whichever unit the condition pass selected.
- **C4** — When `action_target.pool_type == TRIGGERING`, the action fires on the unit the condition pass selected (not re-selected).
- **C5** — When `action_target` carries a different selector from `condition_target`, the action's target is resolved independently from the condition's pass.

### D. Conditions

- **D1** — `ALWAYS` always passes.
- **D2** — `HP_BELOW` / `HP_ABOVE` (`TARGET_HP` / `SELF_HP` / `ALLY_HP` / `ENEMY_HP`) evaluate against current/max HP percentage.
- **D3** — `MP_BELOW` / `MP_ABOVE` evaluate against current/max MP percentage.
- **D4** — `HAS_STATUS` / `MISSING_STATUS` evaluate against the unit's active status set.
- **D5** — Multiple conditions on one slot are AND-combined; one false fails the slot.
- **D6** — `TARGET_IN_RANGE` asks **the slot's own action** whether it reaches the candidate from
  where the actor stands, with no walking. An ability answers with its own range and — for the
  abilities carrying `vertical_tolerance` / `vertical_fixed` — its own vertical bound;
  `ATTACK` / `MOVE` / `WAIT` carry no ability and answer with the equipped weapon's reach, which
  is the same fallback `get_effective_ability_range` already uses for an ability whose range is
  0. `effect_area` does not enter: the ROM measures an AoE to its centre tile.

> D6 is what the gambit surface offers as `In Range` (ADR-0268 dec. 11; **one** row since
> ADR-0283 dec. 2, where it was `Foe In Range` / `Ally In Range`). Those two rows differed in
> their SUBJECT and never in the range, and the subject is its own column now — so the pair
> collapsed to the predicate they shared. A row that named melee-or-spell would restate what the
> `Do` column already says and be wrong the moment the player changed it. The kernel predicate is `target_in_action_range` in
> `combat_combat.glslinc`, and `start_spell` gates on the same `ability_in_reach` it calls, so
> the screen's answer and the unit's behaviour cannot come from two copies of the arithmetic.

> The gambit **row menu** authors one condition per slot (ADR-0268 dec. 3). That is a cap on
> the authoring surface, not on D5 — `Gambit.conditions` stays an array, the mutation operators
> keep writing multi-condition slots, and a slot carrying more than one renders `+N` and is
> saved whole.

- **D7** — `IS_KO` / `IS_ALIVE` ask the candidate's `FLAG_DEAD` bit via `is_unit_dead()`.
  **They do not read status bit 0.** `STATUS_DEAD` is a separate word that nothing in the tree
  sets or reads, so authoring the revive gambit as `HAS_STATUS(&"dead")` encodes cleanly, passes
  every guard and never fires. `GambitCondition.is_ko()` is the spelling that reaches the kernel.
- **D7a** — **Every target pool but one filters KO'd candidates before any condition runs.**
  `find_unit_by_criteria` and `find_nth_nearest` drop `is_unit_dead` units, so `IS_KO` over an
  ordinary `friendlies()` pool is decidable and unreachable — the corpse never becomes a
  candidate. `TargetSelector.friendlies_or_ko()` → `TARGET_NEAREST_ALLY_OR_KO` is the only
  KO-inclusive pool, and it is in **B7**'s pass-2 rank walk precisely because the nearest ally
  is usually standing: without the walk the revive gambit would work only when the corpse
  happened to be closest. Deadness lives in the CONDITION; the pool only decides who may be
  looked at.
  > `include_ko` anywhere without a GPU spelling — an enemy pool, `MOST_CRITICAL` (a corpse is
  > 0% HP and would win every time), `SELF`, `TRIGGERING` — is **E1** UNSUPPORTED, never
  > silently demoted to the KO-blind pool.
- **D8** — `TARGET_DISTANCE` (`COND_DISTANCE_LESS` / `COND_DISTANCE_GREATER`) compares
  `manhattan_distance(actor, candidate)` against the threshold in **tiles**: planar,
  level-blind, wall-blind — FFT's own range metric. `EQUALS` has no kernel arm and is **E1**
  UNSUPPORTED rather than folded into `>`.
  > **Three distances, three questions, and they disagree on purpose.** `TARGET_DISTANCE` is
  > raw grid geometry; **C1**'s `NEAREST` ranking is travel cost through the path field;
  > **D6**'s `TARGET_IN_RANGE` is whether this slot's own action lands. A wall between two
  > adjacent tiles leaves them 1 apart for D8, far apart for C1, and out of range for D6.

### E. Encoder UNSUPPORTED (ADR-0023)

- **E1** — A gambit authored with any UNSUPPORTED feature (e.g. `ENEMY_IN_RANGE` condition, `SPECIFIC_UNITS` pool, `HIGHEST_STAT` resolution) is **skipped** at encode time: the slot is null in the GPU buffer, the encoder calls `push_error`, and evaluation falls through to the next slot. The unit is NOT bricked.
- **E2** — Scenarios that intentionally test encoder skip behavior opt in via `expect_encoder_skips:` so the `push_error` is expected, not noise.

### F. Action execution paths

- **F1 (ATTACK)** — In range → swing. Out of range → walk to adjacent attack tile, then swing.
- **F2 (SPELL/ABILITY)** — In range, no charge → instant cast. In range, charge > 0 → enter SPELL_CHARGING, on timer-zero cast. Out of range → walk to cast position, then cast. Cinematic abilities take the `cast_cinematic_spell` path.
- **F3 (ITEM)** — In adjacent range → instant use. Otherwise → walk to within range, then throw.
- **F4 (MOVE_TO_UNIT)** — Walk toward the target unit, stopping adjacent. Re-paths each tick as the target relocates (ADR-0062).
- **F5 (MOVE_TO)** — Walk toward the packed absolute tile destination. Stops on arrival.
- **F6 (WAIT)** — No movement, no swing. Re-evaluates gambits after `TICKS_GAMBIT_REEVAL`.
- **F7 (REVIVE)** — An ability lands on a **KO'd** target — clearing `FLAG_DEAD` and writing
  HP from the ability's own formula — **iff its ROM inflict list names `Dead` under mode
  `cancel`.** That is the whole permission; there is no `ABFLAG_` for it and none was added.
  Over the shipped database it admits exactly five abilities: Raise (5), Raise2 (6),
  Revive (107), Oink (312), and PhoenixDown (381) through the chemist item's own inflict
  block. Every other ability still no-ops at a corpse, including a plain heal.
  > **The mask bit is not the status bit.** `STATUS_DEAD` (bit 0 of the unit's status word)
  > stays hollow — death is `FLAG_DEAD` in `U_FLAGS` and `is_unit_dead` reads THAT. What F7
  > reads is bit 0 of the **ability's** `AB_INFLICT_MASK`, a fact about the ability table.
  > A revive that wrote HP without clearing the flag would leave the unit dead, which is
  > precisely why the `revived` predicate asserts the flag and not the HP delta.
- **F8 (REVIVE, out of range)** — A reviving ability out of range walks to cast like any
  other (**F2**): `handle_moving_to_cast_state` does not abandon the cast because the target
  is dead. For every non-reviving ability it still does.
  > A corpse is the only thing a revive ever walks toward, so before #1113 this gate failed
  > 100% of the times it was reached — the cast was cancelled on the first tick of the walk.

### G. Pathfinding & terrain

- **G1** — On flat traversable terrain, the unit's path is the Manhattan-shortest reachable.
- **G2** — Unit cannot step onto a tile with `|height_delta| > jump` (ADR-0017 movement-step interpreter).
- **G3** — Impassable terrain → unit pathfinds around (uses `trace_stitched_path` with backtracking).
- **G4** — **Pass-through** — unit may walk *through* an allied unit's tile (not enemy) IF the tile beyond is traversable and unoccupied. (`find_passthrough_destination` in stage_attack/spell.)
- **G5** — Pass-through fails closed: if no walkable+unoccupied tile is reachable on the other side of the allied tile, the unit treats the allied tile as blocked and pathfinds around.
- **G6** — A tile reserved (not just occupied) by another unit is treated as occupied for pathfinding.
- **G7** — `get_next_step` returns "no move" → unit waits `TICKS_PATH_RETRY` ticks, re-tries. Must not loop forever — covered by the no-thrash predicate H6.

### H. State-machine interactions

- **H1** — A unit in `SPELL_CHARGING` does not re-evaluate gambits.
- **H2** — A unit in `ACTING` (swinging, instant casting, etc.) does not re-evaluate.
- **H3** — A unit in `AWAITING_IMPACT` (projectile in flight, ADR-0032) does not re-evaluate.
- **H4** — A unit in `REACTING` (taking damage / playing flinch) does not re-evaluate.
- **H5** — A unit with `U_PAUSED == 1` (cinematic spotlight) does not re-evaluate. Caster is exempt.
- **H6** — **No thrash** — a unit does not commit more than N distinct decisions in K ticks (default N=4, K=20). The shader's existing thrash detector flips `thrash_flag`; the test asserts it stays 0.
- **H7** — Post-action: unit returns to `IDLE` and re-evaluates gambits at the next eval tick.

### I. AoE / multi-target

- **I1** — AoE ability with `effect_area > 0` picks one center target via `action_target_type`, then hits every unit within radius.
- **I2** — Healing AoE filters to allies only (no friendly damage from heal misclassified as damage on allies).
- **I3** — Cinematic AoE stamps `U_AOE_PENDING_FIRE_FRAME` per target, fires damage at `first_hit_frame + N * for_each_delay`.

### J. Cinematic-spell

- **J1** — When a cinematic-spell starts, non-caster units get `U_PAUSED = 1`, freezing their gambit re-evaluation.
- **J2** — The caster's stage_compute / stage_spell continue (so the orchestrator runs).
- **J3** — Cinematic teardown clears `U_PAUSED` on every unit; all units resume gambit evaluation next tick.

### K. Default aims (ADR-0276)

Every other group asks what the kernel does with a rule someone wrote on purpose. K asks what
it does with the rule the **screen** wrote — the aim a slot carries because nobody changed it.
The grader is `GambitOptions.aim_verdict`; `GambitEncoderTest::_audit_every_aim_cell` walks the
whole `(verb x aim x subject)` space statically — **8,992 cells**, `sensible 6,732 | no_op 5 |
forbidden 1,247 | ignored 27 | unnamed 681 | never_resolves 280 | untargetable 20` — and K roots
its most costly grades in the kernel.

> The subject axis is `GambitOptions.subjects() x targets()` deduped by `aim_class` (ADR-0283
> dec. 1), which is the same **three** classes the folded `If` catalogue collapsed to, plus a
> **fourth the screen cannot produce**: a raw `Them` subject, which a pre-ADR-0283 save or
> #895's operators can hold. It is carried deliberately, because it is the only input that
> reaches `never_resolves` — `mirror_of` refuses to build the pair — and a grade that only ever
> reads zero is indistinguishable from a grade nothing examined.

- **`never_resolves`** — `Them` aimed at a `Them` subject encodes `cond_target_type =
  TARGET_THEM`, and `select_target` answers `case TARGET_THEM: return -1;  // Set by caller`.
  Pass 1 writes `VERDICT_NO_CANDIDATE` and skips the slot, every tick, forever. It encodes
  cleanly, so rule E1 cannot see it; `targets_for` withholds the `Them` row instead.

- **K1** — `Move / Self` **fires and moves nowhere.** MOVE inherits `action_target` as its
  destination, so `execute_move_to_unit_gambit` reads its own tile and the adjacency check
  `manhattan_distance(my, my) <= 1` is true on the first evaluation: REASON_ARRIVED, idle. The
  slot COMMITS, so every lower-priority slot is unreachable, and the unit has not moved. Ships
  with a control arm — the same fixture minus the no-op slot — because K1 asserts two absences.
- **K2** — `ThrowStone / Self` **lands on the caster.** The ability carries
  `dont_hit_caster: true` (ADR-0049), but `hit_policy_allows` is called only from the two AoE
  distribution walks, both gated on `effect_area > 0`. ThrowStone's `effect_area` is 0, so the
  single-target path applies the damage without ever consulting the policy. XFAILed: the
  scenario asserts what *should* happen, and reports XPASS the day #1144 enforces it.
- **K3** — **the ROM has TWO self-targeting rules and they are not the same rule** (ADR-0291).
  K2's `dont_hit_caster` is the SPLASH filter; `dont_target_self` (flags1 bit 0x01) is the
  CURSOR filter, and the ROM enforces it somewhere else entirely: `FUN_8017A290` @ `0x8017A290`
  builds the selectable-tile table at `0x80192DD8`, marks the caster's own tile selectable
  (`0x8017A410`–`0x8017A418`), then tests the bit at `0x8017A444` and **zeroes that entry** at
  `0x8017A450`. So the flag decides what the cursor may land ON, not who the effect lands on.

  156 records carry it and 152 of those also carry `dont_hit_caster`, so the gap the screen
  could actually author is **four abilities** — `Revive` (107), `Invitation` (116), `Wish`
  (152), `BloodSuck` (200) — all skillset-reachable, all `effect_area 0`. `aim_verdict` grades
  them `untargetable` and `targets_for` withholds the `Self` row.

  ⚠️ **This is the SURFACE half only.** The kernel has no `dont_target_self` counterpart at
  all, and because every one of the four is `effect_area 0` they sit in the same single-target
  hole K2 does. Closing #1144 is what makes a gambit arriving from anywhere else safe; K3 only
  stops the screen offering the cell.
- **K4** — **the `To` list is ORDERED by the ability's family** (ADR-0296). `healing`/`buff`
  lead with the ally block, `damage`/`debuff` with the foe block, and `Self` heads the list only
  when the ability is *positive* **and** the `Self` row survived K3's gate — so `Wish` and
  `Revive` (healing, but `dont_target_self`) lead with `Ally` and offer no `Self` at all.
  `Self` sinks *below* the ally block for a negative ability, because `Fire / Self` is a worse
  row than `Fire / Ally`.

  It sorts what the gate left and never changes membership, so the ADR-0276 one-decision guard
  (a SET comparison) is untouched. An UNKNOWN-family ability keeps `targets()` order — that is
  the test's control arm, because "`Cure` leads with an ally row" is also true of a sorter that
  leads with an ally row for everything.

  **`Attack` IS ordered, and it was the cell that proved the rule** (ADR-0296 dec. 6). It has no
  family, but it is foe-side anyway — `seed_aim_for` had hardcoded that since ADR-0268 while the
  order asked `family_aim_name`, so `Attack` seeded `Foe` and opened on `Self`. One answer now
  (`aim_polarity`) feeds both, and `Attack` reads `Foe, Nearest Foe, Weakest Foe, Ally, …, Self`.

  ⚠️ **The head is the seeded row for every cell EXCEPT dec. 3's carve-out** — a positive,
  self-targetable ability heads on `Self` while still seeding the family's row (`Cure` opens on
  `Self`, defaults to `Ally`, per ADR-0278 dec. 2). 57 of 281 cells, and `GambitEncoderTest`
  asserts that count is neither 0 nor all of them.

  ⚠️ The polarity this sorts on **is stored in the ROM's AI block** (`ai_target_allies` /
  `ai_target_enemies`), which ADR-0278 says it is not; ADR-0296 dec. 5 and #1227.

## How XFAIL works

A scenario's `xfail:` field names the *specific* expectations expected to
fail today. If only those fail, the scenario reports `XFAIL` and the suite
stays green. If they suddenly pass, the scenario reports `XPASS` (loud-but-
green by default) — flip the xfail off, the bug is fixed.

```gdscript
"xfail": ["trace.by_tick(50)", "liveness.no_stuck(Monk)"],
"xfail_reason": "Secret Fist no-cast-position retries forever (issue TBD)",
```

If an *un-xfailed* expectation starts failing, the scenario reports `FAIL`
regardless of `xfail` — that's a real regression, not the pinned bug.

## Suite mechanics

- Scenarios live in `tests/gambit_scenarios/scenarios_X_*.gd`, grouped by
  rule letter (A through K).
- A single runner scene (`GambitScenarioRunnerTest.tscn`) aggregates every
  scenario, runs them grouped-by-map, and reports per-scenario
  PASS / FAIL / XFAIL / XPASS / ERROR / NORAN.
- `NORAN` (No-Ran) is the "scenario didn't actually execute" sentinel —
  baseline checks (current_tick > 0, all units encoded successfully, at
  least one gambit eval recorded) failed.
- The suite gets **one** entry in `tests/run_all_tests.sh`; the summary
  shows one aggregate verdict, the log shows per-scenario details.
- When the suite outgrows the 360s timeout, shard into
  `GambitScenarioRunnerTest_ABCD.tscn` / `_EFGH.tscn` / `_IJ.tscn`.
- Canonical maps set is small (~4–6); most scenarios reuse them. The
  suite changes map at most once per group.

## Authoring a scenario

```gdscript
{
    "rule": "B6",
    "name": "monk_secret_fist_out_of_range_falls_back_to_attack",
    "map": "MAP042",
    "seed": 42,
    "max_ticks": 200,
    "units": [
        {
            "name": "Monk", "team": 0, "tile": [3, 5],
            "job": "monk", "level": 20,
            "gambits": [
                Gambit.create(TargetSelector.enemies(), [GambitCondition.always()],
                              Gambit.ActionKind.ABILITY, ABILITY_SECRET_FIST,
                              TargetSelector.triggering()),
                Gambit.create(TargetSelector.enemies(), [GambitCondition.always()],
                              Gambit.ActionKind.ATTACK, -1,
                              TargetSelector.triggering()),
            ],
        },
        {
            "name": "Knight", "team": 1, "tile": [9, 5],
            "job": "knight", "level": 20,
            "gambits": [Gambit.create(...)],
        },
    ],
    "expect": {
        "outcome": {"winner": 0},
        "trace": [
            "by_tick(50): unit('Monk').committed(ACTION_ATTACK)",
        ],
        "liveness": [
            "no_stuck(unit='Monk', max_idle_ticks=10, given='any_enemy_alive')",
        ],
    },
    "xfail": ["liveness.no_stuck(Monk)"],
    "xfail_reason": "Secret Fist no-cast-position retries forever (issue TBD)",
}
```

Rules of the road:

- Real maps only — name the canonical map by id (`MAP042`, `MAP015`, ...).
- Real `Gambit` objects, run through `GambitEncoder`. No flat-dict shortcuts.
- Every scenario carries `rule:` referencing this doc.
- `xfail:` is a list of *specific* expectations expected to fail, not a
  blanket marker. Include `xfail_reason:` with the issue/ADR id.
- `seed:` defaults to the suite seed; override for evasion / RNG-sensitive
  scenarios.
