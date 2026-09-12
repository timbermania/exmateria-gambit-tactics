# The battle feedback HUD is observation-only; its presentation splits by placement (over-unit billboard vs screen-space HUD)

FFT's in-battle UI splits into two halves: a **command** layer (the player takes
a unit's turn — the Move/Act/Wait action menu and the target-selection cursor)
and a **feedback** layer (what's happening — floating damage/heal/miss numbers,
status & charge icons over units, the unit-info window when you point at someone).
This game is a **gambit-driven auto-battler**: the GPU compute engine is the sole
writer of battle state (ADR-0031) and units act autonomously from player-authored
gambits. The player issues nothing during combat — so FFT's command layer has no
home here today (a future *command gambit* would route any manual order through
the normal `Gambit→GPU projection` path, never making the CPU a battle-state
writer). What remains, and what we are building, is the **feedback** layer.

The existing combat UI (`CombatUI` in `GPUArena`) is the player-operated
[Window](../context/31-combat-ui-windows.md) cluster — roster bars, equip/ability/stats/gambit
menus, pickers. It is the management surface, not feedback: it takes input and
drives the game. The feedback HUD is the opposite data direction and a different
element class, so it is named and modeled apart (CONTEXT.md **Feedback HUD**).

Full reverse-engineering of the feedback elements is in
`docs/battle-hud-faithful-spec.md`; this ADR records the architectural shape the
grilling settled.

## Status

Accepted (2026-06-17). Scope: the **feedback HUD** — over-unit damage/heal/miss
numbers, over-unit status & charge/CT icons, and the field-inspect unit-info
window. Built **additively** alongside the existing combat UI (nothing removed;
the pieced-together management windows are deprecated incrementally, later, where
FFT has an equivalent — game-original pieces like gambit config are kept). The
**command HUD** (action menu, target-selection cursor) is explicitly out of
scope, deferred to the future command-gambit feature. The turn-order display is
**vanilla — none** (FFT PSX has no on-screen turn list to reproduce).

## Decision

**The feedback HUD is observation-only — an apply-only consumer of the combat
loop's existing GPU signals that never reads FFT's ROM data and never writes
battle state. Its *presentation* splits by placement: elements that belong
*on a unit* are unit-anchored 3D-billboard [combat-visuals](../context/02-combat-buffer-layout.md);
everything else is ordinary screen-space `ui3` HUD.** The observation-only part
is the cross-cutting rule; the rendering mode is chosen per element.

1. **Observation-only, apply-only (applies to ALL feedback).** The HUD is a new
   consumer of `CombatLoop.hp_changed(unit_index, prev_hp, new_hp, delta)`
   (GPU-authoritative, emitted from `GPUCombatInterpreter`'s `HP_CHANGED` event
   carrying `was_heal` / `killed`), of the snapshot's status flags, and of the
   unit's own `UnitStats`. It issues nothing and writes no battle state — the
   [Battle-state authority](../context/02-combat-buffer-layout.md) line (ADR-0031) holds. Faithful FFT
   **visuals**, our **data**.
2. **Over-unit elements → unit-anchored 3D billboards.** *Damage/heal/miss
   numbers* and *status/charge bubbles* are camera-facing billboards positioned
   above the unit (matching FFT, which GTE-projects them with a `+0xC` px raise),
   with **CUSTOM0 GTE depth** so they sort against battlefield geometry, enrolled
   in the `combat_visuals` group so they ride the **ADR-0037** freeze (finishing
   naturally post-victory). They are the UI sibling of `Charge VFX` / `Projectile`.
   **Not a 2D screen-space overlay** — that would sort wrong and sit outside the
   freeze model.
3. **Screen-space elements → ordinary `ui3` HUD.** The *unit-info window* (and any
   menu-like feedback panel) is a normal screen-space `ui3` panel at a fixed
   position — the same machinery as the rest of `ui3`, **not** a billboard floating
   on a unit. It is observation-only (read-only, grabs no input), so it is a
   feedback element, but its *placement* is the screen, not a unit. (FFT draws its
   info window at a fixed screen location via the window/font system, consistent
   with this.)
