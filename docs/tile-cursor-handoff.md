# Tile Cursor — Implementation Handoff

**Branch:** `import-godot-game`
**Anchor commit:** `ad0cd8cc` (CONTEXT.md updated with `Battlefield camera` section)
**Status:** Design fully grilled with the user via `/grill-with-docs`. No code written yet — this doc is the spec to land it against. **The user wants one more grill over this handoff before implementation starts.**

---

## 0. What this is

A tile-cursor camera system: a persistent on-grid device that names which tile the player is aimed at, with the camera following it. Replaces the current free-pan body behavior as the *default* camera mode; the free-pan stays as a debug-only override. Solves the "camera drifts off the map" problem at the root by making the camera's position derivative of an on-grid cursor that physically can't leave the map.

The implementation should be done by an agent who can read CONTEXT.md and follow the design decisions captured below to the letter. This is not an open-ended design brief — every load-bearing choice is locked.

---

## 1. Pre-work already on the branch

Three commits landed during the design conversation, all in `PlayerCamera.gd`:

| SHA | Title | What it does |
|---|---|---|
| `2097cb61` | feat(camera): fall back to Y=0 plane intersection when terrain raycast misses | Replaces the always-jump-to-centroid fallback with a Y=0 plane intersection. The miss path now uses the screen-center ray's hit on the Y=0 plane. |
| `6cd0708f` | feat(camera): snap missed-raycast pivot to nearest tile (use perimeter Y) | After the Y=0 hit, snaps to the **nearest tile** (by XZ distance) and uses its full XYZ as the pivot. Looking off the map → snaps to the nearest perimeter tile at its real Y. Looking through an interior gap → nearest interior tile. |
| `ad0cd8cc` | docs(context): add Battlefield camera section — tile cursor design | All glossary entries this design conversation resolved. |

**The raycast pivot chain those commits introduced (terrain → Y=0 plane → nearest tile → map center) will become free-pan-only after this handoff lands.** Cursor mode bypasses it entirely. The chain stays valid for free-pan; do not delete it.

---

## 2. Glossary entries to read FIRST

Open `godot-learning/CONTEXT.md` and read these four entries before touching code. They are the *binding* design — anything in this handoff that conflicts with the glossary is a bug in this handoff, not the glossary.

1. **Tile cursor** (Battlefield camera section)
2. **Cursor mode** (Battlefield camera section)
3. **Takeover mode** (Battlefield camera section)
4. **Free-pan** (Battlefield camera section)

Cross-reference reads:
- **Combat-visual** (Combat buffer layout section) — for the ADR-0037 freeze-axis model and why the tile cursor is NOT a combat-visual.
- **Battle range-overlay tile** (Asset extraction section) — for the texture/palette infrastructure the cursor highlight will sample from. Note the explicit disclaim that PSX color↔meaning mapping does not carry over.

---

## 3. Decisions made, in order, with the rejected alternatives and why

This is the full design tree. Every Q has an A, every A has rejected alternatives, every rejection has a reason. Do not re-litigate any of these without surfacing a *new* fact the design conversation didn't have.

### Q1: Scope of responsibility

**Decision: (A) Camera-target abstraction only.**

The tile cursor exists to drive camera position. It does **not** carry selection, hover, or ability-targeting semantics today. Its signal interface (`cursor_moved`, future `cursor_confirmed`/`cursor_cancelled`) is shaped so a future selection layer can extend it without modifying the cursor itself.

Rejected: **(B) Unified FFT-style cursor** (cursor also drives selection/targeting). Reasons: collides with existing `PlacementInputHandler` (mouse-driven, strategy-phase-only), requires a "confirm" input action not in the binding table, opens a whole player-input redesign that should not piggyback on the camera-fix thread. The user agreed (A) now, (B) as a natural extension later.

### Q2: Naming

**Decision: "Tile cursor"** (the device) + **"active tile"** (the tile it sits on, derived property).

"Cursor" alone is already overloaded with three other meanings in the glossary (phase cursor, UI3 layout cursor, FFT box-selection-cursor graphic). "Tile cursor" disambiguates against all three. The qualifier `tile` is mandatory in code and docs.

