# Status conformance: all 32 bits

What each `STATUS_*` bit in `U_STATUS_FLAGS_LO` actually does in the kernel, who
can set it, and whether it ever goes away. Measured against the tree on
2026-09-10 for [#1105](https://github.com/timbermania/fft-monorepo/issues/1105);
every claim below is cited to a file and a line, not reasoned from a name.

> A reference count is a floor, not a verdict. The charting pass for
> [#1101](https://github.com/timbermania/fft-monorepo/issues/1101) counted
> references and concluded "13 of 32 are declared and never read." That count is
> confirmed — but it was the *smaller* half of the answer. Three structural
> findings below cut across the table and matter more than any single row.

## Vocabulary

The ticket asked for "hollow" vs "unimplemented" to be fixed in words first,
because the table is unreadable without them. A bit has **two** independent ways
to be absent, and they need different fixes:

**Unread** — no kernel site consults the bit. The rule was never written.
Fixing it means writing a rule.

**Unreachable** — nothing in the shipped data can set the bit, so no battle can
ever produce it. The rule may be fully written and still never run. Fixing it
means authoring data (or a new inflict path), not code.

**Hollow** — unread *or* unreachable. The bit cannot participate in a battle.
This is the word for the *outcome*; "unread" and "unreachable" are the two
*causes*, and a bit can be hollow from either end.

**Unimplemented** is deliberately not used as a verdict: it conflates the two.
`STATUS_TRANSPARENT` has fifteen kernel sites and is unreachable; `STATUS_DEAD`
has none and is reachable from fourteen ability records. Calling both
"unimplemented" hides which end is broken.

A fourth verdict, **delete**, is for bits whose *name* is the defect — see
finding 3.

---

## Finding 1 — nothing decays. The 8-slot timer pool has no producer.

> **RESOLVED by [#1116](https://github.com/timbermania/fft-monorepo/issues/1116).**
> The measurement below stands as written — it was true of the tree on
> 2026-09-10 — and everything it predicted about the 8-slot pool was confirmed
> twice over. `apply_inflict_all` now arms a countdown for every bit it sets, and
> the duration is the ROM's own: the status-attribute table in SCUS at
> `0x80065DE7 + 0x10*status`, byte 0, in CT units
> (`tools/extract_status_attributes.py`). **Sixteen of FFT's forty statuses have
> one and twenty-four do not**, because the ROM's per-unit countdown array is
> sixteen bytes at `unit+0x5D` indexed by `status - 24` (`Status_CT_Set`, SCUS
> `0x8005DB70`) — so "permanent until cured" is a ROM answer for Darkness,
> Silence, Oil, Frog, Confusion, Berserk, Petrify, Blood Suck, Float, Reraise and
> Transparent, not a gap in this port. Eleven of the sixteen have a bit here; the
> other five are #99's.
>
> The pool's 8-slot question the paragraphs below raise **was the wrong shape
> rather than the wrong size**: the slots are now sixteen 16-bit counters in the
> same eight ints, addressed by the status, so "what happens when it is full"
> cannot be asked. See ADR-0298.
>
> ⚠️ **The balance consequence below is NOT fixed by a duration.** Poison's 36 CT
> is 1,296 ticks here, and at `POISON_TICK_INTERVAL = 30` that is 43 bleed ticks
> of `max_hp / 8` — still several health bars. FFT bleeds a poisoned unit on its
> own TURN (~3 times in 36 CT at Speed 8), so the defect is the INTERVAL, not the
> duration, and it is now the only thing standing between this status and
> FFT-faithful lethality.

The kernel has a complete status-decay engine:
`set_status_with_timer` / `tick_status_timers` / `clear_status_timer`, an 8-slot
packed `(status_bit, ticks)` pool at `U_STATUS_TIMER_0..7`, and a per-unit tick
call at `stage_compute.glsl:1155`. It is documented as landed —
`docs/status_system.md:155` says *"A duration-decay engine. That landed
2026-05-31."*

**`set_status_with_timer` has zero call sites.** It is the only function that
writes a non-zero timer slot (`combat_common.glslinc:1627`, `:1633`); every other
write to a timer slot in the tree writes `0` (a clear). Nothing in the shipped
kernel calls it.

The infliction path does not go near it. `apply_inflict_all`
(`combat_common.glslinc:1480`) ORs the mask straight onto `U_STATUS_FLAGS_LO`
with no duration argument and no timer registration. So:

> **Every status inflicted during a battle is permanent for the rest of that
> battle.** Poison, Sleep, Stop, Silence, Slow, Haste, Petrify, Frog — none of
> them wear off.

The only way to reach a live timer is to **seed one at pack time**:
`GPUCombatPacker.gd:829-843` accepts a `status_timers` array from the unit
config. `_extract_unit_config` — the live-unit path — does not emit that key, so
only test and scenario configs can supply it. `tests/GPUStatusDecayTest.gd:49`
does exactly that (`"status_timers": [{"bit": …haste, "ticks": 30}]`), which is
why decay has a green test and no production reachability. The test proves the
consumer works; it cannot see that the producer is missing.

Two kernel comments assert the opposite and are false as written:

- `stage_compute.glsl:1362` — *"The status timer (Tier 2 #6) will decay these on
  its own cadence"*, on the Sleep / Stop / Petrify / Disable decision gate.
- `stage_damage.glsl:182` — *"Status duration is owned by tick_status_timers in
  stage_compute — when a timer slot expires, the flag clears and no further ticks
  fire"*, on the Poison / Regen tick.

**The balance consequence is large and immediate.** `POISON_TICK_INTERVAL = 30`
and `POISON_HP_DIVISOR = 8` (`combat_common.glslinc:509-510`): a poisoned unit
loses `max_hp / 8` every 30 ticks, forever. Eight ticks — **240 ticks** — is a
full health bar. The measured Gariland battle runs ~1,779 ticks
(#1101 charting), so **a single Poison landing is a guaranteed kill within 13% of
a battle's length**, and Regen is the same engine with the sign flipped: a
permanent, un-cancellable full-heal generator.

**Validated on a live battle, not only in the decompile.**
`tests/GPUStatusInflictTest.tscn` inflicts Poison with a spell and then reports
its own observation:

```
SpellTarget  status_flags_lo = 0x00008000 (poison bit SET)
SpellTarget  HP 0/200 (took 200 damage, expected 25 per poison tick)
```

`200 / 25 = 8` ticks — the unit took the full bar and died, and the poison bit is
**still set** at the end. The test scores `[PASS]`, because dying of poison is
what it was written to watch. Nothing in the suite watches for the bit going
away.

The ticket predicted that "which statuses can be simultaneously timed is capped
at 8" would be a balance constraint hiding in the buffer layout. It is not a
constraint yet — **the live cap is 0, not 8**, and it binds in the other
direction: nothing expires. The 8-slot cap becomes real the moment a producer is
added, and should be re-examined then.

## Finding 2 — two of the four inflict modes are silent no-ops.

> ✅ **RESOLVED 2026-09-11 by [#1117](https://github.com/timbermania/fft-monorepo/issues/1117)
> (ADR-0299).** `resolve_inflict_mask` now narrows the listed set per mode and
> `apply_inflict_all` writes the result: `random` lands exactly one bit picked
> uniformly, `separate` rolls each listed bit independently at the ROM's flat 24%
> (`pass_fail_roll(100, 0x18)` at BATTLE.BIN `0x801880E8`). The measurement below is
> left as it was taken — it is what the tree read on 2026-09-10 — and the "reaches a
> target" column is the half that has changed. What did NOT change is the third
> no-op class at the end of this section: three of the 27 (Blaster f61, CrushPunch
> f45, BloodSuck f71) still reach no inflict site at all, and SplitPunch still
> encodes to an empty mask because Death Sentence has no bit (#1119).

`apply_inflict_all` implements `INFLICT_MODE_ALL` and `INFLICT_MODE_CANCEL` and
falls off the end for anything else (`combat_common.glslinc:1482-1494`).
`StatusEncoder` emits four modes. Counting `effects.json` records that carry a
non-empty `inflict_statuses` list:

| mode | records | reaches a target |
|---|---:|---|
| `all` | 114 | yes |
| `cancel` | 14 | yes |
| `random` | 11 | **no — silent no-op** |
| `separate` | 16 | **no — silent no-op** |

**27 of 155 status-bearing abilities inflict nothing**, with no warning at encode
time and no branch at apply time. `StatusEncoder.mode_from_string` translates
`"random"` / `"separate"` faithfully into `MODE_RANDOM` / `MODE_SEPARATE`, packs
them into `AB_INFLICT_MODE`, and the shader ignores them. The encoder's own
docstring flags this (*"RANDOM / SEPARATE land in #102"*) but nothing fails, logs,
or counts.

Casualties include `MimicDaravon` (Sleep), `GalaxyStop` (Stop + Immobilize +
Disable), several `NamelessDance` rows and every `separate`-mode monster ability.

### The five paths a status can travel

For completeness — `apply_inflict_all` is reached by five kinds of gate, across nine
call sites (the two spell stages mirror each other):

| site | gate |
|---|---|
| `combat_combat.glslinc`, formula-10/11 branch | Faith-scaled roll, `hit_chance = clamp(min(MA+X,100) · caster_faith · target_faith / 10000, 0, 100)` |
| `combat_combat.glslinc`, formula-42/56/80 branch | unconditional, no roll |
| `stage_damage.glsl`, AOE loop | AOE bleed, per in-radius target |
| `stage_compute.glsl` / `stage_spell.glsl`, `apply_heal_to_target` + `apply_damage_to_target` | item / instant-ability path (Antidote, Eye Drop, Phoenix Down) |
| `stage_compute.glsl`, `apply_attack_damage` | equipped-weapon on-hit (`U_WEAPON_INFLICT_MASK`) |

Since #1117 every one of them passes the caster and the tick as well as the target,
because `random` and `separate` roll and a roll needs a seed. No vanilla weapon or
chemist item uses either mode, so that last row's behaviour is unchanged.

An ability that carries an inflict list but resolves through none of these
formulas and has no AOE is a third silent no-op class, distinct from finding 2.

## Finding 3 — two bits hold names FFT does not have, while five real statuses have no bit.

The shipped data (`assets/abilities/effects.json` + `items.json`) spells exactly
**30 distinct FFT status names**. Twenty-five of them map to a registry bit. Five
do not: `Charm` (5 refs), `Reflect` (7), `DeathSentence` (9), `Innocent` (4),
`Crystal` (1) — **26 dropped name-instances**, warned once each by
`StatusEncoder._warn_unmapped` and queued behind issue #99.

Meanwhile two registry bits carry names that **never appear in the data and are
not FFT status names at all**:

- **bit 11 `blind`** — FFT's blindness is **Darkness**, which is bit 29 and is the
  single most-inflicted status in the whole database (26 references). `blind` is a
  second, invented spelling of a status that already has a bit.
- **bit 27 `curse`** — not an FFT status. Nothing references it anywhere in the
  tree except its own two declaration lines.

Both are unread *and* unreachable, and neither has a rule anyone is waiting on.
They are junk slots. Deleting them is free and shrinks the vocabulary to FFT's
own — which is the point of `StatusRegistry` existing.

(Capacity is not the argument. `U_STATUS_FLAGS_HI` exists and is entirely unused,
and `set_status` / `clear_status` / `has_status` already route bits ≥ 32 to it,
so the five missing statuses have somewhere to go regardless. The argument is
that a registry claiming to be "the single source of truth for FFT status
effects" should not contain two statuses FFT does not have.)

## Finding 4 — one bit is fully implemented and completely unreachable.

`STATUS_TRANSPARENT` (23) has **fifteen** kernel sites — enemy target searches
skip transparent units in four separate finders, and an AOE hit consumes the bit
(`stage_damage.glsl:37-52`). It is the second-most-implemented status in the
kernel.

**No shipped record can set it.** All four data references to `Transparent`
(`DispelMagic`, `Despair`, `Despair2`, `OddSoundwave`) are the same nine-status
dispel list in `cancel` mode. Nothing grants Transparent; four things remove it.
The only way a unit becomes transparent today is a pre-battle `status_flags_lo`
seed, which is what `tests/GPUTransparentTest.gd` does.

This is the same shape as the defect
[#1102](https://github.com/timbermania/fft-monorepo/issues/1102) found for
`COND_IS_DEAD`: a correct, complete implementation that no battle can reach.
Whether the gap is a missing ability record or a deliberate omission is a data
question, not a kernel one.

---

## The table

**Decay column**: uniform by finding 1. `permanent` means "once set, stays set
for the battle"; `seed-only` means a timer can exist but only if the unit config
supplied one. No row can say "decays on its own."

**Inflict counts** are records in `effects.json` / weapon blocks in `items.json`
whose `inflict_statuses` names the bit, via `StatusEncoder`'s translation
(CamelCase round-trip plus `DontMove`→`immobilize`, `DontAct`→`disable`).

| bit | name | what the kernel does with it | who can inflict | decay | verdict |
|---:|---|---|---|---|---|
| 0 | `dead` | **nothing** — no site reads it. Death is `FLAG_DEAD` in `U_FLAGS`, read by `is_unit_dead` (`combat_common.glslinc:926`) | 14 abilities (`Raise`, `Raise2`, `Revive` cancel; `Death`, `LavaBall`, `CrushPunch` all) — all currently inert | permanent | **delete** — see below |
| 1 | `undead` | Inverts healing into damage at 4 sites: `stage_spell.glsl:568`, `:779`, `stage_compute.glsl:822`, and the Phase-3 pending-damage invert `stage_damage.glsl:299`, `:386`. Also suppresses TRANSPARENT AOE-reveal (`stage_damage.glsl:39`) | 4 (`Zombie`, `Bio3`, `ZombieTouch`) | permanent (FFT-correct) | implemented |
| 2 | `charging` | Set on cast start (`stage_spell.glsl:472`, `stage_pathfind.glsl:913`), cleared on cast complete (`stage_spell.glsl:714`). **Never read by name** — every consumer gates on `U_STATE == LOGICAL_ACTIVITY_SPELL_CHARGING` (7 sites) instead | kernel only; no data path | cleared by the cast | **hollow — unread.** A published state with no consumer; the state machine is authoritative. Either give it a reader or stop maintaining it |
| 3 | `jump` | nothing | nothing | n/a | hollow — deliberately out of scope. There is no Jump action in the action enum |
| 4 | `defending` | nothing | nothing | n/a | hollow — deliberately out of scope. There is no Defend action |
| 5 | `performing` | nothing | nothing | n/a | hollow — deliberately out of scope. The performer-side state of Dance/Song; the *abilities* exist and inflict, the performer state does not |
| 6 | `petrify` | Blocks gambit evaluation entirely — unit skips its decision and re-checks in `TICKS_GAMBIT_REEVAL`=10 (`stage_compute.glsl:1369`) | 19 abilities + 2 weapons (Chaos Blade, Flame Whip) | permanent | implemented — ⚠️ permanent Petrify is a permanent removal from the battle |
| 7 | `stop` | Same decision gate (`stage_compute.glsl:1368`) | 12 abilities + 1 weapon | permanent | implemented — ⚠️ same |
| 8 | `sleep` | Same decision gate (`stage_compute.glsl:1367`) | 19 abilities + 3 weapons | permanent | implemented — ⚠️ same. FFT wakes a sleeper on damage; this does not |
| 9 | `immobilize` | Vetoes `ACTION_MOVE_TO` / `ACTION_MOVE_TO_UNIT` so the gambit list falls through to the next slot (`stage_compute.glsl:567`) | 12 abilities + 2 weapons | permanent | implemented |
| 10 | `disable` | Decision gate (`stage_compute.glsl:1370`) | 12 abilities + 2 weapons | permanent | implemented |
| 11 | `blind` | nothing | nothing — **not an FFT status name** | n/a | **delete** — finding 3. Darkness (29) is FFT's blindness |
| 12 | `berserk` | Overrides the gambit list: forces `ACTION_ATTACK` on `find_nearest_enemy`, clears `U_CURRENT_GAMBIT` (`stage_compute.glsl:1381-1394`) | 8 abilities | permanent | implemented |
| 13 | `chicken` | nothing | nothing (FFT derives it from Brave < 10, not from an inflict) | n/a | hollow — out of scope. **`U_BRAVE` is declared and never read anywhere in the kernel**, so there is no substrate for it |
| 14 | `frog` | nothing | 15 abilities + 3 weapons (`Nagrarock`, `Flame Rod`, `Octagon Rod`) | permanent if set | **hollow — should be built.** Genuinely inflictable, genuinely unread |
| 15 | `poison` | Queues `max_hp / 8` into `U_PENDING_DAMAGE` every 30 ticks (`stage_damage.glsl:187`) | 16 abilities + 3 weapons | permanent | implemented — ⚠️ **lethal by construction**, see finding 1 |
| 16 | `regen` | Same tick, negative sign (`stage_damage.glsl:188`) | 8 abilities | permanent | implemented — ⚠️ permanent heal generator |
| 17 | `protect` | Halves physical damage (`stage_compute.glsl:319`) and counter damage (`stage_damage.glsl:244`) | 12 abilities | permanent | implemented |
| 18 | `shell` | Halves magic damage for formulas 8/12/32/36/78 (`combat_combat.glslinc:499`) | 17 abilities | permanent | implemented |
| 19 | `haste` | Halves `move_ticks` / cast timing at 3 sites: `stage_attack.glsl:483`, `stage_pathfind.glsl:589`, `stage_spell.glsl:396` | 9 abilities | permanent | implemented |
| 20 | `slow` | Doubles the same three (`:485`, `:591`, `:398`) | 10 abilities + 2 weapons | permanent | implemented |
| 21 | `float` | Cancels ELEMENT_EARTH damage outright, before the equipment matrix (`combat_common.glslinc:1534`) | 5 (1 grant `Float`, 4 cancel) | permanent | implemented |
| 22 | `reraise` | Full capture-and-revive. Stage A intercepts lethal damage, sets `FLAG_DEAD` + HP 0 + stamps `U_TIMER` (`stage_damage.glsl:69`); Stage B revives after `RERAISE_REVIVE_DELAY_TICKS` and clears the bit (`stage_spell.glsl:1023-1032`); victory counts a carrier as alive (`stage_victory.glsl:30`). **The only site in the tree that clears `FLAG_DEAD`** | 7 (2 grant, 4 cancel, 1 random) | consumed by the revive | implemented — the most complete status in the kernel |
| 23 | `transparent` | Hidden from every enemy-side target search (`stage_compute.glsl:166`, `:233`, `stage_attack.glsl:437`, `stage_pathfind.glsl:48`, `:543`, `stage_post_conflict.glsl:51`); consumed by AOE damage (`stage_damage.glsl:37`) | **nothing grants it** — all 4 data refs are `cancel` | seed-only | **hollow — unreachable.** Finding 4 |
| 24 | `confusion` | nothing | 19 abilities + 1 weapon (`Ramia Harp`) | permanent if set | **hollow — should be built.** The BERSERK override at `stage_compute.glsl:1381` is the working template for a behaviour-hijack status |
| 25 | `silence` | Vetoes `ACTION_SPELL` / `ACTION_ABILITY`; items still pass (`stage_compute.glsl:563`) | 20 abilities + 2 weapons | permanent | implemented |
| 26 | `blood_suck` | nothing | 3 abilities | permanent if set | hollow — should be built, low value. Needs a per-tick drain-to-caster, i.e. the Poison engine with a beneficiary |
| 27 | `curse` | nothing | nothing — **not an FFT status name** | n/a | **delete** — finding 3 |
| 28 | `invite` | nothing | 2 (`Invitation`, `DragonTame`) | permanent if set | hollow — deliberately deferred. Flipping `U_TEAM` mid-battle has victory-condition consequences (`stage_victory.glsl`) that make it its own piece of work, not a status rule |
| 29 | `darkness` | nothing | **20 abilities + 4 weapons — the most-inflicted status in the database** (`Blind Knife`, `Night Killer`, `Lightning Bow`, `Octagon Rod`) | permanent if set | **hollow — should be built, blocked.** Darkness is an accuracy debuff and **there is no attacker-side accuracy term to debuff**: `roll_evasion` (`stage_compute.glsl:291-306`) is purely defender-side (`c_ev + s_ev + w_ev`, capped 99). Needs a hit-chance model first |
| 30 | `oil` | Doubles ELEMENT_FIRE damage before the equipment matrix (`combat_common.glslinc:1537`) | 6 abilities + 1 weapon | permanent | implemented |
| 31 | `faith` | nothing. ⚠️ The **stat** `U_FAITH` is live — it scales magic damage (`combat_combat.glslinc:443`) and the status-infliction hit roll (`:339`). The **status bit** is unread | 6 (2 grant `PrayFaith`/`Faith`, 4 cancel) | permanent if set | **hollow — should be built.** A one-line multiplier on `U_FAITH` at two existing read sites |

### Tally

| verdict | count | bits |
|---|---:|---|
| implemented | 17 | 1, 6, 7, 8, 9, 10, 12, 15, 16, 17, 18, 19, 20, 21, 22, 25, 30 |
| hollow — should be built | 5 | 14 `frog`, 24 `confusion`, 26 `blood_suck`, 29 `darkness`, 31 `faith` |
| hollow — unreachable (implemented) | 1 | 23 `transparent` |
| hollow — unread (kernel-maintained) | 1 | 2 `charging` |
| hollow — deliberately out of scope | 5 | 3 `jump`, 4 `defending`, 5 `performing`, 13 `chicken`, 28 `invite` |
| delete | 3 | 0 `dead`, 11 `blind`, 27 `curse` |

*(17 + 5 + 1 + 1 + 5 + 3 = 32. Eighteen bits carry a live kernel rule;
`transparent` is one of them but no battle can reach it, so it is counted as
hollow rather than implemented.)*

---

## Bit 0: delete it

The ticket named the choice: **delete** or **make authoritative**. Not "leave it."

**Make it authoritative** — move death from `FLAG_DEAD` into status bit 0, so the
fourteen ability records that inflict the FFT name `Dead` start working — is the
wrong call, and it is worse than doing nothing:

- `apply_inflict_all` ORs a raw bit. An ability with `Dead` in `mode: all`
  (`Death`, `LavaBall`, `CrushPunch`) would become an **instant unconditional
  kill that bypasses `kill_unit` entirely** — no victory bookkeeping, no death
  animation chain, and critically no `try_consume_reraise`. Death would kill
  through Reraise.
- `mode: cancel` (`Raise`, `Raise2`, `Revive`) would clear the KO flag with **no
  HP refill**, producing a living 0-HP unit that the next damage tick re-kills.

Both failures are silent, data-driven, and land the instant the bit goes live.
The status word is an OR-able bag of bits; death has a careful lifecycle. They
are not the same kind of thing, and bit 0 is the seam where that gets forgotten.

**So: delete.** `FLAG_DEAD` is authoritative, `is_unit_dead` is the predicate,
and [#1102](https://github.com/timbermania/fft-monorepo/issues/1102) gave the
gambit layer the live spelling — `GambitCondition.is_ko()` → `COND_IS_DEAD`. Bit
0 has a working rival for every job it could have had.

Deleting it closes the trap `StatusRegistry.gd:60` already half-anticipated:
today `StatusRegistry.bit(&"dead")` returns `0` cleanly, so a revive gambit
authored the obvious way — `HAS_STATUS(&"dead")` — encodes, passes every guard,
and never fires. With the name gone, that same authoring mistake hits the
existing `push_error` and fails loud, which is what line 60 says it wants.

### What executing it requires

Three edits, and one cross-branch hazard:

1. `combat_common.glslinc` — drop `const int STATUS_DEAD = 0;`, leaving bit 0
   reserved with a comment saying why.
2. `StatusRegistry.NAMES_TO_BITS` — drop `&"dead": 0`.
   `tests/StatusRegistryTest.gd::_test_shader_parity` parses the shader and
   asserts a symmetric, count-checked match, so both sides must move together.
3. `StatusEncoder` — the FFT name `Dead` must become an **explicitly reasoned**
   unmapped name ("this is `FLAG_DEAD`'s job, not a status bit"), not an
   unrecognised one, so the fourteen `Raise` / `Death` records skip with an
   accurate message instead of a generic issue-#99 warning.

⚠️ **Merge-order hazard.** `tests/GambitEncoderTest.gd` on the unmerged branch
`feat/1102-ko-alive-distance-conditions`
([PR #1114](https://github.com/timbermania/fft-monorepo/pull/1114)) asserts the
trap in its current form: *`has_status(&"dead")` still encodes (bit 0 is a
registered name)* and *encodes to `COND_HAS_STATUS` on bit 0*. Deleting the name
turns those two assertions red. #1114 must land first; the deletion then rebases
on top and rewrites that test to assert the *closed* trap — `&"dead"` no longer
encodes at all. This is precisely the "resolved is not landed" hazard #1101's
Notes warn about, and it is why the deletion is a separate, gated ticket rather
than part of this audit.

---

## What this does not answer

What to *balance* about the survivors is fog on #1101, not this ticket. But the
audit sharpens it: the permanence in finding 1 is a balance defect, not a tuning
knob, and it has to be settled before any status number means anything.
