---
status: accepted (2026-08-21) — grilled with the user; BUILT 2026-08-21 (see Amendment 1)
---

# The formation screen re-hosts over the map as a camera-child scene, entered through a paused camera takeover

## Context

The Formation screen (`FormationScene` + `DetailScene`, sequenced by
`FormationDetailTransition` per ADR-0084) is a flat orthographic screen you
*leave the map for*: `NavigatorMain.run_formation_view()` instances
`Formation.tscn` as a full-screen overlay over the paused battle world and waits
for `dismissed`.

The wanted behaviour is the opposite — the same screen, over the live map,
"seamlessly integrated": hover a unit with the map cursor and its nameplate +
vitals appear at the bottom; press Enter and they slide up with the dark band and
the full detail panel comes out; the camera pans so the unit sits where the
formation screen would have put it. **Only the backdrop differs** — the map
instead of the stone floor. This is a re-hosting job; no panel geometry is
redesigned.

Two facts decide the shape, and both contradict the assumption that this needs a
render-side rewrite:

- **The map camera is already orthographic.** `PlayerCamera.tscn:24-29` sets
  `projection = 1`, `size = 12.6`; `GPUArena.tscn:31` and `NavigatorMain.tscn:21`
  override only the transform and `near`. So ADR-0077's load-bearing assumption —
  that world Z *is* view-space `order_z` because the camera is orthographic — holds
  unchanged across the move. The depth ladder, the fold ordering and the
  depth-occluded vitals band do not come apart.
- **Camera-child UI is the shipped precedent.** `GPUArena.tscn:34` already mounts
  `CombatUI` (`UICombatManager`) as a child of that camera at local `z = -10`, and
  `UIWindowHost._calculate_world_position` (`:120-137`) already branches on
  `PROJECTION_ORTHOGONAL` to place UI in display-space over it.

The subtractive band needs nothing: `formation_band_fold.gdshader` — the active
fork path, selected by `FormationScene.fold_shader_for("band", true)` — is
background-agnostic (`ALBEDO = vec3(sub)`; its `spot_*` / `index_atlas` uniforms
are gone). Only the off-fork fallback `formation_band.gdshader` re-samples the
cobble, and that path is the test-runner degradation, not the runtime.

## Decision

**The formation screen re-hosts over the map as a camera-child scene in the map's
own viewport, and the Enter gesture is a paused, input-owned camera takeover whose
pan is the first beat of the ADR-0084 recipe.**

- **One camera, one viewport, one fold.** The UI mounts under
  `PlayerCamera/FocusPoint/Camera` exactly as `CombatUI` does. `_build_background`'s
  cobble quad is dropped on this host: the map *is* the background, genuinely behind
  the UI in the same opaque pass, so Pass A seeds the fold scratch with the map and
  the subtractive band subtracts from it unchanged.
- **`UICombatManager` is replaced, not joined.** It is being deprecated; this takes
  its seat rather than sitting beside it.
- **The pan target is the breakout mark.** The camera pans the selected unit's
  **body centre** to display px **`(178, 193)`** — the measured Equip/Ability settle
  `SETTLE_PX = (166, 173)` plus half the 24×40 roster descriptor
  (`FormationScene.gd:1119-1122`). This is the formation screen's own answer to
  "where does a unit go once it is no longer one of a grid," which is permanently the
  map's situation.
- **The unit is covered in settled Status, and that is faithful.** The four opaque
  frames tile `y32..231` full width (`DetailScene.gd:143-162`), so the breakout mark
  is behind the lower panel until a sub-screen narrows it to `x14..138`. The ROM does
  the same — `FormationScene.gd:917`: *"the unit sprites STAY on the grid but their
  vitals readouts blank."* We pan anyway, before the panels open, so the pan is seen
  and no second camera move is ever needed.
- **The gesture is a strict sequence, bracketed by pause and input ownership.**
  Enter: pause the battle (`CombatLoop.combat_active = false`, ADR-0037) → route all
  input to the UI → pan in → open the menus. Esc reverses it exactly: menus close →
  pan out → release input → unpause.
- **The pan is group 0 of the map host's `DETAIL` recipe**, not a hand-sequenced
  phase. ADR-0084 recipes are groups run in order with a barrier between them, and
  `leave()` replays them reversed — so "pan in, then chrome" forward gives "chrome
  out, then pan" on exit for free, and the boot-time reversibility audit covers it.
  Its reverse driver is genuinely asymmetric (`PlayerCamera.release_takeover()`'s
  cosine ease, not the entry run backward), which ADR-0084 already blesses as
  first-class. Pause/unpause sit **outside** the recipe as host state flips; they are
  not animations.
- **Two hosts, dispatched on battle state.** Out of battle, Enter opens the
  **full-screen** formation screen and returns from it — the existing
  `NavigatorMain.run_formation_view()` path. In battle, Enter runs the paused
  pan-and-open sequence above. They coexist permanently; neither replaces the other.
