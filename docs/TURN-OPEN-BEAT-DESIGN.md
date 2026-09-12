# The turn-open beat — settled design

**Status:** design settled 2026-09-08 in a `/grilling` session; **built 2026-09-08**, on
`feat/turn-open-beat`. Two corrections were forced by building it and both are marked 🔴
below: the swallow is *three* gates rather than one, and §4's stated reason for `Home` is
not the measured one (the key is right anyway).
Every statement below is a decision the user made and confirmed, or a fact read
out of the tree at the paths cited. Companion to
[`GAMBIT-BATTLE-DESIGN.md`](GAMBIT-BATTLE-DESIGN.md), whose §3 this fills in.

⚠️ **The beat is a COMPONENT now — `src/gpu/TurnBeat.gd`, not `GambitBattle`**
([ADR-0265](adr/0265-the-navigator-needed-a-battle-host-surface-and-the-turn-presentation-is-components.md)).
`NavigatorMain` mounts the same one. Every decision below still holds and none of them
moved; what changed is the address, and the reading of §5's "the host's `_commandable`" —
each host now supplies its own steerability set, and the navigator grew one to do it.
The host keeps the THIRD of the three gates (its own `_unhandled_input`) and the `print`,
because Space and Esc reach neither the cursor rig nor the camera and two hosts write two
log prefixes. Function names on `GambitBattle` are unchanged: they are wrappers now.

---

## The defect

In `GambitBattle`, when a turn opens you cannot tell whose it is.

The world already stops correctly — `TurnDirector._open_turn`
(`src/gpu/TurnDirector.gd:250`, ADR-0239) gates the pump on the exact tick a
living unit crosses the meter, and emits `turn_opened(taker, team)`. The host's
handler (`GambitBattle._on_turn_opened`, `src/scenes/GambitBattle.gd`) opens the
adjustment window, opens the imperative charges, and then **`print()`s** "Your
turn: X. Tab to adjust, Space to commit, Backspace to cancel."

That print is the entire notification. No camera move, no cursor move, no
on-screen marker, no cue. The freeze is correct and silent.

**This is therefore a presentation defect, not a turn-model defect.** Nothing in
this document changes the director, the pump gate, the snapshot, or the turn
model.

---

## Rejected: cached / claimable turns

Considered and rejected: letting a turn sit un-taken while the world keeps
running, with the player pressing a key (`1` for the first unit, …) to claim it —
at which point the game pauses and focuses that unit.

Rejected because it is a **different machine, not a better notification**:

- It requires the world to keep running while a turn is pending. That is **Active
  mode**, which `GAMBIT-BATTLE-DESIGN.md` names an explicit v1 non-goal.
- It breaks the pre-turn snapshot contract. `AdjustmentTurn`'s undo image is taken
  at the instant the meter is crossed (ADR-0252 dec. 1); a turn claimed N ticks
  later would cancel back to a world that no longer exists.
- The felt problem — "it isn't clear which unit it is" — is 100% presentation. A
  mode change does not address it and costs the semantics already paid for.

---

## Load-bearing facts read out of the tree

| Fact | Where | Consequence |
|---|---|---|
| The freeze gates `CombatLoop.tick`, not the scene tree | `TurnDirector.gd:250`, ADR-0037 dec. 2 | **The camera animates normally during a frozen turn.** Travel-while-frozen needs no new machinery. |
| `PlayerCamera.follow_cursor(world_pos, snap := false)` takes a world position directly | `addons/exmateria_battlefield/camera/PlayerCamera.gd:378` | The camera can be driven to the taker *before* the cursor is placed. |
| `follow_ease_frames = 18` (~0.3 s), already the ADR-0068 tunable `camera.follow_ease_frames` | `PlayerCamera.gd:59,170` | The travel duration is an existing knob. No second knob. |
| `FormationMapHost` mounts a docked **hover pair** (portrait + vitals) that repaints on `cursor_moved` and parks off-edge when no unit is under the cursor | `src/ui3/formation/FormationMapHost.gd` — `_on_cursor_moved`, `_push_pair_views`, `_arm_hover(±1)` | **The name/vitals plate already exists and is cursor-driven.** Parking the cursor on the taker makes it appear for free. No new plate. |
| `GambitBattle` already mounts that host | `GambitBattle._setup_formation_map_screen` | Nothing to wire; the plate is already on screen in this scene. |
| The pair is painted "byte-identical" by two hosts from shared view builders | `FormationMapHost._push_pair_views` doc comment | Forking it to express turn state would break the roster host. Do not touch it. |
| `TurnQueueHud` draws the forecast strip, leftmost = acting now, and refreshes only on turn edges | `src/ui3/TurnQueueHud.gd`, `GambitBattle.gd` mount | A highlight on its head entry is free and costs nothing per frame. |
| `StatusBubble3D` is a camera-facing billboard parented to the unit, drawn from one atlas cell, despawning with its unit | `src/ui3/elements/StatusBubble3D.gd`, ADR-0063 | The exact mount shape the AT sprite wants. |
| `combat_visuals` freeze is the **cinematic spotlight**'s (ADR-0037 dec. 7), not the turn director's | `src/effects/EffectInstance.gd:123` | The turn freeze does not hide over-unit billboards. A spell cinematic would — a known edge, not this ticket's. |
| Bound input actions: `ui_accept ui_cancel ui_focus_next ui_focus_prev ui_left/right/up/down battle_start battle_pause unit_inspect rotate_camera_cw/ccw camera_up/down/left/right formation_sort_next/prev formation_start_menu world_map_start_menu cursor_confirm` | `project.godot` | **Nothing is free** — a recentre key means a new action. Note `camera_*` can pan the camera off the taker independently of the cursor. |
| System SFX bank slot 18 = `help_message_popup` | `assets/audio/sfx_banks/sfx_bank_names.json` via `SfxCatalog.slot_for("system", …)` | The ROM's own "an informational plate came up" cue. |
| For a non-steerable taker the host runs `_think_for()` then `call_deferred("_pass_turn")` | `GambitBattle._on_turn_opened` | An enemy turn is an open-and-pass within a frame or two, plus the rollout's `cap_ms` hitch. There is no player-visible stop. |

