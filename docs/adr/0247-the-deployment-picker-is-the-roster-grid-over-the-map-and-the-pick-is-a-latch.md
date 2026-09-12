# The deployment picker is the roster grid over the map, and the pick is a latch

ADR-0242 built the deployment MODEL and the on-map editing verbs, and left the
half that decides **who** fights as `benched()[0]` — one press on an empty zone
tile deployed whoever came first in roster order. At Gariland the zone's cap is 5
against a 7-unit roster, so choosing who fights is half the deployment decision;
and #940's own note recorded that `benched()[0]` agreed with the mandatory-unit
reserve **by accident of roster order**, not by design. This file is the picker
that replaces it, built (#941) to the design the user settled on 2026-09-06.

Three things the ticket named were straightforward — a fourth `StartActionMenu`
row set, the system-bank cues, a `cursor_cancelled` signal. Two were not. The
ticket says the picker opens "the map-hosted Formation screen" and that you
"pick the unit there", but that screen turns its **roster grid off** and answers
"who is selected" **from the tile cursor** — and a benched unit stands on no
tile, is hidden, and is not in the GPU battle. And it says the pick "LATCHES",
which is a statement about what the *map* shows, not about what the host
remembers.

**The first build got the picker wrong, and the user corrected it in review.**
It walked the bench one unit at a time on the map host's own Status panels,
reading the tension as "that screen has no grid, so the picker cannot be one."
The user's answer: the Formation screen *shows you all your units* — that is what
makes it a picker rather than a scroll. They were right, and the obstacle was
smaller than the first build priced it at.

## Status

accepted

## Decision

1. **The picker is the ROSTER GRID, raised over the battlefield for the length of
   a pick.** `owns_roster_grid()` gated only the BUILD, never the screen's ability
   to have one, so `build_roster_grid()` / `free_roster_grid()` make it a thing the
   host raises and drops — the same three calls `_ready` makes, reversibly. While
   it is up the grid answers "who is selected" (`selected_character()` defers to
   `FormationScene`'s answer-by-cell) and takes the roster's own d-pad routing,
   which this host otherwise suppresses.

2. **It is the MAP host with its grid switched on, not the ROSTER host mounted
   over a battlefield — and `paints_own_backdrop()` is why.** The roster host
   paints a cobble floor and pillarbox bars; over the map that covers the very
   thing you are deploying onto. The map host answers `false` and keeps doing so
   through the whole pick, which is the one predicate that makes "the Formation
   screen, over the battlefield" a real combination rather than two screens
   fighting. It is also the assertion the rig makes, because a test cannot look at
   the screen.

   The first build's rejection of this — "it would put a second selection UI over
   a map the cursor is already driving" — was **weak, and is withdrawn**. The pick
   takes the camera (`begin_hold`), which freezes the cursor, so there is nothing
   to contend with. The real obstacle was one predicate, and the screen already
   had a switch for it.

3. **The pick opens the MAIN menu, not the action menu — so the host-rows check
   is stated on BOTH dispatches.** A plain grid has no detail screen under it, and
   `open_action_menu()` refuses without one; the door for a menu over a bare
   roster is `open_main_menu()`. `FormationDetailTransition.action_rows` swaps the
   rows on either door and routes every choice out through `action_row_chosen`,
   because both dispatches are keyed by INDEX and an index means nothing across
   two row sets — a host-rows check on only the detail path would have sent row 0
   into `enter(State.EQUIP)`. The coordinator stops having an opinion about a list
   it did not author.

   The guard that refuses a MAIN menu on the map host at IDLE stays, narrowed by
   exactly one clause: its reason was "a map has no plain roster, so a
   MAIN-formation menu over a battlefield is a menu about nothing." During a pick
   it has one.

4. **`ROWS_DEPLOY` is one row, and it is the first row set in this port with no
   ROM behind it.** FFT's deployment screen has no action menu; the user's
   explicit ask was to keep the reverse-engineering faithful *and* roll our own
   menu rather than choose between them, and `rows` has been a host-swapped `var`
   since §15.23 — so `ROWS` stays byte-untouched. One row because the screen is
   already showing one unit and the tile was chosen before the screen came up:
   a second row would be a question the player has already answered.
   `LOC_DEPLOY`'s rect is DERIVED from the three proven homes (each is
   `rows*16 + 16` tall and each one's frame art ends at display x244), and it is
   labelled as derived — an invented "oracle" citation is worse than none.

5. **The pick is a LATCH on a TILE, not a carry of a unit.** ○ on an occupied
   tile lights it `CellMarking.Kind.SELECTED` — whose own docstring already said
   "Picked and LATCHED — the cursor has moved on" — and frees the real cursor, so
   two tiles are lit and the player is looking at both ends of the move when they
   press again. Keyed by tile because every verb the second press has (move,
   swap, refuse) is a question about tiles, and the unit is one `unit_at` away.
   The `_carried` variable it replaces was invisible: the state lived in the host
   and the map showed nothing.

6. **A misfire outside the zone refuses and STAYS latched.** The second press is
   the expensive one — it is the press that spends the selection — so an aim that
   lands off the zone must cost nothing. This is the one refusal in the deployment
   verbs that does not reset state.

7. **The deployable tiles stay GREEN.** The user described them as blue;
   `PLACEMENT_PLAYER` renders green and BLUE is `PLACEMENT_ENEMY`, i.e. "you may
   not place here". Keeping the existing marking is one value changeable later,
   where re-colouring it touches a `TileOverlayConfig` `GPUArena` shares.

8. **✕ is a CURSOR intent, `CursorRig.cursor_cancelled`, not a host keybind.**
   ACT and LOOK arrived as signals while BACK was a `ui_cancel` test in
   `GambitBattle._unhandled_input` — two thirds of one intent published and the
   rest re-derived per host. That is the road `unit_inspect` went down: three host
   actions bound to the same key because no port owned the intent. It rides the
   built-in `ui_cancel` name (Backspace here) rather than minting `cursor_cancel`,
   so the battlefield does not back out on a different key from every screen.

9. **Facing is a pure function of the assignment, recomputed on every edit.**
   Every deployed unit turns toward the nearest authored enemy ENTD tile, by
   column distance, on every `_show_assignment` — which covers both units in a
   swap for free and cannot drift out of step with the layout. There is no rotate
   control in this ticket: the ROM has one, and it is a separate verb with its own
   input.

10. **A refusal is audible.** `_report_refusal` printed, which is not feedback:
    the player presses ○, nothing moves, and nothing says why. The system bank
    already carries the vocabulary — `invalid` (5), `unit_removal` (9), `set`
    (10), plus `confirm_selection` / `cancel_selection` for the latch — so this
    adds cues, not a cue system.

11. **The picker offers what the tile would actually TAKE.** The bench is filtered
    by `effective_cap`, so with four of five Gariland tiles held by cadets the
    reserve holds the last slot and the list is exactly one name long. Offering a
    unit the confirm would then refuse is the "legal all the way to the commit and
    then refused at it" shape ADR-0242 dec. 7's reserve exists to end — and a
    picker is where that shape would have come back.

12. **`GambitBattle` mounts the map-hosted Formation screen once, and `can_open`
    is the exact negation of `_cursor_confirm_is_mine`.** The screen and the host
    both listen to `cursor_confirmed`; one predicate read by both sides makes that
    a DISPATCH rather than a race. During deployment ○ is the host's (latch or
    picker) and the screen never sees it; on a turn that is not yours the screen
    opens the unit's panels, as on the arena.

## Rejected

- **Walk the bench one unit at a time on the map host's Status panels** — the
  first build, and the thing the user corrected. It is a scroll, not a picker: the
  Formation screen's whole contribution to this decision is that it shows you
  everyone at once, and a screen that shows one unit and a ← key does not.

- **Mount the ROSTER host over the battlefield.** It paints its own backdrop —
  see dec. 2. That is one predicate away from working and the map host is already
  on the right side of it.

- **A `DeploymentPickerHost` subclass.** It would inherit an entire screen to
  re-answer one question the map host already localises, and the grid it wants is
  a lazy build, not a class.

- **Cycle the bench with repeated ○, no screen.** Rejected by the user in the
  design session and again in the handoff: choosing who fights is a decision the
  player should see the unit's stats to make, which is what the screen is for.

- **Give `ROWS_DEPLOY` a second "Cancel" row.** ✕ already cancels, everywhere in
  this tree; a row that duplicates a button is a row that can disagree with it.

- **Paint occupied zone tiles `PLACEMENT_UNAVAILABLE` ("Already claimed").** The
  ticket notes the kind exists; it is not the right one here. An occupied zone
  tile is a fully legal second press — it SWAPS — so "unavailable" would be a
  false statement about the only tiles the latch can be resolved onto. It shares
  a slot with `PLACEMENT_PLAYER` too, so painting it would replace the green
  rather than layer over it.

- **Latch by holding the UNIT rather than the tile.** Identical while nothing else
  moves, and wrong the moment something does: `unit_at(tile)` is the map's own
  answer and cannot go stale against it.

## Consequences

`GambitBattle` grows a picker region and loses its `_carried` variable and its
`ui_cancel` branch. `GambitBattleTest`'s arm 3 is rewritten around the latch and
gains the facing and zone-paint assertions; the picker gets its own rig,
`GambitDeploymentPickerTest`, which drives the arrows, △ and ○ as **physical key
events through the real InputMap** — the routing is where "the key does nothing"
lives, and setting `selected_cell` directly would skip the action lookup, the
frozen cursor's swallow and the host's own dispatch.

**A missing grid is invisible to every question except one, and
`has_roster_grid()` exists because of it.** `selected_character()` reads the
injected roster by INDEX and `_cell_has_unit` falls through to grid-bounds nav
when nothing is populated — so a host that never built a grid selects, navigates
and reports a character exactly like one that did. Seeded that way, the picker's
rig passed every assertion but one, in a completely different arm. The grid is
what the player SEES, and it now has an assertion of its own.

`CursorRig` publishes FIVE signals now, not four. Its class docstring still says
four about the MEASURED union that closed ADR-0164 dec. 4 criterion 1; that
measurement was of what hosts read in 2026-08 and stays true of what it measured.

**`ui_cancel` is now swallowed by `TileCursor` in every cursor-bearing scene.**
Safe for its twins' reason — `_input_allowed()` is false during a camera takeover,
which is exactly when a screen is up and wants ✕ for itself — but it is a wider
blast radius than the other four items in this ticket, and it is the one to look
at first if a back-out stops working somewhere with a map in it.

The action is exempt from `check_addon_install.py`'s arm 2 (`ui_` prefix), so the
addon owes no new provide.

`GambitBattleTest` arm 3 now ends by restoring the canonical `auto_fill` layout.
Arms 5 and 6 play the battle the assignment produces, and "does Gariland end by
annihilation" is a question about a specific deployment — an arm inheriting
whatever the edit arms left would measure a different battle every time one of
them changed.
