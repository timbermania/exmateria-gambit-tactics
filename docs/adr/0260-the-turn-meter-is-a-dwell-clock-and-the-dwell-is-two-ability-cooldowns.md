# The turn meter is a dwell clock, and the dwell is two ability cooldowns

[ADR-0236](0236-the-turn-meter-is-a-gpu-unit-field-and-it-is-not-called-ct.md) built
the turn meter and deliberately did not set its rate;
[ADR-0242](0242-the-gambit-host-boots-from-one-integer-and-the-gpu-battle-does-not-exist-until-commit.md)
measured what the unset rate feels like — **244 turns to annihilation at Gariland,
a stop every ~0.11 s** — and handed the number to a ticket. This is that ticket's
answer, and it turns out to rest on a **premise correction** rather than on the
arithmetic everyone had been doing.

Built by [#939](https://github.com/timbermania/fft-monorepo/issues/939).

## Status

accepted

## Decisions

**1. A TURN IS A RECONFIGURATION, SO WHAT THIS NUMBER SETS IS DWELL.** Every
attempt to price the turn rate before this one priced it as an *action budget* —
"how often should a unit get to act?" — and every one of them produced a number
that felt arbitrary, because in this mode **a turn is not an action**. Nothing
happens on a turn. The world freezes, an invisible priority list changes, and the
world resumes. What the meter actually sets is how long a gambit config **stays
committed before the player may change it** — its *dwell*.

That reframing is what makes the number decidable, because it supplies the failure
condition the action framing never could: **a config that can be re-tuned faster
than it can express itself is a turn that means nothing.** At `TURN_METER_FULL =
100` a unit was re-aimed roughly **18 times per action it took** (a 17-tick dwell
against a 300-tick cooldown). The player was not being given 385 decisions; they
were being given one decision, 385 times, before anything had happened that could
change the answer.

**2. THE DWELL IS 600 TICKS — TWO ABILITY COOLDOWNS.** All 512 rows of
`assets/abilities/effects.json` carry `cooldown_ticks: 300`, so the action cycle
is a **5-second constant of this game** and the only non-arbitrary unit of measure
in the tree. Dwell is therefore quoted in cooldowns, not in seconds:

- **One cooldown (300 t)** is a twitch: the config has not yet had the chance to
  be *wrong*, which is the thing a reconfiguration turn exists to react to.
- **Three (900 t)** is most of a Gariland fight — each unit gets ~2 turns and the
  mode collapses into deployment with extra steps.
- **Two (600 t, 10 s)** is the first dwell at which a config gets to approach,
  engage, and show you whether its priorities were right.

The stops-per-battle that falls out of that dwell was **projected at ~30 and
measured at 8** (see Measured). The projection assumed a full roster for the whole
battle; Gariland ends with 2 of 11 alive, so attrition — not the meter — is what
sets the count. The dwell is the decision; the stop count is a consequence of it
and of how lethal the fight is, and the two must not be conflated again.

Quoting the dwell in cooldowns rather than in ticks is load-bearing: if abilities
ever stop sharing one cooldown, this decision still says what to do and the
constant follows, rather than silently becoming a number nobody can re-derive.

**3. THE LEVER IS THE METER'S WIDTH, NOT A TICK DIVISOR.** `TURN_METER_FULL` goes
`100 → 3600` — the dwell times the base Speed of 6 (`base_stats.json`, male and
female; monsters 5). The rejected alternative, advancing the meter once every `N`
ticks, reaches the same ratio and is **worse in exactly the way that matters
here**: under a divisor every unit advances on the same tick boundaries, so
crossings quantise into clumps and multiple units come up on the same tick. The
report that opened #939 was *"turns are coming up way too quickly, and they aren't
staggered at the start so they keep happening all at the same time"* — a divisor
fixes the first half by re-manufacturing the second. Widening the meter keeps the
per-tick advance, so crossings land on arbitrary ticks and spread on their own.

**4. SPEED STILL MODULATES THE RECONFIGURATION TEMPO.** `gain = max(1, U_SPEED)`
is untouched, so a Speed-8 unit is re-aimed ~33% more often than a Speed-6 one.
At Gariland this is currently **inert** — every living unit measures Speed 6 — so
the decision is being made for the roster this mode will meet later, not for the
battle it was measured in.
Under the old framing this was self-evidently right (it is FFT). Under decision 1
it is a **new fiction that has to be chosen deliberately**: it now says *agile
units take new orders more often*. Kept, because it is good flavour and it keeps a
ROM-derived stat load-bearing in a mode that would otherwise ignore it. Rejected:
a uniform tempo for every unit with Speed left to drive only the action rate —
defensible, but it hands this mode a flat clock with nothing interesting in it.

**5. THE RATE IS PER-UNIT AND IS NEVER NORMALISED BY LIVING COUNT.** The
fleet-wide stop rate is the per-unit rate divided by the living roster, so a
16-slot ENTD set piece stops ~45% more often than an 11-unit one and every fight
speeds up as it thins. #939 flagged that as a tuning treadmill and asked whether
gain should be divided by the living count to hold stops-per-second constant.
Rejected, and not on fidelity grounds: **it would make the clock a function of the
death toll, so a rollout's meter would depend on kills inside the rollout** — the
AI would be reasoning about a clock it can accelerate by killing, which is a real
distortion of the value function bought for a cosmetic gain. Dwell is a property
of a unit's config; it has no business moving when somebody else dies.

**6. THE OPENING STAGGER WIDENS FOR FREE, AND STAYS FULL-WIDTH.** ADR-0236 dec. 4's
seeded start is `pcg_hash(...) % TURN_METER_FULL`, so it becomes uniform in
`[0, 3600)` with no second edit. This is the half of the report that had no
separate cause: **the stagger was never missing — it was one turn interval wide.**
Spread over a meter that filled in 13 ticks, "uniform in [0, 100)" meant every
unit was ready within a fifth of a second of every other, which is
indistinguishable from lockstep. Rejected: deliberately narrowing the opener so
the battle "gets going" sooner — that re-clusters the first turns, which is the
reported symptom, and deployment (design §9) already owns the setup pass with the
clock stopped.

**7. IT IS A GENERATED CONST, NOT AN ADR-0068 TUNABLE.** `TURN_METER_FULL` is
authored in `combat_common.glslinc` and generated into `GPUCombatPacker.gd`
(ADR-0001), so making it a live slider means promoting it to a battle-header field
or a uniform — a snapshot-layout change every rollout then carries. Rejected for
now: that is real plumbing to save ~30 s of rebuild on a number expected to be
touched a handful of times. If 600 ticks does not settle within a session of
playing it, *that* is the evidence that promotes it, and it becomes its own
ticket.

**8. `SHADER_VERSION` DOES NOT MOVE.** It guards *structural* drift — offsets and
sizes — and no offset changed. A value change to a non-offset const is not a
layout change, and bumping it here would spend the one signal that a packed record
on the device has gone stale.

## Rejected

- **`TurnDirector.playback_rate` as the lever.** The obvious reach and it cannot
  work: it is the between-turn *viewing* rate, and its own doc says the stretch's
  length in ticks is fixed. It stretches the gaps between stops and cannot reduce
  how many stops there are. Still wanted as a viewing control on top of this.
- **A fractional or fixed-point per-tick gain.** Arithmetically identical to
  widening the meter while changing what the field means. No gain, one more thing
  to explain.
- **Shipping the dwell change together with the enemy-turn marker.** Two felt
  changes arriving at once cannot be told apart by the person feeling them.

## Consequences

- The AI's horizon is unchanged at `H = 400` ticks (ADR-0256 dec. 6), but what it
  *covers* changes by a factor of ~48: it used to reach past ~90 fleet-wide stops
  and now reaches ~2. That is healthier for a one-ply search — the rollout now sees the
  consequences of an edit before the next edit lands, which at the old tempo it
  could not. It also means **ADR-0253's owed refit is now doubly owed**: `f` was
  fitted on a corpus generated at the old tempo.
- Thinking beats per battle fall by roughly the same factor, so the beat budget
  (ADR-0256 dec. 6's 250 ms cap) is no longer under pressure from turn *frequency*.
  Raising `rollout.cap_ms` or `H` to spend the recovered budget is a separate
  decision with its own evidence.
- **ADR-0259 dec. 8's `gambit.imperative_watchdog_ticks` default is invalidated and
  re-derived: 120 → 600.** That default was derived *from the meter* — "about eight of a
  Speed-7 unit's own turns" at `FULL` 100 — so widening the meter inverted it: 120 ticks
  is a fifth of one turn at `FULL` 3600, and less than half of one 300-tick cooldown, so
  an unconsumed order would routinely expire before its unit could act on it once, with
  no refund (ADR-0259 dec. 11). Re-priced in the clock it actually races: an imperative
  is spent by an ACTION (ADR-0259 dec. 10), so the deadline is **two ability cooldowns**,
  the same constant dec. 2 uses for the dwell. It therefore lapses exactly when the
  player next gets to re-issue it, and — being priced in the action cycle rather than in
  the meter — **it does not move again if the dwell does**. Still a tunable, still inside
  `WATCHDOG_HINT`'s [15, 1200].

- Design §3's "enemy turns get a cinematic focus beat" is downgraded, by #939's
  answer, to a **brief stop with a marker on the unit**: a reconfiguration has
  nothing to show, and a cinematic is a promise of spectacle it cannot keep. That
  is not built here — it ships as its own ticket so the dwell can be felt alone.

## Measured

`tests/GambitBattleTest.tscn`, scenario 9 (Gariland) played to annihilation with
the AI on, against ADR-0256's 385-turn baseline on the same rig:

| | before | after |
|---|---|---|
| turns to annihilation | 385 | **8** |
| battle length | ~1,650 t | ~1,779 t |
| dwell per unit | ~17 t | **600 t** |

**`U_SPEED` is 6 at Gariland, measured off the GPU, not inferred** —
`[6,6,6,6,6,6,6,6,6,6,6]` for the eleven living units. This is worth writing down
because the ticket's own arithmetic had been quoting Speed 8 from the test rigs,
and because a gain of 1 (which the low turn count first suggested) would have made
decision 4 vacuous. It is not: the ROM stat reaches the kernel.

**Two tests were fixed, and neither was broken by this change.** `GambitSurfaceTest`
arm 5 and `GambitBattleTest` arm 4b both asserted `not adjustment.is_open()` after
a commit, described as "the window closed with the turn". That is a stronger claim
than commit can honour: `TurnDirector.commit` **drains**, so a second unit ready on
the same tick has its turn — and its window — opened inside the same call. The
assertion therefore tested *"no other unit was ready on this tick"*, which is a
property of the battle seed. MEASURED at the new width: unit 1 committed at meter
3602 while unit 4 sat ready at 3601. Confirmed latent rather than introduced by
running the same test at `TURN_METER_FULL = 100`, where it passes with only one
unit ready — and where the seeded meters `[17, 20, 19, 0, 19, 38, ...]` show units
2 and 4 sharing a crossing tick anyway. **It passed on luck and the wider meter
re-rolled the luck.** Both now assert the invariant commit actually owns: the
window is not open *on the committed taker*.

## Soft spots

- **600 ticks is a first felt value, not a measurement.** It is derived from a
  cooldown constant and a battle length, and the only instrument that can refute
  it is a person playing the mode.
- The dwell is priced against **Gariland's** ~1,750-tick length. A materially
  longer or shorter scenario gets proportionally more or fewer decision points,
  and nothing holds that stable — deliberately, per decision 5.
- **The decision count is bounded by battle lethality, and this ADR cannot reach
  it.** Eight stops is what a 30-second fight that loses 9 of 11 units can carry at
  a meaningful dwell. Any attempt to raise the count by shortening the dwell walks
  straight back into decision 1's failure condition; the lever that would actually
  buy more decisions is a longer, less lethal battle, which is nobody's ticket yet.