4. **Over-unit ownership splits by lifetime.** Persistent **status/charge bubbles**
   are a unit-child billboard (they belong to the living unit). Transient **damage
   numbers** are map-anchored at the unit's position (like `Projectile`) so the
   killing blow's number survives the unit's death-frame — death-resilience over
   parent-ownership.
5. **Faithful visuals, our data.** We reproduce FFT's feedback **graphics** — the
   digit and status-icon sprites live in the already-extracted `RANGETILE.tga`
   system atlas; `tools/parse_range_tiles.py` is extended to emit their UV cells +
   CLUT rows (the texels exist; only the metadata is new) — but the **values**
   are this game's (`UnitStats` / snapshot), not FFT's `BattleUnitData`. Only the
   *look* is faithful; the meaning is ours (the
   [take-the-visuals-remap-the-meaning](../context/01-asset-extraction.md) rule).
6. **Field-inspect for the info window.** Pointing/clicking a unit on the
   battlefield (3D pick, `collision_mask = 4`) opens an FFT-layout info window
   reading our `UnitStats`, shown **alongside** the existing portrait→StatsMenu
   path — read-only observation, not a [modal window](../context/31-combat-ui-windows.md).

## Considered options

- **Presentation split by placement (chosen).** Over-unit elements are 3D
  billboard combat-visuals (faithful to FFT's over-unit placement; sort via the
  repo-wide CUSTOM0 depth; reuse the ADR-0037 freeze / `combat_visuals` group; no
  new pause/sort machinery); screen-space elements are ordinary `ui3` panels.
  Each element renders in the mode its placement implies.
- **Everything as a 2D screen-space overlay (rejected for over-unit elements).**
  Simpler text layout, but for *numbers/bubbles* it diverges from FFT's 3D
  placement, **sorts wrong** against battlefield geometry (no CUSTOM0
  participation), and sits **outside** the combat-visual freeze model — it would
  need its own pause handling and world→screen projection feed, re-introducing
  the very split ADR-0037 avoids. Screen-space *is* the right mode for the
  info window — hence the per-placement split rather than one blanket mode.
- **Everything as a unit-anchored billboard (rejected).** Over-generalizes — the
  info window (and any menu-like feedback) is a screen panel, not something that
  floats over a unit; forcing it into a billboard fights the `ui3` HUD it
  naturally belongs to.
- **Read FFT's `BattleUnitData` for the info window (rejected).** Faithful to
  the source, but pointless: we already hold the authoritative values in
  `UnitStats`/the snapshot, and reading the ROM struct at runtime would be a
  second source of truth for state the GPU owns. Only the *layout* is worth
  reproducing.
- **A new texture extractor for digits/icons (rejected).** Unnecessary — the
  texels are already in `RANGETILE.tga`; only the UV/CLUT **metadata** is
  missing, so we extend the existing parser instead of adding a pipeline.
- **Build the command HUD now / add a WotL turn-order sidebar (rejected/deferred).**
  The command HUD surfaces an unbuilt mechanic (command gambit) and FFT PSX has
  no turn-order list to reproduce — both are net-new design, not faithful
  reproduction, and are deferred rather than invented here.

## Consequences

- **New apply-only consumer** of `CombatLoop`'s per-event signals — the feedback
  HUD connects to `hp_changed` (numbers), the snapshot status flags + charge
  state (icons), and a 3D unit-pick → `UnitStats` (info window). No new
  battle-state field, no writeback.
- **Parser extension, not a new artifact:** `tools/parse_range_tiles.py` gains
  damage-digit + status-icon UV-cell + CLUT-row output in `RANGETILE.json`,
  sourced from the BATTLE.BIN tables the RE located (`Status_Bubble_Icon_X/Y`
  ~`0x800949dc`, digit geometry `0x10`/`0x0E`).