- **Enter means one thing: act on the unit under the cursor.** Tab keeps start/pause
  (`_toggle_command_mode` documents Deployment → Live as *"'Starting the battle' is
  mechanically just leaving Deployment"*), so Enter never needs a second meaning.
  Enter on an empty tile does nothing — no confirm dialog is introduced, which keeps
  this off the deliberately-deferred Yes/No geometry (`0x8018D280`). The **deployment
  march wins while it is active**: Enter there stays march-confirm
  (`GPUArena.gd:585`) and the screen is unreachable until the march ends.
- **Enemies get the symmetrical screen, read-only.** Hover and Enter behave the same
  on a unit you do not own; the detail panels open and show their real data
  (equipment, abilities, stats). The START menu's action rows are **disabled**, not
  hidden — painted through the ROM's disabled ramp, the shade-band offset already
  ported in `LearnAbilityMenu.gd:26` (`{1,2,3}` enabled → `{5,6,7}` disabled). No new
  palette and no new geometry; `StartActionMenu` gains the existing mechanism.
- **Hover is animated, and its cadence is AUTHORED, not measured.** Hovering a unit
  fades the band in and translates the pair in from opposite edges — vitals from the
  left, nameplate from the right — on a curve with overshoot ("opens a little too
  much, then settles"). Mechanically this is a **third `UnitInfoCluster` layout**
  (off-screen: vitals left of `x=13`, nameplate right of `x=244`) driven by the
  existing `begin_slide()`/`set_slide_frame()`; no new motion system.

  **There is no oracle for this cadence.** It is invented, and it is the first cadence
  in this screen that is. Root ADR-0001's authored/parsed line therefore decides where
  it lives, and this codebase already encodes that line in the declaration keyword:
  parsed values are `const` (`VitalsSlideAnimator.gd:26` — `SLIDE_CURVE` is the §15.1
  ROM keyframe table), authored ones are `static var` bound to a Tune slug
  (`DetailScene`'s `STATS_FRAME` / `LOWER_FRAME`, *"F3-pinned, materialised"*). So the
  hover cadence is **`static var` + `formation.hover.*` slugs in its production owner**
  (ADR-0068), scrubbed headful and materialised — **never a `const` beside
  `SLIDE_CURVE`**, which would file invented data in the parsed drawer.

  Per ADR-0097 the band fade and the pair slide take **separate named curves**: their
  units are not interchangeable (0→1 scalar vs absolute pixels), which is precisely why
  that ADR refuses a global curve enum.
- **Hover repaints, it never constructs.** One `UnitInfoCluster` is built at host mount;
  each hover calls `set_unit_view()`. No debounce until a stutter is actually observed —
  the last two perf fixes on this screen (`ui3-debug-page-rebuild-is-additive`,
  `ui3-picker-lag-was-manifest-reparse`) were both construction costs misread as
  animation costs.
- **Input ownership is a wholesale handoff with two exceptions.** While a screen is
  up the host takes `_input` and marks events handled, starving `TileCursor`,
  `GPUArena` and `NavigatorMain` alike — **except mouse events and the F3 debug
  bindings**, which stay live for the reason ADR-0084 gives for its narrower swallow.

## Why

Choosing takeover as the pan mechanism is what makes the rest fall out. Every map
input that matters is *already* gated on `camera_mode == CURSOR`:
`TileCursor._input_allowed()` (`:434`) kills cursor movement,
`TileCursor._on_camera_mode_changed` (`:555`) hides the dagger and clears
`_held_action` so no key-repeat is stuck on return, `CursorController` clears the
tile highlight and repaints it on the way back, and `PlayerCamera._input` (`:414`)
kills camera rotation. The handoff question "what happens to the map cursor while
the detail screen is up?" therefore has no bespoke answer — takeover already *means*
hidden, frozen and self-restoring.

The pan-back lands correctly only because two ADRs hold together, and this is worth
stating so it is not mistaken for luck: `release_takeover()` lerps to
**`tile_cursor.active_tile`**, not to a saved position (ADR-0041, cursor is
authoritative on camera body XYZ). That equals "the original camera position"
precisely because ADR-0084's "a screen that is up owns the whole pad" prevents the
cursor from moving meanwhile.

ADR-0037 reserved this: pause "must **not** halt the camera, menus, **future UI
overlays**." This is that overlay.

## Considered options

- **Render the map into a SubViewport and sample it as the background quad's
  material.** Superficially the most literal reading of "instead of the stone
  background, the actual map," and it needs no reparenting. **Rejected: it breaks the
  map's rendering.** `CompositorAutopilot._process` (`:70`) pins the single
  `EngineFoldCompositor` to `get_viewport().get_camera_3d()` — the *root* viewport's
  camera. A SubViewport camera never receives the fold, so every PSX add/sub prim on
  the map (effect particles, cursor, unit shadows) silently drops to native linear
  blend — the exact "vanishes on the next renderer change" fragility ADR-0077 exists
  to end. It also pays a second full render pass to do it.
- **Keep the pan, but let Enter land on a state where the unit is visible**
  (Equip-shaped chrome from a Status press). Rejected: contradicts "it's going to
  present the same screen."
- **Narrow or move the lower panel on the map host so the unit and battlefield stay
  visible.** This is what "seamlessly integrated" emotionally wants — settled Status
  buries ~73% of the screen under opaque tan frames. **Rejected as undeclared drift:**
  it is new panel geometry, which the spec itself forbids, and unfaithful port
  geometry is the specific failure this screen has already been through
  (`LEARN_PICKER.md` §15 round 8). If it is ever wanted it must arrive as a
  deliberate, recorded divergence, not as a slide.
- **Guard each leaking map handler individually on `camera_mode == CURSOR`.**
  Rejected in favour of the wholesale `_input` handoff: `GPUArena._unhandled_input`
  tests **raw keycodes**, not actions, so no named-action swallow can reach it, and a
  per-handler guard has to be re-applied to every handler added later.
- **Hand-sequence the pan with `await` around `enter()`/`settled`.** Rejected:
  ADR-0084 rejects `await` for transitions (cannot run backward, one step per rendered
  frame regardless of delta, un-drivable in a test) and hand-authoring an exit is the
  bug class that ADR exists to kill.

## Consequences

- `FormationDetailTransition` gains a second host. Its call sites cluster such that
  the map host's obligations are small: `selected_character()` and
  `screen_to_world()` are real, the five chrome setters
  (`set_orbs_visible` / `set_header_visible` / `set_box_trail_visible` /
  `set_cell_readouts_visible` / `set_unit_info_visible`) are **no-ops** (a map has no
  roster chrome), and the equip-slide cluster (`begin_equip_slide` /
  `play_equip_slide` / `end_equip_slide` / `redock_units`) is also a no-op — there is
  no grid to split, and the unit reaches the breakout mark by camera pan rather than
  by sliding. `selected_unit_screen_center()` **inverts**: on the roster host the UI
  asks where the unit is; on the map host the breakout mark is fixed and the *camera*
  moves to satisfy it.
- **`cursor_confirmed` does not exist.** `CONTEXT.md` (Tile cursor) names it as the
  signal a future selection layer would listen to, but `TileCursor` declares only
  `cursor_moved` (`:18`). Minting the confirm signal is part of this work — and per
  that same entry, the selection semantics live in the listener, **not** by adding
  them to `TileCursor`.
- `GPUArena`'s Space (`:582`), Enter (`:585`) and Ctrl+R (`:577`), and
  `NavigatorMain`'s Tab (`:564`), stop reaching the map while a screen is up. Space
  and Tab mutate `combat_active`; left leaking they would resume the battle underneath
  an open screen and make the exit unpause an already-running sim.
- The takeover guard is correct beyond this feature: Space should not unpause combat
  during a *cinematic* takeover either, which is a live bug today.
- `NavigatorMain.run_formation_view()` (`:319`) is **not** superseded. It is the
  out-of-battle path and stays live permanently — see the dispatch rule in the
  Decision.

See ADR-0037 (combat pause), ADR-0041 (cursor owns camera body XYZ), ADR-0074 (fold
is a material contract), ADR-0077 (flat UI scenes materialize order into depth),
ADR-0082 (command mode), ADR-0084 (reversible beats, recipes, the pad rule),
ADR-0097 (cadence is a named curve per verb), ADR-0068 (tunable homes), and the
monorepo root ADR-0001 (ISO-derived assets are reproducible — the authored/parsed line).

---

## Amendment 1 — built 2026-08-21

Built as decided, with three corrections the build forced. Each is recorded here rather than
slid in, because unfaithful drift on this screen is the specific failure it has already been
through (`LEARN_PICKER.md` §15 round 8).

### 1. The scale reconciliation is ×1.3125 on the UI root, and nothing else moves

The one question Consequences left open. `FormationScene` is authored for a keep-height ortho of
`240 × 0.04 = 9.6` world units; the map camera runs `size = 12.6`. Mounted camera-child with no
correction the screen occupies 9.6/12.6 ≈ 76 % of the height. The fix is the obvious one and it is
exact: scale the UI **root** by `12.6 / 9.6 = 1.3125` and offset it to `(-6.72, 6.3, -10)` so the
authored screen centre lands on the camera's local origin. `local_z = -10` is `CombatUI`'s own
shipped depth. `FormationMapHost.mount_transform_for()` is the arithmetic; nothing touches
`camera.size` — that would zoom the map, and the spec asks for a pan.

Verified headful over a live `GPUArena`: the band's top feather lands on display y ≈ 171
(`BAND_TOP_OUT` = 168) and the panels reach the screen bottom.

The Decision's load-bearing rendering claim is confirmed by the same run: the subtractive band
**does** subtract from the live map. `formation_band_fold.gdshader` is background-agnostic, so only
the cobble quad is dropped on this host — the band builds into the same `Background` holder as
before.

### 2. `set_unit_info_visible` is REAL on the map host, not a no-op

Consequences lists it among "the five chrome setters" that degenerate, on the grounds that a map has
no roster chrome. That reasoning does not reach it. The docked pair it hides is not roster chrome —
it is the **hover pair this very ADR specifies**, and when the detail overlay mounts its own cluster
at the same docked spot, the host's pair must still hand off or two pairs draw on top of each other
(the hand-off `FormationDetailTransition`'s own docstring describes: *"one pair, not two"*).

The other four (`set_orbs_visible` / `set_header_visible` / `set_box_trail_visible` /
`set_cell_readouts_visible`) and the whole equip-slide cluster degenerate exactly as described —
they iterate collections the map host never populated, so they are no-ops by construction rather
than by an override.

### 3. MAP_DETAIL is ONE group — the pan. The chrome stays a self-clocked leaf.

The Decision says the pan is "group 0 of the map host's `DETAIL` recipe", which implies the chrome
is group 1 and the exit order falls out of replaying the recipe reversed. Group 0 is built as
specified. Group 1 is not, because **the DETAIL chrome is not a beat on either host**: the ○-press
arc is a phase machine inside `DetailScene` (`play_transition` → `_tphase` SLIDE → GAP → box-open),
self-clocked, and ADR-0084 blesses exactly that. Making it a beat is a `DetailScene` refactor this
ADR does not call for, and doing it as a side effect of a re-hosting job is the drift class above.

The ordering the Decision wanted is preserved without it: the recipe's forward settle opens the
overlay, and the overlay's own `closed` signal starts the reverse play. So Enter reads *pan in, then
chrome*, Esc reads *chrome out, then pan* — verified as a frame sequence, not a screenshot. The pan
beat carries a distinct reverse driver, so the boot-time reversibility audit covers it
(`FormationRecipeAuditTest`, `FormationMapHostTest`).

### 4. A latent clip-engine bug this ADR exposed (not caused)

The box-open scissor compared a **global**-space fragment position against a rect built in the
**screen's** space (`display px × ppu`). Those are the same space only while the screen root sits at
the world origin, unrotated and unscaled — true of every UI3 screen that owns its own camera, and
false the instant one mounts as a child of the map's camera.

The symptom was specific and would have been easy to misread: every UNCLIPPED element (the pager
buttons, the hover pair, the band) rendered correctly while every CLIPPED one (all four opaque
panels, their frames, their glyphs) silently discarded every fragment — a Status screen that looked
like it had simply failed to open.

Fixed at the source: `UI3ClipEngine` now pushes a `clip_basis_inv` alongside `clip_world`, and the
seven clip shaders map the fragment back into screen space before the test. The basis is the nearest
ancestor that answers `screen_to_world` — a real criterion, since `clip_world`'s numbers are exactly
that function's image. Identity default, and identity in fact on the roster host, so that host is
unchanged (its five guards still pass).

### 5. `cursor_confirm` is its own input action

`cursor_confirmed` is minted on `TileCursor` as decided, with the selection semantics in the
listeners (`GPUArena` routes the deployment march, `FormationMapHost` routes the screen). It is bound
to a dedicated `cursor_confirm` action rather than `ui_accept`, because Godot's `ui_accept` default
carries **Space** — and on the battlefield Space is pause/resume. Riding `ui_accept` would have made
every pause also a confirm. Bound to Enter / KP-Enter / pad ○; Space keeps its one meaning.

### 6. The hover overshoot is bounded by the settled layout to ~2 px a side

Built as specified — a third `UnitInfoCluster` layout (`LAYOUT_OFF`), the pair translating in from
opposite edges on an overshooting back-out ease, the band fading in on its own monotone curve, both
`static var` + `formation.hover.*` slugs. A frame-exact capture confirms the shape: the pair reaches
`frac` 1.016 at tick 7 and eases back to 1.0 at tick 9; the band is full by tick 6, before the pair
arrives, so it is the ground the pair lands on.

The overshoot NUMBER ran into a wall worth recording, because it is a **layout** fact and not a
taste one. The two pieces overshoot *toward each other*, and the settled layout leaves almost
nothing between them: pixel-scanned off a rendered settled frame, the vitals panel's rightmost ink
(the "Lv./Exp." row) ends at display **x = 131** and the nameplate's frame begins at **x = 135** —
four pixels of slack, total, so the budget is ~2 px a side. At the classic ~1.7 strength each piece
travels ~7.7 px past its mark and the nameplate eats the last glyph of "Exp.00" for four ticks,
which reads as a rendering bug rather than as energy.

The default is therefore `0.7` — ~2.2 px each, a real flourish (≈9 screen px of travel past the
mark at 4× scale) that still clears, verified in the picture rather than argued from the rects.
**A bigger overshoot is not a bigger number, it is new panel geometry**, which this ADR's spec
forbids; if it is wanted it must arrive as a deliberate, recorded divergence. That is the one
aesthetic call in this build the author should look at and dial —
`formation.hover.pair_overshoot`, live under F3.

### 7. The cinematic-takeover Space bug, closed

Consequences noted that the takeover guard "is correct beyond this feature: Space should not unpause
combat during a *cinematic* takeover either, which is a live bug today." Closed here, since it is the
same bug: `GPUArena._unhandled_input` now returns early whenever `camera_mode != CURSOR`. Every other
map input that matters was already gated on that; this was the last one that was not.

### Deferred, deliberately

- **`UICombatManager` is not yet demolished.** The Decision says the map host replaces it rather
  than joining it. The map host takes its seat and mounts identically, but ripping `CombatUI` out
  would take the roster bars and field-inspect with it, with no replacement in this change. At rest
  the map host draws *nothing* (no band, pair parked off both edges), so the two do not collide
  today; the demolition is its own job.
- **Change-Job from the map host.** The wheel is entirely screen-space and inherited, so it should
  work, but it is unexercised over the map and untested there.

## Amendment 2 — the dispatch table: Enter ACTS, Tab INSPECTS (2026-08-21)

Reported as *"GPU arena, cursor on a unit, press Enter, nothing happens."* The diagnosis that
survived contact with a real keypress is not the one this ADR would predict, and the fix rewrites
two of its Decision clauses. It also amends **ADR-0082**, whose one-flag command-mode toggle keeps
its state model but loses its single key.

### 1. What was actually wrong — the effect cell was full and the picture cell was empty

Amendment 1's build was verified by emitting `cursor_confirmed` directly and by booting with
`use_strategy_phase = false`. Both shortcuts skipped the deployment march, so nothing ever
exercised the state the arena actually boots into. Driving a physical `InputEventKey` through the
real action, at real defaults, shows:

- **The march never declined.** `select_march_unit()` returns **true** and the unit is selected.
- **PLACEMENT is transient, not a resting state.** Four confirms retire it; the enemies auto-march;
  the phase reaches COMPLETE and Enter opens the screen exactly as this ADR says.
- **The selection drew nothing.** `march_selection_changed` reached a `print()` and stopped.

So the player hovered a unit, watched the vitals/nameplate band slide in — `_on_cursor_moved` was
never gated — pressed Enter, and the picture did not change. **The bug is a missing picture, not a
missing action.** Any fix that fills in behaviour without also filling in feedback re-ships it.

An audit of every reachable map-cursor state found **10 of 14 rows showed the player nothing**, and
only one of those ten (Enter on an empty tile) was a decision anybody had written down.

### 2. `_is_deployment_active()` was never the real problem, and neither was the gate

The tempting fix is to narrow `can_open`. It is the wrong lever. The march holds a legitimate claim
on ○ during PLACEMENT — acting on a unit there really does mean *deploy it*. What had no defence
was gating **inspection** behind the same predicate: looking at a unit cannot conflict with a
deployment march, and refusing it for the whole phase is what made the screen unreachable at boot
while the hover band kept advertising the unit as interactive.

### 3. Decision — one key per intent, and the phase supplies the meaning

**Enter ACTS on the unit under the cursor. Tab INSPECTS it.** Acting varies by context; inspecting
never does. This supersedes the Decision's *"Enter means one thing: act on the unit under the
cursor"* only in what "act" resolves to, and supersedes *"the deployment march wins while it is
active … the screen is unreachable until the march ends"* outright — the march wins **○ only**.

The map-cursor table is now three rows, and none of them mention a phase:

| Cursor is on | Enter (act) | Tab (inspect) |
|---|---|---|
| a living unit | deploy it during the march; otherwise open its screen **with the START menu up** | open its screen, menu closed |
| a dead unit | nothing | nothing |
| any empty tile | nothing, deliberately — no confirm dialog | nothing |

`FormationMapHost` grows a second entry point. `_on_cursor_confirmed` is gated by `can_open`;
`_on_cursor_inspected` is gated by nothing. Both land in one `_open_for(grid_pos, acting)`, because
inspecting and acting are the same SCREEN reached with different intent — only the menu differs.

### 4. The two listeners are now a dispatch, not a race

`GPUArena` and `FormationMapHost` both listen to `cursor_confirmed`, each checking a private
predicate, with nothing guaranteeing one fires. That is structurally how a silent cell happens.
They are now **the same predicate negated** — the arena acts iff `_is_deployment_active()`, and
`can_open` is `not _is_deployment_active()` — so for any press exactly one side acts, by
construction rather than by inspection.

### 5. Start and pause are different kinds of transition, so they get different keys

ADR-0082 fused three transitions onto Tab. Two of them (Live⇄Paused) are a repeatable toggle; the
third (Deployment→Live) is a **one-way phase exit** — ADR-0082's own prose says *"'starting the
battle' is mechanically just leaving Deployment."* One key for both is why Tab had no room left to
mean anything on the map, and why the two hosts disagreed: `GPUArena` used raw Space,
`NavigatorMain` used Tab.

- **`battle_start`** — Space / pad START. One-way and idempotent: it arms the heartbeat and dumps
  unit state, neither of which a resume should redo, so pressing it on a running battle is an
  accepted no-op rather than a pause.
- **`battle_pause`** — Esc / pad SELECT. The bare flag flip, repeatable, with none of START's
  one-time arming.
- **`command_mode_toggle` is deleted.** ADR-0082's one-flag *state* model is untouched; only the
  key that drove it is split. Its three guards assert the split transitions now.

### 6. Two keysets, and the pad face buttons are left open

PC and pad are maintained as separate keysets, so the pad is not forced to mirror the keyboard.
`unit_inspect` is Tab + pad △ and `battle_start` is Space + pad START — both provisional on the pad
side. **FFT has a real answer for act-vs-inspect and it has not been read off the ROM yet**; the
mapping above is a placeholder chosen to be testable, not a claim about the original.

Note two deliberate double-bindings: Tab is `unit_inspect` on the map and `formation_start_menu`
inside the detail view, and pad START mirrors that exactly. They never contend because the map
cursor is frozen while the detail view is up and the detail view does not exist while the cursor is
live. Read as one idea at two depths: *show me more*.

Disjoint modes are a claim that has to be ENFORCED, and it was not. The coordinator claimed
`formation_start_menu` unconditionally, including while IDLE with no screen up — so on the map host
a Tab press opened a MAIN-formation menu that has no meaning over a battlefield, swallowed the
event, and `cursor_inspected` never fired. A detail-view key claimed outside the detail view is a
mode leak, and it is the second of the two engine-level collisions this amendment had to clear
before Tab could mean anything on the map.

**`ui_focus_next` / `ui_focus_prev` are cleared to take Tab back.** Tab turned out to carry a THIRD
meaning nobody had counted: Godot binds it to focus traversal by default, and the viewport GUI
consumes it *before* `_unhandled_input`, so `cursor_inspected` never fired. Worse, the traversal
then parked focus on a Control that swallowed the next Enter — one unaccounted binding took out
both keys. Nothing in this project drives keyboard focus traversal (`grep` finds no reader), and a
game with its own cursor UI has no use for it, so both actions are overridden to empty. This is the
kind of cell an audit of *our* actions could never find: the collision was with an engine default
that is not in `[input]` until you put it there.

### 7. Closing the screen no longer STARTS the battle

`pause_battle` was `func(paused): combat_active = not paused` — close the screen, the battle runs.
That was harmless only because the screen could not be opened before the battle started. Making
inspection ungated made it reachable, and the first thing the new guard found was a fight beginning
because the player looked at a unit: the deployment march would still be mid-deployment and the GPU
sim would start ticking underneath it. The same shape breaks a deliberate mid-battle pause — open
the screen while paused, close it, and you are live again.

Both hosts now CAPTURE the state on open and RESTORE it on close (`_set_screen_pause`). Pause stays
outside the recipe as this ADR decided; it just stopped assuming what it was returning to.

This is the amendment's own lesson landing on itself: a capability that was gated for a whole phase
had never had its interactions with that phase exercised, and un-gating it is what surfaced them.

### 8. Guard

`tests/CursorConfirmEndToEndTest.gd` boots `GPUArena.tscn` at its real defaults and injects
physical key events — never a signal emit, never `use_strategy_phase = false`. It pins the action
split, that **Tab opens a unit's screen during the march** (the assertion the shipped build fails),
that selecting a unit for the march **paints its tile**, that the march is transient, and that Enter
opens the screen on the far side of it.

### Deferred, still

- **The refusal flash.** Enter on a tile the march cannot use (claimed, ineligible, an enemy) is
  still silent. It is no longer a trap, because Tab now works on every one of those cells, but a
  refused *act* should say so and there is no flash mechanism to hang it on yet.
- **`_unit_at_grid` does not filter on `unit.visible`.** In march mode every unit is visible, so it
  does not bite; on the legacy teleport path `_spawn_roster_units` hides units until placed, and the
  hover could bind the pair to a unit that is not on screen.
- **A "Deploy" row on `StartActionMenu`.** Deployment stays on ○ for now. When Move and Act land
  they need the identical open-a-unit → choose-an-action → pick-a-tile → confirm shape, and
  deployment should become one more row in that machinery rather than a special case.

---

## Amendment 3 — the entry gesture ZOOMS (2026-08-21)

The Decision says the mount reconciles the authored 9.6 ortho against the map camera's 12.6 by
scaling **the UI root** by ×1.3125 and **never the camera** — *"that would zoom the map, and the
spec asks for a pan."* The user, having played it, asked for the map zoom to match the Formation
scene too, and for the exit to undo the zoom as well as the pan.

### 1. Decision — the correction stops being a mount and becomes a function the gesture walks

The pan lerps `camera.size` from 12.6 to the authored **9.6** on the **same cosine ease** as the
position — one move, not two — and the root correction rides from ×1.3125 down to **×1.0** as it
goes. That is what keeps the UI the same apparent size while the map behind it grows, and landing
on 9.6 is precisely what makes the map read at the Formation scene's own scale.

Measured over a live `GPUArena`: `12.6 / 1.3125` at boot, `9.6 / 1.0000` settled, `12.6 / 1.3125`
returned.

`FormationMapHost.AUTHORED_ORTHO_SIZE` names the 9.6 once; `mount_transform_for` already divided by
it inline.

### 2. The mark is satisfied at the END, so the delta is computed at the END size

`_body_delta_to_mark` read `_camera.size`, which was correct only because the size was constant. It
now takes the size it is aiming **at**. Left alone it would aim at the pre-zoom framing and miss the
breakout mark by the zoom ratio — a bug that would have looked like a mis-measured mark rather than
a mis-timed read.

### 3. The exit was already built, and inert

`PlayerCamera.request_takeover` has always latched `_saved_camera_size`, and `release_takeover` has
always eased `camera.size` back to it. The forward half simply never varied the size, so the whole
return path was dead code that came alive the moment it had something to return from. Nothing was
added for the reversal.

### 4. This is the gesture the clip engine said did not exist

`UI3ClipEngine.clip_basis_inv_for`'s staleness note states that the basis is a snapshot of a global
transform, that it would go stale if the screen root moved between pushes, and that this could not
bite because *"the only UI up while the camera moves is UNCLIPPED"* — closing with: *"If a future
gesture ever animates the camera with a box-opening panel on screen, that panel needs a re-push per
frame and this is the note that says so."*

A zoom is that gesture, because the re-mount moves the node that **is** the clip basis. So:
`UI3ClipEngine.refresh_basis()` rewrites **only** `clip_basis_inv`, skipping `resolved_clip_world`
and the nested-element recursion entirely — `clip_world` is a function of each element's own
aperture and nothing the camera does can change it. That is what makes it cheap enough to run every
frame of a pan.

Two honest limits: the re-mount is stepped on **menu ticks** while `release_takeover` eases on
**frames**, so the correction can lag the camera by up to one tick on the way out — invisible today
because the detail overlay is already freed by then and the only UI left is unclipped. And the
forward pan currently still runs at DETAIL entry, so nothing clipped is on screen for it either; the
re-push is what makes moving the pan to EQUIP/ABILITY entry possible at all.

### Guard

`tests/FormationMapHostTest.gd` pins **both ends** of the walk. The ×1.0 end is the one that says
the zoom TARGET is right — a target anywhere else leaves the root correcting for a mismatch that is
supposed to be gone. 9.6 is written as a **literal**, not derived from `AUTHORED_ORTHO_SIZE`, per
this repo's own lesson that a guard computing its expectation from the constant under test cannot
fail; it was confirmed red by hand before being restored.

---

## Amendment 4 — one intent per button (2026-08-21)

Amendment 2 chose **Enter ACTS / Tab INSPECTS** and defended two deliberate double-bindings as safe
because *"the modes are disjoint."* Playing it produced a report that read as a broken feature:
*"the START menu opens and its rows draw, but picking one does not get you to the sub-screen."*

### 1. It was never broken — it was a wrong key with no feedback

Driven against a live `GPUArena` with real keys: on a friendly unit `selection_is_owned` is true, no
rows are disabled, `chosen` fires, and the Equip sub-screen enters and **renders correctly**. The
key being pressed was Tab. Tab was `unit_inspect` + `formation_start_menu` and **never**
`ui_accept`, so on an open menu it fell through every branch to `_claim_pad` and was swallowed with
no buzz, no log, and no trace.

**A wrong key and a broken screen produced byte-identical feedback.** That is the actual defect, and
it is a design defect, not a coding one: two sessions were spent hunting a bug that did not exist.

### 2. Decision — the four face buttons get their documented meanings

The PlayStation face buttons were assigned meanings by their designer (Teiyu Goto): ○ and ✕ are
*correct* and *wrong*, △ is a head in profile — *viewpoint* — and □ is a sheet of paper —
*document*. Japanese-market convention, which FFT ships with, makes that ○ = confirm, ✕ = cancel.
This ADR adopts that as the model rather than inventing one:

| PSX | means | intent | key | pad |
|---|---|---|---|---|
| ○ | yes | **confirm** | Enter / KP Enter | 1 |
| ✕ | no | **back** | Backspace | 0 |
| △ | viewpoint | **look** (inspect, changes nothing) | Tab | 3 |
| □ | document | **menu** | M | 2 |
| SELECT | — | **pause** | Esc | 4 |
| START | — | **start battle** | Space | 6 |

Every key and every pad button now appears exactly once across the whole map.

### 3. What this fixes that was live

- **`ui_accept` and `ui_cancel` were Godot DEFAULTS**, which is why nobody had audited them. Defining
  them takes Space out of accept (it is `battle_start`) and Esc out of cancel (it is `battle_pause`)
  — two collisions of exactly the kind Amendment 2 spent §6 clearing, sitting in the one place an
  audit of *our* actions could not see.
- **Godot's pad defaults are Xbox-shaped** — button 0 = accept, button 1 = cancel — the exact
  inverse of ○=yes/✕=no. The repo's own explicit bindings already used 1 for confirm
  (`cursor_confirm`), so the defaults silently disagreed with the deliberate bindings beside them.
- **Tab stops meaning two things.** The menu moves to □/M. *(Amendment 6 reverses this: △/Tab carries both, as one intent at two depths.)* The IDLE guard on the map host stays, but
  its reasoning is now only the half that never depended on the collision: a map has no plain
  roster, so a MAIN-formation menu over a battlefield is a menu about nothing.

### 4. Prose could not hold this — the table is mechanized

The first draft of this amendment put MENU on **Q**, which is already
`rotate_camera_cw`. While writing the decision that removes double-bindings. A new binding that
squats on a key that already means something is invisible to review and invisible at runtime — the
loser just silently stops working, which is the *same* failure mode as the Tab bug above, one level
up.

So `FormationMapHostTest` asserts the whole table: no owned action shares a key or pad button with
another (with `ui_accept`/`cursor_confirm` admitted by name — two ACTIONS for gating reasons, one
button), and each action's bindings are pinned as literals. Confirmed red by putting MENU back on Q,
which failed on both counts.

Scoped to the ~15 actions this project defines. Godot ships ~120 built-in `ui_*` actions that
collide with each other constantly and are not ours; two of them do overlap our pad — `ui_select`
on pad 3 and `ui_colorpicker_delete_preset` on pad 2 — and both are inert here, since nothing
drives Control focus traversal (Amendment 2 cleared `ui_focus_next`/`ui_focus_prev` for that very
reason) and no game scene holds a ColorPicker. Noted rather than asserted: we cannot fix them from
here.

A dead action was removed while doing this. `select` was defined on pad 1 — the confirm button —
and read by nothing anywhere in the project. A dead action holding a live button is a trap with no
upside.

### 5. Silence is not a refusal

`_refuse()` replaces the six `else:`-branch `_claim_pad` swallows on an open list. It claims the pad
exactly as before, then plays the cue a disabled row already uses
(`SfxRouter.play_system("invalid")`) and logs the rejected event — so an unbound key is never again
indistinguishable from a broken screen.

Two deliberate exclusions. The mouse and F3 are **exempt**, not refused: they were never ours to act
on. And the four directions are excluded, because a one-axis list is not *refusing* left — it simply
has no left, and buzzing there would train the player to ignore the cue, which is the failure this
whole mechanism exists to prevent.

This partially discharges Amendment 2's deferred **"refusal flash"**: a refused *menu row* now says
so. A refused *tile* still does not — there is still no flash mechanism on the map cursor.

### 6. What this does NOT claim

The mapping is grounded in the PSX convention and in Goto's iconography, **not** in FFT's own table.
Amendment 2's admission stands: *"FFT has a real answer for act-vs-inspect and it has not been read
off the ROM yet."* `BATTLE_move_cursor_based_on_input` @ `0x8006e7c0` is recovered with the confirm
path labelled, and `docs/vitals-bar-investigation.md` documents driving the pad directly in
pcsx-redux — so this is a findable fact that has not been looked up, and it should be, before the
mapping is treated as settled.

### 7. Consequence to expect

**Esc no longer backs out of a screen; Backspace does.** Esc is `battle_pause` alone. Older screens
outside the UI3 formation stack (debug panels, the effect studio, `UICombatManager`) still close on
a raw `KEY_ESCAPE` check that bypasses `ui_cancel` entirely, so the app is not yet uniform — those
are untouched here and are their own cleanup.

---

## Amendment 5 — the camera HOLDS at DETAIL, and MOVES at the sub-screen (2026-08-21)

The Decision sequences the map gesture *"pan in, then chrome,"* and defends the order explicitly:
*"We pan anyway, before the panels open, so the pan is seen and no second camera move is ever
needed."* The user played it and reported the opposite. The reason is in the same bullet: settled
Status tiles four opaque frames across `y32..231` full width, so the unit the camera just panned to
is **behind them**. You watch a move, and then the thing you moved to is covered.

The ADR already names what does reveal it — a sub-screen *"narrows it to `x14..138`."*

### 1. Decision — split the takeover from the motion

They were one act because they were introduced together, not because they belong together:

- **DETAIL entry HOLDS.** `begin_hold()` takes the camera without moving it. The takeover is what
  freezes the tile cursor, hides the dagger and kills rotation — all of it gated on
  `camera_mode == CURSOR` — and *that* genuinely belongs at DETAIL entry: the view stops being the
  player's the moment a screen is up. The beat occupies `HOLD_TICKS` = 1; there is nothing to
  animate.
- **EQUIP/ABILITY entry MOVES.** The pan+zoom joins the EQUIP group as a **third concurrent beat**,
  so the camera travels *while* the frames narrow. The unit arrives in the space the panels open for
  it, as one gesture rather than two.

This inverts the Decision's ordering argument. It does not, however, cost what that argument was
protecting: there is still exactly **one** camera move per gesture, just later.

### 2. Why it can ride in the EQUIP group at all

Invariant 4 admits it by construction. The group's three beats declare `chrome`, `roster` and
`camera` — disjoint role sets — so they are allowed to play concurrently, and
`concurrency_conflicts` is asserted clean rather than assumed.

The map beat is appended inside the SHARED recipe builder under a `host_mode == MAP` branch, so the
roster host's EQUIP is untouched. The guard asserts **both** halves — present on the map host,
absent on the roster host — because a branch nothing checks is a branch that quietly stops
branching.

### 3. The exit reverses one level up, deliberately

The EQUIP pan beat's reverse is a **hold**, not a rewind. On this host a sub-screen back-out is a
FULL unwind (ADR-0084 RE25), so the MAP_DETAIL hold beat reverses immediately afterwards, and
`release_takeover()` eases the body **and** the ortho size home on its own cosine curve — one return
for both the pan and the zoom. Rewinding in the EQUIP beat as well would move the camera twice for
one exit.

So the exit mirrors the entry a level up: the frames widen while the camera stays put, then the
Status panels close while the camera returns.

### 4. A broken exit this uncovered

`_teardown_sub_screen` ended with `open_main_menu()` unconditionally. On the map host that opened a
MAIN-formation menu — a menu about a roster that does not exist — over the battlefield, while
leaving the camera held, the battle paused and the pad owned. The sub-screen back-out unwound the
panels and nothing else.

It now takes the map exit: replay the hold reversed, then release the pad and unpause, with the
unwind waiting for the camera exactly as the DETAIL close already did. This was live before this
amendment; the pan move is what made it visible.

### 5. This is the case Amendment 3 built for

Amendment 3 added the per-frame basis re-push and noted that the forward pan still ran at DETAIL
entry, where nothing clipped was on screen — so the re-push was not yet load-bearing. Moving the pan
into the EQUIP group is what makes it load-bearing: the camera now moves with the Status panels
**up**, which is precisely the gesture `UI3ClipEngine.clip_basis_inv_for` said did not exist.

### 6. Tracking had to outlive the beat that starts it

The first build of this froze the root correction at **×1.0458** on the way out — a camera at
`1.0458 × 9.6 = 10.04`, caught mid-return. The cause is a mismatch the ADR already documents without
drawing this conclusion: `release_takeover()` eases over its own **16 vsync frames** while the
reverse beat declares **8 menu ticks**, so the beat's last frame lands with the camera still in
flight, and a correction applied only inside the beat stops there.

The fix is to stop treating the mount as an event and treat it as what Amendment 3 already called
it — *a function the gesture walks*. `_track_moving_camera()` now runs from `_process` and compares
the live `camera.size` against the size the current mount was computed for, early-outing when they
match. In steady state that is one float comparison per frame and the clip engine is never touched;
in flight it is right on the next frame **whoever** is moving the camera and for however long. The
whole class of "the correction froze where the beat ended" goes with it.

### Measured

Over a live `GPUArena`, one round trip:

| | ortho size | root scale | camera moved |
|---|---|---|---|
| boot | 12.600 | ×1.3125 | — |
| DETAIL | 12.600 | ×1.3125 | **0.0000** |
| EQUIP | 9.600 | ×1.0000 | 3.3589 |
| back | 12.600 | ×1.3125 | — |

And the point of the whole exercise: at the EQUIP settle the selected unit's feet unproject to
**(178, 213)** against `FEET_MARK_PX` of (178, 213) — **err (0, 0)**. The unit lands on the breakout
mark, in the gap the narrowed frames open, which is what the original ordering could not deliver.

The camera returns to the tile CURSOR's world position rather than its own start (ADR-0041 — the
cursor, not a saved position, is authority on body XYZ), so a boot-time baseline caught mid-follow
differs from the return by a few units. That is the documented target, not a drift.

---

## Amendment 6 — △ lands ON the menu, and direction means direction (2026-08-21)

Amendment 4 mapped the four face buttons but got the *depth* wrong. It kept Amendment 2's split —
△ opens the unit's screen **menu-closed**, ○ opens it **menu-up** — which meant reaching Item or
Ability from the △ path needed a THIRD key (□). The user's verdict on that key, having played it:
*"M is crazy. also — go into menu would be triangle - and you made that tab."*

They are right, and the reasoning is one line: **△ means "show me this unit's menus", so it should
land on the menus.** A button that opens a screen *next to* the thing it names is a button that
needs a second button.

### 1. Decision — one key, one depth deeper each press is not needed

`_on_cursor_inspected` now opens with `acting = true`. □ loses its only job and goes back to being
unbound; `formation_start_menu` folds onto **Tab / pad △**, the same binding as `unit_inspect`,
because they are the same intent reached at two depths.

The loop closes with the keys already assigned, and was measured end to end:

| press | result |
|---|---|
| △ Tab on a unit | screen opens **with its menu up** |
| ○ Enter | picks the row (Item → Equip) |
| ✕ Backspace | shuts the menu, **screen stays** — the Status read the old △ path existed for |
| △ Tab again | reopens the menu, same key |
| ✕ Backspace ×2 | leaves the screen; camera and zoom return |

### 2. ✕ is BACK. □ is the spare. That was the whole confusion

The user's draft had Backspace on □ and left ✕ unassigned — *"now I don't know what to do with x."*
Backspace was already bound to pad **✕** (button 0), which is the conventional back: ○ and ✕ are
"correct" and "wrong". Nothing had to move. □ is the button with nothing to do, and it stays that
way rather than being given a job to justify itself.

### 3. START and SELECT were already right

The user asked *"what is start... I don't know we even have a psx start button"* and separately
noted *"usually pause is a select key."* Both were already true in the bindings and neither moved:
`battle_start` = Space + pad **START** (starting the battle is what START is for) and
`battle_pause` = Esc + pad **SELECT**. Amendment 5's draft suggested moving pause to START; that
suggestion was wrong and is withdrawn.

### 4. WASD drives whatever has focus

WASD moved the map cursor but did nothing in a menu — menus read `ui_up`/`ui_down`, which were
arrows-only. So W silently did nothing on a list, which is the same silent-swallow class Amendment 4
exists to kill.

`ui_up`/`ui_down`/`ui_left`/`ui_right` now carry **arrows + WASD + d-pad**, and direction means
direction everywhere: the cursor on the map, the rows in a menu, the four ability tabs in the Learn
list. Note the d-pad had to be **re-declared**: defining a `ui_*` action in `project.godot` REPLACES
Godot's default binding, so an explicit definition silently drops pad navigation unless it says so.

`camera_up`/`camera_down`/`camera_left`/`camera_right` are misnamed and were left alone: they move
the tile **cursor** (rotated by camera facing), and `PlayerCamera` only reads them under the
free-pan debug flag.

### 5. Every shared binding is now one intent at two depths

Three pairs share a binding, each admitted **by name** in the guard, and none can contend for one
reason: while a screen is up it owns the WHOLE pad (`_claim_pad`) and marks events handled before
`TileCursor._unhandled_input` sees them.

- ○ `ui_accept` / `cursor_confirm` — confirm. Two actions because the march can refuse the cursor's
  ○ while a menu's ○ is never refusable.
- △ `unit_inspect` / `formation_start_menu` — "show me this unit's menus", on the cursor and one
  level in.
- d-pad `ui_*` / `camera_*` — direction.

The check now matches a set of admitted GROUPS rather than one pair, so a new collision still fails
even though three overlaps are legal.

### 6. Still not FFT's table

Unchanged from Amendment 4 §6: this is the PSX convention and Goto's iconography, not the ROM.
`BATTLE_move_cursor_based_on_input` @ `0x8006e7c0` is recovered with the confirm path labelled and
the pad can be driven directly in pcsx-redux. The one open question this amendment sharpens is what
FFT does with □, since we now have a genuinely spare button rather than a contested one.


## Amendment 7 — ✕ out of a sub-screen returns to the Status screen (2026-08-21)

Amendment 6's table ended `✕ Backspace ×2 | leaves the screen`. Played, that turned out to be two
presses that skip a floor. From Equip, one ✕ **unwound all the way out to the battlefield** — past
the Status screen the player had been standing on one press earlier. The user, having played it:

> *"When I hit back from the ability or item menu I want it to go to the previous state (stats page
> up + chooser menu showing), not exit and go back to the unit."*

### 1. Decision — RE25 is right about the roster and wrong about the map

ADR-0084 RE25 says *"a sub-screen back-out is a FULL unwind to the roster."* That is still exactly
right **on the roster host**, and is not amended there: the Equip screen is reached from the roster
main menu as often as from the Status screen, and the roster is where the ✕ grammar bottoms out.

The map host has no roster. Its bottom is the battlefield, and the rule as written made ✕ mean
"leave the unit" at a depth where the player meant "go back one". So on the **MAP host only**,
✕ out of `EQUIP` / `ABILITY` pops exactly one level and lands on `DETAIL` with the START menu up.

`CHANGE_JOB` is deliberately **not** included. The job wheel is a full-screen takeover that replaces
the Status panels rather than narrowing them, and committing a job change is a destination rather
than a detour. It keeps the RE25 unwind on both hosts until someone plays it and says otherwise.

The predicate is asked in exactly one place (`_sub_exit_returns_to_detail`) and read by the three
sites that must agree about which exit is happening: the stack unwind, the chrome beat's reverse
driver, and the teardown.

| press | before | after |
|---|---|---|
| ✕ from Equip/Ability | out to the battlefield | **Status screen + START menu** |
| ✕ again | — | out to the battlefield |
| ✕ from Change Job | out to the battlefield | unchanged |

### 2. Two things silently depended on the full unwind, and only one was in the handoff

**The camera.** Amendment 5 put the pan+zoom in the EQUIP group and made its reverse driver
(`_map_pan_hold_reverse`) a deliberate no-op, on the stated grounds that *"a sub-screen back-out is a
FULL unwind, so the MAP_DETAIL hold beat reverses immediately after this group and
`release_takeover()` eases both the body and the ortho size home; rewinding here as well would move
the camera twice."* This amendment **falsifies that argument**: the MAP_DETAIL beat no longer
reverses after the group, so nothing downstream brings the camera back.

**The chrome.** `DetailScene.begin_chrome_descend` documented itself as *"always a real descent (the
full-unwind exit returns to the roster, RE25), even for a path-2 entry that only HELD the chrome
forward."* Left alone, ✕ would have docked the vitals+nameplate pair onto a roster this host does
not have, on a screen that was not going anywhere.

Both were load-bearing on a sentence that is no longer true, and both fixes are the same shape: the
exit must mirror what the entry actually did on THIS host, not what it does on the other one.

### 3. The camera holds — and that makes the zoom belong to the UNIT

The falsified justification left a genuine design choice, put to the user because the cheap and the
expensive versions differ a lot: should ✕ back to Status also un-zoom?

**It should not.** The Status screen keeps the framing it was zoomed into, and the camera comes home
only on the final ✕ out of `DETAIL` (`_on_detail_closed` → MAP_DETAIL reversed →
`release_takeover()`). So there is **one takeover per visit to a unit**, released once, and the zoom
is a property of *being on this unit* rather than of *being on the sub-screen*:

```
map ──▶ DETAIL ──▶ EQUIP ──✕──▶ DETAIL ──✕──▶ map
12.6      12.6      9.6         9.6          12.6
```

`_map_pan_hold_reverse` therefore stays a no-op — for a new reason, which its docstring now records
alongside the old one, because a right answer resting on a dead argument is how the next amendment
gets it wrong.

### 4. What the return actually does, and what it must not

The roster host's teardown tail is "free the overlay, restore the roster, reopen the main menu".
Almost none of that vocabulary applies to an exit that lands back on the screen it started from:

- **not** `_restore_formation()` — it un-slides a grid this host has none of and re-shows the docked
  vitals pair, which would leave a second pair behind the overlay's own;
- **not** freeing `_detail` — it is the screen being returned to;
- **not** releasing the camera, the pad, or the pause — the player has not left the unit.

The one thing that *does* have work is the lower panel: the back-out box-CLOSED the narrow
Eqp/Ability frame on the way out, so the joint §15.19 panel is rebuilt and box-OPENED again
(`DetailScene.exit_sub_mode`, the inverse `enter_equip_mode`/`enter_ability_mode` never needed while
no back-out could land here).

### 5. Not visible to the suite, so it was played

No test covered the back-out path. `FormationMapHostTest` now pins the split — that EQUIP/ABILITY
pop one level on MAP and clear the stack on the roster host, that CHANGE_JOB still unwinds on both,
and that the predicate agrees with all three — and the round trip was driven headful over a real
`GPUArena` on a unit marched to a deployed tile.

Two guards were also found rotted by Amendment 4 and un-rotted here: `FormationCoordinatorSeamTest`
and `FormationChangeJobConfirmTest` were tapping **Escape** for ✕. `ui_cancel` has been Backspace
alone since Esc moved to SELECT/pause, so those presses reached nothing —
`FormationCoordinatorSeam` had been failing for the input map rather than for the state machine.


---

## Amendment 8 — the arena's half of the demolition, and the gambit gap it exposes (2026-09-05)

Amendment 2 deferred the `UICombatManager` demolition and shipped `combat_ui.visible = false` in its
place. That is not the same thing, and the difference is not cosmetic: the whole legacy subtree was
still **instanced, readied, processed and carried every frame** of every arena run — two roster bars
with their frames and glyph meshes, four DetailLayer menus, six ModalLayer popups — a UI nobody
could see and no input could reach, whose only remaining effect was cost.

### 1. What landed

`GPUArena` now FREES the node instead of hiding it (`_demolish_legacy_combat_ui`, first statement of
`_ready`), and everything the arena hung off it goes with it:

- the `@onready var combat_ui` binding and both `_setup_combat_ui()` call sites;
- `_setup_field_inspect()`, `_field_inspect` and `_field_inspect_window` — **already dead**, and this
  is worth stating because the deferral's own justification named field-inspect as a thing the
  demolition would take. Nothing called `_setup_field_inspect()`. It had been unreachable code, not
  a live feature, since before Amendment 2 hid its host;
- the arena's `VitalsLayoutDebugPanel` registration, which was gated on that always-null window and
  therefore never fired. The panel is not lost: `FormationScene` registers its own, and the map host
  is a `FormationScene`;
- its `RosterViewDebugPanel` registration, a pure view onto the roster bars that no longer exist here;
- `GPUArena.tscn`'s 13 `CombatUI` property overrides and the `[editable path=…/CombatUI]` marker.

Verified headful over a real `GPUArena`: the node is absent from the camera subtree, boot is
error-free, and the map host still opens the full Status screen (vitals, nameplate, stats,
Eqp/Ability panels, START menu) on △/Tab over a deployed unit.

### 2. 🔴 One thing goes dark with it and has no new home: GAMBITS

`UIGambitDisplay` (the DetailLayer readout) and `UIGambitEditor` (the ModalLayer sentence-builder)
were the only UI in the tree that could show or edit a unit's `GambitList`. The map host has no
gambit section, and `StartActionMenu.ROWS` is ROM ground truth — `Item / Ability / Change Job /
Remove Unit / Order Unit` — with no sixth row to hang one on.

This deletes nothing a player could reach: both have been unreachable since Amendment 2 hid their
host. But it closes the last door, and the arena says so out loud every boot — 13 units, 13
`has only empty gambits!` warnings. **Re-opening the gambit surface on the new screen is the
follow-on job, and it is the one place this port has no oracle to copy:** gambits are this project's
own mechanic, so root ADR-0001's authored/parsed line decides the whole design, not a §15 measurement.

### 3. 🔴 Scoped to this host, deliberately

The node arrives INHERITED from `assets/scenes/CombatCamera.tscn` — 108 scenes instance it and
`GPUCombatTestBase.gd:37` binds it by literal path — and a child of an instanced scene is **not
removable per-consumer**, which is why this is a runtime free and not a `.tscn` edit. Three
alternatives were rejected: instancing the addon's `PlayerCamera.tscn` directly reds
`check_lattice_scene` arm 1 as a new undeclared namer; a second declared mount buys an indirection
file that adds nothing; and the global demolition takes down `CombatUITest`, the documented primary
UI3 test scene. So the ADR's scoped job is still open — the node in the camera mount, `CombatUI.tscn`,
`UICombatManager`, `RosterViewDebugPanel`, and `CombatCameraMountTest`'s arm 2 — and this closes only
the arena's half of it.


---

## Amendment 9 — the docked pair repaints from the CURSOR, and the enemy screen finishes landing (2026-09-05)

Amendment 8 removed the legacy `CombatUI` and left this screen as the arena's only UI. Playing it
that way surfaced two defects the old UI had been masking. Neither was caused by the demolition —
both have been true since this ADR landed — and the user reported them together:

> *"1) the vitals + nameplate UI should also show up for enemy units, not just friendly units.
> However — when in the menus all you can do is look. So it's inspect only.*
>
> *2) When I move my map cursor over a friendly unit, press Tab, and then push Backspace, suddenly
> the vitals+nameplate go to Ramza. They should go back to whoever the map cursor is over."*

