# `dont_target_self` is the CURSOR rule, `dont_hit_caster` is the SPLASH rule, and the wiki named a third the engine never reads

## Status

Accepted (2026-09-11)

Extends ADR-0049 (which owns the `dont_hit_*` triple) and ADR-0276 dec. 12
(which owns "the offer list and the grader are one decision"). Neither is
superseded: ADR-0049's axis is untouched and every grade it produced still
reads `forbidden`.

## The question this answers

*"I think there are some more rules to enforce on gambits (and selection in
general)… is it possible to misconfigure gambits?"*

**Yes, in four named cells.** They are enumerated in dec. 3.

## Context: thirteen flags are extracted and the gate read three

`assets/abilities/ability_attributes.json` carries 368 records with 13 targeting
flags. Before this ADR, `GambitOptions._aim_verdict_for_verb` consulted three of
them — ADR-0049's `dont_hit_*` triple. The rest were extracted and read by
nothing.

🔴 **The flag NAMES come from the FFHacktics wiki, not from a decompile — and
ADR-0049 has no ROM address in it either.** `research/effect-meta-data/scripts/
dump_ability_data.py` cites *"Structure from FFHacktics wiki — Ability Secondary
Data"*. So "enforce the flag the name describes" was not available as a move:
the names are a hypothesis, and one of them turns out to be wrong about the
engine. Each decision below is rooted at an address instead.

## Decisions

### 1. The attribute table is at `0x8005FBF0`, 14 bytes a record, and BATTLE.BIN reads it at 13 sites

`SCUS_942.21` RAM `0x8005FBF0` (file `0x503F0`), 368 `Normal` records. Record
layout: `+0` range, `+1` effect_area, `+2` vertical, `+3` flags1, `+4` flags2,
`+5` flags3, `+6` flags4, `+8` formula.

BATTLE.BIN forms a record pointer in exactly 13 places, every one of them the
same `sll 3 / subu / sll 1` ×14 stride followed by `lui 0x8006 / addiu -0x410`.
Enumerating every mask applied to a byte loaded from one of those pointers is
what the rest of this ADR rests on, and it is a **closed** enumeration rather
than a grep for a name.

### 2. `dont_target_self` (flags1 & 0x01) removes a TILE from the cursor's reach

`FUN_8017A290` @ **`0x8017A290`** builds the selectable-tile table at
**`0x80192DD8`** (512 entries, 5-byte stride, cleared at `0x8017A3D4`). It loads
flags1 at **`0x8017A314`**, marks the caster's OWN entry selectable at
**`0x8017A410`–`0x8017A418`**, and then:

```
8017a444  andi v0,s2,0x1          ; s2 = flags1 -> dont_target_self
8017a448  beq  v0,zero,LAB_8017a454
8017a450  sb   zero,0x0(s5)       ; ZERO the caster's own entry
```

**The flag decides what the cursor may land ON.** It says nothing about who the
effect lands on once a tile is chosen — which is the entire content of
ADR-0049's `dont_hit_caster`, enforced on the AoE distribution walk. Two rules,
two enforcement points, and the repo had been treating the second as if it were
both.

### 3. The authorable gap is FOUR abilities, and saying "four" is part of the finding

`dont_target_self` is true on **156** of 368 records. **152** of those also carry
`dont_hit_caster`, which ADR-0049 already grades `forbidden`. The set where the
screen offered `Self` and the ROM refuses it is therefore:

| id | name | formula | range | area | reachable via |
|---:|---|---:|---:|---:|---|
| 107 | `Revive` | 53 | 1 | 0 | Punch Art |
| 116 | `Invitation` | 42 | 3 | 0 | Talk Skill |
| 152 | `Wish` | 60 | 1 | 0 | Guts, Charge, Holy Sword, Magic, Holy Magic |
| 200 | `BloodSuck` | 71 | 1 | 0 | Blood Suck, SkillSet_86, SkillSet_A7 |

All four are reachable from the 278 distinct action abilities the skillsets
open onto — the same 278 `GambitEncoderTest` audits — so a player could author
`Wish · Self` before this ADR and the gate permitted it.

