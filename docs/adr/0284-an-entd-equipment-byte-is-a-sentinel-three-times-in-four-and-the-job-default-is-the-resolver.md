# An ENTD equipment byte is a sentinel three times in four, and the job default is the resolver

## Status

Accepted

Built by [#1121](https://github.com/timbermania/fft-monorepo/issues/1121), on
build map [#1101](https://github.com/timbermania/fft-monorepo/issues/1101).

## Context

[#1110](https://github.com/timbermania/fft-monorepo/issues/1110) re-seats the
corpus rig on **real ENTD rosters**, so what an ENTD slot's weapon byte *means*
stops being trivia and becomes the denominator of every weapon-tier lever.

An ENTD slot (`research/key_documents/ENTD_FORMAT.md`) carries five equipment
bytes — `head` 0x12, `body` 0x13, `accessory` 0x14, `right_hand` 0x15,
`left_hand` 0x16. **The item table is 0..0xFD** (`items.json` holds exactly 254
records, ids 0–253), and three values outside or at the edge of it dominate the
data. Counted over the 847 slots `EntdBattle.combatant_slots` would actually
deploy (its own filter: `unit_id != 0xFF`, `always_present`, not a protected
NPC) — **not** the raw `job != 0` count, which includes 2,535 empty slots'
padding and the event-join units the port already drops:

| `right_hand` | deployed slots | human slots (720) |
|---|---:|---:|
| `0xFE` | 529 | **506** |
| `0xFF` | 117 | 95 |
| `0x00` | 101 | 19 |
| an item id | 100 | 100 |

So **an explicit weapon is the minority case by seven to one**, and `0xFE` is
not an edge case — it is the norm.

### What the three bytes mean

**`0xFE` is the same "the game fills this in" sentinel the rest of the slot
already uses.** `ENTD_FORMAT.md` documents it for `level`, `month`, `day`,
`bravery`, `faith` and `experience`; the equipment bytes were simply never
written down. It is also self-corroborating in the data: **410 of the 720
deployed human slots carry `level == 0xFE` too**, and 311 of those are the same
slots whose weapon byte is `0xFE`.

**Dynamically closed.** A PCSX-Redux savestate is main RAM, so this was settled
offline with no emulator launch. The battle unit table is at **`0x801908CC`,
stride `0x1C0`, 21 slots** (slot 20 is followed by the pointer block at
`0x80192D8C`). A unit carries its ENTD `unit_id` at **`unit+0x161`** — that is
the join key back to a record. The five equipment bytes are at **`unit+0x1A`
head, `+0x1B` body, `+0x1C` accessory, `+0x1D` right hand, `+0x20` left hand**,
with `0xFF` = empty — established by item-id *range* legality over 571 live-unit
observations across every savestate in `reference-assets/`, with **zero**
cross-column violations (no other window survives: `+0x1C..+0x20` puts an
accessory id in the head slot).

> 🔴 **This paragraph originally read "an enemy carries its ENTD slot index at
> `unit+0x02`", and that was wrong** — corrected by
> [ADR-0289](0289-the-entd-level-byte-is-not-a-level-and-resolving-it-is-only-half-the-fix.md).
> `unit+0x02` is the player-ROSTER index for a save-loaded unit and `0xFF` for an
> ENTD-generated one (SCUS `0x8005aa6c`–`0x8005aa9c` sets it to `0xFE` across the
> stat-growth call and back), so the original join read *player party members* as
> if they were the record's enemies. The ENTD `unit_id` at `+0x161` is what
> `entd_to_roster_loader_16` writes (BATTLE `0x8017fa1c`).

Re-censused on the corrected key across every savestate — **64 distinct
ENTD-generated units**, save-loaded ones excluded:

| ENTD byte | resolves to |
|---|---|
| an explicit item id | **that id, verbatim, in every one of the 64** |
| `0xFE` head | Leather Hat 157 ×17, Feather Hat 168 ×7, 144 ×6, 153 ×2, 154 ×1, empty ×2 |
| `0xFE` body | Clothes 186 ×23, 206 ×10, 172 ×6, empty ×2 |
| `0xFE` right hand | Broad Sword 19 ×11, Dagger 1 ×6, 30 ×4, 64 ×3, 67 ×2, 77 ×2, 59 ×1, 68 ×1, empty ×2 |
| `0xFE` accessory | **empty ×10**, then 224/226/230 ×2 each, 220/227/229/232 ×1 |

`0xFE` resolves to **real, level-appropriate gear**, drawn from a *spread* of
ids within a tier — so the ROM's pick is a **random draw from the qualifying
set**, not a deterministic one. The accessory column is the exception worth
naming: half its sentinels resolved to nothing at all.

**`0x00` is the literal `<Nothing>` record** — `items.json` id 0 is named
`<Nothing>` — and it is what monsters carry: 2,746 of the 3,104 monster slots.
In RAM a monster's five bytes read `00`, passed through unchanged.

**`0xFF` is an absent slot**, the same spelling `unit_id == 0xFF` uses for an
absent unit, and the value the runtime writes for an empty hand.

Statically, WORLD.BIN's equip/inventory list builder agrees that none of the
three is an item — it masks the slot to ten bits and rejects both ends:

```
801216AC  andi  v0,v0,0x3ff
801216B0  beq   v0,zero,...        ; 0 -> not an item
801216B8  slti  v0,v0,0xfe         ; >= 0xFE -> not an item
```

### 🔴 The address the ticket and the research doc both cited is not a resolver

`ITEM_AVAILABILITY_TIMELINE.md` §6a, and #1121 quoting it, name `0x801950CC` as
"BATTLE.BIN's level-gated **enemy-equipment** picker". It is not. The enclosing
function is the **AI's Throw / Item usability gate**:

```
80195078  lbu  v0,0x1ba(s4) ; andi 0x30 -> player branch or AI branch
8019509C  lbu  v0,-0x6920(at)  ; player: 0x800596E0 + id = the party ITEM LEDGER
801950CC  lbu  v1,0x2eba(at)   ; AI:     0x80062EBA + id*12 = rec[2] enemy_level
80195110  ...                   ; loop s0 = 0x17F..0x188, s2 = 1..10
8019513C  lbu  v0,0x2ebd(at)   ; rec[5] class byte == table[0x80061020 + s2]
```

Ability ids **`0x17F`–`0x188` are Knife, Sword, Hammer, Katana, NinjaSword, Axe,
Spear, Stick, KnightSword, Dictionary** — the ten **Throw** classes, bracketed
by `0x17E` Shuriken and `0x189` Ball. The loop picks the best *throwable* of each
class; the `enemy_level` read is the gate on what an AI unit may **throw**, and
the player branch reads the inventory ledger instead. It never touches a unit's
equipment slots. No code in BATTLE.BIN reads `rec[2]` for equipment at all —
the only other reader is the steal/break AI's value comparison at
`0x80187BE4`/`0x80187C08`.

**Where the real resolver lives is still open.** The ENTD record is not resident
verbatim in RAM during a battle, so it runs before BATTLE.BIN's battle loop and
was not located this round. The *effect* is what is closed, and it is closed
dynamically.

### What the port did with all this

`Character._seed_equipment_from_slot` skipped `0xFF` and `0` and wrote
**everything else through verbatim**, so a `0xFE` byte put **item id 254** in
the slot. `ItemDatabase.get_item(254)` returns `{}` and `is_weapon(254)` is
false, so the unit reached the kernel with **WP 0, range 1, weapon_type 0,
`weapon_id` -1** — and silently, because a missing record is an empty dictionary,
not an error. Worse, it **overwrote** the job default weapon that
`create_default` had already seeded, so the majority sentinel was the only one
that destroyed the fallback. Measured over the 720 deployed human slots: **123
reached the kernel holding a weapon record. 597 did not.**

The fallback itself was also broken. `Character.get_starting_weapon` is a
hand-authored job → weapon-id table, and four of its twelve ids named a
different item from their own comment: Archer `81` is Hunting Bow not Long Bow
(83), Lancer `97` is Papyrus Plate not Javelin (99), Samurai `113` is Octagon
Rod not Asura Knife (38), and Ninja `129` is **Buckler, a shield**, which
`is_weapon` rejects outright.

## Decision

1. **All three of `0`, `0xFE` and `0xFF` are sentinels, none is an item id, and
   `_seed_equipment_from_slot` skips all three.** The job default survives, which
   is what the function's own docstring already claimed for the other two.

2. **`0xFE` is spelled `ENTD_RANDOMISE`** — the constant that already exists on
   `Character` for the level/brave/faith bytes. One sentinel, one name, one
   meaning across the whole slot: *the game fills this in*.

3. **`Character.get_starting_weapon` IS the port's enemy-equipment resolver**, and
   it is named as such in its docstring. The ROM's picker is **not ported**. It
   draws at random from the highest-`enemy_level` qualifying items of a legal
   class, which would make a rig run irreproducible, and it needs the unit's
   level — which 410 of 720 deployed human slots do not carry either (they are
   `0xFE` as well, and the port resolves them to level 1). A fixed job default is
   a *deterministic sample* of the ROM's own draw: on the one battle closed
   dynamically it lands in the same tier on every generic slot (Dagger / Broad
   Sword, both `enemy_level` 1) and on the same item for two of four.

4. **Every id in that table is a weapon id**, verified by name against
   `items.json` and guarded: `EntdBattleInitTest` asserts `0 <= id < 128` for
   every covered job.

5. **A rig seated on real rosters records which policy armed each unit.** The
   substitute is not the ROM, so a corpus that does not say so cannot be compared
   to one that used a different rule. This is #1110's obligation, stated here so
   it is not rediscovered.

6. **The job table covers 12 jobs, and that is a known, measured gap, not a
   silent one.** 303 of the 506 `0xFE` human slots carry a job it does not cover
   — story jobs (`01`–`04`, `07`, `0b`, `28`, `30`, …) — and they stay
   bare-handed. Fixing dec. 1 alone lifts the armed count from **123 to 318 of
   720**; closing the rest is follow-up work, not this decision.

## Consequences

- **195 more deployed units reach the kernel holding a weapon record**, so any
  measurement taken before this is not comparable to one taken after. #1110 and
  #1111 must both run post-fix.
- The four corrected job ids change what an Archer, Lancer, Samurai and Ninja
  swing. Ninja in particular goes from **bare fist to Ninja Knife**.
- `weapon_type` reaches more units than the map's charting fact assumed on the
  enemy side, and fewer than the raw ENTD suggests: the honest denominator is
  **720 deployed human slots**, not 5,657.

## Rejected

- **Port the ROM picker faithfully.** It is a random draw over a level-gated
  candidate set, and the level is itself a sentinel on most slots. A rig whose
  rosters change run to run cannot referee a lever.
- **Treat `0xFE` as "no weapon".** It is the opposite of what the ROM does —
  dynamically, those are exactly the units that get gear.
- **Leave the write-through and special-case it downstream.** Item id 254 is not
  an item; every consumer would need the same guard, and each would fail silently
  the same way.

## Soft spots

- **S1. The real resolver was not located.** Its *effect* is closed dynamically
  on one battle; the function that produces it is not cited. A second savestate
  from a high-level battle would test whether the pick really tracks
  `enemy_level` upward.
- **S2. `0xFF` vs `0xFE` is closed statically, not dynamically.** No savestate in
  `reference-assets/` maps to a record carrying `0xFF` on a *human* slot. The
  closing experiment is one savestate of such a battle.
- **S3. `unit+0x1E` and `+0x1F` are unexplained.** They never held an item in 571
  observations, yet the left hand is at `+0x20`, two bytes past the right hand.
- **S4. The job table is a sample of one.** Two of four generic slots matched the
  ROM's draw exactly and all four matched its tier, on a single level-1 battle.
  That is not a measurement of the substitute's fidelity at higher levels.
- ~~**S5. Level `0xFE` resolves to 1.**~~ **CLOSED** by
  [ADR-0289](0289-the-entd-level-byte-is-not-a-level-and-resolving-it-is-only-half-the-fix.md)
  (#1179): the ROM scales the sentinel to the highest level in the player's
  20-slot roster, and the port now resolves *and grows* to a record-derived
  ceiling. That also weakens this ADR's dec. 3 second reason for not porting the
  ROM's equipment picker — "it needs the unit's level, which 410 of 720 slots do
  not carry either". The level is carried now; the *reproducibility* reason
  stands alone, and is why dec. 3 still holds.
