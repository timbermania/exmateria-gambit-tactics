# GPU movement interpretation is a pure module; the snapshot reader stays

`GPUVisualBridge` read the raw GPU movement fields (`prev_move_pos`,
`move_step_id`, `move_total_ticks`, `timer`) and **derived** the new-step /
continuing / stale-retry classification inline, in the middle of its
position-applying loop. The classification carries the system's trickiest
invariant — the `timer <= total_ticks` guard that rejects the GPU's retry/wait
timer, plus per-unit cross-frame `move_step_id` memory — yet it could not be
exercised without a `RenderingDevice`, real tiles, and live `Unit` nodes.

We extract that interpretation into `GPUMovementInterpreter` (pure
`RefCounted`), leaving `GPUVisualBridge` to *apply* the result. We do **not**
delete `GPUStateReader`, which an architecture review had flagged as a
pass-through.

## Status

accepted

## Decision

- **`GPUMovementInterpreter` owns the interpretation.** It holds the per-unit
  `move_step_id` memory and answers one question per unit per frame —
  `classify(unit_index, state) -> MoveStep{kind, …}` where `kind` is
  `NEW_STEP` / `CONTINUING` / `NO_MOVE`. The `timer <= total_ticks` staleness
  guard, the origin-unpack, and the real-displacement check all live here. It
  reads only the string-keyed snapshot Dictionary and holds one int per unit —
  no terrain, no `Node`, no scene-tree handle — so a test drives it exactly as
  the bridge does.
- **`GPUVisualBridge` becomes apply-only.** It `match`es on `step.kind`:
  builds a visualizer from the interpreter's grid coords (resolving tiles —
  the bridge's terrain concern), follows an existing visualizer, or clears a
  stale one and snaps to tile. `_clear_movement_state` now calls
  `_interp.forget(i)`, absorbing the old `_active_move_step_id` erase.
- **The snapshot stays a string-keyed Dictionary (ADR-0002 unchanged).**
  `MoveStep` is a **derived** value (grid coords + ticks + step id), not a
  typed mirror of the 85-field snapshot. ADR-0002 rejected a typed *view over
  the snapshot*; this introduces no such view and re-litigates nothing. The
  attractive-form note in ADR-0002 ("a view *generated* from the layout,
  backed by the buffer") is still the standing answer for the snapshot itself.
- **`GPUStateReader` is retained.** The review called it a pass-through, but
  the deletion test says keep it: it curries `battle_id` across ~30 call sites
  (`GPUCombatTestBase` + ~25 test subclasses + `GPUArena`). Deleting it makes
  `battle_id` reappear threaded through every `get_battle_unit_states(0)` /
  `is_battle_finished(0)` / `get_battle_result(0)` call — complexity
  re-spread, not removed. A thin reader that applies one argument across a
  whole suite is not a pure pass-through.

## Consequences

- The new-step detection and the staleness guard are unit-tested in isolation
  (`tests/GPUMovementInterpreterTest.gd`) — the failure modes CLAUDE.md warns
  about ("stale GPU state fields", a visualizer reactivating as the retry timer
  counts back into range) now have regression coverage that needs no GPU.
- `GPUVisualBridge`'s remaining job — death/grounding, visualizer follow,
  animation/facing, position — is the only thing left in its loop that touches
  the scene; the movement *decision* is no longer entangled with it.
- Recorded so a future review neither re-suggests a typed snapshot view (see
  ADR-0002) nor re-flags `GPUStateReader` as a deletable pass-through (the
  battle_id currying is the reason it stays).