⚠️ **`Heal` (149) is NOT in this set and must not be added to it.** It was the
example the request opened with and the requester withdrew it themselves. Its
record carries neither flag (verified in live PSX RAM, dec. 6), it is
self-targetable, and the gate is right about it. `GambitEncoderTest` pins that
row so the withdrawn claim cannot return silently.

### 4. The grade is `AIM_UNTARGETABLE`, ordered AFTER the hit-policy line

A new grade rather than a reuse of `AIM_FORBIDDEN`, because the two are
different ROM rules with different enforcement halves — `dont_hit_caster` has a
kernel counterpart (`hit_policy_allows`) and `dont_target_self` has none — and
the census is the one place that has to be able to say so.

Ordered **after** `dont_hit_caster` deliberately. The 152-record overlap keeps
the grade ADR-0049 gave it, so `untargetable` counts exactly the gap of dec. 3
and nothing else. The census row is the ticket's own subject rather than a
number something must be subtracted from.

Per ADR-0276 dec. 12 the rule lands in the **grader**, never in `targets_for` —
the offer list follows for free, and a withheld row that the grader still calls
sensible reds `GambitEncoderTest` by construction.

### 5. `targeting_ai_only` (flags4 & 0x01) is INERT — the name is wrong about the engine

58 records carry it, and the name suggests a permission a gambit surface would
have to reason about. **BATTLE.BIN never reads the bit.**

The zero is not a zero from a blind instrument. The same closed enumeration of
dec. 1 finds the other bits of **the same byte** being tested:

| flags4 bit | flag | tested at |
|---|---|---|
| 0x20 | `direct` | `0x8017B8E4`, `0x8017CDC8`, `0x801879EC` |
| 0x08 | `requires_sword` | `0x801819FC` |
| 0x04 | `requires_materia_blade` | `0x80181A18` |
| 0x10 | `blade_grasp` | `0x8018D05C` (working copy) |
| 0x02 | `evadeable` | `0x8018583C` (working copy) |
| **0x01** | **`targeting_ai_only`** | **nowhere** |

The engine's 14-byte working copy of the current action's record lives at
**`0x801938F0`**; its flags4 byte `0x801938F6` is read at three sites, and the
one variable-mask read (`and v0,v0,a1` @ `0x8018CE30`) is the reaction
dispatcher, whose callers pass `0x10` or `0x40`. Not `0x01`.

**No gate is built on it.** A rule derived from that name would have been a rule
invented, not a rule enforced. The data agrees with the decompile and not with
the name: `Draw Out`, `Sing`, `Dance`, `Chakra` and `Punch Art` all carry the
bit and are all player-commanded.

### 6. `auto_target` (flags1 & 0x02) is real, and it means "no target is selected at all"

`FUN_8017A8C0` @ `0x8017A8C0` is the targeting-MODE dispatcher. At
**`0x8017AA6C`**:

```
8017aa6c  andi v0,v1,0x2     ; auto_target
8017aa70  beq  v0,zero,-> normal path (FUN_8017a290, the cursor)
8017aa78  bne  s2,zero,-> normal path        ; s2 = range, must be 0
8017aa7c  andi v0,v1,0x20    ; weapon_range, must be clear
8017aa88  j    -> return 2
```

Return **2** is the same code the action kinds that take no target at all
return (`caseD_b/c/d/e/3` @ `0x8017AA88`). So `auto_target` = *the game does not
ask for a target*, which is `AIM_IGNORED`'s existing shape (see `Wait`).

