# Battlefield camera

The vocabulary for how the camera frames the battlefield and what the player
input aims at. The `PlayerCamera` orbital rig and the `CinematicManager`
takeover already exist (see [Combat-visual](02-combat-buffer-layout.md)); the new
vocabulary below names the missing logical "what is the camera looking at"
device. This section will grow as the camera-mode taxonomy, follow rules, and
input bindings are resolved.

**Tile cursor**:
The persistent on-grid device that names which map tile the player is currently
aimed at — the **camera-target abstraction** the `PlayerCamera` rig pans to
follow in normal play. Moves discretely tile-to-tile (no free-pan), so it
cannot leave the playable area; the camera follows along, which is what makes
the battlefield camera "lock to the map" in retro FFT-style play. Owns the
**active tile** as its sole derived property (`tile_cursor.active_tile -> Tile`),
the shorthand for the tile under the cursor right now. Designed as a
camera-target abstraction *only*: it does **not** carry selection, hover, or
ability-targeting semantics — those live in LISTENERS on the cursor's two signals
(`cursor_moved` / `cursor_confirmed`), never on the cursor itself. Both signals
exist as of ADR-0137, joined by a third in Amendment 2:
`cursor_confirmed(grid_pos, tile)` states that the player **acted** on the tile the
cursor names and nothing more — not whether a unit is there, whose it is, or what
acting means. The **scene** supplies what acting IS, and it may have more than one
answer: in `GambitBattle` a confirm latches a unit or opens the
[deployment picker](12-strategy-phase.md) while deploying, and commits the turn once
the battle runs; in `GPUArena` it has exactly one, the
[map host](32-formation-screen-hosting.md)'s *"open this unit's screen with its action
menu"*. Where two listeners do share the signal they must share **one predicate,
negated** (`can_open` against the scene's own gate), so exactly one fires per press —
a DISPATCH, not a race. `cursor_inspected(grid_pos, tile)` is its passive twin: the
player asked to **look**, which nothing has grounds to refuse, so it is gated by
nothing. Acting varies with context; inspecting never does — that is the whole
reason they are two signals and not one with a mode flag. Both ride dedicated input
actions rather than `ui_accept`, whose Godot default carries **Space** — which on
the battlefield starts the battle. **Structural shape**: a scene-root **sibling node**,
peer to `PlayerCamera` / `CombatLoop` / `ProceduralMap`, never nested under any
of them. Owns its own position state (`active_tile`, `grid_pos`), its own
highlight sprite child, its own input handling (consumes the cursor-move
actions while cursor mode is the camera's mode), and clamping-to-grid against
`TerrainIndex`. **Pushes signals only**: it holds no references to its
consumers — the camera, the audio router, future selection layers all
`signal.connect` from the host scene; the cursor doesn't know who's listening.
That is the operational meaning of *"manipulator-of-other-things, outside of
everything"*: central in the **signal graph**, peripheral in the **ownership
graph**. Distinct from three existing "cursor" terms in this glossary: not the
**phase cursor** (effect-orchestration frame pointer — different domain), not
the UI3 layout cursor (`cursor.x += child_width` inside layout containers —
different domain), and not the FFT **box selection cursor** graphic the
[Battle range-overlay tile](01-asset-extraction.md) entry disclaims (a renderable
yellow-palette artifact whose FFT meaning was explicitly not carried over).
The render artifact for "the active tile is highlighted" is a separate concept
(a future **Tile cursor highlight**) and is not what this entry names — this
is the **logical position**, the highlight is one possible rendering of it.
_Avoid_: using "cursor" unqualified (collides with the three other meanings —
always say *tile cursor* in code/docs); calling the active tile itself "the
cursor" (the cursor is the device, the active tile is what it points at);
promising selection / targeting / hover semantics on this entry (deliberate
non-goals — those are scoped to a future extension that consumes the cursor's
signals); conflating it with the retired mouse-driven `tile_hovered` of the strategy phase
(that was ephemeral and strategy-phase-only; the tile cursor is persistent,
input-agnostic, and shipping-build-grade);
parenting it under `PlayerCamera` or `CombatLoop` (the ownership inversion
that retires the "outside of everything" invariant — every consumer would
then have to traverse through its parent to reach it, re-introducing the
coupling the signal-graph shape exists to prevent); giving the cursor
references to its consumers (push-only via signals — a `cursor.camera =`
field is the same coupling in the other direction).

**Cursor mode**:
The default `PlayerCamera.CameraMode` state. The [Tile cursor](29-battlefield-camera.md)
drives where the camera looks — cursor moves, the camera body eases to the new
active tile's centroid, Q/E rotates around the cursor. Player input acts on
the cursor, never on the camera body directly. The camera holds **no policy**
for what happens at the map edge: the cursor refuses to leave the grid, and
the camera follows whatever the cursor does. This is the retro-FFT invariant
("camera locked to the map") expressed as a layering rule, not as a clamp on
the camera itself.
**Cursor input axes are camera-relative**: pressing the visual-right cursor
action moves the cursor to whatever world neighbor is *visually* right on
screen, not to a fixed world axis. The world-direction-for-screen-direction
lookup is keyed by `CameraRelativeRenderer.get_camera_quadrant()` (0–3, the
same quadrant value `Unit.gd` already consumes for sprite-facing variants —
shared mental model, single source of truth for "what direction is the camera
facing"). Cursor movement is **discrete + key-repeat** (one tile per press,
held-key auto-repeats at a configured rate) and **un-throttled by camera
follow** — the cursor's logical position updates immediately on press; the
camera lerps to catch up and can lag arbitrarily many tiles behind when the
player key-mashes. The cursor never waits on the camera. When Q/E rotates the
camera, the quadrant value that cursor input consults **snaps on the rotation
key-press**, not at the 45° midpoint of the camera's lerp — controls remap
instantly to the player's intent, even though the camera takes ~16 frames to
visually catch up.
**Vertical framing datum**: the body the camera follows does **not** project to
the middle of the screen. FFT frames its optical centre at native-Y **160** of a
256×240 frame, 40 px below the midpoint 120 — the GTE translation decomposes as
`TR = −R·work_position + (256, 160, 640)`, so the aim point lands at (128, 160).
`PlayerCamera` reproduces it by sliding the `Camera3D` **up its own local Y**
inside the rotated `FocusPoint`, by `(vertical_datum_px / 240) · camera.size`, so
the shift is a screen-space one that survives yaw, pitch and zoom exactly like the
GTE's post-rotation `TR`. **Never as a world-space offset** — a constant world
nudge projects to a screen shift that rotates with the camera, so one tuned value
is wrong at every other pose ([ADR-0057](../adr/0057-psx-spatial-transforms-sort-into-three-classes-placement-orientation-render.md);
the cinematic rig tried and deleted one). The magnitude has ONE home,
`ExMateriaPlatform.DisplayPort.VERTICAL_DATUM_PX`, which
`src/scenarios/ScenarioCameraDirector.gd` reads too — the two rigs frame the same
tile, and before this they framed it 40 px apart. Live-tunable as
`camera.vertical_datum_px` (Camera tab → "Framing"); **0 is the A/B control**,
putting the framed tile back on the viewport midpoint. The datum stands down to
zero under `TAKEOVER`, because the cinematic director bakes the same shift into
the pose it hands `apply_takeover()`, and eases back in over the return.
Gate: `tests/PlayerCameraVerticalDatumTest`. Vault: [[Scenario Camera Framing]].

**Camera follow / rotation rules**: the WASD-walk path and the Q/E rotation
path treat the camera body differently — they are NOT the same lerp re-fired.
- **WASD walk** goes through a **deadzone scroll box** (a screen-aligned
  rectangle, default 50% × 40% of the viewport, sized in the camera's
  own right/up basis so it stays a screen-aligned box across yaw and pitch).
  It is centred on the **framed row**, not on the middle of the screen, so it
  rides the datum above — which is also why its height is clamped to the room
  that framing leaves underneath (at datum 40, `deadzone_height` past ~0.66
  would hang the box's lower edge off-screen, where the cursor can never reach
  it and the camera would stop scrolling down at all). `deadzone_box_screen_rect()`
  is the one description of the box; `DeadzoneBoxOverlay` draws what it returns
  rather than re-deriving a centred rectangle.
  As the cursor walks, the body holds still while the cursor stays inside the
  box; once the cursor would project outside, the body scrolls just enough to
  bring it back to the box edge. This is the retro-FFT "camera holds, then
  catches up" feel, and it is implemented as `PlayerCamera.track_cursor(...)`,
  driven from `TileCursor.cursor_moved`. Body XYZ lerp is full (the body rises
  with the cursor walking up a ramp). Box size is tunable live from the
  Camera tab.
- **Q/E rotation** bypasses the deadzone entirely and **recenters the body on
  the cursor's tile** every press, via `follow_cursor(_last_tracked_tile)` —
  matching FFT's "rotate and pan-to-cursor" behavior. The recenter is decoupled
  from the rotation lerp's full settle: it fires at a **kickoff threshold**
  (default ~3° remaining), so the body translation overlaps the rotation's
  slow asymptotic tail instead of waiting for it. An optional concurrent mode
  (`rotation_concurrent_translate`, Camera-tab toggle) fires the recenter at
  press time instead — useful for comparing feels. The rotation lerp itself
  is the **simpler path** than free-pan rotation: `y_target_rot += 90 *
  direction` + standard lerp, with **no raycast, no pivot teleport, no pivot
  lock** — the body is already where cursor-follow has it. The raycast pivot
  machinery (`_get_terrain_pivot` + Y=0 plane fallback + nearest-tile snap)
  is **free-pan-only** and stays gated on the debug override.
The F-key high/low pitch toggle (ANGLE_HIGH ↔ ANGLE_LOW) is unchanged in
cursor mode — pitch is independent of yaw and translation. Both the rotation
lerp speed (`rot_speed`) and the translation ease duration
(`follow_ease_frames`) are live-tunable from the Camera-tab "Speeds" knobs.
_Avoid_: routing WASD / cursor-pad input through `PlayerCamera` while in
cursor mode (input is the cursor's, not the camera's — the camera reacts via
the `cursor_moved` signal, not via shared input actions); putting a
"camera-pan-clamp" on `PlayerCamera` for the map-edge case (the cursor's
grid-clamp already covers it; a second clamp on the camera would be a parallel
source of truth).

**Cursor bob**:
The periodic oscillation a cursor sprite plays at rest, driven by a **ROM
step table** rather than a math curve. Faithful to FFT: the offset is read
from a table the original game ships, not synthesized as a sine. Two distinct
encodings exist, and they are **not interchangeable** — name the cursor when
you say "bob":
- **Tile-cursor bob** (the on-grid knife/dagger): a *vertical* bob from a
  pair of parallel 8-entry tables — an **offset table** (`{0,1,2,3,5,3,2,1}`,
  in FFT units where 1 tile = 28) and a **hold table** (frames to dwell on
  each step, `{16,8,2,2,6,4,4,10}`). One **phase index** (0–7) walks the
  steps; a per-step **frame accumulator** advances it. The motion is
  **one-sided from the resting pose** (dwells 16 frames at offset 0, excursion
  to 5, returns) — *not* a centered sine. Source: BATTLE.BIN `FUN_8007e304`,
  tables at `0x80067798` (offset) / `0x800677b8` (hold).
- **Glove-cursor bob** (the menu/world hand cursor): a *horizontal* bob from
  a different encoding of `[threshold, offset]` byte-pairs,
  0-terminated, indexed by a **modulo timer**, with a separate **idle** and
  **select** table. Offsets are *signed* (can go negative). Source: WORLD.BIN
  `FUN_8007ec504`-family, tables at `0x80156352` (idle) / `0x80156362`
  (select).
Since extraction #3 pass 4 the two encodings are **two classes reading two
assets**, one per owning system — `TileCursorBob` (`Battlefield`,
`assets/sprites/tile_knife.json`) and `GloveCursorBob` (`UI`,
`assets/sprites/glove_cursor.json`), both still generated by the one
`tools/parse_cursor_bob.py` because the ROM is one source. They were a single
`CursorBob` class over a single `cursor_bob.json` until then, which is why the
rule above had to be written as a warning rather than as a type.
The bob amount converts to Godot world units with the repo-wide
`PSX_SCALE = 1/28` (1 tile = 1 Godot unit). The **tick rate** is modelled as
a fixed `VBLANK_HZ = 60` (the NTSC field clock — hardware truth) divided by a
**`vblanks_per_tick`** integer (the per-frame skip), so effective rate =
`60 / vblanks_per_tick`. Normal play is **N = 1 (60 Hz, +1/frame)** —
established statically: BATTLE.BIN's frame pacing (`FUN_80093a98` →
`FUN_8001dba8`) passes 0 to the vblank wait when the global animation speed
`DAT_80045980 == 1`, i.e. no frame-skip. The ROM's own fast-forward
(`DAT_80045980 == 2`) waits 2–4 vblanks with a +2 increment, confirming the
divider mechanism. `vblanks_per_tick` stays debug-tunable for a hardware
capture to lock against (one full cycle = exactly 52 ticks).
_Avoid_: calling it "float", "hover", or "wobble" (reserve **bob** for the
ROM-table oscillation; "hover height" is the *resting* offset, a separate
constant); modelling it as a sine/`sin(t)` (the retired pre-faithful
implementation — the table IS the amplitude and the timing); saying "the bob
table" unqualified (there are four — tile offset, tile hold, glove idle,
glove select); conflating the tile-cursor's hold-count timing with the
glove-cursor's cumulative-threshold + modulo timing.

