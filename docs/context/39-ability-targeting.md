# Ability targeting

What an ability *may reach* and what its blast *covers* — the axis before
[hit policy](07-ability-hit-policy.md), which decides which of the units already in
that area are affected. The ROM answers both with one channel and several writers,
so the vocabulary here names the **channel** first and the mechanisms second.
Transcribed from `BATTLE.BIN` by [#839](https://github.com/timbermania/fft-monorepo/issues/839),
[#840](https://github.com/timbermania/fft-monorepo/issues/840) and
[#900](https://github.com/timbermania/fft-monorepo/issues/900); the model itself is
[#845](https://github.com/timbermania/fft-monorepo/issues/845)'s, and this file is only
the words for it.

**Hit set**:
The **tiles an ability will actually affect**, and the one thing every targeting path in
the ROM agrees on. It is not a data structure of ours: in `BATTLE.BIN` it is **tile record
byte `+5`, bit 7**, set on each tile in the set and cleared on the rest, then read by the
damage target-list builder `FUN_8017D850` — a unit is admitted only if its tile carries the
bit. Naming the channel rather than the mechanism is what makes the ROM's shape sayable,
because **the bit has more than one writer**: the **AOE grid** builder writes it for area
abilities, and the projectile flight validator writes it for the single unit a shot actually
reaches ([#838](https://github.com/timbermania/fft-monorepo/issues/838)). Grid targeting and
flight targeting are two writers of one channel with one consumer, not two systems.
_Avoid_: "the AOE" as a synonym (that is one writer of the set, not the set); "targets"
(plural) for the set, which collides with **target**, the single gambit-selected unit that
[hit policy](07-ability-hit-policy.md) scopes that word to.

**Range grid**:
The tiles an ability **may be aimed at**. Built by `FUN_8017A290` from the caster's position
and the ability's `range` byte, flooded in 2D and mirrored into both terrain levels, then —
only if the ability carries the ROM flag `vertical_tolerance` — filtered by
the **column collapse**. 86 of 368 abilities carry that flag, so for the other
282 **the range grid has no vertical restriction at all**: you may aim at a
bridge deck fifteen levels up.
_Avoid_: "targeting grid" (ambiguous between this and the **AOE grid**); "reach".

**AOE grid**:
The tiles an ability's **blast covers**, once aimed. Built by `FUN_8017B874` from the
ability's `effect_area` byte, and — unlike the range grid — **column collapsed**
unconditionally for the abilities that reach that builder at all. Deliberately **not**
called the *effect* grid: in this package "effect" means the `E###.BIN` visual subsystem
([effect orchestration](15-effect-orchestration.md),
[Effect Studio](16-effect-studio-authoring-tool.md)), and `effect_area` is the ROM byte that
sizes this grid rather than a name for it. `aoe` is the incumbent spelling in the shaders
(`U_AOE_*`, `aoe_ability`, `AOE_CENTER_*`) and it wins.
_Avoid_: **effect grid** (reads as the visual subsystem's); "blast radius" (the radius is
`effect_area`, a scalar; this is the tile set it produces).

**Aimed cell**:
The `(x, z, level)` an ability is **centred on** — a full [terrain cell](38-terrain-lattice.md),
not a [column](38-terrain-lattice.md). Its *level* is load-bearing rather than incidental:
the **column collapse** takes its **reference height** from this cell's own tile record,
indexed `level * 0x100 + z * W + x`, so a blast centred on a bridge deck and one centred on
the moat beneath it produce different hit sets. This is why `AOE_CENTER_X/Z` gains a level
field (ADR-0224 dec. 4, as amended 2026-09-05) instead of deriving one at read time.
_Avoid_: "center tile" (a tile is the scene node — see [Tile](38-terrain-lattice.md));
"target cell", which invites confusion with **target**, the selected unit.

**Column collapse**:
The per-column filter that is the **only stage of ROM targeting that reads a height at all**.
Everything before it — the seed and the flood — scans one level's coordinates and mirrors
each reached cell into both, so a grid that skips the collapse is height-blind in both
directions. The collapse walks every column and does two things: it keeps the single cell
whose height is nearer the **reference height** and erases the other (ties keep the ground
plane), then erases the survivor too if it lies beyond the **vertical reach**. An ability
that skips it is what produces a column-wide area — which is why ADR-0224 dec. 6 was
retracted rather than merely corrected.
_Avoid_: "flatten"; "column merge" (nothing is combined — one cell is erased).

**Reference height**:
The height the **column collapse** measures every candidate against, in **half-levels**, as
`b2*2 + (b3 & 0x1f) + (b3 >> 5)*2` off a tile record. It is **not one number per ability**:
the **range grid** evaluates it at the *caster*, the **AOE grid** at the **aimed cell**.
Conflating the two is easy and wrong — an AOE centred away from its caster collapses around
where it *landed*, not around who threw it.
_Avoid_: "caster height" (true for the range grid only); "ground height".

**Vertical reach**:
How far above and below the **reference height** a cell may sit and still survive
the **column collapse** — `vertical × 2` in half-levels, i.e. the ability's
`vertical` stat in whole levels. Deliberately distinct from **`vertical_tolerance`**, which is the ROM *flag*
(`flags1 & 0x08`) deciding whether the **range grid** collapses at all: the flag is
ROM-canonical and already spelled in `ability_attributes.json`, while the allowance is
derived and ours to name. Naming both "vertical tolerance" would make one word mean a
boolean on one grid and a distance on the other.
_Avoid_: **vertical tolerance** for the distance; "vertical range" (collides with `range`).