- **One blocking prerequisite:** a PCSX-Redux VRAM capture confirming the
  digit/icon cells in RANGETILE + their CLUTs and the number→digit/colour mapping
  (spec §8.1–8.3). The info-window exact frame CLUT/positions (§8.5) and
  animation cadence (§8.4) are capture items but non-blocking for a first cut.
- **Deferred, not lost:** the command-HUD RE (action menu, selection cursor) and
  the turn-order CT-prediction model stay documented in the spec for when the
  command-gambit feature lands. The §4 cursor *input/bob* already shipped
  (ADR-0046); only its selection use is deferred.
- **Deprecation is incremental:** the feedback HUD is additive; StatsMenu and the
  roster bars keep working until the faithful equivalents prove out in real
  battles. Gambit config is kept permanently (no FFT equivalent).

## Amendment 1 (2026-08-28) — built almost entirely, and the only ADR audited so far whose cross-cutting rule has its own guard; the gaps are the *miss* number and which icon a status picks

*Audit pass, 2026-08-28 (ADR consolidation). The six Decision bullets above were an unnumbered
list; they are now `1.`–`6.` so `ADR-0063 dec. N` citations resolve. Nothing else was changed,
and no prose was removed. Graded against the tree.*

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
| --- | --- | --- | --- |
| 1 | Observation-only, apply-only consumer of `CombatLoop.hp_changed(unit_index, prev_hp, new_hp, delta)`; never reads `BattleUnitData`, never writes battle state | **built, and mechanized** | The signal exists with that exact signature (`CombatLoop.gd:37`), carrying `was_heal`/`killed` from `GPUCombatInterpreter` (`:63`–`:64`). `FeedbackHudManager.setup` connects it idempotently (`:55`). Uniquely in this corpus so far, the invariant has a **guard**: `tools/check_feedback_hud.py`, run from `tests/run_all_tests.sh:665`, which fails on ROM reads / battle-state writes from a HUD class and on a billboard that forgets the group or the OT-depth shader. |
| 2 | Over-unit numbers + bubbles are camera-facing billboards with CUSTOM0 GTE depth, in the `combat_visuals` group | **built** | `DamageNumber3D:122` and `StatusBubble3D:41` both `add_to_group("combat_visuals")`; both document the CUSTOM0 Ordering-Table seam (ADR-0009) and the ADR-0037 freeze. |
| 3 | Screen-space elements are ordinary `ui3`, not billboards | **built** | `FieldInspectController` (in `src/ui3/`) opens `UIUnitInfoWindow`, a screen-space panel; the guard's own scope note excludes it from the billboard net for exactly this reason. |
| 4 | Ownership splits by lifetime — bubbles parented to the unit, numbers map-anchored | **built, verbatim** | `FeedbackHudManager`'s header: `DamageNumber3D` is "parented to THIS manager (map-anchored) so the killing blow's number outlives its target's death-frame"; `StatusBubble3D` is "one persistent bubble per unit, parented to the unit (dies with it)". |
| 5 | Faithful visuals, our data; `parse_range_tiles.py` extended to emit digit + status-icon UV cells and CLUT rows | **built for the cells; the status *selection* is placeholder** | The parser gained both families — the digit strip and `status_icon_set()`, read from BATTLE.BIN's parallel `Status_Bubble_Icon_X/Y` arrays (file offsets `0x2D9DC`/`0x2D9F4`, the ADR's `0x800949dc` less the `0x80067000` base). `RangeTileAtlas.status_icon_rect(i)` consumes them. But see below — which cell a *status* picks is invented. |
| 6 | Field-inspect: 3D pick, `collision_mask = 4`, FFT-layout window over our `UnitStats`, alongside the portrait→StatsMenu path | **built, including the literal** | `FieldInspectController.gd:11` — `const UNIT_PICK_MASK := 4`, used at `:76`; `:90` states it reads "UnitStats / progression / status — never FFT's ROM BattleUnitData". |

