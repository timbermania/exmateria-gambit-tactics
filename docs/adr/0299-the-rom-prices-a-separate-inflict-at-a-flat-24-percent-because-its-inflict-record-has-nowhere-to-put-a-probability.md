# The ROM prices a separate inflict at a flat 24%, because its inflict record has nowhere to put a probability

[#1117](https://github.com/timbermania/fft-monorepo/issues/1117) asked what
`INFLICT_MODE_RANDOM` and `INFLICT_MODE_SEPARATE` should do. `apply_inflict_all`
implemented `ALL` and `CANCEL` and fell off the end for the other two, while
`StatusEncoder.mode_from_string` translated all four faithfully — so the encoder was
honest and the shader silently dropped half of what it was handed. Measured over
`effects.json`: **27 of the 155 status-bearing abilities inflicted nothing**, with no
warning at encode time and no branch at apply time. The casualties include `MimicDaravon`
(Sleep), `GalaxyStop` (Stop + Immobilize + Disable), the whole Bio family and every
`separate`-mode monster ability.

The ticket flagged the hard part correctly: *"Both need a per-status probability, which
`effects.json` may or may not carry; check before designing."* It does not carry one.
**Neither does the ROM** — and that absence is what fixes the design.

## Status

accepted

## Context: one function, four modes, and a six-byte record with no room for odds

An ability's `inflict_status` byte (secondary-data offset 0x0B) indexes
`InflictStatusList`, **128 entries of six bytes** at SCUS RAM `0x80063FC4` (file offset
0x547C4, ending at the `ItemAttributes` label — 0x300 bytes). Each entry is **one mode
flag byte plus a five-byte status set**, MSB-first: `0x80` all, `0x40` random, `0x20`
separate, `0x10` cancel. That is the whole record. There is no probability column, no
per-status weight, and no room for one.

Decoded, the vanilla table is 75 `all`, 18 `cancel`, 15 `separate`, 10 `random` and 10
all-zero reserved entries. **No entry sets two mode bits, and none uses the low nibble** —
so `decode_inflict_mode`'s documented "highest priority wins" fallback never fires on
stock data, which is the positive control for reading the byte as a single-choice enum.

`BATTLE.BIN 0x8018B904` is the consumer: it multiplies the set id by six, adds
`0x80063FC4`, and copies the six bytes to scratch at `0x80193906` (mode) /
`0x80193907..0B` (statuses). **`FUN_80187F24` (BATTLE.BIN `0x80187F24`)** is where the
mode is spent, and it resolves the mode to a mask BEFORE it touches the unit:

- **`0x20` SEPARATE** — for each of the 40 status bits that is set, call
  `pass_fail_roll(100, 0x18)` (SCUS `0x8005E0CC`, labelled on FFHacktics as
  *Pass/Fail Roll*: returns true when `roll(0..99) >= threshold`). The **true** branch
  XORs that status back OUT of the scratch set at `0x80188110`. So a status is KEPT when
  the roll comes in under 24 — **a flat 24%, independent of the ability**.
- **`0x40` RANDOM** — walk the 40 bits, push the set ones onto a stack array, then index
  it with a single draw: `FUN_8018EEA0() * count >> 15`. **Uniform over the bits
  present**, and exactly one of them.
- **`0x80` ALL** — OR all five bytes onto the action's add-set at `+0x1B`.
- **`0x10` CANCEL** — OR them onto the remove-set at `+0x20` instead.

Two details in that function matter to the port and neither is the mechanism:

**The `>>= 2` on `[action + 0x2A]` is bookkeeping, not a second gate.** The SEPARATE
branch quarters that halfword before anything else. `+0x2A` is never a roll argument
anywhere in BATTLE.BIN: every reader multiplies into it (`FUN_80187510` does
`[+0x2A] = [+0x4] * [+0x2A] / 100` and rolls against `+0x4`; `FUN_80184360` does the same
against its own local), it is initialised as `100 - unit[+0x24]`, zeroed on the
no-effect path, and read once as `if ([+0x2A] == 0) cancel the action`. It is the
**running product of the component chances — the predicted-success percentage** the game
shows and the AI scores. Quartering it is how the ROM books the 24% into that display
(24% ≈ ¼). Our kernel displays no such number and composes no such product, so it has
nothing to carry the quarter *into*; carrying it anyway would apply the penalty twice.

**`DAT_8018F5FC` forces RANDOM and SEPARATE to ALL when it is non-zero**, which is the
AI/preview pass asking what the action *could* do. One consequence is dead code the port
should not reproduce: the SEPARATE loop's `|| DAT_8018F5FC == 2` disjunct can never be
reached, because the override above it already redirected every non-zero value to the
ALL branch.

## Decisions

**1. SEPARATE's per-status chance is a constant, and the constant is 24.**
`INFLICT_SEPARATE_KEEP_PCT = 24` in `combat_common.glslinc`, cited to
`pass_fail_roll(100, 0x18)` at `0x801880E8`. Not 25, and not derived from the ability:
the six-byte record has no probability column, so there is nothing per-status to read and
the ability's own hit rate is spent deciding whether the inflict site is reached at all.
A nine-status `separate` set (GrandCross) therefore lands **2.16 statuses on average**,
and the Bio family's single-status sets land ~1 in 4 — which is the reputation those
spells have.

**2. RANDOM is uniform over the bits PRESENT, so a short mask skews the pick rather than
losing a status.** The ROM enumerates its five-byte set; we enumerate a 32-bit mask that
`StatusEncoder` has already dropped five names from (#99). Measured, exactly one
`random`-mode record is affected — Muramasa and Nightmare each list Death Sentence — so
their "pick one of two" is currently a pick of one. **That is #1119's debt, named here so
a later reader does not read the determinism as a bug in this decision.**

**3. The mode resolves to a mask, and then there is ONE apply.** `resolve_inflict_mask`
narrows the listed set; `apply_inflict_all` writes the result. This mirrors the ROM's own
shape (`FUN_80187F24` filters the scratch copy in place and only then ORs it onto the
unit) and it is what keeps #1116's producer correct: the countdowns are armed off the
**resolved** mask, so a status a SEPARATE roll dropped cannot get a countdown for a flag
it never set. The alternative — a fourth and fifth `else if` branch beside ALL and CANCEL
— would have had three copies of the one-write-then-arm-per-bit dance and three chances
to arm the wrong set.

**3b. BOTH RESOLVE LOOPS WALK THE SET BITS, AND THAT IS A COMPILE-TIME DECISION
WITH A MEASUREMENT BEHIND IT.** `resolve_inflict_mask` is inlined at nine call
sites, so a `for (b = 0; b < 32; b++)` in it is a 32x unrolled body at every one.
The first version had exactly that and it cost **+2.5 s on a cold pipeline build**:
`warm_pipelines_async`'s eight stages took 11.1 s against 8.8 s for a comment-only
control at the same commit with an equally cold driver cache. That is not an
abstract cost — 11 s of async compile outlives a short test's `quit()`, and
`GambitDeploymentPickerTest` scored THREW in both repeats on `GPUEffectTimingLoader`
reading a freed autoload *after* printing its own `[PASS]`. Walking the set bits
(`m &= m - 1` to clear the lowest, `findLSB` to name it) makes the trip count the
number of statuses LISTED — one to nine in the shipped data, never thirty-two — and
took the build to 10.1-10.2 s and the suite to 103/103 across two repeats. **The
teardown race itself is not this ticket's and is not fixed here**: it is latent in
any shader edit, since any shader edit makes the driver's pipeline cache cold.

**4. The RNG is `rand_int`, salted, and the salt is load-bearing.** `rand_int` folds
`(battle_seed, seed slot, tick)` into a hash, and the status hit roll at the same
`(caster, target, tick)` already seeds on `caster * 100 + target` (`roll_break_hit`). An
unsalted inflict roll would be **that same draw read again at a new modulus**, correlating
"did it hit" with "which status landed". `INFLICT_RNG_SALT = 7919`, and SEPARATE walks it
per bit (`salt * (b + 1)`) so the nine rolls of one cast are nine draws and not one.

**5. `apply_inflict_all` keeps its name, and the name is now wrong in three ways.** It
predates CANCEL (#100) and both of these. Renaming it would orphan the citations in three
ADRs (0049, 0293, 0298), five docs and a test, for no behavioural gain — ADRs record what
was decided and editing one to follow a later rename is worse than a stale-sounding name.
The docstring says `_all` is historical and not a mode.

**6. THE CONTRADICTION IS CAUGHT AT ENCODE TIME, AND THE PAIR IS THE UNIT.**
`StatusEncoder.inflict_for_record(names, mode, what)` resolves the mask and the mode
together and `push_error`s on a record that names an unknown mode, or that lists statuses
with no mode at all. Both encode sites (`GPUAbilityLoader`, `weapon_inflict_for_item`)
route through it. The class it closes is the ticket's third question: a non-zero mask
beside `MODE_NONE` encodes cleanly and inflicts nothing, once per cast forever, and
neither half could see it while they were resolved by separate calls. It is a **ratchet on
a clean tree** — measured zero violations across every ability and both item blocks, and
the ROM's own table has none either — not a threshold on a tolerated class.

**7. What this does NOT fix is named, not counted.** Three of the 27 records carry a
mask and still reach no inflict site, because their formula is not one of
10/11/42/56/80 and they have no AOE: **Blaster (f61), CrushPunch (f45) and BloodSuck
(f71)**. A fourth, SplitPunch, lists only Death Sentence and so encodes to an empty mask
(#1119). The ticket scoped that class out and it stays out; this ADR names its four
members so the next census does not rediscover them as a surprise.

## Evidence

- **Static, ROM.** `InflictStatusList` @ SCUS `0x80063FC4` (128 × 6 bytes, decoded by
  `tools/_fft_decode.py::extract_inflict_status_sets`); its one consumer
  `BATTLE.BIN 0x8018B904`; the mode dispatcher `FUN_80187F24` @ `0x80187F24`; the
  per-status roll `pass_fail_roll(100, 0x18)` @ `0x801880E8`; the RANDOM draw
  `FUN_8018EEA0` @ `0x8018EEA0` (called from `0x80188044`); the AI/preview override `DAT_8018F5FC`.
- **Static, data.** 128-entry census: 75 all / 18 cancel / 15 separate / 10 random / 10
  reserved; **zero** entries with two mode bits set, zero using the low nibble, zero with
  statuses set and a zero mode byte. `effects.json`: 114 all / 14 cancel / 11 random / 16
  separate.
- **Dynamic, this kernel.** `tests/GPUInflictModeTest.gd`, four arms in one battle.
  RANDOM: LookofDevil (f80, five statuses) set **exactly one** across every run. SEPARATE:
  GrandCross (f56, nine statuses, radius 2) over three targets in one cast gave **2 / 3 /
  4** and **2 / 0 / 0** and **3 / 0 / 0** of nine on successive runs — three different
  subsets from one cast, which is the claim no other mode can satisfy.
- **Both directions, seeded.** Making RANDOM take the ALL path reds arm 1 and only arm 1
  (`5 of 5 listed statuses`); making SEPARATE take it reds arm 3 and only arm 3 (`all
  three targets came out with the same status set`). **The second seed is why the test has
  a settle window**: the first version snapshotted when the first bit appeared and the ALL
  seed still PASSED, because `cast_cinematic_spell` gives each in-radius target its own
  fire frame and the third target had not been hit yet.
- **Compile time, controlled.** Cold-cache pipeline build of the eight stages,
  measured on `GambitDeploymentPickerTest`'s own log line: **46 ms** warm; **8.8 s**
  for a comment-only edit at the base commit (the cold control — a comment changes
  the SPIR-V source hash and nothing else); **11.1 s** for the first version of
  `resolve_inflict_mask`; **10.2 s** and **10.1 s** for the set-bit version across
  two repeats. The cold control is what makes this attributable: a cold cache alone
  reproduces the 8.8 s and does NOT reproduce the failure.
- **Not dynamically validated against PSX.** Nothing here was confirmed on the real
  hardware; the 24 and the uniform pick are a static read of two functions. See Soft spots.

## Rejected alternatives

- **Deriving the per-status chance from the ability's hit rate.** The intuitive reading
  of "separate" — each status rolls the ability's own hit% — and it is not what the ROM
  does. The roll is `pass_fail_roll(100, 0x18)` with an immediate, in a function that
  never reads the ability. Adopting the intuition would make GrandCross (f56, no hit roll
  at all) inflict all nine every time.
- **Quartering the hit chance as well as rolling 24%.** The literal transcription of
  `[+0x2A] >>= 2`, and it double-counts: `+0x2A` is a display/AI accumulator that is never
  rolled against, and the quarter exists precisely *because* of the 24%.
- **A per-ability probability field.** There is nowhere to put one. Six bytes, one of
  them the mode.
- **`bitCount` replaced by a hand-rolled loop** for stylistic consistency with the rest of
  the shader. `#version 450` has the instruction; counting bits by hand to match a file
  that never needed to count them is not consistency.
- **Renaming `apply_inflict_all`** — see decision 5.
- **Failing loud at APPLY time on an unhandled mode.** The ticket offered it. A shader
  cannot raise, the per-cast frequency makes a log useless, and after this ADR the set of
  unhandled modes is empty; the encode-time guard in decision 6 catches the same fault
  before the buffer is packed.
- **A rate-band test** measuring the 24% directly. This suite already has six tests
  skipped for exactly that (`tests/skip_tests.tsv`, the GPUEvasion* family, #539): a band
  over a handful of GPU casts measures the box. The shape invariants in decision 3's
  witness do not.

## Soft spots

- **S1. The 24 is static-only.** Standing bar here is static-rooted AND
  dynamically-validated; this ADR meets the first half. A PCSX arm — break on
  `0x801880E8`, count the survivors of a known `separate` set over N casts — would settle
  it and is not expensive. Until then, the strongest corroboration is indirect: 24 ≈ ¼ and
  the same function quarters the displayed chance.
- **S2. Arms 3 and 4 of the witness are probabilistic.** P(all 27 rolls fail on a correct
  shader) = 0.76²⁷ = **8.2e-4**, and that is the only false red. The number assumes all
  three targets are in the blast, which is CONTROLLED (three ALL-seeded runs put all three
  at 9 of 9) rather than assumed — unit placement is not pinned by the engine.
- **S3. RANDOM's uniformity is asserted structurally, not statistically.** The witness
  holds "exactly one landed", which reds under ALL and under the old fall-through, but a
  pick that always returned the lowest set bit would pass it. That is a property of
  `rand_int`, which every other roll in this kernel already leans on.
- **S4. The teardown race this exposed is still there.** `warm_pipelines_async`
  compiles on a `WorkerThreadPool` task that can outlive the scene's `quit()` and
  then reads autoloads that are already freed, which the runner scores THREW even
  though the test printed `[PASS]` and `109 passed, 0 failed`. Decision 3b bought
  ~1 s of margin; it did not remove the race, and the next shader edit that costs a
  second of compile will find it again. Filed separately.
- **S5. Decision 2's skew is live.** Two abilities' RANDOM picks are deterministic today
  and will silently stop being so when #1119 lands — correctly, but nothing fails when it
  changes.