**Not gated here, deliberately.** All 45 `auto_target` records are `range 0`
self-centred, none is in the dec. 3 gap, and grading their aim column `ignored`
is a separate behaviour change that should be priced on its own evidence rather
than smuggled in beside a four-cell fix. Open as
[#1201](https://github.com/timbermania/fft-monorepo/issues/1201), not done here.
⚠️ That ticket's first job is to check **our** kernel: `AIM_IGNORED` is a claim
about `execute_gambit_action`, and `0x8017AA6C` is a fact about the ROM's.

## What was NOT done, and why it is written here rather than left implied

- 🔴 **The KERNEL still does not enforce `dont_target_self`.** There is no
  counterpart to `hit_policy_allows` for it, and all four gap abilities are
  `effect_area 0` — the same single-target hole [#1144](https://github.com/timbermania/fft-monorepo/issues/1144)
  / ADR-0276 dec. 5 already opens on, and the standing `K2` XFAIL in
  `GambitScenarioRunnerTest`. **This ADR closes the SURFACE half only.** A
  gambit arriving from a pre-existing save or from #895's operators is not made
  safe by it.
- ⚠️ **`AIM_FORBIDDEN` may be over-strict for AoE, and that is left open.** The
  ROM lets you place the cursor on your own tile for an ability that carries
  `dont_hit_caster` but not `dont_target_self`; the splash simply skips you.
  For `effect_area > 0` that is a legitimate move — hit the ring, spare
  yourself — and the grader calls it `forbidden` anyway. Re-grading it is a
  behaviour change to ADR-0049's axis and needs its own evidence. Open as
  [#1202](https://github.com/timbermania/fft-monorepo/issues/1202) — which is
  framed as a question, not a defect, because ADR-0276 dec. 4 may already
  account for it.

## Evidence — which half was met

Per the standing bar, both halves are reported rather than merged:

- **STATIC — met, and mechanistically complete.** Every decision above cites the
  instruction, and dec. 1's enumeration over all 13 record-pointer sites is
  closed rather than a name search. dec. 5's absence carries its positive
  control in the same byte.
- **DYNAMIC — partially met, and the gap is named.** Against live PSX main RAM
  mined offline from a battle savestate (`nightsword.sstate`, 8 MiB, protobuf
  field 3 → sub 1):
  - the extracted attribute table is **byte-exact against live RAM for all 368
    records** (368/368, so an addressing error could not have passed);
  - the four gap abilities read `flags1 = 0x09` (`dont_target_self` set,
    `dont_hit_caster` clear) and `Heal` reads `0x08` (clear) **in live RAM**;
  - the engine's working copy at `0x801938F0` carries a set
    `dont_target_self` bit for the action in flight, so the flag demonstrably
    reaches the live action record.
  - ❌ **NOT shown live: the cursor itself refusing the caster's tile.** That
    needs a savestate captured with a targeting cursor open and none exists; the
    available states are mid-effect, and the table at `0x80192DD8` holds no
    marks by then. The claim rests on the decompile at `0x8017A450`. The cheap
    way to close it is a savestate taken at a Squire's `Basic Skill` menu, where
    `ThrowStone`/`Dash` (bit set) and `Heal` (bit clear) give an A/B on one unit.
    Procedure written up as
    [#1203](https://github.com/timbermania/fft-monorepo/issues/1203).

## Consequences

- `tools/generate_ability_database.py` merges `dont_target_self` and whitelists
  it; `AbilityView` exposes it (regenerated, not hand-edited). ADR-0013's
  deferred-flags guard is unaffected — it locks `anim_flags` and
  `rsm_other_id` only.
- `GambitOptions` gains `AIM_UNTARGETABLE` and one clause;
  `GambitEncoderTest`'s census learns the grade (rows still sum to 8,992) and
  gains a positive control plus a four-arm matrix: the rule must FIRE on the gap
  set, must NOT fire on `Heal`, must NOT swallow `ThrowStone`'s `forbidden`, and
  must NOT leak off the caster class onto the other pools.
- `docs/gambit-rules.md` gains **K3** and its stale census line is refreshed
  (it still quoted 6,744 cells from before ADR-0283/0285).
- `docs/context/07-ability-hit-policy.md` gains the term **Aim policy** and
  corrects a sentence this ADR falsifies: it called the `dont_hit_*` triple
  *"the closest thing the tree has to a classifier for what an ability may be
  aimed at"*, and that classifier is `dont_target_self`, a different rule.
- **Verified at baseline with a matched-load control.** Branch `768/776` in
  9.9 min at N=8; the base commit `e1d58ab6d`, re-run in the SAME worktree so
  the commit is the only variable, scored `767/776` in 10.1 min. Six non-passes
  are stable across both arms; the rest SHUFFLE (`GPURangedCombatTest` and
  `EffectStudioTexturePlayheadTest` red on the branch and green on the control,
  `GPUMeleeHitCloudTest` / `GPUTeleportTest` / `SpuClippingMetricsTest` the
  reverse), which is load, not the diff.
