# The back grammar is one table, and the claims belong to the stack

The map-hosted Formation screen ([ADR-0137](0137-the-formation-screen-re-hosts-over-the-map-as-a-camera-child-scene-entered-through-a-paused-camera-takeover.md))
grew a third nesting on `GambitBattle`: the deployment pick raises a roster grid over
the battlefield, and a Status screen opens **over that grid**. Played, it locked the
player out:

> Enter on a tile → the formation screen shows up → Enter on a unit → Tab for the
> menu → **Backspace, and the formation screen doesn't close, the cursor returns to
> the map, and you're locked out of a formation screen that is still there.**
> — user, 2026-09-08

The screen had two nesting structures and only one of them nested. `_stack`
(ADR-0084) nested correctly. The **claims** — the camera takeover, pad ownership, the
battle pause, "a pick is open" — were flat booleans, each taken by one site and
released by another, so they described *the last screen to open or close* rather than
*whether anything is up*.

## Status

accepted (2026-09-08) — grilled with the user; supersedes ADR-0137 Amendment 7's
CHANGE\_JOB exemption.

## Decision

1. **The deployment pick is a stack level, not a host mode.** `State.PICK` is the map
   host's floor. As `FormationMapHost._picking` it was invisible to the coordinator:
   with a full roster grid on the display `current_state()` answered `IDLE`, and three
   separate sites grew a private `_picking()` question to work around the lie — the
   START-menu guard, the pad backstop, and `_on_menu_cancelled`. All three are gone,
   because `IDLE` now means what it says.

2. **The claims are held iff the stack is non-empty.** Taken by the push that makes it
   non-empty, released by the pop that empties it, and by nothing else. This is the
   lock-out's actual mechanism: `TileCursor._input_allowed()` refuses every press
   unless `camera_mode == CURSOR`, so **the camera takeover IS the battlefield cursor's
   input gate**. Backing out of the action menu ran a `leave()` that released the
   takeover with the pick's grid still up — the tile cursor woke underneath a live
   screen, where ○ was refused by `_on_deployment_confirm` and ✕ was swallowed by
   `TileCursor` before the grid's own dismiss could see it. No press could close it.

   `PlayerCamera.request_takeover`/`release_takeover` is a **single flag with no
   depth**, shared with the cinematic manager and the effect viewer, so it cannot be
   taken twice and released once. Depth-counting it was rejected: making a shared
   engine-level resource tolerant of unbalanced calls is how a cinematic that forgets
   one release becomes an undebuggable frozen camera. One owner, one seam.

3. **The pad claim is derived, and `PICK` is excluded from it.** `map_input_owned()`
   reads the stack instead of a flag. `PICK` is excluded because a pick *is* the
   roster grid, and the grid reads the pad through `FormationScene._unhandled_input`
   — a wholesale claim in `_input` runs earlier and would eat the arrows that walk it.
   Nothing is unguarded there: the cursor underneath is frozen by the camera claim.

4. **✕ is one level, always. The back grammar is a table.** `_UNWIND_ROSTER` /
   `_UNWIND_MAP`, read once by `_exit_settled` and by the Amendment 7 predicate. The
   depth used to be stated in three places in prose beside a `pop_back()`/`clear()`,
   and prose is where they drifted.

   `_on_menu_cancelled`'s extra `leave()` — fired whenever the host had supplied
   `action_rows` — is deleted. Its reasoning (#941) was that a host menu is its
   screen's only verb, true of the one-row deploy set. But `action_rows` is not a fact
   about the menu that is closing: `GambitBattle` assigns `ROWS_ADJUST` at **mount**,
   so the branch fired on every ✕ on that host. On the adjustment rows the Status
   screen *is* a destination — it is where you read the unit before choosing "Gambit".

5. **CHANGE\_JOB joins the map host's pop-one column.** Amendment 7 excluded it
   because "committing a job change is a destination, not a detour" — an argument
   about the **commit**, applied to the press where you did not commit. Left exempt,
   ✕ off Item landed on Status and ✕ off Change Job landed on the battlefield, one row
   apart on the same menu. The RE25 full unwind stays on the roster host, where the
   grammar really does bottom out at a roster, and on the commit path.

6. **A multi-level unwind is the stack's own, not a signal handshake.**
   `unwind_all()` walks the stack down for the exits that are a *destination* — a
   completed deployment. `GambitBattle._close_picker` used to arm a `CONNECT_ONE_SHOT`
   on `settled` and call `leave()` from the handler, but `settled` has eight emitters,
   so a detail box-open or a gambit surface landing in between stole the shot.

## Rejected

- **Fork the coordinator for the battle overlay** (the user's own "perhaps an
  alternate version with different transition rules"). Every defect here was a rule
  stated in one place and not another — `_dispatch_menu_row` exists precisely because
  #941 found that a rule stated in only one of two dispatches does not hold. A fork
  doubles that surface. The roster host already disagreed with itself about Change
  Job, so the table earns its place before the map host is even considered.
- **Keep the pick a host mode and re-take the claims after each nested exit.** Leaves
  `current_state()` lying about what is on the display, which is the thing that made
  each of the three workarounds necessary.

## Consequences

- `State.PICK` is **appended** to the enum. Several tests compare `current_state()`
  by value; inserting it would silently redefine `IDLE`..`GAMBIT`.
- The MAP\_DETAIL recipe plays only when `DETAIL` is the bottom. Over a pick there is
  no camera to take (it is taken) and no tile to pan to — the unit is benched — so
  Status opens the self-clocked way the roster host opens it.
- Guarded by `FormationMapHostTest` (the table, both hosts, both new levels) and
  `GambitDeploymentPickerTest` arm 10, which drives the user's four presses through
  the real InputMap. Arm 10 **only reds through its `_settle()`**: the teardown it
  asserts against takes a measured 31 frames, and reading four frames after the press
  scores the defect green.
