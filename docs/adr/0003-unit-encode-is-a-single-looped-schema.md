# Unit→buffer encoding is one looped schema with a per-field `live` flag

Getting a live `Unit` into the [combat buffer layout](../context/02-combat-buffer-layout.md)
happened in two hand-written functions joined by an implicit string-keyed
`unit_config` dict: `_extract_unit_config()` *produced* the keys, and
`_write_unit_data()` *consumed* them with ~36 separate
`unit_config.get("key", default)` reads. The key set was typed twice and
matched by eye, and every read carried a fallback — a missing, renamed, or
forgotten key silently substituted a stat default (`100` HP, `50` brave,
`-1` reaction) with no error. That is the same silent-missing-key failure
mode [ADR-0002](0002-unit-state-snapshot-stays-string-keyed.md) eliminated
on the *output* snapshot, still live on the *input* path — the path that
decides who fights with which numbers. We replace the two parallel lists
with a single `UNIT_CONFIG_SCHEMA` table that both sides loop over.

## Status

accepted

## Considered options

- **Single looped schema (chosen).** One `static var UNIT_CONFIG_SCHEMA`
  whose rows carry `{key, field: UnitField.*, default, extract: Callable,
  live: bool}`. `_write_unit_data` writes each row
  (`data[offset + row.field] = unit_config.get(row.key, row.default)`);
  `_extract_unit_config` builds an extract context once, then fills the
  dict by calling each row's non-null `extract`. Key / offset / default
  exist once, so the producer and consumer cannot disagree about a key.
  Chosen because it mirrors what ADR-0002 already did for the snapshot
  (generate the key set so none can go silently missing), applied to the
  encode side, and because the test path is preserved unchanged.
- **Minimal: declare the key set, writer loops it, a test guards extract.**
  Same table minus the `extract` closures; `_extract_unit_config` stays
  hand-written, with a test asserting it covers the schema keys. Rejected:
  it kills writer↔schema drift but leaves the producer's keys hand-typed
  and only catches a dropped key at test time, not at the call site.
- **Generate the table from the layout, like `SNAPSHOT_FIELDS`.** Rejected:
  the snapshot keys are mechanically `member.lower()` of each `UnitField`,
  but the *input* key→value mapping is not mechanical — `wp` comes from
  `prog.get_weapon_power()`, `c_ev` from `_get_evade_breakdown()`,
  `weapon_flags` from a packed-bits loop. The extract logic knows the Unit
  API and is inherently hand-authored, so a generator cannot emit it.

## Consequences

- The table lives in `GPUBatchSimulator.gd` next to `_extract`/`_write`,
  **not** a new module — consistent with
  [ADR-0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md)'s
  explicit deferral of a standalone `GPULayout` module until a CPU-side
  simulator needs the offsets too. Because the `extract` rows hold
  Callables, it is a `static var` built once at load, not a `const`.
- **Scope is the simple config-derived fields only** (~22). Init-constants
  (`STATE = 0`, `TARGET = -1`, the `DBG_*` block) and the 8-slot
  status-timer bit-packer stay hand-written in `_write_unit_data`: they
  have no producer to drift against, so a uniform row type would buy a more
  complex schema for no safety.
- **`live` semantics.** A `live = true` row is one the production path is
  expected to supply today; the schema check fails (boot `push_error`) if
  such a row has a null `extract`, and a row carrying a `gap` note downgrades
  that to a warning instead. `reaction_ability` was the first such gap — the
  shader resolves it at damage time (counter, Blade Grasp / Arrow Guard in
  `stage_compute.glsl`) and the player equips it, but `_extract_unit_config`
  never set it, so a roster unit's equipped reaction silently did nothing in
  `GPUArena`. **Now wired:** `REACTION_ABILITY_TO_REACT` maps the 7
  shader-resolved reactions (Counter, Hamedo, AbsorbUsedMP, AutoPotion,
  BladeGrasp, ArrowGuard, MPSwitch) by ability id to their `REACT_*` enum;
  every other equipped reaction falls through to `REACT_NONE` and stays
  inert (no shader logic exists for it). `REACT_*` are not generated into
  GPUConstants, so the map mirrors `combat_common.glslinc` by hand. The `gap`
  mechanism remains for the next dormant-but-live field.
