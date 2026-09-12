# Gambit Scenario Runner

Behavioral test suite for the gambit system. The spec — every rule the system
is supposed to follow — lives in [`docs/gambit-rules.md`](../../docs/gambit-rules.md).
This directory holds the harness:

- `GambitScenarioRunner.gd` — registry + executor + reporter. Sorts scenarios
  by `map:`, runs each through `CombatLoop.start_battle`, evaluates
  `GambitAssertions`, prints a six-state verdict.
- `GambitAssertions.gd` — predicate library (`outcome.winner`,
  `by_tick(T).committed(...)`, `no_stuck(...)`, `gambit_fired_at_slot(...)`,
  `damage_dealt_to(...)`).
- `GambitTraceLogger.gd` — subscribes to existing `CombatLoop` signals + reads
  per-tick GPU snapshots (`current_gambit`, `decision_hist_*`), produces the
  queryable trace the predicates read.

Scenarios live in [`../gambit_scenarios/`](../gambit_scenarios/) as one file
per rule letter (`scenarios_A_ordering.gd`, `scenarios_B_fallthrough.gd`, …).

## Authoring conventions

- Every scenario carries `rule:`, `name:`, `map:`, `seed:`, `max_ticks:`,
  `units:` (with real `Gambit.create(...)` objects), and `expect:` block.
- Real `Gambit` domain objects only — the runner pipes them through
  `GambitEncoder.encode_gambits()` like production. **No flat-dict
  `make_attack_gambit()`-style helpers** (they bypass the encoder and miss
  exactly the drift this suite catches).
- Real ROM-derived maps only (`MAP042`, `MAP015`, …) via
  `MapComposer.change_map`. No synthetic terrain.
- `xfail:` is a list of specific expectation **names** expected to fail today
  (not a per-scenario marker). Include `xfail_reason:` pointing at the issue
  driving the future shader fix.
- `expect_encoder_skips: true` opts in to an UNSUPPORTED-encoder feature so
  the `push_error` from `GambitEncoder` is expected and the skip is asserted.
- Pre-combat status seeding for B4/B5: set `status_flags_lo:`/`status_flags_hi:`
  on the unit cfg (bit positions from
  [`combat_common.glslinc`](../../src/gpu/shaders/combat_common.glslinc) — e.g.
  `1 << 25` for `STATUS_SILENCE`, `1 << 9` for `STATUS_IMMOBILIZE`). The bit
  stays set indefinitely unless paired with a `status_timers:` entry.

See [the docs/gambit-rules.md authoring template](../../docs/gambit-rules.md#authoring-a-scenario)
for the canonical scenario shape and the `xfail:` semantics.

## Six-state verdict taxonomy

| Verdict | Meaning |
|---------|---------|
| PASS    | every expectation passed |
| FAIL    | an un-`xfail`-ed expectation failed |
| XFAIL   | only `xfail`-ed expectations failed (loud-but-green) |
| XPASS   | an `xfail`-ed expectation passed → flip the xfail off |
| ERROR   | scenario setup raised before evaluation could run |
| NORAN   | baseline check tripped (sim didn't advance, all gambits skipped, …) |

XPASS treatment is soft-fail by default (suite stays green); configurable via
the runner's `xpass_treatment` knob.

## Adding a new scenario

1. Pick or create the appropriate `scenarios_X_*.gd` file in
   `../gambit_scenarios/`.
2. Add a static helper that returns the scenario dict; append it to the
   file's `scenarios()` return.
3. Run `bash tests/run_all_tests.sh` (or the single scene
   `res://tests/GambitScenarioRunnerTest.tscn`). Check the log at
   `tests/logs/GambitScenarioRunnerTest.log` for the verdict block.
