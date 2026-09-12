# Status System

**As of:** 2026-06-15
**Branch:** `status-registry-67`
**Sourced from:** #67 PRD (registry + encoder fix); plug-in convention.
**Companion docs:** [`compute_shader_status.md`](compute_shader_status.md) §4.3 (which status semantics are currently wired in which stage), [`gambit-rules.md`](gambit-rules.md) D4 (HAS_STATUS / MISSING_STATUS).

This document covers the **data plumbing** for FFT status effects — the name
registry, the bit positions, and the plug-in convention that says **which shader
stage** a new status's combat semantic lives in. It does **not** track per-status
implementation status; that's owned by `compute_shader_status.md` §4.3.

---

## 1. The registry

[`src/data/StatusRegistry.gd`](../src/data/StatusRegistry.gd) is the single
source of truth for `(StringName name, int bit_index)` pairs. It mirrors the
`const int STATUS_*` declarations in
[`src/gpu/shaders/combat_common.glslinc`](../src/gpu/shaders/combat_common.glslinc)
(lines 219–250).

```gdscript
StatusRegistry.bit(&"silence")           # → 25
StatusRegistry.bitmask([&"silence", &"haste"])  # → (1 << 25) | (1 << 19)
StatusRegistry.name_of(15)               # → &"poison"
```

A runtime drift assertion parses the shader on first access and `push_error`s
on any disagreement, so the hand-mirrored GDScript table can't silently desync
from GLSL. `tests/StatusRegistryTest.gd` repeats the parity check explicitly.

| bit | name (StringName)  | bit | name              |
|----:|--------------------|----:|-------------------|
| 0   | `&"dead"`          | 16  | `&"regen"`        |
| 1   | `&"undead"`        | 17  | `&"protect"`      |
| 2   | `&"charging"`      | 18  | `&"shell"`        |
| 3   | `&"jump"`          | 19  | `&"haste"`        |
| 4   | `&"defending"`     | 20  | `&"slow"`         |
| 5   | `&"performing"`    | 21  | `&"float"`        |
| 6   | `&"petrify"`       | 22  | `&"reraise"`      |
| 7   | `&"stop"`          | 23  | `&"transparent"`  |
| 8   | `&"sleep"`         | 24  | `&"confusion"`    |
| 9   | `&"immobilize"`    | 25  | `&"silence"`      |
| 10  | `&"disable"`       | 26  | `&"blood_suck"`   |
| 11  | `&"blind"`         | 27  | `&"curse"`        |
| 12  | `&"berserk"`       | 28  | `&"invite"`       |
| 13  | `&"chicken"`       | 29  | `&"darkness"`     |
| 14  | `&"frog"`          | 30  | `&"oil"`          |
| 15  | `&"poison"`        | 31  | `&"faith"`        |

Bits 0–31 live in `U_STATUS_FLAGS_LO`; bits 32–63 are reserved in
`U_STATUS_FLAGS_HI` for future allocation. The 32 currently-defined names are
the full slate today.

---

## 2. Plug-in convention — which stage owns the semantic?

Different status categories live in different shader stages because they hook
the simulation at different points. Don't try to flatten this into a single
data table — pick the stage from the category.

| Category            | Statuses                                           | Stage(s)                                                | What plugs in                                  |
|---------------------|----------------------------------------------------|---------------------------------------------------------|------------------------------------------------|
| **Timer multiplier**| `haste`, `slow`                                    | `stage_attack`, `stage_spell`, `stage_pathfind`         | CT/charge-time scale at the timer-set call.    |
| **Activity veto**   | `silence` (SPELL/ABILITY), `immobilize` (MOVE), `stop` / `sleep` / `petrify` / `disable` (all) | `stage_compute` (`execute_gambit_action` + STATE_IDLE entry) | Action falls through; gambit slot is skipped. |
| **Per-tick HP delta**| `poison`, `regen`                                 | `stage_damage` (or a per-tick hook in `stage_compute`)  | Apply ±HP each tick; route through `pending_damage` to honor `undead` inversion. |
| **Damage modifier** | `protect`, `shell`                                 | `stage_damage` (incoming-damage path)                   | Multiply incoming damage; protect cuts physical, shell cuts magical. |
| **Target filter**   | `transparent`, `invite`                            | `stage_compute` (target selection)                      | `transparent` removes the unit from enemy gambit pools; `invite` changes team affiliation for pool membership. |
| **Action override** | `berserk`, `confusion`, `chicken`, `frog`          | `stage_compute` decision path                           | Replace the gambit list with the override behavior (BERSERK → ATTACK nearest, FROG → restricted action set, etc.). |
| **Re-targeting**    | `reraise`                                          | `stage_damage` / death handler                          | On lethal damage, restore HP and clear bit instead of dying. |
| **Damage inversion**| `undead`                                           | `stage_damage` Phase 3                                  | Swap heal↔damage routing on the `pending_damage` invert. |

**Not status-shaped** (omitted from the table on purpose):
- `dead`, `charging`, `jump`, `defending`, `performing` — these are *state*
  flags, not combat semantics. The state machine owns them.
- `blood_suck`, `curse`, `darkness`, `oil`, `blind`, `faith` — TBD; they don't
  fit a single category cleanly. Add a row when the semantic is implemented.

---

## 3. How to add a new status — the loop