- **Status fields are intentionally dormant** (`live = false`). The shader
  can honor a pre-set status (berserk override) and self-applies
  `STATUS_CHARGING`, but there is **no ability→status infliction path** (no
  `status_id` on the ability layout) and no pre-combat status seed, so no
  roster `Unit` has status to carry yet. `support_ability` /
  `movement_ability` / `ability_flags` / `pending_heal_*` are likewise
  dormant or test-only.
- **Enforcement mirrors ADR-0001's two-net philosophy.** A boot-time
  `_validate_unit_config_schema()` (alongside the existing
  `_validate_shader_constants()`) asserts `live ⇒ extract != null` and
  unique keys/offsets for the edit-then-Play inner loop, plus a suite
  round-trip test (`dict → _write_unit_data → read back via
  SNAPSHOT_FIELDS`) that needs no `RenderingDevice`. The Python
  `gen_gpu_layout.py --check` cannot see a GDScript table, so the nets stay
  GDScript-side.
- The test path (`set_battle_units` with hand-built partial dicts, used by
  `GPUCombatTestBase` / `GPUSeedReproTest` / `StrategyPhaseTest`) is
  unchanged: absent keys still fall to `row.default`.
- **The schema and its checks moved into `GPUCombatPacker.gd`** (from
  `GPUBatchSimulator.gd`) when the buffer-layout region and unit/gambit
  packing were extracted into the packer; `GPUBatchSimulator` re-exports
  `SNAPSHOT_FIELDS` and calls the pure check functions from its boot validators.

## Amendment: write-completeness net over the whole unit record

The `live ⇒ extract` check above guards the *config-derived* rows, but it says
nothing about the rest of the buffer. A `UnitField` can gain an enum slot —
`gen_gpu_layout.py` adds it to the enum **and** to the generated
`SNAPSHOT_FIELDS`, so the *decode* side always sees it — while nothing writes it
on the *encode* side. `PackedInt32Array` zero-inits, so the field reads back a
plausible **silent zero** whose meaning may be wrong (this is not hypothetical:
`unit_buffer_coverage_problems()` caught `PENDING_ACTION_TYPE`, offset 84,
reading `0 = ACTION_ATTACK` where the field's dormant value is `ACTION_NONE = -1`
— benign only because `stage_compute` rewrote it each tick before use).

The unit buffer is in fact **fully dense**: every offset in `[0, UNIT_SIZE)` is
written by `_write_unit_data` — config-derived rows via the schema loop,
everything else (init constants, the `DBG_*` block, the status-timer packer,
reserved slots) via hand-written writes. So we assert exactly that, the unit
analogue of ADR-0016's gambit completeness check:
`unit_buffer_coverage_problems()` sentinel-fills a probe buffer, runs
`_write_unit_data(probe, 0, {}, 0)`, and errors on any offset that still holds
the sentinel. Two distinct sentinels rule out a write that stores a sentinel's
own value. It is pure (a `UNIT_SIZE`-int probe, no `RenderingDevice`), so the
boot validator and `UnitEncodeSchemaTest` share it, exactly as the config-schema
check is shared.

- **Dynamic sentinel, not a declared offset list.** The gambit check lists its
  non-schema offsets (`_GAMBIT_HAND_PACKED` / `_GAMBIT_RESERVED`) because gambit
  writes are already a small declarative block. The unit init writes are
  scattered *imperative* `data[offset + UnitField.X] = …` assignments; a parallel
  const list of those offsets would be a **new drift surface** (list vs. code) —
  the very failure mode this ADR exists to remove. A dynamic probe verifies the
  real writes with nothing to keep in sync. (Folding the imperative init into a
  declarative table would let the check go pure-static like gambit's; that is a
  larger write-path refactor deferred as a separate change, not required by the
  guard.)
- **Residual hole, matching gambit.** The net proves each offset is *written*,
  not that a config-derived field is written *through the schema*: hand-writing a
  config field in the init block instead of adding a schema row passes the
  coverage check while bypassing the single source of truth. Same documented
  `_Avoid_` as the gambit schema; the completeness net is a floor, not a ceiling.
