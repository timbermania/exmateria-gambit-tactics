# Battle VFX / timing trigger architecture — what drives what, and where we diverge from FFT

**Status:** investigation / architecture map · **Date:** 2026-07-30 · **Branch:** `import-godot-game`

> The decision this map supports is [ADR-0076 — Battle VFX and timing are
> SEQ-opcode-driven](adr/0076-battle-vfx-and-timing-are-seq-opcode-driven.md). This
> document is its supporting reference: the full trigger inventory and the A–E
> mechanism taxonomy.

## The question

> Opcode sequencing *should* be driving battle VFX and timing, but "other stuff"
> seems to be doing it instead. Where are we using the **wrong thing** to trigger
> what an opcode should trigger? Melee attacks already time the hit off the
> attacker's SEQ — so why does a second, non-opcode path exist at all?

This doc enumerates **every** place a battle visual/audio/timing event is
triggered, classifies each by mechanism, and calls out which are faithful to
FFT's opcode-authoritative model, which are legitimate architecture choices,
and which are genuine **bypasses** that should be re-routed.

**Bottom line up front:** there is exactly **one** genuine bypass — the generic
melee **hit cloud** is spawned from the HP-change event, not from the attacker's
`PostGenericAttack` (`0xDE`) opcode. Everything else the user is worried about is
either (a) the *same* opcode timing **precomputed at load** instead of walked at
runtime — faithful, just optimized — or (b) GPU-authoritative visual lifecycle,
which is a deliberate architecture per ADR-0031, not an accident.

---

## 1. The trigger taxonomy (ubiquitous language)

Five named mechanisms. Use these terms when discussing a trigger.

| # | Name | What fires it | Faithful to FFT? |
|---|------|---------------|-------------------|
| **A** | **Opcode-driven (runtime walk)** | `AnimationPlayback` walks the SEQ each frame and emits a `side_effect` when it crosses an opcode (`PostGenericAttack`, `QueueSpriteAnim`, `SetLayerPriority`, `QueueThrowAnimation`). | ✅ This *is* FFT's model. |
| **B** | **Precomputed-timing-driven** | The SEQ is walked **once at load** (`tools/parse_seq.py` `_timings` sidecar → `GPUAnimationTimingLoader` buffer). The GPU compute shader fires the event when `anim_frame` reaches the baked `damage_frame` / `projectile_frame` / `move_start_frame`. | ✅ Faithful — **same opcode timing**, just not re-walked per frame. This is the "we parse out opcode-sequence timings so we don't walk the opcodes" mechanism. |
| **C** | **GPU-state-edge-driven** | CPU diffs the GPU snapshot against `_prev_*` and reacts to a transition (`cast_step_id` bump → `CAST_BEGAN`; `cinematic_timer` −1→N; `SPELL_CHARGING` enter/exit; `anim_flags & 2` edge). | ⚠️ Legitimate (ADR-0031: GPU is authoritative), but faithfulness = "does the edge land on the same tick the opcode would?" — mostly yes because the edges are themselves set by precomputed opcode timing. |
| **D** | **Damage-event-driven** | CPU reacts to an `HP_CHANGED` delta (spawn cloud, record `_last_damage_tick`, death). | ❌ when it *replaces* an opcode trigger (the hit cloud). ✅ when it merely *informs* one (hit/miss attribution). |
| **E** | **Formula / has-effect-file / ad-hoc** | Gated on `ability.formula`, `ability.weapon_range`, `has_effect_file`, item-id offset, etc. | ✅ FFT also branches on formula/ability data — this picks the *handler*, not the *trigger time*. |

**The key distinction the investigation turned on:** categories **A** and **B**
are the *same* faithful timing (walk-now vs walk-once). Category **B is not a
bypass** — it is the optimization the user half-remembers, and it is correct.
The only place we substitute a *different signal* for the opcode is category
**D** spawning the hit cloud.

---

## 2. The full classified map

### A — Opcode-driven (runtime SEQ walk) — *the faithful core*

| Site | Event | Gate |
|------|-------|------|
| `AnimationPlayback.gd:181-198` | Emits `QUEUE_SPRITE_ANIM`, `SET_LAYER_PRIORITY`, `POST_GENERIC_ATTACK`, `QUEUE_THROW_ANIMATION` side-effects as playback crosses each opcode's frame | opcode frame ∈ `(from_frame, to_frame]` — fires **only for the 40/227 anims that carry `0xDE`** for PGA |
| `CombatLoop.gd:1143-1152` `_on_unit_type1_side_effect` | On `POST_GENERIC_ATTACK`: `fire_pending_trap` (deferred weapon trap) **+** `_trigger_physical_reaction` (hit/evade reaction anim + hit/block SFX) | `effect_type == POST_GENERIC_ATTACK` |

