# The battle handoff costs ONE frame, and everything the player sees is on it

> **FIXED IN THREE ROUNDS.** Everything below is ROUND 1's DIAGNOSIS, kept verbatim as the
> record of what was measured on `bffe50dcb`. What landed, and the two places that
> diagnosis turned out to be wrong, are in [§ What landed](#what-landed).
>
> 🔴 **READ ROUND 3 FIRST.** Round 1 fixed the SPIKES and the report came back about the
> SHAPE; round 2 fixed the shape and the report came back a THIRD time.
> [§ Round 3](#round-3--the-image-was-never-static-and-the-protagonist-was-running-at-2x)
> is where the code's current behaviour lives, and it **refutes round 2's central
> argument** — the premise that the revealed field is a static image, on which round 2
> deliberately left ~100 ms of blocking build in the visible window. Ten sprites are
> breathing at 60 fps through that window.
>
> [§ Round 2 — the ease's SHAPE, not its spikes](#round-2--the-eases-shape-not-its-spikes)
> supersedes round 1's account of the CAMERA and is still current on that subject: it is
> where `camera.handoff_ease_seconds` and the two clocks are explained. Its camera numbers
> reproduce unchanged after round 3.


**Measured 2026-09-10** against `main` @ `bffe50dcb`, headful, `Engine.time_scale = 1.0`,
RTX 5090, warm driver cache. Instrument: `tools/probe_ready_freeze.gd` (below).

The report, in the author's words:

> When the dark screen is up and it says "ready" there is a performance (I think)
> issue where when the ready is fading out, the game freezes for a sec, and then
> jerks into position on to the first unit in the battle (I think). This
> transition needs to be seamless.

Both halves are correct, and both land on **the same single frame**. The "(I think)"s
were right: it is a performance stall, and it does end on the first unit.

## The beat

Gariland's opener (group root 9) is scn 10, and scn 10 **is** the battle-intro
template — the whole event is the intro (`research/working_documents/BATTLE_RESULTS_SCREEN.md`
§13's 78-event census). Its tail:

```
pc 37   {78} 00 3C   Display Conditions   READY!, hold 60
pc 38   {E5} 38 00   Wait For Instruction holds while the screen is on its own clock
pc 39   {77}         Remove Dark Screen
pc 40   {E5} 36 00   Wait For Instruction
pc 41   {1C} 01      Event Speed
pc 42   {DB}         Event End            -> the navigator advances to `pre_battle`
```

`NavigatorRunner` then dispatches `pre_battle` → `NavigatorMain.run_pre_battle`, which
builds the frozen `CombatLoop` and mounts the command cursor.

## What the trace says

`probe_ready_freeze.gd` records, per frame, the UNSCALED wall-clock cost of that frame
and the camera pose, against the VM's PC. Clean tree, 1,190 frames, 21.2 s:

```
frame cost_ms  pc op                    res(live,mode,el) dark(prog) nav(st,act) loop  dpos    cam
 1007    15.9  39 Remove Dark Screen     1,0,130    1.00   2,0        0    0.000  (67.321,45.755,-55.321)
 1008    16.1  39 Remove Dark Screen     1,0,131    1.00   2,0        0    0.000  (67.321,45.755,-55.321)
 1009   790.1  43 <event ended>          0,0,132    0.00   7,1        1    6.643  (66.758,47.294,-61.758)
 1010    27.3  43                        0,0,132    0.00   7,1        1    0.013  (66.754,47.306,-61.754)
```

Every other frame in the run is 16.0 ms. **Frame 1009 is 790 ms**, and on that one frame:

- the READY! screen dies (`res_live` 1 → 0),
- the VM runs `{77}`, `{E5} 36 00`, `{1C}` and `{DB}` — four instructions, pc 39 → 43,
- the dark screen goes from fully established to gone (`dark_prog` 1.00 → 0.00),
- the navigator advances (`nav_state` 2 → 7, `nav_action` 0 → 1),
- the frozen battle loop stands up (`loop_up` 0 → 1),
- and the camera **teleports 6.643 units** (`dpos`).

## Finding 1 — the stall is device + buffer creation, not the pipeline compile

`a3bfefa11` moved the ~5.5 s compute-pipeline compile onto a background worker. **That fix
is working**: the warm-up reports 28–54 ms and the battle device's own `_build_stages`
reports 28–72 ms. The handoff's "the warm-up lost its race" hypothesis is **refuted**.

What is still on the frozen frame, timed leaf by leaf over four runs:

| leaf | cost (ms) |
|---|---|
| `RenderingServer.create_local_rendering_device()` | **208 – 560** |
| `GPUEffectTimingLoader.build()` (+ cooldown buffer) | **162** |
| `_build_stages` (battle device) | 28 – 72 |
| distance + battle + results buffers | 23 |
| `GPUAbilityLoader.build()` | 15 |
| `GPUAnimationTimingLoader.build()` | 12 |
| `build_map_data` + buffer | 2 |
| `CombatLoop.setup_distance_field` | 15 – 40 |
| `NavigatorMain._mount_turn_director` | 10 – 30 |
| `NavigatorMain._mount_formation_map_screen` | **61 – 116** |
| `CursorRig.mount` | 3 – 9 |
| `CursorController.seed_from_map` | 2 – 4 |

`boot_battle` totals **469 – 1547 ms** across runs; `run_pre_battle`'s whole body
**481 – 1597 ms**. The spread is box load, not the diff — it is never small.

None of this is per-unit or per-map work that must wait for the battle to be known:
`rollout_fleet_size` is 0, so `_num_battles` is 1 and every buffer is tiny. The three
`GPU*Loader.build()` calls are pure, deterministic CPU data builds, and the local
rendering device is a resource, not a battle. **All of it could be paid before the
intro ever starts**, exactly as the pipeline compile now is.

## Finding 2 — the camera jerk is a deliberate hard cut

`run_pre_battle` → `_enter_command_cursor()` → `CursorRig.seed_from_map()` →
`CursorController.seed_from_map()`, whose last two lines are:

```gdscript
	_cursor.move_to(Vector2i(cell.grid.x, cell.grid.y))
	if _camera != null:
		_camera.follow_cursor(lattice.world_position_at(cell.grid), true)   # snap = true
```

`follow_cursor(pos, true)` assigns `global_position = world_pos` outright. Measured:

```
[ready-freeze] seed_from_map 2.7 ms — camera (4.062889, 1.067886, 7.937111) -> (3.5, 2.607143, 1.5)
```

6.643 units in zero frames — the exact `dpos` the trace records on frame 1009. The
comment above it says so on purpose ("hard-cuts the camera onto the tile instead of
sliding in from the old focus"), which is right for a bare scene boot and wrong for a
handoff **out of a cinematic that just posed the camera**. `resume_cursor_framing()`'s
16-frame datum ease then slides a further ~1.2 units over frames 1010–1025, which is
why the jerk reads as a cut followed by a settle.

Note what the event script itself is doing here: scn 10's `{19}` **at pc 33 (offset 178)
is a camera move under the dim** — the ROM poses the battle's opening camera while the
screen is dark, then retracts the dim onto an already-framed field. The port throws that
pose away two seconds later.

## Finding 3 — `{77}`'s retract never plays, so there is no cover to hide behind

Two independent reasons, both on frame 1009:

1. **The barrier does not hold.** `ScenarioDarkScreen.is_settling()` returns true only
   for `_dir == 1` (the grow-in), so the kind-54 liveness closure in `ScenarioVM`
   (`_task_liveness[TASK_DARKSCREEN]`) reports dead the instant `{77}` runs, and the
   following `{E5} 36 00` releases on the same frame. In the ROM it does not: `{76}`'s
   body re-labels its task `0x37` once the dim is up and `{77}` re-labels it back to
   `0x36`, so `{E5} 36 00` waits for the task to EXIT — the full teardown
   (BATTLE_RESULTS_SCREEN.md §13, "`{E5} Wait For Instruction` blocks on the task *kind*").
   `ScenarioDarkScreen.sweep_frames()` is **112 frames** for the shipped operands.
2. **And then it is snapped away.** `run_pre_battle` → `_ensure_battle_world()` calls
   `_vm.settle_screen_effects()` **unconditionally**, which calls `_dark_screen.settle()`
   → `_dir = 0, visible = false`. That call is documented as the *seek / fast-forward*
   guarantee ("Called by NavigatorMain.run_combat"), but `_ensure_battle_world` is also
   on the ordinary linear walk, where nothing was fast-forwarded and the retract is a
   real authored animation.

So the intro ends ~1.9 s early, the dim vanishes in one frame instead of retracting, and
the 0.5–1.6 s battle build lands on a fully revealed battlefield with nothing over it.

## What a fix has to do

The three findings are one shape: **the battle is built after the curtain is already up,
and the curtain's own retract was cancelled.** In the ROM the field is standing and framed
before `{77}` ever runs.

Ranked, cheapest first:

1. **Pay the build before the intro.** Move `_build_frozen_combat_loop` +
   `_enter_command_cursor` to the battle-world boot (`_ensure_battle_world`), where the
   cost joins an existing loading stall instead of landing on a live reveal. Needs care:
   the opener's `{19}` camera takeovers must still win over the cursor's framing for the
   duration of the cinematic.
2. **Or warm what is warmable**, the way `warm_pipelines_async` already does — the local
   rendering device and the three `GPU*Loader.build()` results are battle-independent and
   together are the majority of the stall.
3. **Stop hard-cutting the camera** out of a cinematic: seat the cursor without moving the
   camera when the camera already holds an authored pose (scn 10's pc-33 `{19}` IS the
   battle's opening pose), or ease instead of snapping.
4. **Hold `{E5} 36 00` for the retract** (kind-54 liveness must count `_dir == -1`), and
   stop calling `settle_screen_effects()` on the walk path where nothing was seeked.
   On its own this makes the beat *longer*, not smoother — it is only worth doing
   together with (1) or (2).

## The instrument

```
# from the package root
OUT=/tmp/rf.csv godot --path . -s res://tools/probe_ready_freeze.gd -- --battle=9 --watch-opener
```

~25 s, headful, no suite. It scores only the frames from the intro's first `{78}` screen
onward (the scene's own boot costs hundreds of ms and moves the camera 160 units — real,
and not the subject), and prints:

```
[ready-freeze] VERDICT: 3 frame(s) over 100 ms; worst 1026.1 ms; worst camera step 6.643 units
[ready-freeze]   slowest frame: 892,1026.087,1,43,,0,0,132,0,0.0000,7,1,1,0,6.6425,0.0000,66.758,47.294,-61.758
[ready-freeze]   biggest jump:  892,1026.087,1,43,,0,0,132,0,0.0000,7,1,1,0,6.6425,0.0000,66.758,47.294,-61.758
```

**The slowest frame and the biggest camera jump are the same frame** — which is the whole
finding in one line. Seven runs on `bffe50dcb` put the stall between **469 ms and 1,547 ms**
and the camera step at **6.6425 units every time**, onto the same coordinates. A fix has to
take both to zero (or, for the camera, to a step spread over frames).


---

## What landed

Three fixes plus a camera change, on `fix/1168-ready-fadeout-freeze`. Measured with
the same instrument, same battle (Gariland, root 9), both handoff paths — parked at
Deployment and `skip_pre_battle` straight to combat:

| | before | after |
|---|---|---|
| worst frame in the window | **469 – 1547 ms** (7 runs) | **56.0 – 57.2 ms** (3 runs, idle box) |
| worst single-frame camera step | **6.6425 units**, every run | **0.625 units**, eased over 18 frames |
| what the probe now calls "biggest jump" | the handoff frame | the opener's own authored `{19}` move under the dim |

### 1. `{77}`'s retract plays again (fix 4)

Both causes in Finding 3, both fixed. `ScenarioDarkScreen.is_settling()` is now
`is_sweeping()` and true in BOTH directions — the PSX barrier is on the task KIND, and
`{77}` re-labels the slot back to `0x36` for the whole teardown, so `{E5} 36 00` waits
out all 112 frames. And `settle_screen_effects()` moved INSIDE `_ensure_battle_world`'s
seek branch: `_battle_world_root != root` is the seek predicate, because `play_beat`
stamps it when the opener beat boots the world, so the linear walk no longer reaches
the fast-forward guarantee it was never entitled to.

### 2. The battle-independent cost is paid before the intro (fix 2)

`create_local_rendering_device()` (208–560 ms) and `GPUEffectTimingLoader.build()`
(162 ms) now happen before the beat, not on it.

🔴 **The device CANNOT ride the existing worker warm-up, and this cost a cycle to
learn.** A local `RenderingDevice` is THREAD-AFFINE. Built on a `WorkerThreadPool` task
and handed to the main thread, every call on it fails with *"This function (free_rid)
can only be called from the render thread"*, `buffer_get_data` comes back short, and the
first read of a unit state dies on `Invalid access of index '4'` — with an `exit 134`
at the end for good measure. So the ~180 ms is paid on the main thread either way; the
fix is WHERE. `GPUBatchSimulator.prewarm_device()` runs in the host's `_ready`, and
`prewarm_stages()` at the battle-world boot (`_boot_world_for`) — the earliest point the
worker warm-up has filled the driver's pipeline cache, and a stall already under a
primed-black screen. `release_prewarm()` gives back an unclaimed device, because a live
one at process shutdown is `exit 134`, not a leak warning (#471).

`GPUAbilityLoader.build()` is deliberately NOT prewarmed despite being the same shape:
it reads `LeverSet`, which the F3 panel edits at run time, so a parked copy would go
stale. It is 15 ms, already inside a frame's budget.

### 3. The remainder is spread over frames (fix 3)

`_build_frozen_combat_loop` and `_enter_command_cursor` are coroutines, yielding at the
boundaries this document's leaf table named. The distance field and the GPU simulator
are driven from the navigator with a yield between them rather than from inside
`boot_battle` (which no-ops once `gpu_simulator` is up). The UI3 MAP host's build is
split across three frames inside `FormationDetailTransition._ready`; the ROSTER host is
untouched.

### And the camera — Finding 2 needed its own fix after all

**The handoff's prediction that the seat would land under the dim is REFUTED by the
measurement.** With the barrier holding for the full retract (fix 1), `{DB} Event End`
fires when the dim has already cleared, so the build — and the seat — land on a fully
revealed field. `dark_prog` is `0.0000` on the handoff frame in every post-fix trace.
So the hard cut was not hidden by fixing the retract; it became MORE visible.

Fix 3 from the ranked list, in its "ease instead of snapping" form: the seat passes
`snap_camera = false`, and `PlayerCamera.ease_onto()` is the call with no first-touch
snap. ⚠️ `follow_cursor(pos, false)` was NOT enough and the first attempt at this failed
for a reason worth keeping: `move_to` emits `cursor_moved` → `_on_cursor_moved` →
`track_cursor`, whose own "no prior target" branch snaps the body from inside `move_to`
— and nothing had driven the follow path while the opener held the camera in TAKEOVER.
The ease is primed BEFORE the move, which gives `track_cursor` a prior target and sends
it down its deadzone path instead.

### The residual, said out loud

⚠️ The before- and after-numbers above are **both from an idle box**, which is the only
way they compare. The same tree scored 74-77 ms while a stranger's suite held 7 Godot
processes — the spread is load, exactly as the 469-1547 ms baseline's is.

The worst remaining frame is **~55 ms of `FormationMapHost._ready`** — the UI3 screen
host's own element-tree build, reached through `super()`, and it is ONE indivisible call.
Splitting the three frames of `FormationDetailTransition._ready` around it was tried and
REVERTED: it moved no number (61.3 ms without it, 66.0 with) because the `_build_recipes()`
it deferred profiles at 0 ms, and it made `formation()` — the screen's whole selection
surface — return null for two extra frames, which reds `GambitDeploymentPickerTest` and
`FormationChangeJobConfirmTest`. Reducing it means going into the UI3 host build. It lands
on a static, fully revealed field in the frame immediately BEFORE the camera ease starts,
which is the best placement available without that surgery. `setup_gpu_simulator` is the
other, at ~44 ms (stage adoption + buffers + the un-prewarmed ability table).

One test paid for the retract, and the charge is real. `NavigatorWorldMapArrivalTest`'s
walk crosses a battle intro, so it is 2.2 s longer (24472 -> 26704 ms). Its budget was
25 s — which means trunk was passing it with **528 ms of margin**, on a box shared with
~45 worktrees. Raised to 45 s, and it prints its margin now.

### Why there is still no perf test

The probe stays a hand-run instrument. A `perf`-kind test is the only place
`Time.get_ticks_*` is allowed (TEST-CHARTER clause 14) and auto-lane-pins the process,
and the measurement is load-sensitive by nature — this document's own baseline spans
469–1547 ms on one tree from box load alone. A gate on that number is a flake
generator. What IS guarded, seed-broken both ways:

- `ScenarioDarkScreenTest` — the kind-54 barrier is live on the frame `{77}` runs, still
  live one frame short of the retract's end, and clear after it.
- `NavigatorPreBattleTest` — the walk path does not settle the VM's screen effects, with
  a positive control on the counting stub.
- `PlayerCameraDatumEdgeTest` — the seat eases, arrives, and does not move on the call
  frame; plus the control that `follow_cursor` on a fresh rig still hard-cuts.

---

## Round 2 — the ease's SHAPE, not its spikes

> **FIXED — `fix/1168-ready-camera-ease-shape`.** Round 1 above took the worst frame from
> 469–1547 ms to ~60 and the worst single camera step from 6.6425 units to 0.625, and the
> report did not go away — it MOVED:
>
> > I still get a little bit of jerk after (instead of during) the ready text. And/or maybe
> > the camera moves too fast to the first unit after ready begins. How does it compare to
> > how the camera moves at the end of Magic City battle, in between combat and Ramza's
> > dialogue at the end.
>
> All three clauses are right, and the trace round 1 left behind already contained all of
> them. This section is what they turned out to be.

### The instrument had to change first, and that is the lesson

Round 1's verdict is `worst single-frame cost` + `worst single-frame camera step`. Both
were green by the time the report came back, and **neither can express what was being
reported**, because neither is a claim about MOTION. A beat can have every frame inside
budget and every step a textbook cosine and still read as a lurch.

`probe_ready_freeze.gd` now scores the window that opens the frame the retract ends:

| line | what it is for |
|---|---|
| `DEAD BEAT` | frames (and ms) between the full reveal and the camera's first move |
| `MOVE` | frames, ms, **arc length**, peak and mean per-frame step |
| `CLOCK LAG` | how far the ease's own progress has drifted from the WALL CLOCK |
| `VELOCITY` | units per SECOND, mean and peak — what the eye integrates |
| `EASES` | the body / datum / rotation spans as three `[start,end]` pairs |
| `FILM=<dir>` | the reveal as a strip of PNGs, so "ugly" gets looked at |

**`CLOCK LAG` is the one to read first**, and the two metrics either side of it are traps.
`JERK` (2nd difference of the per-frame step) silently assumes every frame lasted the
same: under a frame-counted ease that assumption HIDES the defect, and under a
clock-driven one it INVENTS one — a 28 ms frame legitimately carries a double-length step
and gets reported as a 98 %-of-peak spike. Both readings were produced during this work
and both are meaningless. What the eye sees is position as a function of wall clock.

### What the handoff's three leading hypotheses turned out to be

All three were refuted by the first run of the extended probe, before any code changed:

- **"the three eases are on three clocks that don't line up"** — body `1135–1152`, datum
  `1135–1150`. They start on the SAME FRAME. (It became true later, but only as a
  CONSEQUENCE of the fix — see the datum, below.)
- **"rotation discontinuity may be the real culprit"** — `0.000 deg` across the whole
  window. The instrument is not blind: it reads 0.36 deg/frame at frame 624.
- **"a clipped or restarted ease"** — 2nd difference 3.1 % of peak. The cosine is clean.

### Finding 4 — `ease_onto` borrowed a counter that is neither its length nor its unit

`ease_onto` is `follow_cursor` without the first-touch snap, and it inherited
`follow_ease_frames` along with the rest. That constant is wrong for this call twice over.

**UNIT — and this is the reported jerk.** The counter advances once per FRAME, so the
ease's wall-clock speed is whatever the frame pacing happens to be. It is armed on the
frame straight after `FormationMapHost._ready` costs ~60 ms; the swapchain has drained, so
Godot renders the next three frames in 2–3 ms each:

```
1134  67.6 ms   <- FormationMapHost._ready, camera still in TAKEOVER
1135  17.3 ms   ff=1  dpos=0.0512   <- the ease is armed HERE
1136   3.1 ms   ff=2  dpos=0.1522
1137   2.6 ms   ff=3  dpos=0.2484
1138   2.8 ms   ff=4  dpos=0.3370
1139  11.3 ms   ff=5  dpos=0.4152
```

Five of eighteen steps — 1.20 of 6.70 units — in 37 ms instead of 83. Over three idle-box
runs the ease **LEADS the wall clock by 43–58 ms of a 300 ms glide (14–20 %)**, peaking at
**2.0–4.5x** its intended speed, always at step 1 or 2. Every per-frame step stays a clean
cosine throughout, which is exactly why round 1's verdict could not see it.

**LENGTH — and this is "the camera moves too fast".** 18 frames is a good SINGLE-TILE step
and `follow_ease_frames`' own doc says so ("18 frames ≈ 0.30 s cosine-eased single-tile
step"). The handoff is **6.699 units**, so the same 18 frames run it at ~27 u/s where a
tile step runs at ~3.

### The comparison the report asked for, answered

"How does it compare to the end of Magic City battle" is a question about two **different
mechanisms**, and that is the whole answer:

| | entry (before) | exit |
|---|---|---|
| driver | `PlayerCamera._execute_cursor_follow` | `ScenarioCameraDirector`'s `{19}` lerp |
| clock | `_follow_frame`, **frames** | `_cam_lerp_elapsed_s`, **continuous seconds** |
| length | `follow_ease_frames` = 18 (0.30 s) | the script's authored `Time` operand |
| the victory beat's value | — | `Time=48` ticks = **0.80 s** |

The cinematic rig has been seconds-driven for years and says why on `_cam_lerp_elapsed_s`
("so the visual update runs per host frame regardless of refresh rate — otherwise the
camera holds its pose between ticks and the motion stutters"). **The exit the report likes
already solved this; the entry never had.** So `camera.handoff_ease_seconds` (ADR-0068,
Camera tab) defaults to **0.80** — the ROM's own number for the move that was named as the
good one — and `ease_onto` advances on the rig's unscaled wall clock.

`follow_cursor` is **untouched and still counts frames.** A tile step is the cursor's own
hop, and `TurnBeat` reads `follow_ease_frames` at arm time as a frame countdown to ride it.
Two motions, two clocks, two knobs.

### And the datum had to follow the body, which the ARC LENGTH is how we found out

`_datum_blend_frame` was its own 16-frame counter borrowed from `_return_total`. That read
identically to the body ease only while the body ease was also ~18 frames — so lengthening
the body **created** the misalignment the handoff had guessed at. At 0.80 s the datum's
1.383 units of vertical framing all land inside the first third of the glide: the camera
goes **UP and then ALONG** instead of straight, and the trace says so as distance travelled
— **7.509 units to reach a point 6.699 units away.**

Sharing `handoff_ease_seconds` puts it back to 6.686 and makes the entry ONE curve of one
length starting on one frame, which is what `_returning` has always been on the exit.

### Measured — Gariland (root 9), idle box, three runs per arm

| | before | after |
|---|---|---|
| clock lag | ease **LEADS** by 43–58 ms of 300 (**14–20 %**) | tracks to 13–24 ms of 800 (**2–3 %**) |
| peak wall-clock velocity | **2.03 – 4.45x** mean | **1.62 – 1.76x** (the cosine's own ratio) |
| arc length | 6.699 units (two clocks aligned by accident) | **6.686** |
| ease spans | body 18 frames, datum 16 | **identical, same start frame** |
| dead beat | 6 frames / 158–172 ms | 6 frames / 158–188 ms (unchanged, deliberately) |

**BOTH handoff paths, and they are the same beat.** `SKIPPB=1` arms
`navigator.skip_pre_battle`, where `run_pre_battle` returns before the loop and the cursor
and `run_combat` builds both instead — different surrounding work, same seat and same glide:
dead beat 162 ms, move 815 ms / 6.687 units, clock lag 2 %, peak/mean 1.69x. Worth having as
a number rather than as an inference from "it is the same call", because it is the path a
`Seek here` takes and nothing else measures it.

⚠️ **The after-numbers survived a loaded box, and that is the strongest single result
here.** Three further runs landed while a stranger's suite held 9–15 Godot processes, one
of them with an **814 ms frame inside the window**. Arc length stayed 6.686 on all three,
clock lag 2–3 %, peak/mean 1.62–1.76x. On the frame-counted path that 814 ms frame is a
sustained over-speed burst; on the clock it is one honest step.

### The dead beat is named, priced, and deliberately left

6 frames / ~165 ms of revealed, motionless field between the retract ending and the
camera's first move — the largest thing in the window that no round-1 metric named. It is
**not** worth removing, and the reasoning is the same one that placed the residual there:

- ~115 ms of it is the two build hitches (`setup_gpu_simulator` ~48 ms,
  `FormationMapHost._ready` ~67 ms). **A frozen frame on a STATIC image is invisible** —
  nothing is moving, so a repeated frame is indistinguishable from a rendered one.
- Arming the glide earlier so it overlaps the build does not delete those hitches, it makes
  them VISIBLE, as judder in a moving image. The current ordering is the best placement
  available, exactly as round 1 concluded for a different reason.
- What is left is ~165 ms of dead air ahead of an 800 ms glide — 17 % of the beat. It reads
  as a beat, not as a stall. At the old 300 ms glide it was 35 %, which is part of why the
  same pause felt like a freeze.

Shrinking it further needs the UI3 host-build surgery that is already a separate ticket, or
moving the camera arm ahead of `_mount_formation_map_screen` — which changes what
`bind_map` reads at bind time (`GambitDeploymentPickerTest`, `FormationChangeJobConfirmTest`).

### What the film shows, and the one pop that is left

`FILM=<dir>` films the reveal as a strip of PNGs — the scene screenshots ITSELF, because
`grim` aimed at an off-screen window silently returns whatever is on the visible workspace
instead, which looks like a successful capture. The glide is smooth end to end and lands
framed on the leader.

🔴 **The one visible pop left in the window is not the camera.** The deployment HUD — the
roster portrait strip and the unit info panel — arrives over ~2 frames, coincident with
`FormationMapHost._ready`'s ~60 ms hitch. It is untouched by this work and pre-dates it. If
the report comes back a third time, that is the thing to look at, and it is the same UI3
host build the 55 ms residual lives in.

### The deepest fix, still not taken

The ROM does not glide here **at all**: scn 10's `{19}` at pc 33 poses the battle's opening
camera under the dim, and `{77}` retracts onto an already-framed field. Our seat is 6.7
units from that authored pose, so either the `{19}` interpretation or the leader placement
differs from the ROM's. Closing that gap would delete the dead beat AND the glide from the
visible window together. It is a real ticket and it is not this one.

### What is guarded

`PlayerCameraDatumEdgeTest` gains two arms, both seed-broken (21–22 of 24):

- **arm 8, the two clocks** — one 50 ms frame handed to `_execute_cursor_follow` must move
  the HANDOFF ease by its 50 ms share and a `follow_cursor` TILE STEP by one frame's worth.
  On trunk both answered the same, which is the defect stated as a number. Driven through
  the seam directly rather than by spinning a real hitch: that needs `Time.get_ticks_*`,
  which the charter reserves for `perf` (clause 14), and buys nothing.
- **arm 9, one curve** — after the same 50 ms the datum blend and the body glide are at the
  same point on the same cosine, and that point is `handoff_ease_seconds`', not a 16-frame
  counter's.

⚠️ `TEST_EASE_SECONDS` is 0.50 because **0.20 was measured flaky**. `_process` clamps its
unscaled delta to 0.1 s, so the worst legal FIRST frame of an ease is 100 ms — at 0.20 s
that is `t = 0.5`, which lands the datum at half strength and reds the "one frame in, still
small" arm on a slow boot. Arms 4 and 7 are frame-CAPPED now rather than frame-counted, and
the cap is far above 60 Hz on purpose: the loop breaks on arrival, so the cap bounds only
the failure path, and sizing it to 60 Hz would make a fast box fail a slow rig's test.

Still no `perf`-kind gate, for round 1's reasons — but note that the SHAPE metrics above
are the load-insensitive ones. Arc length and clock lag held across a 9–15-process box and
an 814 ms frame. If a gate is ever wanted here, those are the numbers to gate, not the
wall clock.

## Round 3 — the image was never static, and the protagonist was running at 2x

Round 2 closed with the dead beat **named, priced and deliberately left**, on one argument:

> *"~115 ms of it is the two build hitches … A frozen frame on a STATIC image is invisible —
> nothing is moving, so a repeated frame is indistinguishable from a rendered one."*

The report came back a third time — *"the jitter in the transition between 'story' and
'battle' is improved but still not solved… There's two kinds of stutters. Maybe it's not even
a performance thing?"* — and both halves of that sentence turned out to be right. There are
two, they are of different kinds, and **neither is a cost**.

### The instrument: trace what ADVANCED, not what it cost

`tools/probe_handoff_seq.gd` records, per rendered frame and per unit, the sprite-sequence
handle, the sprite frame counter behind it, the clock owner and the world position, and scores
the arms **against the clock owner** rather than the frame number. A frame-cost trace cannot
tell these two stutters apart — one is a single 60 ms frame and the other is a rate — and that
is exactly why `cost_ms` had already been read three times without finding either.

### Finding 5 — the image is NOT static through the dead beat

The deployed squad is SCENARIO-owned and idle-breathing for the whole window: **ten sprites,
every one advancing a frame on every rendered frame**. What the per-frame advance trace reads
across the two build hitches on trunk:

| frame | cost | sprite frames advanced (all ten units) |
|---|---|---|
| … | 16 ms | 1 |
| `setup_gpu_simulator` | **44 ms** | 1 |
| next | 3.8 ms | **2** |
| … | 16.7 ms | 1 |
| `_mount_formation_map_screen` | **61 ms** | 1 |
| next | 15.9 ms | **4** |

Hold, then snap — twice, on every sprite on screen at once, on the frame the field is
revealed. Round 2's premise was about the CAMERA being still and read that as the image being
still. The camera is one of the things in the frame.

A hitch is worse here than a plain freeze, because the VM's tick accumulator drains the
backlog on the following frame: the animation does not resume, it **jumps**.

### The fix: there is 6.5 seconds of black to spend

The intro holds a fully established `{76}` dim for ~6.5 s while `{78}` paints the victory
conditions over it, against ~100 ms of build. `ScenarioVM.screen_is_fully_dark()` is that
cover as a predicate and `NavigatorMain._prewarm_battle_under_the_dark` spends it.

Two seams make it possible, and they are the same cut — **what is shaped by the CAST versus
what is shaped by where the cast STANDS**:

- `_build_battle_machinery` — compose the teams, stand the loop up, distance field, GPU
  simulator. `boot_battle` loads each unit onto the GPU buffer *at its tile*, so it is the one
  step that would bake a mid-opener position; it stays behind at the normal time.
- `_build_command_surface` — the cursor rig and the formation map screen. Everything below it
  in `_enter_command_cursor` is the camera's.

Gated to the OPENER beat: the outro holds an identical black plate, and a prewarm there would
stand a `CombatLoop` up on the far side of the battle that just ended.

⚠️ `_battle_booted` replaces `_combat_loop == null` as "is the battle built". The prewarm
leaves a live `CombatLoop` with no battle in it, and the old test would have skipped the boot
outright on the direct-seek path. `_command_surface_seated` replaces `built_here` for the same
reason — the seat belongs to the build (ADR-0265 dec. 1 as amended), and the build can now
happen a beat before the entry.

#### Measured — Gariland (root 9), idle box, three runs per arm

| | before | after |
|---|---|---|
| dead beat | 6 frames / 154–158 ms | **2 frames / 32 ms** |
| worst frame in the revealed window | 58.7–61.9 ms | none — it is under the black plate |
| reveal-window sprite cadence | hold 44/61 ms, snap 2 and 4 frames | **unbroken 1 frame per frame, worst 23 ms** |
| arc length | 6.686–6.687 | 6.686–6.687 (unchanged) |
| clock lag | 2–3 % | **1 %** |
| peak/mean velocity | 1.64–1.68x | 1.65–1.76x (the cosine's own ratio) |

### Finding 6 — the protagonist's idle ran at exactly 2x, and halved at the handoff

The second stutter is not a cost at all, which is the user's own intuition arriving as a
number. `_units_by_id` is keyed by EVENT ID, and an event id is not a unit: the deployed
leader answers to his squad id `0x78` **and** to the `0x01` protagonist alias.
`ScenarioVM._advance_scenario_anim` walked `keys()` advancing as it went, so that one body
took two sprite frames per tick.

Measured at Gariland — **Ramza 120.1 sprite-frames/s against the other nine units' 60.1**,
through the whole opener and the whole Deployment hold, then **halved to ~60 at `_go_live`**
when the CombatLoop's single pump took over. A 2x animation-rate step on the one sprite the
player is watching, landing exactly on the story→battle boundary.

🔴 **ADR-0083 does not cover this, and that is why it went unseen for so long.** Its invariant
is one OWNER per unit, and both of these advances came from the *same* owner. The rule is the
other one: **one DECISION per body per tick.** The two gates are now collected across every id
that names a body and the advance applied once — collecting rather than first-key-wins,
because the registry is insertion-ordered with the `0x78`+ ids ahead of the alias, so
first-key-wins would walk past a `{11}` paint mark left on `0x01`. That leak was real: the
control run shows the painted body advancing one frame through a hold it should have sat out.

`NavigatorDeployedIdlePumpTest` gains four assertions on its existing process. Against trunk's
`ScenarioVM.gd` they read leader=60 / peer=30 plus the paint leak.

### What Lead 1 turned out NOT to be

The handoff's leading hypothesis was that `AnimationClock` runs 45 frames/s in delta mode
(`FRAME_DURATION = 1/45`) against 60 in tick mode, and that the handoff therefore changes the
rate. **Dead, and worth saying loudly because the two numbers still look wrong on
inspection.** The scenario→battle handoff is `SCENARIO → COMBAT` and BOTH are tick mode:
`ScenarioVM` pumps `advance_frame()` once per 60 Hz VM tick, `CombatLoop` once per 60 Hz GPU
tick. The 45 belongs to `owner == SELF` (free-roam), which no unit is on this path. Measured:
SCENARIO 60.0–60.2/s, and the flip frame itself advances **0** sprite frames for every unit —
there is no phase to lose, because neither host pump carries an accumulator.

### Still open, and both are observations rather than defects

- One scenario unit idles at **40.6/s** rather than 60 (it holds a non-looping SEQ that
  completes and pauses). Consistent across runs; not on the transition path.
- In live combat the per-unit rate spreads **58.7–92.7/s**, stable across runs, and the units
  above 60 are the ones on SEQ 31/33 advancing two frames per rendered frame. The obvious
  candidate is `_get_unit_anim_speed` returning `VERTICAL_MOVE_SEQ_SPEED = 2` for a cliff move,
  which Gariland's roofs would give plenty of — **but that is a candidate, not a measurement:
  nothing in this trace records `is_cliff_move`, so the mechanism is unconfirmed.** Not on the
  handoff path either way; the flip frame itself is clean.

### Trap — the film contaminates the thing it films

`FILM=` saves a PNG every third frame, and `get_image()` + `save_png` costs ~10 ms plus a GPU
readback. A filmed run reports a metronomic **46 ms / 3 ms / 2 ms** three-frame cadence for the
whole glide, a 278 ms dead beat and a peak velocity of **24.65x** mean. All three are the
instrument. The unfilmed control on the same tree reads 16 ms flat, 155 ms and 1.65x. Never
read a timing number off a filmed run.

⚠️ `probe_ready_freeze.gd` also had to re-anchor. It stopped 180 frames after `loop_up`, and
the prewarm moves `loop_up` hundreds of frames earlier — so it cut the trace off before the
retract and reported **NO SUBJECT**, which reads like a broken game rather than a mis-aimed
probe. It anchors on the reveal itself now: a dim went fully up, and has now fully cleared,
with a battle standing behind it.
