# Real-time ability cooldown is a per-ability floor

## Status

Accepted

Verified 2026-08-28 — all six decisions are built (`tools/parse_abilities.py`,
`src/gpu/shaders/stage_compute.glsl`, `src/gpu/shaders/combat_common.glslinc`,
`src/gpu/GPUBatchSimulator.gd`, `docs/gambit-rules.md` rule B8). Two of them ship
differently from the shape this ADR first landed — the default is 300 ticks, not
60 (#93), and the state is a dedicated SSBO, not a field on the unit struct
(#85). Both stand below as they ship, with the originals under **Considered
options**. See `AUDIT.tsv` and `audit-notes/0047.md`.

## Context

FFT was turn-based. The cost of any action was *using the turn*, and the CT
("charge time") field tuned the spacing between actions — long-CT spells were
expensive because the unit sat exposed during charge; short-CT actions were
spammable but capped by the turn cadence itself. Real-time gambit evaluation
removes the turn cadence entirely. A CT=0 ability with no MP cost (Knight
Skills, Punch Art, Geomancy, Mediator Talk skills, Sing/Dance) would have *no
floor at all* — a gambit re-evaluating every `TICKS_GAMBIT_REEVAL` ticks fires
it again as soon as the previous instance resolves, and the unit never needs to
"regular Attack" because the sword skill is free and instant.

This is a balance problem the FFT data cannot answer — there are no bytes in the
ROM describing how long a unit should wait between two Holy Swords, because the
question never arose. So the floor has to be invented.

## Decision

1. **Cooldown is universal across every ability.** Every ability record carries a
   `cooldown_ticks` field. There is no `is_cooldown_class` predicate at runtime —
   `cooldown_ticks > 0` is the only "class membership" the system needs, and the
   GPU just reads the number. Two structural exemptions fall out of the
   implementation rather than out of a list: `ATTACK` and `MOVE` carry no
   `ability_id` and so are never gated, and an `ability_id` at or above
   `MAX_COOLDOWN_ABILITIES` (summon / cinematic-spell ids) falls through the veto
   as a no-op — those have CT-or-projectile-bounded natural rate limits.

2. **Default value: 300 ticks (5 seconds at 60 Hz),** `DEFAULT_COOLDOWN_TICKS`
   in `tools/parse_abilities.py`. It is safe to apply globally because cooldown
   counts from *commit*, not from animation end: a CT-bearing ability (Cure,
   Bolt, Fire, …) spends most of its action lifetime in `SPELL_CHARGING` after
   the commit, so the floor has long expired by the time charging finishes and
   the ability re-fires on its natural CT cadence. Only CT=0 abilities — Punch
   Art, Knight Skills — actually feel it, which is exactly the set the cooldown
   exists for. The same per-ability field supports per-ability overrides; data
   starts uniform and grows differentiated as balance work surfaces specific
   abilities.

3. **The cooldown veto fires at gambit eval time, same shape as the MP-cost veto
   (rule B3).** `stage_compute.glsl` carries `cooldown_pre_validate(battle_id,
   unit_id, ability_id)`; on `false` the gambit slot falls through to the next
   one via the existing fall-through machinery (rule B8). The veto is independent
   of the MP veto — either one short-circuits the slot.

4. **State lives per-(unit, ability_id) in its own SSBO, not on the unit
   struct.** Binding 9 holds a flat `int` array indexed
   `[unit_global_idx * MAX_COOLDOWN_ABILITIES + ability_id]`, with
   `MAX_COOLDOWN_ABILITIES = 128` — 512 B/unit. It is *out* of the unit struct
   deliberately: `copy_unit_to_next` runs `UNIT_SIZE` ints per unit per tick, and
   per-commit state has no business in that copy. The buffer is single-buffered,
   which is load-bearing rather than incidental — a commit written earlier in the
   same tick is visible to the next slot's `cooldown_pre_validate`, so two slots
   naming the same ability cannot both commit on one tick. The same ability
   referenced from two gambit slots shares one timer, which is the desired
   semantics: `action_id` is the rate-limit's natural granularity, not slot index.

5. **Timer starts at commit-time, same place MP is deducted.** Fire-and-forget —
   an action interrupted mid-flight does not refund the cooldown, matching the MP
   model. No refund machinery. Written for `ACTION_SPELL` / `ACTION_ABILITY` /
   `ACTION_ITEM` only, as `tick + cooldown_ticks`.

6. **Cooldown is parser-authored, not ROM-extracted.** The default constant lives
   in the parser source as a hand-authored value, in the same family as
   `tools/_fft_decode.py`'s `ELEMENTS` table — extractor source carrying things
   ROM bytes can't name. Reproducibility holds because the parser is
   deterministic. It reaches the runtime through `abilities.json` → the
   [AbilityView](../context/05-ability-data.md) `cooldown_ticks` getter →
   `GPUAbilityLoader`'s `AB_COOLDOWN_TICKS` slot. Future per-ability tuning grows
   the parser's cooldown table from "global default" to "lookup keyed by
   ability_id."

See the `Ability cooldown` glossary entry in
[CONTEXT.md](../context/02-combat-buffer-layout.md) for the runtime details.

## Considered options

- **Default 60 ticks (1 second)** — shipped, then raised to 300 (#93). 60 was
  chosen as the smallest value universally subsumed by any non-zero CT
  (CT 2 = `ct * 30` = 60 ticks), so the floor never raised the bar for CT ≥ 2
  abilities. It delivered *spacing* correctly and the *fall-through* contract not
  at all: 60 ticks is barely longer than the Secret Fist cast animation (~60
  ticks of ACTING), so the IDLE window between consecutive commits was too short
  for a slot-1 ATTACK to ever land, and the alternation the design promised never
  materialised. Dec. 2 is what survived. The subsumption property is lost by the
  raise, and does not need recovering — see dec. 2's commit-time argument.

- **`cooldown_ready_at` inline on the unit struct** — shipped, then pulled out to
  binding 9 (#85). A 128-wide per-commit array inside a struct that
  `copy_unit_to_next` walks every tick per unit is per-tick cost for data that
  changes at commit rate. Dec. 4 is what survived.

- **Rebalance MP costs to limit CT=0 spam.** Rejected: MP is already a meaningful
  constraint that the affected ability families *deliberately* bypass — Knight
  Skills cost 0 MP, Punch Art costs 0 MP. Adding MP cost redefines what those
  families *are*, and conflates "this ability is expensive" with "this ability
  has a minimum interval."

- **Global GCD across all the unit's abilities.** Rejected: a single unit-level
  cooldown would make firing Potion lock out Holy Sword for the same duration,
  inverting the local-balance intent. Per-ability floors keep each ability's
  spacing local to itself.

- **Per-job action-rate caps.** Rejected: the rate-limit is properly a property
  of the *ability*, not the *job*. A future job granting the same Knight Skills
  should inherit the same rate-limit; a job-level cap would decouple them.

- **Scale CT for low-CT cases (e.g. CT 0 → CT 1).** Rejected: this changes what
  CT means (the charging vulnerability window) and conflates "the unit is exposed
  while preparing" with "the unit cannot act again yet." CT=0 = "no
  vulnerability" plus a separate cooldown = "rate-limit only" preserves both
  semantics cleanly.

- **Predicate-conditional cooldown (only CT=0 non-projectile non-inventory
  abilities).** Rejected: universalising the field collapses the predicate — CT,
  projectile flight, and AoE caster-lock are already longer floors for the
  abilities that have them, so cooldown is a no-op there. One field, one shape,
  no authored exemption list (dec. 1's two exemptions are structural, not a
  curated set).

## Consequences

- **GPU buffer growth**: 512 B/unit for the binding-9 array. At
  `MAX_UNITS_PER_BATTLE = 8` that is 4 KB/battle — negligible against the combat
  buffer, and it costs nothing per tick because it sits outside the unit copy.

- **A cooldown gap read off the host frame is not the floor** (#86). `CombatLoop`
  can run several `step_tick(1)`s per host frame at `Engine.time_scale > 1`, so a
  trace tick records end-of-frame (`commit_gpu_tick + remaining_ticks_in_frame`)
  and two casts whose within-frame offsets differ by `K` show a trace gap of
  `true_gap ± K`. Anything asserting spacing must recover the GPU commit tick as
  `cooldown_ready_at - cooldown_ticks` by sampling the SSBO at `cast_began`
  emission, which is what
  `GambitAssertions._check_cooldown_respected` prefers when the sample is
  present; trace ticks stay reported alongside for transparency.

- **No editor surface yet.** Cooldown is not exposed in the gambit editor — the
  value is per-ability data, tuned in the parser. A future debug overlay may
  surface per-unit cooldown timers when balance work begins.

## Verification

- `docs/gambit-rules.md` rule B8 states the fall-through, parallel to B3.
- `tests/gambit_scenarios/scenarios_B_fallthrough.gd`
  `ct_zero_ability_respects_60_tick_cooldown` — B8 spacing, `min_spacing=60`,
  `min_casts=3`, `max_ticks=1000`, scored on the GPU-commit axis.
- `secret_fist_alternates_with_attack_fallback` in the same file — the dec. 2
  regression guard (#92): the cooldown window must admit at least one ATTACK
  commit per cycle. This is the bar that failed at 60 ticks.
- `GPUBatchSimulator.get_cooldown_ready_at()` is the sampling seam;
  `GambitTraceLogger.on_cast_began()` attaches `cooldown_ready_at` to each cast
  event.
