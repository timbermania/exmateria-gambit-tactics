# TileCursor is the sole authority on camera body XYZ

## Status

Accepted

Verified 2026-08-28 — all five decisions are built in
`addons/exmateria_battlefield/camera/PlayerCamera.gd` and
`addons/exmateria_battlefield/cursor/CursorController.gd`. Two of them ship
differently from the shape this ADR first landed (`_saved_global_pos` was
deleted and then restored as the no-cursor fallback; `request_takeover`'s param
was typed `Node` and then widened to `Object`); both stand below as they ship,
with the reversed attempts kept under **Considered options**. Dec. 1's push
path has since gained a deadzone scroll box, stated here as it runs. See
`AUDIT.tsv` and `audit-notes/0041.md`.

## Context

Before this decision, `PlayerCamera` owned its own body position on a takeover
edge: `request_takeover` captured `global_position` into `_saved_global_pos`,
and `release_takeover` lerped back to that saved pose. The camera's body
position therefore had two potential sources of truth — wherever the active
input handler placed it during normal play, and the saved pre-takeover pose the
return ease honoured. With the [Tile cursor](../context/29-battlefield-camera.md)
introduced as the persistent on-grid camera-target device, a third would appear:
the cursor's `active_tile.global_position` is the player's intent ("where am I
aimed?"), and that intent must outrank a captured snapshot of where the camera
body happened to be when a cinematic spell fired.

## Decision

1. **The TileCursor is the sole authority on camera body XYZ.** In CURSOR mode
   every body write traces back to a cursor tile pushed in on `cursor_moved`.
   `CursorController` forwards that signal to `PlayerCamera.track_cursor(tile_world)`,
   which clamps through the deadzone scroll box and calls `follow_cursor` only
   when the tile would leave the box; `follow_cursor(world_pos, snap)` is the
   direct entry, used for the seed snap and for the Q/E recenter, which re-delivers
   the last pushed tile (`_last_tracked_tile`). The camera may re-deliver a cursor
   position; it never invents one. In TAKEOVER mode the driver writes pos/rot/ortho
   via `apply_takeover(...)` until it releases; on `release_takeover` the body lerps
   toward `_follow_target` — the cursor's last pushed world position — not toward a
   saved pre-takeover XYZ. (The deadzone's own feel rules are the
   [Camera follow / rotation rules](../context/29-battlefield-camera.md), not this ADR's.)
2. **`_saved_global_pos` is not a position source while a cursor exists.** The
   field lives, but the return ease reads it only on the no-cursor path:
   ```gdscript
   var target_xyz: Vector3 = _follow_target if _follow_has_target else _saved_global_pos
   ```
   `request_takeover` still saves it; a host that instantiates a `TileCursor`
   never observes it driving the return. It exists for the takeover scenes that
   have no cursor at all (CameraSpinTest, IfritTest, MeteorCallbackTest,
   Haste2CameraTest, GPUCallbackE005Test, GPUCallbackE065Test), which would
   otherwise be stranded at the cinematic's final pose. Treat it exactly like the
   saved yaw/pitch/zoom: it is the *fallback* return target, and a review that
   proposes deleting it must produce a no-cursor return path first.
3. **Yaw, pitch, and ortho-size are still saved by `PlayerCamera`.** The cursor
   has no opinion about angle or zoom; the F-key pitch toggle, the player's
   current yaw (`y_target_rot`), and the camera's `size` are all saved at
   `request_takeover` and restored at `release_takeover`. The authority rule is
   XYZ-specific, not a wholesale rejection of saved state.
4. **TAKEOVER drivers do not learn about the cursor, and are typed `Object`.**
   A driver — `CinematicManager` today, `EffectViewerScene`, future death
   cinematics, future AoE preview pans — calls `request_takeover(self)`, writes
   pos/rot/size each frame via `apply_takeover`, and calls `release_takeover()`
   when done. It does **not** look up the cursor's position to "restore" the
   camera to; the release path's choice of `_follow_target` is `PlayerCamera`'s
   concern. The param is `driver: Object` because the live drivers sit in
   different branches of the Godot type hierarchy — `CinematicManager` extends
   `RefCounted` (the third manager `CombatLoop` composes, sibling of
   `EffectManager` / `ProjectileManager`, ADR-0018 cluster), `EffectViewerScene`
   extends `Node3D`, test drivers extend `Node3D`. `Object` is the common
   ancestor and still a real constraint (it rejects primitives), so a future
   driver that is a `Resource`, an autoload `Node`, or a `RefCounted` manager all
   pass identically. Do not tighten it back to `Node`.
5. **The cursor is signal-source for the camera; the camera holds no cursor
   reference.** `_follow_target` is pushed in from `cursor_moved`. `PlayerCamera`
   does not `get_node` the cursor and does not poll it. The cursor's "outside of
   everything" invariant ([Tile cursor](../context/29-battlefield-camera.md)
   glossary entry) stays intact.

## Considered options

- **Delete `_saved_global_pos` outright** — shipped, then reversed. The intent
  was enforcement: with no field to hold an XYZ guess, a contributor who wanted
  one had to confront the cursor as the authority first. It regressed every
  takeover scene without a cursor, because the return then lerped toward an unset
  `_follow_target`. This ADR's first Consequences list had promised those scenes
  would "fall back to lerping toward the camera's own pre-takeover XYZ" — but
  `_return_from_pos` is captured *at release time*, which is the cinematic's
  final pose, not the pre-takeover one. Dec. 2 is what survived.
- **`request_takeover(driver: Node)`** — shipped, then reversed. It read as "the
  driver should be a scene-tree thing," and bombed the first time a cinematic
  spell fired in `GPUArena`: `CinematicManager._on_camera_started` calls
  `player_camera.request_takeover(self)` with a `RefCounted` self, Godot rejected
  the call, no takeover happened, and the cinematic ran with the strategy-view
  camera still active.
- **A saved-pose return with the cursor as a hint** — rejected. Two sources of
  truth for one value is the problem this ADR exists to remove; a hint that loses
  to a snapshot is not an authority.

## Consequences

- The enforcement of the [Takeover mode](../context/29-battlefield-camera.md)
  `Avoid` clauses is the mode gate, not the absence of a field: drivers cannot
  write the body outside `request_takeover`, and the saved XYZ they do cause to be
  captured is unreachable whenever a cursor has pushed. A driver that wants the
  old saved-pos coupling would have to make `_follow_has_target` false, which no
  driver can do.
- Future borrowers — death cinematics, victory zooms, AoE preview pans — are free
  to write the camera anywhere during their takeover. On release the camera
  returns to the cursor; the driver never authors that path.
- The seed snap is part of the contract and belongs to `CursorController`:
  `seed_from_map()` moves the cursor, then calls `follow_cursor(tile.global_position, true)`
  so a fresh seed (and every map-change re-seed) hard-cuts onto the tile instead
  of sliding in from the old focus. Host scenes choose *when* to seed; they no
  longer hand-wire the follow.
- If a host never instantiates a cursor, the body stays wherever the scene placed
  it, `_follow_has_target` stays false, the per-frame follow ease is a no-op, and
  the return path uses dec. 2's fallback. The cursor is the authority *when it
  exists*; its absence isn't an error.
- The rotation-pivot policy is a corollary. Q/E in cursor mode does **not** call
  the `_get_terrain_pivot` raycast chain (terrain → Y=0 plane → nearest tile →
  map center): the body is already on the cursor's tile, so there is no pivot to
  recompute. `_rotate_yaw` enforces this — the raycast path (`_rotate_around_terrain`)
  runs only behind the `free_camera()` debug override, where the body's XYZ is not
  anchored to anything.

## Verification

- `tests/TileCursorIntegrationTest.gd` — `cursor_moved` reaches the camera and
  sets `_follow_has_target`.
- `tests/TileCursorTakeoverTest.gd` — the full CURSOR → takeover → release edge
  *with* a cursor present: the body returns toward the cursor's last-known
  position.
- `tests/CameraSpinTest.gd`, `IfritTest.gd`, `MeteorCallbackTest.gd`,
  `Haste2CameraTest.gd`, `GPUCallbackE005Test.gd`, `GPUCallbackE065Test.gd` —
  takeover *without* a cursor; these are what dec. 2's fallback exists for.
- `tests/EffectStudioCameraOwnershipTest.gd` — a takeover driver that never
  consults the cursor.

No guard asserts the negative in dec. 5 (that `PlayerCamera` holds no cursor
reference); see `AUDIT.tsv`.