---

## Decisions

### 1. The beat, on a steerable taker

In order:

1. **World freezes** — already happens. The **AT marker appears** on the unit here,
   at the freeze, so it is already present when the camera arrives.
   `adjustment.open()` and `imperatives.open()` stay exactly where they are, at the
   crossing tick: they are the **undo image**, and taking them 18 frames later
   would snapshot a world the turn did not open in.
2. **Camera travels** to the unit over `camera.follow_ease_frames` (18f, ~0.3 s).
   **Input is swallowed for the duration. There is no skip.**

   🔴 **A swallow is THREE gates, not one.** The battlefield accepts device input on three
   independent surfaces, and gating one just tells the player which key still works: the
   **cursor** (`CursorRig.input_enabled` — movement, ○, ✕, △), the **camera**
   (`PlayerCamera.input_enabled` — Q/E and F, and Q/E is the one that matters because
   `_rotate_yaw` re-aims a running travel at the cursor's *pre-beat* tile), and the
   **host's own `_unhandled_input`** (Space and Esc, which reach neither of the other
   two). A camera TAKEOVER looks like a free deafen and is not: `PlayerCamera._process`
   returns early in any non-CURSOR mode, so it would silence the input *and delete the
   travel it exists to show*.
3. **Cursor lands** on the unit's cell. Its own `cursor_moved` then slides the
   existing hover pair in — so the plate arrives at the end of the beat for free,
   and the camera does not lurch a second time (the cursor's follow target is the
   position the camera has already reached).
4. **Beat over.** Frozen world, free cursor. The player unfreezes it by committing.

**Degenerate case:** if the cursor is already on the taker there is **no travel and
no swallow** — the beat is instant, because there is nothing to show.

### 2. The marker is the ROM's AT sprite

The floating **"AT"** sprite over the acting unit, as the ROM draws it. Mounted the
way `StatusBubble3D` is: a camera-facing billboard parented to the unit, drawn from
an atlas cell, despawning with its unit.

- **Shown at the freeze, hidden on `turn_committed`.** Never absent while a turn is
  open; never present when one is not. A cancel re-opens the same turn, so the
  marker survives a cancel.
- **Player turns only** — see §5. This **diverges from the ROM on purpose**: the
  ROM's predicate is "this unit is the acting unit", whoever that is
  (`AT_MARKER_RENDERING.md` §4.1). The port gates on the host's `_commandable`.
  Restoring fidelity here is a change to §5, not a bug fix to the code.
- **Rejected: a tile marking.** An earlier draft added `CellMarking.Kind.TURN_TAKER
  = 7` to paint the cell under the unit. The AT sprite does the same job, is the
  ROM's own answer, and reads as belonging to the unit rather than to the ground.
  **No new `CellMarking` value is added.**