Routing chain: `AnimationPlayback.side_effect` → `Unit.body_side_effect`
(`Unit.gd:590`) → `CombatLoop._on_unit_type1_side_effect` (`CombatLoop.gd:296`).

### B — Precomputed-timing-driven — *faithful, optimized*

| Site | Event | Note |
|------|-------|------|
| `GPUAnimationTimingLoader.gd:82-88,140-144` | Bakes per-anim `damage_frame` (PGA tick), `move_start_frame` (MoveUp2), `projectile_frame` (QueueSpriteAnim→eff1) into a GPU buffer | Walked once at load by `parse_seq.py`. **GOTCHA:** the sidecar's `damage_frame` falls back to `throw_frame\|t//2` when an anim has no PGA (`parse_seq.py:156`), erasing the `-1` sentinel — so the GPU buffer **cannot** answer "does this anim have `0xDE`?". Only `type1_seq.json` can. |
| GPU `stage_attack.glsl` → `PROJECTILE_FIRED` (`GPUCombatInterpreter.gd:216`) | GPU sets `anim_flags & 2` when `anim_frame >= projectile_frame`; CPU reads the edge → `CombatLoop._apply_projectile_fired:778` → `spawn_from_gpu` | Projectile spawn time is the baked `QueueSpriteAnim` tick. Faithful. |
| GPU damage stage → `HP_CHANGED` at baked `damage_frame` | The damage itself lands at the precomputed PGA tick | Faithful. (The *cloud* that rides this is the bypass — see §3.) |
| `ProjectileManager.gd:117-120` | Flight time = `damage_frame − anim_frame` (both baked) | ADR-0038 — arrival lands on the damage tick. Faithful. |

### C — GPU-state-edge-driven — *legitimate GPU-authoritative lifecycle*

| Site | Event | Edge |
|------|-------|------|
| `GPUCombatInterpreter.gd:180-198` → `CombatLoop.gd:715` `_apply_cast_began` | `CAST_BEGAN` → `_on_spell_cast_complete` (cast anim, facing, distort, spell-effect spawn) | `cast_step_id` counter bump w/ valid ability+target |
| `CombatLoop.gd:756-767` (in `_apply_state_changed`) | `spawn_charge_vfx` / `stop_charge_vfx` | enter/exit `SPELL_CHARGING` |
| `CombatLoop.gd:772-775` | facing + `_update_unit_animation` | any `STATE_CHANGED` into `ACTING`/`SPELL_CHARGING` |
| `CinematicManager.gd:106-130` `update_edge` | `spawn_cinematic_effect` (−1→N) / teardown (N→−1) / spotlight handoff | `cinematic_timer` field edge (lowest-id caster) |
| `CinematicManager.gd:241,293` | camera `request_takeover` / `release_takeover` | `camera_started` / `camera_finished` effect signals |

ADR-0031 makes GPU battle state authoritative, so mirroring visuals off state
edges is by-design. These edges are themselves set by precomputed opcode timing
(`cinematic_timer`, `anim_flags`), so they're timing-faithful.

### D — Damage-event-driven

| Site | Event | Verdict |
|------|-------|---------|
| **`CombatLoop.gd:807-815` `_apply_hp_change`** | **melee hit cloud** `spawn_trap_effect(..., is_melee=true)` | ❌ **THE BYPASS.** `if delta < 0 and attacker found and not projectile` — **no animation gate.** Fires for any non-projectile damaging ability whose anim lacks `0xDE` (→ spurious Dash cloud). |
| `CombatLoop.gd:794` | records `_last_damage_tick[i]` | ✅ *informs* the opcode-driven reaction (hit vs miss). Not a bypass — this is fine. |
| `CombatLoop.gd:705-712` `_apply_death` | death visual + `stop_charge_vfx` | ✅ death is genuinely an HP=0 event. |

### E — Formula / has-effect-file / ad-hoc *(handler selection, not trigger time)*

