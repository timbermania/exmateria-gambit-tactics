# GPU combat buffer layout is shader-authoritative

The [combat buffer layout](../context/02-combat-buffer-layout.md) — the integer offsets, struct
sizes, and action/target/condition enums of the packed unit/gambit/ability
SSBO buffers — was hand-duplicated across `combat_common.glslinc` and
`GPUBatchSimulator.gd`, and the two drifted (the GDScript `ActionType` was
silently missing four values the shader defined). We make
`combat_common.glslinc` the single source of truth and **generate** the
matching GDScript constants from it, so the layout exists in one authored
place and the rest is mirrored.

## Status

accepted

## Decision

**`src/gpu/shaders/combat_common.glslinc` is the single authored source for the
combat buffer layout; the GDScript that mirrors it is generated from the shader
by `tools/gen_gpu_layout.py`.**

The rules below were decided by this ADR but were only ever stated as prose —
in the summary above and in Considered options / Consequences. They are numbered
here on 2026-08-28 so `ADR-0001 dec. N` is a checkable citation; each names the
section that carries its evidence. Nothing is added and nothing is retired by
the numbering.

1. **The shader is authoritative; the GDScript is generated.** The `const int
   U_*` / `GM_*` / `AB_*` / `ACTION_*` / `TARGET_*` / `COND_*` declarations in
   the `.glslinc` are the authored truth. A Python generator parses them and
   rewrites the GDScript. Shader authors keep hand-editing GLSL. (Considered
   options, "Shader-authoritative (chosen)".)

2. **Never the other direction, and never a neutral schema.** Generating the
   `.glslinc` *from* GDScript is rejected (it inverts the GPU-is-the-authority
   stance), and so is a hand-authored schema file that emits both sides (it
   makes the `.glslinc` block generated and takes offsets out of GLSL — friction
   on the file that changes most). (Considered options, the two rejected
   bullets. See Amendment 1: one constant family now works the rejected way.)

3. **Membership is by prefix, not annotation.** Adding `ACTION_FOO` to the
   shader makes the GDScript member appear on regenerate with no extra step.
   This is what structurally retires the drift class. (Consequences, bullet 1.)

4. **Generated code lands in sentinel-delimited regions of existing files, not
   in a new module.** A standalone `GPULayout` module is deferred until a
   CPU-side simulator needs the offsets too. (Consequences, bullet 2.)

5. **A constant the shader declares is generated; a GD-only constant is
   hand-authored outside the region.** Buffer sizes and strides
   (`MAX_GAMBITS`, `GAMBIT_SIZE`, `ABILITY_SIZE`, `MAX_ABILITIES`) are
   generated because a silent mismatch would corrupt the layout;
   `MAX_ANIMATIONS`, which the shader does not declare, stays hand-authored.
   (Consequences, bullet 5.)

6. **Display-name arrays stay hand-maintained, by design.** They are display
   only and guarded by bounds checks at the read sites. (Consequences, bullet
   7.)

7. **The string-keyed snapshot is generated from the same offsets.** A
   `SNAPSHOT_FIELDS` map (snake_case key -> field, one per field) is emitted
   into the same region and the builder loops over it, so a key cannot drift
   from an offset and no field can be silently missing. (Consequences, bullet
   8.)

8. **Two enforcement nets, and the gap between them is accepted.** A `--check`
   mode run as a pure-Python pre-flight in `tests/run_all_tests.sh`, plus the
   retained boot-time validator for the edit-shader-then-Play inner loop. There
   is no CI or pre-commit, so a commit that never runs the suite can land a
   stale region; it surfaces at the next test run or game boot. (Consequences,
   bullet 9.)

9. **This layout is not an ISO-derived asset.** It is hand-authored shader
   source and stays out of `bootstrap_assets.sh`. (Consequences, bullet 10 —
   and see Amendment 1 on why this sentence is the one most often mistaken for
   the *root* ADR-0001.)

## Considered options