**Sequencing: done.** The seam (`show_turn_marker(unit)` / `hide_turn_marker()`)
landed first and the sprite landed into it on **2026-09-08** —
`src/ui3/elements/TurnMarker3D.gd`, a unit-child billboard drawing the ROM's own
`RANGETILE(114,176)` / `(114,188)` cells with its 16-frame flip and 1 px bob.
Its RE is `research/working_documents/AT_MARKER_RENDERING.md` (§8.1 records why
it is its own node rather than a `StatusBubble3D` icon index; §8.3 tabulates
which of the ROM's six requirements the port meets and which two are open).

### 3. The cursor is parked, then free

The beat parks the cursor on the taker. **It is not locked there.** Reading the
board is the whole point of a reconfiguration turn — you are deciding what gambit
to write — so the player may walk the cursor anywhere while the world stays frozen.

Consequently **the hover pair is never locked to the taker.** It shows whoever the
cursor is on, exactly as it does today, including enemies. The AT sprite is what
carries "whose turn," which is what makes free roaming safe.

### 4. `Home` recentres

A **new input action `turn_recenter`**, bound to `Home`, snaps **both cursor and
camera** back to the turn taker from anywhere.

🔴 **The reason below was wrong and the key is right anyway.** Measured while building:
`camera_up/down/left/right` **are** `TileCursor.CURSOR_ACTIONS` — they walk the *cursor*,
and `PlayerCamera._execute_translation` returns immediately unless the
`camera.free_camera` debug override is on, so in normal play they pan nothing on their
own. What actually strands the taker is the cursor, which decision 3 deliberately leaves
**free**: walk it across the map and the camera follows it there, and now the acting unit
— and the AT sprite with it — is off screen. Q/E is the second route,
`PlayerCamera._rotate_yaw` recentring on the *cursor's* tile rather than the taker's.
Both make the conclusion hold.

~~Needed because `camera_up/down/left/right` can pan the camera off the unit without
moving the cursor at all~~, so the taker — and the AT sprite with it — can end up off
screen with no cheap way back. Without this key, "leave the cursor free" is a
one-way trip.

The weaker meaning ("camera back to the cursor") is already covered: one cursor
step drags the camera to it.

### 5. Enemy turns get nothing

No camera travel, no cursor move, no AT sprite, no cue.

An enemy turn is an open-and-pass — there is no stop the player experiences — so a
beat would be a disruption with no decision behind it, and a marker that flashes on
and off eleven times a round-robin is noise. **AT means "this is yours to steer."**

**One exception, and it is not a beat:** the `TurnQueueHud` strip advances its
highlight on every turn, including enemy ones. It is already on screen, already
refreshes on turn edges, steals no camera and no input. Without it the rollout's
`cap_ms` hitch is a frame that stutters for no visible reason, which reads as a bug
rather than as thinking.

### 6. The cue

`help_message_popup` (system bank slot 18) on the beat.

It is literally the ROM's sound for "an informational plate just came up," which is
what this is. `confirm_selection` was rejected as transactional — you hear it again
two seconds later when you actually confirm something — and `power_up` reads as a
buff landing.

---

## Explicit non-goals

- **No Active mode, no cached or claimable turns.** See "Rejected", above.
- **No changes to `TurnDirector`**, the pump gate, the snapshot, or the turn model.
- **No new plate.** The cursor-driven hover pair already exists and is unchanged.
- **No new `CellMarking` value.**
- **No travel skip** and **no camera return** — the camera stays where the taker is,
  because the next thing the player does is almost always at that unit.
- ~~**No AT sprite implementation** — that is a separate reverse-engineering effort;
  this builds the seam it lands in.~~ **Landed 2026-09-08**; the seam is no longer
  empty. See §2 "Sequencing".

---

## Test

**One test**, asserting state and not pixels — the suite is ~736 processes at a
~2.3 s Godot boot each (`docs/TEST-CHARTER.md`), and half this feature is a camera
animation. Carry every assertion that shares the setup:

- on `turn_opened` for a steerable taker, the cursor cell == the taker's cell;
- input is refused during the travel and accepted after it;
- the marker seam is called shown on open and hidden on commit;
- `turn_recenter` returns the cursor to the taker after it has been moved away.

**Not** asserted: the easing curve, the sprite's appearance, the cue's audio.

**Built as arm 4a of `tests/GambitBattleTest.gd`, not as its own scene.** It needs exactly
arm 4b's setup — scenario 9 booted, deployment committed, a commandable turn held open —
and TEST-CHARTER clause 13 prices a second process at 2.3 s on every run forever. Two
things the arm has to do that the spec above does not say:

- **It cancels the turn on purpose.** `TurnDirector.cancel` re-opens the *same* turn, which
  is the only way to observe a beat from a *known* cursor position. Without it the first
  beat is whatever the deployment arm left the cursor on — possibly the taker's own tile,
  i.e. the degenerate no-travel case, and the arm would assert nothing about the travel.
- **"Hidden on commit" is read from inside the `turn_committed` signal.** `commit` DRAINS,
  so by the time the call returns a second ready unit may already have raised the marker on
  itself. Read after the fact, that assertion is about the battle seed.

---

## Open items deliberately deferred

- ~~The AT sprite itself — art, atlas cell, and render path (separate RE effort).~~
  Done 2026-09-08. Two ROM behaviours are still deliberately unbuilt: the marker's
  **status-alternation** (the ROM swaps AT with an active status every 16 frames)
  and the ROM's **depth-only `+0x0C` lift**. Both are recorded in
  `AT_MARKER_RENDERING.md` §8.3, not lost.
- Whether the beat should ever be skippable, if the 18-frame toll proves annoying
  in play. Settled as "no skip" for now; it is one `static var` away from being
  revisited.