### The Status line is honest, and the invariant is guarded

Two things worth recording because the preceding five audits found the opposite. First, this
ADR's Status ("Accepted (2026-06-17)") makes no claim about a pending build, so the
stale-`pending` streak (0040, 0069, 0071, 0092, 0093) does not extend here. Second, dec. 1 is
the first cross-cutting ADR rule this audit has met that someone actually mechanized:
`check_feedback_hud.py` is a text net, but it is scoped, wired into the suite, and it names the
ADR. The corpus-level lesson from the other audits — "the rule survives, the guard never
existed" — does not apply to this one.

### The *miss* number was never built

"Damage/heal/**miss** numbers" appears three times above — in the Status scope line, in dec. 2
and in dec. 5. `DamageNumber3D` ships `enum Kind { DAMAGE, HEAL, MP }`: there is no MISS kind,
no miss path in `FeedbackHudManager`, and no signal that could feed one (`CombatLoop` publishes
`hp_changed`/`state_changed`/`action_committed`, none of which distinguishes a miss from a
zero-damage hit). Conversely `MP` is built and is not named anywhere in this ADR — the source
calls it "here for when an MP-number consumer is wired (spec §5 type 3)". So the shipped
element set differs from the specified one in both directions, and the direction that matters
is the missing one: a miss number is a *new GPU-side signal*, not a rendering task.

Two further cosmetic shortfalls the code declares in its own comments, both consistent with
this ADR's "non-blocking capture items" consequence rather than contradicting it: `HEAL`/`MP`
numbers use flat tints because only the damage CLUT (`0x7d7c`) is RE'd, and the zodiac sign in
the info window reuses that same digit CLUT as a documented default until the menu CLUT is read
from VRAM.

### Recorded question — is a placeholder status→icon map inside dec. 5 or outside it?

`parse_range_tiles.py` extracts the *faithful* `status_type → atlas cell` table from the ROM
("read from the table … not eyeballed"). The runtime does not use it as a mapping:
`FeedbackHudManager` declares `STATUS_ICON = {poison: 1, stopped: 2, petrified: 3, hasted: 4,
slowed: 5}` and `CHARGE_ICON := 19`, with a comment saying the ROM table → our-status
reconciliation "is UNRECOVERED — the atlas cells are unlabeled (spec §8, open item #1/#6), so
these are stable PLACEHOLDER indices". A poisoned unit therefore shows whatever cell 1 happens
to be. Two readings:

- **Reading A — this is an open gap against dec. 5.** The decision promises faithful feedback
  *graphics*, and an icon's identity is a graphic, not a value. The extraction half is already
  done; what is missing is labelling the 20 cells (a VRAM capture / spec §8 item the ADR itself
  lists) and mapping our status names onto them. Until then the bubbles are faithful in style
  and wrong in content.
- **Reading B — it is inside dec. 5's own boundary.** Dec. 5 says "Only the *look* is faithful;
  the meaning is ours", and our status set is not FFT's: `hasted`/`slowed` may have no ROM
  counterpart at all, so a total mapping is not merely unrecovered but undefined. On this
  reading the placeholder table is the correct terminal state for the statuses that do not
  correspond, and only the ones that do (poison, petrify, stop) are owed a fix.

Not guessed here — settling it requires knowing whether our status vocabulary is meant to
converge on FFT's, which is a game-design question this ADR does not own.

### On mechanizing this ADR

Dec. 1 and dec. 2 are already covered by `check_feedback_hud.py`; dec. 4's ownership split and
dec. 6's pick mask are covered by `FeedbackHudTest` / the field-inspect path. The arm that is
**absent and cheap** is over dec. 5: assert that every cell index `FeedbackHudManager` hands to
`StatusBubble3D` is `< RangeTileAtlas.status_icon_count()` and that the mapping is sourced from
the extracted table rather than a literal dictionary. Today it would report the literal, which
is the correct answer while the question above is open — so it is a guard to write *after* the
reconciliation, not before.
