# Combat unit-state snapshot stays a string-keyed Dictionary

`GPUBatchSimulator.get_battle_unit_states()` returns `Array[Dictionary]` with
string keys (`state["hp"]`, `state.get("timer", 0)`), read at ~176 sites. We
deliberately keep it that way rather than introducing a typed view object
(`UnitStateView` with named fields) — the safety a typed view would add is not
achievable in GDScript without a cost out of proportion to the residual risk.

## Status

accepted

## Considered options

- **String-keyed Dictionary (chosen).** The keys are generated from the
  [combat buffer layout](../context/02-combat-buffer-layout.md) (`SNAPSHOT_FIELDS`, one per
  `UnitField`), so they can't drift from the offsets and every field is always
  present.
- **Typed view object** (`view.hp` instead of `state["hp"]`). Rejected — see
  below.

## Why a typed view isn't worth it here

- The high-value failure mode — a consumer reading a key the builder forgot to
  include — was already eliminated by generating *all* 85 fields into the
  snapshot. Every real field is always present.
- The only residual risk is **key typos**. In GDScript a typed view catches
  those at parse time *only* when (a) the view declares 85 explicit typed
  members and (b) every consumer holds a **typed local** (`var s: UnitStateView
  = ...`). Today all ~176 read sites use untyped locals, so realizing the
  safety means migrating every site *and* annotating it — and the guarantee is
  only ever as strong as the weakest unannotated consumer (`var s = states[i]`
  silently opts out of all checking).
- The per-frame `Dictionary` allocation (the one durable, discipline-independent
  win a buffer-backed view would offer) has not shown up as a performance
  problem.

## Consequences

- Reconsider only if profiling shows the per-unit-per-frame dict allocation
  matters, or if a typo class bug actually bites. If revisited, the attractive
  form is a view *generated* from the same layout (not a hand-maintained
  mirror) and backed by the packed buffer.
- Recorded so architecture reviews don't re-flag the string-keyed snapshot as a
  deepening opportunity (it was flagged once; this is the standing answer).
