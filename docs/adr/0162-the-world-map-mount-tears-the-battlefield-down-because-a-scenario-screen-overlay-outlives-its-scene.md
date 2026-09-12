# The world-map mount tears the battlefield down, because a scenario screen overlay outlives its scene

Mounting the world map **frees the battle world** (`_teardown_world()`), instead
of parking it behind the map's CanvasLayer. The overlay quads a group's scene-out
leaves standing are **camera-independent by construction**, so parking the world
parks a full-screen black wall in front of the next 3D screen that mounts into it.

Status: accepted (2026-08-25) — grilled with the user; BUILT 2026-08-25. Owned by
`src/scenarios/NavigatorMain.gd` (`run_world_map`). Supersedes the standing
rationale in `WORLD_MAP_MOUNT_BLACK_SECONDS` ("`run_world_map` does NOT tear the
world down, so that quad is still up"). Neighbours ADR-0161 (the map raises
itself) and ADR-0137 (Formation re-hosts over the **battle** map as a camera
child — a different mount from this one). Guarded by
`tests/NavigatorWorldMapFormationRenderTest.gd`. Adds **Scenario screen overlay**
to `CONTEXT.md`.

## Context

Formation opened from the world map rendered as a black screen. It was reported
once, diagnosed as the inherited `_fade_rect` (`FadeLayer`, layer 100) being
un-hidden when the map's layer went invisible, and fixed by lifting that rect
around the Formation mount. **The screen was still black afterwards.**

The fix was correct and was lifting the wrong cover. Measured on the live route,
with Formation open: `_fade_rect` alpha `0.000000`, the map's CanvasLayer
`visible=false`, Formation mounted, camera current, five owned units bound — and
**113 of 61,440 sampled pixels non-black (0.2%)**. The 113 are the debug compass,
a CanvasLayer at layer 50, which draws over 3D and so escapes.

The cover was `ScenarioColorScreen`'s `ColorScreenQuad`. Group 9's last member
(scenario 12, "Gariland Fight — Ramza talking about honest lives") ends on
`{3E} Color Screen Mode 2, (0,0,0)->(255,255,255), Time 60`: a subtractive
full-screen ramp whose settled state is white, and `out = B - F` with `F` white
is black. It was still drawing: `is_drawing=true colour=(255,255,255) mode=2`.

**Every property that makes an overlay quad correct also makes it unavoidable.**
`ScenarioScreenOverlay` exists to own one fiddly recipe, and its own docstring
explains why: the vertex shader rewrites the corners straight to NDC
(`POSITION = vec4(sign(VERTEX.xy), 0.0, 1.0)`), which moves them out of the mesh's
local AABB, so every such quad must carry an oversized `custom_aabb`
(`±4096`) or the frustum culler silently drops it. Add `depth_test_disabled` and
`render_priority = 100` (ADR-0009's deliberate opt-out from the CUSTOM0 ordering
table) and the result is a mesh that **fills the screen of any camera that renders
it, from anywhere, at any zoom, over everything**. That is exactly right for a
scene-out. It is fatal for a screen that mounts a second camera into the same
`World3D`.

Which is what `Formation.tscn` is: a bare `Node3D` with its own orthographic
`Camera3D` and **zero `Control`/`CanvasLayer` nodes** — every unit, HP bar,
portrait and glyph is a `MeshInstance3D` quad. The world map never noticed the
standing quad because the map is a CanvasLayer at layer 100 and draws over all 3D.
Formation cannot.

Three facts decided the shape:

- **The reason for parking the world was circular.** The standing comment kept
  the battlefield alive *because the `{3E}` quad was providing the black backdrop*
  — and that same quad is what blacked out Formation.
- **The overlays already have a lifetime, and it is the VM's.** They are VM
  children (`ScenarioVM._make_color_screen` → `add_child`), and the VM already
  carries two family-wide sweeps: `settle_screen_effects()` resolves all of them,
  and the restart path frees all of them. Nothing new needs inventing; the
  world-map mount was simply opting out of the lifetime that machinery assumes.
- **It is not one quad.** `ScenarioScreenOverlay` has four subclasses — `{3E}`
  Color Screen, `{76}` Dark Screen, `{7D}` Show Graphic, `{91}` Show Map Title —
  and `ScenarioWeather` shares the same `CULL_AABB`. `{3E}` is only the one this
  route happens to raise. **And the battlefield geometry is standing too**:
  Formation's camera sits at `(5.12, -4.8, 10)` in the same `World3D` as
  Gariland's terrain, and does not frame it *on this map*. That is luck.

## Decision

**`run_world_map` tears the battle world down**, immediately after
`_fade_battlefield_out()` and before the map's layer joins the tree, and clears
`_battle_world_root`.

- **The teardown is invisible because the rect already holds the black.**
  `_fade_battlefield_out()` awaits its tween and returns only once
  `_fade_rect.color.a == 1.0`. So the black outlives the quad that used to supply
  it, and no teardown frame is ever shown.
- **`_battle_world_root = -1` is part of the fix, not tidiness.**
  `_teardown_world()` does not clear it and `_ensure_battle_world` trusts it —
  leaving the outgoing root set would make a later hop back to the same group skip
  its boot and play a beat against a freed world.
- **No per-overlay bookkeeping.** Freeing the VM frees all five overlays as its
  children. A sixth overlay added later is covered on the day it is written.
- **This is the console's shape.** Entering the overworld is a `WORLD.BIN` load
  (`WLDCORE` + `WORLD.BIN` + `WLDTEX` + `MUSIC_27`). The battlefield is gone, not
  parked. `WORLD_MAP_SCREEN.md` §33.7 already says Formation is a blocking
  `WORLD.BIN` call rather than a page push, which is the same statement one level
  up.

## Alternatives rejected

- **Lift the quad the way `_fade_rect` is lifted.** Proven sufficient — hiding
  `ColorScreenQuad` alone took the same frame from 0.2% to 89.1% non-black. Rejected
  because it would be the *third* cover patched one-at-a-time in one handler, it
  addresses `{3E}` only, `run_formation_view` needs its own copy, and it leaves the
  geometry bleed untouched.
- **Suspend the overlay family for the duration of the screen.** One VM-level
  call covering all five. Rejected as a save/restore dance that still parks a world
  nobody is looking at, and still leaves the terrain in Formation's frustum.
- **Give the overlays a visual layer Formation's camera excludes.** Structural and
  no save/restore. Rejected as unproven here: the repo uses no `cull_mask` today,
  and this fork overloads `render_layer` for the engine fold — Formation has 13
  `Fold.add` prims, and the orthogonality of the two would have to be demonstrated
  before it could be trusted.

## Consequences

- The world map is the first screen on this line that owns the display outright.
  A later screen that mounts 3D over a *live* scenario world (ADR-0137's camera-child
  Formation over the battle map) does **not** get this protection and must reason
  about the overlay family itself.
- **`ScenarioVM` does not stop `{6B}` BG Sounds when freed** — its `_notification`
  only closes a trace file. This is pre-existing (every `_boot_world_for` already
  frees the VM the same way), but the teardown moves the orphan window onto the map,
  where the map's own music is playing. No bg sound fires on the Gariland route, so
  it is unexercised rather than proven safe.
- A guard for this class must **render**. `NavigatorWorldMapFormationTest` is 9/9
  green through the whole defect: it asserts the two known covers are lifted, never
  samples a frame — and, decisively, **its route seeks past scenario 12**, so it
  cannot raise the quad whatever it asserts. The route is half the guard.
