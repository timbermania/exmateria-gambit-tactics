# The ROM says how long a status lasts, and it gives sixteen of them a byte to count it in

[#1116](https://github.com/timbermania/fft-monorepo/issues/1116) asked where a status
duration comes from. The kernel had a complete decay **consumer** and no **producer**:
[#1105](https://github.com/timbermania/fft-monorepo/issues/1105) measured that
`set_status_with_timer` — the only writer of a non-zero timer slot — had **zero call
sites**, so every status inflicted in a battle was permanent for that battle, and
`tests/GPUStatusDecayTest.gd` was green throughout because it seeded a countdown and
therefore never touched the producer.

The ticket offered three honest options for the number: a per-status constant table, a
per-ability field extracted from the ROM *if one exists*, or a single global scalar in
the lever layer. **One exists**, and finding it also answered the ticket's other two
questions — which statuses are permanent by design, and what happens when the eight
timer slots are full.

## Status

accepted

## Context: the ROM's table, and the three sites that fix its shape

The status-attribute table is 40 records of 0x10 bytes at SCUS RAM **0x80065DE7**
(file offset 0x565E7), one per FFT status in `STATUS_NAMES_BY_BYTE` order. Byte +0x00 is
the default duration in **CT units**. Three disassembly sites pin it, and it takes all
three:

1. **`Initialize_Status_Check_Data` (SCUS 0x80059854)** loops `i = 0 .. 0x27` adding
   `0x10` per iteration, reading flag bytes at `0x80065DE8 + 0x10*i` and `+1` to build the
   eleven derived `status_check_table` rows. That fixes the **entry count** (40) and the
   **stride** (0x10) — and nothing else.
2. **`Status_CT_Set` (SCUS 0x8005DB70)** computes `sll v1, status, 4` and then
   `lbu param_1, 0x5DE7(at)` with `at = 0x8006`. That fixes the **record base**, one byte
   BELOW the flag bytes above. The distinction is not pedantry: aligning records to
   `...DE8` shifts the duration column one status off its owner and reads Sleep = 24,
   Don't Move = 60 and Death Sentence = 0xF2 — a plausible-looking table that is wrong in
   every row.
3. **The same function's store**, `sb param_1, 0x5D(v1)` where `v1 = unit + (status - 0x18)`
   behind `sltiu (status - 0x18), 0x10`. That fixes **who can be timed at all**: the
   per-unit countdown array is sixteen bytes at `unit+0x5D`, one per status 24..39.

The decoded column is its own cross-check — Sleep 60, Stop 20, Haste 32, Poison 36,
Don't Act 24 and Death Sentence 3 are the durations FFT is documented to have — and the
extractor asserts the pairing the three sites imply: **the sixteen statuses with a
non-zero CT are exactly the sixteen with a countdown slot.** A mis-decoded base breaks
that equality.

`BATTLE.BIN 0x8018D910` is the decrementer (`unit[0x5D + i] -= 1` for `i = 0..0xE`,
queueing the removal when a counter reaches zero). Death Sentence (slot 15) sits outside
that loop because it counts the unit's **turns**, not clock ticks.

## Decisions

**1. The duration is the ROM's, extracted once and mirrored twice.**
`tools/extract_status_attributes.py` writes the debug artifact with its citations
(`tools/extracted/status_attributes.json`); `StatusRegistry.DEFAULT_CT` is the
game-facing table keyed by this repo's own status names (ADR-0013 — bit decoding stays at
the parser, the consumer owns the name → bit mapping); `combat_common.glslinc`'s
`status_default_ct` is the shader's copy. `StatusRegistryTest::_test_duration_parity`
holds the last two equal **in both directions**, because the existing bit-parity arm
cannot see them: it regexes `const int STATUS_*` declarations and these are switch arms.

**2. Zero is a ROM answer, not a hole.** Sixteen of FFT's forty statuses carry a
duration and twenty-four do not, because only statuses 24..39 have a byte to count down
in. So Darkness, Silence, Oil, Frog, Confusion, Berserk, Petrify, Blood Suck, Float,
Reraise and Transparent are **permanent until something cancels them** — which is the
ticket's "which statuses are permanent by design" question answered from the ROM instead
of from taste. Eleven of the sixteen have a bit in this kernel; Wall (24 CT), Innocent
(32), Charm (32), Reflect (32) and Death Sentence (3) are the five
`StatusEncoder.UNMAPPED_NAMES` still skips
([#99](https://github.com/timbermania/fft-monorepo/issues/99)), and their slots are
reserved so adding them renumbers nothing.

**3. One CT is `TURN_METER_FULL / 100` kernel ticks, DERIVED and not chosen.** FFT
decrements a status counter once per clock tick — the same clock on which a unit accrues
Speed toward 100 and acts. This kernel's only statement of that clock is the turn meter
([ADR-0236](0236-the-turn-meter-is-a-gpu-unit-field-and-it-is-not-called-ct.md)):
`max(1, U_SPEED)` per tick, full at 3600. So a clock tick costs 36 ticks here, written as
the quotient rather than as the number, so rescaling the meter moves the durations with
it instead of leaving them to disagree silently.

⚠️ **Not the 30 that `GPUAbilityLoader` multiplies an ability's CT by.** Charge CT and
status CT are the same unit in FFT and are not the same thing in this kernel: charge is
speed-independent here at a flat 30 ticks per CT, while a status counter is
speed-independent in FFT too — so the faithful conversion for THIS quantity is the clock
tick. The two numbers being close is an accident of `TURN_METER_FULL = 3600`.

**4. The countdowns are addressed by STATUS, not by arrival — sixteen 16-bit counters in
the same eight ints.** `U_STATUS_TIMER_0..7` held a first-come pool of
`(bit << 24) | ticks` pairs, and a pool has a ninth case the ROM does not: a flag set with
no slot left, permanent and silent, in whichever battle happened to stack that many.
Slot `s` now lives in int `s >> 1`, low half for even `s` and high half for odd, indexed
by `status_timer_slot` using the ROM's own indices (`status - 24`). The longest ROM
duration is Sleep at 60 CT = 2,160 ticks, far inside 16 bits. **This deletes the ticket's
third question instead of answering it**: "what happens when the eight slots are full"
cannot be asked of a layout with one slot per timed status, and the answer the pool would
have needed — refuse the infliction, evict the shortest, or leave it permanent — would
have been three inventions competing to look least wrong.

**5. The producer is `apply_inflict_all`'s ALL branch: one flags write, then one armed
countdown per bit.** Every inflicted status in the kernel reaches a duration through
`arm_status_default_duration`, so "where does the number come from" has one site.
🔴 The flags write stays a **single OR of the whole mask**: `set_status` reads the CURRENT
buffer and writes the NEXT one, so setting bits one at a time would OR each onto the
frame-start word and keep only the last.

**6. `read_status_timer` / `write_status_timer` read the NEXT buffer, and two counters per
int is why.** A CURRENT-buffer read-modify-write composes with nothing: arming slot 1
would write back an int whose slot-0 half is the pre-tick value, silently undoing a
decrement or an arming from the same dispatch. Poison and Regen share
`U_STATUS_TIMER_0`, so the collision is certain rather than theoretical. `stage_compute`'s
TRANSPARENT consume already hand-rolls a NEXT-buffer AND-NOT for exactly this reason.

**7. `set_status_with_timer` is DELETED, not kept as a second entry point.** #1105's
finding was a writer with no callers; replacing it with another never-called helper would
have reproduced the finding. A caller wanting a duration the ROM did not give a status is
asking for a balance lever, and that does not belong in a shader helper.

**8. A cinematic pause freezes a countdown, and that is faithful.** `compute_unit_state`
early-returns on `U_PAUSED` before `tick_status_timers`, so a status outlives its
countdown by however long its carrier spent paused — measured at ~107 ticks on the witness
fixture, all of it one Slow cast's cinematic. FFT's clock stops for the animation too, so
this is left alone and the test's timing arms are one-sided because of it.

**9. The witness is `GPUStatusDecayTest`, un-skipped, with the arm the suite did not
have.** Three arms in one battle: a SEEDED countdown clears (the consumer, #1105's
original arm), an INFLICTED one clears at the duration the ROM gives it — the countdown is
read out of the buffer on the frame the bit appears and must be exactly 864 = 24 CT x 36 —
and a status the ROM never times stays set (the control, without which "the bit cleared"
is consistent with a tick loop that clears everything).

The test was in `tests/skip_tests.tsv` as red since
[#542](https://github.com/timbermania/fft-monorepo/issues/542) — *"HASTE timer clears 8
ticks off a ±3 tolerance"* — and **the rule was never wrong; the instrument was.** The bit
is sampled once per FRAME and a frame banks as much wall clock as it took, so under load
the observed clear lands arbitrarily late: a ±3 window on a per-frame poll measures the
box. Arm 1 is one-sided now (early is a defect, late is the sampler and the pause), and
the test is in the runner's array.

**10. Duration is not a named lever yet, and the blocker is named.** #1101's thesis makes
duration a primary lever on lethality and
[#1106](https://github.com/timbermania/fft-monorepo/issues/1106) will want one, but the
table lives in the shader, so a lever is a config or buffer field and a scale applied at
`arm_status_default_duration` — a separate change with its own authoring surface. What
this ADR fixes is that the baseline a lever would scale is now the ROM's and not a guess.

## Evidence

**Static: met, and mechanistically complete for the table.** Three cited sites fix the
base, stride, count, field meaning and the timed set; the extractor asserts the pairing
they imply over the real bytes, and the decoded values match FFT's documented durations.

**Dynamic: met for this kernel, NOT met for the ROM.** `GPUStatusDecayTest` watches an
inflicted status arm at 864 ticks and clear on its own in a real battle on the GPU. What
is *not* done is a PCSX run watching the ROM decrement Haste's 32 — so the claim "one CT
is one clock tick" rests on FFT canon plus the turn meter, not on a live oracle. The
decrementer's own caller (`BATTLE.BIN 0x80182CBC`) is identified and unwalked.

## Rejected alternatives

**A per-status constant table of our own numbers.** The ticket's first option, and the
obvious one before the ROM table was located. It would have invented sixteen numbers that
exist, and the invention would have been invisible: a balance table and an extracted
table read identically in code.

**A single global duration scalar in the lever layer.** The ticket's third option. It
cannot express Sleep 60 against Stop 20 against Death Sentence 3, so it would have
flattened a shape the ROM has — and the flattening, not the number, is what would have
been wrong.

**A per-ability duration field.** `effects.json` carries none, and the ROM's duration is
per-STATUS: the same Sleep lasts 60 CT however it was inflicted.

**Keeping the eight-slot pool and adding an overflow policy.** The pool was the wrong
SHAPE, not the wrong size. Any policy — refuse, evict-shortest, leave-permanent — is a
rule FFT does not have, adjudicating a case FFT cannot reach.

**Converting with the ability-CT 30.** It is the number already in the tree, which is
exactly why it is tempting; it is also a different claim about a different quantity.

**A new test scene for the inflicted witness.** The charter prices a test in PROCESSES
(~2.3 s of boot forever). The decay engine's own test is the home for the decay engine's
other half, and it shares the whole harness.

**Widening the unit block to sixteen int counters.** Sixteen 16-bit halves fit the eight
ints already reserved; growing the block costs every buffer, snapshot and schema citation
to buy range nothing uses.

**Fixing Poison's bleed interval here.** Named below and left alone: it is a different
rule with a different source.

## Soft spots

**S1 — Poison is still lethal, and the duration is not what was wrong.** 36 CT is 1,296
ticks, and at `POISON_TICK_INTERVAL = 30` that is 43 bleed ticks of `max_hp / 8`. FFT
bleeds a poisoned unit on its own TURN (~3 times in 36 CT at Speed 8), so the defect is
the INTERVAL. #1105's finding 1 carries the measurement and this ADR does not fix it.

**S2 — two CT conversions now live in the kernel**, 30 for charge and 36 for status
counters. Both are defensible and they are not the same quantity, but a reader who finds
one will expect the other.

**S3 — the armed value is asserted for ONE status.** Slow's 24 CT is witnessed on the
GPU; the other ten rows are held only by the parity test against the shader, which cannot
tell a wrong number from a right one — only a disagreeing one.

**S4 — the pause freeze is unbounded.** A battle thick with cinematics stretches every
duration in wall-tick terms, and nothing measures how much.

**S5 — five timed statuses have no bit (#99).** Their slots are reserved, so the layout is
final, but until they land the kernel times eleven of sixteen.

**S6 — Death Sentence's no-re-arm carve-out is not ported.** `Status_CT_Set` refuses to
refresh it; this kernel refreshes every countdown, and has no Death Sentence bit to be
wrong about yet.

**S7 — a cross-unit arming race exists inside `stage_compute`.** An attacker's thread can
write a target's countdown before the target's own `copy_unit_to_next` runs. The flags
write has always had the same race at the same call site; this change neither adds nor
fixes it.

**S8 — byte +0x0F of the ROM record is an order column this decode does not explain**: 39
of 40 entries are distinct values in 0..39 and the 40th reads 0xF7. Nothing here reads it.
