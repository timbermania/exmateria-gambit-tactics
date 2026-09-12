# The ENTD level byte is not a level, and resolving it is only half the fix

## Status

Accepted

Built by [#1179](https://github.com/timbermania/fft-monorepo/issues/1179), on
build map [#1101](https://github.com/timbermania/fft-monorepo/issues/1101).

## Context

[#1110](https://github.com/timbermania/fft-monorepo/issues/1110) re-seats the
corpus rig on **real ENTD rosters**, so what an ENTD slot's `level` byte *means*
stops being trivia and becomes the axis every lethality lever is dialed against.

Counted over the **847 slots `EntdBattle.combatant_slots` actually deploys**:

| `level` byte | deployed slots |
|---|---:|
| `0xFE` | **506** |
| an explicit 1–99 | 336 |
| ≥ 100 (101, 105, 105, 110, 115) | 5 |

The port resolved `0xFE` to **1** — `_entd_value(int(slot.get("level", 1)), 1)`
— so the majority of the deployed cast fought at the bottom of the curve.

### What the ROM actually does — SCUS_942.21, not BATTLE.BIN

The ENTD record is consumed *before* the battle loop, which is why #1121 could
not find the resolver in BATTLE.BIN: `entd_to_roster_loader_16`
(BATTLE `0x8017f8a0`) walks the record's sixteen 40-byte slots and hands each to
**SCUS** `0x8005a9b4`, which builds the unit. Two SCUS routines own the level.

**`0x8005cbd0` computes the ceiling** — called first, at BATTLE `0x8017f8f4`:

```
8005cbd0  s1 = 0                            ; running max
8005cbf0  v1 = roster_entry(s0)             ; 0x80057F74 + s0*0x100, 20 entries
8005cbfc  if (v1[+0x01] == 0xFF) skip       ; empty roster slot
8005cc0c  if (s1 < v1[+0x16]) s1 = v1[+0x16]   ; +0x16 is the roster LEVEL
8005cc2c  if (s1 >= 100) s1 = 99
8005cc40  DAT_80066308 = s1
```

So the ceiling is **the highest level anywhere in the player's 20-slot roster**
— the whole barracks, not the deployed party — clamped to 99, recomputed at
every battle load.

**`0x8005add4` resolves the byte** against that ceiling `P`:

```
8005add4  s0 = entd[+0x03]                  ; the level byte
8005ade0  if (s0 == 0) -> randomise
8005ade8  if (s0 == 0xFE) -> randomise
8005adec  if (s0 < 100) -> verbatim
          ; party-RELATIVE branch
8005ae40  v0 = P + 156                      ; +156 == -100 in the byte
8005ae44  s0 = s0 + v0                      ; = P + (byte - 100)
          ; randomise branch
8005adfc  v0 = P >> 3                       ; floor(P/8)
8005ae00  s0 = v0 + 1                       ; the window's WIDTH
8005ae04  jal 0x8002230c                    ; BIOS A(2Fh) rand(), 0..32767
8005ae08  s1 = P - v0                       ; the window's FLOOR
8005ae20  v0 = (width * rand) >> 15
8005ae28  s0 = s1 + v0                      ; uniform over [P - P/8, P]
          ; the clamp both branches land on
8005ae50  if (result == 0) result = 1
8005ae64  if (result >= 100) result = 99
8005ae74  unit[+0x22] = result              ; the unit struct's LEVEL byte
```

**The byte is a three-branch field, not a number.** `0` and `0xFE` are the same
sentinel; 1–99 is authored; ≥ 100 is *party-relative*.

### The second half: the level then GROWS the stats

`0x8005b880` walks the raw stats up to that level, over the same ×16384 fixed
point the port uses (`srl a0,v0,14`):

```
8005b8b0  t7 = unit[+0x22]                  ; level
8005b8dc  if (unit[+0x02] != 0xFE) skip     ; the "generated, not save-loaded" gate
8005b910  for (a2 = 2; a2 <= level; a2++)
8005b918     a0 += a0 / (C + a2 - 1)
```

That is **exactly `UnitProgression.level_up()` repeated** — `grow_stat` is
`raw + raw/(C + level)` applied with the pre-increment level, so the ROM's
divisor sequence `C+1, C+2, … C+level-1` is the port's, term for term.

### Dynamically closed, offline

A PCSX-Redux savestate is main RAM, so this needed no emulator launch. Over the
94 savestates in `reference-assets/`: the roster max computed from
`0x80057F74` **equals the stored `DAT_80066308` in every state that holds a
battle**, and joining live units back to their ENTD record yields **31 distinct
sentinel observations**, of which **28 land inside `[P - P/8, P]`**:

| savestate | record | P | window | observed levels |
|---|---:|---:|---|---|
| `before_bridge` | 259 | 99 | [87, 99] | 87, 90, 91, 92, 94, 96 |
| `scenario_14_start_maybe` | 260 | 99 | [87, 99] | 89, 90, 90, 93, 97 |
| `battle_results_ss0_*` | 384 | 99 | [87, 99] | 90, 90, 92, 93, 95, 97 |
| `orbonne_*` (P is 1) | 256 | 1 | [1, 1] | 1 × 10 |

The spread across the window is the random draw showing itself. The **three
outliers are all `unit_id` 4 and 7 at level 1–2 while `P` is 99** — Ramza and
Agrias, who are in the player's save: the ROM loads a named unit from the roster
instead of generating it, which is what the `unit[+0x02] != 0xFE` gate above
says. All 336 explicit 1–99 bytes reproduce verbatim.

🔴 **This corrects ADR-0284's join key.** That ADR read `unit+0x02` as "an
enemy's ENTD slot index". It is not: it is the **player-roster index** for a
save-loaded unit and `0xFF` for a generated one, and the ENTD `unit_id` lives at
**`unit+0x161`** (which `fft-ghidra`'s own label for `entd_to_roster_loader_16`
already documented). ADR-0284's *conclusions* survive and are now better
supported — re-censused on the corrected key, **64 distinct ENTD-generated units
across every savestate show zero cross-column violations, every explicit item id
passing through verbatim, and `0xFE` resolving to a spread of real items** (head
→ 144/153/154/157/168, right hand → 1/19/30/59/64/67/68/77). One row of its table
does not: the accessory it reported as *Battle Boots* came from a player unit;
on generated units `0xFE` in the accessory slot resolved to **empty in 10 of 20
observations**.

### And the port's level was decorative anyway

`create_default` seeds the raw stats at the level-1 base and **only
`level_up()` grows them**. `from_entd_slot` wrote `progression.level` and stopped.
Nothing reads that field except display, the save schema and the formation panel
— it never reaches `U_MAX_HP` / `U_PA` / `U_MA`. So **all 847 deployed slots
fought at base stats**, not just the 506 sentinel ones: an authored level-9
Knight hit exactly as hard as a level-1 one.

## Decision

1. **The `level` byte is a three-branch field and
   `Character.resolve_entd_level(raw, ceiling)` implements all three**, plus the
   ROM's `0 -> 1` / `>= 100 -> 99` clamp. `0` is the SAME sentinel as `0xFE`;
   reading it as a literal level was a second, quieter version of the same bug.

2. **The sentinel resolves to the MIDPOINT of the ROM's window, not to a draw.**
   The ROM picks uniformly from the `P/8 + 1` levels in `[P - P/8, P]`; the port
   takes that window's middle. This is ADR-0284 dec. 3's argument applied to the
   same sentinel on the same slot: *a rig whose rosters change run to run cannot
   referee a lever*, and a deterministic sample of the ROM's own draw is the
   substitute that keeps two corpus runs comparable.

3. **The ceiling is the RECORD's, and only then the corpus parameter's.**
   `Character.level_ceiling_for_slots(slots)` takes the highest authored 1–99
   level among the record's deployed slots, because those track the chapter the
   fight belongs to (Gariland ceilings at 4, Riovanes at 75). Only **75 of the
   174 records with deployed slots author one**, so the rest fall back to
   `Character.entd_level_ceiling`, a `static var` defaulting to **23 — the ROM's
   own median** across the 336 authored deployed levels (mean 22.2).

4. **Resolving the level is HALF the fix; `from_entd_slot` now GROWS to it.**
   `_grow_progression_to` iterates `level_up()` from the level-1 base, which is
   byte-for-byte the ROM's growth walk at `0x8005b880`. Without this the decision
   above would move nothing a shader can see.

5. **The ceiling a corpus ran under is part of the corpus.** ADR-0284 dec. 5
   already obliges a rig to record which policy armed each unit; the ceiling is
   the same kind of fact about how each unit was *levelled*, and two runs under
   different ceilings are not comparable. #1110 records it.

6. **A caller holding a whole cast passes the record ceiling.** `ScenarioCast`,
   `NavigatorMain` (through `SlugBinding.resolve_character`) and
   `CombatUITestScene` derive it once per record; `-1` means "use the corpus
   parameter", which is what the two catalogue-internal callers take.

## Consequences

Measured over all 847 deployed slots, in three arms, so the two halves of the
defect can be told apart:

| | level mean | level median | slots at level 1 | Σ effective HP | Σ effective PA |
|---|---:|---:|---:|---:|---:|
| before (`0xFE` → 1, no growth) | 10.04 | 1 | 560 | 30,857 | 4,258 |
| growth applied to the OLD levels | 10.04 | 1 | 560 | 56,482 (×1.83) | 5,045 (×1.18) |
| after (resolved + grown) | 23.47 | 22 | 54 | **109,523 (×3.55)** | **6,375 (×1.50)** |

- **The deployed cast's total effective HP more than triples**, and roughly half
  of that move is the missing growth rather than the sentinel — so a measurement
  taken before this is not comparable to one taken after, and **both #1110 and
  #1111 must run post-fix**, as they already must post-#1121.
- **506 slots stop fighting at level 1**; 54 still do, and those are authored
  level-1 slots (Orbonne's Ramza among them), not sentinels.
- Every unit now reaches the kernel with the stats its level implies, including
  the 336 slots whose level was never a sentinel at all.
- **A slot dict with no `level` key now takes the sentinel, not 1.** Real ENTD
  data always carries the byte, so this only reaches hand-built dicts; the
  sentinel is the honest reading of an absent field, since "unknown" is exactly
  what the ROM spells `0xFE`.

## Rejected

- **Port the ROM's random draw.** Reproducibility, same as ADR-0284 dec. 3. The
  variance is real — the observed draws spread 87…97 on a P=99 battle — and a rig
  that re-rolls its cast cannot attribute a change to a lever.
- **Derive the ceiling from the opposing side's mean resolved level.** Circular:
  **99 of the 174 records with deployed slots author no level at all**, so on the
  majority case both sides are sentinels and there is nothing to average.
- **Keep `0xFE -> 1`.** It is not a conservative default; it is the one value the
  ROM can only produce when the player's roster is itself empty.
- **Resolve the level and leave the stats at base.** That is the state this ADR
  found, and it makes the whole field decorative.
- **Thread a battle seed down to `from_entd_slot` and draw faithfully.**
  Defensible, and rejected for cost, not principle: the seed is owned three
  layers up (`start_entd_battle(entd_record, map, seed)`), and a seeded draw is
  only comparable across runs that share the seed — which is the determinism of
  dec. 2 with more plumbing.

## Soft spots

- **S1. The corpus ceiling is a parameter, not a measurement.** 23 is the ROM's
  median authored level, which is a defensible *number* and not a *derivation*:
  there is no roster in the rig for the ROM's rule to read. It is the single
  knob most likely to be re-picked by #1110.
- **S2. The party-relative branch (`>= 100`) has ZERO dynamic observations.** It
  is closed statically only. Five deployed slots use it, and the one savestate
  whose record carries such levels (201) is not the record its units aligned to.
- **S3. The midpoint erases variance the ROM has.** A 13-wide window becomes one
  number, so the rig's fights are more uniform than FFT's by construction. If
  #1111 ever wants a lethality *distribution* rather than a mean, this is the
  line to revisit.
- **S4. The port has no save-roster override.** In the ROM a named unit already
  in the player's save keeps its own level and skips generation entirely
  (`unit[+0x02] != 0xFE`); the port scales every ENTD slot alike. This is only
  visible once the Catalogue carries levelled story characters.
- **S5. The growth walk is faithful per level but not proved against a high-level
  savestate.** The divisor sequence matches the ROM's term for term statically;
  no savestate was used to compare a *generated* unit's raw HP at level 93
  against the port's.