1. **Allocate the bit.** Append `const int STATUS_NEW = N;` in
   `combat_common.glslinc`. Add `&"new": N` to `StatusRegistry.NAMES_TO_BITS`.
   The drift assertion will pass; `StatusRegistryTest` exercises both sides.
2. **Pick the stage** from the convention table above. If the new status
   doesn't fit a row, write the row first — figure out the semantic shape
   before the implementation.
3. **Write the consumer code** in that stage. Existing examples to copy from:
   - Timer multiplier: how `haste`/`slow` scale `U_ACT_TIMER` in `stage_attack`.
   - Activity veto: how `silence` falls SPELL/ABILITY through in
     `execute_gambit_action` (`stage_compute`).
   - Damage modifier: how `protect`/`shell` scale in the `stage_damage`
     incoming-damage path.
   - Action override: how `berserk` overrides the gambit list at STATE_IDLE
     entry in `stage_compute`.
4. **Add a scenario witness.** Pattern from `tests/gambit_scenarios/scenarios_D_conditions.gd`:
   seed the bit via `StatusRegistry.bit(&"new")`, write a slot conditional on
   `HAS_STATUS(&"new")` or `MISSING_STATUS(&"new")`, witness the expected
   fall-through with `gambit_fired_at_slot` and/or `trace.committed`.
5. **Update `compute_shader_status.md` §4.3.** Add a row to the "Wired up" table
   pointing at the call site + test scene.

Per-status patches are typically 20–100 lines across one stage file plus a
test scene — same shape as the Tier-2 status batch that landed 2026-05-31.

---

## 4. Gambit-side contract

`GambitCondition` exposes two condition types that consult the registry:

- `GambitCondition.has_status(&"name")` → `Type.HAS_STATUS`
- `GambitCondition.missing_status(&"name")` → `Type.MISSING_STATUS`

`GambitEncoder._encode_gambit_condition` routes `cond.status_id` through
`StatusRegistry.bit()` to a bit index in `[0, 32)`. The shader at
`stage_compute.glsl:100-104` reads `condition_value` as a bit index into
`U_STATUS_FLAGS_LO`. Unknown name → encoder-skip (`push_error` + null) per
ADR-0023 — never a silent `value=0` (= STATUS_DEAD) fallback.

**Conditions stay single-bit per condition.** Multi-status semantics
("Has A and B", "Missing A or B") compose via existing rule D5 AND-combine
across multiple conditions on one slot:

```gdscript
# "Has Poison AND Missing Regen" — two conditions on one slot, AND-combined.
Gambit.create(
    TargetSelector.self_(),
    [GambitCondition.has_status(&"poison"),
     GambitCondition.missing_status(&"regen")],
    Gambit.ActionKind.WAIT, -1, TargetSelector.self_())
```

No `bitmask` condition shape, no shader change. The encoder stays mechanical
(one match-arm per Type, one bit index per condition).

---

## 5. What this system explicitly is not

- **A unit data model.** `U_STATUS_FLAGS_LO/HI` already exists and already
  carries multiple bits at once. Nothing here touches the unit struct.
- **A status display layer.** Icons, status bar, tooltip text, application /
  decay animations all *consume* the registry but are scoped to a separate
  PRD (UI3).
- **An FFT inflict-status-set resolver.** `AbilityDatabase.inflict_status`
  holds an index into FFT's packed 5-status-set table. Extracting that table
  from the ROM and wiring it through `stage_damage` is its own work item.
  🔴 **DONE — and the parenthetical this bullet used to carry was wrong.** It read
  *"the same table the ROM uses for Fire → which statuses with what probability"*.
  The table (`InflictStatusList`, SCUS `0x80063FC4`, 128 entries of six bytes) says
  WHICH statuses and in what MODE — one mode flag byte plus a five-byte status set —
  and **carries no probability at all**. It was extracted for #98; the last two of
  its four modes landed 2026-09-11 (#1117), and `separate`'s odds turned out to be a
  flat 24% compiled into the ROM's code rather than anything in its data. See
  ADR-0299.
- **A YAML generator.** 32 entries rarely change; the runtime drift assertion
  catches drift cheaper than a code-gen pre-flight would.
- **A duration-decay engine.** That landed 2026-05-31 in
  `combat_common.glsl:tick_status_timers` and is owned by
  `compute_shader_status.md` §4.3. The registry is the *names* layer; decay
  is downstream.
  🔴 **Half of it landed, and the other half landed 2026-09-11 (#1116).** The
  *consumer* (`tick_status_timers`, `clear_status_timer`) was live and per-tick
  from the start; the *producer* was missing — `set_status_with_timer` had zero
  call sites and `apply_inflict_all` ORed the mask on with no duration, so every
  status inflicted in battle was permanent and a countdown existed only where a
  unit config seeded one (measured 2026-09-10, `status-conformance.md` (#1105)
  finding 1). `apply_inflict_all` now arms one, with the duration the ROM's
  status-attribute table carries for that status — **sixteen of FFT's forty have
  one, and the other twenty-four are permanent until cancelled, which is the
  ROM's answer and not a gap.** The 8-slot pool is gone with it: the countdowns
  are sixteen 16-bit counters addressed by the status's own slot, the shape
  `Status_CT_Set` has at `unit+0x5D`. See ADR-0298.