| Site | Event | Gate |
|------|-------|------|
| `CombatLoop.gd:1487` | `is_cinematic` ownership split | `ability.ct > 0 and not is_item` (Fire double-cast fix) |
| `CombatLoop.gd:1594-1621` | `_spawn_spell_effect` (single + AoE) | `has_effect_file and effect_id>0 and not is_cinematic` |
| `CombatLoop.gd:1516-1523,1652-1658` | `spawn_item_effect` | `effect_id > ITEM_EFFECT_ID_OFFSET` |
| `CombatLoop.gd:1545-1551` | weapon-attack anim (Break/Holy Sword) | `ability.weapon_range` |
| `CombatLoop.gd:726-737` | `set_pending_trap` (deferred weapon trap) | `ev.defers_trap` (weapon-range non-damage) → fired later on PGA opcode |
| `EffectManager.gd:200-246` | trap handler routing (21 Break-triangles vs 2 dust) | `ability.formula` — **picks handler, matches FFT** (formula only chooses the handler) |
| `CombatLoop.gd:1264-1340` | spell/Raise reactions | `ability_react_triggered` / `hit_reaction_triggered` / `refresh_tile_triggered` (E-file timeline keyframes) |
| **`CombatLoop.gd:1633-1650` `_on_projectile_landed`** | **ranged hit cloud** `spawn_trap_effect(..., is_melee=false)` | `proj_type not in [POTION, ITEM]` — arrival-driven, **also ungated on the attacker's anim** (see §3, lower priority) |

Reaction routing has four entry points (all stateless → `ReactionType` lookup →
`Unit.play_reaction_animation`): physical (PGA opcode), projectile
(`projectile_landed`), spell (`ability_react`), Raise rise (`hit_reaction`).

---

## 3. The two-path contradiction, resolved

**Why does a non-opcode hit-cloud path exist next to the opcode path?**

The `0xDE` opcode work is actually **split into two halves** in the port, and
only one half was wired to the opcode:

| Half of `0xDE` | Port trigger | Correct? |
|----------------|--------------|----------|
| **Reaction animation** (target flinches/guards) + hit/block SFX | `POST_GENERIC_ATTACK` opcode → `_trigger_physical_reaction` | ✅ opcode-driven |
| **Hit cloud** (dust/flash impact particles) | `HP_CHANGED` delta → `_apply_hp_change` | ❌ damage-driven, **no `0xDE` gate** |

So the reaction half is faithful; the cloud half is the bypass. In FFT **both**
come off `0xDE` in the attacker's strike anim (`FUN_8006894c`); only 40/227 anims
carry it, and cast/dash/idle/walk do **not** — which is why FFT shows no Dash
cloud and the port does.

**Was the damage path necessary for attribution?** The predecessor's hypothesis
was that damage-time is where you reliably know *target + hit/miss + evasion*,
which a raw animation event doesn't carry. **The evidence refutes that as a
justification:** `_trigger_physical_reaction` — which *is* opcode-driven —
already reconstructs all three from the opcode side:

- **target:** `attacker_state.target` (`CombatLoop.gd:1179`)
- **hit vs miss:** `_last_damage_tick` window (`CombatLoop.gd:1191-1192`)
- **evasion type:** `_last_evade_type` (`CombatLoop.gd:1193`)

The comment at `CombatLoop.gd:1169-1175` documents exactly this: `damage_target`
is a one-frame GPU pulse and the HP sample lags PGA by a frame, so the reaction
path already uses `_last_damage_tick` instead. **The hit cloud could read the
same fields.** The damage-driven spawn is therefore **redundant, not required** —
it duplicates attribution the opcode path already performs, while dropping the
one thing that matters (the `0xDE` gate).

Most tellingly, the faithful machinery **already exists and is used**: deferred
weapon abilities call `set_pending_trap` on cast-begin and `fire_pending_trap`
on the `POST_GENERIC_ATTACK` opcode (`CombatLoop.gd:731`, `1149`;
`EffectManager.gd:367-384`). The generic melee cloud is the *only* melee trap
that does **not** go through this opcode seam.

---

## 4. Recommendations

Ordered by faithfulness win vs. risk.

### R1 — Route the hit cloud through the `0xDE` opcode (the fix) — ✅ IMPLEMENTED

**Status: done (TDD, 2026-07-30).** The `spawn_trap_effect` call was deleted from
`_apply_hp_change` and the cloud now spawns from `_trigger_physical_reaction` (the
`POST_GENERIC_ATTACK` handler) when `is_hit`, reusing the target/dir/evasion it
already computes. The trigger is now category **A**, matching FFT; Dash (no `0xDE`)
produces no cloud with no special-case gate.

Details of the landed change:
- New host seam `CombatLoop.hit_cloud_hook` + `_spawn_hit_cloud(...)`, sibling of
  `spell_effect_hook` (ADR-0018). Only the opcode-triggered cloud routes through
  it; ranged (`_on_projectile_landed`) and deferred break traps stay direct.
- `EffectManager.fire_pending_trap` now returns `bool`; `_on_unit_type1_side_effect`
  passes `not fired_pending` so a deferred break/holy-sword cloud is not
  double-spawned by the generic path.
- Guards: `tests/GPUMeleeHitCloudTest` (strike → exactly 1 cloud) and
  `tests/GPUDashNoHitCloudTest` (Dash deals damage → 0 clouds).

