# The gambit surface is three levels of one list, and the action menu dispatches by name

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §4 makes **all four adjustment types
legal** on an open turn — gambits, equipment, job, ability slots. ADR-0252 built
the turn that makes three of them work: equipment, job and ability slots are
editable through the map-hosted formation screen today. **Gambits were not, because
there was no screen for them** (#1007).

`UIGambitDisplay` and `UIGambitEditor3` were the only UI in the tree that could
show or edit a `GambitList`. Both have been unreachable since ADR-0137 Amendment 2
hid `UICombatManager`, and `GPUArena._demolish_legacy_combat_ui` freed the arena's
copy outright — its own comment names this ticket: *"🔴 ONE THING GOES DARK WITH IT
AND HAS NO NEW HOME: the gambit surface."*

## Status

accepted

## Decision

1. **The ROM-faithful screen wants a different shape, so the two UI2-era components
   are not re-hosted.** `UIGambitEditor3` is a mouse-clicked `UIModalWindow`: its
   rows are `UIClickableField`s, its only keyboard binding is ESC, and it is placed
   by a `UIWindowHost` the formation screen does not have. Every neighbour on that
   screen — the equip picker, the ability picker, the job wheel, the action menu —
   is a glove-cursored ○/✕ list driven from the pad. Re-hosting the modal would put
   **the one screen you cannot reach with the controller** in the middle of the turn
   loop, on a battlefield where the pad is the only input the design assumes. The
   two components stay where they are, still compiled by `UICompileTest`, still the
   record of what a full sentence builder looked like.

2. **The surface is SLOT → PART → CHOICE, and all three levels are one class.**
   `GambitSurfaceMenu` is a titled list of strings with a glove, a box-open and the
   ROM's scroll window; `GambitSurface` is the two-integer stack that says which
   list is showing. Three classes would have been three copies of the glove, the
   scroll and the fold twin. What differs between the levels is the STRINGS, and
   strings are data.

3. **A PART is edited, not a field, and each part offers named whole values.** A
   `Gambit` is an `ActionKind`, an `ability_id` and two `TargetSelector`s carrying a
   pool type, a team filter, a role filter and a resolution strategy. Exposed as
   fields that is a five-dropdown form over a cross-product most of whose cells are
   nonsense — "Self, filtered to enemies, resolved by lowest stat" is reachable and
   means nothing. The unit already reads its gambits as a sentence
   (`Gambit.get_sentence_lines`), so the screen edits the sentence: **Do**, **To**,
   **When**, **If**, plus a named **Clear**. Each choice is a whole selector built by
   the domain's own constructors (`TargetSelector.enemies().with_resolution(…)`,
   `GambitCondition.target_hp_below(…)`), never a raw enum.

4. **The part rows ARE the readout, so there is no second display window.** Each
   row shows its part's current value ("Do: Attack", "If: HP < 50%"), and landing a
   choice returns to the sentence, which now reads it back. `UIGambitDisplay`'s job
   — showing what a slot says — is done by the list you edit it from.