**Takeover mode**:
The `PlayerCamera.CameraMode` state entered when an external subsystem
requests camera control via `request_takeover(driver)`. The driver writes
pos/rot/ortho-size each frame via `apply_takeover(pos, rot, ortho_size)` until
it calls `release_takeover()`, at which point the camera smoothly returns to
[Cursor mode](29-battlefield-camera.md) (the existing 16-frame cosine ease in
`PlayerCamera._process` is reused). **On release, the camera body lerps toward the cursor's last pushed world
position** (`_follow_target`, delivered by `cursor_moved` — the camera never
reads the cursor) — the [Tile cursor](29-battlefield-camera.md) is the sole
authority on camera body XYZ, so the return lands on the player's aim rather
than on a saved pre-takeover position. Yaw / pitch / ortho-size restore from
the camera's own saved state (the cursor has no opinion about angle or zoom).
`_saved_global_pos` survives *only* as the no-cursor fallback: hosts that never
instantiate a cursor (the takeover test scenes) would otherwise be stranded at
the cinematic's final pose. See [ADR-0041](../adr/0041-tile-cursor-is-authoritative-on-camera-body-position.md) dec. 2.
`PlayerCamera` emits a `camera_mode_changed(new_mode)` signal on every
transition; the cursor connects to it to hide its sprite + gate its input
handler on `TAKEOVER` (the cursor's input handler early-returns when
`camera_mode != CURSOR`). Two live drivers today: `CinematicManager`
(per-cast cinematic-spell stage takeover, the original caller — see ADR-0037
addendum and [Combat-visual](02-combat-buffer-layout.md)) and `EffectViewerScene`
(the effect-inspector tool driving the camera from authored animation
curves — *not* a cinematic). Future borrowers — death cinematics, victory
zoom, AoE preview pans — fit by the same borrow/return contract without
further naming work. The mode replaces the retired `CameraMode.EFFECT`
(overloaded with the dozen "Effect"-named systems in this repo, and naming
the *thing being shown* instead of the *relationship*) and the API verbs
`enter_effect_mode` / `apply_effect_camera` / `exit_effect_mode` (replaced by
`request_takeover` / `apply_takeover` / `release_takeover`, which read as a
borrow contract).
_Avoid_: calling this "Effect mode" / "Cinematic mode" / "Override mode"
(EFFECT is the retired name; CINEMATIC is too narrow — EffectViewer isn't
one, AoE-preview wouldn't be; OVERRIDE collides with Godot's method/property
override vocabulary); adding new modes for each new borrower (a death
cinematic and a victory zoom both `request_takeover` — they're the same mode
with different drivers); writing pos/rot/size to `PlayerCamera` from outside
without going through `request_takeover` first (the mode gate is what stops
the cursor-follow loop from fighting the driver).

