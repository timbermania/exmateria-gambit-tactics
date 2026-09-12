# The cooldown is the ability's own period, and the ceiling was the index not a budget

## Status

Accepted

Built by [#1108](https://github.com/timbermania/fft-monorepo/issues/1108), on
build map [#1101](https://github.com/timbermania/fft-monorepo/issues/1101).
Amends [ADR-0047](0047-real-time-ability-cooldown-is-a-per-ability-floor.md)
decisions 1, 2 and 6; 0047's decisions 3, 4 and 5 stand unchanged.

## Context

Every one of the 512 abilities carried `cooldown_ticks: 300`, hand-authored as
`DEFAULT_COOLDOWN_TICKS` in `tools/parse_abilities.py`. It was the **only**
hand-authored number in a balance corpus that is otherwise ROM-faithful, and it
made every ability in the game interchangeable on rate.

ADR-0047 dec. 2 argued a single global value was safe:

> cooldown counts from *commit*, not from animation end: a CT-bearing ability
> spends most of its action lifetime in `SPELL_CHARGING` after the commit, so
> the floor has long expired by the time charging finishes … Only CT=0
> abilities — Punch Art, Knight Skills — actually feel it.

🔴 **That justification is false, and measuring it is what made this ticket
sharp.** The charge period is `ct * 30` ticks (`GPUAbilityLoader.gd`), so it
exceeds a 300-tick floor only above `ct 10` — **six abilities**. Counted over
the shipped table:

| CT-bearing abilities (144 total) | count |
|---|---|
| flat 300 **binds** (cooldown > charge period) | **123** |
| exactly equal (`ct 10`) | 15 |
| floor genuinely inert (`ct` 13/15/20) | 6 |

The flat floor added between **+30 and +240 ticks** on top of FFT's own cadence,
for 123 abilities — 72 of the 87 that sat below the old ceiling and were actually
gated. It did not merely fail to differentiate. It **overrode the differentiation
the ROM already had**, flattening a 2–20 spread onto one number.

`ct` is not the cooldown and must not be copied into it: the kernel already
spends the spelling "CT" on an ability's **charge period**
(`AB_CHARGE_TIME` / `get_ability_charge_time`), and `combat_common.glslinc`
refuses to reuse the name for the turn clock for exactly this reason. `ct` is
read here as *evidence of what FFT considered an ability to cost*.

Three populations, not two — the map's charted facts said "224 at `0`, the rest
2–20" and that is incomplete:

| population | count | ids < 128 |
|---|---|---|
| `ct` present, `== 0` | 224 | 41 |
| `ct` present, 2–20 | 144 | 87 |
| **`ct` field absent entirely** | **144** | 0 |

The 144 absent ones are ids 368–511 (Reaction 32 / Support 32 / Movement 24 /
Item 14 / Throwing 12 / Jumping 12 / Charging 8), carrying a 20-field record
instead of 37. **Absent is not zero.**

## Decision

**1. The cooldown of a CT-bearing ability IS its charge period** — `ct * 30`.
Not zero, and not a second price. The kernel's effective spacing between two
commits is `max(charge, cooldown)`, so at factor 1.0 the ability paces exactly
as FFT paced it, while the lever layer still has a real, non-zero base to scale.
A base of `0` would be unleverable (`0 × anything` is `0`) and would read as a
hollow lever under [ADR-0277](0277-the-lever-set-is-a-strict-partition-baked-at-load-and-a-hollow-lever-is-an-error.md)
dec. 9. This is what ADR-0047 dec. 2 *intended* and did not achieve.

**2. A free-and-instant ability is priced by JP, mapped onto FFT's own ct
scale.** For the 224 records at `ct == 0` the floor is the whole price and must
come from somewhere else. **MP cannot carry it — 209 of the 224 cost 0 MP.** JP
can: it is what FFT charges to learn the ability, the only ROM number separating
Wave Fist from Holy Explosion. `virtual_ct = jp_cost / 50`, then the same `* 30`,
so one derivation and one unit system covers both populations. `JP_PER_CT_UNIT
= 50` is chosen so the observed JP range (10–900) lands on the range the ROM's
own `ct` already occupies (2–20) rather than on an invented scale.

**3. What the ROM does not price keeps the bare floor.** 127 of the `ct == 0`
records are unlearnable monster/enemy skills at 0 JP *and* 0 MP, and the 144
records with no `ct` field are mostly ADR-0277-unreachable anyway. Both keep 300,
which is what they had, so nothing regresses. ⚠️ Only **3 of those 127** sat below
the old ceiling, so that tail is nearly all newly-gated.

**4. The 300-tick floor itself is unchanged, and it is a floor, not a default.**
The derivation may raise a value above it, never undercut it. #92/#93 established
300 empirically: the original 60 left no fall-through window for a `ct == 0`
ability like Secret Fist whose cast animation is itself ~60 ticks of `ACTING`, so
the slot-1 `ATTACK` fallback never had room to commit.

**5. The ceiling is deleted, not raised — `MAX_COOLDOWN_ABILITIES` is now the
whole ability table (512 == `MAX_ABILITIES`).** The old 128 let
`ability_id >= MAX_COOLDOWN_ABILITIES` fall through the veto as a no-op,
justified as "summons / cinematic spells have CT-or-projectile-bounded natural
rate limits". Counted, that does not hold: of the 384 ids above 128, **240 are
ordinary `Normal` abilities**, an ungated tail wider than the gated head. It was
a fair reading only while every cooldown was the same 300; once the floor is
derived, an ungated tail is a live balance hole.

**6. It was measured before being raised, and the measurement contradicted the
ticket's own worry.** #1108 asked whether the flat indexing
(`unit_global_idx * MAX_COOLDOWN_ABILITIES + ability_id`) makes raising it
expensive, "per-unit-per-battle, so it multiplies by the rollout fleet". It does
not:

- **VRAM** is `total_units * MAX_COOLDOWN_ABILITIES * 4` bytes — the default
  1024×8 fleet goes **4 MiB → 16 MiB**.
- **Per beat**, the rollout forks through `snapshot_battle` / `restore_battle`,
  which is `RolloutHarness.fill_ms`. The budget bench recorded
  **0.73 ms of a 318.87 ms beat** (`tests/logs/rollout_budget_attack_all.csv`) —
  **0.23%**. Even quadrupled it stays far inside ADR-0237's 250 ms cap.
- **Per tick, nothing at all.** ADR-0047 dec. 4 deliberately kept this buffer
  out of the unit struct, so it is not in `copy_unit_to_next`.

**7. `MAX_COOLDOWN_ABILITIES` stays a LITERAL integer in the shader, and a host
guard reconciles the two registers.** ADR-0277 dec. 8 derives cooldown
reachability by regex-scanning `const int MAX_COOLDOWN_ABILITIES = (\d+)` out of
`combat_common.glslinc` (`src/balance/LeverSet.gd`), and an unread ceiling is an
**error** there rather than "everything is reachable" — spelling it
`= MAX_ABILITIES` would silently break that scan. Since the number therefore
lives in two files, `GPUBatchSimulator` refuses to initialize if
`MAX_COOLDOWN_ABILITIES != MAX_ABILITIES`; drift would silently un-gate the ids
in the gap, which is precisely the failure the old ceiling caused on purpose.

**8. `SHADER_VERSION` 33 → 34.** The cooldown SSBO and the `snapshot_battle`
image both change width, and `restore_battle` already refuses a snapshot whose
`shader_version` does not match.

## Verification

**ADR-0277 dec. 8's claim was tested, not assumed** — the ceiling moved with no
edit to `LeverSet.gd` and no edit to ADR-0277. `LeverSetTest`'s own summary line
now reads `cooldown ceiling 512`, and `tools/probe_cooldown_reach.gd` re-measures
the derived coverage through LeverSet's own predicate rather than a Python
replica of its regex:

| of the 91 ability category classes | ceiling 128 | ceiling 512 |
|---|---|---|
| cooldown reaches every member | 17 | **86** |
| reaches none | 60 | **4** |
| straddles the ceiling | 14 | **1** |

421 of 512 ability records now reach `cooldown_ticks`. ⚠️ ADR-0277 dec. 9's
"60 … and 14 straddle" is a **measurement with a date**, not an invariant, and is
deliberately left standing there.

**The derivation lands on 17 distinct values where there was 1** — and 15 of
them below the old 128 ceiling, i.e. where the kernel could already consume them:

```
  60 x9    90 x16   120 x29   150 x25   180 x12   210 x21   240 x4
 270 x7   300 x372  330 x1    360 x3    390 x2    420 x2    450 x2
 480 x3   540 x1    600 x3
```

123 abilities got faster, 17 slower, 372 unchanged. The regeneration diff was
**attributed before it was trusted**: the parser was first run unchanged into a
temp dir and came back byte-identical to the committed `effects.json`, so the
only field that moves is `cooldown_ticks` (140 records) with key order untouched.

**The guard is direction-tested.** `LeverSetTest` arm 9 rides the existing
process (charter clause 13 — it already holds the ROM table and the scanned
ceiling). Collapsing `derive_cooldown_ticks` back to a flat default reds exactly
arms 9a and 9b, and the failure message recomputes "**123 of 144**" from inside
the running game, independently of the offline measurement above. Arms 9c/9d/9e
stay green under that seed, so they are independent rather than one blob; 9e is
the control that the reachability predicate can still say *no* (it refuses 91
ids), without which "1 straddling" would be indistinguishable from a blind yes.

## Considered options

**Raise the ceiling to 512 but keep the flat 300.** Rejected: it gates 240 more
abilities at a rate the ROM never chose, widening the flatness rather than
fixing it. The two halves of #1108 are not independent.

**Re-key the SSBO to a small per-unit `(ability_id, ready_at)` table instead of a
dense array over the id space.** Genuinely tempting and *nearly* shipped: a unit
can only ever gate the abilities named in its own gambit slots, and
`MAX_GAMBITS = 6`, so `action_id` — whose sole producer is
`get_gambit_action_id` (`stage_compute.glsl:636`) — can take at most six distinct
values per unit. The dense 512-wide row therefore carries ≤6 live timers and is
>98% dead weight, and a 6-pair table would both delete the ceiling *and* shrink
the buffer. **Rejected on the measurement in dec. 6**: the cost argument that
motivated it does not exist (0.23% of a beat), so this would be a
correctness-neutral rewrite of the kernel's indexing, a `SHADER_VERSION` bump and
a snapshot-shape change bought with elegance alone. It also needs an
insert/evict policy that ADR-0047 dec. 4's "two slots naming one ability share
one timer" semantics does not currently need. Worth revisiting only if the
cooldown buffer ever shows up in a profile.

**Copy `ct` straight into `cooldown_ticks`.** Rejected: they are different
quantities (dec. 1's context), and it leaves the 224 `ct == 0` abilities — the
exact set the floor was built for — at zero.

**Derive the `ct == 0` price from MP.** Rejected on measurement: 209 of the 224
cost 0 MP, so the field cannot separate them.

**Treat an absent `ct` as `ct == 0`.** Rejected: it would hand the full derived
floor to the 144 Reaction/Support/Movement/Item/Throwing/Jumping/Charging
records, pricing abilities ADR-0277 already classifies as unreachable.

**Lower the 300 floor so JP differentiates further down the range.** Rejected: it
re-opens #93. The floor would have to be the ability's own `ACTING` animation
length, which is SEQ frame data in the anim-timings buffer and is not reachable
host-side (the same constraint ADR-0279 dec. 6 hit).

## Soft spots

- **S1. The `ct == 0` set differentiates only above 500 JP.** With the floor at
  300 and `JP_PER_CT_UNIT = 50`, a JP price below 500 rounds under the floor, so
  97 learnable abilities produce just 7 distinct values and 127 unlearnable ones
  produce one. The tail is differentiated; the middle is not.
- **S2. `JP_PER_CT_UNIT = 50` is the one invented constant here.** It is
  principled (it maps the ROM's JP range onto the ROM's ct range) but it is not
  measured against play, and #1101 rules the final numbers out of scope.
- **S3. Nothing has played a battle at these rates.** 123 abilities got faster
  and the map's whole thesis is that battles should get *longer*; re-timing is
  the pacing layer's job, but the interaction is unmeasured until
  [#1110](https://github.com/timbermania/fft-monorepo/issues/1110)'s rig runs.
- **S4. The 91-refusal control counts Reaction/Support/Movement.** It proves the
  predicate is not blind, but it does not prove the predicate is *right* about
  any particular ability.
- **S5. `TICKS_PER_CT_UNIT = 30` is a second register.** The parser mirrors
  `GPUAbilityLoader.gd`'s `ability.ct * 30`; nothing holds those two together,
  and LeverSetTest arm 9b would only notice the drift if it made a cooldown
  exceed a charge period.
