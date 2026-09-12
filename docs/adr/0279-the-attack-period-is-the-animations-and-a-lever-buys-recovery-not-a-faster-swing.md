# The attack period is the animation's, and a lever buys recovery rather than a faster swing

[#1107](https://github.com/timbermania/fft-monorepo/issues/1107) opened on two
findings quoted from the kernel's own comments: that basic attack is the only
unlimited action in the game, and that *"a bow is a sword with more reach"*. The
first holds. **The second is refuted by measurement**, and this ADR is shaped
around the refutation rather than around the ticket's proposed mechanism.

Status: accepted (2026-09-10). Resolves #1107 on build map
[#1101](https://github.com/timbermania/fft-monorepo/issues/1101). Reads
[ADR-0277](0277-the-lever-set-is-a-strict-partition-baked-at-load-and-a-hollow-lever-is-an-error.md)
for the lever layer this extends and for the alternative dec. 6 below narrowly
reverses,
[ADR-0032](0032-ranged-damage-waits-in-state-awaiting-impact.md)
for why recovery cannot be a longer `ACTING`,
[ADR-0235](0235-reconfigure-is-an-overlay-and-the-shader-write-set-classifies-the-fields.md)
for the `carry` / `recompute` split that dec. 3 turns on, and
[ADR-0047](0047-real-time-ability-cooldown-is-a-per-ability-floor.md) for the
cooldown mechanism this deliberately does **not** use. Splits
[#1147](https://github.com/timbermania/fft-monorepo/issues/1147) out as its own
defect. **It authors zero factors** — see dec. 8.

## Context

**A per-weapon-type attack period already exists, and it is written.**
`setup_attack_animation` ends on
`write_unit(battle_id, unit_id, U_TIMER, timer_value)` where `timer_value =
max(MIN_ATTACK_DURATION, total_frames_seq)`; `GLOBAL_SPEED_DIVISOR` is `1.0` and
`ABILITY_SEQ_SPEED` is `1`, so the scaling is the identity and the period is the
raw SEQ length. `compute_unit_state` returns early while `timer > 0`, so the
unit cannot re-decide. For ranged weapons the ACTING timer-zero edge hands off to
`LOGICAL_ACTIVITY_AWAITING_IMPACT` with `U_TIMER = damage_frame - anim_frame`,
and that state is one of the five both brakes treat as mid-action — so the flight
tail is the firer's time too.

Ticks from attack commit to IDLE, at each type's native range, measured from the
shipped `type1_seq.json` / `wep1_seq.json` `_timings` and `items.json`:

| weapon type | records | native range | period |
|---|---:|---:|---:|
| Knife…Flail (the nine melee types) | 70 | 1 | 38 |
| Nothing (unarmed) | 1 | 1 | 40 |
| Crossbow | 6 | 4 | 66 |
| Bow | 9 | 5 | **76** |
| Gun | 6 | 8 | **100** |

A bow is **2.0x** a sword and a gun **2.6x**, and both scale with distance at
`max(dist * 10, 15)` flight ticks. **Reach already costs rate, roughly in
proportion to reach.** The map's charted fact — *"no per-weapon recovery… the
downside does not exist to be scaled"* — is wrong in its last clause.

What is actually missing is three things, and only the first two are this ADR's:

1. **The period is unauthored.** Every number above is a SEQ frame count that
   arrived with the sprite data. There is no way to say "bows should be slower"
   without editing an animation.
2. **It is flat across 70 of 127 weapon records.** All nine melee types collapse
   to one `TYPE1_MELEE_SWING`, from Knife (`wp` 3–12) to Knight's Sword (16–40).
3. **The key that produces it is wrong.** `get_attack_anim_id` selects the bow on
   `weapon_type >= WEAPON_TYPE_CROSSBOW`, unbounded, so eight non-ranged types —
   Instrument, Book, Polearm, Pole, Bag, Cloth, Throwing, Bomb, **36 records** —
   draw a bow and pay its 52-tick period. Its bounded sibling `is_ranged_weapon`
   (`10 <= wt <= 12`) disagrees and is right. This is a visual defect with a
   balance side-effect; it is **#1147**, not this ADR, because its blast radius is
   animations and bundling it here would make one change impossible to review.

## Decision

1. **`attack_period` is the seventh lever quantity**, domain `item`, kind `cost`.
   ADR-0277 dec. 4 closed the enum so that a seventh would be a decision rather
   than an edit; this is that decision. `cost` for the same reason
   `cooldown_ticks` is: ticks the unit owes, higher is worse.

2. **Its ROM base is the weapon's SEQ period, not zero — which is why the
   quantity is `attack_period` and not `attack_recovery`.** A lever multiplies
   and never replaces, so a quantity whose base is 0 cannot be authored at all:
   every factor would multiply to 0. The base is real, already per-weapon-type,
   and already in the buffer as `U_TOTAL_FRAMES`. Naming the quantity after the
   tail rather than the span would have made the layer unable to express it.

3. **A levered period is realised as RECOVERY — a tail after the animation —
   never as a longer animation.** ADR-0032 defines `LOGICAL_ACTIVITY_ACTING` as
   covering SEQ playback only, so stretching the ACTING timer would have the
   playback state claim ticks in which no SEQ is playing. Recovery is instead
   `U_TIMER` written on the IDLE edge, the idiom `TICKS_GAMBIT_REEVAL` already
   uses at four sites: IDLE-with-a-timer is a unit that exists but is not yet
   choosing. No new `LOGICAL_ACTIVITY`, so no new animation mapping, no new
   brake-list member, no UI change. `U_ATTACK_RECOVERY` is `BEHAVE_CARRY` and the
   schema guard is why — see Consequences.

4. **The base is the WHOLE PERIOD, not the animation.** `rom_period =
   max(attack_duration, damage_frame)`. For a melee weapon the two are the same
   number — the swing's damage frame is 18, well inside a 38-frame SEQ — so the
   `max` picks the duration and nothing changes. **For a ranged weapon they are
   not**, because `damage_frame` is `projectile_frame + max(dist * 10, 15)` and
   the firer waits that tail out in `AWAITING_IMPACT` before it may choose again.
   Scaling only the animation would make `attack_period x2.0` mean *"x2.0, except
   on the three weapon types where it is x1.68, varying with how far away the
   target stood"* — a quantity whose name does not describe what it does, on
   exactly the weapons this ticket was about.
   ⚠️ **This was the first version's behaviour**, and every melee arm of the test
   passed while it was wrong. The ranged arms exist because of it.

5. **The unlevered period is the floor.** `recovery = max(0, levered -
   rom_period)`, so a factor below 1.0 clamps to zero recovery and cannot make a
   unit act faster than its own sprite and its own projectile. A physical
   constraint, not a policy: there is no shorter SEQ to play and no faster arrow.

6. **The packer bakes the Q8 FACTOR into the unit row, not the levered value.**
   🔴 **This narrowly reverses one of ADR-0277's rejected alternatives** — *"a
   parallel `U_*_FACTOR_Q8` unit field the shader multiplies at use"* — and the
   reversal is deliberate, scoped to this one quantity, and for a reason ADR-0277
   did not have in front of it. All six original quantities have a host-side
   base: `wp`, `weapon_range` and `w_ev` come off the item record,
   `cooldown_ticks` / `charge_time` / `mp_cost` off the ability record. **This one
   does not.** Its base is SEQ frame data in the anim-timings buffer, reachable
   in GDScript only by mirroring `get_attack_anim_id` — and #1147 has just
   established that predicate is wrong. Duplicating a predicate that has proven
   itself wrong, into a second language, to recompute a number the kernel already
   holds, is the trade this refuses; the two copies would disagree the moment
   #1147 lands and the disagreement would split period from animation silently.
   **Dec. 2 of ADR-0277 keeps its purpose intact**: the factor is baked at load,
   is not live-scrubbable, and rides the unit row, so a rollout that forks the
   unit buffer inherits it for nothing. Only the site of the multiply moves.

7. **`attack_period` has no host-side realised-factor report, and that is a named
   soft spot rather than an omission.** ADR-0277 dec. 9's report computes the
   worst realised factor per lever in GDScript, which it cannot do for a quantity
   whose base it does not hold. Building a host-side copy of the base purely to
   report on it would reintroduce exactly the duplication dec. 6 refuses.

8. **No factor is authored here.** #1101's destination rules the final numbers out
   of scope — *"a ticket that says 'pick the damage scale' is unresolvable; one
   that says 'make damage scale measurable against a target, and report where it
   lands' resolves in a session"* — and the measurement above says the motivating
   gap does not exist as stated. Authoring a factor now would be inventing one.
   `levers.json` stays empty; what changes is that the period is leverable and the
   layer has a second bake site a non-identity factor visibly moves.

## Considered alternatives

- **Stretch the ACTING timer instead of adding a tail.** One line rather than a
  new field. Rejected on ADR-0032: `ACTING` is SEQ playback by definition, and a
  unit held in it past its animation is a unit frozen mid-swing.
- **A new `LOGICAL_ACTIVITY_RECOVERING`.** Honest naming, and it would show in the
  debug overlay. Rejected on cost: a new activity needs an animation mapping, a
  row in both brakes' mid-action lists, and a `LOGICAL_ACTIVITY_NAMES` entry, to
  express something IDLE-with-a-timer already expresses at four existing sites.
- **Bake the value and mirror `get_attack_anim_id` in GDScript.** The orthodox
  ADR-0277 dec. 2 shape, and it would keep the realised-factor report. Rejected
  under dec. 6: two copies of a predicate #1147 is about to change.
- **Give attack an ability id and reuse the ADR-0047 cooldown.** Rejected, and
  #1107 warned about it in its own words: ability id 0 is a real ability, and the
  cooldown SSBO is bounded by `MAX_COOLDOWN_ABILITIES`, so attack would inherit
  that ceiling and collide with every unit's slot 0 at once.
- **Fix #1147's unbounded bow arm in this change.** It is two lines and it is
  right there. Rejected: it moves animations for 36 weapon records, so the two
  changes have disjoint blast radii and bundling them makes neither reviewable.
- **Author a first factor to discharge ADR-0277's soft spot S1.** Rejected under
  dec. 8 — the measurement removed the evidence that would have justified one.

## Consequences

- **At factor 1.0 the kernel is unchanged tick for tick.** `U_ATTACK_RECOVERY` is
  0 for every unit whose factor is the identity, which — with the lever set
  shipping empty — is every unit in the game. `consume_attack_recovery` returns
  early and the pre-#1107 fallthrough survives byte for byte. The broad test
  fallout #1107 predicted does not arrive with this change; it arrives with the
  first authored factor.
- **`UNIT_SIZE` 102 → 104 and `SHADER_VERSION` 32 → 33.** Both are generated into
  `GPUCombatPacker.gd` from the shader by `tools/gen_gpu_layout.py` (ADR-0001).
- **`U_ATTACK_RECOVERY` is `BEHAVE_CARRY`, and a guard is why.** Written
  `BEHAVE_RECOMPUTE` first; `GPUBatchSimulator`'s schema check refused it —
  *"'attack_recovery' is 'recompute', but the shader WRITES it — a live field must
  be 'carry' or 'clamp' or reconfigure silently resets it"*. The case is real: a
  turn is an opportunity to reconfigure a unit (ADR-0260) and a unit mid-swing
  still gets one (ADR-0236 design S3), so a RECOMPUTE would re-pack 0 over the
  recovery a levered weapon had just been charged, at the one moment it mattered.
- **ADR-0277's soft spot S1 is NOT discharged**, because dec. 8 declines to author
  a factor. What is discharged is the weaker claim that no bake site could be
  proven end to end: `AttackPeriodTest` drives a non-identity factor through the
  packer into the kernel and measures the realised tick gap in a live battle.
- **An unarmed unit cannot be levered.** `item_factor_q8` answers the identity for
  `item_id < 0`, and 5,103 of 5,657 deployed ENTD slots name no weapon
  ([#1121](https://github.com/timbermania/fft-monorepo/issues/1121)), so this
  layer's live reach is bounded by that ticket and not by this one.

## Verification

**Static and dynamic agree to the tick**, which is the whole claim.

`AttackPeriodTest` puts every arm **in a single battle on a single tick clock** —
a duration compared across two runs measures the box as much as the change — each
differing from its own control in exactly one field, `attack_period_factor_q8`:

| arm | weapon | factor | modal gap | added |
|---|---|---|---:|---:|
| Control | sword | x1.0 | 40 | — |
| Doubled | sword | x2.0 | 78 | **+38** |
| Halved | sword | x0.5 | 40 | +0 |
| BowControl | bow @ dist 3 | x1.0 | 59 | — |
| BowDoubled | bow @ dist 3 | x2.0 | 115 | **+56** |

Statically `TYPE1_MELEE_SWING` is 38 frames, and `+38` is that exactly. The bow's
`+56` is `max(52, 26 + 30)` — **the period, not the 52-frame animation**, which
is dec. 4's whole claim. `halved == control` is dec. 5's floor.

**Three seeds were run, not argued**, and each reds a different arm:

- `consume_attack_recovery` returning unconditionally collapses every arm onto
  its control and reds both lever arms.
- `rom_period = timer_value` (the animation rather than the period) leaves every
  melee arm GREEN and reds only the bow: *"added only 52 ticks against a control
  gap of 59"*. This is the defect the ranged arms were added for, and it is the
  reason a melee-only version of this test was not enough.
- Removing the Q8 clamp in `LeverSet.item_factor_q8` lets a composed
  `20.0 x 20.0` reach the kernel as Q8 102400 and reds `LeverSetTest`'s clamp arm.

**The instrument names its own subject, because once it did not.** The first
version seated five attackers on team 0; a battle is **4v4**, the fifth was
dropped with no error, and slot 4 belongs to the dummy — so the test read the
dummy's 40-tick melee gaps as a bow's and reported them confidently. Every arm
now asserts its slot's `weapon_type` and `attack_period_factor_q8` before any
timing assertion runs.

## Soft spots

- **S1. No host-side realised-factor report for `attack_period`** — dec. 7. The
  resolution belongs with [#1111](https://github.com/timbermania/fft-monorepo/issues/1111),
  which owns the verdict.
- **S2. The lever set is still empty** — dec. 8. No shipped path bakes a
  non-identity factor; only the test does.
- **S3. The period is still keyed off the animation**, so until #1147 lands, a
  Polearm's `attack_period` base is the bow's 52 rather than the melee 38 — and a
  lever authored against `item_type: Polearm` today would scale the wrong base.
- **S4. Melee is one bucket.** A lever can distinguish Knife from Knight's Sword
  by `item_type`, but their *bases* are identical, so the tier can only express
  differences it invents rather than differences the ROM data carries.
