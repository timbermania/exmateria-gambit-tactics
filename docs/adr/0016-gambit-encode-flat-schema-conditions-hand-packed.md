# Gambit→buffer encoding loops a flat schema; the condition block stays hand-packed

`set_unit_gambits` hand-wrote each `GambitField` offset
(`data[off + GambitField.ENABLED] = …`, ~10 lines) while the unit path
loops a single `UNIT_CONFIG_SCHEMA`
([ADR-0003](0003-unit-encode-is-a-single-looped-schema.md)). The gambit
dict keys are typed twice — once where `GambitEncoder` builds the encoded
dict, once where `set_unit_gambits` reads it back with `g.get("key", …)` —
the same silent-missing-key drift ADR-0003 removed on the unit encode, still
live on the gambit encode. We replace the flat hand-writes with a looped
`GAMBIT_CONFIG_SCHEMA`, split packing from upload, and add a whole-buffer
completeness check.

## Status

accepted

## Decision

**`_pack_gambits` loops a flat `GAMBIT_CONFIG_SCHEMA` for the five plain fields,
hand-packs the derived count and the repeated condition block, and a whole-buffer
completeness check asserts the two together cover every offset.**

The rules below were decided by this ADR but were only ever stated as prose — in
the chosen option and in the Consequences bullets. They are numbered here on
2026-08-28 so `ADR-0016 dec. N` is a checkable citation; each names the section
that carries its evidence. Nothing is added and nothing is retired by the
numbering.