Rejected: **"Battlefield cursor"** (verbose), **"Focus tile"** (collides with `PlayerCamera`'s existing `FocusPoint` child Node3D), **"Camera anchor"** (hides the FFT-cursor lineage we wanted to honor), **"Active tile" as the noun for the device** (it's the *property*, not the thing — confusing call-site reads).

### Q3: Ownership and lifecycle

**Decision: (ii) Scene-root sibling node.** Owns its own position, sprite, input handling, and grid clamping. Emits signals only — holds **no references to consumers**. The "manipulator-of-other-things, outside of everything" shape: central in the *signal graph*, peripheral in the *ownership graph*.

Rejected:
- **(i) Child of `PlayerCamera`**: layering inversion — camera would have to know about `TerrainIndex` / `Tile` for clamping. The codebase has been careful to avoid this (see Combat-step interpreter read rule, ADR-0018).
- **(iii) Autoload singleton**: needs `TerrainIndex` access, which is per-scene; collides with the existing pattern (PlayerCamera, CombatLoop, PlacementInputHandler are all per-scene).
- A **more central manager-of-managers** shape: rejected because the signal-out pattern already achieves "central in the signal graph" without any reference-in-the-ownership-graph coupling.

Lifecycle: created by the host scene (GPUArena, GPU test scenes) in `_ready`, after the map placed its tiles. Lives as long as the scene. Does **not** join `combat_visuals` (must keep running during pause/cinematic).

### Q4: Camera mode taxonomy + default

**Decision: (α) Cursor-default, free-pan is a debug-only override.**

- `CameraMode = { CURSOR, TAKEOVER }`. Two real states.
- Free-pan is **NOT** a `CameraMode` enum value. It's `DebugConfig.free_camera_enabled`, an input-handler override that activates while CURSOR is logically the mode.

Rejected: **(β) Three peer modes** (CURSOR | FREE | EFFECT, with a player toggle). Reasons: spends design budget on a player-facing toggle that doesn't need to exist now; "or maybe even some kind of 'free camera'" in the user's prompt was a hedge, not a commitment. Promoting `free_camera_enabled` to a player-settings toggle later is a one-line change.

**Behavior during free-pan:** the tile cursor's position is preserved (sprite stays put on its last active tile; camera no longer follows it). Toggling off restores camera follow at the cursor's preserved position. **No implicit cursor moves** — the cursor doesn't follow the camera body during free-pan (option (a), rejected (b) hide-sprite-and-freeze and (c) follow-raycast).

### Q5: `EFFECT` rename

**Decision: rename to `TAKEOVER`.**

- `CameraMode.EFFECT` → `CameraMode.TAKEOVER`
- `enter_effect_mode()` → `request_takeover(driver: Node)` (driver param is for future bookkeeping/logging; do **not** route it elsewhere today)
- `apply_effect_camera(pos, rot, ortho_size)` → `apply_takeover(pos, rot, ortho_size)`
- `exit_effect_mode()` → `release_takeover()`

