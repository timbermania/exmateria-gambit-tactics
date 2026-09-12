# The rollout fleet is the whole batch, and the only thing the CPU prunes is what cannot change

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §7 gives the enemy AI one move:
"snapshot battle 0, fill the fleet with K candidates, run, restore battle 0",
with the candidate set built from mutation operators, an authored playbook and an
imperative issue, all under common random numbers. [ADR-0237](0237-the-rollout-budget-is-bounded-by-the-horizon-and-the-unit-count-not-the-fleet.md)
measured what that beat costs. This file is what it IS: the decisions that
turn §7's paragraph into `RolloutHarness`, `RolloutCandidates` and
`RolloutPlaybook`, and the one family that could not be built.

Built by [#895](https://github.com/timbermania/fft-monorepo/issues/895).

## Status

accepted

## Decisions

**1. The fleet is every battle slot, the live battle included, and that is why
the restore is load-bearing rather than tidy.** `step_tick` encodes one compute
list over the whole batch — ADR-0237 dec. 1 is the measurement of exactly that,
and it is why 1024 battles cost 1.4x what one costs. There is no per-battle
active mask, so a 300-tick horizon carries the LIVE battle 300 ticks forward
whether or not it holds a candidate. §7 leans into it: the live battle is
candidate 0 / seed 0's substrate, and `restore_battle(0, pristine)` puts it back
afterwards. That is the whole reason no shader change was needed, and it makes
the rollout the second consumer of [ADR-0235](0235-reconfigure-is-an-overlay-and-the-shader-write-set-classifies-the-fields.md)'s
keystone — so the bit-identity test guards the thing the AI depends on, exactly
as §7 predicted.

The consequence worth stating: after a beat, slot 0 no longer shows its
candidate. Its result record was read before the restore and is valid; the slot
is not. `GPURolloutHarnessTest` asserts both directions — every other slot still
carries its assigned seed and candidate image, and slot 0 carries neither.

**2. A candidate is an encoded gambit IMAGE, not a `GambitList`.** The mutation
domain is the buffer: `GAMBITS_PER_UNIT` ints, the same slice `snapshot_battle`
hands back and `restore_battle` installs. Mutating domain objects would put a
`Gambit` -> encoder -> packer round trip inside the thinking beat, and every
candidate could then FAIL to encode — [ADR-0023](0023-gambit-gpu-projection-stays-in-encoder-faithful-or-explicit.md)'s
faithful-or-explicit skip — with nothing to do about it mid-beat. An image edit
is definitionally installable.

Authored postures are the exception and prove the rule: they are the only place a
gambit is SPELLED rather than edited, so they go through the one encoder, and a
posture the GPU cannot express is dropped there with ADR-0023's own verdict.

Two properties fall out and are guarded: no operator touches slot
`MAX_USER_GAMBITS`, because that is [ADR-0048](0048-safety-net-gambit-is-encoder-injected-ui-invisible.md)'s
terminal candidate and a rollout scoring a unit that can strand itself is
measuring a different game; and **candidate 0 is the unmutated incumbent**,
because without a "leave it alone" arm the AI is forced to change its gambits
every single turn, re-planning a working posture the moment every mutation scores
below it with nothing carrying its score.

**3. The legality prefilter is STATIC-ONLY, and the dynamic half stays in the
shader unduplicated.** §7 says the prefilter "reuses `spell_pre_validate` /
`cooldown_pre_validate`". Those live in `stage_compute.glsl` and read CURRENT MP
and a live cooldown clock; a CPU copy would be a second implementation of a
runtime rule, and the two copies would disagree — the same objection
[#894](https://github.com/timbermania/fft-monorepo/issues/894) raises against a
cleverer imperative-gambit predicate ("reachability, LOS and affordability all
duplicate shader logic on the CPU"). So the CPU prunes only what cannot change
over the horizon: an ability the unit does not have, and an ability whose
`mp_cost` exceeds the unit's MAX MP. Both read the same ability table the shader
indexes (`GPUAbilityLoader.build`'s buffer), so they are a ceiling test on the
rule's inputs rather than a copy of the rule.

An illegal candidate is therefore not waste. Its slot falls through in-shader
exactly as it would in a real battle, and it scores like the plan it degrades to
— which is the truth about it.

**4. The common-random-number seeds are spaced by the RNG's own input width, and
the boundary is proved against the hash rather than against the formula.**
`rand_int` is a stateless PCG hash of `battle_seed + unit_id * 1000 + tick`
(`combat_common.glslinc`), so a battle running `U` unit slots for `H` ticks draws
on exactly `[S, S + (U-1)*1000 + H - 1]`. Two seeds are provably disjoint at a
separation of `(U-1)*1000 + H` and can share draws below it. Sharing is not a
crash and not a visible wrong answer: it is the variance reduction quietly
turning into shared error, so the M replicates stop being independent and the
comparison keeps a bias nobody can see.

`RolloutCrnSeedsTest` builds the actual input sets `{S + u*1000 + t}` for two
battles and intersects them, at `separation - 1` (must collide) and at
`separation` (must not). A test that only asserted `seeds_are_disjoint(crn_seeds(...))`
would pass for any two functions that agreed with each other, including two that
were both wrong.

The same M seeds ARE reused across all K candidates. That aliasing is the point:
two candidates under seed m face identical luck, so the difference between their
outcomes is the gambit edit and nothing else.

**5. The playbook is keyed by `UnitRole`, not by job id.** §7 says "per-job
authored playbook (to be expanded)". A per-job table is ~130 rows of invention
with no data behind any of them, and `JobDatabase.get_job_role` is an existing,
tested job -> archetype map that covers every job — monsters and specials
included, via its HYBRID default. Role is the widest key that is ALREADY
authored, and splitting a role into its jobs later is additive: a job-keyed
override table in front of this one changes no caller.

**6. Scoring is one bulk read of the result buffer, and this harness does not
score.** ADR-0237 dec. 7 measured the alternative: `read_unit_column` is a
blocking `buffer_get_data` per battle and one column across 1024 battles costs
33-51 ms, as much as running the entire horizon, for one feature. The whole
result buffer reads in 0.11 ms. `GPUBatchSimulator.read_all_results` is that read
and returns raw ints, because `_get_results`' per-battle Dictionary building was
the measured cost of the existing readers. `RolloutHarness.run` returns the raw
per-slot records and stops — a harness that also ranked would make
[#896](https://github.com/timbermania/fft-monorepo/issues/896)'s H-sweep unable
to vary the scorer.

**7. Imperative-issue candidates are OUT, with a reason and not a shrug.** §7's
third candidate family is a one-shot top-priority lock-on. A lock-on has to name
ONE unit, and no encodable target does: `TARGET_THEM` is the unit the condition
matched, not a unit the issuer chose, and `TargetSelector.PoolType.SPECIFIC_UNITS`
is in the encoder's UNSUPPORTED set (ADR-0023). The charge economy is #894's and
so is the target encoding it needs. `RolloutCandidates` gains a sixth family when
that lands; nothing else about the harness changes.

**8. No fleet is allocated by default and no size tunable is published.**
`CombatLoop.rollout_fleet_size` defaults to 0, which means one battle — the shape
every host in the tree has had since the simulator was written, and the shape
every host that never runs a rollout still wants. ADR-0237 dec. 8 is why: a
discovered ceiling belongs in an [ADR-0068](0068-tunables-bind-a-slug-to-a-code-default-with-a-coalescing-override-layer.md)
`static var` published by whoever wires the AI ([#897](https://github.com/timbermania/fft-monorepo/issues/897)),
and shipping a default here would ship a number nobody chose to every host,
paying its VRAM on a box where a lost Vulkan device is how the suite fails.

## Rejected

**A widened `1 + K` simulator with a per-battle active mask.** §7 names it as the
upgrade for Active mode, where a rollout would have to overlap live play. It buys
nothing while the turn is frozen, and it costs a shader change plus a mask every
stage has to honour. Decision 1 is the cheaper design *because* the live battle is
frozen; when that stops being true, this is what replaces it.

**A CPU legality prefilter that mirrors the shader's pre-validates.** It would
prune more candidates, and every pruned candidate would be pruned on a
disagreement nobody could see. Decision 3.

**Compacting the gambit list on a delete.** The shader skips a disabled slot
rather than closing the gap, so a delete that also compacted would be a delete
AND a reorder — two edits presented as the one-step operator §7 specifies, and
the search would never be able to try either alone.

**Taking the first K candidates in family order.** The enumeration runs to a few
hundred at a realistic roster, so a K of 32 or 64 truncates it — and truncating
in family order spends every slot on `swap` and reaches no playbook posture at
all. The families are interleaved instead, so a small K drops the tail of every
family. §7's own degradation reasoning: bias is worse than variance.

## Consequences

- `GPUBatchSimulator` gains four accessors (`is_initialized`, `get_num_battles`,
  `get_units_per_battle`, `get_result_size`) and `read_all_results`. The
  accessors exist because the harness has to refuse a beat the fleet cannot hold,
  and it cannot refuse what it cannot see.
- **`RolloutHarness.run` refuses loudly and restores anyway.** An undersized
  fleet, an aliasing seed set or a malformed candidate returns `{}` — a beat that
  silently ran 12 of 64 candidates returns a confident recommendation drawn from
  a search that never happened. Every path that reached the fill restores battle
  0 before returning, because a rollout that leaves the player's battle 300 ticks
  in the future is not a wrong answer, it is a destroyed game.
- **FOUND: a candidate family can be ENUMERATED and never OFFERED, and the
  obvious test cannot see it.** `families()` enumerates and `FAMILIES`
  interleaves — two lists. Deleting `"playbook"` from `FAMILIES` makes that whole
  family unreachable through `generate` while `families()` still produces it: the
  search space silently shrinks and every candidate that survives is still valid,
  so nothing looks wrong. The first version of `RolloutCandidatesTest` walked
  `FAMILIES` to check family coverage, so **the seed deleted its own check** and
  the run was green. The enumeration's own keys are now the oracle, in both
  directions, and the interleave arm demands every family at
  `K = 1 + family count` rather than a threshold. Six other seeded defects
  (missing restore, transposed fill slot, off-by-one separation, no MP ceiling,
  no incumbent, editable safety net) each reddened only their own arms on the
  first try.
- **The transposed-fill seed is what justifies the per-slot addressing arm.**
  Writing candidate `k` / seed `m` into slot `m*K+k` instead of `k*M+m` left the
  bit-identity arm green (the restore still ran) and the CRN-identity arm green
  (a 2x2 fleet transposes symmetrically). Only the arm that reads each slot's
  header seed and gambit image back caught it.
- **The playbook's postures are a floor, not a design.** They are plausible and
  they are guarded for encodability; none of them is calibrated, because nothing
  can calibrate them until #896 has a value function. The set is meant to grow.
- No production caller exists. #897 wires the beat to a turn and sizes the fleet;
  #896 ranks what the beat returns. This ticket's deliverable is the machine and
  its guards.