1. **The flat fields loop one table.** A `GAMBIT_CONFIG_SCHEMA` of
   `{key, field, default}` rows covers `enabled`, `cond_target_type`,
   `action_type`, `action_id`, `action_target_type`; the write loop emits each
   as `int(g.get(row.key, row.default))`. (Considered options, "Flat schema +
   completeness net (chosen)".)

2. **The schema/hand-packed line is ADR-0003's line.** A value that is a plain
   `g.get` goes in the schema; a value that is *derived* (`COND_COUNT`, from
   `conditions.size()`) or *repeated* (the indexed `COND_TYPE_*`/`COND_VAL_*`
   block) stays hand-written. Modelling the condition block in the schema is
   rejected: a row type expressing "repeated four times, indexed" plus
   "count derived from array length" buys a more complex schema for no added
   safety. (Considered options, the chosen bullet and the first rejected one.)

3. **The schema is a `const`, not a `static var`.** Its rows carry no `extract`
   Callable — the value is always a plain read from the already-encoded dict —
   which is what distinguishes it from its unit sibling. (Considered options,
   end of the chosen bullet.)

4. **Honest scope: this de-duplicates the write side only, and that is
   accepted.** `GambitEncoder` is branchy and cannot loop a table, so the
   `GambitEncoder`-keys ↔ schema-keys drift is *not* auto-closed. Coupling the
   encoder to the schema would fight its transformation logic. (Consequences,
   bullet 1. The producer-side complement is
   [ADR-0023](0023-gambit-gpu-projection-stays-in-encoder-faithful-or-explicit.md).)

5. **Packing is split from upload.** A pure `static _pack_gambits(gambits) ->
   PackedInt32Array` fills the array; the caller uploads it. This mirrors the
   unit path's fill/upload separation and is what lets the round-trip test run
   with no `RenderingDevice`. (Consequences, bullet 2.)

6. **The completeness check is whole-buffer, and deliberately stronger than the
   unit side's.** `gambit_config_schema_problems()` asserts every offset in
   `[0, GAMBIT_SIZE)` is written exactly once — by the schema, by the declared
   hand-packed set, or by the declared reserved set. Mirroring the unit
   duplicate-offset check alone is rejected: it would miss the dominant failure
   mode here, adding a `GambitField` and forgetting to pack it, which silently
   leaves it zero. (Considered options, third bullet; Consequences, bullet 3.)

7. **The table lives beside its unit sibling, not in a new module** — consistent
   with [ADR-0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md)
   dec. 4's deferral of a standalone layout module. (Consequences, bullet 4.)

8. **Two nets, and no warning tier.** A boot-time
   `_validate_gambit_config_schema()` beside the unit one, `push_error` on any
   problem — there are no knowingly-dormant gambit fields, so every problem is a
   real error — plus a pure suite round-trip test that needs no
   `RenderingDevice`. (Consequences, bullet 5.)

9. **Behavior is unchanged by the refactor.** The schema defaults match the
   former inline `g.get(…, default)` calls, the condition block is packed as
   before, and a disabled or absent slot stays fully zero. (Consequences,
   bullet 6.)

## Considered options

- **Flat schema + completeness net (chosen).** A `const GAMBIT_CONFIG_SCHEMA`
  of `{key, field, default}` rows for the five *flat* fields (`enabled`,
  `cond_target_type`, `action_type`, `action_id`, `action_target_type`);
  `_pack_gambits` writes each as `int(g.get(row.key, row.default))`.
  `COND_COUNT` (derived from `conditions.size()`) and the
  `COND_TYPE_*/COND_VAL_*` block (a repeated, index-arithmetic write) stay
  hand-packed — the **same separating line** ADR-0003 drew when it left the
  status-timer bit-packer out of the unit schema: a value that is a plain
  `g.get` goes in the schema; a value that is *derived* or *repeated* stays
  hand-written. Because the rows carry no `extract` Callable (the value is
  always a plain read from the already-encoded dict), the schema is a `const`,
  not a `static var` like its unit sibling.
- **Model the condition block in the schema too.** Rejected: a row type that
  expresses "repeated four times, indexed" plus "count derived from array
  length" reinvents exactly the complexity ADR-0003 deliberately kept out of
  the unit schema, buying a more complex schema for no added safety on the
  one structured part.
- **Mirror the unit duplicate-offset check only.** Rejected: the unit check
  never verified that the schema *covers* the buffer; it only rejects
  duplicate offsets and missing extractors. That would miss the dominant
  failure mode here — adding a `GambitField` and forgetting to pack it, which
  silently leaves it zero. The dense gambit buffer (no dormant fields, no init
  constants) makes a whole-buffer completeness net cheap, so we take the
  stronger check instead of the weaker mirror.
- **Leave it hand-written.** Rejected: it preserves the unit/gambit asymmetry
  and gives the input path that decides how every unit acts no machine-checkable
  guarantee that all of its fields are written.

## Consequences

- **Honest scope: a write-side schema, not the two-sided drift-killer
  ADR-0003 got.** ADR-0003's schema was strong because *both* sides loop it —
  `_extract_unit_config` fills the dict via per-row Callables and
  `_write_unit_data` writes via per-row offset. The gambit producer,
  `GambitEncoder`, is branchy (string→enum maps, `TargetSelector`→enum,
  ability-name lookup) and **cannot** loop a table — the same reason ADR-0003
  rejected *generating* the extract side. So `GAMBIT_CONFIG_SCHEMA`
  de-duplicates only the **write** side; the `GambitEncoder`-keys ↔
  schema-keys drift is **not** auto-closed. We accepted that rather than
  couple the encoder to the schema, because forcing the encoder to loop a
  table fights its transformation logic. The win is real but narrower than
  the unit case: the write loop is data-driven, and completeness is
  machine-checked.
- **Packing is split from upload.** `set_unit_gambits` previously packed *and*
  uploaded (`_rd.buffer_update`) in one function. It now calls a pure
  `static _pack_gambits(gambits) -> PackedInt32Array` and uploads the result —
  mirroring the unit path's `_write_unit_data` (fills an array) / upload
  separation. The pure pack step is what lets the round-trip test run with no
  `RenderingDevice`.
- **The completeness check is stronger than the unit side**, by design:
  `gambit_config_schema_problems()` asserts every offset in
  `[0, GAMBIT_SIZE)` is written exactly once — by the schema, the declared
  `_GAMBIT_HAND_PACKED` set (`COND_COUNT` + the 8 condition slots), or the
  declared `_GAMBIT_RESERVED` set (offsets 14–15). `GambitField` itself is
  generated from the shader
  ([ADR-0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md)), so
  the *offsets* can't drift from the shader; this net guards that the CPU
  writer *covers* them.
- **The table lives in `GPUBatchSimulator.gd`** beside `set_unit_gambits` and
  next to `UNIT_CONFIG_SCHEMA` / `unit_config_schema_problems` — consistent
  with ADR-0001's deferral of a standalone layout module.
- **Enforcement mirrors ADR-0003's two-net philosophy.** A boot-time
  `_validate_gambit_config_schema()` runs beside `_validate_unit_config_schema()`
  (`push_error` on any problem — there are no knowingly-dormant gambit fields,
  so every problem is a real error, no warning tier), plus a pure suite
  round-trip test (`GambitEncodeSchemaTest`: `dict → _pack_gambits → read back
  by GambitField offset`) that needs no `RenderingDevice`.
- **Behavior is unchanged.** The flat defaults match the former inline
  `g.get(…, default)` calls (`enabled` still defaults to true, the target/action
  defaults to their former `GPUConstants.*`), the condition block is packed as
  before, and a disabled or absent slot stays fully zero.

## Amendment 1 — every decision holds; the host file moved and one comment beside it drifted

Graded 2026-08-28 against the code and the suite. This ADR is **built and enforced**,
decision by decision:

| dec | where it is now | held? |
|---|---|---|
| 1 | `GPUCombatPacker.GAMBIT_CONFIG_SCHEMA` — exactly the five rows, exactly the five defaults | yes |
| 2 | `_GAMBIT_HAND_PACKED` = `COND_COUNT` + 4 `COND_TYPE_*` + 4 `COND_VAL_*`; `_pack_gambits` writes them with `mini(conditions.size(), 4)` and index arithmetic | yes |
| 3 | `const GAMBIT_CONFIG_SCHEMA :=` (the unit sibling at `GPUCombatPacker.gd:327` is still `static var UNIT_CONFIG_SCHEMA`) | yes |
| 4 | still true — `GambitEncoder` still transforms rather than loops; ADR-0023 carries the producer side | yes |
| 5 | `static func _pack_gambits(...) -> PackedInt32Array`, called from `GPUBatchSimulator.set_unit_gambits` which does the `_rd.buffer_update` | yes |
| 6 | `gambit_config_schema_problems()` walks `range(GAMBIT_SIZE)` and reports every unwritten offset; `_GAMBIT_RESERVED` is still `RESERVED_14`/`RESERVED_15` and `GAMBIT_SIZE` is still 16 | yes |
| 7 | see below — the *module* rule holds, the *filename* moved | partly |
| 8 | `GPUBatchSimulator._validate_gambit_config_schema()` (`push_error`, no warning tier) + `GambitEncodeSchemaTest`, wired in `tests/run_all_tests.sh` | yes |
| 9 | not re-derivable from the tree — see below | unmeasured |

### Decision 7: the sibling rule held through a move the ADR could not have named

Consequences says the table lives in **`GPUBatchSimulator.gd`**, "beside
`set_unit_gambits` and next to `UNIT_CONFIG_SCHEMA`". The schema, the completeness
check and `_pack_gambits` all now live in **`src/gpu/GPUCombatPacker.gd`** — the same
host move that relocated ADR-0001's generated region. The rule decision 7 actually
states survived it intact and arguably came out ahead: `UNIT_CONFIG_SCHEMA`
(`:327`), `unit_config_schema_problems` (`:403`), `GAMBIT_CONFIG_SCHEMA` (`:699`) and
`gambit_config_schema_problems` (`:719`) are now **all four in one file**, so "next to
`UNIT_CONFIG_SCHEMA`" is *more* true than when it was written. Only "beside
`set_unit_gambits`" broke: that function stayed at `GPUBatchSimulator.gd:1245` and now
calls across. No standalone layout module was created, which is the part
[ADR-0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md) dec. 4 deferred.

### The drift class this ADR kills, surviving in a comment

`GPUCombatPacker.gd:686` reads:

```gdscript
const GAMBITS_PER_UNIT = MAX_GAMBITS * GAMBIT_SIZE  # 80 ints per unit
```

The **value** is correct and cannot drift — `MAX_GAMBITS` and `GAMBIT_SIZE` both come
from `GPUConstants`, generated from the shader, where `MAX_GAMBITS = 6` (5 authored +
1 encoder-injected safety net, ADR-0048) and `GAMBIT_SIZE = 16`, so the constant is
**96**. The **comment** says 80, the answer from when `MAX_GAMBITS` was 5. The shader's
own comment on the same quantity (`combat_common.glslinc:614`) says 96. Nothing is
broken; it is worth naming only because it is this ADR's own failure mode — a
hand-maintained copy of a generated number going quietly stale — surviving one layer
out, in prose no net reads.

### Decision 9 is not re-derivable, and that is a limit of the audit, not a finding

"Behavior is unchanged" is a claim about the pre-refactor code. The current tree can
show that the defaults are `true` / `TARGET_NEAREST_ENEMY` / `ACTION_ATTACK` / `0` /
`TARGET_THEM` and that an absent slot stays zero (`PackedInt32Array` zero-init, and
`GambitEncodeSchemaTest` asserts it) — but it cannot show those match what the deleted
inline `g.get(…)` calls used. Read decision 9 as a statement about the commit that
landed this ADR, not as an invariant a later reader can re-check.
