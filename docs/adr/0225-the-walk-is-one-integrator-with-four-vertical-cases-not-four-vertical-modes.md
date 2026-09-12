# The walk is one integrator with four vertical cases, not four vertical modes

`ScenarioPathMotion` was 341 lines that decided, per tile, which of four vertical
*shapes* a `{28} Walk To` step had:

```gdscript
enum VMode { FLAT, FALL, HOP, RAMP }
```

`FALL` was a gravity arc armed on a downward step. `HOP` was a launch at
`sqrt(2·g·Δy)` armed on an upward one. `RAMP` was a linear climb armed when the
step was less than a whole elevation level. Each was chosen at the tile boundary
from that step's `Δy`, and each ran to a snap on arrival.

The ROM has none of them. It has **one** integrator, `unit_move_stepper @
0x8006AF7C`, with **four vertical cases** — armed walk, running walk, airborne, and
the fall-through — and **one gravity**, `0x925`. A descent is not a case at all:
the two walk cases integrate gravity themselves, which is why there is no drop
branch anywhere in the function. A sub-level slope is not a case either: it is the
Y term of the direction vector, `(corner − 1) · slope_height · 6`, fed through
`vec3_normalize` like the X and Z terms. And a leap and a hop are the same case —
they differ only in what seeds `+0x2C` and `+0x28`/`+0x30`.

So two of the four modes named shapes the hardware does not have, and the two that
survived were armed off the wrong input. #803 §19 item 8, §22.2, §24.3.