Why rename: "effect" is the most overloaded noun in this codebase (EffectManager, EffectInstance, EffectMultiMeshPool, EffectParticleRenderer, ExMateriaEffectSfx, effect_anim_id, effects/, assets/effects/, E###.BIN). The mode named the *thing being shown* (an Effect), not the *relationship* (camera is being driven by someone else). `CinematicManager.gd:13` already used "PlayerCamera takeover" in its own docstring — the vocabulary was already there, just not promoted.

Rejected: **CINEMATIC** (too narrow — EffectViewerScene isn't a cinematic, future AoE-preview pan wouldn't be), **OVERRIDE** (collides with Godot's method-override/property-override vocabulary), **EXTERNAL** (correct but less verby; `request_takeover` reads better than `request_external_control`), **SCRIPTED** (implies timeline-driven, forecloses interactive-but-not-cursor cases).

**Rename scope** (already audited, no surprises):
- `godot-learning/src/scenes/PlayerCamera.gd` — 4 functions, 1 enum value, 4 internal references
- `godot-learning/src/gpu/CinematicManager.gd` — 4 references + 1 docstring
- `godot-learning/src/scenes/EffectViewerScene.gd` — 8 references

### Q6: Movement model

**Decision: (α) Discrete + key-repeat. (c) No throttle on the position update.**

- One press = one tile step. Holding the key = after an initial delay (~250ms default), repeats at a rate (~10Hz default, 100ms between steps). Tunables on `DebugConfig` or a constant.
- The cursor's logical position updates **immediately** on press. The camera lerps to catch up; if the player key-mashes, the cursor can be many tiles ahead of the camera. The cursor never waits on the camera.

Rejected:
- **(β) Continuous glide** — creates a mismatch between visual cursor (between tiles) and logical cursor (snapped); audio cue and rotation pivot become ambiguous mid-glide.
- **(γ) Held-direction auto-advance keyed to camera lerp speed** — couples cursor cadence to camera lerp tuning (two knobs become one).
- **(a) No queuing / inputs ignored during catch-up** — feels unresponsive when key-mashing.
- **(b) Queue one move at a time** — adds mutable state (`pending_move`) for negligible visual gain.

### Q7: Axis frame for cursor movement

**Decision: (β) Camera-relative. (i) Quadrant snaps on rotation key-press.**

- Cursor input is screen-relative: pressing "visually right" moves the cursor to whatever world neighbor is visually right on the screen.
- The world-direction-for-screen-direction lookup is keyed by `CameraRelativeRenderer.get_camera_quadrant()` (already in the codebase, returns 0–3, used by `Unit.gd` for sprite-facing variants). Shared mental model with the sprite system.
- When Q/E rotates the camera, the quadrant value cursor input consults snaps on the rotation **key-press**, not at the 45° midpoint of the camera's lerp. Controls remap to the player's intent instantly; visual lerp catches up over ~16 frames.

Rejected:
- **(α) World-axis** (D always means +Z): violates the retro-FFT motivation, produces "I rotated and now my controls are sideways" feel.
- **(ii) Quadrant samples per-cursor-move from live `get_camera_quadrant()`** — during the 16-frame rotation lerp, two fast direction presses could produce a diagonal world path because the quadrant value flips mid-lerp.

### Q8: Camera follow and rotation in cursor mode

**Decision (A): Smooth lerp for body XYZ.**
- Camera body XYZ smoothly lerps toward `active_tile.global_position` (full XYZ, including Y — the body rises with the cursor walking up ramps).
- Default lerp duration: ~8–10 frames at 60fps (faster than the takeover-return 16-frame ease because cursor steps are 1 tile and need to feel snappy). Tunable.
- Use the same cosine ease shape as the existing takeover-return code (or simple `lerp` — implementer's call, but match feel to the existing pan smoothness).

**Decision (B): Simplified rotation in cursor mode.**
- Cursor-mode rotation is just `y_target_rot += 90 * direction; rotation_settled = false`. That's it.
- **No raycast, no pivot teleport, no `pivot_lock_time` cooldown.** The body is already where cursor-follow has it.
- The existing `_rotate_around_terrain` path (raycast → Y=0 plane → nearest-tile snap → map-center fallback) is **free-pan-only** from here on. Keep it, just don't call it from cursor mode.

**Decision (C): Concurrent independent lerps.**
- Translation lerp and rotation lerp run on independent axes simultaneously. Pressing a cursor direction and Q/E in the same frame produces a smooth glide-and-spin. No interlock needed (matches the existing `_maintain_rotation` + `_execute_translation` split in `PlayerCamera._process`).

**Decision (D): F-key pitch toggle unchanged.**
- `ANGLE_HIGH` ↔ `ANGLE_LOW` toggle (F key) still works in cursor mode. Pitch is independent of yaw and translation; cursor is unaffected.

### Q9: Takeover ↔ cursor interaction

Four sub-decisions:

**(A) Cursor accepts input only when `camera.camera_mode == CURSOR`.**
- The cursor's input handler checks the camera mode and early-returns otherwise. One line.
- The cursor knows about camera modes; the camera does not know about the cursor's input gating.

**(B) Cursor sprite hides during TAKEOVER.**
- Sprite hides the moment mode flips to TAKEOVER; restores on flip back to CURSOR. Position preserved underneath.

**(C) Cursor learns about mode changes via signal.**
- `PlayerCamera` emits `camera_mode_changed(new_mode)` on every transition.
- Cursor connects in its host scene's `_ready`. Reacts: hides sprite + gates input.
- The same signal is available for any future consumer (audio system to duck cursor-move SFX during cinematics, UI to hide tile-info panel, etc.).

**(D) On `release_takeover()`, camera body lerps toward `tile_cursor.active_tile.global_position`.**
- **Cursor is the sole authority on camera body XYZ.** The camera does NOT save its own pre-takeover position.
- Yaw, pitch, ortho-size are still saved by `PlayerCamera` and restored on release (cursor has no opinion about those).
- **The `_saved_global_pos` field on `PlayerCamera` is DELETED.** This is the ADR-worthy decision below.

### Q10: Visual representation

**Decision: (δ) Cursor owns its own sprite/mesh, sampling the shared range-overlay texture atlas.**

- TileCursor has a child `MeshInstance3D` (or `Sprite3D` — implementer's call; whichever is consistent with how the range-overlay-tile renderer handles single tile graphics today).
- That mesh's material samples the **same texture atlas** as the range-overlay-tile renderer. A UV region + palette of the existing FFT-extracted bitmap.
- Mesh positioned at `active_tile.global_position + small_y_offset` (the Y offset prevents z-fighting with the tile's own PLACEMENT overlay).
- The tile system **does not know** about cursor rendering. Tile state tracks PLACEMENT roles; the cursor mesh sits on top as a separate node. The composition is two 3D meshes at the same XZ with slightly different Y — no compositing logic, no Tile state mutation, no `PLACEMENT_CURSOR` enum addition.
- **FFT-faithful behavior:** in the original game, the yellow cursor highlight rendered *on top of* the red attack-range highlight. (δ) gets that naturally.

Rejected:
- **(α) New `PLACEMENT_CURSOR` enum type**: mixes axes — PLACEMENT_* tags tile *categories*, cursor tags transient *input state*. Forces a "what role wins" decision when the cursor lands on a PLACEMENT-tagged tile.
- **(β) Standalone sprite ignoring range-overlay infrastructure**: re-implements the shimmer/animation, parallel source of truth, the kind of drift the codebase has been careful to avoid.
- **(γ) Cursor role tracked on Tile (cursor_present: bool), composed at render time**: still couples Tile to cursor presence; the user pushed back on this and the (δ) refinement is cleaner.

**Deferred (not blocking implementation):**
- **UV coords + palette index** for the cursor highlight inside the range-overlay atlas. Until parsed from the ISO (same pattern as the existing range-overlay-tile decoding), use a **placeholder UV/palette**. The placeholder can be any visible region — even a solid color via a tinted plain `StandardMaterial3D` — to validate "the cursor renders something" while the ISO offsets get resolved.
- **Animation: shimmer vs static.** Defer. Once the mesh is in place, it's a shader uniform — play with both at the keyboard, pick later.

### Q11: Initial cursor position

**Decision: map centroid tile by default; scene-overridable via `tile_cursor.move_to(specific_tile)`.**

- TileCursor's `_ready` sets `active_tile` to the tile whose XZ is closest to the geometric centroid of all tiles (`procedural_map.get_all_tiles()`).
- Scenes that want a specific starting tile (e.g., GPUArena could pick the player-team deployment centroid) call `tile_cursor.move_to(specific_tile)` after combat setup.
- Test scenes that don't care get the centroid default. Good enough.

### Q12: Input bindings (open — needs implementer judgment)

**Not explicitly grilled.** The implementer needs to decide whether to:
- **(a)** Reuse the existing `camera_up/down/left/right` actions for cursor-move (semantic: "player intent to move the view" — interpreted by whoever has the input). PlayerCamera's WASD handler becomes free-pan-only, gated on `DebugConfig.free_camera_enabled`. Cursor's handler activates on `camera_mode == CURSOR && !free_camera_enabled`.
- **(b)** Add new `cursor_up/down/left/right` actions, leave existing ones for free-pan only. Cleaner semantically but requires editing `project.godot`.

**Recommendation: (a).** Avoid project.godot churn; the action name `camera_up` is honest about the player intent (move the view), and the binding-level abstraction is the same as in tactics games shipping today.

The `rotate_camera_cw/ccw` (Q/E) and the F-key pitch toggle remain unchanged — they apply to both cursor mode and free-pan with the behavior described in Q8.

---

## 4. Implementation plan (suggested order)

This is a suggested sequence. Each step is independently committable + verifiable.

### Step 1: Rename EFFECT → TAKEOVER (Q5)

**Files:**
- `godot-learning/src/scenes/PlayerCamera.gd`
- `godot-learning/src/gpu/CinematicManager.gd`
- `godot-learning/src/scenes/EffectViewerScene.gd`

**Changes:**
- Rename `CameraMode.EFFECT` → `CameraMode.TAKEOVER`
- Rename `enter_effect_mode()` → `request_takeover(driver: Node)` (add unused `driver` param for future bookkeeping)
- Rename `apply_effect_camera(pos, rot, ortho_size)` → `apply_takeover(pos, rot, ortho_size)`
- Rename `exit_effect_mode()` → `release_takeover()`
- Update the `CinematicManager.gd:13` docstring to use the new vocabulary

**Verify:**
- `"$GODOT" --path . --quit-after 2 res://assets/scenes/GPUArena.tscn` parses clean.
- Effect viewer still works (manual run of EffectViewerScene; verify camera enters takeover on play and exits cleanly).
- A combat test that triggers a cinematic spell (any `CinematicManager`-driven cast) still takes over the camera and returns cleanly.

**Commit shape:**
```
refactor(camera): rename EFFECT -> TAKEOVER mode and its API verbs

Renames CameraMode.EFFECT -> CameraMode.TAKEOVER and the
enter/apply/exit verbs to request/apply/release_takeover, matching
the borrow-contract relationship the mode actually models.
Pure rename — no behavior change. Prep for the tile-cursor work.
```

### Step 2: `PlayerCamera` emits `camera_mode_changed` signal (Q9 prep)

**Files:** `godot-learning/src/scenes/PlayerCamera.gd`

**Changes:**
- Add `signal camera_mode_changed(new_mode: CameraMode)`.
- Convert `camera_mode` to a setter-triggered property that emits the signal on change.

**Verify:** same parse-check + manual cinematic run; no behavior change yet.

**Commit shape:**
```
feat(camera): emit camera_mode_changed signal on every mode transition

Foundation for tile-cursor and other future consumers to react to
mode flips (hide sprite during TAKEOVER, gate input, etc.) without
polling. No consumers wired yet.
```

### Step 3: `CameraMode.CURSOR` added, `FREE` renamed (Q4)

**Files:** `godot-learning/src/scenes/PlayerCamera.gd`

**Changes:**
- Rename `CameraMode.FREE` → `CameraMode.CURSOR` in the enum + every internal reference.
- The runtime behavior is currently identical to the FREE behavior — there's no cursor yet to follow, so cursor mode just does what FREE used to do until Step 5 wires the cursor in.
- This is a temporary state; the next steps land the actual cursor behavior.

**Verify:** scenes load, camera still WASD-pans because nothing has changed semantically.

**Commit shape:**
```
refactor(camera): rename CameraMode.FREE -> CURSOR

Prep for the tile-cursor system: CURSOR is the new default mode name.
Behavior is unchanged in this commit — Step 5 will replace the
free-pan input handler with cursor-follow logic and gate the legacy
free-pan path behind DebugConfig.free_camera_enabled.
```

### Step 4: `TileCursor` node — minimal vertical slice

**Files:**
- New: `godot-learning/src/scenes/TileCursor.gd` (+ `.uid`)
- New: `godot-learning/src/scenes/TileCursor.tscn` (so it can be added to scenes via editor)
- New (eventual): `godot-learning/tests/TileCursorTest.gd` + `.tscn` — a headful test that builds a fake terrain, walks the cursor around, asserts active_tile updates and signal emission

**Shape:**
```gdscript
class_name TileCursor
extends Node3D

signal cursor_moved(active_tile: Tile)
# signal cursor_confirmed(active_tile: Tile)  # future
# signal cursor_cancelled()                   # future

@export var procedural_map_path: NodePath
@export var camera_path: NodePath

var active_tile: Tile = null
var grid_pos: Vector2i = Vector2i.ZERO

var _procedural_map: Node3D
var _terrain_index: TerrainIndex
var _camera: PlayerCamera
var _camera_renderer: CameraRelativeRenderer  # reuses Unit.gd's quadrant source

var _key_repeat_state: Dictionary = {}  # action -> {next_fire_msec, held}

# Tunables
const KEY_REPEAT_INITIAL_DELAY_MSEC: int = 250
const KEY_REPEAT_INTERVAL_MSEC: int = 100
const Y_OFFSET: float = 0.05  # cursor mesh sits this far above the tile surface

func _ready():
    # Resolve dependencies
    # Pick initial tile (centroid of get_all_tiles())
    # Build the cursor highlight mesh as a child
    # Connect camera.camera_mode_changed for sprite hide + input gate

func _input(event):
    if _camera.camera_mode != _camera.CameraMode.CURSOR:
        return
    if DebugConfig.free_camera_enabled:  # free-pan override active
        return
    # Camera-relative direction remap via _camera_renderer.get_camera_quadrant()
    # Try to move; emit cursor_moved on success

func move_to(tile: Tile) -> void:
    # Set active_tile + grid_pos + reposition mesh + emit signal

func _on_camera_mode_changed(new_mode):
    # Hide/show the highlight mesh based on mode
```

**Highlight mesh**: placeholder. A simple `MeshInstance3D` with a quad and a `StandardMaterial3D` tinted yellow (or any visible color). The real sampling from the range-overlay atlas is a follow-up after UV/palette parsing.

**Verify (this is the big verify step):**
- Add `TileCursor` to GPUArena.tscn at the scene root.
- Run GPUArena headful: cursor appears on a tile near center; WASD moves it tile-by-tile; camera-relative axis works (rotate camera with Q/E, then WASD again, confirm visual direction matches).
- Key-repeat: hold W; cursor advances after ~250ms then every ~100ms.
- Grid clamping: walk cursor to map edge; further presses do nothing.
- Hold W while pressing E (rotation): translation lerp + rotation lerp run concurrently; cursor remap snaps on E press.

**Commit shape:**
```
feat(camera): add TileCursor sibling node — minimal vertical slice

Persistent on-grid cursor that drives camera-follow in CURSOR mode.
Camera-relative input axes via CameraRelativeRenderer quadrant lookup,
discrete key-repeat (250ms initial, 100ms interval), grid-clamped via
TerrainIndex. Placeholder yellow-quad highlight; sampling the
range-overlay atlas with the real cursor UV/palette is follow-up.
Emits cursor_moved(active_tile) for consumers to subscribe to.
```

### Step 5: Wire cursor → camera follow + cursor-mode rotation (Q8)

**Files:**
- `godot-learning/src/scenes/PlayerCamera.gd`
- `godot-learning/src/scenes/TileCursor.gd` (signal connection)
- Scene host (`GPUArena.gd` etc.) — to connect `tile_cursor.cursor_moved` → `player_camera.follow_cursor(tile)`

**Changes in PlayerCamera:**
- Add `func follow_cursor(tile: Tile)`: sets a `_follow_target_position: Vector3 = tile.global_position` field; the `_process` smooth-lerp toward `_follow_target_position` runs in cursor mode (~8–10 frame ease).
- Split `_input` so that:
  - **WASD/arrows** → handle ONLY if `camera_mode == CURSOR && DebugConfig.free_camera_enabled` (i.e., free-pan path). Calls the existing `_execute_translation`.
  - **Q/E rotation** → in cursor mode, do the simplified path: `y_target_rot += 90 * direction; rotation_settled = false`. No raycast, no pivot lock, no body teleport. In free-pan (debug), keep the existing `_rotate_around_terrain` path.
  - **F-key pitch toggle** → unchanged in both modes.
- Update `release_takeover()`: instead of lerping back to `_saved_global_pos`, lerp to `tile_cursor.active_tile.global_position`. Delete the `_saved_global_pos` field. Keep `_saved_x_rot`, `_saved_y_rot`, `_saved_camera_size`.

**Cleanup:**
- The `_rotate_around_terrain` raycast pivot chain (terrain → Y=0 → nearest-tile → map-center) stays — used by free-pan. The recent commits `2097cb61` + `6cd0708f` keep their full meaning here, just only consulted when `DebugConfig.free_camera_enabled`.

**Verify:**
- Cursor mode: cursor moves → camera smoothly pans to follow. Cursor walks up a ramp → camera rises.
- Rotation: Q/E rotates around the cursor's tile (visually orbits it). Smoothness matches existing feel.
- Hold cursor-direction across a yaw rotation: visual confirms remap is instant on key-press, camera catches up.
- Trigger a cinematic spell: TAKEOVER engages, cinematic plays, release returns the camera to the cursor's tile (which hasn't moved, since input was gated).
- Toggle `DebugConfig.free_camera_enabled = true` via F3 debug overlay: cursor sprite stays put, WASD now pans the body, Q/E rotation uses the raycast pivot. Toggle off: camera snaps back to follow the cursor.

**Commit shape:**
```
feat(camera): cursor-mode camera follow + simplified rotation

In CURSOR mode the camera body smoothly lerps toward
tile_cursor.active_tile.global_position; Q/E rotation skips the
raycast pivot (cursor is the pivot). Free-pan (the legacy raycast +
WASD body-pan behavior) becomes a DebugConfig.free_camera_enabled
override that gates the input handlers. release_takeover now returns
the camera to the cursor's tile — the saved global_pos field is
retired, with the cursor as the sole authority on body XYZ.
```

### Step 6: Audio cue wire-up (cheap follow-up)

Hook `tile_cursor.cursor_moved` → `SfxRouter` to emit the `ui.cursor_move` cue (the namespace is already there at `SfxRouter.gd:13` waiting for an emitter). Small, satisfying, ~10 lines.

### Step 7: ADR (Q9 follow-up)

After Steps 1–5 are landed and tested, write `godot-learning/docs/adr/0041-tile-cursor-is-authoritative-on-camera-body-position.md` capturing the decision and its implications. Use the ADR shape that matches the existing ADRs in `docs/adr/` (see ADR-0017, ADR-0018, ADR-0037 for prior art on architectural-invariant ADRs). The ADR should:
- Cite the deletion of `_saved_global_pos` as the enforcement.
- Note that future TAKEOVER drivers do not need to save state — the cursor does.
- Reference the CONTEXT.md `Takeover mode` and `Tile cursor` entries.

### Step 8 (Deferred): Real cursor highlight UV/palette

Once someone parses the cursor UV/palette offsets out of the ISO (same pattern as the existing range-overlay-tile decoding — see the Battle range-overlay tile glossary entry for the discovery method), swap the placeholder mesh material for one that samples the range-overlay atlas with the real UV region + cursor palette index. Add a `Tile cursor highlight` glossary entry naming it formally.

### Step 9 (Deferred): Animation tuning

Decide whether the cursor highlight shimmers (using the same 15-phase barber-pole rotation as PLACEMENT_*) or stays static. Default to static if undecided.

---

## 5. Things to NOT re-litigate

These are locked. If implementation surfaces a reason to reverse, *raise the new fact* — don't quietly change the design.

- The four glossary entries (Tile cursor, Cursor mode, Takeover mode, Free-pan).
- Sibling-node ownership (not parented to PlayerCamera or CombatLoop).
- Push-signals only — TileCursor holds no references to consumers.
- Camera-relative input axes, with quadrant snap on rotation key-press.
- Discrete key-repeat with no throttle on logical position updates.
- Simplified cursor-mode rotation (no raycast, no pivot lock, no body teleport).
- Cursor is the sole authority on camera body XYZ.
- Cursor owns its own sprite/mesh; Tile system does not track cursor presence.
- Free-pan is `DebugConfig.free_camera_enabled`, not a CameraMode.

---

## 6. Open questions deferred to implementation

These are intentionally not pre-grilled. The implementer makes the call.

- **Input action naming** (Q12): reuse existing `camera_up/down/left/right` (recommended) vs new `cursor_up/down/left/right` actions. Either is defensible; recommendation is reuse.
- **Lerp tuning numbers**: cursor-follow ease duration (~8–10 frames), key-repeat delay (~250ms) and interval (~100ms). These are starting points; tune at the keyboard once it runs.
- **Highlight mesh choice**: `MeshInstance3D` vs `Sprite3D` vs reusing whatever the range-overlay-tile renderer uses. Pick whichever is most consistent with the existing tile-overlay code path you find.
- **`PlayerCamera.follow_cursor(tile)` vs camera reads `tile_cursor.active_tile` directly**: signal-driven (recommended — matches the push-only invariant) vs polling (simpler but couples). Either works; signal is cleaner.

---

## 7. Verification checklist for the implementer

Before declaring "done":

- [ ] `"$GODOT" --path . --quit-after 2 res://assets/scenes/GPUArena.tscn` exits clean (no parse errors).
- [ ] `bash godot-learning/tests/run_all_tests.sh` passes (or at least no NEW failures beyond the known RangedCombatTest flake noted in memory).
- [ ] Headful GPUArena run: cursor visible, WASD moves it tile-by-tile, camera follows smoothly, Q/E orbits the cursor.
- [ ] Camera-relative axes verified: rotate camera 90°, press W, cursor moves in screen-up direction.
- [ ] Map edge: cursor refuses to move off the grid.
- [ ] Cinematic spell: TAKEOVER engages, cinematic plays correctly, release returns camera to cursor's tile.
- [ ] Debug toggle: `DebugConfig.free_camera_enabled = true` via F3 → WASD becomes body-pan, cursor stays put. Toggle off → camera resumes following cursor.
- [ ] Audio: cursor-move plays `ui.cursor_move` cue once per logical move (if Step 6 landed).
- [ ] `_saved_global_pos` is no longer in `PlayerCamera.gd`.

---

## 8. Read-before-coding files

```
godot-learning/CONTEXT.md                        — Battlefield camera section + Combat-visual entry
godot-learning/src/scenes/PlayerCamera.gd        — current camera code; the rename + cursor wiring lands here
godot-learning/src/gpu/CinematicManager.gd       — current TAKEOVER driver
godot-learning/src/scenes/EffectViewerScene.gd   — second TAKEOVER driver (not a cinematic)
godot-learning/addons/exmateria_sprite_rig/render/CameraRelativeRenderer.gd  — get_camera_quadrant() source; the cursor reuses this
godot-learning/src/map/TerrainIndex.gd           — for cursor grid clamping (get_tile, get_all_tiles)
godot-learning/src/map/MapComposer.gd            — backward-compat shim for get_all_tiles
godot-learning/src/strategy/PlacementInputHandler.gd    — existing mouse-only tile-hover system (NOT to be modified; informs the future selection-layer extension)
godot-learning/project.godot                     — input action bindings (camera_up/down/left/right, rotate_camera_cw/ccw, F is not yet an action)
```

---

## 9. Anchor commits

```
ad0cd8cc docs(context): add Battlefield camera section — tile cursor design
6cd0708f feat(camera): snap missed-raycast pivot to nearest tile (use perimeter Y)
2097cb61 feat(camera): fall back to Y=0 plane intersection when terrain raycast misses
```

Branch: `import-godot-game`. Resume from `ad0cd8cc`.
