# `reconfigure` is an overlay, and the shader-write set classifies the fields

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §2 calls its keystone "a lossless
state ⇄ config round-trip" and gates it on one bit-identity test. Building it
found the framing wrong twice over, in ways that change what got built.

**There is no round trip.** `UNIT_CONFIG_SCHEMA`
([ADR-0003](0003-unit-encode-is-a-single-looped-schema.md)) already partitions
the 101-int unit block: 45 offsets are config-derived and 56 are hand-written
init constants, and those 56 are *exactly* the live combat state (`cast_timer`,
`anim_*`, `status_timer_0..7`, `decision_meta`, `current_gambit`, `move_step_id`,
…). `_extract_unit_config` reads a **CPU-side `Unit` node**, not the GPU buffer —
there is no `buffer → config` direction anywhere in the tree. So the second half
of the design's round trip is not lossy; it does not exist. What §4's
"all adjustment types legal" actually needs is an **overlay**: write the
config-derived offsets onto a live block and leave the rest alone.

**And "RNG stream position", which §2 requires the round trip to cover, is not
state.** `rand_int` (`src/gpu/shaders/combat_common.glslinc`) is a *stateless*
PCG hash of `(battle_seed, unit_id, tick)`. Determinism follows from the battle
header, which is already inside the captured slice.

Both §2 clauses are wrong. Its conclusion — build this first, gate it on
bit-identity — stands, and is what the two primitives below are gated on.

## Status

accepted

## Decisions

**1. Two primitives, not one: `snapshot`/`restore` (bytes ⇄ bytes) and
`reconfigure` (a selective write).** They have different correctness criteria and
one test cannot see both. `snapshot_battle` / `restore_battle` on
`GPUBatchSimulator` capture and reinstall a battle; `reconfigure_unit` overlays a
fresh config onto a unit that is already fighting. Both sit on the
simulator/packer layer and on no host, so `GPUArena`, GambitBattle, the rollouts
and the tests inherit them.

**2. `UNIT_CONFIG_SCHEMA` membership *is* the field classification.** Not a table
in this ADR, not a generated list beside `gen_gpu_layout.py`. Config-derived = has
a schema row; live = does not. `unit_buffer_coverage_problems()` already proves
the two sets partition all 101 offsets, so a parallel table would be a second
drift surface — precisely what ADR-0003 exists to prevent.

**3. Each schema row declares a behaviour: `recompute` | `clamp` | `carry`,
and a row without one is a boot error.** A blind overlay corrupts live rows that
are config-derived *at boot* and live *mid-battle*, so an unguarded job change
would teleport the unit to its deployment tile at full HP. `clamp` keeps the live
value and clamps it to the freshly recomputed ceiling named by `clamp_to` — §4's
"clamp to the new max, never scale", because scaling makes toggling a +HP item a
free heal. `carry` leaves the live value alone. The 56 non-schema offsets are
`carry` implicitly. The column is **required**, not defaulted: a newly added
config-derived field that forgot to answer would silently reset itself on the
player's first job change, and forcing the answer is the whole point.

The current split is 27 `recompute`, 16 `carry`, 2 `clamp` over 45 rows.

**4. The classification's floor is derived from the SHADER, not audited by
hand.** `shader_written_unit_fields()` scans `write_unit(battle_id, unit, U_X, …)`
call sites out of `src/gpu/shaders/`, and `overlay_behaviour_problems()` errors if
any field in that set is classified `recompute`: a field the kernel writes during
a battle is live state by definition. It runs at boot beside the other two
ADR-0003 nets and as an arm of `UnitEncodeSchemaTest`. The scan currently finds
**57** written fields.

This is not decoration. A hand-audit of the design's own list produced `pos_*`
and `status_flags_*`; the scan added three more the audit had missed:

- **`pending_heal_target` / `pending_heal_amount`** — written by the deferred-heal
  path and read back by `apply_pending_heal`.