**Free-pan**:
A `PlayerCamera.free_camera()` gate (slug `camera.free_camera_enabled`, owned by
`PlayerCamera` since #500 — ADR-0140 dec. 5) that, while true, overrides the
cursor-mode input handler — WASD/arrows pan the camera body directly (the
pre-tile-cursor behavior), Q/E rotates the body around a screen-center
raycast pivot (the existing `_get_terrain_pivot` path with its Y=0 plane
fallback + nearest-tile snap). **Not a `CameraMode`**: the camera is still
logically in [Cursor mode](29-battlefield-camera.md); the flag swaps the input
dispatch behind that mode. The [Tile cursor](29-battlefield-camera.md)'s position
is preserved while free-pan is active (sprite stays put on its last active
tile; the camera no longer follows it); turning the flag back off snaps the
camera back to follow the cursor at its preserved position. Lives alongside
the other `DebugConfig` flags (e.g. `camera_debug_enabled`) and is toggled
through the F3 debug overlay.
_Avoid_: promoting this to a third `CameraMode` enum value (re-introduces
the three-mode taxonomy this design retired — debug toggle stays at a
different layer); coupling to player-facing settings (it's a debug knob; if
free-pan ever ships to players, the promotion is a one-line change deferred
until the need is real); allowing free-pan during [Takeover mode](29-battlefield-camera.md)
(the takeover driver is writing the camera every frame — debug input must not
race it; gate the override on `camera_mode == CURSOR`).

#### Extraction #3 translation table (`Battlefield`)

Loop pass 4 of extraction #3 ([ADR-0159](../adr/0159-platform-is-not-a-leaf-and-battlefields-seam-waits-on-inverting-it.md),
[#551](https://github.com/timbermania/fft-monorepo/issues/551)). Old term → new,
kept for a reader who knows the old vocabulary. Rows marked **(predicted)**
describe the seam as designed at loop pass 3; loop pass 9 checks them, so read
them as a plan until then.

| you may have read | say now | why |
|---|---|---|
| `CursorBob` | **`TileCursorBob`** (`Battlefield`) and **`GloveCursorBob`** (`UI`) | dec. 4 as amended. The two halves share no function, no reader and no consumer; the single name forced `UI` to reach 31 lines into `Battlefield` for a table `Battlefield` does not use. The rule was already in this file — *name the cursor when you say "bob"* — it just had no type to hang on |
| `assets/sprites/cursor_bob.json` | **`tile_knife.json`** (`Battlefield`) + **`glove_cursor.json`** (`UI`) | the class split alone would have left both systems naming one `res://` path — **a duplication no instrument scores**, because each system still shows exactly one outbound reference to an unbucketed asset. Splitting the data is what makes the seam real. One generator still writes both: the ROM is one source, so faithfulness stays single-sourced |
| *the glove bob has no consumer yet* | **six consumers**, all `src/ui3/detail/` — `DetailScene`, `StartActionMenu`, `EquipPickerMenu`, `JobPickerMenu`, `LearnAbilityMenu`, `AbilityPickerMenu` | this file and `tools/parse_cursor_bob.py` both still said "a future consumer, not built yet" while 25 call sites used it. The vocabulary was right years before the code; only the *staleness* was the defect |
| *`CursorBob` is `Battlefield`'s* | **the knife half is; the glove half never was** | ADR-0157 (pass 1) found all 31 inbound lines were the glove half. It is booked to `Battlefield` by an explicit per-file rule in `classify_blueprint.py`, not by a directory — a file booked to a system by a classifier rule, whose content belongs to its consumers |
| *the five `src/debug/` panels are `Battlefield`'s* | **they are `Debug`'s** — `CameraFeelDebugPanel`, `CursorDebugPanel`, `MapRenderDebugPanel`, `SkirtDebugPanel`, `TilesDebugPanel` | dec. 5, by the rule ADR-0068 already states: the production owner holds the tunable, the debug panel is a pure view. `MapGridOverlay` and `DeadzoneBoxOverlay` are **not** rebooked — scene-tree overlays, not registry views. **(predicted)** |
| *`Tile` stores the unit that reserved it* | **`Tile` holds an opaque claim** | dec. 6. `reserved_by: Unit` is 4 lines in `src/map/Tile.gd` with `src/units/Unit.gd` its only outside caller, on 2. `BLUEPRINT.md` §1 already has occupancy crossing *out*, and the stored type ran against its own table. **(predicted)** |
| *`platform` is a leaf* | **it is now** — `Tune.register_all()` is deleted | ADR-0159's headline (pass 3) was that it is not: the replay named 17 owners across 7 of 11 systems. ADR-0173 / [#535](https://github.com/timbermania/fft-monorepo/issues/535) removed the reach by removing the reason for it — `Tune.reset()` no longer clears the declarations, so nothing replays. `path_refs.py platform`: **13 outbound into 6 systems → 3**, all `res://config/…`. Goal #5's guard scored **zero both before and after** and is still blind to the shape; `check_tune_owner_self_registration.py` S2 is what holds it |
| *`register_all()`'s manifest is the enumeration* | **both enumerations are gone** | #551 found there were two — the manifest and `TuneRegisterAllTest.gd`'s literal 17-row mirror of it, *the act of measuring adding to the thing measured*. ADR-0173 inverted both: `tests/TuneOwnerSelfRegistrationTest.gd` DISCOVERS the owner set by walking the tree and derives each owner's slugs by calling its entry point, so it names no owner and no slug. Deleting the list without its mirror would only have moved the enumeration into `tests/`, where `classify()` is `None` for every file |
| *a test resets `Tune` and then spawns a production node* | **it wants `reset_overrides()`, not `reset()`** | ADR-0173. `reset()` is unchanged — the total slate, overrides AND declarations. `reset_overrides()` is everything except the one thing it cannot undo: a declaration's only producer is a `bind` at its use-site, and for a class-load owner that runs from `_static_init`, once per class load per process. Wanting the total slate and having no way back is the entire reason a central replay existed. Seven tests move; the other 24 `reset()` callers want registry ISOLATION and keep it (`_register` is first-write-wins) |
| *`Tune` is a port, so a `Tune` reach inside the addon is resolved* | **a port answers arm 1; arm 2 is a different question** | [ADR-0175](../adr/0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md) dec. 1. *Port* is a verdict about which BUCKET a name belongs to — it licenses a reach. A standalone-parse break is about the NAME, which only a `project.godot` `[autoload]` block creates. Both are true of the same 59 lines at once. Verified with `godot --check-only`: co-locating `Tune.gd` beside its consumer in one addon leaves **16 of 16** parse errors standing |
| *the shapes are port, sever, or accepted debt* | **re-bind · sever inward · invert outward · accepted debt** | [ADR-0175](../adr/0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md) dec. 1. The old menu names one tier verdict and two dispositions, on different axes. **Re-bind** is the shape this repo has actually shipped — `exmateria_sound` resolves both its autoloads by node path — and it is what "port" gets you *after* a `class_name` façade replaces the bare identifier |
| *the `Debug` residue has to land somewhere* | **31 of the 38 were `print` behind a switch, and they are deleted** | [ADR-0175](../adr/0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md) dec. 3, amending [ADR-0140](../adr/0140-debug-is-a-system-and-a-system-logs-itself.md) dec. 5. *Residue* names the real risk — #500 measured that severing a `DebugConfig` gate CREATES a `Tune` bind — but it presumes the output is worth keeping. Ask that first: 25 gates guarded ASCII banners, 5 were genuine warnings that became un-gated `push_warning()`, 1 survived. Deletion has no residue at all |
| *`Battlefield` publishes three autoloads* | **it publishes none** — the whole surface is `class_name`: 28 of them | [ADR-0183](../adr/0183-the-published-autoloads-were-named-from-inside-and-that-half-was-uncounted.md) dec. 1/2. ADR-0175 dec. 2's argument run backwards: an `[autoload]` line is written by the *consuming game's* `project.godot`, so publishing one asks every consumer for three install steps before the addon's own `Tile.gd` parses. 25 of the 46 moving rows already declared a `class_name` — the three autoloads were the exception, not the pattern |
| *the published surface's problem is the 21 outside reaches* | **it was the 27 reaches from INSIDE**, which no instrument counted | [ADR-0183](../adr/0183-the-published-autoloads-were-named-from-inside-and-that-half-was-uncounted.md). `autoload_reach.py` reports who names a system's autoloads *from outside*, and that direction cannot break a standalone parse. `SkirtGeometryGenerator` naming `SkirtConfig` ×10 can. Post-move arm 2 was **92, not 65**; #588 owns 65, so the other 27 were unowned. Arm 2's docstring had already sentenced them — an autoload name is created by *"a project that does not autoload it — including the addon's own"* |
| *a config autoload becomes a `class_name` singleton* | **only if it has instance state** — measure before choosing | [ADR-0183](../adr/0183-the-published-autoloads-were-named-from-inside-and-that-half-was-uncounted.md) dec. 2. `SkirtConfig` holds none (3 consts + pure `Tune` getters) and is a **static class**, joining `register_all()`'s `load()` list. `TileOverlayConfig` splits *within one class*: the tunable half static, only `changed` + `paused`/`scrub_phase` behind `of()`. `Tune.register_all()`'s own comment is the discriminator — the `/root/` list is for owners *"whose `register_tunables` reads instance state seeded in `_ready`"* |
| *a Tune-backed config façade is a type worth sharing* | **it is a pattern, not a base class** | [ADR-0183](../adr/0183-the-published-autoloads-were-named-from-inside-and-that-half-was-uncounted.md) dec. 3. `SkirtConfig` and `TileOverlayConfig` share the shape — a slug prefix, a code-default home, a debug panel that is a pure `TuneField` view (ADR-0068 R1) — and share no code, no consumer, no slug namespace and no destination directory. One is static and one extends `Node`, so they *cannot* share a base class. Two concerns |
| *`Battlefield` is `src/map/` plus scattered files* | **it is `addons/exmateria_battlefield/`, ten directories** — `cursor` 12 · `terrain` 7 · `overlay` 6 · `texturing` 5 · `camera` 4 · `assembly` 4 · `lattice` 3 · `doodad` 2 · `debug` 2 · `pathfinding` 1 | [ADR-0184](../adr/0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md), loop pass 6. 46 files and 284 `res://` references in one commit; `src/map/` no longer exists. The ~27 hand-audited per-file `Battlefield` rules in `classify_blueprint.py` collapsed into the one prefix rule #561 dec. 2 designed, which is why `docs/EXTRACTION-3-MOVE-MANIFEST.tsv` exists: after the collapse the census restates where files were PUT rather than measuring what `Battlefield` is |
| *`platform` is a bucket with no address* | **`addons/exmateria_platform/`** — `pixel_aspect` · `dither` · `fixed_point` · `display_port` | ADR-0169 dec. 1 + ADR-0171 dec. 3, built at the same pass. Four of the tier's five files; `src/core/Tune.gd` stays in the host, so the bucket sits at **two addresses** until it lands. The subdirectory names are the FACT each file encodes, not the file's name — which is what lets dec. 10 of [ADR-0129](../adr/0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md) be honoured by the address without renaming the file — it asked for `pixel_aspect` as `par`'s longer name and its trigger fired at extraction #1 without executing |
| *goal #5 is met when the addon exists* | **the address is one commit and the seam is four more** — arm 1 carries a named ten-line burn-down | ADR-0184 dec. 4. Nine of the ten are ADR-0157 dec. 2's outbound debt, enumerated by file and line *before* `Battlefield` was chosen; the extraction does not create them, it makes them visible, because arm 1 cannot see a file in `src/`. Under a strictly-green arm 1 a **split** pass 6 is not awkward but impossible — every ticket but the last has it red by construction |
| *`DebugConfig.psx_camera_angle_12bit` is the camera-angle mirror* | **`PSXDisplay.live_camera_angle`** — the platform port's, beside the five globals it already pushed | [ADR-0186](../adr/0186-the-publish-already-existed-on-the-wrong-half.md) dec. 2, building ADR-0175 dec. 4 ([#590](https://github.com/timbermania/fft-monorepo/issues/590)). It was never a debug flag: written every frame by `PlayerCamera` and read by `Unit._build_view` (`Battle`) and `CameraRelativeRenderer` (`Sprite Rig`), i.e. `Debug` hosting live camera state for two other systems. Landed on today's spelling rather than waiting for [#583](https://github.com/timbermania/fft-monorepo/issues/583)'s `DisplayCalibration` rename, which that ticket's own Ordering says blocks nothing |
| *the mirror is a workaround you could just read back* | **you cannot read it back at all** — `global_shader_parameter_get` is editor-only, unconditionally | [ADR-0186](../adr/0186-the-publish-already-existed-on-the-wrong-half.md) dec. 3. It returns `null` for a value pushed one line earlier and raises *"This function should never be used outside the editor"*. `check_addon_portability.py` arm 4 — which reads the **push** side as well as the declaration — is the only instrument that can assert who pushes a `[shader_globals]` name |
| *`cursor_moved` is the publish the SFX cue needs* | **`cursor_stepped` is** — `cursor_moved` has TWO emit sites and the cue sat below one | [ADR-0186](../adr/0186-the-publish-already-existed-on-the-wrong-half.md) dec. 4 ([#589](https://github.com/timbermania/fft-monorepo/issues/589)). The other emit is `move_to`, which host scenes call to place the cursor after a build; connecting the cue there would sound on every programmatic reposition. **A signal publishes the EVENT — "there is already a signal on the line above" is a claim about one emit site, not about the signal** |
| *the addon pushes its outputs to `Effects` and `Audio`* | **it publishes them; `BattlefieldWiring` hands them over** | [ADR-0186](../adr/0186-the-publish-already-existed-on-the-wrong-half.md) dec. 5/6 — the assembler [ADR-0134](../adr/0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md) defines as a composition that *"wires once and leaves"*. One class split by SUBJECT (`wire_map`, `wire_cursor`), booked **`assembler`** so no system's reach count moves for it — ADR-0167's severance first read as GROWTH because its class was booked to the bucket it drained. Each map seam publishes BOTH a replay and a signal: connect-only misses everything (the builder is constructed *inside* `_build_map`), drain-only goes stale (materials are lazy, per surface type, on every `rebuild_mesh`) |
| *`Battlefield`'s outbound debt is nine lines* | **the scored debt is ZERO** — `autoload_reach.py` reads `dec. 2 counts 0` | [ADR-0186](../adr/0186-the-publish-already-existed-on-the-wrong-half.md). Arm 1's burn-down is **six**, all of it the lattice (ADR-0166 dec. 2/3, ADR-0164 dec. 1/2). Goal #5's remainder is three named things: those six, 62 arm-2 lines **every one of which names a port** (#588), and four arm-4 `[shader_globals]` declarations nobody owns |
| *the port façade is a `class_name`* | **two of them** — `TunePort` and `DisplayPort` (two bare `class_name`s until ADR-0212 dec. 1 moved both onto `ExMateriaPlatform`) | [ADR-0187](../adr/0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md) dec. 1 ([#588](https://github.com/timbermania/fft-monorepo/issues/588)). There are two autoloads, and a signature that forwards both `bind` and `live_fx_stretch` is not a port, it is a namespace. Each sits beside what it fronts: `display_port/DisplayPort.gd` next to `PSXDisplay.gd`, and a new `tunables/` under the platform addon's layout rule — *the subdirectory names the FACT the file encodes* |
| *the 78 standalone-parse lines are one population* | **62 and 16** — and the 16 were free | [ADR-0187](../adr/0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md) dec. 1. `PSXDisplay.gd` lives in `addons/exmateria_platform/` and so does the façade, so re-pointing its 16 lines makes them **intra-addon**: arm 2 stops seeing them and arm 5 never counts them. The measurement is the arm-5 delta — **69 → 131, +62**, the battlefield subtotal and not the 78. Every prior statement of this ticket's size, its own re-measurement comment included, treated the 78 as one number |
| *the call sites change identifier and nothing else* | **18 of them change ARITY** | [ADR-0187](../adr/0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md) dec. 3. The ticket asserts that AND *"the fallback is total"* in the same paragraph, and a total fallback is one that gets **passed**: `TunePort.get_value(slug, fallback)`. The second claim is the true one — every one of the 18 sites already held the same constant its matching `bind` declared. `on_update` is the one verb with no honest absent answer, because it carries no literal at all, so it is a **no-op** and its 13 sites' own member defaults stand |
| *re-pointing a call site is a change to the call site* | **it is a change to every instrument that reads the NAME** | [ADR-0187](../adr/0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md) dec. 4. `materialize_tunables.py`'s `CALLS` is a hardcoded list of registration spellings and `locate_call_for_slug` reports **nothing** for one it lacks — indistinguishable from *"no literal at this line"*. 32 registration lines (24 `bind` + 8 `bind_update`) moved onto the façade and would have gone quietly unmaterializable. ADR-0148's stale-subject pattern in the one place it does not go red; ADR-0151's companion-change rule is the fix |
| *goal #5's remainder splits by LANGUAGE — a GDScript half and a shader half* | **it splits by FAILURE MODE: parse · reach · compile, and only PARSE is closed** | [ADR-0187](../adr/0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md). `check_addon_portability.py` arm 2 prints **no rows at all** and `autoload_reach.py Battlefield` reads *"dec. 2 counts 0; goal #5 answers for all 0"*. So the addon **parses** standalone, which it never has before. It still **reaches** — arm 1's six lattice lines on `ARM1_BURN_DOWN` (ADR-0166 dec. 2/3, ADR-0164 dec. 1/2) are `.gd` too, which is why *"the GDScript half is done"* is the wrong summary and why this pass's own first draft made that mistake. And its shaders still do not **compile** — the four `[shader_globals]` declarations ADR-0169's Consequences called *"pass 6's call"* — the only open QUESTION in this extraction, which three passes declined to answer and [#626](https://github.com/timbermania/fft-monorepo/issues/626) now measures: by `#include` closure the requirement is **six** names over 11 addon shaders, not four declaration lines, and `visible_angles_cull_mode` has no CPU writer anywhere |