- **Shader-authoritative (chosen).** The shader's `const int U_*/GM_*/AB_*/
  ACTION_*/TARGET_*/COND_*` declarations are authoritative; a Python
  generator parses them and rewrites a sentinel-delimited region of
  `GPUBatchSimulator.gd`. Chosen because the compute shader is already the
  single source of truth for combat logic — a field's offset and the code
  that reads it then live in the same file — and because the boot-time
  validator already parses the shader, so this only moves that parse to
  build time and makes it *generate* instead of *warn*. Shader authors keep
  editing GLSL with zero workflow change.
- **Neutral schema file** (a hand-authored `unit_layout.json` that emits
  both sides). Rejected: cleanest "one source," but it forces shader
  authors to stop hand-editing offsets in GLSL and edit JSON instead, and
  makes the `.glslinc` block generated — friction for the file that changes
  most.
- **GDScript-authoritative** (generate the `.glslinc` from the `.gd`).
  Rejected: inverts the "GPU is the source of truth" stance — the shader,
  the actual combat authority, would consume generated constants.

## Consequences

- Membership is by **prefix**, not annotation: adding `ACTION_FOO` to the
  shader makes `ActionType.FOO` appear on regenerate with no extra step.
  This is what structurally retires the drift class — a new value can't be
  forgotten on the GDScript side.
- There are **two generated targets**, each a sentinel-delimited region in
  an existing file (no new module):
  - `GPUBatchSimulator.gd` — the offset *enums* `UnitField` / `GambitField`
    / `AbilityField` (strip prefix → member) plus `UNIT_SIZE` /
    `BATTLE_HEADER_SIZE` / `SHADER_VERSION`. Keeps the ~180 existing
    `UnitField.X` references untouched.
  - `GPUConstants.gd` — the `ACTION_*` / `TARGET_*` / `COND_*` / `STATE_*`
    *flat consts* (full prefixed name kept), since 172 call sites already
    reference `GPUConstants.ACTION_*` etc. This is the GD-side aggregator.
  Extracting a standalone `GPULayout` module is deferred until a CPU-side
  simulator needs the offsets too.
- The redundant `ActionType` / `TargetType` / `ConditionType` enum copies
  that previously lived in **both** `GPUBatchSimulator.gd` and
  `GambitEncoder.gd` were deleted; both now reference the generated
  `GPUConstants` consts. (These copies were the ones that had actually
  drifted — `GPUConstants` was missing `TARGET_` 5/8, `COND_` 2/13,
  `ACTION_` 6/10 before generation filled them in.)
- Buffer sizes that exist in the shader (`MAX_GAMBITS`, `GAMBIT_SIZE`,
  `ABILITY_SIZE`, `MAX_ABILITIES`) are generated into `GPUConstants` too —
  they define buffer strides, so a silent shader/GD mismatch would corrupt
  the layout. `MAX_ANIMATIONS` is GD-only (not in the shader) and stays
  hand-authored outside the region.
- Three more hand-maintained copies turned out to be **unused dead code**
  (0 references) and were deleted rather than generated, by the deletion
  test: `GambitEncoder.GambitField`, `GPUBatchSimulator.StateReason`, and
  `GPUStateReader.UnitState`. (`StateReason` had even drifted — missing
  `THRASH_ABORT` — but nothing read it; the `DBG_STATE_REASON` value is
  decoded for display via `GPUConstants.REASON_NAMES`.)
- Still hand-maintained, by design: the `STATE_NAMES` and `REASON_NAMES`
  display-name arrays in `GPUConstants` (display only, guarded by bounds
  checks at the read sites; same call as leaving any *_NAMES array out).
- The string-keyed `get_battle_unit_states()` snapshot is generated too: a
  `SNAPSHOT_FIELDS` map (snake_case key -> `UnitField`, one per field) is
  emitted into the same region, and the builder loops over it. The keys are
  mechanically `member.lower()` so they can't drift from the offsets, and
  every field is always present — removing the silent-missing-key failure
  mode of `state.get("x")` (a hand-written dict previously listed only 70 of
  85 fields; the omitted 15 were internal scratch no consumer relied on).
- Enforcement is a `--check` mode run as a pre-flight in
  `tests/run_all_tests.sh` (pure Python, no Godot), plus the retained
  boot-time validator for the edit-shader-then-Play inner loop. There is no
  CI or pre-commit, so an **accepted gap** remains: a commit that never
  runs the suite can land a stale region; it surfaces at the next test run
  or game boot rather than at commit time.
- Not part of `bootstrap_assets.sh` — the layout is hand-authored shader
  source, not an ISO-derived asset.

## Amendment 1 — almost nobody who writes `ADR-0001` means this one, and one family now works the rejected way

Graded 2026-08-28 against the code, the generator and the suite. The mechanism is
alive and enforced: `tools/gen_gpu_layout.py --check` runs as a pre-flight at
`tests/run_all_tests.sh:70`, and the boot-time validator still parses the shader for
`SHADER_VERSION` (`GPUBatchSimulator.gd`). Decisions 1 and 3–8 hold as written.
Four things a reader needs before citing this ADR:

### The number is shared with the root corpus, and the split is 18 to 0

`/docs/adr/0001-iso-derived-assets-reproducible.md` — the repo root's ADR-0001, "ISO-derived
assets are reproducible outputs of one host-agnostic extractor" — is a *different
document with the same number*. Every one of the **18** non-ADR files in
`godot-learning/` that writes `ADR-0001` means **that** one, not this one:

| where | files | what they mean by it |
|---|---:|---|
| `src/` | 6 | `EquipStatDelta`, `ChangeJobWheel`, `ChangeJobScreen`, `DamageNumber3D`, `FormationHoverAnimator`, `EquipPickerMenu` — "parsed from the ROM, no hand-maintained copy" |
| `tests/` | 2 | `ChangeJobWheelTest` (data-derived invariants), `run_all_tests.sh:89` (the opcode catalog transcribed from vendor XML) |
| `tools/` | 10 | `_fft_bytecode.py`, `bootstrap_assets.sh`, `gen_opcode_catalog.py`, `parse_formation_orb.py`, `parse_roster_selection.py`, `parse_number_popup.py`, `parse_world_map.py`, `parse_formation_box.py`, and the two `test_parse_*.py` |

That is the whole of this ADR's `code` / `test` / `tool` count in
`docs/adr/AUDIT.md` — **the register credits this ADR with 18 citations it does not
have.** Only `docs/pitfalls.md` and the sibling ADRs (0003, 0005, 0007, 0008, 0009,
0013, 0018, 0021, 0023, 0031, 0032, 0037, 0048) mean the buffer layout, and they
resolve it by relative link rather than by number.

Two files get the disambiguation right and are the pattern to copy:
`FormationHoverAnimator.gd` writes "Root ADR-0001's authored/parsed line";
`parse_number_popup.py` writes "Per root ADR-0001". ADR-0013 writes "**ADR-0001
(top-level)** is the umbrella". `check_adr_anchors.py` cannot catch the rest: a bare
`ADR-NNNN` carries no anchor, so there is nothing for it to resolve, and it only ever
resolves against `godot-learning/docs/adr/`.

### Decision 4's two targets: one moved, and it grew a third field family

Consequences names `GPUBatchSimulator.gd` and `GPUConstants.gd` as the two generated
targets. The first moved: `gen_gpu_layout.py`'s `TARGETS` now writes
**`src/gpu/GPUCombatPacker.gd`**, which carries `UnitField` / `GambitField` /
`AbilityField` **and a `BattleHeaderField` (`BH_`) family that did not exist when this
ADR was written**, plus a second key-map `BATTLE_STATE_FIELDS` beside
`SNAPSHOT_FIELDS`. The promise attached to the old host — "keeps the ~180 existing
`UnitField.X` references untouched" — was kept through the move by a forwarding
`const UnitField = GPUCombatPacker.UnitField` in `GPUBatchSimulator.gd`; the repo now
has 195 such references and none of them had to change. Decision 4's *rule* is intact;
only the filename in Consequences is stale.

### Decision 2 has a carve-out: the activity family is YAML-authoritative

`STATE_*` was dropped from `gen_gpu_layout.py`'s `TARGETS` and `STATE_NAMES` deleted
from `GPUConstants` by the activity-taxonomy refactor (#45/#46). Those constants are
now `LOGICAL_ACTIVITY_*`, generated by `tools/gen_activity_taxonomy.py` from
`tools/activity_taxonomy.yaml` — **into both sides**, including a
`=== BEGIN GENERATED: logical-activity ===` region inside `combat_common.glslinc`
itself. For that one family the shader is a consumer, not the author. That is
decision 2's rejected "neutral schema file" option, adopted.

**This is not recorded as a reversal anywhere, and there are two readings.** ADR-0026
names `tools/activity_taxonomy.yaml` **authoritative** for the Logical↔Display mapping
and says "the generator emits the dispatch shell, the constants, and the Markdown
table" — but it says it in its *References* section, not in a decision, and it cites
neither ADR-0001 nor the inversion. So either (a) ADR-0026's reference line ratifies
the whole thing and "the constants" already covers the shader's, or (b) ADR-0026
ratified only that the *mapping* is YAML-owned, and generating the **shader's**
constants from YAML is an ADR-0001 reversal no ADR states. Nothing in either document
distinguishes them. Whoever knows which it is should say so here and in ADR-0026;
until then, do not cite ADR-0001 decision 2 as though it still covers unit activity.

### Decision 6 is now half a rule

Consequences names "the `STATE_NAMES` and `REASON_NAMES` display-name arrays" as still
hand-maintained. `REASON_NAMES` is, at `GPUConstants.gd:116`, outside the generated
region, exactly as decided. `STATE_NAMES` no longer exists anywhere in the repo — the
same #46 sweep deleted it, and its replacement `LOGICAL_ACTIVITY_NAMES` is *generated*,
inside the taxonomy region. Decision 6 stands for the one array that is left.