### 1. The pair snapped to Ramza because the map host inherited a GRID question

The Decision's §"SELECTION inverts" names two questions this host re-answers: *who is selected*
(`selected_character`) and *where the selected unit must end up* (`selected_unit_screen_center`).
There is a **third**, and it was missed: *repaint the pair for the selection*
(`FormationScene._update_vitals_for_selection`). The inherited one reads

```gdscript
var index := selected_cell.y * COLS + selected_cell.x
var character = _roster_characters()[index]
```

and this host owns no grid and never writes `selected_cell`, so the index was a constant `0` —
the first owned unit, which at Gariland is Ramza.

It stayed invisible because nothing on the way IN reaches it: hover and open both repaint through
`_push_pair_views`. The way OUT does. `FormationDetailTransition._on_detail_closed` →
`_restore_formation()` → `refresh_selection_readouts()` is the final-✕-out-of-`DETAIL` tail, so
every close of a unit's screen repainted the pair with Ramza while the cursor stood over somebody
else.

**The map host overrides it and repaints from `_hovered`** — what the cursor is over *now*, which is
the user's own statement of the fix — falling back to `_selected` when nothing is hovered, and never
to a cell. `_push_pair_views` is already this host's repaint primitive and re-reads both views, so
the inherited method's stated reason survives intact: a sub-screen can MUTATE the unit (a Change-Job
commit recomputes HP/MP), and the pair is re-read rather than merely re-shown.

