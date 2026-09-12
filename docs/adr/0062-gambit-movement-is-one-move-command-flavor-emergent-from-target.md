# Gambit movement is one `MOVE` command; its flavor is emergent from the target

## Status

accepted

## Context

`Gambit.ActionKind` carried three movement verbs — `MOVE`, `RETREAT`,
`APPROACH` — that the editor offered but `GambitEncoder` could not project
(they sat in `UNSUPPORTED_ACTION_KINDS`, so authoring one skipped the gambit
with a `push_error` under faithful-or-explicit, [ADR-0023](0023-gambit-gpu-projection-stays-in-encoder-faithful-or-explicit.md)).
Issue #37 was the fork: wire them, or remove them.

The verbs turned out to be the wrong shape. The gambit vocabulary targets a
**unit** ("do X on the unit that …"); movement is fundamentally about
**position**, which the vocabulary had no way to name. Worse, "retreat" has no
single referent — a corner, a near ally, a far ally, away from the nearest
enemy are all different behaviors — so it cannot be one command. Meanwhile the
GPU already had a working absolute-tile move (`ACTION_MOVE_TO`, `action_id`
packs `x*256 + z`), exercised through a back door (`GPUCombatTestBase.make_move_to_gambit`,
~12 tests) that bypasses `Gambit` + `GambitEncoder` entirely.

## Decision

- **One movement command: `ActionKind.MOVE`.** `APPROACH` and `RETREAT` are
  **deleted from the enum**. "Approach", "retreat", "regroup", "relocate" are
  *emergent* descriptions of a (target, condition) pattern a player composes —
  not verbs the engine blesses. "Retreat" specifically is **not** encodable as
  one command (it has no canonical meaning); the player picks the target that
  means retreat to them.
- **The move's target carries a destination anchor — unit or tile.** See the
  `Move (the movement command)` glossary entry in [CONTEXT.md](../context/02-combat-buffer-layout.md).
- **Phase 1 (this issue) wires unit-anchored moves only.** A `Gambit`'s `MOVE`
  is always unit-anchored; `action_target` stays a plain `TargetSelector`. The
  encoder learns exactly one new mapping — `MOVE` + a unit `TargetSelector` →
  the GPU move-toward-unit primitive — and `MOVE` comes off
  `UNSUPPORTED_ACTION_KINDS`. `MOVE` inherits the same supported/`UNSUPPORTED`
  resolution set as every other action because it reuses
  `_target_selector_to_gpu(action_target)`.
- **A new GPU primitive `ACTION_MOVE_TO_UNIT`** resolves the target unit at
  runtime, re-paths each decision as the unit relocates, **stops adjacent**
  (or where no closer tile is reachable) into `LOGICAL_ACTIVITY_IDLE` + gambit re-eval,
  and **never attacks** — acting stays the job of `ATTACK`/`ABILITY` gambits, so
  "approach then strike" is two composed gambits. Added shader-side and
  regenerated into `GPUConstants` per [ADR-0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md).
- **The absolute-tile path is untouched.** `ACTION_MOVE_TO` keeps meaning
  "absolute coords in `action_id`". Absolute-tile moves remain a *program-built
  command* (raw pre-encoded config, bypassing domain + encoder) — the channel
  for instructions that transcend the AI. The gambit **editor authors only
  unit-anchored moves** ("Move" + the existing To/Prefer/Team unit pickers;
  "Retreat" is dropped, pairing with #33).

## Considered options

- **Three co-equal movement verbs (`Approach`/`Retreat`/`Move` as
  `ActionKind`s).** Rejected: the flavor is fully expressed by *which target*
  the one `MOVE` steers toward, so distinct verbs are redundant — and "retreat"
  has no single referent to encode.
- **Retreat as a relational tile selector (`farthest-from-enemy`).** Rejected:
  needs a battlefield/distance-field scan that does not exist, and it *is* the
  over-broad retreat the model refuses to pin. A genuine threat-aware flee
  primitive is an explicit future option, not a planned phase.
- **Repurpose `ACTION_MOVE_TO` to branch on `action_target_type`** (one unified
  GPU move). Rejected: breaks the absolute back door (which signals absolute via
  a meaningless `TARGET_SELF` placeholder) and forces a tile-target enum
  (`TARGET_TILE_ABSOLUTE`) into this pass. A second GPU primitive is cheap under
  ADR-0001 — one *domain* verb does not require one *GPU* primitive.
- **Build a domain tile-target type now** so absolute commands flow through the
  encoder. Deferred: absolute-tile stays a raw command dict until tile targeting
  is designed properly.

## Consequences

- **Tile-*targeted* gambit authoring is a roadmap item with its own
  grill-with-docs** — the tile-selector vocabulary (specific tile, corner,
  highest/lowest by elevation, within-X radius, …) and the combat-UI surface to
  author it. Tracked as a follow-up issue. Until then, tile-anchored moves are
  program-only.
- **`MOVE` becomes a mapped value** the ADR-0023 completeness test covers; the
  `UNSUPPORTED_ACTION_KINDS` entry for movement is removed.
- **Legacy saves** that stored the `"Approach"`/`"Retreat"` action *names*
  (`Gambit.from_dict` legacy path) migrate: `Approach → MOVE`; `Retreat` has no
  faithful target, so it degrades to the default (`WAIT`).
- **The editor↔engine vocab drift #37 named dissolves** — there is one `MOVE`,
  and movement intent is composed from targets, so the editor cannot offer a
  movement verb the engine can't run.

## See also

- The `LOGICAL_ACTIVITY_APPROACHING` Logical activity carries this
  reposition-without-attack contract end-to-end through the
  [activity taxonomy](../context/18-sprite-layers.md)
  (source: `tools/activity_taxonomy.yaml`). It's deliberately distinct
  from `LOGICAL_ACTIVITY_WALKING` so `handle_moving_state`'s opportunistic
  attack never fires for a pure reposition.
