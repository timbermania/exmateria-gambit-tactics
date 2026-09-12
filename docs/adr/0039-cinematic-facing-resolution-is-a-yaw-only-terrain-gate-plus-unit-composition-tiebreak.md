# Cinematic facing resolution is a yaw-only terrain gate plus a unit-composition tie-break

When the effect camera frames a unit during a cinematic, it picks its base
**yaw** by a layered rule: a **terrain-visibility gate** chooses which of the
4 fixed yaws keep the focused unit unhidden by map geometry, then a
**foreground-composition tie-break** (fewest occluding units → most-foreground
→ minimal rotation) picks among the survivors. Only **yaw** is resolved —
pitch and zoom stay whatever the effect authored. The gate mirrors the ROM's
`calc_facing_angles`; the composition tie-break is a deliberate **addition**
the ROM does not have. See
[Cinematic facing resolution](../context/15-effect-orchestration.md).

## Status

accepted

## Context

The real game freezes the action when an ability fires and moves the camera to
frame the acting/target unit. We want the same — and specifically we do not
want to play a cinematic where the unit is hidden behind a cliff.

We confirmed the ROM behavior in the disassembly. `calc_facing_angles`
(`0x801aac28`, decompiled at `battle_bin_decompilation.txt.c:97426`) is called
by the `TARGET` / `CASTER` / `CURSOR` angle sources. It:

1. Reads a **4-bit field** from the focused tile's characteristics
   (`get_tile_characteristics(...) + 7`, low nibble). `get_tile_characteristics`
   (`...:78000`) indexes a **static, map-loaded** 8-bytes-per-tile array
   (`&DAT_8018f8cc + (elevation*0x100 + z*width + x) * 8`) — the same array
   holding surface type, height, slope, depth. **It is not unit data.**
2. Indexes a per-quadrant bit table `DAT_801b69d8 = [0x08,0x04,0x02,0x01]`.
3. Keeps the current yaw if its quadrant bit is clear; otherwise rotates the
   **minimum** amount to a clear quadrant (`+90`, else `−90`, else `+180`); if
   all four are blocked (`0xf`), keeps the current yaw.
4. Copies pitch and roll from the current camera unchanged — **yaw only**.

Two consequences for our design:

- The ROM resolves **terrain** occlusion of the unit, via a **precomputed
  per-tile per-quadrant bit**. It never considers other **units**, and it does
  **no "best angle" scoring** — there is no notion of ranking multiple valid
  angles beyond "nearest unblocked, prefer current."
- Our maps are **procedural** (`MapComposer`), so we have no byte-7 nibble to
  read. `CameraSubsystem._get_facing_yaw` (`src/effects/CameraSubsystem.gd:630`)
  already stubs the snap-to-45° part and explicitly skips the occlusion
  adjustment with the comment "(we lack tile data)". This ADR fills that gap.

Separately, the maintainer wants a behavior the ROM lacks: among angles where
the unit is visible, prefer the one that puts the **focused unit in the
foreground relative to other units** — so an ally standing between camera and
subject doesn't bury the shot. An early single-raycast experiment "focused on
big items" because one nearest-hit ray cannot tell "terrain hiding the unit"
apart from "unit in front of the subject."

The enabling primitive already exists: collision layers are `tiles = 2`,
`units = 4`, so terrain and units can be raycast independently (per
`godot-learning/CLAUDE.md`).

## Decision

Replace the `_get_facing_yaw` stub with a **facing resolver** that returns a
base yaw for a given **focused unit**, layered as follows.

**Candidate set.** The 4 fixed yaws (±45°, ±135°). Pitch and zoom are left at
whatever the effect/cinematic authored — the resolver never moves them. (We
considered escalating to the steeper pitch when no yaw clears, and scoring all
4×2 poses; both were rejected to stay ROM-faithful and to never fight the
authored cinematic.)

**1 — Terrain-visibility gate (ROM-modeled).** For each candidate yaw, test
whether the focused unit's **silhouette** (sample heights spanning feet → head)
is hidden by terrain along the sightline to the camera. A yaw is **eligible**
if a threshold fraction of samples are visible. Computed **live** (not baked):
we only ever query the subject tile and it runs once per subject.

This started as a physics raycast (`collision_mask = 2`) and **did not work** —
see Consequences. The shipped gate is **analytic**: march the sightline from
each silhouette sample toward the (orthographic) camera and compare every
column's tile-top world-Y (via `TerrainIndex`/`get_tile`) against the ray
height; occluded the moment terrain rises above the line. This is the same
quantity the ROM precomputed into per-tile bits, just evaluated live.