5. **The reachable set is smaller than the legal set, and that is the trade.** The
   curated choices cannot author every valid `Gambit`. They can author every gambit
   a player can read back off the row, which is the property that matters for a
   screen. The mutation operators (#895) write into the same list without passing
   through here, so the generator is not bounded by what this offers.

6. **The action menu gains a game-original row set, and the ROM's five stay
   byte-untouched.** `StartActionMenu.ROWS_ADJUST` is `["Item", "Ability", "Change
   Job", "Gambit"]` — three ROM verbs plus the gambit door, with the two roster
   verbs dropped because mid-battle "Remove Unit" and "Order Unit" name nothing a
   turn can do (they were already inert on the map host). It is the second row set
   here with no oracle behind it, after ADR-0247's `ROWS_DEPLOY`.

7. **The coordinator dispatches the action menu BY ROW LABEL, not by row index.**
   This is the load-bearing change. ADR-0247 named the hazard exactly — *"an index
   means nothing across two row sets"* — and took the only position available at the
   time: a host that supplies rows also owns what they mean. Index 3 is "Gambit" on
   `ROWS_ADJUST` and "Remove Unit" on `ROWS`, so an index-keyed dispatch reaches a
   roster verb. A **name** means the same thing in both sets. `MENU_LABEL_STATE` maps
   the four verbs this coordinator owns to their states; a label it does not know
   still leaves through `action_row_chosen`, so ADR-0247's rule survives intact for
   the rows it was written for.

8. **The two chosen-row handlers became one.** `_on_menu_chosen` and
   `_on_main_menu_chosen` carried the same body and the same comment twice, and #941
   found out the hard way that a rule stated in only one of them does not hold — a
   host-rows check on only the detail path sent the deployment pick's row 0 into the
   Equip screen. `_dispatch_menu_row` is stated once.

9. **A four-row list gets a four-row home.** Each of the three oracle containers is
   `rows*16 + 16` tall (5→96, 4→80, 3→64), the rule ADR-0247 derived for the deploy
   home. `ADJUST_HOME_FOR` pairs each five-row home with its four-row twin, and
   `home_for` is asked AFTER the existing side-flip policy has run — so the
   adjustment menu inherits "open opposite the unit" for free, and a row set with no
   twin passes straight through instead of having to opt out.

10. **✕ pops exactly one level, on both hosts.** ADR-0137 Amendment 7 made that a
    map-only rule because the roster host's ✕ grammar bottoms out at the roster.
    This surface is never reached from the roster — it is on a row set only a battle
    host supplies — so there is no second case to disagree about.

11. **The surface does not mark the turn touched.** `touch()` is raised by
    `unit_act_requested`, which fires when ○ opens the screen on a unit, and there is
    no route to this surface that skips that press: the "Gambit" row is on the menu
    that press opens. A second answer to an answered question can only ever differ by
    one of them being wrong.

12. **The title is FONT.BIN text, not a baked atlas cell.** *(Amendment 2 retired the
    title for the ROW level entirely — this argument now governs the IMPERATIVE level,
    which is the one that still wears one.)* The atlas carries two
    window tabs, "Eqp" and "Ability", RE'd off the ROM's own lower windows. FFT has
    no gambit screen, so there is no "Gambit" cell to sample and never will be — and
    reusing the "Ability" cell (the ability picker's deliberate deviation) would
    title this window with the name of a *different* screen one press away.

## Considered options

**Re-hosting `UIGambitEditor3` on the formation screen**, which is what #1007's own
wording suggested. Rejected on dec. 1: the shape is wrong for the host, and the
mismatch is input, not looks. A mouse modal on a pad-driven battlefield screen is
not a re-homing job, it is a rewrite wearing 1,182 lines of someone else's layout
code.

**Deleting the two UI2-era components** once nothing re-hosts them. Rejected: they
are the only record of the full sentence builder, they cost one line each in
`UICompileTest`, and dec. 5 leaves a real gap they document.

**Appending "Gambit" to the ROM's `ROWS` as a sixth row.** Rejected twice over: the
ROM row set is byte-faithful and the map has said so since §15.20, and six rows
overflow every proven container (`rows*16 + 16` puts them at 112 against a 96-px
box).

**A `ROWS_ADJUST` that is a strict SUPERSET of `ROWS`** — the ROM's five plus
"Gambit" at index 5 — so indices agree and the index dispatch survives untouched.
Rejected: it keeps two roster verbs that do nothing mid-battle, and it buys index
compatibility that dec. 7 makes worthless. The index dispatch is the thing that was
wrong; preserving it was not a goal.

**Keeping ADR-0247's rule unchanged and having `GambitBattle` dispatch all four
rows itself**, calling `enter(State.EQUIP)` and friends from the host. Rejected: the
host would be reaching through the coordinator's front door to drive its own state
machine, and "Item opens the Equip screen" would then be stated in two places that
could drift.

**A five-dropdown editor over the raw `Gambit` struct** (the UI2 model). Rejected on
dec. 3: it exposes a cross-product, most of it meaningless, on a screen whose
neighbours are all one-column lists.

**A separate `UIGambitDisplay`-shaped readout window above the editor.** Rejected on
dec. 4 — the part rows already say what the slot says, and two surfaces showing one
list is two places for it to be stale.

**Seeding the gambit lists so the screen opens onto something.** Deliberately not
here. The seeded per-job playbook is design §7 and map #886 still carries it as
fog; the map's own note says whatever fills these lists is either this screen or the
generator, and which is not decidable until #895's operators exist. Hand-authoring
through this screen is now one of the two ways it stops being fog.

## Consequences

**Gambits are editable mid-battle for the first time.** All four of §4's adjustment
types now have a route through the adjustment turn, and `AdjustmentTurn.commit`'s
second write (`set_unit_gambits`, ADR-0252 dec. 6) finally has something to carry:
before this it landed an unedited list on every commit.

**It opens onto four empty slots, and that is the honest state.** #892 recorded that
a scenario-booted cast has empty gambit lists — `UnitSpawn` mints a `GambitList` and
nothing in the boot path authors into it — so on Gariland every slot reads "---".
`GambitSurfaceTest` asserts that rather than assuming it: an editor that opened onto
a seeded list would be reading somebody else's fixture.

**`GambitDeploymentPickerTest` changed by one assertion.** It asserted that a pick
ending hands the rows back to *empty* (the ROM's five). The host now holds
`ROWS_ADJUST` whenever a pick is not open, so that assertion moved rather than
broke — and the deploy row set is still the one row set `GambitBattle` owns the
dispatch for, which is the rule dec. 7 leaves standing.

**`GambitBattle.NO_ROWS` is gone.** With the screen always carrying rows there was
no remaining assignment for it to guard; its typed-array warning moved onto
`ADJUST_ROWS`, which is the const that now needs it.

**What is NOT here.** §5's imperative gambits (#1006) — the one-shot top-priority
lock-on with finite charges and a watchdog — are the next slot-shaped thing this
screen will have to show, and they are a separate ticket by the design's own rule.
The `enabled` flag on a `Gambit` is likewise not exposed: nothing in the tree reads
it, and a toggle for a field the kernel ignores would be a lie the player can press.

**The surface's door is △, not ○, and the rig is what said so.** Mid-battle on a
commandable taker's turn `GambitBattle._cursor_confirm_is_mine()` is TRUE, so ○
belongs to the HOST and means *commit the turn* — ADR-0137 Amendment 2's dispatch,
working exactly as designed. The first version of `GambitSurfaceTest` pressed ○ to
open the screen; that spent the turn and *then* opened it, so the menu came up with
`director.taker() == -1` and every row correctly disabled. The failure read like a
steerability bug and was a wrong keycode. It is worth writing down because the same
trap is waiting for the player: **on your turn, Enter ends it.** Amendment 6 is what
makes the △ door sufficient — `_open_for` is called with `acting = true` from both,
so the adjustment turn is still marked touched, which is what dec. 11 rests on.

**The window's size came off a capture, not off a layout assertion.** At the first
authored height the fifth row's glyphs sat on the bottom frame border, and the title
sat on the stats panel's border above. Both are invisible to every predicate the rig
can ask. The height is now `VISIBLE_ROWS*16 + 16` plus an 8-px title band, by the
same container rule ADR-0247 derived, and the title moved INSIDE the frame — unlike
the two ROM pickers, whose baked tabs poke above because they have a window to tab
against.

**Pixel placement is authored, not oracle-derived, and stays that way.** There is no
ROM gambit screen to prim-scan. The window rides one `Tune` key location
(`gambitsurface.loc.window`) so it is F3-dialable, and ADR-0244's warning applies in
full: a UI3 window host left at the camera's own origin draws perfectly and is
invisible, and no layout test can see that. A screenshot is the acceptance
instrument for where this window sits.

## Amendment 1 (2026-09-10) — the row level wears no title, and the window takes the ROM panel's margins

*Retires dec. 12 for the ROW level and re-derives the window's rect. Dec. 12's
**argument** is untouched and still governs the one level that still wears a title.*

The player reviewed the live surface. Three of the twelve things they raised are
one geometry change, and none of the three is visible to a layout predicate — which
is exactly the hazard the original "pixel placement is authored" note warned about.
All three were measured on a capture, and the fix was verified on another.

**The `Gambit` title is gone from the ROW level.** Dec. 12 argued that *if* this
window wears a title it must be FONT.BIN text and not a baked cell, and that
argument is correct and still stands — the IMPERATIVE level is the one window in
this family whose name is written nowhere else on screen, and it still wears
`Imperative` in FONT.BIN for dec. 12's reasons. What dec. 12 never asked is whether
the row level needs a title *at all*. It does not: this window is reached by taking
the **`Gambit` row of the adjustment menu**, it is the only thing on screen when it
opens, and the title was restating the press that opened it.

It was also restating it *badly*. The `STRIPE` frame inks its own top border at
`c.y + 2` and the header sat at `c.y + 3`, so the title's first glyph row was eaten
by the frame — visible on the capture, invisible to every assertion the rig can ask.
The header moved to `c.y + 4` for the level that still has one.

**The 8-px title band is now collapsible, not unconditional.** `title_band()` is 0
for an untitled window. That was already the honest answer for the two CHOICE lists
(dec. 10 took their titles away and left them paying for the band anyway — 8 px of
empty frame under the last row, and `choice_container_for`'s height was `rows*16 +
24` to cover it). It is `rows*16 + 16` now, ADR-0247's container rule and the whole
of it.

**The window took the ROM-pinned lower panel's margins.** `GAMBIT_CONTAINER` was
`(12, 134, 232, 104)` against `DetailScene.LOWER_FRAME`'s `(14, 137, 230, 94)` — the
panel occupying the very slot this window replaces. Two screens sharing one slot
disagreed by 2 left, 3 up and 2 wide, which reads as the panel *jumping* when the
surface opens. It is `(13, 137, 230, 96)` now.

`x = 13` and not 14 because **the match is on INK, not on rect**: the detail
screen's panels are FRAME.BIN 9-slice mounts and ink at their rect, while a UI3
`Frame.STRIPE` inks one px inside it. Measured on the capture, the stats panel above
inks its left column at x=14 and its right at x=240; `(13, …, 230, …)` reproduces
both. The height is 96 and not LOWER_FRAME's 94 because 96 is ADR-0247's rule for
five rows, and the original note is still true — at 92 the fifth row's glyphs sat on
the bottom border.

**The old comment's objection to moving right does not hold.** It claimed x=12 was
as far left as the window could go, because the glove hangs at `container.x −
CURSOR_X_BIAS` and the mask clips to `[0, 256]`. The ROM's own Eqp window puts its
glove at `13 − 12 + bob ≈ 1`, half off the left edge, **by design**
(`vault/Equip Sub Screen.md`). Half a glove off the edge is the ROM's look, not a
clipping bug.

**The rows element's `rect` and `authored_home` now agree, and that was a real 4-px
lie.** The rows element was built with `rect` at `c.y + 14` under an
`authored_home` of `c.y + 18`. `UI3Element.rel_world` subtracts `authored_home`
while the node itself sits at `rect`, so **every row glyph drew 4 px above the
display coordinate it was handed** — while the glove, whose element has rect ==
home, landed where the formula said. Measured on the capture: the row-0 `○` inked at
y 147–155 under a glove inked at 153–163. With the two agreeing, the window now
reproduces `StartActionMenu`'s oracle-matched relationship — text top at
`c.y + 11 + i*16`, glove top at `c.y + i*16 + 10`, the glove 1 px above the text
cell — and `ROW0_TEXT_INSET_Y` is written as `CURSOR_Y_OFFSET + 1` so the two
numbers cannot drift into two independent literals.

**ENABLE and DO moved right by 2, and DO's cap paid for it.** Those two columns are
measured off the frame's inner LEFT edge, which moved; `To`, `If` and `+N` are
measured off the RIGHT edge, which did not — x=240 before and after. `COL_DO_CAP`
went 52 → 50 to keep the 12-px chevron gap in front of `To`.

**Verified on a capture, per the original note.** `tools/capture_gambit_surface.gd`
at `--level=row` and `--level=do`, headful, engine fold active.