Status: accepted (2026-09-03). Built on `research/803-jump-semantics`, ticket
[#803](https://github.com/timbermania/fft-monorepo/issues/803). Extends
**ADR-0055** (Walk To stays a scene-free value object the VM drives) in place: the
object is unchanged, what is inside it is not. Publishes one name under
**ADR-0211 dec. 4** and ships its test under **ADR-0194**.

## Context

### The old model was not wrong by accident — it was never scorable

`ScenarioPathMotion`'s docstring cited a live trace and named real addresses, and
its three shapes each reproduced something someone had watched. What it never had
was a way to be **scored**: there was no artefact that said *this trajectory, frame
for frame, is what the hardware does*. So every one of its constants was a
plausible reading that nothing could contradict, and three of them were wrong in
ways no test in this tree could see:

| the old model said | the ROM does |
|---|---|
| `frames_per_tile = 224 / Speed`, a float | an integer recurrence whose per-frame step is `sar12(mag · 4095)`, because `vec3_normalize` returns **4095** for a cardinal axis, and whose position is re-quantised once per step at the launch gate. Speed 16 costs **15** frames a tile, not 14; Speed 8 costs **30**, not 28 |
| a climbing step flies `hop_air_frames(dh)`, `64·sqrt(x)` | `SquareRoot0 @ 0x8001C268`, a LUT — the `64·sqrt` approximation runs 0.15 % high and misses the launch velocity by 25 subunits |
| a sub-level step is a linear `RAMP` | a Y term in the direction vector, so the unit is on the drape the whole way across |
| `configure(… speed …)` | the operand is a little-endian **8.8** halfword; `+0x38 = raw << 1`. Six shipped `{28}`s are fractional |

The `224/Speed` figure was not only in the class. `ScenarioApplyTest` asserted it,
which is the shape a test takes when it is written from the same reading as the code
it guards.

### What changed is that there is now something to be scored against

`research/scenario29_walk_vs_jump/evidence/rom_walk_render.py` is the whole render
side transcribed as one executable file — every branch a line of
`battle_decompilation.c` cited by address, no free parameters — and it is scored
against thirteen live PSX captures at **43 510 of 43 510 field-frames** over sixteen
logged fields. The captures are not thirteen repeats of one thing: they cover the
shipped walk, a widened moat, a leap that climbs, both steep-slope gait route bits,
four Speeds including a fractional one, and all ten drape shapes no capture had ever
crossed.

That file is a specification a port can be *diffed against*, which is what the old
model never had.

### Two findings a port gets wrong if it ports the prose instead

**The walk animation is a function.** `FUN_80082DF8` re-picks it from a band of
`unit+0x38` on every re-latch: 14 below `0x1401`, 12 below `0x3000`, 13 above, and
11/9/10 instead when the tile under the unit has `depth ≥ 2`. Speed 10 gives
`+0x38 = 5120` against a threshold of `5121` — it clears the boundary by **one
subunit**. Speed 10 was the only Speed ever on the wire before 2026-09, so a
hard-coded `14` scored 14 502 of 14 502 field-frames across five captures and was
still wrong for **80 of the 282 shipped `{28}`s**.

**The Speed operand is 8.8 fixed point.** Five of scenario 29's own instructions
are fractional (PCs 19/27/34/152/478) and one of scenario 117's is. An `int`
operand rounds all six, and for at least one of them that is a different animation
band.

### Where the fidelity is actually lost, and it is not in the stepper

The stepper reads five bytes per tile: surface, height, depth, slope height, slope
type. `ScenarioVM._plan_walk_route` hands `ScenarioPathMotion` a **polyline** —
a list of world-space waypoints — which can state exactly one of those five,
approximately: each tile's height, rounded to the nearest whole level from its
waypoint's Y.

That is a fact about the caller, not about the port. `TerrainCell` carries `height`,
`surface_type`, `impassable`, `unselectable` and `pass_through_only`, and no
`slope_height`, `slope_type` or `depth` — though every shipped `terrain.json` bakes
all three.

## Decision

**1. The walk's motion is a transcription, and it lives in one file.**
`addons/exmateria_battlefield/motion/RomWalkStepper.gd` is the ROM's `{28} Walk To`
render half, ported branch for branch from `rom_walk_render.py`. Every function
carries the address it came from. Nothing in it is a model with a tunable, and
nothing in it may be "cleaned up" into one — including the two GTE LUTs, which are
what make `4095` and `SquareRoot0` exact rather than nearly right.

**2. It is scored against the WIRE, and the fixtures carry the wire's own rows.**
`tools/gen_rom_walk_fixtures.py` bakes the thirteen captures into
`addons/exmateria_battlefield/tests/fixtures/rom_walk/` — the **live** per-frame
rows off the PSX logs, plus each arm's post-patch MAP009 tile array.
`RomWalkStepperTest` replays them and reports:

> `VERDICT: 43510 of 43510 field-frames over 13 captures (0 differ)`

Baking the tile array rather than reading `res://assets/maps` is deliberate: that
directory is an asset **symlink**, absent from a bare worktree, and a test that
reached for it would go red for a reason that has nothing to do with the walk. It
also means the fixture needs no patch machinery on the GDScript side.

**3. A second, clearly-labelled corpus covers what the captures cannot reach.**
All thirteen captures are ordinary walks on MAP009, so whole arms of the machine
are never entered by them — the leap, the big jump, the wind-up, hard landing and
recovery, the landing sound and puff tables, the far-fall pose swap, the gait.
`tools/gen_rom_walk_fuzz_fixtures.py` generates a seeded random corpus and
`RomWalkStepperCrossCheckTest` scores the port against the **Python spec** on it:
**157 518 of 157 518 field-frames over 47 cases, all 32 states of `unit+0x7f`,
222 landing sounds and 82 puffs**.

That test is loudly labelled as saying **nothing about the ROM**. Both
implementations were written from the same reading, so a shared misreading passes
it silently. What it catches is the population of errors a *port* introduces — a
mistyped constant, an inverted comparison, a dropped sign, a wrong table index —
in the two thirds of the state machine no capture visits. Capture fixtures test
the reading; these test the transcription; neither substitutes for the other, and
saying which is which is the point.

The state count is **asserted**, not printed: a regenerated corpus that quietly
stopped reaching the leap would still report "0 differ", over a machine it never
entered.

**4. `compare_frames` is asserted, not just the mismatch count.** A stepper that
halts after three frames scores "0 differ" over three frames, and a suite that only
counts mismatches reads that as a pass. Each fixture records the frame count the
Python scorer compared, and the test asserts it.

**5. `ScenarioPathMotion` keeps its API and stops modelling the walk.** Its public
surface — `configure`, `advance`, `position`, `is_done`, `snap_to_end`,
`poll_facing_change`, `waypoints`, `dur_s` — is unchanged, so `ScenarioActor`,
`ScenarioWorld`, `ScenarioApply`, `ScenarioVM` and `exmateria_battlefield` compile
untouched. What it does is now two jobs and no others:

  * the **coordinate map** — render units (28 per tile edge, 12 per elevation level,
    Y negative up) to Godot world metres, anchored on the caller's own start
    waypoint and on the start tile's **ground in render units**, never on its height
    in levels (a draped start tile does not sit on a whole level);
  * the **clock** — the whole trajectory is stepped once at `configure` time and
    `advance(dt)` walks a cursor along it. That makes the result deterministic and
    framerate-independent, and it makes `dur_s` known before the first frame, which
    is what the `{29}` Wait Walk watchdog needs from an emergent frame count.

`enum VMode` is retired. `hop_air_frames` is deleted rather than corrected — the
right answer is `RomWalkStepper.square_root0`, and keeping a second, approximate
spelling of it beside the exact one is how the approximation comes back.

**6. The ARRIVAL frame is recorded, though the scorer drops it.** `step()` returns
`false` on the frame in which the running handler snaps to the destination centre
and finds the route buffer spent — so the arrival *happened* in a frame the loop
does not report. `rom_walk_render.py` drops it too (its `replay` appends after the
break), which is correct for a scorer comparing a prefix and wrong for a
trajectory: without it the walk ends a seventh of a tile short of the seat it was
sent to.

**7. A polyline caller is told what it is not saying.** `configure` documents
exactly what a waypoint list cannot state — no gait, no drape, no splash, no
landing sound, no leap — and `configure_rom` is the surface with none of that
missing. Both share one coordinate map, which `ScenarioPathMotionTest` asserts by
running the same flat route through each.

**8. Closing that gap is the CALLER's change, and it is not taken here.**
`_plan_walk_route` would need a `terrain.json` reader producing PSX tiles (the
ADR-0052 Z flip included) and, with it, a **second GDScript copy of the exporter's
slope-type and surface-type enums** — 13 and 50 name-to-byte rows that today exist
only in `tools/fft_exporter/models/terrain.py`. That is new duplicated ROM knowledge
that wants its own guard against the Python enum, and unlike everything else in this
change it has no golden fixture to be scored against. It is filed, not smuggled in.

## Prediction

Written before the port ran, and both were checked:

1. **A faithful GDScript port reproduces the Python transcription's score exactly**,
   43 510 of 43 510 — not approximately, because both are integer arithmetic over
   the same LUTs and there is no float anywhere on the path. *Held, first run.*
2. **At least one existing assertion in the tree encodes the `224/Speed`
   approximation and goes red.** *Held:* `ScenarioApplyTest`'s walk duration, which
   asserted `(224·3/8)/60 = 1.4 s` against the recurrence's 91 frames = 1.5167 s.

A third thing was not predicted and is worth recording because it is the same
class of defect: that test's walk fixture stated tile **corners**
(`Vector3.ZERO, (1,0,0), …`), a shape `_plan_walk_route` has never emitted — it
emits `(t.x + 0.5, wy, t.y + 0.5)`. It went unnoticed for as long as the motion
lerped between arbitrary points and never asked which *tile* one was in. A
tile-addressed stepper asks immediately.

## Consequences

- **Walks are slower than they were, by a frame per tile or more**, at every Speed.
  That is the ROM's cadence and the old one was short; any timing tuned against the
  old number was tuned against an approximation.
- **`ScenarioApplyTest` now asserts the recurrence**, and names why.
- **`ScenarioDecode.walk_to_duration_frames` is deleted, not corrected.** Once the
  motion stopped calling it, its only remaining caller was its own test — a
  function whose docstring said *ROM-derived* and whose value was low by a frame a
  tile, sitting in the decoder every future caller reads first. That is the same
  argument decision 5 makes about `hop_air_frames`, and it applies wherever an
  approximate spelling survives beside an exact one. `ScenarioDecodeTest` keeps
  every `walk_to_speed` arm — the 8.8 decode is right and is now the only thing
  about Speed this file is responsible for.
- **The battlefield addon publishes a sixteenth name**, and `test_check_addon_globals`'s
  restore control moves 15 -> 16 with it — that count is the control, and a number
  nobody maintains stops saying which surface came back. `RomWalkStepper` sits beside
  `EventPathfinder` because they are the two halves of one opcode: that one turns a
  start and a destination into route bytes, this one turns route bytes into a
  trajectory. Both are pure, both are host-independent, and the stranger rig runs
  the new test green in a project that did nothing for the addon.
- **`configure_rom` has no production caller yet.** It is exercised end to end by
  `ScenarioPathMotionTest`, including the drape a polyline cannot state, so it is a
  proven seam rather than a speculative one — but decision 7 is the reason it is
  idle, and a reader should not take its existence as a claim that the game runs
  on it.
- **The wading animation band was UNREACHABLE, not merely unscored, and is now
  wired.** `rom_walk_render.py` made `FUN_8008278C`'s depth class a defaulted
  parameter of `walk_anim` and then never passed it — while its own comment said
  the band was `[STATIC]`, which claims the opposite. The ROM has no such
  parameter: `FUN_80082DF8` reads the depth itself at `0x80082E1C`, off the tile
  under `+0x40`/`+0x44`. Wired in the port **and back into the spec**, and both
  still score 43 510/43 510 — which is the evidence that connecting it moves
  nothing any capture has seen. `RomWalkStepperTest` now has the arm the thirteen
  captures cannot provide, because MAP009's moat is depth 1 and the threshold is
  `≥ 2`. The band remains `[STATIC]`: reached, and still not scored against
  hardware.
- **Three more things in the stepper are transcribed and unscored, and say so in
  place**: the landing sound and puff
  (the 46-surface accounting closes exactly, but nothing has been heard or seen
  fire), `landing_frames = 18` (from one capture; the mechanism is known and the
  number must come from SEQ), and the big jump (`FUN_8006A7C0`, unreachable from
  `{28}` because the planner's climb gate is 3 levels). A green suite does not
  cover any of them.
- **Porting a specification is itself a way of testing it.** The gap above was not
  found by a capture or by a guard; it was found by transcribing the file a second
  time, into a language whose defaulted arguments look different, and asking what
  each one was for. A spec scored 43 510/43 510 still had a branch nothing could
  enter.
- **The routing half is still the shipped uniform-cost BFS.** `EventPathfinder` is
  not the ROM's flood; `rom_event_flood.py` is that transcription, scored 9/9 arms
  and 224/224 tiles, and porting it is separate work. Until it lands, route bytes
  reaching the stepper carry no leap (`extra` is always 0) and no steep-slope bits.

- **Three producer-side guards fired on the new file, and all three were right.**
  `check_no_raw_psx_units` wanted the `>>12` routed through `PsxUnits` — answered
  with the `# psx-faithful-sim:` header the guard itself provides, because here the
  fixed point IS the hardware's arithmetic and re-deriving it would replace the
  thing under test with a model of it. `check_move_manifest` wanted the new file on
  `EXTRACTION-3-MOVE-MANIFEST.tsv` — the addon's population is a manifest, not a
  folder listing. And `check_lattice_doors` reported a `Tile` in a return position:
  the record was named `Tile`, colliding with `lattice/Tile.gd`, which is a
  `Node3D` a host can hold. Renamed to `MapTile`. That last one is worth keeping in
  mind as a pattern — the guard's finding was a false positive about the *rule* and
  a true positive about the *name*, and one addon carrying two `Tile`s is a
  register that cannot say which one crossed the boundary.

- **All three test files gate on ARMS RUN, not only on assertions failed.** A
  GDScript error aborts just its enclosing function, so an arm that dies part-way
  contributes no failures, `_ready` resumes, and the file prints `[PASS]` over a
  test that never ran. `43 510 of 43 510` is precisely the kind of number that
  would have gone on appearing over an arm that aborted on frame one. The
  `_completed` pattern is `BattlefieldProvidesTest`'s, four files away in this same
  addon. It was **proved by seeding an abort before the arm's first assertion** —
  `25 passed, 0 failed → [PASS]` became `25 passed, 0 failed, 4/5 arms reported →
  [FAIL]`. ⚠️ A seed that trips any assertion on its way down reds the file for the
  ordinary reason and leaves the arm count as decoration; the guard is only proved
  against an abort with **zero** failures.

## Alternatives considered

**Fix the four modes rather than replace them.** Rejected: two of the four name
shapes the ROM does not have, so "fixing" them means deciding which hardware
behaviour each mode is *supposed* to approximate — which is the activity that
produced the wrong constants in the first place. There is no arrangement of
`{FLAT, FALL, HOP, RAMP}` in which a descent is not a case and a slope is a
direction vector.

**Keep the stepper in `src/scenarios/` beside its adapter.** Rejected: it is
`EventPathfinder`'s sibling, it reaches nothing outside itself, and putting it in
the addon is what makes the stranger rig able to say so. The adapter stays in
`src/scenarios/` because converting to Godot world space is the host's job, not the
addon's.

**Port the routing half in the same change.** Rejected as scope: the two halves
have independent specs and independent scores, and the render half is the one that
`ScenarioPathMotion` was getting wrong.

**Score the GDScript port against `rom_walk_render.py`'s simulation.** Rejected:
that scores a transcription against its sibling transcription, and a shared
misreading passes. The fixtures carry the **live** rows, so a green test is a
statement about hardware.