**2 — Foreground-composition tie-break (our addition, not in the ROM).** Among
eligible yaws, in order:
1. **Fewest occluding units** — raycast the silhouette with
   `collision_mask = 4`; count *other* units between camera and the focused
   unit; prefer the minimum (ideally zero).
2. **Most foreground** — prefer the yaw where the focused unit has the nearest
   camera-depth relative to neighbouring units.
3. **Minimal rotation from current** — the ROM's stabilizer: prefer the current
   yaw, then `+90`, then `−90`, then `180`. Keeps the camera from flip-flopping
   between equally-good angles.

**3 — All-blocked fallback (ROM-faithful).** If **no** yaw clears the terrain
gate, **keep the current yaw** (the ROM's `0xf` branch). We deliberately do not
best-effort the most-visible yaw here — the maintainer chose faithful + simple,
accepting that a fully-boxed-in unit stays hidden (rare).

**When it runs.** The cinematic freeze (`combat_visuals` →
`PROCESS_MODE_DISABLED`, [ADR-0037](0037-combat-pause-is-domain-scoped-via-process-mode-group.md))
pins every unit and tile for the cinematic's duration. So the resolver is
computed **once per focused subject and cached**: once for the caster
(charge / pre-pan), recomputed once when the subject switches to the target,
reused across that subject's keyframes. Movement never triggers a recompute
(nothing moves); only a subject change does. If caster == target, it resolves
once. `ALL_TARGETS` and `EFFECT_CTR` are not unit-anchored and get no facing
resolution (matching the ROM's no-op).

The focused unit's silhouette sample heights come from the unit's visual/
collision bounds; the hypothetical camera pose per candidate yaw is the
subject position plus the orbit offset for that yaw at the authored
pitch/distance (to be pinned in implementation).

## Consequences

- **Why the terrain gate is analytic, not a raycast.** The first implementation
  raycast `collision_mask = 2` and never reported occlusion. Cause:
  `DynamicTerrainBuilder._create_collision_shape` gives each tile only a flat
  `ConvexPolygonShape3D` over its top quad; the vertical cliff faces and skirts
  have **no collider at all**. A camera ray rising at ~26° from a unit threads
  *between* the flat tops and exits the map without hitting the cliff that
  visually blocks the unit. Adding wall colliders would be invasive and is
  unnecessary — the tile heights already encode the occluder, exactly as the
  ROM's precomputed per-tile bits did. So the gate marches tile heights instead.
  `CinematicFacingResolverTest` (loads MAP042 live) is the regression: it
  asserts the gate *detects* a real cliff occlusion and the resolver rotates to
  a clear angle. Unit occlusion is unaffected — units are Area3D volumes, so
  those rays work (with `collide_with_areas = true`).
- The cinematic reliably frames the unit unhidden by terrain, and prefers shots
  where allies don't block it — without a single-ray "big items" failure.
- We diverge from the ROM in two documented, deliberate ways: the
  foreground-composition tie-break (the ROM has no unit awareness or scoring),
  and computing terrain visibility live rather than from baked per-tile bits.
  We stay faithful in three: yaw-only (pitch never moved), the
  minimal-rotation-from-current stabilizer, and the keep-current all-blocked
  fallback.
- Two mechanisms for two purposes (terrain = analytic height march, units =
  physics raycast). Conflating them into one nearest-hit ray is the bug this
  design exists to avoid; see the CONTEXT _Avoid_ note.
- Cost is negligible: one resolve per subject (≈1–2 per cinematic) ×
  4 yaws × a handful of silhouette samples (a short height-march per sample for
  terrain, one ray per sample for units).
- Reversible in isolation — the resolver is a single function behind the
  existing `_get_facing_yaw` call site. The hard-to-reverse part is the
  *contract* (yaw-only, gate-then-compose, keep-current fallback) that callers
  and future cinematic tuning will assume.

## Alternatives considered

- **Replicate the ROM exactly** (baked per-tile quadrant bits, nearest-unblocked
  snap, no unit awareness). Rejected: misses the maintainer's foreground-
  composition requirement, and baking buys nothing when we only ever query the
  subject tile under freeze.
- **Pure raycast "best angle" scoring** (score every pose by visibility %,
  framing, distance; pick the max). Rejected: diverges furthest from the ROM,
  needs an invented scoring policy, and is what produced the "big items"
  behavior.
- **Let pitch participate** (escalate to steeper pitch, or score all 8 poses).
  Rejected: the effect authors pitch/zoom; a resolver-driven pitch change reads
  as a different shot than intended.
- **Best-effort most-visible yaw on all-blocked.** Rejected by the maintainer in
  favor of ROM-faithful keep-current.
- **Re-resolve per keyframe.** Equivalent results under freeze but redundant;
  per-subject caching is the minimal exact form.
