# The ability data is the permission to land on a corpse, and an empty slot is not one

## Status

Accepted

Built by [#1113](https://github.com/timbermania/fft-monorepo/issues/1113), on
build map [#1101](https://github.com/timbermania/fft-monorepo/issues/1101).

## Context

[#1102](https://github.com/timbermania/fft-monorepo/issues/1102) made `IS_KO` reachable: it
gave the gambit surface a **KO-inclusive target pool** so a `KO'd?` slot could see a corpse at
all. The slot then fired, the caster charged, the MP was spent, the animation played — and the
ability **no-opped at the impact moment**. #1102 opened the first of the filters between a
commit and an HP write, and said in as many words that it had not touched the rest.

This ADR is what a **revive** costs. It is mostly routing rather than invention:
`stage_spell.glsl` already clears `FLAG_DEAD` for the RERAISE auto-revive. The two open
questions were *what lets a CAST reach that write*, and *what the ability data has to say for
it to be allowed to*.

### The filters, enumerated — six, not three, and two of them are unreachable

Walking every `is_unit_dead` gate on the path from gambit commit to HP-restored:

| # | site | reached by | verdict |
|---|---|---|---|
| 0 | `find_unit_by_criteria` / `find_nth_nearest` (the pool) | every revive | already open (#1102) |
| 1 | `handle_moving_to_cast_state` — `stage_pathfind.glsl` | every out-of-range revive | **OPENED** |
| 2 | `run_cinematic_orchestrator`'s per-target walk — `stage_spell.glsl` | Raise, Raise2 (`ct > 0`) | **OPENED** |
| 3 | `apply_attack_damage` — `stage_compute.glsl` | PhoenixDown only | **OPENED**, unwitnessed (S1) |
| 4 | `cast_cinematic_spell`'s AoE stamp walk — `stage_spell.glsl` | nothing | **left strict** |
| 5 | `apply_damage` Phase 1's AoE walk — `stage_damage.glsl` | nothing | **left strict** |

**Rows 4 and 5 are the discriminating count.** Both are AoE walks, and **0 of the 5
cancel-Dead abilities carries `effect_area > 0`** — every one is single-target. Opening them
would be a change no ability in the shipped database can exercise and no test can witness.
"We opened the AoE walks too" would have been a claim with an empty denominator.

There is also a **seventh site that is not a filter**, and it had to be found by reading rather
than by grepping for `is_unit_dead`: `cast_instant_spell` (the `charge_time == 0` landing) has
no dead gate at all. What stopped a revive there was its own **break / heal / damage fork**,
which routed the two cancel-Dead abilities that are *not* `ABFLAG_HEALING` into the damage arm,
where `stage_damage` Phase 2 then dropped the write for being aimed at a corpse.

### What the ROM says about who may do this

FFT carries **no "may target the dead" flag**. It carries an inflict list, and the abilities
that undo death are exactly the ones whose list names `Dead` under mode `cancel`. Over the
shipped database that is **five and only five**:

| id | name | `ct` | landing site | `ABFLAG_HEALING`? | formula |
|---|---|---:|---|---|---|
| 5 | Raise | 4 | cinematic orchestrator | yes (`receive_heal`) | `0x0D`, Y=50 |
| 6 | Raise2 | 10 | cinematic orchestrator | yes | `0x0D`, Y=100 |
| 107 | Revive | 0 | `cast_instant_spell` | **no** (`taking_damage`) | `0x35`, Y=20 |
| 312 | Oink | 0 | `cast_instant_spell` | **no** | `0x35`, Y=100 |
| 381 | PhoenixDown | — | `apply_attack_damage` (ITEM) | yes | `0x4B` (unimplemented, S2) |

Both fields are **already packed into the ability SSBO** by `GPUAbilityLoader`
(`AB_INFLICT_MASK` / `AB_INFLICT_MODE`), and for an ITEM ability the loader already substitutes
the chemist item's own inflict block — which is how PhoenixDown, whose `effects.json` row
carries no inflict list of its own, still lands in the table.

### An unfilled unit slot was reading as a corpse

`GPUBatchSimulator.set_battle_units` fills the roster into the low unit slots and then marks
every slot past it `FLAG_DEAD` + `HP 0`, leaving the rest of the record **zeroed — `U_TEAM`
included**. Its own comment says why: *"this prevents ghost units from interfering with target
selection."* That was true for exactly as long as **every** pool filtered the dead.

So a 2v1 scenario in an 8-slot battle carries **five phantom team-0 corpses standing at tile
(0, 0)**, and #1102's KO-inclusive ally pool is the first pool in the kernel that admits them.
Whether they *win* is geometry: they rank by path cost like anything else, so anywhere far from
the corner the real corpse beats them and the defect is invisible. Measured both ways from tile
(1, 0), one step from the phantoms:

- **without** the `is_unit_slot_filled` clause, the Cleric casts Raise at **`Unit3`** at tick
  **10** — before anything on the field has died — and the real Bait is never revived;
- **with** it, the slot cannot fire until tick **23**, when Bait is actually a corpse, and the
  revive lands.

🔴 **#1102's own D7 scenario cannot see this, and neither could this ADR's first draft.** D7
asserts that the first commit came from slot 0, which is true whether the slot aimed at a
corpse or at a slot that was never a unit. The ADR's first draft asserted only the revive, at a
mid-map geometry where the phantoms lose the rank walk — so the fix went in, changed nothing
measurable, and would have shipped as an unexercised claim. Relocating the roster to the corner
is what turned it into evidence.

## Decision

1. **The permission is the ability's own ROM inflict list.** `ability_revives(ability_id)` is
   `inflict_mode == INFLICT_MODE_CANCEL && (inflict_mask & (1 << STATUS_DEAD))`. **No `ABFLAG_`
   was invented**, so ADR-0013's deferred-flag guard has nothing new to police, and the rule
   tracks the data: re-extract the ability table and the set of revivers moves with it.

2. **The mask bit is not the status bit.** What decision 1 reads is bit 0 of the **ability's**
   inflict mask — a fact about the ability table. `STATUS_DEAD` (bit 0 of a *unit's* status
   word) **stays hollow**; nothing here sets or reads it, and
   [#1105](https://github.com/timbermania/fft-monorepo/issues/1105) keeps its call on whether
   it lives at all. `is_unit_dead` still reads `FLAG_DEAD` in the flag word.

3. **`revive_unit` is the one place `FLAG_DEAD` is cleared.** It writes HP, clears the flag,
   and returns the unit to `IDLE` + `TICKS_GAMBIT_REEVAL`. The RERAISE Stage B orchestrator,
   which previously spelled those four writes out inline, was **re-routed through it** — so the
   number of places a unit can come back goes one → one, not one → two. Two would be two places
   a reader of `FLAG_DEAD` has to find, and they would find one.

4. **The HP is the ability's own formula**, and that required implementing one. The cast passes
   `calculate_spell_damage`'s result. Formula `0x0D` was already **Y% of the target's max HP**
   (Raise 50%, Raise2 100%). Formula `0x35` — the same percentage heal with a PA-based hit roll
   instead of an MA-based one, which is what Revive and Oink use — **was not implemented** and
   fell to the `damage = formula_y` default, so a Revive restored 20 flat HP rather than 20% of
   maximum. The two formulas now share an arm, because the thing that differs between them is
   the hit roll and this function returns the amount. RERAISE keeps its hard-coded
   `max_hp / RERAISE_HP_DIVISOR`: a lethal-damage capture has no ability whose formula it could
   read. `revive_unit` clamps into `[1, max_hp]`, so no caller can revive a unit into 0 HP for
   `stage_damage` to re-kill, and a 100% revive cannot overshoot.

5. **The revive is taken BEFORE the break / heal / damage fork at every landing site**, not
   inside the heal arm. Two of the five revivers are not `ABFLAG_HEALING`, so a revive hung off
   `is_ability_healing` would silently cover three of five. On a **living** target nothing
   changes: the fork runs exactly as before.

6. **Four of the six filters open; the two that stay strict are the two no ability can reach.**
   See the table above. The strictness is load-bearing, not laziness — an AoE walk that admitted
   the dead would change behaviour for every AoE in the game and for no reviver.

7. **The victory tally needs no change, and the reason is structural rather than lucky.**
   `check_victory` ends a battle only when a team has **0 alive** and the other team's survivors
   are **all `CELEBRATING`** (or both teams are at 0). A revive's caster is, for the whole window
   between commit and landing: alive, **on the corpse's own team** (the KO-inclusive pool is
   ally-only, and `include_ko` on an enemy pool is UNSUPPORTED), and in
   `SPELL_CHARGING`/`ACTING`, which is never `CELEBRATING`. It therefore contributes +1 alive and
   −1 celebrating to precisely the team whose wipe would end the battle. A `U_REVIVE_PENDING`
   unit field was considered and is not needed. One residual window survives — S3.

8. **An unfilled unit slot is not a corpse.** `is_unit_slot_filled` reads `U_MAX_HP > 0` and
   gates both KO-inclusive pool walks. `FLAG_DEAD` cannot be the discriminator, because telling
   "empty slot" from "KO'd unit" is exactly what it can no longer do. `U_MAX_HP` is not a trick:
   the packer writes it for every real unit and zeroes every empty slot, and a combatant with no
   maximum HP is not a combatant under any other rule in this kernel. The check is paid **only
   on the `include_ko` path** — a KO-blind pool already drops empty slots as part of dropping
   the dead.

9. **A corpse does not occupy its tile, and that stays true.** `get_tile_occupant` skips
   `FLAG_DEAD` units, so a healer may walk through a corpse and stand on it. That is what let
   #1102's pool rank a corpse by path cost in the first place. It is now load-bearing in a way
   it was not before — S4.

10. **The witness asserts the flag, not the HP delta.** The `revived` predicate reads
    `FLAG_DEAD` out of the per-tick snapshot and demands the transition DEAD → NOT DEAD with
    `hp > 0`. A predicate keyed on a positive `hp_event` would go green on a half-fix that
    writes HP and leaves the flag set — which is what `apply_heal_to_target` does at a corpse
    today. The predicate also **fails loud when the target never died**, in both arms, because
    "it never died" and "it was never revived" are indistinguishable to any predicate that only
    looks at the end state.

## Consequences

- **Two rule rows, three scenarios, one control.** `F7` (the revive) and `F8` (the
  walk-to-cast) join `docs/gambit-rules.md`. F7's control arm is the same roster with **one
  constant changed** — Cure instead of Raise — so a kernel that revived on *any* heal landing at
  a corpse fails it. F8 uses Revive (107): its range of 1 forces the walk, and its
  `taking_damage` reaction category makes it the arm that proves decision 5.
- **#1102's D7 keeps its job and is not repurposed.** It witnesses the POOL. Folding its commit
  assertion into F7 would have hidden the fix behind an assertion that already passes.
- **The empty-slot fix changes behaviour for every KO-inclusive gambit, not just revives.** Any
  `KO'd?` slot authored today was ranking phantoms in any battle with an unfilled slot — which
  is every gambit-lab cell and most scenario fixtures.
- **Formula `0x35` now returns a percentage for every ability that uses it**, not just the two
  revivers. Nothing else in the shipped database reaches `calculate_spell_damage` with it today.
- **`FFT_SCENARIO_FILTER` exists now**, opt-in and loud: a filtered run prints a banner and its
  tail line is forced to `[FAIL] … NOT a verdict`, so it can never be mistaken for the suite's
  own result. Diagnosing this change took eight iterations of a 12-minute suite; it takes 40
  seconds now.
- **`gambit_fired_at_slot` reports WHAT the slot aimed at**, not just when it fired. A slot-only
  report cannot tell a cast at the authored corpse from a cast at some other candidate, and this
  change spent a diagnosis round on exactly that ambiguity.

## Rejected

- **A new `ABFLAG_MAY_TARGET_KO`.** The data already answers it, and the flag would have to be
  derived from the same two fields — one more hand-maintained column for a rule already in the
  table, plus an ADR-0013 deferred-flag surface to defend.
- **Routing the revive through `apply_inflict_all`'s `INFLICT_MODE_CANCEL` arm.** It is where
  the cancel-Dead bit already lands, and it is the wrong place twice: it clears the **hollow**
  status bit 0, which `is_unit_dead` does not read, and it has no access to the heal amount. It
  would also make the one write that matters invisible at every call site.
- **Reusing the RERAISE cinematic wholesale.** It is timer-driven off a lethal-damage capture a
  cast does not have, and it hard-codes both `RERAISE_HP_DIVISOR` and `RERAISE_EFFECT_ID`. What
  the two paths genuinely share is the four-write revive, and that is what was extracted.
- **Opening the two AoE walks.** No shipped ability can reach them; see decision 6.
- **A `U_REVIVE_PENDING` unit field for the victory tally.** A new unit field, a new stride, and
  new packer/test surface, for a case decision 7 shows the tally already blocks.
- **Making `get_tile_occupant` count the dead.** More ROM-faithful — FFT does not let a unit
  stop on a KO'd unit's panel — and genuinely tempting given S4, but it moves pathing,
  pass-through, and cast-position selection under the entire suite for a hazard this ticket only
  has to *name*. It belongs to whoever owns the revive posture, not to the plumbing.
- **Marking padding slots `U_TEAM = -1` instead of decision 8's `U_MAX_HP` check.** An enemy
  pool tests `team != my_team`, so `-1` reads as **enemy** and every enemy-side search would
  then admit all five phantoms. It would have moved the bug, not closed it.

## Soft spots

- **S1 — PhoenixDown's arm is opened and UNWITNESSED.** It is the only ability that reaches
  filter 3, it is an ITEM, and `Gambit.ActionKind` has no ITEM verb — the same blocker
  `docs/gambit-rules.md`'s F3 section already records. No scenario in this repo can author that
  cast. It becomes witnessable on the day F3 does.
- **S2 — PhoenixDown's formula `0x4B` (`Heal_(Rdm(1..9))`) is still unimplemented.** It falls to
  `calculate_spell_damage`'s default and would revive at a flat `z_value` = 20 HP. The shape is
  right (a small fixed amount), the number is not FFT's. Pre-existing, unreachable per S1, and
  the clamp means it cannot misbehave.
- **S3 — one residual victory-tally window.** On the projectile-deferred path the caster can
  reach `IDLE` on the tick after the landing, so a last enemy dying on exactly that tick could
  let the caster celebrate. It needs the projectile path, which today means PhoenixDown, which
  S1 says nothing can author. Unreachable and therefore unmeasured.
- **S4 — a reviver can stand in the tile it is about to refill.** Decision 9 keeps corpses
  non-occupying, so `find_cast_position` may legally return the corpse's own tile. In the F8
  witness it does not, because the near-adjacent tile has lower path cost from the caster's side
  — but that is a property of that geometry, not a guarantee.
- **S5 — Revive (107) and Oink (312) are admitted on the ability table alone.** Their inflict
  rows say `Dead`/`cancel` and that is the whole evidence; what those two monster skills do in
  the ROM was not checked against a savestate or a decompile. If either turns out not to be a
  revive, the rule is still right and the table is wrong.
- **S6 — a cancel-Dead ability landing on a LIVING target is unchanged.** Raise at a live ally
  still heals 50% of max HP through the ordinary heal arm. FFT does not do that. Out of scope:
  it is a question about the fork's *living* half, which this ADR deliberately did not touch.
- **S7 — the `revived` predicate samples once per host frame while the GPU runs ~25 ticks in
  that time.** A revive that does not SURVIVE a frame is invisible to it. The fixtures handle
  this by giving Bait a max HP large enough that a percentage revive outlives many swings
  (`hp: 20` to die, `max_hp: 2000` to come back), which is a property of the fixtures rather
  than of the predicate.