- **`wp` and `s_ev`** — zeroed by **Break Weapon / Break Shield**
  (`combat_combat.glslinc`, formula 37). Under `recompute` a broken weapon would
  be silently repaired by any job or equipment change.

The rule is one-sided on purpose: shader-written implies *not* `recompute`, but a
field the shader never writes may still be `carry`. `height` is: its extractor
reads the CPU-side cell, which is stale the moment the unit moves. (It is also,
since [ADR-0224](0224-the-gpu-battle-mover-addresses-a-cell-so-the-map-is-two-planes-and-the-unit-carries-its-level.md)
dec. 6 moved single-target attacks onto `get_tile_height(x, z, level)`, read by
**nothing** in the kernel — recorded here because the next reader will wonder.)

**5. `wp` and `s_ev` are `carry`, so a broken weapon stays broken.** Forced by
decision 4, and the conservative half of a genuine trade-off: `carry` means
equipping a *different* weapon does not change `wp` either. Whether an equipment
change repairs a break is an adjustment rule, not a classification one, and it is
[#894](https://github.com/timbermania/fft-monorepo/issues/894)'s to settle;
what this ADR refuses is the *silent* repair.

**6. A snapshot captures four slices, and the ping-pong cursor is not one of
them.** Battle state lives in four SSBOs, and three of them are outside the
battle slice: the single-buffered cooldown SSBO
([ADR-0047](0047-real-time-ability-cooldown-is-a-per-ability-floor.md)), the gambit
SSBO, and the 4-int result record. The gambit slice is `readonly` to the shader,
which is exactly *why* it is captured — it is what the player edits, so
undo-on-cancel is meaningless without it, and a rollout candidate **is** a gambit
edit.

Only the **current** ping-pong half is captured, and `restore` writes that one
image into **both** halves. The other half carries nothing into the future:
`compute_unit_state` opens every tick with `copy_header_to_next` +
`copy_unit_to_next`, both total over their whole record, so the write half is
fully overwritten from the read half before anything else runs. Capturing both
halves would instead force `_current_buffer` into the snapshot — and that cursor
is **global to the batch**, so a per-battle restore carrying it would corrupt
every other battle running alongside. This is what makes forking battle 0 into
candidate slots 1..K safe.

**7. `restore_battle` takes a target battle id, and the snapshot is plain data.**
`restore_battle(k, snapshot_battle(0))` is how §7 forks; reading the id back out
of the snapshot would have made that impossible. The dict is plain
`PackedInt32Array`s so a caller can edit `battle[BattleHeaderField.SEED]` before
restoring, which is how §7 spaces its Common-Random-Numbers seeds — the stateless
RNG hashes `battle_seed + unit_id*1000 + tick`, so adjacent seeds alias each
other's draws. `restore_battle` validates `units_per_battle` / `unit_size` /
`shader_version` and refuses a mismatch loudly.

**8. Two test layers, because neither is sufficient alone.**
`GPUBattleSnapshotTest` runs the §2 gate on a real battle;
`UnitEncodeSchemaTest` (pure, no GPU) runs the classification exhaustively.

The GPU arms run the seed-locked 4v4 from `GPUSeedReproTest`, **re-gambited to
cast** — every ability carries `cooldown_ticks: 300`, so a spell gambit is what
puts live state in the cooldown SSBO at all; with attack-only gambits that slice
stays zero and the arm covering it would pass vacuously. The arms report the
nonzero count of each captured slice for that reason.

- **A. Slice identity** — `snapshot → restore → snapshot` returns the same four
  slices.
- **B. Bit-identity (the gate)** — reference N ticks from the snapshot point,
  restore, run N again, compare all 101 fields of all 8 units plus all four
  slices. **N is odd (181)**, so the second run starts on the *opposite*
  ping-pong half.
- **C. No-op identity** — reconfigure with an *unchanged* config at an arbitrary
  mid-battle tick; all 101 offsets byte-identical.
- **D. Job change** — the `recompute` set moved, the `clamp` set clamped, the
  `carry` set and every non-schema offset did not, driven off the schema rather
  than a hand-list.

**Arm A is strictly weaker than arm B, and the seeded defects prove it.** With
`restore` writing only half 0, arm A passes and arm B fails
(`unit=0 field=cast_timer: straight-through=90, via restore=88`). With the
cooldown slice dropped from `restore`, arm A passes again and arm B fails
(`unit=1 field=aoe_pending_caster: 5 vs -1`) — a no-tick restore-then-snapshot
reads back the unrestored slice, which still equals the source. The odd tick
count in arm B is load-bearing, not decorative.

**A real battle only diverges the fields it happens to touch**, so arm C cannot
see a misclassified field the battle never moved — a 4v4 that never breaks a
weapon would not have noticed `wp`. That is why the exhaustive half is pure:
`UnitEncodeSchemaTest` arm 6 saturates all 101 offsets with a distinct sentinel,
overlays a known config, and asserts `recompute` took the config value, `clamp`
kept the live value under the new ceiling, and `carry` plus every non-schema
offset kept its sentinel — including an assertion that the clamp actually **bit**,
so the arm cannot pass by clamping nothing.

## Considered options

- **One primitive gated on one test (the design's §2), rejected.** A raw
  snapshot/restore test cannot see an overlay's failure mode, and the overlay has
  no bytes-to-bytes criterion to be gated by. Shipping them as one would have
  meant shipping the bit-identity arm and calling the classification proved.
- **A behaviour table in this ADR, or generated beside `gen_gpu_layout.py`,
  rejected** (decision 2). ADR-0003's whole argument is that a second list of the
  same field set is a drift surface.
- **`recompute` as a silent default for a row that declares nothing, rejected**
  (decision 3). It is the friendlier default and it is exactly the wrong one: the
  failure it produces is a silent reset the player reads as "my unit lost its
  cooldowns when I swapped a hat."
- **Reusing `set_battle_units` for the overlay, rejected.** It is the existing
  config→GPU path and it writes the whole block, resetting all 56 live offsets to
  their init constants. Correct out of combat, where nothing is live; mid-battle
  it drops the unit's cast, animation, status timers and cooldowns.
- **Capturing both ping-pong halves, rejected** (decision 6). It buys nothing the
  kernel's own per-tick copy does not already guarantee, and it drags the global
  `_current_buffer` into a per-battle artifact.

## Consequences

- `GPUCombatPacker` gains `BEHAVE_*`, `overlay_unit_config`,
  `shader_written_unit_fields` and `overlay_behaviour_problems`; every
  `UNIT_CONFIG_SCHEMA` row gains `behave` (and `clamp_to` on the two clamp rows).
  `GPUBatchSimulator` gains `snapshot_battle`, `restore_battle`,
  `reconfigure_unit`, `reconfigure_unit_from`, and a third boot net beside the
  ADR-0003 pair.
- **The schema is now the classification, so adding a unit field is a decision,
  not an append.** A new `U_*` field still means "append at the next index, bump
  `SHADER_VERSION` and `UNIT_SIZE`, run the generator" — but a new *config-derived*
  one must also say what a mid-battle reconfigure does to it, and the boot net
  refuses to start without an answer.
- **`overlay_behaviour_problems()` reads the shader source at run time.** An
  empty scan is reported as an error, not as clean, so an unreadable shader
  directory cannot turn the guard inert.
- **The design doc's §2 is superseded by this file on two clauses** — the round
  trip and the RNG stream — and its conclusion is honoured. The doc is the input
  to the build map, not a record of it; it is not edited.
- Downstream, [#895](https://github.com/timbermania/fft-monorepo/issues/895) owns
  seed spacing on top of decision 7, [#894](https://github.com/timbermania/fft-monorepo/issues/894)
  owns the break-repair rule left open by decision 5, and #891's cancel path is
  `restore_battle` with the snapshot taken at freeze.