**This does not touch Amendment 7 §4.** That amendment rules `_restore_formation()` out of the
*sub-screen* back-out (`_return_sub_screen_to_detail`), and it still is not called there. The tail
corrected here is the other one — the final ✕ out of `DETAIL`, where `_restore_formation()` is
called and always was. What changed is what one of its steps means on this host, not which host
calls it.

### 2. The enemy screen: the read-only half was built, and the RESOLUTION half was not

The Decision already rules this — *"Enemies get the symmetrical screen, read-only … the START
menu's action rows are disabled, not hidden"* — and half of it was shipped:
`FormationDetailTransition._apply_ownership` calls
`StartActionMenu.set_all_rows_disabled(not _formation.selection_is_owned())` on both menu-open
paths. That code has been correct and unreachable.

Unreachable because the unit never resolved. `FormationMapHost.character_for_unit` returned `null`
for every enemy, and on this host a `null` is indistinguishable from an empty tile — no hover pair,
no nameplate, and no way to press △ at all. The cause is not in `ui3/`: it is the population
`character_for_unit` resolves against, and it is ruled in **ADR-0180 Amendment 2**, written with
this one.

With that fixed the clause lands with no further UI work. Verified headful over a real `GPUArena` at
Gariland, driving the production signal path (`cursor_rig.seed_from_map` → `cursor_inspected`):
hovering a team-1 Squire docks the vitals + nameplate pair over the map; △ opens the full Status
screen — portrait, HP/MP, Move/Jump/Speed, Weap.Power, the Eqp and Ability panels — and the START
menu opens with **all five rows painted in the ROM's disabled ramp**. ✕ closes it and the pair stays
on the Squire.

### 3. What the suite could and could not have caught

`FormationMapHostTest` had an arm for exactly this ownership question, and it passed through the
defect, because its fixture built an "ENTD enemy" by REGISTERING a Character and leaving it out of
the owned overlay. Every real ENTD enemy fails one step earlier — it is not in the catalogue at all
— so the fixture asserted a case the production path never reaches. Two arms are added beside it:

- an ENTD generic (empty slug, uncatalogued) and an unregistered named unit (Delita's shape) each
  resolve to the Character they were built from, and neither reads as owned;
- the docked pair repaints from the cursor, with the fixture deliberately hovering the unit at owned
  position **1** so an implementation still reading cell 0 paints a different name.

Both were confirmed RED against the pre-fix source before being trusted.