Two facts discovered while implementing:
1. The old damage-path attribution was **doubly** broken — `attacker_idx` (scanned
   from the `damage_target` pulse) is `-1` on every damage tick in the test harness
   because the pulse is already cleared, so the cloud didn't even fire reliably.
2. **A killing blow suppresses `HP_CHANGED`** (`GPUCombatInterpreter` emits only
   `DIED`), so the old damage-path cloud never fired on a lethal hit. The opcode
   path fixes this too (it fires from the attacker's anim regardless of target
   death), though `_trigger_physical_reaction` currently early-returns if the target
   is already dead — see the naming/model note below.

**Naming:** the word "generic" was dropped throughout. The cloud is FFT's non-E-file
impact VFX (`FUN_8006894c`), triggered precisely at the `0xDE` frame with the
**handler** (dust / elemental puff / Knight-Break triangles) selected from ability
formula by `EffectManager` — there is no "generic" tier, only a precise trigger +
formula-driven handler.

### R1-followup — Unify the deferred break trap with the hit cloud (not done)

Modelling the cloud precisely reveals the **deferred break/holy-sword trap**
(`set_pending_trap`→`fire_pending_trap`) and the hit cloud are the **same event** —
a hit cloud at the `0xDE` frame — split only historically (breaks needed their
position deferred). They could collapse to one spawn point at `POST_GENERIC_ATTACK`
with the handler chosen by formula. Deferred because it touches shipped break tests
(`GPUBreakTrapTest`, `TrapUnifiedPublishTest`); the `fired_pending` dedup keeps them
correct in the meantime.

### R2 — Verify the ranged hit cloud (`_on_projectile_landed:1648`), lower priority

It's arrival-driven (fires when the arrow lands on the precomputed damage tick),
so it is **timing-faithful** even though the mechanism isn't the opcode. Open
question for `/effect-parity`: do bow/ranged strike anims carry `0xDE`, and does
FFT gate the arrow's impact cloud on it? If yes, fold it through the same opcode
seam as R1; if the arrow cloud is unconditional on landing, leave it.

### R3 — Leave categories B and C alone

Precomputed timing (B) and GPU-state edges (C) are **not** bypasses. B is the
same opcode timing walked once instead of per-frame; C is ADR-0031's
GPU-authoritative lifecycle. Re-routing them through a runtime opcode walk would
be a regression in both perf and the GPU-authoritative model. The user's instinct
that "opcodes should drive things" is satisfied here already — the opcodes *did*
drive them, at bake time.

---

## 5. "It didn't used to be this way" — open, deferred

Within **this** monorepo the damage-driven cloud has been present at
`_apply_hp_change` since the first import commit `c64d05cfe` (a squashed 764-file
import; the pre-import game history lives in a **separate original Godot repo**
not reachable here). So "always this way" is only proven back to the import
**floor** — the damage path may well have *replaced* an opcode-driven one in the
original repo. Confirming that requires running `-S "spawn_trap_effect"` /
`-S "PostGenericAttack"` archaeology in that original repo.

**Deferred per user instruction** ("forget about the old repo for now"). If/when
the original repo is available, that archaeology is the only place the "used to
be" evidence can exist — and R1 makes the port faithful regardless of what the
history shows.

---

## Appendix — source index

- Opcode emit: `addons/exmateria_sprite_rig/sequence/AnimationPlayback.gd:181-198`;
  opcode enums `addons/exmateria_sprite_rig/sequence/AnimationOpcodes.gd`.
- CombatLoop handlers: `_apply_hp_change:789`, `_apply_cast_began:715`,
  `_apply_state_changed:740`, `_on_unit_type1_side_effect:1143`,
  `_trigger_physical_reaction:1166`, `_on_spell_cast_complete:1427`,
  `_on_projectile_landed:1633`.
- Interpreter edges: `src/gpu/GPUCombatInterpreter.gd` (`CAST_BEGAN:194`,
  `PROJECTILE_FIRED:216`, `_defers_trap:255`, `last_casting_ability_id:263`).
- Precomputed timing: `src/gpu/GPUAnimationTimingLoader.gd`, `tools/parse_seq.py`
  (`_timings`, `damage_frame` fallback `:156`).
- Cinematic lifecycle: `src/gpu/CinematicManager.gd`.
- Trap spawn / pending: `src/effects/EffectManager.gd:200-246,367-384`.
- Ground truth: `research/wiki_articles/hit_cloud_spawner_pipeline.txt`,
  `charge_effect_handler_triggers.txt`, `vfx_systems_overview.txt`.
</content>
</invoke>
