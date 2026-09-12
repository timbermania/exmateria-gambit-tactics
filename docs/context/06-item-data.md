# Item data

The vocabulary that distinguishes the four overlapping "item"-ish
identifiers FFT mixes together. Each one is the right key for exactly
one job; using the wrong one silently samples the wrong table without
crashing. The easy mistake is keying a sprite-side lookup off `graphic`
(the menu-icon index) or a SEQ-side lookup off the per-record id.

**Item id**:
The position of a record in `items.json` — `0..253`, covering every
category (weapons `0..127`, shields `128..143`, armor `144..207`,
accessories `208..239`, consumables `240..253`). The PSX engine indexes
its **per-item battle-graphic table** (BATTLE.BIN `0x2d3e4`, 144 entries
`0..0x8F` for weapons + shields only) by this id; that table holds the
WEP1 palette nibble, the EFF1 palette nibble, and the vertical pixel
offset into WEP1.tga that picks each specific weapon's row. So sword id
35 (Excalibur) and sword id 51 (Rod) are categorically identical (same
[item type id](06-item-data.md), same SEQ behavior) but visually distinct
(different rows of WEP1.tga). `WeaponGraphicData` keys here.
_Avoid_: calling this "item type" — that is the per-family id below;
keying `WeaponGraphicData.get_v_offset` off `items.json[id].graphic`
(the bug shape: Rod was reading Excalibur's pixels because
`items.json[51].graphic == 35`).

**Item type id**:
The per-family classifier — `0..34`, with 19 weapon families (Knife=1,
Sword=3, Polearm=15, Bag=17, Cloth=18, Shield=19), 12 armor families,
and 3 throwables (Shuriken=32, Ball=33, ChemistItem=34). Multiple items
share an id — Dagger and Mythril Knife both have `item_type_id=1`. The
PSX engine indexes its **per-item-type animation table** (BATTLE.BIN
`0x2d364`, 3 bytes/entry for the high/mid/low BODY slot) by this.
`weapon_animation_ids.json` keys here; so does the
[animation resolution map](18-sprite-layers.md)'s attack resolver.
_Avoid_: keying sprite-side data off this (no per-instance
discrimination — Dagger and Mythril Knife sample identical pixels under
this key); calling it "weapon type" outside humanoid-attack contexts
(it is also defined for armor and consumables, which never produce a
swing animation).

**Graphic** (field on items.json):
The **menu-icon graphic** index used on inventory / shop / equipment
screens — has no role in battle rendering (authority: ffhacktics wiki
"Item Graphics in Battle"). Distinct integer space from [item
id](06-item-data.md); do not key any battle-time table by `graphic`.
_Avoid_: passing `items.json[id].graphic` as the key to
`WeaponGraphicData.get_v_offset` or any other BATTLE.BIN
`0x2d3e4`-derived lookup; conflating with the WEP1-layer sprite-row
selection (that comes from the per-item battle-graphic table keyed by
item id, not from this field).

**Item palette** (field on items.json):
The top-level `palette` field on each `items.json` record — pairs with
[graphic](06-item-data.md) to drive the **menu-icon** color row, NOT the
WEP1-layer palette. The WEP1-layer palette (and EFF1-layer palette)
come from BATTLE.BIN `0x2d3e4`, indexed by [item id](06-item-data.md), not
from this field.
_Avoid_: feeding `items.json[id].palette` into `wep1_palette_row` (it
is the menu-icon palette, a different table); confusing with [sprite
palette](18-sprite-layers.md) (the BODY-layer indexed-color lookup) or the
[effects-system palette](15-effect-orchestration.md) (RGB tint).
