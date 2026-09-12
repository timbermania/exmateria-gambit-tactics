# Ability hit policy is ROM-flag-derived, not animation-inferred

## Status

Accepted (2026-06-18)

The "who-in-the-radius-actually-gets-affected" axis (the **hit policy** — see
CONTEXT.md §"Ability hit policy") reads the ROM's three
`dont_hit_enemies` / `dont_hit_allies` / `dont_hit_caster` flags on the
ability record, surfaced as `ABFLAG_HIT_NO_ENEMIES` / `NO_ALLIES` /
`NO_CASTER` bits on `AB_FLAGS`. The previous heuristic — gating AOE team
membership from `is_ability_healing` (derived from
`target_reaction_type == "receive_heal"`, a post-hit reaction-animation
tag) — was a two-step indirection that misrouted Esuna
(`target_reaction_type = none`, but FFT-canonically hits any unit in
radius) and is retired. `ABFLAG_HEALING` is kept, narrowed to its
HP-write-direction job only (heal adds HP / damage queues pending).

## Consequences

- **FFT canon: friendly fire is on by default.** Cure cast on an enemy
  tile heals the enemy; Fire on an ally tile damages the ally. Every
  sampled spell except Bio has all three `dont_hit_*` flags false. A
  future game-design "team-lock" toggle can sit on top of this axis but
  is not part of this slice.
- **Esuna ally-cleanse works without per-ability classification.** The
  cancel-mask no-ops on units without the named statuses, so "hit
  everyone in radius" naturally maps to "cleanse whoever has it."

  > **KNOWN DROP, 2026-08-22: the end-to-end witness for this bullet is
  > DELETED.** `tests/GPUEsunaAllyTest.gd` asserted exactly this sentence —
  > Priest at (0,0) casts Esuna on the NEAREST_ENEMY at (3,0), and the
  > poisoned ally at (2,0), inside the enemy-centred AOE, is cleansed. It is
  > removed for **load-dependent flakiness, not because the claim stopped
  > mattering**, and the number it died holding is written down here so the
  > gap is visible rather than silent.
  >
  > **The mechanism, so a replacement does not inherit it.**
  > `tests/GPUCombatTestBase.gd` (~lines 44–50) records that combat runs on
  > CombatLoop's **real-time delta-driven pump**, which is *"load-bearing for
  > combat resolution"* — a fixed ticks/frame substitute was tried and
  > reverted. So the test's `max_ticks = 1200` was a **wall-clock budget
  > wearing a tick's clothing**: it waited out charge (90) + anim (60) +
  > cinematic delivery, and on a loaded machine the harness cut it at tick
  > **1227**, 27 short. It was `PASS` in `docs/TEST-BASELINE-E2.tsv` (frozen
  > at `4ed6fb5c7`) and failed under load on 2026-08-22. **Widening
  > `max_ticks` would be tuning a test to green and is not the fix.**
  > A second, load-independent defect: `_print_results` sampled
  > `status_timer_0` in the very frame the poison bit cleared, with no settle
  > window — a race by construction.
  >
  > **WHAT IS STILL GUARDED, AND WHAT IS NOT — the gap is a COMPOSITION, not
  > the claim.** Both halves survive independently:
  > - *Hit policy ignores team* — `tests/gambit_scenarios/scenarios_I_aoe.gd`
  >   pins both directions, including the surprising one ("an in-radius foe IS
  >   healed" by Cure, and Fire damaging an ally).
  > - *CANCEL clears a status* — `tests/GPUStatusCancelTest.gd` covers
  >   `apply_break_effect` → `apply_inflict_all` with `mode=CANCEL`, and names
  >   Esuna (14) as riding the same path as Antidote (374).
  >
  > **Unguarded is their composition**: a status cancel reaching a unit that
  > is only in the hit set *because* hit policy ignored its team. A
  > regression that re-introduced the retired `is_ability_healing` team gate
  > **would** be caught by `scenarios_I_aoe.gd`; one that broke CANCEL
  > dispatch *specifically for units admitted by hit policy* would not.
  > Restoring the witness is [#428](https://github.com/timbermania/fft-monorepo/issues/428).
- The generator (`tools/generate_ability_database.py`) merges the three
  flags from `ability_attributes.json` into the ability record alongside
  `vertical_tolerance` / `vertical_fixed`; `AbilityView` exposes them;
  `GPUAbilityLoader` packs them into `AB_FLAGS`.
- Three shader sites stop reading `is_ability_healing` for team gating
  (`stage_damage.glsl` Phase 1 AOE, `stage_spell.glsl` cast_cinematic_spell
  + cinematic orchestrator). They now call a single `hit_policy_allows`
  helper that composes the three flags against `caster_team` /
  `target_team` / `is_self`.
