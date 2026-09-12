# GPU Arena performance — living document

**This file is the durable artifact for combat performance work.** It is the single source
of truth for what is wrong, what each item is worth, and what is done. Start at
[`## Work list — the loop`](#work-list--the-loop) — that is the state of the effort and the
list to iterate. Everything above it is the standing diagnosis; everything below the Work
list is either supporting evidence or the chronological round log that produced it.

**Question.** GPUArena gets laggy once units close on each other and start attacking.
Is the bottleneck CPU or GPU? On a Ryzen 9 9900X (12C/24T) + RTX 5090 it should not be.

---

## Rig

| | |
|---|---|
| CPU | AMD Ryzen 9 9900X, 12C/24T |
| GPU | NVIDIA RTX 5090, 32 GB, driver 610.57.04 |
| RAM | 30 GB (⚠ 15 GB in use, **18 GB of swap in use** at session start) |
| Display | Dell S2417DG, 2560x1440 **@ 144 Hz**, Hyprland/Wayland, vrr off |
| Godot | 4.8 compositor fork (`4.8.dev.custom_build`), Forward+ |
| vsync | `project.godot` sets no vsync key → Godot default **Enabled** → frame budget **6.94 ms** |

## Instruments already in the tree (nothing new needed for round 1)

- **`PerfMonitor`** autoload (`src/debug/PerfMonitor.gd`) — per-frame sampler.
  Records real frame time, `TIME_PROCESS` (CPU main-thread script), `TIME_PHYSICS_PROCESS`,
  draw calls, objects-in-frame, node count, `combat_visuals` group size. Logs spikes over
  `debug.perf_spike_threshold_ms` (default **33 ms**) and prints a session summary on
  `DebugConfig.quit_requested` (i.e. on `--quit-after=`).
- **`CombatLoop` `[PERF #n]` report** (`src/gpu/CombatLoop.gd:664`) — every 3 s, gated on
  `debug.gpu_debug_enabled`, which the `--perf-debug` CLI flag sets. Buckets the tick:
  `GPU` (the `step_tick` while-loop incl. `_read_tick_columns`, projectiles, and
  per-unit `advance_frame`), `state` (`_check_state_changes` + `_handle_revives`),
  `visual` (`get_all_unit_states` + `update_visual_positions`), plus `delta`, effective
  fps, ticks-per-frame and a live unit-state histogram.
- **`PerfDebugPanel`** / **`PerfHUD`** — F3 overlay graph + corner readout (`debug.perf_hud_enabled`).

### The CPU-vs-GPU discriminator

> ❌ **CORRECTED (R29, correction 16). Both sentences below are wrong about the
> instrument, and the identity they set up cannot be evaluated.**
> `Performance.TIME_PROCESS` is **not** a per-frame value and is **not** script-only.
> `main/main.cpp` keeps `process_max = MAX(process_ticks, process_max)` and publishes it
> with `performance->set_process_time(...)` **inside the once-per-second block**, resetting
> it there — so the monitor is the **MAXIMUM `_process` duration over the last second,
> refreshed once a second** and held constant for the ~1 000 frames in between. And
> `process_ticks` brackets `main_loop->process()` **plus `NavigationServer::process()` plus
> `RenderingServer::sync()` plus `RenderingServer::draw()`** — the render submit and the
> wait on the previous frame's draw are inside it, so the identity below double-counts them.
> `PerfMonitor`'s `cpu_proc: mean=` line averages that per-second max over frames, and its
> `est_other_mean` is the clamped result of the invalid subtraction: it prints **0.00 ms in
> every run in this document**. A 35 s static arena arm in R29 reported
> `frame_time: mean=0.66ms` next to `cpu_proc: mean=14.28ms` — 22× the whole frame.
> **Use the R29 head/tail bracket instead** (Round 29): `PerfMonitor` at
> `process_priority = -100` stamps the head, a probe at `1000` stamps the tail, and the
> difference is the real per-frame script pass.

Godot's `TIME_PROCESS` is main-thread **script** time only. So per frame:

```
frame_time  ≈  TIME_PROCESS + TIME_PHYSICS_PROCESS + (render submit + GPU wait + vsync wait)
```

- `TIME_PROCESS` climbing with the engagement ⇒ **CPU/GDScript** bound.
- `TIME_PROCESS` flat but `frame_time` climbing, with `nvidia-smi` util pinned ⇒ **GPU** bound.
- Both flat and `frame_time` at ~6.94 ms ⇒ vsync, not a problem.
- Neither, with `nvidia-smi` util low ⇒ a **stall** (readback sync, shader compile, allocation).

⚠ The compute sim is dispatched *and read back* on the main thread inside `_process`, so a
GPU-side stall bills to `TIME_PROCESS` too — the `[PERF]` `GPU:` bucket is what separates
"the compute dispatch/readback is slow" from "the rest of the frame is slow".

## Auto-deploy run command

> ❌ **CORRECTED (R24, F27).** This section used to say `config/tune_overrides.json`
> "already carries `simulation.skip_march: true`". **On `main` it carries `false`** — the key
> is `AUTOSAVE`-bound through `Tune`, so any editor session flips it and the flip gets
> committed. With it false the arena takes the **strategy phase**, the auto-place branch does
> not run, and a 60 s run reports `Units: IDLE=15, WALKING=1` throughout: **plausible-looking
> `[PERF]` numbers for a scene in which combat never happens.** Do not rely on the JSON.

**Pass `--skip-strategy` explicitly.** It forces `DebugConfig.skip_strategy_phase` regardless
of the JSON, and the arena takes `_place_units_at_defaults()` → `_start_battle_from_roster()`.
`--combat-autostart` is the "auto deploy" switch: it flips `combat_active = true`.

```bash
# from the package root
godot --path . res://assets/scenes/GPUArena.tscn -- \
  --combat-autostart --skip-strategy --perf-debug --combat-seed=<N> --quit-after=<sec>

# ...and to PUSH it (W7/R26). N is per TEAM, so the cast is 2N; omit for the shipped 13.
godot --path . res://assets/scenes/GPUArena.tscn -- \
  --combat-autostart --skip-strategy --perf-debug --combat-seed=424242 \
  --stress-units=32 --quit-after=25
```

(Headful — never `--headless`, per CLAUDE.md.)

**Check the fixture engaged before believing any number**: `[PERF #2]` must read
`Units: 12/16 alive: ACTING=9, WALKING=4, IDLE=3` at seed 424242. Anything with `IDLE=15` is the empty
scene. The battle reaches VICTORY at tick ~800, so a 60 s run yields **4** reports, not 32.

---

---

# STATE OF PLAY — read this first

*Everything below this block is the chronological round log, including hypotheses that
were later refuted. This section is what currently holds.*

## The answer: CPU, and it is not close

| | per frame, heavy combat |
|---|---|
| **GPU** (Godot's own `--gpu-profile`, 40 samples) | **0.16 ms** |
| **CPU** | **~15 ms** |

~100×. GPU utilization never exceeded 25 %, power never exceeded 93 W of 600 W. No
GPU-side change will help. The `step` bucket — the actual compute submit+sync — is
**0.38 ms/frame**, 6 % of the combat loop that is named after it.

**This is the one headline that survived every re-measurement**, including R26's stress
fixture: at **80 units — six times the shipped cast** — `step` is 1.88 ms of a 28.95 ms
`CombatLoop`, still under 7 %. The CPU/GPU verdict does not move with the cast size. (The
`~15 ms` CPU figure itself is an `-O0` number; see the R26 curve below for what it is now.)

## Where the frame goes (144 Hz budget = 6.94 ms)

⚠ **These are `-O0` numbers and they are stale three times over (R24, R25).** They were taken
on the old engine, before W1 and PR #883 landed, and through a frame-rate cap. On the shipped
engine, measured genuinely unthrottled, the same fixture's heaviest frame is **1.3 ms — 745 fps,
19 % of the 6.94 ms budget** (R26). ⚠ R25's own replacement figure — 2.08 ms / 482 fps — was
**itself the 500 fps cap** (R26, correction 11); this is the third setting to bite. Kept as the
audit trail of how the effort started. **The "budget exhausted at five live units" claim below
is an artifact of the unoptimized engine and is not true of the engine that ships: R26 pushed
the same fixture to 48 units and never crossed the budget.**

Measured uncapped, overlay hidden, seed 424242, reproduced across three runs:

| game state | ms/frame | fps |
|---|---|---|
| paused — static scene, 16 units, full map | **2.29** | 435 |
| combat, late (most units dead) | 5.7 | 176 |
| combat, mid | 11.1 | 90 |
| **combat, heaviest (units converging + acting)** | **14.4** | **69** |
| *+ debug overlay when open (**W4** — no longer forced open)* | *+2.4* | |

Heavy-combat breakdown at tick 360:

```
11.10 ms  frame
 5.14 ms  CombatLoop   anim 2.6 · state 1.2 · visual 1.3 · edge/step/cols 0.6
 3.67 ms  combat-driven work outside CombatLoop's own timers (F19)
 2.29 ms  static baseline
```

**The engine, map, renderer and units are cheap (2.29 ms — a third of budget). The entire
deficit arrives with combat.** That is why it goes bad exactly when units converge.

## It breaks at 64 units, and the shipped cast is 13 (R26)

**Measured with the stress fixture** — `GPUArena --stress-units=N` pads each team to `N` by
cloning the cast it already has, so the unit count is the independent variable (**W7**).
Seed 424242, overlay closed, `misc:render_unfocused_fps = 2000`, 2 interleaved reps per arm,
25 s each. Each column is the **worst 3-second `[PERF]` window** that arm ever produced.

| cast | 13 (shipped) | 16 | 32 | **48** | **64** | 80 | 96 |
|---|---|---|---|---|---|---|---|
| worst ms/frame | **1.3** | 1.5 | 2.6 | **3.9** | **7.6** | 52.8 | 29.6 |
| fps in that window | 745 | 682 | 392 | 258 | 132 | 19 | 34 |
| windows over 6.94 ms | 0/6 | 0/6 | 0/8 | **0/12** | **1/10** | 11/14 | 7/16 |

**The 144 Hz budget survives 48 units and first breaks at 64** — five times the shipped cast.
**R29 restates this for the game's real host: 63 units.** Every column below came from
`GPUArena`; `NavigatorMain`'s own per-frame work — the thing that shifts the intercept — was
measured at **+0.05 ms**, against an arena control whose own three arms span 0.069 ms
(**W10**). The choice of host costs less than the noise.
Below 48 the fixture is nowhere near the budget (3.9 ms of 6.94 at nearly four times the real
cast); above 64 it does not degrade, it collapses. **The curve is a cliff, not a slope**, and
the edge of the cliff is the **16.67 ms tick interval**, not the 6.94 ms budget — Round 26.

> ### ❌ The claim this section used to make, withdrawn
>
> It read *"it scales at ~1 ms per live unit"*, fitted `ms/frame ≈ 0.97 × live_units + 2.50`
> (R18), and concluded **"the 144 Hz budget is exhausted at about five live units."** That was
> measured on the `optimize=none` engine and before W1. On the shipped engine the same fixture
> costs **≈ 0.07 ms per unit** between 13 and 48 units on the worst-window series
> ((3.9 − 1.3) ÷ 35) — **thirteen times shallower** — and the budget holds to 64.
> Every *reaches a player?* judgement in the Work list below was originally made against a
> slope 16× too steep.

## Work list — the loop

**This table is the state of the effort.** It replaces the old *"ranked by measured value"*
summary: the same items, ordered by **what to do next** rather than by raw milliseconds,
each carrying a status so a session can pick up where the last one stopped. **The `W`
numbers are stable identity, not position** — a loop takes the first actionable row in
**table order**, which is not the same as ascending `W`. Per-item detail
is in the subsections below; the round log further down is the audit trail behind them.

> **Rank by work removed, not by milliseconds saved.** Fixes that make the same work cheaper
> (an engine rebuild) die at this machine's edge; fixes that **delete work** (W1's 16 × 99
> dictionaries, W2's uncached scans) generalise to every build, every machine, every player.
> That is what the *reaches a player?* column is for — and it is why the two items with the
> largest measured milliseconds, W3 and W4, are not at the top of this list. Say which of the
> two kinds a proposed fix is.

**Statuses.** `TODO` — specified, ready to implement. `DIAGNOSE` — not understood yet, the
deliverable is a measurement rather than a fix. `DOING` — claimed by a live session.
`PARTIAL` — some of it landed, the rest is still open. `DONE` — landed and proven with an
after-number. `REFUTED` — attempted, the predicted win did not materialise; kept on the list,
not deleted. `DEFERRED` — consciously not now, with the reason.

| # | item | status | measured before | expected after | reaches a player? |
|---|---|---|---|---|---|
| **W1** | `_check_state_changes()` and `GPUVisualBridge` share one 101-field snapshot build | **`DONE`** (R22) | `state` **1.73 ms** | `state` **0.77 ms** — **−0.96 ms**, and **−1.50 ms** across the loop | **yes** |
| **W2** | `AnimationFrameCalculator` re-scans the opcode array ~23 000×/s | **`REFUTED`** (R25) — built, proven equivalent, measured | `anim` **0.052 ms/frame** unthrottled | predicted −0.82, **measured −0.014 ms** | yes, but the win is noise |
| **W11** | the swing/hit SFX play spent **99.8 % of itself waiting on `_audio_mutex`**, because the reap's per-UNIT voice veto never cleared and un-reaped one-shot sessions were sequenced forever ([#933](https://github.com/timbermania/fft-monorepo/issues/933)) | **`DONE`** (R28) — `ONE_SHOT_SILENCE_SUBS`, a narrower second path past the veto | `sfx_play` **27.0–39.0 ms/call** at 80 units, of which `lock` was **99.8 %**; 240–355 live sessions | **`sfx_play` → 0.25–0.35 ms** and sessions → ≤23, on 4 interleaved reps (F45); 3 of 4 baselines degraded, **all 4 fixed arms bounded** | headroom only — no effect at the shipped cast, where the lane never packs |
| **W12** | `_update_unit_animation` re-fetched the **FULL 101-field snapshot** once per `STATE_CHANGED` event — the cost W1 took off the per-frame path, still paid per event ([#934](https://github.com/timbermania/fft-monorepo/issues/934)) | **`DONE`** (R27) | **0.18 ms/event** at 32 slots, **0.36–1.39** at 80 (R27/F37) | **the fetch is gone** — the caller hands down the hot row it already holds; one full build per event deleted, 58–178 events per 3 s window at 80 units | yes |
| **W9** | the per-tick `_check_state_changes` rebuilds 39 fields for **every slot**, and its gate opens if **any** unit moved | **`REFUTED`** (R27) — premise measured, not built | `chk` **0.01 ms/frame** at 13 units, **13.24** at 80 (R26) | the gate does **not** open more often with N (5–40 % flat), ~**1 unit** moves per open, and the rebuild is **20 %** of the call — **apply is 75 %** (F34, F35) | the cliff was real; it is **W11**, not this |
| **W6** | `CombatLoop`'s tick catch-up loop is unbounded. ⚠ **TWO loops, not one** (correction 19): the combat drain at `654` and a second at `604` inside `if victory_achieved:`, on the same accumulator | **`DONE`** (R31) — **RULED: clamp.** The sim runs *slow* under load rather than catching up | `tpf` 0.1 at 13 units, 3.2 at 80 (R26) — but **3.7–5.1 → 0.1–0.2 once W11 landed** (F46) | the **delta** is clamped, in **REAL** seconds (`max_catchup_real_s`, 1.0), at the one place both drains draw from — not the loop's iterations, which would have destroyed ADR-0239's remainder and red four `SIM_TIME_SCALE := 40.0` proofs. `CombatLoopCatchupClampTest`, counted work, every arm against a ceiling-lifted control | **yes, past the 16.67 ms tick interval** |
| **W7** | **build a stress fixture** and find where the budget actually breaks | **`DONE`** (R26) | arena at 13 units, never pushed | **breaks at 64 units**; 48 fits in budget at 3.9 ms | **it decided it: there is headroom, and a cliff** |
| **W10** | the same curve on the **navigator's** host, not the arena's | **`DONE`** (R29) — the deliverable was a measurement | never measured | **the intercept is ≈ 0**: outside-`CombatLoop` is **0.90 ms** on `NavigatorMain`'s own Gariland battle vs **0.85 ms** on the arena's — a **+0.05 ms** gap, *smaller than the arena's own rep-to-rep spread* (0.82–0.89 over 3 arms). Breaking point restates to **63 units**, not 64 | **it decided it: the arena's numbers transfer** |
| **W3** | the engine binary is built `optimize=none` | **`DONE`** (R24) — built, adopted **and measured** | `CombatLoop` 2.32 ms, frame 7.4 ms on `-O0` | **0.74 ms and 6.1 ms** — 3.1–4.5× on script buckets, **1.13× on GPU submit**, 1.21× on the frame (R24) | no — but it *is* your F5 |
| **W4** | the F3 overlay costs ~26 % fps **while open** | `PARTIAL` — the known ~46 % is **`DONE`** (R31); the ~54 % is `DIAGNOSE`. ⚠ **`--combat-autostart` could not open the overlay at all**, so every automated run since #866 measured the CLOSED arm | −26 % fps with it open (a **round-2** figure, `-O0` engine, never re-measured) | the graph redraw and the live label share one ~10 Hz gate; `PerfPanelThrottleTest`, counted work. The window's **update mode is REFUTED as a lever** — a viewport attached to an OS screen draws every frame regardless (`renderer_viewport.cpp:825`) | no — dev loop only |
| **W5** | F19's tick-driven work outside every bucket | **`DONE`** (R29) — attributed; the fix shapes are **W13** and **W14** | claimed 3.7 ms (`-O0`), then 1.82 ms (500 fps cap), then 5.34 ms in the R29 handoff (144 fps cap) | **0.82–0.89 ms**, and fully named: **0.46–0.49 ms engine/render submit/present** + **0.36–0.39 ms non-`CombatLoop` script**, of which the largest single item is a **debug panel that runs with the overlay closed** (W13). F19's sprite-repaint hypothesis is **REFUTED**: `Unit._process` + `CameraRelativeRenderer` = **0.071 ms/frame**, 5 % of the frame | no — it is 0.8 ms of a 6.94 ms budget |
| **W13** | `AudioBusMixerDebugPanel._process` meters every audio bus **every frame for the whole session**, overlay closed ([#955](https://github.com/timbermania/fft-monorepo/issues/955)). ⚠ **TWO causes, not one** (correction 17): `Node`'s `NOTIFICATION_READY` calls `set_process(true)` for any script defining `_process` **before `_ready`**, so `_build_ui`'s `set_process(false)` was inert; and `DebugDashboard.add_panel()` then calls `on_shown()` unconditionally at registration while `on_hidden()` **had no caller anywhere in the repo** | **`DONE`** (R30) | **0.064–0.103 ms/frame**, ~26 % of all non-`CombatLoop` script and the second-largest script cost in the frame after the combat loop itself | the gate went on **`BaseDebugPanel`**, not on the panel: `_notification` → `set_process(is_visible_in_tree())`. Of 41 subclasses **three** define `_process`, and the census only saw the one the arena instantiates — `ScenarioVMDebugPanel` repopulates a disassembly list every frame and never called `set_process` at all. `on_hidden()` deleted; **one** panel opts out (`ScenarioUnitSpriteOffsetDebugPanel`, whose `_process` re-applies sprite offsets to the live units). `DebugPanelProcessGateTest`, seed-proven | **yes — it ships and it is pure waste** |
| **W14** | `ScenarioDialogueBoxPool._sprite_billboard_anchor` calls `RenderingServer.global_shader_parameter_get("pixel_aspect")` ([#956](https://github.com/timbermania/fft-monorepo/issues/956)), which is **editor-only**: outside the editor it `ERR_FAIL_V_MSG`es, returns `null`, and prints an error + a 4-line GDScript backtrace **per open box per frame**. ⚠ **But `pixel_aspect` ships at 1.0** (correction 18), so the correction was **dead, not wrong** — no shipped frame moved either way | **`DONE`** (R30) | `TODO` (R29) | **35 790 calls in a 150 s navigator walk** (~239/s while a box is open); and the PAR correction the call feeds **silently never applies in the shipped build** | reads `PSXDisplay.live_par` — the mirror the addon keeps for exactly this trap. `DialogueBoxAnchorParTest` pins both halves: the stretch happens at PAR 1.5, and the anchor is **unmoved at 1.0** so the fix cannot be misread as a visual change. Seed-proven | **yes — a correctness bug, and the log; NOT a frame number** |
| **W8** | the regression witness — **counted work, not wall clock** | `DEFERRED` | nothing asserts the budget | a threshold per fix | keeps the wins |

### ⚠ Three caveats apply to every number in this document

1. ✅ **RESOLVED (R24) — and the ordering did NOT survive.** Everything up to round 23 was
   measured on the `optimize=none` engine; the optimized one went live on `$PATH` on
   2026-09-06 (R23). R24 re-took the breakdown on both binaries, interleaved, on one code
   state: script-heavy buckets scale **3.1–4.5×**, the GPU submit (`step`) **1.13×**, and the
   frame **1.21×**. **`anim` — W2's whole target — is now 0.214 ms**, so W2's predicted win
   rescales from −0.82 to **≈ −0.19 ms/frame** — and W2 was then built and **measured at
   −0.014 ms**, i.e. `REFUTED` (R25). ⚠ **R24's own absolutes were taken through a frame-rate
   cap and R25 withdraws them**: unthrottled, the heaviest frame is **2.08 ms / 482 fps**, not
   6.08. R24's arm-to-arm *ratios* stand. The absolutes in the table below are the old `-O0`
   ones, kept only as the "measured before" they claim to be.
2. **Most of it was measured with the debug overlay open**, which inflates buckets it has no
   business touching: `state` **+28 %**, `GPU` **+33 %**, `total` **+25 %** (W4). This Work
   list restates figures **overlay-closed** wherever a closed measurement exists. The round
   log below does **not** — treat its absolutes as roughly a quarter high.
3. **Taken 23 commits before `2c9ac86ab`**, i.e. before the GPU arena dropped the legacy
   `CombatUI` (PR #883). Ratios should survive that; absolutes may not.

---

### W1 — one 101-field snapshot, built every ticking frame, for dead units and empty slots too

**Status:** `DONE` (R22, shape **B**)  · **Reaches every player**  · Measured **−1.50 ms/frame
of CombatLoop work**; the frame-time effect is **not resolvable on a contended box**

| bucket | A: full 101 | B: lean 39 | Δ |
|---|---|---|---|
| `state` (`_check_state_changes` + `_handle_revives`) | 1.730 ms | **0.768 ms** | **−0.96** |
| `visual` (`get_all_unit_states` + `update_visual_positions`) | 0.859 ms | **0.486 ms** | **−0.37** |
| **CombatLoop total** | **4.332 ms** | **2.830 ms** | **−1.50** |
| real frame time (`delta`) | 13.81 ms | 13.26 ms | −0.55 ⚠ |

A/B/A/B interleaved, seed 424242, 60 s arms, 32 `[PERF]` reports each, `render_unfocused_fps`
raised to 144. The arms differ by **one line-exact flip** of which builder the two per-frame
callers use — not a branch diff — so nothing else can move.

⚠ **The frame-time row is not a result.** Its two reps disagree by more than the effect:
**+0.11 ms** and **−1.21 ms**. The box carried chromium at ~6 of 24 cores throughout and the
load climbed 12.6 → 16.4 across the run, with two other sessions starting suites mid-measure.
At that contention the frame is not bound by `CombatLoop`'s CPU work, so this rig cannot
resolve whether removing 1.5 ms of it moves fps. **The bucket rows survive that** — they are
self-timed spans *inside* the frame, and both reps agree on them to within 0.12 ms.

**So W1 delivers what this list ranks on — work removed, −1.50 ms, reproduced — and does NOT
yet demonstrate an fps win.** Re-take `delta` on a quiet box. It is worth doing together with
**W3**: on an `optimize=none` engine the ~9 ms *outside* `CombatLoop` is inflated too, so one
clean re-measure on the optimized binary answers both questions at once.

Prediction check: R21 predicted −1.43 ms at a 31-field union, revised to ~−1.1 ms once the
union turned out to be 39. **Measured −1.50 ms** — better than either, because the `visual`
bucket improved as well (a 39-key Dictionary is cheaper for its consumer to read, not just
cheaper to build).

The per-frame path now takes `get_battle_unit_states_hot()` — **39 of the record's 101
fields** (`GPUCombatPacker.SNAPSHOT_HOT_UNION`) — on both callers, sharing one version cache
so whichever runs first pays the build and the other is free. The full 101-field
`get_all_unit_states()` is unchanged and still serves every cold and test caller.

Three instruments keep the union honest, because its failure mode is silent: the pre-flight
guard `tools/check_snapshot_union.py` (covers the code, and **refuses** unregistered
computed-key reads), `GPULeanColumnReadTest` arm 2 (62,400 value comparisons), and
`GPUSnapshotUnionTest` (a seeded battle with every non-union field poisoned — covers the
run). **The union was wrong three more times after R21 and the last two corrections came
from those instruments, not from reading.** Full account in **Round 22**.

`gpu_state_reader.get_all_unit_states()` builds **16 × 101 string-keyed Dictionary fields**
every ticking frame — for dead units and empty roster slots as well. It is the one cost that
**never decays as units die** (F22), so it is worst exactly where the frame budget is
tightest.

Two callers sit on the per-frame hot path:

```
src/gpu/CombatLoop.gd:657   vis_states = gpu_state_reader.get_all_unit_states()   → GPUVisualBridge
src/gpu/CombatLoop.gd:844   _all_states.assign(...)                               → _check_state_changes
```

> ⚠ **The obvious fix saves nothing.** Those two callers **share one cache**
> (`_rb_states_cache` / `_rb_states_version`, `GPUBatchSimulator.gd:1164`). The first caller
> after a version bump pays the full 101-field build; every later caller that frame is free.
> Convert `_check_state_changes()` alone and the visual bridge simply becomes the one that
> pays, for a net **~0 ms**. **Both hot-path consumers must move together** or the cost does
> not budge.

#### ❌ CORRECTIONS (R21, then R22) — the union is **39 of 101**, not 15 of 99, across **five** consumers

Round 20 sized this item by grepping field reads in **two** files. Re-derived by walking the
call graph out of `_check_state_changes()`, the snapshot dictionary is consumed by **five**:

| consumer | how it receives the dict | fields read |
|---|---|---|
| `GPUCombatInterpreter.interpret()` | `_check_state_changes` passes `_all_states[i]` | 10 |
| `GPUVisualBridge` | `CombatLoop.gd:657` `vis_states`, plus `update_facing_toward_target(_, _, _all_states)` | 10 |
| **`CombatLoop`'s own `_apply_*` pump** | `_apply_combat_event(i, state, ev)` → 8 handlers | **21** |
| **`ProjectileManager`** | `spawn_from_gpu(i, state, _all_states)` and `update(tick, _all_states)` | **7** |
| **`CinematicDebugProbe`** | `probe(_battle_state, _all_states, …)`, `on_cinematic_began/ended` | **8** |
| **union** | | **31** |

```
anim_flags anim_frame aoe_pending_caster aoe_pending_fire_frame cast_step_id cast_target
cast_timer casting_ability_id cinematic_timer damage_amount damage_frame damage_target
dbg_conflict_blocked decision_meta flags hp level move_total_ticks mp paused
pending_heal_amount pending_heal_target pos_x pos_z projectile_frame state target team
timer total_frames weapon_type
```

The bottom three rows are the ones round 20 never looked at. `_apply_state_changed` alone
reads `pos_x, pos_z, timer, casting_ability_id, cast_timer`; `_apply_hp_change` reads
`anim_frame, projectile_frame, damage_target, pending_heal_target`;
`_process_thrash_detection` reads `decision_meta`.

Two smaller corrections in the same sweep:

- **`SNAPSHOT_FIELDS` has 101 keys, not 99** (`GPUCombatPacker.gd`; `UNIT_SIZE = 101`). Every
  "16 × 99 = 1 584" in the round log below is really **16 × 101 = 1 616**. The conclusions
  do not move; the arithmetic does.
- **Round 20's access-pattern check counted a spelling, not a field.** Its fourth bracket
  read, `state["word"]`, is `EffectKeyframeInspector.gd:1582` — the *effect studio's*
  keyframe dictionary, not a GPU unit snapshot. `word` is not in `SNAPSHOT_FIELDS` at all,
  and that site **mutates** it (`state["word"] = …`), which the check's "nothing mutates the
  dictionary" conclusion would have wrongly covered. The genuine bracket reads on a unit
  snapshot are `pos_x`/`pos_z` (`GPUVisualBridge`, 4 sites) and two cold debug prints
  (`CombatLoop.gd:710`, `:1994`). Nothing iterates the dictionary's keys — **that half of
  the check survives.**

**What the correction costs.** `read_unit_column()` measured **62 µs for 5 columns**
(~12 µs each) against **1 800 µs** for the dict build. **31** columns ≈ **372 µs**, so the
expected win falls from −1.6 ms to **≈ −1.43 ms**. Still the largest item on this list, and
still flat across the battle.

#### ⚠ The fix SHAPE is now an open decision — see `## Open`

Round 20 pre-decided "move both hot consumers onto `read_unit_column()`" while believing the
union was 15 fields in 2 files. At 31 fields across 5 files that shape is materially bigger,
and a second shape now competes with it:

| | shape | files | expected | failure mode if a field is missed |
|---|---|---|---|---|
| **A** | **columns, as round 20 specified** — the hot path passes `PackedInt32Array` columns, no dictionary | 5 (`CombatLoop` + all 4 consumers, incl. every `_apply_*` signature) | **−1.43 ms** | **loud** — the dictionaries stop existing, so a missed read is a parse/type error |
| **B** | **lean dictionary** — every signature unchanged; `get_battle_unit_states()` builds from a declared 31-key union instead of all 101 | 1 (`GPUBatchSimulator`) + the union constant | **−1.25 ms** (87 % of A) | **silent** — `state.get("x", default)` quietly returns the default; only `state["x"]` raises |

B buys 87 % of A's win for roughly a tenth of the blast radius, and trades a loud failure
mode for a silent one. That silent mode is closable at test cost only (build both forms in a
seeded battle and assert the emitted events and visual positions are identical), which is
the characterization test this item needs anyway.

**Not decided here.** Narrowing A to B changes what the item delivers, so it is the user's
call, not a session's.

**Invariant to protect (either shape):** state transitions must be bit-identical.
Characterization test first — same seed, same tick, same state dump — then refactor under it.

---

### W2 — `AnimationFrameCalculator` re-scans the opcode array ~23 000 times a second

**Status:** `TODO`  · **Reaches every player**  · Expected `anim` **2.67 → ~1.85 ms/tick**

`addons/exmateria_sprite_rig/sequence/AnimationFrameCalculator.gd` does **four uncached
linear scans of the opcode array per playback per tick** — 6 playbacks × 16 units × 60
ticks/s ≈ **23 000 scans/s**. All four are pure functions of `(anim_id, sequences)`, so they
are memoisable as-is.

**Safety (checked).** `sequences` is `UnitAnimationSet.type1_seq`, sourced from
`AnimationDatabase`'s static `_json_cache`. **No `type1_seq[...] =` assignment exists anywhere
in `src/` or `addons/`** — the opcode dictionaries are never mutated after load, so a memo
cannot go stale through mutation.

> ⚠ **The hazard is `addons/exmateria_sprite_rig/sequence/AnimationDatabase.gd:82` —
> `_json_cache.clear()`.** A reload seam exists, so the memo table **must** be invalidated on
> that same call, or a post-reload lookup answers from the previous corpus. Cheap to handle,
> easy to miss.

**Invariant to protect:** not a single animation frame may change. Characterization test
first, then memoise. Files touched: 2 (`AnimationFrameCalculator`, plus the invalidation hook
in `AnimationDatabase`).

**Note:** this cost is partly self-mitigating — it scales with live playbacks, so it decays as
units die. W1 does not. That is why W1 goes first despite a similar headline number.

---

### W11 — the swing SFX plays synchronously on the tick path, and it is the cliff

**Ticket:** [#933](https://github.com/timbermania/fft-monorepo/issues/933)  ·
**Status:** `TODO`  · **Reaches every player, every attack**  · Measured **7.01 → 1.89 ms/frame
at 80 units** with one cue suppressed (R27/F38) — **3.8×**, the largest single effect in this
document. **0.27–0.47 ms per attack at the shipped 13-unit cast**, where the frame absorbs it.

`_start_attack_animation` ends with `SfxRouter.play_system(swing_slug)`. That call is on the
**main thread, inside the tick loop**, four frames deep: gated `_check_state_changes` → apply
`STATE_CHANGED` → `_update_unit_animation` → `translate` → the ACTING routing. Its cost is
**0.47 ms when the sound engine is idle and 27.8 ms when it is carrying ~130 live sessions**,
and the session count is driven by exactly one thing: how many attacks the battle just started.
That feedback — more units → more attacks/second → more live sessions → a slower play call →
slower frames → more ticks per frame (W6) → more attacks applied per frame — is why R26 saw the
budget *collapse* at 64 units rather than degrade.

> ❌ **CORRECTED (R28, correction 15). The two mechanisms this entry used to name are BOTH
> false.** They were read from the source and never timed. Timed (R28/F39): the bank load is
> **0.087 ms of a 25.7 ms call — 0.3 %** — and `_pick_unit` is **not on this path**
> (`play_one_shot` routes to `_pick_event_unit`, a 2-element walk with no reap in it). The
> two candidate fixes they justified are worth 0.3 % and 0.1 % respectively.

**What it actually is** (R28, F39–F42 — measured, 2 interleaved reps):

1. **99.8 % of the call is `_audio_mutex.lock()`.** `lock` grows 0.47 → 25.67 ms/call as
   sessions go 15 → 240; `load` and `bind` are flat across that whole range.
2. The thread it waits on is `_scheduler_main`, whose hold reaches **31.5 ms**. The
   O(sessions) reap inside that hold is **0.16 %** of it. The cost is **~32 µs per sequencer
   entity per sub** — flat across an 11× range — and the scheduler's budget is 4.16 ms/sub, so
   it goes permanently behind at **≈130 entities** and therefore permanently holds the mutex.
3. **The entity count is unbounded because the reap never fires.** `killed` is 71 in the first
   window and **0 in every window after**. `_reap_dead_sessions`' third condition,
   `if _unit_voice_count(u) > 0: continue`, asks a **per-UNIT** question to make a
   **per-SESSION** decision: all one-shot casts pack onto `MAX_EVENT_UNITS = 2` cores, so one
   audible cast vetoes reaping every other session on that core. It accounts for **99.5 %** of
   all reap skips. An un-reaped session stays linked into `unit["list"]` and is sequenced
   forever.

**The fix the evidence points at** is making that audibility test per-session — the session
already records `last_slot_idx`, and `pool.voice_for_slot()` gives its voice pair. That is a
**reap policy change**, which the standing authorisation for this item explicitly excluded, so
R28 measured it and stopped.

> ⚠ **STOP AND ASK BEFORE BUILDING THIS.** Every candidate fix — cache the bank, reap harder,
> or get the call off the tick thread — is a change to **`exmateria-sound`**, whose parity
> contract (ADR-0085 and the FEDS capture rig) this document has no standing to rule on. The
> game-side alternative, deferring the cue to the frame boundary, changes *when a sound plays
> relative to the animation frame that triggers it*, which is a design decision about the thing
> the package exists to be faithful about. R27 measured it and filed it deliberately.

**Verify with the instrument, not the frame clock.** `--perf-debug` now prints
`_start_attack_animation (n calls): ... sfx_play=X ms/call` and `sfx engine: sessions=...`.
`sfx_play` at 80 units is the number to move; the frame time is contended on this box and W8's
ruling stands — assert counted work.

---

### W12 — the full 101-field snapshot, once per state change

**Ticket:** [#934](https://github.com/timbermania/fft-monorepo/issues/934)  ·
**Status:** **`DONE`** (R27)  · **Reaches every player**  · Was **0.18 ms/event at 32 slots,
0.36–1.39 ms at 80** (R27/F37); the fetch no longer happens

`_update_unit_animation` opens with `gpu_state_reader.get_all_unit_states()` — the **full 101
field** snapshot for every slot — to read, in the end, `casting_ability_id`. That is F22's cost,
which W1 removed from the per-frame path, still being paid on the per-event path: the caller
(`_check_state_changes`) is holding `_all_states[i]` from the *hot* 39-field snapshot at that
moment, and `casting_ability_id` is already in `SNAPSHOT_HOT_UNION`.

**Built (R27).** `_update_unit_animation` now takes the caller's snapshot row as a parameter.
`_apply_state_changed` hands it `_all_states[i]` — the hot row it is already holding, same
`_battle_version`, so this is not a staleness trade; `_clear_spell_cast_active`, the one other
call site, hands down the row it had already fetched for its own `state` read. **Verified by
counted work, not wall clock (W8):** the `[PERF]` line lost its `full_snapshot=` column because
there is no fetch left to time, at identical event counts window-for-window (178 / 80 / 85 / 76
/ 58 `STATE_CHANGED` per 3 s at 80 units, before and after). `check_snapshot_union.py` is green
(40 fields on the per-frame path, 41 union keys valid) and `GPUSnapshotUnionTest` passes 1 800
ticks with every non-union field poisoned.

**Fix shape (as filed).** Pass the hot state down instead of re-fetching. `ActivityTranslator` reads
`casting_ability_id` and nothing else (`param_field: casting_ability_id` in
`tools/activity_taxonomy.yaml`, twice); `_start_attack_animation` reads `weapon_type`, `target`,
`pos_x`, `pos_z` — **all four in the union**. `tools/check_snapshot_union.py` and
`tests/GPUSnapshotUnionTest.tscn` are what keep that honest, and the union's own comment records
what a silent miss costs. Smaller than W11 and independent of it.

---

### W9 — ❌ REFUTED: the gate is not the multiplier, and the rebuild is not the cost

**Status:** `REFUTED` (R27) — **the measurement its own entry demanded is what killed it.**
Kept, not deleted, per this list's rule.

The item said two things grow with the cast at once. **Both were measured; one is false and the
other is 20 % of the call.**

1. ❌ *"The gate opens more often — `P(any of N units changed state)` goes to 1 as N grows."*
   It opens on **5–40 % of ticks at 16, 32, 48, 64 and 80 slots alike**, with no trend, and
   **~1 unit** has moved when it does (F34). Correction 14.
2. ❌ *"The call costs more because it rebuilds 39 fields for every slot."* It does — and that
   rebuild is **0.24 ms of a 1.4 ms call at 32 slots, 0.6 of 3.0 at 80**. The **apply pump is
   75–80 %** (F35), and the events that cost are the state-movers' own, so restricting the call
   to movers keeps the expensive part and *moves* the rest to the per-frame call.

What the entry got right is that `chk` is the cliff — R26/F32 stands. It named the wrong half of
it. The cost is **W11**, four frames further down, with **W12** beside it.

> The residue worth keeping: `_read_tick_columns` still throws an index set away into a bool,
> and the `chk split` counter that proved this is committed. If W11 and W12 land and `chk` is
> still hot, the mover set is there to be used — but it is a *third* item behind two bigger
> ones, not the top of the list.


### W7 — build a stress fixture, and find where the budget actually breaks

**Status:** **`DONE`** (R26) — the deliverable was a measurement and it is in
`## It breaks at 64 units` above and Round 26 below.

**Answer: 48 units fits inside the 6.94 ms budget (worst window 3.9 ms across 12 windows);
64 units breaks it.** Above that the frame does not degrade gracefully — it collapses, and
the mechanism is named in **W9** (per-tick cost ∝ slots) and **W6** (the catch-up loop that
compounds it once a frame passes 16.67 ms). ⚠ **R27 re-reads the first half**: the per-tick
cost is dominated by the apply pump, and inside it by one synchronous SFX call — **W11**.

**The fixture** is `GPUArena --stress-units=N` (`_pad_teams_for_stress`), off unless asked.
It clones the cast the scenario already gave the arena: deep clones
(`Character.from_dict(to_dict())`, because `bind_for_combat` binds progression **by
reference** and two units on one `Character` share an HP pool), each on its own free ground
cell drawn from `Battle`'s own placement policy (`PlacementTileGenerator.placement_cells()`),
nearest-first to its team's centre so the sides still converge and fight, and drawn
**alternately** by the two sides so a tile shortage degrades symmetrically.
`GPUArenaStressCastTest` pins the clone's independence — that property fails silently and
would make every number the fixture produces wrong in the same direction.

**Arena, not navigator, and that was a choice.** The stress cast is synthetic wherever it
runs — no ENTD has 64 combatants — so the only question the host decides is which *constant*
costs surround it. The arena was chosen because 25 rounds of history are comparable to it, it
is CLI-drivable (`--skip-strategy --combat-autostart`), and the thing under measurement —
`CombatLoop` and the per-unit work it pumps — is **shared through `CombatHost`**, the seam
both hosts sit on. What the arena does not carry is the navigator's own per-frame work
(scenario, roster, story), which shifts the intercept, not the slope. **That was W10, and R29
measured it: the intercept is +0.05 ms against a control that spans 0.069 ms — the choice of
host cost this effort nothing.**

⚠ **The map is the ceiling.** Gariland is 10×15; the fixture placed at most **111** units
before running out of valid ground cells, and it warns when it does. A bigger cast needs a
bigger map, not a bigger `N`.


### W10 — the same curve on the navigator's host, not the arena's

**Status:** **`DONE`** (R29) — the deliverable was a measurement and here it is  · **This was
the half of the old W7 that R26 did not answer, and the item that decided whether any of this
reaches a player. It does: the intercept is ≈ 0.**

#### The answer: the navigator costs the same as the arena

`NavigatorMain` was booted with `navigator.autoplay` and walked **live, at `time_scale` 1**,
from the Orbonne prayer through the Orbonne battle (group 3, MAP056) and on to the **Gariland
battle (group 9, MAP022) — the same map the arena runs** — with `--perf-debug`. No new code:
the `[PERF]` report fires on any `CombatHost`, exactly as this entry predicted. Two 600 s
walks, interleaved with three 60 s arena arms in one time window (R29).

Every row is the **`[PERF #2]` window at tick 360**, overlay closed,
`misc:render_unfocused_fps = 4000` (A/B'd against 16 000 — no difference; not a cap).

| host · battle | slots / alive | frame | `CombatLoop` | **outside the loop** |
|---|---|---|---|---|
| arena · Gariland, seed 424242 (arm 1) | 16 / 8 | 1.218 ms | 0.40 ms | **0.818 ms** |
| arena · same (arm 2) | 16 / 8 | 1.249 ms | 0.41 ms | **0.839 ms** |
| arena · same (arm 3) | 16 / 8 | 1.367 ms | 0.48 ms | **0.887 ms** |
| **navigator · Gariland (group 9)** (walk 1) | 12 / 7 | 1.291 ms | 0.41 ms | **0.881 ms** |
| **navigator · Gariland** (walk 2) | 12 / 7 | 1.356 ms | 0.44 ms | **0.916 ms** |
| navigator · Orbonne (group 3, walk 1) | 10 / 4 | 1.146 ms | 0.30 ms | **0.846 ms** |
| navigator · Orbonne (walk 2) | 10 / 4 | 1.220 ms | 0.32 ms | **0.900 ms** |

**Arena mean 0.848 ms · navigator-on-Gariland mean 0.899 ms · Δ = +0.051 ms.** The arena's
own three arms span **0.818–0.887 ms (0.069 ms)** — so *the intercept is smaller than the
noise floor of the control*, and the honest statement is **bounded below 0.1 ms**, not
"measured at 0.05".

**Why it is that small, from the per-script census** (R29's `[W5]` rig, same windows). The
navigator does bring per-frame work the arena never runs — `ScenarioVM` 0.017 ms,
`ScenarioVMDebugPanel` 0.008 ms, `DialogueBox` 0.002 ms — but it also **does not run**
`TileCursor` (0.023 ms) or `FeedbackHudManager` (0.015 ms), which the arena does. The two
sets cancel. Non-`CombatLoop` script is **0.36–0.39 ms on the arena** and **0.31–0.36 ms on
the navigator**: the navigator is, if anything, marginally *cheaper* in script, and pays its
small excess in the render half instead (`outside_script` 0.57–0.59 vs 0.46–0.49 ms).

⚠ **On the navigator the loop is billed to `NavigatorMain.gd`, not `CombatHost.gd`** — combat
there is a bare `CombatLoop` on the world units (decision #180), pumped from
`NavigatorMain._process`. Its census bin (0.414/0.446 ms) *is* the loop, and reads as
double-counting unless you subtract it.

**R26's breaking point, restated as this entry asked.** `64 − (navigator overhead ÷ per-unit
cost)` = `64 − (0.05 ÷ 0.07)` = **63 units**. The cliff does not move. ⚠ And the intercept
was measured at the navigator's *own* 11–12-unit cast, which is the only cast an ENTD
produces; nothing here shows the navigator's constant work stays constant at 64, only that
scenario/roster/story work has no term in the combatant count.

#### What the item said before it was measured — kept, because two of its three bullets held

Every number in this document, R26's curve included, came from `GPUArena.tscn`. The
destination is the *game's* frame rate and the game's host is `NavigatorMain`:

- They share `CombatLoop` through `CombatHost`, so the per-tick cost (R27: **W11**/**W12**,
  formerly filed as W9) and W6's catch-up transfer by construction — those are properties of
  the loop, not of the host.
- The navigator brings per-frame work of its own — scenario, roster, story — that the arena
  never runs and that has never been measured. That shifts the **intercept**: whatever it
  costs comes straight off the 6.94 ms budget, so the 64-unit breaking point moves down by
  however many milliseconds the navigator spends before combat starts. ✅ **True, and the
  amount is +0.05 ms** — one unit off the breaking point. The bullet was right about the
  mechanism and silent about the size, which is why it had to be run.
- The arena force-opened the F3 overlay until #866; `NavigatorMain` registers panels but
  never opens it.

**Done when** the navigator's own per-frame cost is measured on a real battle with the same
instrument (`--perf-debug` reports on **any** `CombatLoop` host — no new code), stated next to
the arena's, and R26's breaking point is restated as `64 − (navigator overhead ÷ per-unit
cost)`. ✅ **All three met above.** The "no new code" claim held exactly: the only thing the
walk needed that the CLI does not offer is `"navigator.autoplay": true` in
`config/tune_overrides.json`, and the `[PERF]` report fired on `NavigatorMain` untouched.

**Not cheap the way the arena is.** The navigator has no `--stress-units`: its cast is the
ENTD's. Measuring the *intercept* needs no stress fixture at all, and that is the part worth
having; a stress cast on the navigator would need the same synthetic padding the arena got.
Do the intercept first, and only then decide whether the padded version is worth building.

**R29 did the intercept and the padded version is NOT worth building.** A stress cast on the
navigator would cost the arena's whole `_pad_teams_for_stress` machinery to re-derive a curve
whose intercept has now been measured at under 0.1 ms — the curve would land on top of R26's.

**What the walk did surface is two defects the arena could never have shown**, because the
arena runs neither the scenario VM nor a dialogue box: **W13** (which the arena has too, and
which the navigator's own census found at the same size) and **W14**. Both are below.

### W3 — the engine binary is compiled with the optimizer switched off

**Status:** **`DONE`** (R24) — built (R23), adopted (R23) and **measured** (R24)  · **Not a
code change — a recompile**  · Measured **3.1–4.5×** on the script-heavy buckets, **1.13×** on
the GPU submit, **1.21×** on the frame. **The 5.33× itself remains unverifiable against this
build pair — see below**; R24 is a pair-of-builds comparison, stated as one.

**Built 2026-09-06**, zero errors, 5 min 35 s at `-j20`:

```
scons -j20 platform=linuxbsd target=editor dev_build=no
→ bin/godot.linuxbsd.editor.x86_64      164 MB
   bin/godot.linuxbsd.editor.dev.x86_64  1032 MB   (untouched, still there)
```

The filename encodes the flag, so it landed **beside** the dev build rather than over it —
falling back is instant. Confirmed optimized by the payload, not by the version string:
`DEV_ENABLED` appears in the `.dev` binary's strings and **not** in the new one, and the
6.3× size drop is `-g3` going away.

**Still open, and neither is bookkeeping:**

1. ~~Nothing uses it yet.~~ **ADOPTED 2026-09-06 06:56.** `/usr/local/bin/godot` now names
   `godot.linuxbsd.editor.x86_64`, so `godot` on `$PATH` — every session's engine per
   CLAUDE.md, and the whole test suite — **is the optimized build**. Verified by payload:
   `strings $(readlink -f $(command -v godot)) | grep -c DEV_ENABLED` → **0**.

   > ⚠ **Every measurement in this document above round 23 was taken on the OLD engine.**
   > The absolutes are not comparable to anything measured from here on. Ratios within a
   > single round still hold, because both arms of every A/B ran on the same binary.
2. **⚠ The 5.33× CANNOT be measured against this pair — still true after R24.** R24 measured
   the pair and reports it *as* a pair-of-builds comparison, which is the second option below;
   it is not an optimizer number. The two binaries are not the same
   engine source. The `.dev` one was built **2026-08-10 at commit `3e530a3e9`**; the new one
   is at **`f2a208da6`**, roughly four weeks of fork commits later. Any A/B between them
   measures engine churn *plus* the optimizer. A clean number needs `dev_build=yes` rebuilt
   at `f2a208da6` — about six more minutes — or it needs to be stated as a pair-of-builds
   comparison rather than an optimizer measurement.

**Two desktop launcher entries now exist** (`~/.local/share/applications/`), because the
`super+space` entries hardcode absolute paths and are therefore unaffected by the symlink
either way:

| entry | binary |
|---|---|
| `Godot (patched dev)` | `godot.linuxbsd.editor.dev.x86_64` — unchanged, keeps `DEV_ENABLED` |
| `Godot (patched, optimized)` | `godot.linuxbsd.editor.x86_64` — new |

The dev entry is kept deliberately: `DEV_ENABLED` is the flag'"'"'s real payload and is worth
having while stepping through the fork'"'"'s C++. The fork'"'"'s `godot-standalone` window-class
routing is a **source** patch, not a build flag, so the optimized binary keeps it and
Hyprland'"'"'s `^Godot$` / `^godot-standalone$` rules apply to it unchanged.

> Confirmed still open (R22), and now from the build's own recorded environment rather than
> by inference from the filename — `~/Repos/godot/.scons_env.json`:
>
> ```
> dev_build = True      optimize = 'none'      target = 'editor'
> CCFLAGS opt/debug flags: ['-gdwarf-4', '-g3']      # no -O flag at all
> ```
>
> `~/Repos/godot/bin/` holds **only** `godot.linuxbsd.editor.dev.x86_64`, and `godot` on
> `$PATH` resolves to it through the root-owned `/usr/local/bin/godot`. So every number in
> this document — W1's included — was taken on an unoptimized engine.
>
> ⚠ `.scons_env.json` cannot answer the `DEV_ENABLED` question: it serialises `CPPDEFINES`
> as `<<non-serializable: deque>>`, so a grep of that file for `DEV_ENABLED` returns a
> **false negative**, not evidence that the define is absent. Check the SConstruct or the
> binary, not the env dump.

`~/Repos/godot` is built `dev_build=yes`, which means `-O0`. Confirmed by the binary's own
filename: `bin/godot.linuxbsd.editor.dev.x86_64` (`SConstruct:1041` appends `.dev` only for a
dev build).

Two consequences, and the second is the one that matters day to day:

1. Every millisecond in this document is inflated by an unknown, **non-uniform** factor, so
   the ranking itself may be wrong rather than merely the magnitudes.
2. **F5 runs on that binary.** This is not only a measurement artifact — it is the engine you
   play on.

**What `dev_build=yes` actually buys**, from the fork's own `SConstruct` — one flag changing
three independent things:

| | effect | overridable? |
|---|---|---|
| `optimize` | defaults to `none` (`SConstruct:538`) | **yes** — it only applies while `optimize=auto` |
| `debug_symbols` | on, `-g3` instead of `-g2` (`:546`, `:871`) | **yes** — `debug_symbols=no` |
| `DEV_ENABLED` | defined (`:556`) | no — that *is* the flag |

`DEV_ENABLED` is the only real payload, and the SConstruct comment scopes it precisely:
*"enables engine developer code which should only be compiled for those working on the engine
itself."* It is worth paying for while stepping through the compositor fork's C++ in a
debugger, and worth nothing while writing GDScript.

**Fix shape.**

```
cd ~/Repos/godot && scons -j24 platform=linuxbsd target=editor dev_build=no
```

With `target=editor` + `dev_build=no`, `optimize` resolves to `speed_trace` (`SConstruct:541`)
— optimized, still usable stack traces. The middle option, keeping the engine asserts while
dropping `-O0`, is `dev_build=yes optimize=speed_trace`.

> **You cannot lose the current binary.** The filename encodes the flag, so an optimized build
> lands *beside* the dev one (`godot.linuxbsd.editor.x86_64`) rather than overwriting it.

**Three traps.**
1. `/usr/local/bin/godot` is a **root-owned** symlink to the `.dev` filename and will dangle.
   Repoint it by hand: `sudo ln -sf ~/Repos/godot/bin/godot.linuxbsd.editor.x86_64 /usr/local/bin/godot`.
2. Close any editor running from the binary being rebuilt.
3. `godot --version` still reports `4.8.dev.custom_build` either way — that `dev` is the
   engine's version *status* from `version.py`, unrelated to `dev_build`. **Confirm by
   filename, not by version string.**

---

### W4 — make the overlay cheap **while open**, not merely closed

**Status:** `PARTIAL` — the known ~46 % is **`DONE`** (R31); the ~54 % is **`DIAGNOSE`**,
and one of its two hypotheses is now refuted.  ·  **Dev loop only, reaches no player**

The goal is a fast game **with the F3 overlay up**, so "stop opening it" is not the fix.
What the 26 % was made of (round 2, arms D and E):

| component | share of the overlay's cost | state |
|---|---|---|
| `PerfDebugPanel`'s 240-sample graph redraw | ~31 % | **`DONE`** (R31) |
| `PerfDebugPanel`'s per-frame `Label` text | ~15 % | **`DONE`** (R31) |
| the window itself + every other panel | ~54 % | `DIAGNOSE` — one hypothesis refuted |

**Landed in an earlier round** (branch `perf/overlay-default-866`): `GPUArena._ready()`'s
unconditional `DebugOverlay.show_overlay()` deleted; the strategy-phase call gated on
`not DebugConfig.combat_autostart`; `PerfDebugPanel._on_sample()` does nothing unless the
control is on screen. That half made every *downstream measurement* honest. It did not
make an open overlay fast — and see the ⚠ below for what it also did.

#### The known ~46 % — `DONE` (R31)

`PerfMonitor` samples every frame and is **right to**: the ring buffer the graph draws has
to stay dense. What was wrong is that the panel did full-fidelity work on every emission.
The live label and the graph redraw now sit behind **one shared gate at ~10 Hz** — a frame
time graph and a text readout are read by a human eye, and ten updates a second is fully
legible at about a fourteenth of the cost.

The interval accumulates each **sample's own `frame_time_ms`** rather than reading the
clock. That makes it a *rate* and not every-Nth-frame — a frame-count throttle would stall
the readout exactly when the frame rate drops and a developer most needs to read it — and
it lets a test drive the rate deterministically.

`PerfPanelThrottleTest`, counted work rather than milliseconds (W8's standing ruling):
one simulated second buys **10** updates whether it arrives as 1000 samples of 1 ms or 100
of 10 ms; the visibility gate still comes first; the graph redraw shares the gate, counted
through real `draw` emissions. Its control runs **through** the production constant rather
than around it — `set()` cannot write a `const` — by feeding samples that each carry a
full interval, which must every one land.

#### 🔴 Every automated run in this document measured the CLOSED arm

⚠ **The two changes above interact, and nobody noticed.** Deleting `GPUArena`'s
unconditional `show_overlay()` and gating the strategy-phase call on
`not combat_autostart` together mean that **an `--combat-autostart` run cannot open the
overlay at all**, and every run in the `## Auto-deploy run command` recipe is one. There
was no flag, no setting and no code path that would open it. So W4's open arm was
unreachable from the rig for the whole of the effort that followed #866.

`--debug-overlay` (R31) fixes that: it sets the flag, and because `DebugOverlay` is a
later autoload than `DebugConfig` the toggle fires into nothing, so the overlay re-reads
the flag in its own `_ready`. It then **prints the OS window count** — an open-vs-closed
arm whose "open" side never mapped a second window measures nothing, and a blind
instrument's zero reads exactly like an absent effect. Confirmed live:
`dashboard shown on boot: visible=true os_windows=2`.

`draw_calls: mean` was also added to the `PerfMonitor` session summary. It was already
sampled per frame and never aggregated. ⚠ **It turned out to be too noisy to serve as the
positive control it was added to be** — 195 / 292 / 335 across three runs of the *same*
closed arm, a spread far larger than a second window's contribution. The window-count
print is the control that works.

#### ❌ REFUTED: the `Window`'s update mode is not a lever

W4's entry named this the cheap first hypothesis — *"a `Window` is a `Viewport`, so its
update mode is worth checking."* It is not available, and the reason is structural:

- `update_mode` is declared on **`SubViewport`**, not on `Viewport`
  (`scene/main/viewport.h:919`). A native `Window` has no such property.
- At the `RenderingServer` level `Window` already does the right thing — it sets
  `VIEWPORT_UPDATE_WHEN_VISIBLE` on show and `VIEWPORT_UPDATE_DISABLED` on hide
  (`scene/main/window.cpp:756`, `803`, `1714`, `1811`). **The closed overlay already costs
  nothing to render.**
- But for a window that IS shown, `renderer_viewport.cpp:825` decides
  `visible = vp->viewport_to_screen_rect != Rect2()` *before* the update mode is consulted,
  and `window.cpp:1440` attaches exactly that rect. **A viewport attached to an OS screen
  is drawn every frame, unconditionally.** There is no dirty-tracking for a native window
  to switch on.

So the remaining ~54 % cannot be attacked by making the window update *less often*. It has
to be attacked by making the per-frame draw *cheaper* — which points at the volume of
visible canvas items, and the dashboard shows all 23 category cells at once with no tabs
(the arena registers 14 panels into them). That is a UX change, not a perf toggle, so it
is a decision rather than a task.

R30 already eliminated the other half of the hypothesis: of 41 `BaseDebugPanel`
subclasses **three** define `_process`, so "every other panel" is not per-frame script
work. Do not re-run that census.

#### ⚠ What is NOT established, and why no number is quoted here

R31 ran three interleaved open-vs-closed reps, uncapped
(`--disable-vsync --max-fps 0`), on session-mean frame time. **The result is not
reportable and is not reported.** Two reasons, both disqualifying:

1. **The arms were not the arms.** Both sides already carried the 10 Hz throttle, so the
   comparison could never have shown the ~46 % it had just removed. The A/B that matters
   is trunk-panel-open vs throttled-panel-open, and it has not been run.
2. **Within-arm spread swamped the effect.** The closed arm alone read 2.84 / 2.92 /
   3.19 ms while another session's suite held the box at load ~4. The signal sought is
   ~0.35 ms.

An earlier arm was also thrown away for a third reason worth recording: comparing
`[PERF #N]` windows across arms compares **battle phases**, not configurations. The
"open is faster" reading it produced was reproduced by the *closed* arm on its next rep —
the early windows simply precede engagement.

**Still open.** The ~54 %, on a quiet box, with the trunk-vs-throttled open arms actually
distinguished. The 26 % headline itself is a **round-2** figure taken on the
`optimize=none` engine 23 commits before `2c9ac86ab` (caveat 3) and has never been
re-measured; whoever takes this should re-establish it before optimising against it.

**Blast radius (round 20, fix 1).** The ~10 `tests/EffectStudio*` and `tests/Colour*` tests
call `show_overlay()` **themselves** — their own comments explain why ("a HIDDEN Window does
not lay out") — so they cannot break. The three `GPUArena`-derived tests (`GPUThrashTest`,
`GPUTeleportTest`, `GPUItemFallthroughTest`) never reference `DebugOverlay` at all.
`TrapViewerScene.gd:104` and `FireCastReproScene.gd:81` force-open it appropriately: leave them.

---

### W5 — F19: the block outside `CombatLoop` — 0.85 ms, and now named

**Status:** **`DONE`** (R29) — attributed, with the two fix shapes filed as **W13** and
**W14**. Not fixed in this pass, as the entry required.

> ❌ **Every size this entry ever carried was wrong, and each was wrong for a different
> reason.** "3.7 ms of a ~15 ms frame" was an `-O0` number. R25's replacement, "1.82 ms of a
> 2.08 ms frame", was taken through the 500 fps cap (R26/F29). The handoff into R29 restated
> it as "frame 6.075 − `CombatLoop` 0.738 = **5.34 ms**", which is the R24 pair taken through
> the **144 fps** cap (F28). **Measured uncapped on the shipped engine the block is
> 0.82–0.89 ms** — 6.3× smaller than the handoff's 5.34, 2.1× smaller than R25's 1.82, 4.4×
> smaller than the original 3.7.
>
> ⚠ **But read the SHARE the other way round.** The old entry called it *"about a quarter of
> the frame"*; it is now **65–68 % of it** (0.82–0.89 of a 1.22–1.37 ms frame), and it is
> **larger than `CombatLoop`**, which is 0.40–0.48. The block did not become a small share —
> everything around it got cheaper faster than it did. What changed is that two thirds of a
> 1.25 ms frame is not a problem, and that it is no longer unexplained.

**The instrument.** `Performance.TIME_PROCESS` cannot decompose a frame (correction 16), so
R29 bracketed the real script pass instead: `PerfMonitor` already runs at
`process_priority = -100` and stamps the head; a probe node at `1000` runs last and stamps the
tail. Every top-level `_process` in `src/` and `addons/` was wrapped to bin its own wall cost
by script path, and `CombatLoop`'s own 3 s `[PERF]` report **drains** the bins, so the census
averages exactly the frames the `[PERF]` line above it does. Cross-check: the census billed
`src/gpu/CombatHost.gd` **0.4084 ms/frame** in a window where `CombatLoop`'s independent timer
reported `total: avg=0.41ms`. The rig costs nothing measurable — instrumented and clean arena
arms at the same load gave the same frame and the same bucket totals to 0.01 ms.

**The split**, arena, seed 424242, `[PERF #2]` at tick 360, 13-unit cast, overlay closed,
three interleaved arms:

| | arm 1 | arm 2 | arm 3 |
|---|---|---|---|
| frame | 1.218 ms | 1.249 ms | 1.367 ms |
| `CombatLoop` (its own timer) | 0.40 | 0.41 | 0.48 |
| **outside `CombatLoop`** | **0.818** | **0.839** | **0.887** |
| ↳ engine + render submit + present (`frame − script span`) | 0.457 | 0.471 | 0.492 |
| ↳ non-`CombatLoop` script (`script span − loop`) | 0.362 | 0.373 | 0.393 |

**So it is roughly half render, half script** — and the script half is fully named:

| script | ms/frame | calls/frame |
|---|---|---|
| **`src/debug/AudioBusMixerDebugPanel.gd`** | **0.093–0.103** | 1.0 |
| `src/effects/EngineFoldCompositor.gd` | 0.063–0.068 | 1.0 |
| `src/units/Unit.gd` | 0.061–0.065 | 13.0 |
| `addons/exmateria_battlefield/cursor/TileCursor.gd` | 0.024 | 1.0 |
| `src/ui3/elements/FeedbackHudManager.gd` | 0.016 | 1.0 |
| `src/ui3/elements/DamageNumber3D.gd` | 0.012–0.013 | 3.6 |
| `addons/exmateria_sprite_rig/render/CameraRelativeRenderer.gd` | 0.010 | 13.0 |
| `src/effects/TrapEffect.gd` | 0.008 | 0.5 |
| `addons/exmateria_battlefield/camera/PlayerCamera.gd` | 0.007 | 1.0 |
| `addons/exmateria_battlefield/assembly/MapComposer.gd` | 0.006 | 1.0 |
| `src/core/Tune.gd` | 0.003 | 1.0 |
| **named total** | **≈ 0.30** | |
| unattributed remainder (engine dispatch between callbacks, signals, tweens) | ≈ 0.06–0.09 | |

**❌ F19's hypothesis is REFUTED.** The block was called *"consistent with sprite-repaint
churn"* — `Unit._process` (which pushes the view and drives the shadow) plus
`CameraRelativeRenderer` together are **0.071 ms/frame across all 13 units**, 5 % of the
frame and 20 % of the non-loop script. Sprite repaint is not the block; it was never
instrumented, and reading it as the candidate is the same failure as corrections 6, 14 and 15.

**The largest single script item in the frame after the combat loop itself is a debug panel
running with the overlay closed** — that is **W13**, and it is bigger than every unit's
per-frame work put together.

**The static floor** — same scene, units placed, combat never started (`--skip-strategy`
without `--combat-autostart`), 35 s, two arms — is **0.66 / 0.74 ms mean frame**. That is
within ~0.15 ms of the block, so **most of the block is the static scene**, which is what the
old entry guessed and could not show. ⚠ The two are not perfectly comparable: the floor is a
whole-run mean over 35 s, the block a 3 s combat window. A static arm reports **no `[PERF]`
line at all** — `CombatLoop.tick()` returns early when `combat_active` is false — so the
`[W5]` census cannot be drained there, and the floor is a `PerfMonitor` summary figure only.

**Where this leaves the ranking.** At the shipped cast the whole block is **0.85 ms of a
6.94 ms budget**. W13 is worth ~0.09 ms of it and is free to fix; the rest is the engine
drawing a map. Nothing here reaches a player.

---

### W13 — a debug panel meters the audio buses every frame, with the overlay closed

**Status:** **`DONE`** (R30, [#955](https://github.com/timbermania/fft-monorepo/issues/955), found by W5's census)  · **Reaches every player**  · Measured
**0.064–0.103 ms/frame**, ~26 % of all non-`CombatLoop` script, on **both** hosts

`src/debug/AudioBusMixerDebugPanel.gd`'s `_process` walks every `AudioServer` bus, reads its
peak volume left and right, updates a meter and a `%.1f dB` label per row, then rebuilds four
more label strings — two of which (`_scheduler_line()`, `_sfx_scheduler_line()`) query the
live SPU's queue counters. Every frame. All session. The F3 overlay is closed.

**The mechanism is not a missing gate — the gate is armed ON at registration.** The panel does
the right thing three times over and is defeated by its caller:

- `_ready()` ends with `set_process(false)`.
- `on_hidden()` is implemented, and does `set_process(false)`.
- `on_shown()` does `set_process(true)`.

> ❌ **CORRECTED (R30, correction 17): it is two, not three, and the third was defeated by the
> ENGINE, not by the caller.** The first bullet is `_build_ui()`, which runs BEFORE the panel
> enters the tree (every panel is built `new()` → `setup()` → `register_panel()`), and
> `Node`'s `NOTIFICATION_READY` calls `set_process(true)` for any script that defines
> `_process` — *before* `_ready` (`scene/main/node.cpp:272`). That `set_process(false)` has
> therefore never had an effect in any build. It matters past the bookkeeping: under the
> filed mechanism the fix is *"give `on_hidden()` a caller"*, and that would have left
> **`ScenarioVMDebugPanel`** — which repopulates a whole disassembly list every frame and
> never calls `set_process` at all — running exactly as before. There was nothing on it for a
> caller to switch off.

`DebugDashboard.add_panel()` (`src/debug/DebugDashboard.gd:350`) calls `on_shown()`
**unconditionally, at registration**, whether or not the overlay is visible — and
**`on_hidden()` has no caller anywhere in the repo.** A repo-wide grep finds the `func`, finds
`BaseDebugPanel`'s docstring for it (*"Override to pause updates when not visible"*), and finds
**zero** call sites. So the panel is switched on when it is created and there is no code path
that can ever switch it off.

**What was built (R30).** Neither of the two shapes this entry proposed. The gate went on
**`BaseDebugPanel`**, once, because correction 17 says a caller-side fix cannot reach the
panels that never armed a gate in the first place:

```gdscript
func _notification(what: int) -> void:
    if what == NOTIFICATION_READY or what == NOTIFICATION_VISIBILITY_CHANGED:
        _sync_process_to_visibility()

func _sync_process_to_visibility() -> void:
    if processes_while_hidden:
        return
    set_process(is_visible_in_tree())
```

Three things decided that shape.

1. **`is_visible_in_tree()` is strictly stronger than the hook pair could be.** A panel is
   hidden by **four** things — the dashboard Window, the header's page switcher, its category
   cell's fold, and its own per-panel fold (`add_panel` opens the first panel in a cell and
   folds every later one). `on_shown()`/`on_hidden()` can only ever see the first.
   `NOTIFICATION_VISIBILITY_CHANGED` reaches the panel for all four:
   `CanvasItem::_handle_visibility_change` recurses into child canvas items, and
   `CanvasItem::_window_visibility_changed` is what carries a Window's hide down into them.
2. **`_notification`, not `_ready`.** GDScript dispatches `_notification` to every script in
   the inheritance chain, so a subclass cannot shadow the gate by defining its own. (None of
   the 41 subclasses defines `_ready` or `_notification` today; this keeps that from becoming
   a trap.) It also lands *after* the `NOTIFICATION_READY` auto-arm, which is the point.
3. **One panel had to opt out, and finding it is the reason to check rather than assume.**
   `ScenarioUnitSpriteOffsetDebugPanel._process` does not repaint — it **re-applies** the
   stored `shared_loc_offset` overrides to the live units every frame, because the sprite
   pipeline rewrites the offset per animation (its own docstring: *"re-applied per frame + on
   reload"*). Gating it would drop a calibration the moment the panel folded away. It sets
   `processes_while_hidden = true`, which names the case instead of leaving it to be
   rediscovered.

`on_hidden()` and its `BaseDebugPanel` docstring are **deleted**: a hook with no caller is
worse than no hook, because it reads as a gate. `on_shown()` stays — `add_panel` still calls
it and 13 panels re-sync in it — but it no longer arms anything. The mixer's staleness check
(`AudioServer.bus_count != _built_for_bus_count`) moved from `on_shown()` into `_process`,
where it is one int compare per **visible** frame and also catches a bus added after
registration, which the hook could not.

⚠ The other two `set_process(true)` sites named below were checked and **neither is a
BaseDebugPanel**: `EffectTimelineView.gd:42` is the Effect Viewer's timeline strip (its
`_process` returns immediately while unbound) and `UI3RegistryView.gd:630` is self-limiting —
it arms for a row-reveal flash and disarms when the flash expires. Left alone.

**Witness.** `DebugPanelProcessGateTest` asserts **counted work** — `is_processing()` — not
milliseconds, which is W8's standing ruling and the only assertable thing here: 0.09 ms is far
inside this box's rep-to-rep spread. It drives the real registration path (a real
`DebugDashboard`, hidden as it is at boot), the full `show()`/`hide()` round trip on that
Window, the visibility transitions under a plain ancestor, the inherited gate on
`ScenarioVMDebugPanel`, and the opt-out. Seed-proven against trunk: **6/9 red** on exactly the
three claims, 15/15 after.

⚠ **The round trip is in there because the first draft of this witness asserted three ways a
panel STOPS and only one way it starts** — and that one way (a plain `Control` ancestor) is not
the path the shipped game takes. The gate rests on a link that draft never exercised: only the
**topmost** `CanvasItem` under a `Window` connects to its `visibility_changed`, and it reaches
a nested panel by recursion. A break anywhere in that chain leaves every panel gated off
forever — a dead F3 mixer, worse than the bug being fixed — and every hidden-direction
assertion would have stayed green through it. **A gate needs both of its directions tested,
and the release direction has to be tested on the real host.**

**Why it is worth doing even though it is 0.09 ms.** It is the *"delete work"* kind, not the
*"make work cheaper"* kind — it generalises to every build and every machine, it is bigger
than all 13 units' `_process` put together, and it costs nothing to remove. It is the only
item on this list that is both free and real.

---

### W14 — the dialogue box calls an EDITOR-ONLY RenderingServer API, every frame, per box

**Status:** **`DONE`** (R30, [#956](https://github.com/timbermania/fft-monorepo/issues/956), found by W10's navigator walk)  · **A correctness bug first**

`src/scenarios/ScenarioDialogueBoxPool.gd:739`, inside `_sprite_billboard_anchor`:

```gdscript
var par: Variant = RenderingServer.global_shader_parameter_get("pixel_aspect")
if par != null and float(par) > 0.0:
    v.x = o_view.x * float(par)
```

`MaterialStorage::global_shader_parameter_get` opens with
`if (!Engine::get_singleton()->is_editor_hint()) { ERR_FAIL_V_MSG(Variant(), "This function
should never be used outside the editor, it can severely damage performance."); }`. Outside
the editor it therefore **always returns `null`**, and the guard below it means

1. **the PAR correction this code exists to apply has never run in the shipped game** — the
   dialogue tail's screen-x is never stretched by `pixel_aspect`, which is the exact defect
   ADR-0036 and the comment above the call describe; and

   > ❌ **CORRECTED (R30, correction 18): dead, not wrong.** `pixel_aspect` ships at **1.0**
   > (`project.godot [shader_globals]`, and no `render.pixel_aspect` override is committed),
   > so the multiply this guard was skipping is a multiply by one. **No frame the player has
   > ever seen was in the wrong place**, and restoring the call moves nothing on screen today.
   > What was broken is the *response to a PAR scrub* — ADR-0036 dec. 2's opt-in, which this
   > surface silently was not honouring. That is still worth fixing and it is still the
   > reason to fix it; it is not the visible defect this sentence reads as. R30's test pins
   > **both** halves so the fix cannot be sold as a visual change.

2. every call prints an engine error **plus a 4-line GDScript backtrace** to stdout.

**Measured on the navigator walk:** `_reposition_open_box` → `_place_box_on_unit` →
`_sprite_billboard_anchor` fired **35 790 times in 150 s** (~239/s whenever a box is open),
each printing the error, its `at:` line and a six-line backtrace: **≈ 286 000 of that run
log's 288 124 lines — 99 % of everything the game said.** It does **not** fire during combat
(no box is open), which is why 25 rounds on `GPUArena` never saw it.

⚠ **The frame cost is NOT established, and the A/B that tried says so.** Arm A (trunk) vs arm
B (the one line stubbed to `null` — behaviour-identical outside the editor, since the call
already returns `null` there), two interleaved reps each, 150 s per arm, scored on
frames-completed-in-fixed-wall-clock:

| | rep 1 | rep 2 | mean |
|---|---|---|---|
| A — trunk | 184 897 | 207 323 | 196 110 |
| B — call removed | 201 416 | 208 349 | **204 883** |

B is **+4.5 %**, but **arm A's own two reps differ by 12 %** — the effect is inside the
control's spread and this rig cannot resolve it. Two reps agreeing is the check (R28), and
these do not. **File this on the correctness half and on the log, not on a frame number**;
whoever fixes it should not claim a speed-up.

**Fix shape, and the repo already wrote it down.** `addons/exmateria_platform/display_port/
PSXDisplay.gd:311` keeps a runtime mirror **for this exact reason**, in a comment that names
the trap: *"`RenderingServer.global_shader_parameter_get` is editor-only and spams a 'severely
damage performance' warning every frame at runtime."* `PSXDisplay` already owns `live_par` and
a `live_par_changed` signal. Read the mirror. A census of the whole repo finds **one**
production call site that missed the memo — this one; the other four hits are the addon's own
comments and three tests that assert the call returns `null`.

**Built (R30).** `var par: float = PSXDisplay.live_par` / `if par > 0.0`. Three lines,
including the deleted `null` guard the getter's failure mode required.

**Witness — `DialogueBoxAnchorParTest`, and it deliberately asserts the boring half too.**
Two claims, because either alone misleads:

- at `live_par = 1.5` the anchor's cam-local x **is** stretched by 1.5 (y and z untouched) —
  the half that was dead; and
- at `live_par = 1.0` the anchor **is** the raw mesh origin, plus a read of
  `shader_globals/pixel_aspect` from `ProjectSettings` asserting the shipped default is 1.0 —
  correction 18, pinned so nobody reads this as a repositioning.

Plus a source assertion that the box pool no longer **calls** the editor-only getter. It
matches the call (`RenderingServer.global_shader_parameter_get(`), not the bare name: the
fix's own comment explains the trap by name, and a guard its own explanation satisfies is the
classic false green. Seed-proven — with the old line restored the test reds 6/9, and the
engine's *"severely damage performance"* error appears in the test's own log.

⚠ The test builds a `UnitMesh` child so the anchor takes its billboard branch, which
`tools/check_mount_node_paths.py` (ADR-0217 dec. 3) correctly flagged as undeclared. It is
now a declared crossing — and the reason to declare rather than exempt is that the coupling
runs the wrong way: on a rename production silently swaps to the tile origin while a test
holding its own copy of the name stays green.

---

### W6 — the tick catch-up drain is unbounded, and there are two of them

**Status:** `DONE` (R31)  ·  **RULED: clamp** — the simulation runs *slow* under load
rather than catching up.

`CombatLoop.tick()` converts `delta` into whole `TICK_INTERVAL` steps. With no ceiling,
a slow frame schedules more ticks, which makes the next frame slower.

⚠ **Two corrections to this entry as it stood** (correction 19, verified on `3854f4fcd`):

- The cited `src/gpu/CombatLoop.gd:565` had **moved**; line 565 is an unrelated bounds
  check. The combat drain is at **654**.
- There are **TWO** unbounded drains. The second is at **604**, inside
  `if victory_achieved:` — "keep animations ticking but skip GPU/state processing" —
  draining the **same accumulator** with the same absent ceiling. Post-victory animation
  is exactly where a long drain gets paid. A clamp on one would have read as complete.

#### The ruling

Clamping was flagged as a design decision because a clamp changes the sim's timing
contract. **It does not** — the contract already says so. `playback_scale`'s own doc
comment (`CombatLoop.gd:118`) states it outright:

> *"It scales how fast you WATCH the sim, never what the sim does: `_tick_accumulator`
> still drains in whole `TICK_INTERVAL` steps and every outcome is a function of tick
> count, so no rate can change a result (ADR-0065's principle — a beat is a function of
> ticks, not wall clock)."*

`playback_scale` (ADR-0239) already ships a knob making one tick cost 4× less wall clock.
So "wall-clock-per-tick is variable and nothing downstream depends on it" is not a new
contract a clamp introduces — it is the one the loop advertises and exercises. A clamp
changes the *observer's* experience (slow-motion under overload), not the simulation.

#### The fix shape, and why the obvious one is wrong twice

The obvious fix is to cap the `while` loop's iterations. **Do not.**

1. **It breaks ADR-0239.** The turn gate `break`s out mid-drain and deliberately *keeps*
   the accumulator remainder — the loop's own comment: *"keeps the accumulator remainder,
   which is what makes the resume seamless."* A cap needs a post-loop "throw the excess
   away" or the debt banks and every later frame runs pegged at the cap forever; that
   discard would silently destroy the seamless resume.
2. **A cap in TICKS is a red.** Four navigator proofs run at `SIM_TIME_SCALE := 40.0`,
   and `NavigatorGarilandVictoryTest` documents *"~175 ticks/s wall at time_scale 40"*
   against a 120 s budget — ~44 ticks per frame. Any cap low enough to bound the shipped
   path throttles them. `TurnDirectorTest` hands one `tick()` a full second on purpose.

**Shipped instead: clamp the DELTA, in REAL seconds, at the one place both drains draw
from.**

```gdscript
var _catchup_ceiling: float = max_catchup_real_s * maxf(Engine.time_scale, 0.0001)
var capped_delta: float = minf(delta, _catchup_ceiling)
```

With the delta bounded, each drain still runs *to completion*, so no frame inherits debt
and the turn gate's remainder is untouched. `playback_scale` multiplies **after** the
clamp, so a 4× playback rate still buys 4× the sim out of the bounded second.

`Engine.time_scale` is multiplied back in — the same unscaling `DebugConfig`'s quit timer
does — because a fast-forward is a *request* to decouple sim time from real time. The
clamp answers a machine that cannot keep up, not a developer who asked to go faster.

#### Why the ceiling is 1.0 s and not a tight budget

⚠ **The first default was 0.25 s and it was wrong.** The ceiling must sit above every
frame rate this project *normally* runs at, or the guard stops being a guard and becomes
a behaviour change on the ordinary path — the very thing the ruling was about. The arena
measures **`tpf: 1.0` at 60 fps** (one tick a frame; ~59× headroom at 1.0 s). But an
agent-launched headful session reports **1–2 fps** through a Wayland present block, so at
`time_scale 1` a frame arrives as a *full second* of delta: 0.25 s would have quartered
the sim rate of every combat test run that way. 1.0 s bounds what is worth bounding — a
multi-second stall arriving as one enormous delta — and leaves the ordinary path alone.

`max_catchup_real_s` is a host-tunable pump knob, peer of `ticks_per_frame` and
`max_ticks`. `TurnDirectorTest` lifts it to `INF`.

#### The witness

`CombatLoopCatchupClampTest` — counted work, never wall clock (W8's standing ruling), on
the same bare `CombatLoop` mount `TurnDirectorTest` uses, with **no** director so no turn
gate can explain a count. Five arms, **each with a ceiling-lifted control** so a clamped
arm cannot pass for a loop that never ran:

| arm | asserts | measured |
|---|---|---|
| 1 | the clamp bites at `time_scale 1` | 4 s frame → **59** ticks; control → **240** |
| 2 | a deliberate fast-forward is exempt | at `time_scale 40` → **240** |
| 3 | no debt banks | the frame after a clamped fat frame drains **exactly 1** tick |
| 4 | `playback_scale` survives the clamp | at 4×, 4× the budget's ticks |
| 5 | **the post-victory drain too** | counted through `ProjectileManager.update` |

⚠ Its expectations are **derived, not typed in**: `TICK_INTERVAL` is `1/60` rounded *up*
in binary, so sixty of them sum past 1.0 and a nominal one-second frame drains **59**
ticks, not 60. The test mirrors the loop's repeated subtraction rather than dividing.

⚠ **The `TurnDirectorTest` lift is not fixing a red — measured both ways.** The suite is
green without it: at `SEED 12345` the first crossing lands inside a clamped frame anyway.
It restores the arm's *stated* margin, which was about to become luck — arm 1's guard
accepts a crossing as late as tick 59, and one at 16–59 would have failed on the clamp
rather than on the director.

---

### W8 — the regression witness: assert counted work, not wall clock

**Status:** `DEFERRED` until W1 and W2 land  · Keeps the wins from rotting

A budget nobody asserts rots within weeks. But a **wall-clock** assertion is the flakiest
test that could be written here: this suite runs in parallel, contention already produces
reds at high `-N`, and a perf test would fail on machine load rather than on regression.
This very investigation was inflated **9×** by a parallel suite in another worktree, and lost
a whole session to a box that was never quiet.

> **The shape is already decided: assert counted work, not wall clock.** Counted work is
> deterministic, immune to load, and is exactly what the fixes change. What is left is
> choosing the counters.

**Candidates**, one per landed fix:
- dictionary rebuilds per ticking frame in `_check_state_changes` (today 16 × 99 string-keyed
  fields, dead units and empty slots included) — **W1**
- opcode-array scans per playback per tick in `AnimationFrameCalculator` (today 4 uncached,
  ~23 000/s) — **W2**
- per-tick allocations, or version-cache misses, in the visual bridge

**Open questions.**
1. Which counters, at what thresholds? A threshold must sit **below** today's number and
   **above** the fix's, or it asserts nothing.
2. Where does each live? `tests/GPUPerfBenchmark.tscn`, `GPUDashPerfTest.gd` and
   `SpacerVerdictsPerfTest.gd` already exist — prefer extending over adding.
3. Should a wall-clock harness exist deliberately **outside** the suite, run by hand? The
   budget is a wall-clock claim in the end and something has to be able to check it.
4. What does a counter cost when nothing is being measured? A guard that taxes every frame to
   defend the frame rate is self-defeating.

**Why deferred, not TODO.** A threshold cannot be chosen before the fix that moves it exists —
but it must be chosen **before the fix is called done**, or the win ships with no witness.
Take this immediately after W1 and W2, not at the end.

---

## What it is NOT — hypotheses tested and rejected

- **Not the GPU.** 0.16 ms/frame.
- **Not XWayland, not the display driver, not vsync.** With the rig's own cap removed,
  x11 / wayland / no-vsync give 15.8 / 14.6 / 15.7 ms in combat — identical.
- **Not the Omarchy/Hyprland frame cap *for the user*.** `render_unfocused_fps = 60` caps
  **agent-launched** windows (class `godot-standalone` → workspace 10, unfocused). The
  user's own F5/F6 runs are class `learning`, focused, uncapped. It ruined my measurements,
  not their gameplay.
- **Not draw-call submit.** Measured 1.58 µs/call on this build → 0.43 ms for the game's
  ~270 calls.
- **Not stutter.** 10 spikes >33 ms in 13 165 frames, and 9 of them are boot-time node
  instantiation (`nodes_d` +1028/+1159/+1404 at `tick=0`). Exactly **one** >33 ms frame
  occurs during an entire battle.
- **Not vsync quantisation.** vsync-on and vsync-off frame times are within noise
  (16.0/14.6/10.6/9.5 vs 16.1/15.7/10.8/9.3) — nothing is snapping to 144/72/48.

**So the symptom is a sustained low frame rate during engagement, not hitching.**

## Corrections made to my own earlier findings

1. R2's `project.godot` driver fix was **never actually applied** — verified with a grep
   against output that could not contain the pattern. Both keys are needed; neither works
   alone (reproduced 2/2).
2. R2's flat 145 fps on Wayland **never reproduced**; it was the outlier, and it was right.
3. R2's "XWayland is the 60 Hz cap" and its 2.08× — **fully withdrawn** (R12/R13). It was
   `render_unfocused_fps` acting on my own windows. **I told the user their Omarchy config
   was not the culprit; it was, for the measurements.**
4. R13's "the ~8 ms is `-O0` draw-call submit" — **refuted by measurement** (R14): my
   25 µs/call guess was ~16× too high.
5. R16's "the unbounded tick loop is the mechanism behind the `max` column" — **refuted**
   (R17): the max column is boot-time instantiation; the accumulator drains fine at 1×
   (48–290 zero-tick frames per 3 s window).
6. R20's sizing of W1 — **wrong in the census, not in the direction** (R21). The snapshot
   union is **39 fields of 101** across **five** consumers, not 15 of 99 across two (R21
   found 31 of them; R22's two instruments found the last 8 — see correction 7): the
   scoping grepped `GPUCombatInterpreter` and `GPUVisualBridge` and never walked the call
   graph out of `_check_state_changes()`, which reaches `CombatLoop`'s own `_apply_*` pump
   (21 fields), `ProjectileManager` (7) and `CinematicDebugProbe` (8). Its access-pattern
   check also **counted a spelling rather than a field**: `state["word"]` is the effect
   studio's keyframe dictionary, and `word` is not a `SNAPSHOT_FIELDS` key at all. W1 stays
   the top item, but its fix shape was pre-decided on the wrong number and went back to the
   user, who ruled **shape B** (R22).
7. **My own R21 census was wrong twice more** (R22), and neither miss was found by reading:
   - `decision_hist_0/1/2` — the hand walk's regex was `[a-z_]+` and those names **end in
     digits**. Found by `check_snapshot_union.py` on its first run. 31 → 34.
   - `pa, ma, speed, wp, s_ev` — `GPUCombatInterpreter` reads them through a **computed**
     key (`state.get(sf[0], 0)` over `STAT_FIELDS`), which no census looking for a quoted
     field name can see. Found by the poisoned battle, **as a live corruption**: every
     unit's PA/MA/Speed/WP fell to 0 on tick 1 and `_sync_stat_to_unit` wrote it into
     `unit_stats`. 34 → **39**.

   The guard now refuses an unregistered computed-key read instead of skipping it. **Do not
   re-derive this union by reading — run the guard.**
8. **This document's own run command has been measuring an idle scene** (R24, F27). The
   `## Auto-deploy run command` section asserted `simulation.skip_march: true` in
   `config/tune_overrides.json`; `main` carries **`false`**, because the key is `AUTOSAVE`-bound
   and editor sessions commit the flip. Run verbatim today it produces 60 s of
   `Units: IDLE=15, WALKING=1` — no unit ever deploys — with entirely plausible `[PERF]`
   figures and exit code 0. Fixed by passing **`--skip-strategy`**, which does not depend on the
   JSON. Also in the same sweep: R13/R18's headline absolutes (14.4 ms, the 0.97 ms/unit slope)
   are stale for a **second** reason beyond `-O0` — today's code reads 7.4 ms on that same `-O0`
   binary, so W1 and PR #883 had already moved them before the engine changed.
9. **R24's frame-time row was the THROTTLE, published one commit earlier as a real cost**
   (R25, F28). This document's own rig rule said to raise `misc:render_unfocused_fps` to
   **144** — itself a cap at 6.94 ms. Harmless at `-O0`, where a combat frame cost 14 ms and
   never reached it; fatal on the optimized engine, where **everything the game does is under
   it**. R24 read 6.05 ms / 165 fps; unthrottled the same fixture reads **2.08 ms / 482 fps**.
   The `--disable-vsync` arm that "confirmed" it ruled out vsync and nothing else, and two
   tells were argued past rather than tested: 165 fps *exceeds* the 144 Hz display, and the
   idle scene read the same 6.0 ms as heaviest combat. **The founding claim that the 144 Hz
   budget is exhausted at five live units is an artifact of the unoptimized engine.**
10. **W2 was ranked on a scan COUNT that nobody priced** (R25). "~23 000 scans/s" is correct
    and `advance_frame()` really does call 3–5 of them per playback per tick — but a scan walks
    a **median of 10 opcodes**. Built, proven equivalent over 26 473 comparisons, and measured
    at **−0.014 ms** against a −0.82 ms prediction. `REFUTED`. A count is not a cost.

11. ❌ **R25's 2.08 ms / 482 fps was the `render_unfocused_fps = 500` cap** (R26, F29) —
    the same defect as correction 9, one setting further out. R25 corrected the rule from 144
    to 500 and then measured 482 fps against it: **96 % of the cap**, which is the tell.
    Re-taken as a straight A/B on one code state, 2 interleaved reps each, identical unit
    states window-for-window:

    | `render_unfocused_fps` | worst window | median window |
    |---|---|---|
    | **500** | **2.1 ms — 474 fps** | 2.00 ms — 498 fps |
    | **2000** | **1.3 ms — 745 fps** | 1.20 ms — 859 fps |

    R25's figure reproduces *exactly* at 500 (2.1 vs 2.08, 474 vs 482), which is the proof
    that it was the cap and not the game. The shipped 13-unit cast's heaviest frame is
    **1.3 ms — 19 % of the 6.94 ms budget**, not 30 %. **A cap set "far above the frame rate
    you expect" is still a cap when you expected wrong.** The rule now says to A/B the setting
    itself, which is the only version of it that cannot fail this way a fourth time.
12. ❌ **The `[PERF]` `Units:` histogram counts corpses, and the rig hygiene rule told you to
    trust it** (R26). `get_all_unit_states()` returns one record per **slot** and buckets it by
    logical activity — there is no `DEAD` name in `LOGICAL_ACTIVITY_NAMES`, so a dead unit
    keeps reporting whatever it was doing and an unused slot reports `IDLE`. One measured
    window: `Units: ACTING=31, WALKING=17` on a 48-slot battle — **16 alive**. The two arms of
    correction 11 print the *identical* histogram three windows running while the live count
    falls 12 → 8 → 6. Fixed: the line now reads `Units: 12/16 alive: WALKING=7, ACTING=6,
    IDLE=3`. Every "read the histogram before believing a run" instruction in this document
    was, until R26, an instruction to read a number that cannot see a death.
13. ❌ **The per-tick `_check_state_changes` was not introduced by #93, and W9's "confirm it
    against #93" cannot be answered as written** (R27). Issue #93 is *per-ability cooldown
    tuning* (`DEFAULT_COOLDOWN_TICKS`). The per-tick call came from commit **`14cd63bc3`**
    (2026-08-22), whose message cites #93 only for the `ACTION_COMMITTED` workaround it forced
    on the gambit suite; `CombatLoop.gd`'s own comment inherited that "(#93)" and reads as a
    provenance claim. The commit IS the record, and it answers W9's objection in W9's favour:
    its stated purpose is *"any state a unit ENTERS AND LEAVES inside one batch is coalesced
    away"*, with `AWAITING_IMPACT` as the named symptom — state edges, nothing else. It no
    longer matters, because of correction 14.
14. ❌ **W9's second factor is false: the gate does NOT open more often as the cast grows**
    (R27, F34). The entry argued `P(any of N units changed state this tick)` goes to 1 as N
    grows. Measured at 16, 32, 48, 64 and 80 slots, the gate opens on **5–40 % of ticks with no
    trend in N**, and **~1 unit** has moved when it does. A unit changes logical state about
    once per second, not once per tick; six times the cast is six times the events landing on
    the same ticks. The item was sized off a factor that does not exist — which is the failure
    R25's W2 filed and the reason W9's own entry said to count the gate first.
15. ❌ **W11's two filed mechanisms are BOTH false, and the cost is a mutex wait** (R28,
    F39–F42). The entry named the per-call `_FedsBank.load_from_file` and
    `_pick_unit()` → `_reap_dead_sessions()`. Timed: the load is **0.087 ms of a 25.7 ms
    call (0.3 %)**, and **`_pick_unit` is not on this path at all** — `play_one_shot` routes
    to `_pick_event_unit`, a 2-element walk with no reap in it. **99.8 % of the call is
    `_audio_mutex.lock()`**, waiting on `_scheduler_main`, which is over its 4.16 ms/sub
    budget because un-reaped sessions stay linked into their unit's entity list and are
    sequenced forever (~32 µs/entity/sub). Both mechanisms were **read from the source and
    never timed**, which is the same failure as corrections 6 and 14 — third firing.
16. ❌ **`Performance.TIME_PROCESS` is a per-SECOND MAXIMUM that INCLUDES the render, and
    this document's discriminator is built on it being neither** (R29). *"Godot's
    `TIME_PROCESS` is main-thread **script** time only"* and the per-frame identity under it
    are both wrong. `main/main.cpp` accumulates `process_max = MAX(process_ticks,
    process_max)` and publishes it via `performance->set_process_time(...)` **inside the
    once-per-second block**, resetting it there — so one value is held across the ~1 000
    frames of the next second, and it is a **max**, never a mean. And `process_ticks`
    brackets `main_loop->process()` **+ `NavigationServer::process()` +
    `RenderingServer::sync()` + `RenderingServer::draw()`**, so the render submit and the
    wait on the previous frame's draw are already inside the term the identity then adds
    separately. `PerfMonitor` sums that monitor per frame and divides by frames, which is a
    mean of per-second maxima; its `est_other_mean` is the clamped remainder of the invalid
    subtraction and **prints 0.00 ms in every run in this document.** The tell was in plain
    sight for 28 rounds: R29's static arena arm printed `frame_time: mean=0.66ms` on the line
    directly above `cpu_proc: mean=14.28ms`. **Nothing in the standing diagnosis rests on
    it** — the CPU-vs-GPU headline was settled by `--gpu-profile` (0.16 ms) and by the
    `[PERF]` buckets, both independent of this monitor — but no future round may use
    `cpu_proc` or `est_other` to size anything. Use the R29 head/tail bracket (W5).
17. ❌ **W13's "the panel does the right thing three times over" is TWO times, and the third
    was defeated by the engine rather than by the caller** (R30). `_build_ui()`'s closing
    `set_process(false)` runs before the panel enters the tree — every panel here is built
    `new()` → `setup()` → `register_panel()` — and `Node`'s `NOTIFICATION_READY` then calls
    `set_process(true)` for **any script that defines `_process`**, *before* `_ready`
    (`scene/main/node.cpp:272`). That line has never had an effect in any build. The
    bookkeeping is the small half; the large half is that the entry's fix shape follows from
    the wrong mechanism. *"Give `on_hidden()` a caller"* would have fixed the mixer and left
    **`ScenarioVMDebugPanel`** — a full disassembly repopulate every frame, no `set_process`
    call anywhere in the file — running exactly as before, because there was nothing on it
    for a caller to switch off. Of 41 `BaseDebugPanel` subclasses three define `_process`;
    the census saw one because the arena instantiates one. **A census bounds what was LOOKED
    AT, not what is there** — and this document has now been caught reading a census as a
    population twice (correction 12 was the other).
18. ❌ **W14's PAR correction was DEAD, not WRONG — `pixel_aspect` ships at 1.0** (R30). The
    entry reads as a visible defect (*"the dialogue tail's screen-x is never stretched by
    `pixel_aspect`, which is the exact defect ADR-0036 describes"*), and #956 was filed on
    that framing. But `project.godot [shader_globals]` declares `pixel_aspect = 1.0` and no
    `render.pixel_aspect` override is committed, so the multiply the dead guard was skipping
    is a multiply by **one**. No frame the player has ever seen was in the wrong place, and
    fixing it moves nothing on screen today. What was actually broken is the surface's
    *response to a PAR scrub* — ADR-0036 dec. 2's opt-in, which it silently was not
    honouring. Still worth fixing, still the reason it was fixed; **not** the visible defect
    it was filed as. The pattern: the *mechanism* was verified against the engine source and
    the *consequence* was never checked against the shipped value, which is correction
    6/14/15's read-not-timed failure wearing a different coat.
19. ❌ **W6's entry cited a line that had moved, and described ONE loop where there are
    TWO** (R31). Verified on `3854f4fcd`: `src/gpu/CombatLoop.gd:565` is
    `if unit_idx < 0 or unit_idx >= all_states.size():` — an unrelated bounds check. The
    combat drain is at **654**. The one the entry never mentions is at **604**, inside
    `if victory_achieved:` ("keep animations ticking but skip GPU/state processing"),
    draining the **same accumulator** with the same absent ceiling; post-victory animation
    is exactly where a long drain would be paid. A clamp on one and not the other would
    have been a partial fix that read as a complete one. ⚠ And the fix SHAPE the entry
    implies — cap the loop's iterations — is the wrong one twice over. It would have
    broken ADR-0239: the turn gate `break`s out mid-drain and **keeps the accumulator
    remainder on purpose** ("what makes the resume seamless"), so the post-loop "discard
    the excess" that a cap requires would silently destroy it. And any cap expressed in
    TICKS is a red: four navigator proofs run at `SIM_TIME_SCALE := 40.0`, and
    `NavigatorGarilandVictoryTest` needs ~44 ticks a frame to make its 120 s budget. The
    shipped fix clamps the **delta**, in **real** seconds, at the one place both drains
    draw from. Same shape as 17/18: the mechanism was read off the source and the
    consequence was checked against nothing.
20. ❌ **W4's open arm was UNREACHABLE from this document's own rig, and had been since
    #866** (R31). Two changes in W4's "Landed already" half compose into a third that
    nobody stated: `GPUArena._ready()`'s unconditional `show_overlay()` was deleted, and
    the strategy-phase call was gated on `not DebugConfig.combat_autostart`. **Every run
    in `## Auto-deploy run command` passes `--combat-autostart`.** No flag, no setting and
    no code path was left that would open the overlay in an automated run — so every
    "overlay open" measurement taken after #866 was in fact **the closed arm**, and the
    entry read as though the open arm were merely un-*prioritised* rather than
    unreachable. `--debug-overlay` (R31) is the reachability fix, and it prints
    `os_windows` because the next failure mode along is an open arm whose second window
    never maps.

## Open

Open *work* lives in the Work list above — this section holds only what is open and is
**not** a work item.

- ~~W1's fix shape — A (columns) or B (lean dictionary)?~~ **RULED: B**, with the two
  instruments that close its silent failure mode. Built in R22; see **W1**.
- Whether to revert the now-unjustified `project.godot` driver keys. The justification was
  withdrawn (round 13) and the keys were already reverted to `HEAD`; nothing depends on the
  answer, so it is recorded rather than ticketed.
- **Whether to rebuild `dev_build=yes` at `f2a208da6`** (~6 min) to get a clean optimizer
  number. R24 measured the existing pair and states its result as a pair-of-builds
  comparison, so nothing is blocked on this — but the 5.33× stays unverified until it is
  done, and W3's row now carries a measured figure that is *not* that number.
- ⚠ **R25 — whether this effort has a subject left.** ⚠ **R26 corrects the numbers in this
  bullet: 2.08 ms / 482 fps was the 500 fps cap** (correction 11); the real figure is
  **1.3 ms at 745 fps — 19 % of the 6.94 ms budget**, which only sharpens the point. W2, the last ranked in-code
  item, was built and came in at **−0.014 ms**. Two questions follow, neither a measurement:
  1. **Is the memo kept or reverted?** It is one file, every signature unchanged, proven
     equivalent over 26 473 comparisons, and it removes real work — but the work it removes is
     worth ~0.014 ms/frame. It also carries a fix for the `_timings` crash the scan had, which
     is worth keeping either way and is two lines on its own.
  2. ~~**Is there anything left to optimise?**~~ **ANSWERED (R26): yes** — R26 said W9,
     **R27 re-answers it: W11**, the swing SFX on the tick path (3.8× the frame at 80 units,
     0.3 ms/attack at 13). The
     stress fixture found a real cliff — `chk` goes from 0.01 ms/frame at the shipped cast to
     13.24 ms/frame at 80 units, 100 % of the `edge` bucket at every size — plus W6 as its
     amplifier. Neither reaches a player at 13 units, and **that is the honest framing**: they
     are headroom items, not current-cost items. The shipped game has 5× the cast in hand
     before either fires. What is genuinely closed is *"is the game slow?"* — it is not: the
     heaviest frame the shipped cast produces is **1.3 ms of a 6.94 ms budget** (R26,
     correction 11).

Everything else that was listed here has become a Work list entry: F19's sprite-repaint
hypothesis was **W5**, and R29 **refuted it and closed the item** — the block outside
`CombatLoop` is 0.85 ms, half of it the engine drawing the map, and sprite repaint is
0.071 ms of it. The `dev_build=no` rebuild is **W3**.

- ⚠ **R29 — should the frame's script/not-script bracket be committed?** The 50-file
  `_process` census that produced W5's table must not be, and was reverted. But the
  three-file part of it — `PerfMonitor` stamping the head at `process_priority = -100`, a
  child probe stamping the tail at `1000`, drained by `CombatLoop`'s existing `[PERF]`
  report — is the only instrument this effort has ever had that can say how much of a frame
  is script, and **W8 is asking for exactly this kind of witness**. It is ~40 lines across
  three files and costs nothing measurable. Committing a debug surface is a design call, not
  a measurement, so it is recorded here rather than done.

## Rig hygiene for anyone repeating this

- **`misc:render_unfocused_fps` is a cap, and "far above what you expect" is not good enough.
  A/B THE SETTING ITSELF.** Raise it via `hyprctl keyword` (restore after) and **state the
  value used** — then run one arm at that value and one at 4× it, and believe the number only
  if the two agree. ❌ This rule has now been wrong **three times, at 60, 144 and 500**: R12
  found 60 capping every early round, R25 (F28) found 144 capping R24's 6.0 ms, and R26 (F29)
  found **500 capping R25's own 2.08 ms / 482 fps** — 482 is 96 % of 500, and the shipped cast
  actually runs at **1.3 ms / 745 fps**. Each time the rule was corrected to a bigger number,
  and each time the bigger number became the next cap, because the engine kept getting faster
  than the rule. **A measured fps within ~10 % of the setting is a cap until an A/B says
  otherwise.**
- **Per-frame bucket figures move with the frame rate**, because they average per-*tick* work
  over frames. Compare buckets only between arms measured at the same setting; ratios survive,
  absolutes do not.
- `--print-fps`, `--gpu-profile`, `--disable-vsync`, `--max-fps` all exist; no
  `project.godot` edit is needed for any of them.
- `hyprctl dispatch sendshortcut ",F3,class:godot-standalone"` drives the running game;
  verify the effect landed (window count) rather than assuming.
- Check `/proc/loadavg` **and** `pgrep -f run_tests_parallel` before believing any number.
  A parallel suite in another worktree inflated one round's figures 9×, and another session
  sharing this box held it at load 7–11 for an entire session. **Queue behind it; do not
  measure through it.**
- **Never invoke Godot with `--headless`.** Every flag needed exists on the CLI, and a window
  opening on the user's display is not a reason to avoid running it.
- **Pass `--skip-strategy`, and read the `Units:` line before believing a run** (R24, F27).
  Without it the arena sits in the strategy phase and nothing deploys: 60 s of
  `IDLE=15, WALKING=1`, plausible bucket numbers, exit 0. `simulation.skip_march` in
  `tune_overrides.json` is `AUTOSAVE`-bound and cannot be trusted to hold any value. At seed
  424242 an engaged `[PERF #2]` reads `Units: 12/16 alive: ACTING=9, WALKING=4, IDLE=3`.
- **Read the `n/m alive` count, NOT the histogram** (R26, correction 12). The histogram counts
  **slots** and there is no `DEAD` activity: a corpse keeps reporting `ACTING`, and an unused
  slot reports `IDLE`. `ACTING=31, WALKING=17` on a 48-slot battle was **16 alive**. The
  `alive` count is the one that can see a death; it was added in R26, and every histogram
  quoted in this document before then is a slot census.
- **The stress fixture is `--stress-units=N`** (R26/W7): it pads **each team** to `N` by
  cloning, so the cast is `2N` and `units_per_battle` sizes itself. `N=0`/absent is the shipped
  13-unit cast, byte-for-byte. Gariland tops out near **111 units**; past that it warns and
  under-fills. Verify with the `Units: n/m alive` line — `m` is what the sim actually
  allocated, and it is the number the buckets scale with.
- **The overlay reopens itself unless you close it in `user_settings.json`.**
  `DebugOverlay._ready()` restores `debug_window.was_visible`, so an "overlay-closed" arm is
  only closed if you set that false before the run — and the file is rewritten on every quit,
  so back it up and restore it (W4 inflates `state` +28 %, `GPU` +33 %, `total` +25 %).
- **Never edit `project.godot` while the Godot editor is open on that worktree.** It rewrites
  the file and garbles comments into corrupt setting keys. Use CLI flags.
- **Where to work.** Not `/home/curry/Repos/fft-monorepo-main` — that is the pinned asset hub,
  permanently on `main`, never branched. `/home/curry/Repos/fft-monorepo-perf` is cut for this
  effort: ROM assets, the SPU library and the `.godot` cache are already symlinked to the hub,
  so it boots without re-populating anything. Cut a topic branch there from `origin/main`.
- **Interleave arms A/B/C/A/B/C — never block them.** Ambient load on this box swings 7–15 and
  moves results ~6 %. Interleaving is what let the overlay finding rule out the load confound:
  the winning arm ran on a *busier* box than its control.
- **Measure frames-completed-in-fixed-wall-clock, not `frame_time: mean`.** A ~1.8 s boot spike
  lands in every run and skews the mean by ~0.6 ms.
- `user_settings.json` lives at `res://user_settings.json` (not `user://`) and is **written on
  every quit**, so arms contaminate each other through it. Back it up and restore it.
- **Queue behind the other session by the BINARY, not the cmdline** (R29). `pgrep -f godot`
  matches other sessions' immortal waiter shells — several of them sit on this box forever
  with `godot` in their own `bash -c` string — so a "wait until the box is clear" loop written
  that way **never fires**. It cost R29 one aborted pass. Use
  `ps -eo comm=,args= | awk '$1 ~ /^godot/' | grep -v -- --editor`; `comm` is the executable,
  and a waiter shell is `bash`. Same defect family as the handoff's trap 2.
- **`--perf-debug` alone gives you no navigator battle.** `NavigatorMain` has no CLI flag for
  the walk: set `"navigator.autoplay": true` in `config/tune_overrides.json` (AUTOSAVE-bound —
  back it up and restore it, same as `user_settings.json`) and it drives itself. A **600 s**
  headful run reaches the Orbonne battle at ~+370 s and the **Gariland** battle — the arena's
  own map — at ~+560 s, and yields two `[PERF]` windows each. There is no seek from the CLI;
  `ScenarioDebugSession.navigator_start_root` is a plain autoload var the F3 panel writes.
- **A W5-style census window is only valid from `[PERF #2]` onward on the navigator.** The
  accumulators are drained by `CombatLoop`'s report, and on the navigator no loop exists
  during the cinematic walk — so `[W5 #1]` averages every frame since boot (140 000–280 000 of
  them) and its `non_loop_script` comes out negative. `#1` is a useful *whole-cinematic*
  figure (0.65–0.81 ms/frame) and a useless *window*.

---

## Round log

---

## Round 1 — baseline auto-deploy, seed 424242, 150 s

`run_arena.sh r1_baseline 150 --combat-seed=424242` → `run_r1_baseline/`.
16-slot battle (`units_per_battle = 16`), team0 = 8 (Ramza + cadets + Delita),
team1 = 5 ENTD. Gariland / MAP022.

### `[PERF]` buckets (CombatLoop `_process`, 3 s windows)

| # | tick | GPU avg / max | state | visual | total avg / max | delta (fps) | tpf | units |
|---|---|---|---|---|---|---|---|---|
| 1 | 180 | 4.56 / **37.59** | 1.99 | 2.64 | **9.22** / 41.46 | 19.6 ms (51) | 1.2 | WALK 8, ACT 5, IDLE 3 |
| 2 | 361 | 4.28 / 22.62 | 1.83 | 1.50 | 7.64 / 26.19 | 18.0 ms (55) | 1.1 | ACT 9, WALK 4, IDLE 3 |
| 3 | 541 | 3.23 / 10.47 | 1.81 | 1.04 | 6.12 / 11.86 | 16.1 ms (62) | 1.0 | WALK 2, ACT 11, IDLE 3 |
| 4 | 722 | 2.81 / 9.45 | 1.74 | 0.66 | 5.26 / 10.14 | 16.1 ms (62) | 1.0 | WALK 4, ACT 9, IDLE 3 |

### PerfMonitor session summary

```
seed=424242  frames=9211  spikes=17  threshold=33.0ms
frame_time: mean=16.72ms  max=2014.98ms  est_fps_mean=59.8
cpu_proc:   mean=28.15ms  phys: mean=0.66ms
```

⚠ `cpu_proc mean=28.15ms` exceeds `frame_time mean=16.72ms`, and individual spike rows
read `cpu=1922.0` / `cpu=2117.2` on frames whose real time was 124 ms / 69 ms.
**`PerfMonitor`'s `TIME_PROCESS` reading is not trustworthy** — it is sampled at
`process_priority = -100` (start of frame) and the unit scaling is evidently wrong.
Treat the CPU column as unusable until fixed; that is a finding in its own right
(the `est_other_mean` line clamps to 0.00 and hides the render/present remainder).

### nvidia-smi, 1 Hz over the whole run

```
utilization.gpu :  11–17 %   (one 32 % blip)
utilization.mem :   1–3 %
power.draw      :  60–84 W   of a 600 W cap
clocks.sm       :  1.9–2.8 GHz
memory.used     :  3.8–4.3 GB of 32 GB
```

### Findings

**F1 — the GPU is idle. It is not the bottleneck.** 12–17 % utilization, 1–3 %
memory-controller, ~70 W of 600 W. An RTX 5090 rendering a 1024×960 window of
sprite quads is doing nothing. Any theory that blames GPU throughput is dead.

**F2 — the frame rate is pinned at ~62 fps on a 144 Hz display, independent of load.**
The battle reached VICTORY early (log line 331, ≈ tick 900). The remaining **~140 s ran
the post-victory path**, which returns from `CombatLoop.tick()` before any GPU step,
state check, or visual update — near-zero combat work. It still reported **62 fps, every
heartbeat, for 140 consecutive seconds** (`fps=62/63` × 130 samples, dead flat).
A workload limit is noisy; a flat 16.1 ms is a **present cap**. Frame budget is
therefore **16.6 ms, not the 6.94 ms a 144 Hz display should give**.

**F3 — that cap is why engagement "feels laggy" rather than "gets gradually slower."**
Under FIFO vsync, missing the deadline does not cost you a few percent — it costs you
a whole present interval. `[PERF #1]` shows CombatLoop alone at 9.22 ms avg (55 % of a
16.6 ms budget) with maxes at 41 ms while units are converging and acting; the frame
falls to 19.6 ms and the reported rate collapses to 51 fps. As units die and the work
drops to 5.26 ms, it snaps back to the 62 fps cap. Exactly the cliff the user describes.

**F4 — the per-frame combat cost is CPU-side and large for 16 units.**
`GPU: 2.8–4.6 ms` is *not* GPU compute — it is the tick while-loop, and
`GPUBatchSimulator._run_tick()` ends in `_rd.submit()` + **`_rd.sync()`**, a blocking
CPU↔GPU round trip, plus `_read_tick_columns()`'s blocking `buffer_get_data`. Two
full stalls per tick, on the main thread, inside `_process`. `state: ~1.8 ms` is
`get_battle_unit_states()` rebuilding **16 units × 99 string-keyed Dictionary fields =
1584 inserts every frame**. Neither cost is graphics.

### Round 1 verdict

> **Bottleneck is CPU (main thread), not GPU** — and it is amplified by a 60 Hz
> present cap that leaves no headroom to absorb the engagement spike.

### Open questions for round 2

1. Why 60 Hz on a 144 Hz monitor? X11/XWayland vs the native Wayland backend is the
   first suspect (`XDG_SESSION_TYPE=wayland`, but `DISPLAY=:0` is also set and
   Xwayland is resident). → **round 2 A/B on `--display-driver`.**
2. The 150 s window measured mostly post-victory idle. Need a run that stays *engaged*
   → `--combat-auto-reset`.
3. `PerfMonitor`'s CPU column is broken; the render/present remainder is invisible.
---

## Round 2 — display-driver A/B (the 60 Hz cap)

Same scene, same seed 424242, same 70 s, back-to-back, sequential (no overlap).
`--display-driver wayland` vs `--display-driver x11`.

| | **x11** (what "default" resolves to) | **wayland** |
|---|---|---|
| frames rendered in 70 s | 4 263 | **8 887 (2.08×)** |
| mean frame time | 17.37 ms | **8.34 ms** |
| mean fps | 57.6 | **119.9** |
| fps once the battle is over (no work) | flat **62** | flat **145** |
| fps while units are engaged | 47–62 | 53–82 |
| GPU utilization | 12.9 % | 14.8 % |
| GPU power | 64 W | 68 W |

`godot --verbose` on the default driver prints `XInput: … xwayland-pointer:1` —
Godot picks **X11**, which on Hyprland is **XWayland**, which presents at 60 Hz.

**F5 — the 60 Hz cap was XWayland, not Hyprland and not the game.** The compositor
was always willing to present at 144. Identical CPU work, identical GPU load, 2.08×
the frames. *(This is why there is nothing to change in the Omarchy/Hyprland config —
the monitor and compositor were never the limit.)*

### Fix applied

`godot-learning/project.godot`, `[display]`:

```ini
display_server/driver="wayland"
```

⚠ **The platform-tagged key does not work here.** `display_server/driver.linuxbsd="wayland"`
was tried first and had **no effect** — the run still came back at 62 fps with XWayland
input devices. Godot reads the display driver before feature-tag overrides resolve, so
only the untagged key takes. Verified after the change: `--verbose` reports **zero**
xwayland devices with no CLI flag. `--display-driver x11` on the command line still
overrides it, so the escape hatch is intact. Because the key is untagged it would also
apply on Windows/macOS, where `"wayland"` is not a valid driver — acceptable here
(the game is fork-on-Linux only per CLAUDE.md) but worth knowing.

---

## Round 3 — `tests/GPUPerfBenchmark.tscn` (already in the tree)

Isolates `step_tick` from everything around it. Seed-locked 4v4 (8 slots), 800 ticks
after 40 warmup. **Idle machine.**

```
PERF_RESULT  mean_us=133.7 median_us=109.0 p95_us=287.0 p99_us=583.0 max_us=879.0
PERF_BATCHED k=1  : 128.8 us/tick     k=2 : 107.6     k=8 : 83.8
             k=30 :  79.8 us/tick     k=60:  81.3
PERF_READBACK per_call_us=3.0  per_frame_us=1056.6
              old_tick_us=890.6 (full 99-field snapshot rebuild)
              new_tick_us=62.2  (5 lean columns)
```

**F6 — the compute sim is NOT the problem.** A full 8-pass tick, including the blocking
`submit()` + `sync()`, is **109 µs median**. At the 60 ticks/s the loop runs, that is
**6.5 ms per SECOND** — 0.65 % of one core. Batching to K=30 would save ~50 µs/tick
(3 ms/s). Real, but it is not where the frame went. The `_run_tick` fence was already
optimized (the code's own comment records the 8-round-trips-per-tick era).

**F7 — the 99-field snapshot rebuild is expensive and is still paid once per frame.**
`get_all_unit_states()` for **8** units costs **890 µs**; the arena runs **16**, and
`_check_state_changes()` calls it every frame. That predicts ~1.8 ms/frame — and the
arena's `state:` bucket measures **1.66–1.99 ms**. Exact match. It is not GPU readback
(`_read_battle_region` is version-cached; a repeated read is **3.0 µs**) — it is
GDScript building **16 × 99 = 1 584 string-keyed Dictionary entries every frame**.

---

## Round 4 — verify the fix, and split the mislabeled bucket

The `GPU:` bucket in `[PERF]` is **not GPU time**. It wraps the whole tick while-loop:
`step_tick` **+** `_read_tick_columns` **+** per-tick `_check_state_changes` **+**
`cinematic_manager.update_edge` **+** `projectile_manager.advance_one_tick` **+**
`unit.advance_frame()` for every unit. Instrumented `src/gpu/CombatLoop.gd` to split it
four ways (`step` / `cols` / `edge` / `anim`), printed under the same
`--perf-debug` gate as the line above it.

---

## Round 5 — CONTAMINATED, do not cite the absolute numbers

`load average: 50.10`. Full parallel test suites were running in **two other worktrees**
(`fft-monorepo`, `fft-monorepo-find`), plus a Godot editor on `NavigatorMain` and a
Blender instance holding 1.3 GB of VRAM. The arena measured 8.7 fps mean — a contention
artefact, not a regression. Verified my runs cannot corrupt those suites: each worktree
owns a **real** `.godot/` directory, none is a symlink into the hub.

The *ratios* inside the split held across all 24 reports of that run, so they are worth
recording as a hypothesis to re-test clean:

| bucket | share of the tick loop |
|---|---|
| `anim` — per-unit `advance_frame()` | **66–70 %** |
| `edge` — per-tick state edge + cinematic + projectile | 12–20 % |
| `step` — `step_tick()`, the actual GPU submit+sync | **11–13 %** |
| `cols` — `_read_tick_columns()` lean readback | 6–8 % |

**H1 (to confirm on an idle machine): the tick loop is dominated by sprite animation,
not by anything GPU.** `Unit.advance_frame()` builds a fresh 4-key Dictionary
(`_build_view()`, including a `get_camera_quadrant()` call) **per unit per tick**, then
runs `AnimationClock.advance_frame` → two `PlaybackSet`s → a `frame_changed` repaint
cascade. At 16 units × 60 ticks/s that is 960 view-dict builds and 960 clock advances
per second, each capable of triggering a repaint.

**Status: waiting for the machine to go idle before re-taking round 5.**
---

## Round 6 — static analysis of the `anim` bucket (no measurement; machine still at load ~45)

Read the whole per-unit-per-tick animation path to find what H1's 66–70 % is made of.

### The call tree, per unit, per GPU tick

```
CombatLoop tick loop
└─ Unit.advance_frame(speed, 1)                         src/units/Unit.gd:983
   ├─ _build_view()                                     → allocates a 4-key Dictionary,
   │                                                      calls get_camera_quadrant(),
   │                                                      reads PSXDisplay.live_camera_angle
   └─ UnitDisplay.advance_frame(view, n, r)             addons/…/render/UnitDisplay.gd:201
      ├─ set_view(view)
      └─ AnimationClock.advance_frame(n, r)             addons/…/sequence/AnimationClock.gd:86
         ├─ n × PlaybackSet(normal).advance_frame()  →  body + wep1 + eff1
         └─ r × PlaybackSet(react ).advance_frame()  →  body + wep1 + eff1
                                                         = 6 AnimationPlayback.advance_frame()
```

**H1a FALSIFIED — the speed multiplier is not the mechanism.** I expected WALKING and
ACTING to multiply `normal_reps`, which would have explained "laggy exactly when they
engage" directly. They do not: `MovementTimingConfig` has
`HORIZONTAL_MOVE_SEQ_SPEED = 1`, `CHARGE_SEQ_SPEED = 1`, **`ABILITY_SEQ_SPEED = 1`**.
Only `VERTICAL_MOVE_SEQ_SPEED = 2` (cliff jumps). So `normal_reps` is 1 almost always
and the per-tick playback count is a flat 6.

### What each of those 6 calls actually does

`AnimationPlayback.advance_frame()` (`addons/…/sequence/AnimationPlayback.gd:126`) makes
**four full linear scans of the sequence's opcode array**, every call:

| call | file:line | scans for | cached? |
|---|---|---|---|
| `AnimationFrameCalculator.get_duration(anim_id, sequences)` | `AnimationFrameCalculator.gd:48` | sums `LOAD_FRAME_WAIT` durations | **no** |
| `AnimationFrameCalculator.is_looping(anim_id, sequences)` | `:65` | any `INCREMENT_LOOP` | **no** |
| `AnimationFrameCalculator.get_frame_at(anim_id, anim_frame, …)` | `:24` | walks to the frame | **no** |
| `_process_side_effects(from, to)` | `AnimationPlayback.gd:190` | 12-branch `elif` chain over every opcode | **no** |

…plus `has_pause()` and `is_hold_forever()` (two more scans) on the completion edge.

Every scan does `op.get("op_code_id", 0)` — an **untyped, string-keyed Dictionary
lookup — per opcode**, and `get_frame_at` / `_process_side_effects` do two or three more
on the ops they match.

**F8 — the animation pump does ~23 000 full opcode-array walks per second.**

```
6 playbacks × 4 scans          =    24 walks per unit per tick
× 16 units                     =   384 walks per tick
× 60 ticks/s                   = 23 040 walks per second
```

Sequence size, measured off `assets/sprites/animations/type1_seq.json`
(228 sequences, 2 548 opcodes total): **mean 11.2 opcodes, median 10, max 58**.

```
23 040 walks/s × ~11 opcodes  ≈  250 000 opcode iterations per second,
                                 each ≥ 1 string-keyed Dictionary.get()
```

Against the clean round-4 numbers (`GPU:` bucket 2.81–3.99 ms/frame, of which the
contaminated split says 66–70 % is `anim`), that predicts **~2.0–2.8 ms/frame of
animation bookkeeping** — consistent, and it is the single largest item in the frame.

**F9 — four of those six scan kinds are pure functions of `(anim_id, sequences)` and
depend on nothing that changes between ticks.** `get_duration`, `is_looping`,
`has_pause`, `is_hold_forever` do not read `anim_frame` at all. `sequences` is the
shared, immutable `type1_seq` dictionary loaded once by `AnimationDatabase` (which
already keeps a `_json_cache`). They are recomputed from scratch 60 times a second per
playback for an answer that cannot change. `get_frame_at` does depend on `anim_frame`,
but it is a lookup into a table derivable once per `anim_id`.

*(Noted, not implemented — per the loop's instruction. This is the shape of the fix, not
the fix.)*

### Frame accounting so far (clean round-4 / round-2-wayland numbers)

| | ms/frame in combat | attributed? |
|---|---|---|
| `anim` — animation pump | ~2.0–2.8 | ✅ F8 |
| `state` — 16 × 99-field snapshot rebuild | 1.66–1.99 | ✅ F7 |
| `visual` — `update_visual_positions` | 0.6–2.4 | partial |
| `edge` — per-tick state edge / cinematic / projectile | ~0.5 | partial |
| `step` — the actual GPU submit+sync | ~0.4 | ✅ F6 (not a problem) |
| `cols` — lean readback | ~0.2 | ✅ F6 |
| **CombatLoop total** | **4.6–7.9** | |
| **rest of the frame** (render submit, Unit `_process`, UI3, effects, present) | **~7–9** | ❌ **unattributed** |

**The biggest remaining unknown is the ~8 ms outside `CombatLoop`.** Idle on Wayland is
6.9 ms/frame but that is the 145 Hz vsync floor, so the *uncapped* idle cost is unknown
and the render half cannot be separated from the present wait.

### Round 7 plan (needs an idle machine)

1. **Re-take round 5 clean** — confirm the 66–70 % `anim` share on a quiet box.
2. **Disable vsync temporarily** (`display/window/vsync/vsync_mode=0`, reverted after)
   and measure uncapped idle vs uncapped combat. That is the only way to size the
   render half against the script half, and it also repairs the blind spot left by
   `PerfMonitor`'s broken CPU column.
3. Sample `nvidia-smi` throughout to confirm the GPU stays idle when uncapped.

### Blocked on

`load average 44.93`, 25 `godot` test processes across `fft-monorepo` and
`fft-monorepo-find`, plus a headless Chromium at 578 % CPU. Monitor armed for load < 8.
---

## Round 7 — the engine binary is built with NO OPTIMIZATION

Chasing the unattributed ~8 ms, I went looking at what the frame runs *on*.

`godot` on `$PATH` → `/usr/local/bin/godot` → `~/Repos/godot/bin/godot.linuxbsd.editor.dev.x86_64`
(1.08 GB). The `.dev` in that filename is SCons' `dev_build=yes` marker. Confirmed from
the fork's own `.scons_env.json`:

```
dev_build     = True
target        = editor
optimize      = none      ← -O0.  No optimization. At all.
debug_symbols = True
production    = False
lto           = none
CCFLAGS       = [… '-gdwarf-4', '-g3', …]
```

**F10 — the game runs on an unoptimized, `DEV_ENABLED` editor build of the fork.**
Every C++ line the frame touches — the GDScript VM interpreter loop, Variant dispatch,
Dictionary hashing, the servers, the renderer — is compiled `-O0` with dev asserts live.

### Measured: how much that costs

Wrote a standalone pure-GDScript microbenchmark in the scratchpad
(`vmbench/`, **not** in the repo — it has no scene, no rendering, no engine subsystems).
It runs the exact shape of the real hot loop: an uncached linear scan over string-keyed
opcode Dictionaries, sized to the measured corpus (11 ops/sequence, 228 sequences),
200 000 walks ≈ 9 s of the arena's animation pump.

| build | run 1 | run 2 | run 3 | per opcode |
|---|---|---|---|---|
| **fork 4.8, `dev_build=yes`, `optimize=none`** | 1766.1 ms | 1784.2 ms | 1788.6 ms | **803–813 ns** |
| **stock 4.7.1 (Arch release build)** | 333.8 ms | 329.4 ms | 339.2 ms | **150–154 ns** |

> **5.33× slower on the fork's dev build for identical GDScript work.**

Spread within each build is under 1.5 %, so the ambient load (~16) did not distort this —
it is single-threaded and there were free cores.

**Confounds, stated plainly:** the two binaries differ in Godot version (4.8 fork vs
4.7.1) as well as in optimization, and the Arch package is a production build with
different flags throughout. Some of the 5.33× is version, not `-O0`. The clean version of
this experiment is to build **the same fork** with `dev_build=no` and re-run — that is the
recommendation, and it is also the fix. But VM changes between 4.7 and 4.8 do not plausibly
account for a 5× gap; `-O0` does.

**This does not conflict with CLAUDE.md.** The rule is *use the compositor fork, never
stock 4.7* — because the engine-fold compositor is fork-only. It says nothing about
`dev_build`. An optimized build of the same fork satisfies the rule completely.

### Why this reframes everything above

Every absolute millisecond in rounds 1–6 was measured on a ~5× slow interpreter.
The **ratios** survive (all buckets are the same binary), but the **magnitudes** are not
the game's real cost. Scaling the round-2-wayland combat frame by even a conservative 3×
on the script half puts `CombatLoop` at ~1.5–2.6 ms instead of 4.6–7.9 ms.

**F11 — do not start optimizing GDScript until the engine is rebuilt optimized.**
The profile could reorder completely. The `anim` bucket (F8) is pure GDScript and would
shrink most; the `step` bucket (GPU submit/sync, F6) is driver/GPU latency and would
shrink least — so a rebuild could invert their ranking.

### Revised fix ranking (nothing below is implemented)

| # | fix | expected | cost | status |
|---|---|---|---|---|
| 1 | `display_server/driver="wayland"` — stop presenting through XWayland | **2.08× measured** | 1 line | ✅ **applied** |
| 2 | Rebuild the fork `dev_build=no` (keep `target=editor` for the editor, add a `template_release` for game runs) | up to ~5× on script cost | a recompile, **no code change** | not done |
| 3 | Memoize `AnimationFrameCalculator` — `get_duration` / `is_looping` / `has_pause` / `is_hold_forever` are pure in `(anim_id, sequences)` and recomputed 60×/s per playback (F8/F9) | ~2.0–2.8 ms/frame today | small, local | not done |
| 4 | Stop rebuilding 16 × 99 string-keyed Dictionaries every frame in `_check_state_changes` (F7) | 1.66–1.99 ms/frame today | medium | not done |
| 5 | `Tune`-backed `DebugConfig` flags read in per-unit-per-frame guards (`show_depth_center` in `Unit._process` ×16/frame; `perf_spike_*` ×2/frame). Each read is `is_registered` + `get_value` → 2 dict lookups, an eagerly-formatted assert message string, `Engine.get_process_frames()`, a dict write, `_coerce`. | **minor** (~19 reads/frame) | small | not done — and item 2 strips the asserts anyway |

Item 5 is listed for completeness, not because it is big — I measured the call count
before claiming it mattered, and it does not.

### Round 8 plan

1. Re-take round 5 clean (confirm the 66–70 % `anim` share) — still blocked on the box.
2. Uncapped-vsync run to size render vs script.
3. **Ask the user whether to rebuild the fork optimized** — it is a long compile and a
   change to their toolchain, so it is their call, not mine to make.

### Machine state this round

`load 13.5–16.6`, down from 52. Three `godot` test processes left in `fft-monorepo`,
plus a headless Chromium at 578 % CPU and Blender at 98 %. Still not clean enough for
the frame-level re-takes; fine for the single-threaded VM benchmark.
---

## Round 8 — the round-2 fix does NOT reach the way the game is actually played

Noticed two live Godot **editor** processes on this worktree:

```
pid  84113  --path …/fft-monorepo-main/godot-learning --editor            (10 h old)
pid 624957  --path …/fft-monorepo-main/godot-learning --remote-debug …
            --editor-pid 84113 --scene res://assets/scenes/NavigatorMain.tscn
            --wid 10485766 --display-driver x11 --position 768,177 --resolution 1024x960
```

The played scene carries **`--display-driver x11`**, put there by the editor. Traced it
through the fork's own source:

**1. The editor's own driver is an EDITOR setting, not a project setting.**
`main/main.cpp:3056` — for an editor launch the driver comes from
`run/platforms/linuxbsd/prefer_wayland`, read straight out of the editor settings file:

```cpp
if (display_driver.is_empty()) {
    if (prefer_wayland) { display_driver = "wayland"; }
    else                { display_driver = "default"; }   // → X11 here
}
```

`editor/settings/editor_settings.cpp:1149` defaults it to **`false`**, and
`~/.config/godot/editor_settings-4.8.tres` does not set it. **The editor runs on X11.**

**2. The editor forces the embedded game onto the editor's own driver.**
`editor/run/game_view_plugin.cpp:1364–1382` — after inserting `--wid`:

```cpp
#ifdef WAYLAND_ENABLED
    if (DisplayServer::get_singleton()->get_name() == "Wayland") { … "--display-driver", "wayland" }
#endif
#ifdef X11_ENABLED
    if (DisplayServer::get_singleton()->get_name() == "X11")     { … "--display-driver", "x11" }
#endif
```

**3. The project setting only governs a STANDALONE launch.**
`main/main.cpp:3161` — `display_driver = GLOBAL_GET("display/display_server/driver")`
sits on the non-editor path. That is the line round 2's fix targets.

### F12 — pressing Play in the editor bypasses the round-2 fix entirely

```
editor setting prefer_wayland = false  (default, unset)
        ↓
editor DisplayServer = X11
        ↓
editor appends --display-driver x11 to the embedded game
        ↓
game presents through XWayland at 60 Hz — project.godot never consulted
```

Every measurement in rounds 1–7 was a **standalone** `godot --path .` launch, which is
the path the project setting governs. If the user's real workflow is **F5 in the editor**
— and two live editor processes say it is — then they have been getting the 60 Hz cap all
along and the round-2 fix, as applied, does not reach them.

**The lever for that path is an editor setting, not a project setting:**
`run/platforms/linuxbsd/prefer_wayland = true` (Editor Settings → Run → Platforms →
Linuxbsd; flagged `set_restart_if_changed`, so it needs an editor restart). The editor
then runs Wayland and hands `--display-driver wayland` down to the embedded game — the
`WAYLAND_ENABLED` branch above — so embedding keeps working *and* the cap lifts.

`run/window_placement/game_embed_mode` is currently `0` = "Use Per-Project Configuration"
(the enum is `Disabled:-1, Use Per-Project Configuration:0, Embed Game:1, Make Game
Workspace Floating:2`). Setting it to `-1` would also dodge the forced driver by not
embedding at all — but that costs the embedded Game workspace, so `prefer_wayland` is the
better lever.

*Not changed — it is the user's editor config, and the loop says don't implement.*

### Correction to the round-2 write-up

Round 2 called `display_server/driver="wayland"` "the fix". That was too broad. It is
**the fix for standalone launches only**. The complete fix is both:

| launch path | lever | status |
|---|---|---|
| `godot --path . <scene>` (scripts, tests, my runs) | `project.godot` → `display_server/driver="wayland"` | ✅ applied |
| **F5 / Play in the editor** (the human workflow) | editor setting `run/platforms/linuxbsd/prefer_wayland = true` | ❌ **not applied — user's config** |

### Machine state

`load 11.4`, and **zero** test processes left — the suites finished. What remains is the
user's own work: headless Chromium at 578 % CPU (~6 cores), Blender at 97 %, the two
editor processes above (93.7 % + 24.5 %), and pcsx-redux at 44.7 %. The load-<8 monitor
timed out after an hour; that threshold was never going to be met while the user is
working. Frame-level re-takes still want a quieter box, or many repeats with the noise
declared.

### Still open

1. Round 5 clean re-take (confirm the 66–70 % `anim` share).
2. Uncapped-vsync run to size render vs script.
3. **User decision:** rebuild the fork with `dev_build=no` (F10/F11 — the 5.33× item).
4. **User decision:** flip `prefer_wayland` in their editor settings (F12).
---

## Rounds 9–11 — clean measurements, and two corrections to earlier rounds

Box was quiet-ish and **steady** (`load 11–12`, all of it the user's own long-running
Chromium/Blender/editor/pcsx, none of it spiky) — much better for A/B than round 5's
suite storm. No `project.godot` edit needed for the vsync arm: Godot has CLI flags
`--disable-vsync`, `--gpu-profile`, `--max-fps`, `--print-fps`.

### ❌ CORRECTION 1 — round 2's fix was NOT applied. Both keys are required.

Round 2 claimed `display_server/driver="wayland"` was "verified". It was not. That
verification ran while **both** the untagged and `.linuxbsd` keys were in the file; I then
deleted the `.linuxbsd` line and never re-checked. `grep -c xwayland` on the later runs
returned 0 only because those runs had no `--verbose` — the XInput lines never print
without it. A zero from a grep against output that cannot contain the pattern is not
evidence.

Probed all three configurations with `--verbose`, twice each, discriminating on
`Xinput 2.2 detected` vs `Wayland`:

| `project.godot` `[display]` | result | repeats |
|---|---|---|
| `display_server/driver="wayland"` only | **X11 / XWayland** | 2/2 |
| `display_server/driver.linuxbsd="wayland"` only | **X11 / XWayland** | 1/1 |
| **both keys** | **native Wayland** | 2/2 |

Reproducible and strange — neither key alone takes, both together do. The registered
create-function name really is lowercase `"wayland"`
(`platform/linuxbsd/wayland/display_server_wayland.cpp:2653`), so a simple case mismatch
does not explain it. **Both keys are now in the file.** Mechanism unexplained; the
behaviour is reproducible, which is what the fix rests on.

Consequence: **round 9's arms A and B both ran on XWayland**, not Wayland. Their CPU
buckets are still valid (script cost is driver-independent); their frame rates are the
XWayland story. Round 10 re-took both arms on genuine Wayland.

### F13 — the GPU does 0.12–0.19 ms of work per frame

`--gpu-profile`, 40 samples through live combat:

```
GPU PROFILE (total 0.122ms) … 0.143 … 0.157 … 0.158 … 0.174 … 0.188ms
```

Against the ~15 ms combat frame that is **~1 %**. Against a 144 Hz budget, ~2 %.
This is the engine's own GPU timing, not an inference from `nvidia-smi`. Combined with
12–24 % utilization and 74–90 W of 600 W across every run:

> **The GPU is not the bottleneck, is not close to being the bottleneck, and no amount
> of GPU-side work will change this. CPU 15 ms vs GPU 0.16 ms — roughly 100×.**

### The clean bucket split — H1 CONFIRMED

Round 10, native Wayland, vsync on, `[PERF #2]` (mid-engagement, ACTING 9 / WALKING 4):

| bucket | ms/frame | share of CombatLoop |
|---|---|---|
| **`anim`** — per-unit `advance_frame()` | **2.22** | **35 %** |
| `state` — 16 × 99-field snapshot rebuild | 1.53 | 24 % |
| `visual` — `update_visual_positions` | 1.32 | 21 % |
| `edge` — per-tick state edge / cinematic / projectile | 0.69 | 11 % |
| `step` — **the actual GPU submit + sync** | 0.38 | 6 % |
| `cols` — lean readback | 0.19 | 3 % |
| **CombatLoop total** | **6.37** | |

`anim` is **64 % of the mislabeled `GPU:` bucket** and the largest single item in the
frame — confirming H1 and matching F8's independent prediction of 2.0–2.8 ms. The
round-5 ratios survive the clean re-take; only their magnitudes were inflated (`anim`
read 19.94 ms under load, 2.22 ms clean — a 9× contention artefact).

Note `step` at **0.38 ms/frame**: the thing named "GPU" in the report is 6 % of the loop.

### Sizing the render half — uncapped runs

| | vsync on | `--disable-vsync` |
|---|---|---|
| frames in 70 s | 4 416 | **12 770 (2.9×)** |
| mean frame time | 16.76 ms | **5.79 ms** |
| post-victory fps | 62 | **204–216** |
| mid-combat frame | 15.1–16.1 ms | 9.4–16.0 ms |
| CombatLoop total, `[PERF #4]` | 5.03 ms | 3.23 ms |
| GPU utilization | 21.4 % | 24.3 % |

At 210 fps the whole frame is ~4.8 ms with the animation pump still running, so the
**engine/render baseline outside `CombatLoop` is ~4–5 ms** — and `CombatLoop` adds
3.2–7.6 ms on top during combat. Roughly a 40 / 60 split between combat script and
everything else, all of it CPU, none of it GPU.

### ❌ CORRECTION 2 — the 60 Hz cap reproduces on native Wayland too

Round 2 measured a flat **145 fps** idle under `--display-driver wayland`. **That has not
reproduced.** Rounds 10 and 11, on verified-native Wayland, idle at a flat **62 fps** with
vsync on — and jump to 204–216 fps with `--disable-vsync`. Since disabling vsync moves it
by 3.4×, it is a present cap, not a workload limit; but it is now capping under *both*
display drivers.

Checked and ruled out: the monitor is still `2560x1440@143.998`, `vrr: false`,
`dpmsStatus: 1`; the Godot window is `mapped=True, hidden=False`. What differs between the
round-2 conditions and now is not yet identified.

**So the round-2 conclusion "XWayland was the 60 Hz cap" is not established.** What is
established: **vsync-on presents at 60 here regardless of driver; vsync-off reaches
200+.** The 2.08× X11-vs-Wayland frame count in round 2 is real data but its causal story
is now in doubt, and the two runs are not directly comparable to rounds 10/11.

This does **not** touch the CPU-vs-GPU verdict, which F13 settles independently.

### Open, in priority order

1. **Why does vsync-on present at 60 on a 144 Hz display?** Now the largest unexplained
   item. Worth trying Godot's other vsync modes (Adaptive / **Mailbox**) — Mailbox would
   let the game present at monitor rate without blocking on a 60 Hz FIFO negotiation.
2. **User decision:** rebuild the fork `dev_build=no` (F10/F11, measured 5.33×).
3. **User decision:** editor `prefer_wayland` (F12) — though correction 2 means this may
   matter less than round 8 implied.
4. Code-level fixes 3–5 from round 7's table — still not implemented, and still worth
   deferring until the engine is rebuilt optimized.
---

## Round 12 — the 62 fps was MY measurement rig, not the game. ❌ CORRECTION 3

### The sweep that broke it open

Built a standalone 640×400 scratch project (`vsynctest/`, one animated circle, no game
code) and swept vsync mode × display driver:

| driver | vsync_mode | reported mode | fps |
|---|---|---|---|
| X11 | 0 Disabled | 0 | 3 612 |
| X11 | 1 Enabled (FIFO) | 1 | **62.3** |
| X11 | 2 Adaptive | **1** (unsupported → FIFO) | **62.3** |
| X11 | 3 Mailbox | **1** (unsupported → FIFO) | **62.3** |
| Wayland | 0 Disabled | 0 | 5 308 |
| Wayland | 1 Enabled (FIFO) | 1 | **62.3** |
| Wayland | 2 Adaptive | **1** (unsupported → FIFO) | **62.3** |
| Wayland | 3 Mailbox | 3 | 5 353 |

A trivial window with **one circle** presents at 62.3 fps. Not the game, not
`CombatLoop`, not the `-O0` build. Something outside Godot caps every vsynced Godot
window at 60.

*(Side finding: Adaptive vsync is unsupported on both backends and silently falls back
to FIFO; Mailbox works only on Wayland.)*

### The cause — it was in the Hyprland config all along

`~/.config/hypr/looknfeel.conf`:
```
misc { render_unfocused_fps = 60 }
```
`~/.config/hypr/hyprland.conf`:
```
windowrule = workspace 10 silent,                    match:class ^godot-standalone$
windowrule = suppress_event activate activatefocus,  match:class ^godot-standalone$
windowrule = render_unfocused 1,                     match:class ^godot-standalone$
```

And the fork (`~/Repos/godot/docs/adr/0001`) patches **standalone** runs — a Godot binary
launched from the CLI *without* `--editor-pid` — to report window class
**`godot-standalone`** instead of the project name, precisely so agent-launched games get
routed away from the user's view.

**Every game I have launched this whole session is an agent-launched standalone run.** So
every one of them was: routed to workspace 10, never focused, never activated, and
rendered by Hyprland at `render_unfocused_fps = 60`.

Confirmed live — `hyprctl clients` during a run:
```
class=godot-standalone  ws=10  title='learning (DEBUG)'
class=godot-standalone  ws=10  title='Debug Dashboard'
```

### The decisive test

Runtime keyword change only (`hyprctl keyword`, no file edit), same scene, same seed,
**restored to 60 immediately after**:

| `misc:render_unfocused_fps` | post-victory fps | combat fps |
|---|---|---|
| 60 (the config value) | flat **62** | 50–104 |
| **144** | flat **143–147** | **50–122** |

> **F14 — the flat 62 fps in rounds 1, 4, 9A, 10 and 11 was `render_unfocused_fps = 60`
> acting on my own agent-launched windows. It was never the game, and never XWayland.**

This also explains the round-2 145 fps that would not reproduce (correction 2) — that run
must have landed focused or on the visible workspace before the routing settled. It was
the outlier, and it was the *correct* number.

### What this means — and the part that matters most

**The cap applies to agent-launched runs only.** The fork's whole point is that the
user's own F5/F6 editor runs report class `learning`, open on the current workspace, and
take focus — so they render at the full 144 Hz. Confirmed in the same `hyprctl` dump:
`class=learning ws=1 title='learning (DEBUG)'`, sitting on the user's active workspace.

> **So the user's real gameplay was never capped at 60. Their lag is not a present cap —
> it is the genuine CPU cost, measured against a 6.94 ms budget.**

That makes the whole picture coherent for the first time:

| | ms/frame |
|---|---|
| 144 Hz budget | **6.94** |
| `CombatLoop` during engagement | 6.3 – 7.7 |
| engine/render baseline outside it | ~4 – 5 |
| **total in combat** | **~11 – 13** |
| GPU | **0.16** |

`CombatLoop` **alone** eats the entire 144 Hz budget, and the frame lands at roughly
double it. Measured combat rate at a 144 cap: **50–122 fps, dipping to ~50 exactly while
units converge and act** — which is the user's reported symptom, precisely.

### ❌ CORRECTION 3, stated plainly

At the very start the user asked *"change the omarchy framecap if you can/need to"* and I
answered that the Omarchy/Hyprland config was **not** the culprit and needed no change.
**That was wrong.** There is a frame cap in their Hyprland config, it is
`render_unfocused_fps = 60`, and it was capping every measurement I took. I based the
"not the culprit" claim on the round-2 145 fps reading — the one observation that later
failed to reproduce — instead of checking the config, which the user had pointed me at.

The saving grace is that the *conclusion* about their gameplay survives: the cap hits my
rig, not their play session, so the CPU diagnosis stands and is if anything sharper (they
are missing a 6.94 ms budget, not a 16.6 ms one).

### Consequences for the earlier rounds

- **CPU bucket numbers stand.** `anim` 2.2 ms, `state` 1.5 ms, `step` 0.38 ms, GPU
  0.16 ms — all per-frame script/GPU costs, independent of present rate.
- **Every frame-RATE number from an agent-launched run is capped at 60 and understates
  the real headroom.** Round 2's "x11 vs wayland = 2.08×" is *not* a driver effect;
  both arms were capped, and the difference has another explanation.
- **The round-2 `project.godot` driver change is not justified by any measurement I
  have.** It is still in the tree (both keys) and should be reconsidered — native
  Wayland does bring working Mailbox vsync, but nothing here demonstrates it helps.

### Nothing persisted

`misc:render_unfocused_fps` was changed at runtime only and restored to 60. No Hyprland
config file was edited.

### Revised standing recommendations

| # | item | evidence | status |
|---|---|---|---|
| 1 | **Rebuild the fork `dev_build=no`** (`optimize=none` today) | 5.33× measured on a GDScript microbenchmark | user decision |
| 2 | Memoize `AnimationFrameCalculator` (4 uncached opcode scans × 6 playbacks × 16 units × 60 ticks/s) | `anim` = 2.2 ms/frame, largest single item | not implemented |
| 3 | Stop rebuilding 16 × 99 string-keyed dicts per frame | `state` = 1.5 ms/frame | not implemented |
| 4 | For **agent** perf runs, raise `render_unfocused_fps` or the rig is measuring the cap | F14 | use `hyprctl keyword` per run |
| 5 | Revisit the `project.godot` display-driver change | no longer evidence-backed | pending |
| ~~vsync/XWayland~~ | ~~2.08×~~ | **withdrawn — measurement artefact** | — |
---

## Round 13 — the honest matrix, cap lifted. Driver and vsync are IRRELEVANT.

Re-took everything with `misc:render_unfocused_fps 144` (runtime keyword, restored to 60
by an `EXIT` trap), so the rig is no longer measuring its own cap. Same scene, same seed
424242, 60 s each, three arms back to back. `load 11.3`, steady.

### Idle (post-victory) — where the caps still show

| arm | post-victory fps | mean frame over run |
|---|---|---|
| x11 + vsync | 164–165 | 7.42 ms |
| wayland + vsync | 144–145 | 8.20 ms |
| wayland + `--disable-vsync` | 204–214 | 6.00 ms |

### Combat (`[PERF #2]`, mid-engagement, ACTING 9 / WALKING 4) — where it matters

| arm | frame delta | fps | CombatLoop total | `anim` |
|---|---|---|---|---|
| x11 + vsync | 15.8 ms | 63 | 6.52 ms | 2.26 ms |
| wayland + vsync | 14.6 ms | 69 | 6.24 ms | 2.13 ms |
| wayland + no vsync | 15.7 ms | 64 | 6.46 ms | 2.28 ms |

> **F15 — during combat, the display driver and the vsync mode make no difference
> whatsoever.** 63 / 69 / 64 fps across three arms that differ in exactly those two
> variables. The frame is 14.6–15.8 ms because that is what the CPU takes, and it never
> gets near any present cap. Caps only bind once the battle is over and the frame gets
> cheap.

### ❌ Round 2's display-driver finding is now fully withdrawn

Round 2 reported x11 = 4 263 frames vs wayland = 8 887 (2.08×) and I changed
`project.godot` on that basis. With the rig's own cap removed, the same comparison during
combat is **15.8 ms vs 14.6 ms** — noise. The 2.08× was `render_unfocused_fps = 60`
interacting with the two runs differently, not a driver effect.

**Recommendation: revert the `project.godot` display-driver change.** It is two keys of
unexplained behaviour (neither works alone, both work together) bought on evidence that
has now evaporated. The only real argument left for native Wayland is that Mailbox vsync
works there and is unsupported on X11 — and nothing measured shows Mailbox helping, since
combat never reaches the cap anyway. *Not reverted — the loop says don't implement.*

### The frame budget, finally measured under real play conditions

| | ms/frame | vs 144 Hz budget |
|---|---|---|
| **144 Hz budget** | **6.94** | — |
| combat frame, actual | **14.6 – 16.1** | **2.1 – 2.3× over** |
| ├ `CombatLoop` total | 6.24 – 7.70 | ~100 % of budget **by itself** |
| │  ├ `anim` | 2.13 – 2.70 | 31 – 39 % |
| │  ├ `state` | 1.51 – 1.72 | 22 – 25 % |
| │  ├ `visual` | 1.36 – 2.43 | 20 – 35 % |
| │  ├ `edge` | 0.36 – 0.77 | 5 – 11 % |
| │  ├ `step` (real GPU submit+sync) | 0.34 – 0.38 | 5 % |
| │  └ `cols` | 0.18 – 0.21 | 3 % |
| └ everything else (render submit, `Unit._process`, UI3, effects) | **~8** | **~115 %** |
| **GPU** | **0.16** | **2 %** |

Late in the battle, with units dead, it improves to 9.3–10.1 ms (99–108 fps) — better,
still never reaching 144.

### F16 — the ~8 ms outside `CombatLoop` is now the single largest item

It is bigger than the entire combat loop. Draw calls, from the spike log:
**~261–291 during combat** against 63–91 at boot. Those cost the GPU essentially nothing
(0.16 ms total), so the expense is the **CPU-side submit path** — which is engine C++,
which is exactly what `optimize=none` penalizes hardest.

Working hypothesis: **most of the ~8 ms is Godot's renderer CPU path running unoptimized.**
~270 draw calls at ~25 µs each ≈ 7 ms; on an `-O2` build the same calls would be a
fraction of that. This is consistent with F10/F11 and cannot be separated from them
without the rebuild — which makes the rebuild the *diagnostic* as well as the fix.

### Where this leaves the recommendations

| # | item | evidence | note |
|---|---|---|---|
| 1 | **Rebuild the fork `dev_build=no`** | 5.33× measured on GDScript; also the only way to test F16 | now clearly first — it is both fix and instrument |
| 2 | Memoize `AnimationFrameCalculator` | `anim` 2.1–2.7 ms/frame, reproduced across 3 independent runs | biggest in-code item |
| 3 | Kill the per-frame 16 × 99 dict rebuild | `state` 1.5–1.7 ms/frame | |
| 4 | `visual` — `update_visual_positions` | 1.4–2.4 ms/frame | not yet investigated |
| 5 | Raise `render_unfocused_fps` for any agent perf run | F14 | rig hygiene, not a game fix |
| 6 | **Revert** the `project.godot` driver change | F15 withdrew its basis | |

### Nothing persisted

`render_unfocused_fps` restored to 60 via trap; verified. No config file edited. The only
tree changes remain the (now-unjustified) `project.godot` driver keys and the
`CombatLoop.gd` bucket-split instrumentation.
---

## Round 14 — F16 REFUTED by measurement, and the real second-biggest cost found

### ❌ F16 was wrong. The draw-call submit path is 0.4 ms, not 7 ms.

Round 13 hypothesised the ~8 ms outside `CombatLoop` was Godot's renderer CPU submit path
running at `-O0`, on the arithmetic "~270 draw calls at ~25 µs each ≈ 7 ms". **The 25 µs
was a guess and it was wrong by ~16×.** Built a scratch project (`drawbench/`) that spawns
N `MeshInstance3D`s each with a *unique* material so nothing batches — N nodes == N draw
calls, nothing animating, no per-node scripts. Only the renderer's submit path runs.

| draw calls | **fork 4.8 `-O0`** | **stock 4.7.1 release** |
|---|---|---|
| 0 | 0.333 ms | 0.183 ms |
| 64 | 0.467 ms | 0.209 ms |
| 256 | 0.737 ms | 0.305 ms |
| 512 | 1.144 ms | 0.397 ms |
| **marginal cost per draw call** | **1.58 µs** | **0.42 µs** |

At the game's measured ~270 combat draw calls that is **0.43 ms on this build** (0.11 ms
on a release build). **Draw-call submit is ~5 % of the ~8 ms, not ~90 %.** Hypothesis dead.

*(The 3.8× `-O0` penalty per draw call is consistent with the VM benchmark's 5.33×, so
F10/F11 still stand — the rebuild just isn't the answer to F16.)*

### F17 — the arena force-opens a debug overlay that costs ~2.4 ms/frame

`GPUArena._ready()` line 204 calls `DebugOverlay.show_overlay()` **unconditionally**, then
`switch_to_tab(SIMULATION)`. Per ADR-0035 the overlay is a **separate OS-level `Window`** —
a second viewport with its own full render pass — and `PerfDebugPanel` connects to
`PerfMonitor.sample_taken`, so it calls `_graph.queue_redraw()` and redraws a 240-sample
graph **every frame**.

Paired runs, same seed 424242, compared **at identical ticks** (so the battle state is the
same in both), overlay hidden by sending F3 via `hyprctl dispatch sendshortcut`:

| tick | overlay ON | overlay OFF | frame gain |
|---|---|---|---|
| 180 | 15.7 ms (64 fps) | **12.6 ms (80 fps)** | −3.1 ms, **+25 %** |
| 361 | 15.2 ms (66 fps) | **11.7 ms (85 fps)** | −3.5 ms, **+29 %** |
| 541 | 10.9 ms (91 fps) | **7.7 ms (130 fps)** | −3.2 ms, **+43 %** |
| 721 | 9.9 ms (101 fps) | **7.4 ms (136 fps)** | −2.5 ms, **+35 %** |

**Attribution at tick 361**, separating the overlay from the tick-rate artefact:

```
overlay ON : delta 15.2  −  CombatLoop 6.37  =  rest 8.83 ms
overlay OFF: delta 11.7  −  CombatLoop 5.28  =  rest 6.42 ms
                                        overlay's own cost =  2.41 ms
```
(The 1.09 ms `CombatLoop` drop is *not* a saving — faster frames accumulate fewer ticks
each, `tpf` 0.9 → 0.7. Same work per second, spread over more frames.)

> **The debug overlay costs ~2.4 ms/frame — about 35 % of the entire 144 Hz budget — and
> it is on by default every time the arena launches.**

### Verification that the toggle was real

The first attempt proved nothing: the log carries **no trace** of F3, and the
`hyprctl clients` check ran immediately after the dispatch, before Godot could unmap the
window. Re-ran with a within-run double toggle and a 4 s settle:

```
t=16 before hide:  windows=2  ['learning (DEBUG)', 'Debug Dashboard']
     >>> F3 #1
t=20 after hide:   windows=1  ['learning (DEBUG)']          ← dashboard gone
     >>> F3 #2
t=38 after show:   windows=2  ['learning (DEBUG)', 'Debug Dashboard']
```

That run's own timeline independently replicates the paired runs: `[PERF #1]` (before the
hide) = 15.4 ms, matching the overlay-ON run's 15.7; `[PERF #2..4]` (after) = 11.4 / 7.8 /
7.4, matching the overlay-OFF run's 11.7 / 7.7 / 7.4. The second toggle landed after the
battle ended, so it produced no further reports — it is not evidence either way, and is
not counted as such.

### Updated frame accounting (combat, tick 361, 144 Hz budget = 6.94 ms)

| | ms | note |
|---|---|---|
| **frame total** | **15.2** | 2.2× over budget |
| `CombatLoop` | 6.37 | `anim` 2.13 · `state` 1.51 · `visual` 1.36 · `edge` 0.65 · `step` 0.34 · `cols` 0.19 |
| **debug overlay window** | **~2.4** | ✅ F17 — *default-on, and pure debug* |
| draw-call submit (~270) | ~0.4 | ✅ measured, F16 refuted |
| **still unattributed** | **~6.0** | `Unit._process` ×16, sprite repaint cascade, UI3, engine baseline |
| GPU | 0.16 | |

### Recommendations

| # | item | measured gain | note |
|---|---|---|---|
| 1 | **Don't force the debug overlay on in `GPUArena._ready()`** — or start it hidden | **+25–43 % fps** | cheapest real win found so far; one line |
| 2 | Rebuild the fork `dev_build=no` | 5.33× GDScript, 3.8× draw submit | user decision |
| 3 | Memoize `AnimationFrameCalculator` | `anim` 2.1–2.7 ms | |
| 4 | Kill the per-frame 16 × 99 dict rebuild | `state` 1.5–1.7 ms | |
| 5 | Revert the `project.godot` driver change | — | basis withdrawn in R13 |

Still not implemented — the loop says investigate only.
---

## Round 15 — the ~6 ms "unattributed" resolved. The engine baseline is cheap.

Used `--print-fps` (a continuous fps stream independent of `CombatLoop`) plus
`hyprctl dispatch sendshortcut` to drive the game live: **F3** hides the overlay (removing
F17 as a variable), **Escape** is `battle_pause`, which prints a
`[Combat] PAUSED at tick N` marker so the fps stream can be split on it exactly.
All runs: `render_unfocused_fps 144`, overlay hidden, seed 424242.

### F18 — the static scene costs 2.29 ms. It was never the problem.

Uncapped (`--disable-vsync`), combat paused at tick 549, all 16 units still in the scene,
full map rendering, overlay hidden:

```
Project FPS: 435 (2.29 mspf)   ← steady across 9 consecutive samples
```

**2.29 ms/frame.** Against a 6.94 ms budget that is 33 %. The engine baseline —
`Unit._process` × 16, the map, the UI, the render submit, the autoloads — is **not**
where the frame goes. My round-13/14 estimate of "~8 ms of other" was wrong: most of that
8 ms is not static cost at all, it is *combat-driven*.

Post-victory (animation pump still running, but only 2 units alive so most playbacks
early-return): **2.65 ms (375 fps)** — only 0.36 ms above paused, and not a clean measure
of the live animation cost precisely because the dead units' playbacks no-op.

### The real decomposition — uncapped, overlay hidden, one run

| game state | ms/frame | fps |
|---|---|---|
| **paused** (static, 16 units on screen) | **2.29** | 435 |
| post-victory (anim pump, 2 alive) | 2.65 | 375 |
| combat, tick 720 (light — most units dead) | 5.7 | 176 |
| combat, tick 540 | 7.9 | 126 |
| combat, tick 360 (heavy) | 11.1 | 90 |
| **combat, tick 180 (heaviest — units converging)** | **14.4** | **69** |
| *(+ debug overlay, which is **on by default**)* | *+2.4* | |

### Where the combat cost actually splits (tick 360, uncapped, overlay hidden)

```
frame total                                       11.10 ms
  ├ CombatLoop (its own timed buckets)             5.14 ms
  │    anim 2.59* · state 1.22 · visual 1.29 · edge/step/cols ~0.6
  ├ combat-driven work OUTSIDE CombatLoop's timers  3.67 ms   ← newly isolated
  └ static baseline (== the paused measurement)     2.29 ms
```
\* `anim` here is the whole `GPU:` bucket 2.59; the split line gives its parts.

**F19 — there is ~3.7 ms/frame of combat-driven cost that `CombatLoop`'s own
instrumentation does not see.** It appears only when combat is live and vanishes on pause,
so it is caused by the sim, but it is billed outside every bucket in the `[PERF]` line.
The likely mechanism: the animation pump changes each unit's displayed frame, which dirties
sprite materials/UVs and forces the RenderingServer to re-upload and re-sort — work that
happens in the render step, after `CombatLoop.tick()` has returned. 16 units × 6 playbacks
churning every tick is exactly the shape that produces it. **Not yet proven** — proving it
means instrumenting the repaint path, which is implementation.

### What this means

The scene, the map, the units, the renderer and the engine are all **cheap** (2.29 ms).
Everything above that is the combat simulation and the sprite animation it drives:

> At 144 Hz the budget is 6.94 ms. Paused, the game uses 2.29 ms — a third of it.
> In heavy engagement it uses 14.4 ms, and 12.1 ms of that appeared the moment combat
> started. **The fix surface is combat + animation, not rendering and not the GPU.**

### Corrections carried

- Round 13's "~8 ms outside CombatLoop" is superseded: it is 2.29 ms static +
  ~3.7 ms combat-driven + ~2.4 ms debug overlay (F17). The three were being counted as one
  undifferentiated block.
- F16 (draw-call submit) remains refuted at 0.4 ms — consistent with F18, since a static
  scene renders the same ~270 draw calls at 2.29 ms total.

### Recommendation table (unchanged in order, sharper in evidence)

| # | item | measured | note |
|---|---|---|---|
| 1 | Don't force the debug overlay on at arena boot | **+25–43 % fps** | one line, pure debug cost |
| 2 | Rebuild the fork `dev_build=no` | 5.33× GDScript, 3.8× draw submit | user decision; would scale *everything* below |
| 3 | Memoize `AnimationFrameCalculator` | `anim` 2.1–2.7 ms | may also shrink F19's 3.7 ms if fewer frame changes are emitted |
| 4 | Kill the per-frame 16 × 99 dict rebuild | `state` 1.2–1.7 ms | |
| 5 | Investigate F19's 3.7 ms repaint churn | 3.7 ms | biggest single unexplained item now |
| 6 | Revert the `project.godot` driver change | — | basis withdrawn in R13 |

Nothing implemented. `render_unfocused_fps` restored to 60.
---

## Round 16 — a spiral-of-death in the tick loop, and F19 looks per-TICK

Tried to settle F19 (is the 3.7 ms per-tick animation churn, or per-frame render work?)
using `--time-scale`, the one existing lever on tick rate. `DebugConfig` validates it to
`1.0 ≤ scale ≤ 20.0`, so only *speeding up* is available.

### F20 — `CombatLoop.tick()`'s catch-up loop is unbounded. It can spiral.

`src/gpu/CombatLoop.gd:556`:
```gdscript
_tick_accumulator += delta
while _tick_accumulator >= TICK_INTERVAL:
    _tick_accumulator -= TICK_INTERVAL
    ...    # step_tick + readback + edges + projectiles + 16 units × advance_frame
```
**No clamp on `delta`, no cap on iterations per frame** — and the same shape appears twice
(the post-victory loop at line 529 too). Godot does not clamp `_process` delta by default
(`max_physics_steps_per_frame` governs `_physics_process` only), so this is the classic
accumulator spiral: a slow frame produces a larger `delta`, which queues more ticks, which
makes the next frame slower still.

`--time-scale=2.0` drives it straight into that state — same seed, same scene:

| | time-scale 1.0 | **time-scale 2.0** |
|---|---|---|
| tick ~360 frame time | 11.4 ms (88 fps) | **125.4 ms (8 fps)** |
| ticks per frame | 0.7 | **7.5** |
| `GPU:` bucket | 2.52 ms | **36.10 ms** |
| 0-tick frames | 89 | **0** |

At 2× the loop *wants* 120 ticks/s and the machine delivers ~60, so the accumulator never
drains and `tpf` climbs (3.6 → 7.5 → 9.5) instead of settling. It is not "2× work costs
2×" — it is runaway.

**This is not just a time-scale curiosity.** It is the mechanism behind the `max` column
in every `[PERF]` line all session: averages of 2.4–7.4 ms sitting next to maxima of
**50–163 ms**. One hitch — a shader compile, a background process, a stray long frame —
converts into a multi-tick catch-up burst on the next frame, which is exactly what a
player perceives as a stutter rather than a low average. The fix shape is standard
(clamp `delta`, or cap ticks per frame and drop the surplus), but it is a behaviour change
to the sim's timing contract and belongs to the owner, not to this loop.

### F19 scaling — consistent with per-TICK, not per-frame

The 2× arm is degenerate, so it cannot answer the question. Using the 1× arm's natural
variation across the battle instead (`F19 = frame − CombatLoop − 2.29 ms static`):

| tick | frame | CombatLoop | F19 | `tpf` | **F19 / tpf** |
|---|---|---|---|---|---|
| 181 | 15.0 | 7.37 | 5.34 | 0.9 | 5.93 |
| 361 | 11.4 | 5.17 | 3.94 | 0.7 | 5.63 |
| 541 | 7.6 | 3.20 | 2.02 | 0.5 | 4.04 |
| 721 | 6.4 | 2.42 | 1.69 | 0.4 | 4.23 |

**F19 itself varies 3.2× (5.34 → 1.69); F19 normalised per tick varies only 1.5×
(5.9 → 4.0).** If it were per-frame render work it would be roughly constant per frame;
it is not. If it were per-tick it would be roughly constant per tick; it nearly is.

> **F19 is driven by ticks, not by frames rendered — consistent with the sprite-repaint
> churn hypothesis (each tick advances 6 playbacks per unit, changing displayed frames and
> dirtying the renderer).** Still *consistent with*, not proven: unit deaths reduce both
> the tick cost and the animation churn together, so the two are confounded in this data.
> A clean test needs the repaint path instrumented.

### Reproducibility check

The 1× arm independently reproduces round 15b at every tick (tick 361: frame 11.4 vs 11.1,
CombatLoop 5.17 vs 5.14, F19 3.94 vs 3.67). Three separate runs now agree.

### Recommendations

| # | item | measured | note |
|---|---|---|---|
| 1 | Don't force the debug overlay on at arena boot | +25–43 % fps | one line |
| 2 | Rebuild the fork `dev_build=no` | 5.33× GDScript | user decision |
| 3 | **Clamp the tick catch-up loop** (F20) | removes 50–163 ms stutter spikes | fixes *felt* lag, not average fps — arguably the most user-visible item |
| 4 | Memoize `AnimationFrameCalculator` | `anim` 2.1–2.7 ms | may also shrink F19 |
| 5 | Kill the per-frame 16 × 99 dict rebuild | `state` 1.2–1.7 ms | |
| 6 | Revert the `project.godot` driver change | — | basis withdrawn in R13 |

Nothing implemented. `render_unfocused_fps` restored to 60.
---

## Round 17 — two of my own hypotheses tested and both rejected

No new runs needed; both questions were answerable from data already on disk.

### ❌ CORRECTION 5 — F20's spiral does NOT fire at 1×. The `max` column is BOOT.

Round 16 claimed the unbounded catch-up loop was "the mechanism behind the `max` column
in every `[PERF]` line". **Checked it. Wrong.** The PerfMonitor spike log for a full
13 165-frame run lists **10 spikes over 33 ms**, and their timestamps give it away:

```
  +9.78s   tick=-1   ft=782.3ms   nodes_d=+1404      ← scene load
  +11.50s  tick=0    ft=1715.0ms  nodes_d=+1159      ← scene load
  +13.72s  tick=0    ft=1803.8ms  nodes_d=+1028      ← scene load
  +11.63s  tick=0    ft=134.8ms   nodes_d=+21
  +13.89s  tick=0    ft=165.9ms   draw=157
  +13.99s  tick=9    ft=98.1ms                       ← first combat ticks, shader/effect warmup
  +14.06s  tick=15   ft=67.9ms
  +14.10s  tick=20   ft=44.7ms
  +16.65s  tick=174  ft=39.0ms    vis=6              ← the ONLY in-battle spike
```

Nine of ten are the 9–14 s boot window — mass node instantiation (`nodes_d` +1028/+1159/
+1404) and first-tick warmup, all at `tick=0`. **Exactly one >33 ms frame occurs during an
entire battle.** Replicated identically in a second run.

And the accumulator is nowhere near saturated at 1×: zero-tick frames per 3 s window run
**48 / 89 / 217 / 290**, i.e. the loop is idle-waiting most frames. It drains constantly.

> **F20 stands as a latent robustness issue (it genuinely runs away at 2×), but it is not
> causing anything today.** Demoted to #6. Round 16's framing was an assertion I had the
> data to check and did not.

### ❌ Vsync quantisation — also rejected

I was about to argue that FIFO at 144 Hz quantises a missed frame to 72 fps, making the
drop feel like a cliff. Same battle, same ticks:

| tick | vsync ON | vsync OFF |
|---|---|---|
| 180 | 16.0 ms (62) | 16.1 ms (62) |
| 361 | 14.6 ms (69) | 15.7 ms (64) |
| 541 | 10.6 ms (94) | 10.8 ms (92) |
| 721 | 9.5 ms (105) | 9.3 ms (108) |

Within noise, and 94/105 fps sit nowhere near the 144/72/48 steps. **Nothing is
quantising.** Hypothesis dropped before it entered the recommendations.

### What survives

The symptom is **a sustained low frame rate during engagement, not hitching**: ~65–90 fps
where the display offers 144, essentially spike-free, with no vsync artefact and no
driver dependence. Plain, steady CPU cost — which is the least exotic answer and the one
the bucket data supported all along.

### Document restructured

Sixteen rounds of chronological appends carrying five corrections had made the file
unreadable as a *living* document — a reader could not tell what currently holds from what
had been withdrawn. Added a **STATE OF PLAY** section at the top: the answer, the frame
budget, the ranked findings, the rejected hypotheses, the corrections, and rig hygiene.
The round log below it is kept intact as the audit trail.
---

## Round 18 — how the cost scales with live units: ~1 ms per unit, per frame

No new runs. The `[Heartbeat]` line prints live team counts (`T0=6/8 T1=4/5`) and the line
under it prints `fps=`, so every existing log already contains a units-vs-framerate
series. Paired them across two independent uncapped, overlay-hidden runs.

| live units | r16_ts1 | r15b | | live units | r16_ts1 | r15b |
|---|---|---|---|---|---|---|
| 13 | 12.74 ms | 12.50 ms | | 7 | 7.58 ms | 9.26 ms |
| 12 | 18.87 ms | 16.95 ms | | 6 | 7.30 ms | 7.25 ms |
| 10 | 13.16 ms | 13.51 ms | | 4 | 7.58 ms | 5.95 ms |
| 9 | 10.00 ms | 10.10 ms | | 3 | 6.71 ms | 6.17 ms |

The two runs agree closely at every count. Least-squares over the pooled 17 points:

```
ms/frame  ≈  0.97 × (live units)  +  2.50        R² = 0.744
```

### F21 — each live unit costs ~1 ms of frame time, and the 144 Hz budget breaks at ~5

| live units | predicted | fps |
|---|---|---|
| 4 | 6.4 ms | 157 |
| **~4.6** | **6.94 ms** | **144 — budget exhausted here** |
| 6 | 8.3 ms | 120 |
| 8 | 10.3 ms | 97 |
| 10 | 12.2 ms | 82 |
| **13 (this fixture)** | **15.1 ms** | **66** |
| 16 | 18.0 ms | 56 |
| 20 | 21.9 ms | 46 |
| 24 | 25.8 ms | 39 |

**The arena runs out of 144 Hz budget at about five live units.** This fixture has 13, and
real FFT battles routinely field more — so the observed 65–90 fps is not an edge case, it
is the normal operating point, and a larger battle gets proportionally worse.

### An independent confirmation of F18

The regression's intercept — the extrapolated cost at **zero** live units — is **2.50 ms**.
The directly measured static baseline (round 15, combat paused, uncapped, 16 units still
on screen) was **2.29 ms**. Two completely independent methods, one a fit across a battle's
heartbeats and the other a direct pause measurement, land within 0.2 ms. That is a real
cross-check on F18, not a restatement of it.

### Caveats, stated

- **R² = 0.744 — indicative, not precise.** Live-unit count falls monotonically through a
  battle, so it is confounded with battle phase and activity mix.
- **The 12-alive point is worse than 13** (18.9 / 17.0 ms) in *both* runs. That is the
  moment of peak convergence — everyone alive and acting at once — so activity mix clearly
  matters on top of raw count. Excluding it gives `0.74 × alive + 3.72` (R² = 0.822), but
  that intercept (3.72) agrees less well with the measured 2.29 ms baseline, so the
  all-points fit is the one reported.
- 17 points from 2 runs of a single seed. A different battle would shift the constants.

### Why this is the useful framing

The per-unit slope is where every ranked fix lands: `anim` (6 playbacks per unit per tick),
`state` (99 dict fields per unit per frame), `visual` (per-unit interpolation) and F19's
repaint churn are all **per-unit** costs. The 2.3–2.5 ms intercept — engine, map, renderer,
UI — is fine and is not worth touching. **Every millisecond worth chasing is in the
per-unit slope**, which is exactly what items 2–5 in the recommendation table attack.
---

## Round 19 — pooled 52 samples across 15 runs. `state` is a tax that never decays.

No new runs. Every `[PERF]` line carries the bucket split *and* the activity histogram, so
15 runs' worth of logs is already a dataset. Pooled them, excluding the contaminated
round-5 run and the degenerate `time-scale=2` samples (`tpf` 3.6–9.5).

### A methodology error of mine, caught before it reached a conclusion

My first pass normalised **every** bucket by `tpf`. That is wrong: `state_ms` and
`visual_ms` are timed *after* the `while` loop (`CombatLoop.gd:647`, `:660`) — they run
**once per frame**, not once per tick. Only `anim` / `step` / `cols` / `edge` are inside the
loop. Dividing the per-frame buckets by `tpf` produced nonsense on the degenerate samples
(state/tick "collapsing" to 0.13 ms at `tpf` 9.5), which is what exposed it.

### The decay profile — 13 samples per phase, 15 different run configurations

| battle phase | WALK / ACT | **`anim` per TICK** | **`state` per FRAME** | **`visual` per FRAME** | `tpf` |
|---|---|---|---|---|---|
| ~tick 100 (converging) | 8 / 5 | 2.67 ms | 1.64 ms | 2.35 ms | 0.93 |
| ~tick 300 | 4 / 9 | 2.43 ms | 1.44 ms | 1.35 ms | 0.82 |
| ~tick 500 | 2 / 11 | 2.06 ms | 1.12 ms | 0.88 ms | 0.58 |
| ~tick 700 (few left) | 4 / 9 | 1.85 ms | 1.06 ms | 0.57 ms | 0.58 |
| **decay across the battle** | | **−31 %** | *(see below)* | **−76 %** | |

`state`'s apparent per-frame decline is an artefact of `tpf` falling: `get_all_unit_states()`
is version-cached, so a frame that ran **zero** ticks hits the cache and pays almost
nothing. Correcting for that — cost per frame that *actually ticked*:

| phase | ~100 | ~300 | ~500 | ~700 |
|---|---|---|---|---|
| **`state`, per ticking frame** | **1.76 ms** | **1.76 ms** | **1.92 ms** | **1.89 ms** |

### F22 — `state` is O(slots), not O(live units). It is flat for the whole battle.

**Dead flat at ~1.8 ms.** Every other cost decays as units die — `anim` by 31 %, `visual`
by 76 % — because dead playbacks early-return and `update_visual_positions` skips grounded
corpses. `state` does not, because `get_all_unit_states()` rebuilds **all 16 slots × 99
string-keyed Dictionary fields** whether the unit is alive, dead, or an empty slot. It
cannot tell the difference and never asks.

So late in a battle, when `anim` has fallen to 1.85 ms/tick and `visual` to 0.57 ms/frame,
`state` is still charging its full opening price — and its share of the combat cost *grows*
monotonically as the fight resolves.

### This re-ranks the fixes

`anim` is still the single biggest number, but it **self-mitigates**: its cost is
proportional to units that are actually animating. `state` does not self-mitigate at all,
is the simplest of the three to fix (skip dead/empty slots; or read the handful of fields
the consumers want instead of building 99-key dicts), and is measurably the same 1.8 ms
in the opening clash and the last duel alike.

| # | item | measured | why here |
|---|---|---|---|
| 1 | Don't force the debug overlay on at arena boot | +25–43 % fps | one line, pure debug cost |
| 2 | Rebuild the fork `dev_build=no` | 5.33× GDScript | scales everything below it |
| 3 | **`_check_state_changes()`'s 16 × 99 dict rebuild** | **flat 1.8 ms, never decays (F22)** | **promoted** — simplest fix, only non-decaying cost |
| 4 | Memoize `AnimationFrameCalculator` | `anim` 2.67 → 1.85 ms/tick | biggest raw number, but self-mitigating |
| 5 | F19's tick-driven repaint churn | ~3.7 ms | needs instrumenting first |
| 6 | Clamp the tick catch-up loop | latent (R17) | robustness only |
| 7 | Revert the `project.godot` driver keys | — | basis withdrawn (R13) |

### Reproducibility

13 independent samples per phase, drawn from 15 runs spanning three display drivers, both
vsync states, overlay on and off, and two frame-rate caps. `anim/tick` at phase ~100 ranges
2.47–2.87 (±8 %); `state` per ticking frame holds 1.76–1.92 across the entire battle. The
per-tick costs are a property of the code, not of any run condition — which is why the
buckets have been stable all session while the frame rates moved around.
---

## Round 20 — blast-radius scoping for the top three fixes (still no implementation)

Data analysis is mined out. This round reads the code to size each recommended fix: what
it touches, whether it is safe, and — for one of them — why the obvious version would have
delivered **nothing**.

### Fix 1 — stop force-opening the debug overlay. LOW RISK.

`DebugOverlay.show_overlay()` callers outside the overlay itself:

| caller | note |
|---|---|
| `GPUArena.gd:204`, `:567` | the two under discussion |
| `TrapViewerScene.gd:104`, `FireCastReproScene.gd:81` | debug/viewer scenes — appropriate, leave alone |
| ~10 `tests/EffectStudio*`, `tests/Colour*` | **call it themselves** |

The tests are self-sufficient — they open the overlay explicitly, and their own comments say
why ("a HIDDEN Window does not lay out"). They do **not** depend on `GPUArena` opening it,
so gating the arena's call cannot break them. The three `GPUArena`-derived tests
(`GPUThrashTest`, `GPUTeleportTest`, `GPUItemFallthroughTest`) never reference
`DebugOverlay` at all.

⚠ **This is a product decision, not purely a perf one.** The arena is the user's own dev
scene and they may well want the overlay up by default. The right shape is an `@export` /
tunable with the user choosing the default — not a removal. Flagged for them.

### Fix 3 — the 99-field snapshot. ⚠ THE OBVIOUS FIX SAVES NOTHING.

`get_all_unit_states()` is called **16 times in `CombatLoop.gd` alone** (22 in `src/`, 82 in
`tests/`). Two of those are in the per-frame hot path:

```
CombatLoop.gd:657   vis_states = gpu_state_reader.get_all_unit_states()   → GPUVisualBridge
CombatLoop.gd:840   _all_states.assign(...)                               → _check_state_changes
```

**They share one cache** (`_rb_states_cache` / `_rb_states_version`,
`GPUBatchSimulator.gd:1164`): the first caller after a version bump pays the full 99-field
build, every later caller in that frame is free.

> **So converting only `_check_state_changes()` to lean columns would save ~0 ms — the
> visual bridge would simply become the one that pays.** Both hot-path consumers have to
> move together, or the 1.8 ms does not budge. This is exactly the kind of thing that makes
> a "simple" fix land as a no-op.

The good news is how few fields they actually want, out of 99:

| consumer | fields read |
|---|---|
| `GPUCombatInterpreter` (285 lines, the whole per-unit detection pass) | `anim_flags, casting_ability_id, cast_step_id, cast_target, flags, hp, mp, pos_x, pos_z, state` — **10** |
| `GPUVisualBridge` | `cast_target, dbg_conflict_blocked, flags, level, move_total_ticks, pos_x, pos_z, state, target, timer` — **10** |
| **union** | **15 distinct fields** |

`read_unit_column()` already exists and was measured at **62 µs for 5 columns** (~12 µs
each) against **1 800 µs** for the dict build. 15 columns ≈ **180 µs** — a **~10×**
reduction, saving **~1.6 ms per ticking frame**, flat across the whole battle (F22).

Access-pattern check: only four bracket-style reads exist in `src/`
(`state["pos_x"|"pos_z"|"target"|"word"]`), all covered by the union. Nothing iterates the
dict's keys. The 82 test call sites can keep using the full snapshot — it stays available,
it just stops being on the per-frame path.

> ### ❌ EVERYTHING IN "fix 3" ABOVE IS SUPERSEDED BY ROUND 21.
> The census counted **two** files; there are **five** consumers, the union is **39 of 101**
> (not 15 of 99), and `state["word"]` belongs to the effect studio, not to a unit snapshot.
> The expected win drops to **−1.43 ms** and the fix shape reopens. Read
> **W1** in the `## Work list`; do not size this item off the table above.

### Fix 4 — memoize `AnimationFrameCalculator`. SAFE, with one hazard.

The four pure functions key on `(anim_id, sequences)`, and `sequences` is
`UnitAnimationSet.type1_seq`, sourced from `AnimationDatabase`'s static `_json_cache`.
Checked: **no `type1_seq[...] = ` assignment exists anywhere in `src/` or `addons/`** — the
opcode dictionaries are never mutated after load, so memoised results cannot go stale
through mutation.

⚠ **The hazard is `AnimationDatabase.gd:82` — `_json_cache.clear()`.** A reload seam exists,
so any memo table must be invalidated on that same call, or a post-reload lookup returns
answers computed against the *previous* corpus. Cheap to handle, easy to miss.

### Summary of what the eventual implementation costs

| fix | files touched | risk | expected |
|---|---|---|---|
| 1 overlay default | 1 (`GPUArena.gd`) + a tunable | low — tests self-sufficient | +25–43 % fps |
| 3 lean snapshot | ❌ **superseded (R21)**: 5 consumers, not 3 | ❌ **superseded (R21)**: 31-field union, not 15 | ❌ **superseded (R21)**: ~1.43 ms |
| 4 memoise calculator | 2 (`AnimationFrameCalculator`, `AnimationDatabase` invalidation) | low — data proven immutable | part of `anim` 1.85–2.67 ms/tick |

None of this is implemented. The scoping is here so that when the go-ahead comes, the
shared-cache trap in fix 3 and the `_json_cache.clear()` hazard in fix 4 are already known
rather than discovered halfway through.

---

## Round 21 — W1's field census re-derived: 31 of 101, across five consumers. ❌ CORRECTION 6

No measurement this round; the box was at load 23.6 with another session's parallel suite
running against `fft-monorepo-main`, so nothing was timed (rig hygiene: queue behind it,
do not measure through it). This is static analysis only, and every claim below is
reproducible from the tree.

### What round 20 did, and why it under-counted

R20 sized W1 by grepping field reads in **`GPUCombatInterpreter.gd` and `GPUVisualBridge.gd`**
and taking their union. Those are the two files the snapshot is *handed to by name*. But
`_check_state_changes()` also hands each `state` dictionary to its own apply pump, and
`_all_states` to two more subsystems — none of which R20 opened.

Re-derived by walking the call graph out of `_check_state_changes()` and `_handle_revives()`
(29 reachable functions in `CombatLoop.gd`), then unioning with the four files that receive
the dictionary:

| consumer | how it receives the dict | fields |
|---|---|---|
| `GPUCombatInterpreter.interpret()` | `_check_state_changes` passes `_all_states[i]` | 10 |
| `GPUVisualBridge` | `CombatLoop.gd:657`, and `update_facing_toward_target(_, _, _all_states)` | 10 |
| **`CombatLoop`'s `_apply_*` pump** | `_apply_combat_event(i, state, ev)` → 8 handlers | **21** |
| **`ProjectileManager`** | `spawn_from_gpu(i, state, _all_states)`, `update(tick, _all_states)` | **7** |
| **`CinematicDebugProbe`** | `probe(...)`, `on_cinematic_began/ended` | **8** |
| **union** | | **31 of 101** |

The three bold rows are new. Spot checks: `_apply_state_changed` reads
`pos_x, pos_z, timer, casting_ability_id, cast_timer`; `_apply_hp_change` reads
`anim_frame, projectile_frame, damage_target, pending_heal_target`;
`_process_thrash_detection` reads `decision_meta`. None of the five is in R20's union.

### F23 — the access-pattern check counted a spelling, not a field

R20: *"only four bracket-style reads exist in `src/` — `state["pos_x" | "pos_z" | "target" |
"word"]` — all inside the union."*

`state["word"]` is `src/effects/studio/EffectKeyframeInspector.gd:1582` — the **effect
studio's keyframe dictionary**, unrelated to a GPU unit snapshot. `word` is not a
`SNAPSHOT_FIELDS` key at all (the 101 keys are listed in `GPUCombatPacker.gd`). Worse, that
site **mutates** its dictionary (`state["word"] = …`), so R20's "nothing mutates the
dictionary" conclusion was drawing a safety guarantee partly from a file that violates it.

The genuine bracket reads on a unit snapshot are `pos_x`/`pos_z` in `GPUVisualBridge`
(4 sites) plus two cold, debug-gated prints (`CombatLoop.gd:710` and `:1994`, the latter in
`_log_initial_state`, which runs once at battle start). **The other half of R20's check
survives: nothing iterates the dictionary's keys**, so a lean build cannot break a key walk.

### F24 — it is 101 fields, not 99

`GPUCombatPacker.gd`: `UNIT_SIZE = 101`, and `SNAPSHOT_FIELDS` has 101 keys. Every
"16 × 99 = 1 584 dictionary entries" in rounds 1–20 is really **16 × 101 = 1 616**. The
conclusions are unaffected; the arithmetic is corrected here rather than edited throughout
the log.

### What it does to W1

| | R20 | R21 |
|---|---|---|
| union | 15 of 99 | **31 of 101** |
| consumers | 2 | **5** |
| cost after (@ ~12 µs/column) | 180 µs | **372 µs** |
| expected win | −1.6 ms | **−1.43 ms** |
| files touched by the specified shape | 3 | **5** |

**W1 remains the top item.** It is still the only cost that does not decay as units die
(F22), and −1.43 ms of a ~15 ms frame is still the largest single win on the list. What
changed is that its *shape* was pre-decided on a number that was wrong by 2×, so the shape
goes back to the user — see `## Open`.

### Not done this round

No characterization test, no refactor, no measurement. The loop's rule is that a shape
decision belongs to the user, not to the session that discovers it; narrowing the specified
columns fix to a lean-dictionary fix would have delivered 87 % of the item while reporting
it as done.

---

## Round 22 — W1 BUILT (shape B). The union was 15 → 31 → 34 → **39**, and the last two corrections were found by instruments, not by reading.

**Shape B was ruled by the user** after R21 reopened it: keep every consumer signature,
build the per-frame snapshot from a declared union instead of all 101 fields. One file
instead of five, ~87 % of the columns win, and a *silent* failure mode to close.

Closing it is the whole story of this round. **The union was wrong three more times, and
every correction after the first came from an instrument rather than from a person reading
code.**

| pass | union | derived by | what it missed, and why |
|---|---|---|---|
| R20 | 15 of 99 | grep of the 2 files the snapshot is handed to *by name* | 3 consumers that receive the dict as a **parameter** |
| R21 | 31 of 101 | hand call-graph walk | 3 fields — the walk's regex was `[a-z_]+` and **`decision_hist_0/1/2` end in digits** |
| `check_snapshot_union.py` | 34 | mechanical call-graph walk | 5 fields read through a **computed key** |
| `GPUSnapshotUnionTest` | **39** | a poisoned battle, through the real consumers | — |

### F25 — the last five fields were a live corruption, and only the runtime arm could see it

`GPUCombatInterpreter` reads its five break-affected stats through a **computed** key:

```gdscript
const STAT_FIELDS := [["pa","PA"], ["ma","MA"], ["speed","Speed"], ["wp","WP"], ["s_ev","S_EV"]]
...
var cur_val := int(state.get(key, 0))      # `key` is a variable — no grep can see this
```

No census that looks for a quoted field name can find those, and neither R20's, R21's, nor
the first version of the static guard did. Leaving them out of the union did **not** read a
wrong number — it read the **default**: every unit's PA, MA, Speed and WP "broke" to 0 on
tick 1, and `_sync_stat_to_unit` wrote that into `unit_stats`. The arena log filled with

```
[Tick 1] [STAT_BREAK] Squire8: PA 3 -> 0 (-3)   MA 4 -> 0   Speed 6 -> 0   WP 3 -> 0
```

**This is exactly the silent failure the shape decision was about, it happened, and the
static guard did not catch it.** Only the poisoned battle did.

### The three instruments, and what each one actually proves

**1. `tools/check_snapshot_union.py`** (pre-flight). Walks `CombatLoop.gd`'s intra-file call
graph out of `_check_state_changes()` and `_handle_revives()` — 29 functions — and unions the
field reads with those of the four files that receive the dictionary. Proves the union covers
the **code**.

> It now **refuses** a computed-key read rather than skipping it. A `.get()` whose key is an
> expression must be registered in `COMPUTED_KEY_SITES` with the keys it can produce, or the
> guard fails and names the site. An invisible read becomes a visible, reviewed one — which
> is the only reason F25 cannot recur.

Falsified three ways before being believed: un-register the computed site → red naming both
call sites; delete one union key → red naming the field and its reader; restore → green.

**2. `tests/GPULeanColumnReadTest.gd`, arm 2** (extended, not added). The lean snapshot is
built by walking parallel `HOT_UNION_KEYS`/`HOT_UNION_OFFSETS` arrays — a **second,
independent** offset-resolution path over the same bytes, so it can drift on its own. Asserts
the lean snapshot carries exactly the union's keys with byte-identical values: **62,400
comparisons over 200 ticks**, green.

**3. `tests/GPUSnapshotUnionTest.tscn`** (new). A real seeded battle with every **non-union**
field of the per-frame snapshot set to `-999,777,333`. Union reads are untouched, so a battle
that reads nothing else is unaffected; a battle that reads anything else gets nine digits of
nonsense where a plausible number used to be. Proves the union covers the **run**.
1800 ticks, 13 units, green — no poisoned value reached a unit's stats or a visual position.

### What is NOT proven — stated plainly rather than left implied

- **The poisoned battle reached no death and no revive** (`dead: [13 × false]`). `_apply_death`
  and `_handle_revives` are covered by the static guard only. A seed that resolves would be a
  strictly better fixture; this one damages (HP 40 → 15–31) but does not finish inside 1800
  ticks.
- **A read reached through a `Callable` is invisible to both**, as is a brand-new consumer
  file absent from the guard's `RECEIVER_FILES`.
- `CinematicManager` reads field-heavy state off `_all_states` and is deliberately **not** a
  receiver file: all three of its read sites call `refresh_all_states_now()` first, which
  re-fills `_all_states` with the full 101-field form. It is a cold caller wearing a hot
  caller's clothes. If that refresh is ever dropped, it becomes union business.

### The measurement

A/B/A/B interleaved, seed 424242, 60 s arms, 32 `[PERF]` reports each, overlay closed,
`render_unfocused_fps` raised to 144 and restored after. The two arms differ by a
**line-exact flip** of which builder `CombatLoop`'s two per-frame callers use — not a branch
diff — so no other change can leak in. `refresh_all_states_now()` stays on the full form in
both arms; a bare `sed` would have dragged it along, since it contains a byte-identical
`_all_states.assign(gpu_state_reader.get_all_unit_states())`.

| bucket | A: full 101 | B: lean 39 | rep 1 | rep 2 | pooled Δ |
|---|---|---|---|---|---|
| `state` | 1.730 | **0.768** | −0.90 | −1.02 | **−0.96** |
| `visual` | 0.859 | **0.486** | −0.36 | −0.39 | **−0.37** |
| **CombatLoop total** | **4.332** | **2.830** | −1.30 | −1.70 | **−1.50** |
| real frame time | 13.81 | 13.26 | **+0.11** | **−1.21** | −0.55 ⚠ |

**−1.50 ms of work per frame, reproduced.** Better than the −1.1 ms predicted once the union
reached 39 fields, because `visual` improved too: the lean dictionary is cheaper for its
consumer to *read*, not merely cheaper to build. Note both callers share the lean cache, so
whichever runs first pays and the other is free — the shared-cache trap round 20 warned about
is dodged, and the proof is that `visual` did not simply inherit the cost.

⚠ **The frame-time row is not a result, and is recorded as one that failed to resolve.** Its
two reps disagree by more than the effect (+0.11 vs −1.21 ms). Chromium held ~6 of 24 cores
for the whole run, load climbed 12.6 → 16.4, and two other sessions launched suites
mid-measure. The bucket rows survive that — they are self-timed spans *inside* the frame and
agree across reps to within 0.12 ms — but `delta` does not. **Do not cite −0.55 ms as an fps
win.** Re-take it on a quiet box, ideally after **W3**, since the ~9 ms outside `CombatLoop`
is inflated by `optimize=none` as well.

### A rig trap that cost ~50 minutes, and will cost the next session too

The measurement queued correctly behind another session's suite — and then stayed queued for
~50 minutes **after that suite had finished**, because 23 processes still matched
`pgrep -f run_tests_parallel`. None was a suite. They were abandoned waiter shells from other
sessions running

```
until ! pgrep -f "run_tests_parallel.py"; do sleep 15; done
```

whose **own command line contains the literal string**, so each one matches its own pattern
and can never exit. The `[l]`-bracket trick protects a waiter from matching *itself*; it does
nothing about *other* shells' plain-text copies. A predicate that works:

```bash
while pgrep -af "run_tests_paralle[l]\.py" 2>/dev/null | grep -qv "bash -c"; do sleep 30; done
```

`[l]` for self-exclusion, `\.py` so `python -m unittest test_run_tests_parallel` (a unit test
*of* the runner) is not mistaken for a suite, and `grep -v "bash -c"` for the ghosts.

### F26 — the union bit a FOURTH time, and this one only the full suite could see

All three instruments were green, the branch looked done, and the full suite failed
**62 of 82 gambit fixtures** with a uniform signature:

```
[FAIL] gambit_fired_at_slot(unit='Monk', slot=0) — first commit at tick 374 slot -1 (expected 0)
```

`tests/gambit_runner/GambitScenarioRunner.gd:351` reads
`_all_states[unit_idx].get("current_gambit", -1)`. `current_gambit` is not in the union, so
it returned the **default** — `-1` — and every slot assertion in the corpus compared `-1`
against its expected slot.

**Why no instrument saw it.** `_all_states` is a field on `CombatHost`, so **any test
subclassing it indexes the per-frame snapshot directly**. Three do
(`GambitScenarioRunner`, `GPUThrashTest`, `GPUTeleportTest`), and `GambitTraceLogger` is
handed the array. The static guard's receiver list held *production* consumers only; the
poisoned battle runs one seed through `GPUArena`, not the gambit corpus; the fidelity arm
compares values, not consumers. The lean snapshot had escaped into a whole population of
readers nobody had enumerated.

**Fixed by moving the readers, not by widening the union.** A diagnostic observer asks for
the full snapshot — `gpu_state_reader.get_all_unit_states()`, served off the same
per-version cache — exactly as production does through `refresh_all_states_now()` for the
cinematic edge. Widening the union to 43 fields would have taxed every production frame
forever to serve a test's trace log.

**The guard gained a second sweep**: every `.gd` under `src/` and `tests/` that indexes
`_all_states`, with its fields required to be in the union. Falsified against the real bug —
reintroduce the exact line and it fails naming both the field and the file.

### Separating the suite's reds — 14 reported, 3 were mine

The full run was 715/729 with 10 FAILED, 3 HUNG, 1 NO_VERDICT, taken while another session's
suite shared the box at load ~19. Two cheap arms split them:

| arm | finding |
|---|---|
| re-run the 14 at **N=2** on a clear box | 7 pass, **including all 3 HUNG** → contention |
| re-run the survivors with **W1 stashed** on the same branch | 3 flip to PASS → **mine**; 3 stay red → **pre-existing** |

- **Mine (3):** `GambitScenarioRunnerTest` (F26 above) plus `CombatCameraMountTest` and
  `ProceduralMapMountTest` — both *count ratchets* that my new `GPUSnapshotUnionTest.tscn`
  legitimately moved (108 → 109 and 109 → 110). Bumped with reasons, as each file's own
  docstring instructs.
- **Not mine (3):** `EffectScreenInsertDeleteAcceptanceTest`,
  `EffectStudioColourKeyframeAcceptanceTest` (FAIL) and `EffectScriptSaverAcceptanceTest`
  (NO_VERDICT) are red on the baseline too.

⚠ **`git stash -u` is what made the isolation arm honest, and it is also a trap**: it
removes *untracked* files, so the new test scene vanished with the code — which is precisely
why the two ratchets read one lower and "passed". Read a ratchet flip as a scene-count
change before reading it as a behaviour change.

### The lesson, stated for the next session

Round 20 grepped, and was wrong. Round 21 walked the call graph by hand, and was **still**
wrong — twice, in two different ways (digits in a field name; a key that is not a literal).
The number only stopped moving once a machine was deriving it and a battle was checking it.
**Do not re-derive this union by reading. Run `check_snapshot_union.py`.** And note the
count did not settle until the FULL suite ran: 15 → 31 → 34 → 39, with the fourth miss
(F26) invisible to all three instruments because it lived in a test that indexes
`_all_states` directly. A lean snapshot escapes to everyone who can reach the field it is
stored in — enumerate *that* population, not just the call graph.

---

## Round 23 — the optimized engine exists, and the 5.33× is now unmeasurable against it

`scons -j20 platform=linuxbsd target=editor dev_build=no`, 5 min 35 s, zero errors.
`bin/godot.linuxbsd.editor.x86_64` (164 MB) landed **beside** the untouched `.dev` build
(1032 MB) — the filename encodes the flag, so there was never a moment where the working
engine did not exist.

Confirmed optimized by payload rather than by version string, because `godot --version`
reports `4.8.dev.custom_build` for **both** (that `dev` is the version *status* from
`version.py`, unrelated to `dev_build`):

| probe | `.dev` build | new build |
|---|---|---|
| `DEV_ENABLED` in `strings` | present | **absent** |
| size | 1032 MB | **164 MB** (`-g3` gone) |
| `.scons_env.json` | `dev_build=True`, `optimize='none'` | — |

### ❌ The 5.33× cannot be measured against this pair, and that is a new finding

The two binaries are **not the same engine source**. The `.dev` one was built
**2026-08-10 at `3e530a3e9`**; the new one is at **`f2a208da6`**, ~4 weeks of fork commits
later. Any A/B across them measures engine churn *plus* the optimizer, and there is no way
to separate the two after the fact.

This matters beyond tidiness: W1's own frame-time row (R22) failed to resolve, and the plan
recorded there was to re-take it on the optimized engine. That plan is still good, but the
*comparison* has to be optimized-vs-optimized on one code state, not new-vs-August. A clean
optimizer number needs `dev_build=yes` rebuilt at `f2a208da6` — six more minutes.

### Adopted the same day — and that resets the baseline

`/usr/local/bin/godot` was repointed at **06:56 on 2026-09-06** (root-owned symlink, done by
hand). `godot` on `$PATH` is now `godot.linuxbsd.editor.x86_64`; `strings` on it reports
`DEV_ENABLED` **0 times**.

**So the engine changed underneath this document.** Everything measured in rounds 1–22 —
including W1's `state` 1.730 → 0.768 ms — was taken on the `-O0` build. Those numbers are
still *internally* valid (both arms of every A/B ran on the same binary, so the ratios and
the deltas hold), but their **absolutes are not comparable** to anything measured from round
24 onward, and the *ranking* of the Work list may reorder, because the buckets are not
uniformly GDScript. Re-read the ordering before trusting it: caveat 1 at the top of the Work
list said the rebuild could reorder rather than merely scale, and that is now live.

The `super+space` launcher entries are a **separate** path and were unaffected either way —
they hardcode absolute `Exec=` lines and never consult the symlink. A second entry now
exists (`Godot (patched, optimized)`) alongside the original, which is kept because
`DEV_ENABLED` is worth having while debugging the fork's C++. The fork's `godot-standalone`
window-class routing is a source patch rather than a build flag, so Hyprland's `^Godot$` and
`^godot-standalone$` rules apply to the optimized binary unchanged.


---

## Round 24 — re-taken on the shipped engine. The ordering does NOT survive, and the documented run command measures an idle scene.

The engine on `$PATH` changed at 06:56 on 2026-09-06 (R23) and caveat 1 said the rebuild
could **reorder** the Work list rather than merely scale it. This round is the re-measure
that caveat asked for. It reorders.

### Method

Two arms differing **only in the binary**, on one code state (`origin/main` at `862f0a670`,
i.e. post-W1), interleaved **OPT/DEV/OPT/DEV**, 60 s each:

| arm | binary | |
|---|---|---|
| **OPT** | `bin/godot.linuxbsd.editor.x86_64` | 164 MB, `DEV_ENABLED` absent — what `godot` on `$PATH` is now |
| **DEV** | `bin/godot.linuxbsd.editor.dev.x86_64` | 1032 MB, `dev_build=yes optimize=none` — what rounds 1–22 were taken on |

Seed 424242, overlay closed (`user_settings.json` `was_visible` forced false, backed up and
restored), `misc:render_unfocused_fps` raised to 144 and restored by an `EXIT` trap. Load
10.4 → 14.2 across the run, with another session's Godot editor live throughout.

⚠ **This is not a clean optimizer number and cannot be**, for the reason R23 gives: the two
binaries are ~4 weeks of fork commits apart (`3e530a3e9` vs `f2a208da6`). The arms measure
*optimizer + engine churn*. That is fine for the question this round asks — "what does the
engine we now ship actually cost?" — and it is **not** an answer to W3's 5.33×.

### The buckets, pooled over 8 reports per arm (2 reps × 4 reports)

| bucket | **OPT (shipped)** | DEV (`-O0`) | DEV/OPT |
|---|---|---|---|
| **`CombatLoop` total** | **0.738 ms** | 2.321 ms | **3.15×** |
| ├ `GPU` (the whole tick loop) | 0.470 | 1.458 | 3.10× |
| │  ├ `anim` — **W2's target** | **0.214** | 0.939 | **4.39×** |
| │  ├ `step` — real GPU submit+sync | **0.150** | 0.169 | **1.13×** |
| │  ├ `edge` | 0.060 | 0.270 | 4.50× |
| │  └ `cols` | 0.046 | 0.081 | 1.76× |
| ├ `state` — W1's bucket, post-fix | 0.140 | 0.482 | 3.45× |
| └ `visual` | 0.113 | 0.349 | 3.10× |
| real frame time (`delta`) | **6.075 ms** | 7.375 ms | 1.21× |

Both reps agree closely — `CombatLoop total` per report index, rep1/rep2: OPT
0.81/0.83, 0.80/0.82, 0.76/0.67, 0.61/0.60; DEV 2.50/2.62, 3.11/3.01, 2.00/2.05, 1.67/1.61.

> **The one bucket that is not GDScript is the one bucket that did not move.** `step` — the
> compute submit and sync, i.e. actual GPU work — scales **1.13×** while every GDScript-heavy
> bucket scales **3.1–4.5×**. That is an internal validity check on the whole measurement: if
> the arms differed by anything other than CPU-side script cost, `step` would have moved too.

### ❌ WITHDRAWN (R25) — "the 6.0 ms frame is real, not a present cap"

> **This subsection is wrong and Round 25 replaces it.** The `--disable-vsync` arm ruled out
> *vsync* and nothing else; `render_unfocused_fps` was set to **144**, which is a cap at
> 6.94 ms. Unthrottled (`=500`) the same fixture reads **2.08 ms / 482 fps**. The reasoning
> below is kept as the audit trail of how the wrong answer was reached — note it even names
> the two tells (165 fps exceeds the 144 Hz display; the idle scene reads the same 6.0 ms)
> and argues past both.

`delta` sits at 6.0–6.3 ms (≈165 fps) on OPT, which is *faster* than the 144 Hz refresh, so
the obvious worry is that some cap — vsync, `render_unfocused_fps`, the compositor — is what
is being measured. It is not: a third OPT arm with **`--disable-vsync`** reports 6.1 ms
(158–165 fps), indistinguishable from vsync-on. Consistent with **F15** (R13): during combat
the display path is irrelevant.

**So the heaviest point of this fixture now costs ~6.1 ms against a 6.94 ms budget — inside
144 Hz, at ~165 fps.** On the `-O0` engine the same fixture is 7.4 ms.

⚠ What this does **not** establish: the doc's headline "14.4 ms / 69 fps at the heaviest" is
**not** simply 6.1 ms scaled by the optimizer. The DEV arm — same `-O0` engine as R13 — reads
**7.4 ms**, not 14.4. Most of that gap is **code that landed since R13** (W1, and PR #883
dropping the legacy `CombatUI` 23 commits before `2c9ac86ab`), not the engine. The doc's
headline numbers were already stale before the binary changed.

### ⚠ Does the Work list ordering survive? No.

| item | ranked on (`-O0`) | on the shipped engine | effect |
|---|---|---|---|
| **W2** `anim` memoization | `anim` **2.67 ms/tick**, "biggest in-code item" | the **entire** `anim` bucket is **0.214 ms** | its predicted win (2.67 → 1.85) rescales to **≈ −0.19 ms/frame**, ~3 % of the frame |
| **W5** work outside every bucket | 3.7 ms/frame | frame 6.075 − `CombatLoop` 0.738 = **5.34 ms is outside `CombatLoop`** | the only remaining item whose target is large enough to matter — and it is still `DIAGNOSE` |
| **W3** engine rebuild | 5.33× on GDScript, unmeasured | **measured: 3.1–4.5× on script buckets, 1.13× on GPU submit** | shipped and now quantified |

**W2 was the top actionable row and is now worth about a fifth of a millisecond.** W5 was
fifth and is now, by size, first. That is precisely the reorder caveat 1 warned about.

The Work list's own ranking rule cuts the other way, though, and is why this round does not
re-sort the table on its own authority: **W2 deletes work** (an uncached per-tick rescan) and
so generalises to every machine and every build, while the 5.34 ms outside `CombatLoop` is
not yet attributed to anything. Whether a −0.19 ms work-deleting fix outranks a `DIAGNOSE`
with a 5.34 ms envelope is a judgement about the effort's direction, not a measurement. **It
is in `## Open` for the user.**

### ⚠ F27 — the run command in this document measures a scene in which combat never happens

The `## Auto-deploy run command` section says `config/tune_overrides.json` "already carries
`simulation.skip_march: true`". **On `main` it carries `false`** — the file is `AUTOSAVE`-bound
through `Tune`, so an editor session flips it and commits the flip (`047610494` is one such
"absorb Tune autosave churn" commit).

With it false, `GPUArena` takes `use_strategy_phase = true`. Running the documented command
verbatim on the optimized engine for 60 s produces **32 `[PERF]` report lines in which no unit
ever deploys**:

```
[PERF #3] tick=540 frames=498 | GPU: avg=0.25ms | state: 0.13ms | visual: 0.11ms |
          total: avg=0.50ms | delta: 6.0ms (166 fps) | Units: IDLE=15, WALKING=1
```

`IDLE=15, WALKING=1` for the entire run. The strategy phase prints its **manual** deployment
prompt (`Deployment march: cursor onto a unit + Enter…`) and the auto-place branch at
`GPUArena.gd:581` never runs — `[Strategy] Automated mode - auto-placing units` is absent from
the log. `--combat-autostart` sets `combat_active` but there is nothing on the field to fight.

**This does not announce itself.** Every number in that report is plausible, the run exits 0,
and the only tell is the `Units:` histogram. A session that repeats the documented command
today measures an empty scene and gets bucket figures that look like a spectacular win.

**Use `--skip-strategy`.** It is a real CLI flag (`DebugConfig.gd:466`), it forces
`use_strategy_phase = false` regardless of the churning JSON, and it restores the
`_place_units_at_defaults()` → `_start_battle_from_roster()` path that rounds 1–22 describe.
Every OPT/DEV number above was taken with it.

**Identity check that the fixture is the right one:** with `--skip-strategy`, report #2 reads
`ACTING=9, WALKING=4, IDLE=3` — byte-identical to the unit histogram R13 quotes for its own
`[PERF #2]`. Same seed, same placement, same engagement.

### ⚠ One unresolved discrepancy, recorded rather than smoothed over

R22 reports "32 `[PERF]` reports each" for its 60 s arms. This fixture reaches **VICTORY at
tick ~800** and emits **4** reports (8 lines) before combat stops; the report timer is
wall-clock (3 s, `CombatLoop.gd:681`) and only advances while the loop pumps. 32 lines is the
signature of the **idle** fixture above — but R22's `state` of 1.730 ms is an order of
magnitude above what an idle scene costs (0.13 ms OPT / 0.48 ms DEV), so R22 was plainly
measuring an engaged battle. Its battle therefore ran ~4× longer in ticks than this one, and
nothing in the record says why.

**What this does and does not cost.** It does **not** touch this round's conclusions: both
arms ran one fixture, interleaved, and the ratios and the OPT absolutes stand on their own.
It does mean **R22's absolutes should not be compared against R24's**, and W1's `−1.50 ms`
was measured on a battle this rig does not currently reproduce.

### Nothing persisted

`render_unfocused_fps` restored to 60 (verified). `user_settings.json` backed up before the
first arm and restored after the last (verified `was_visible: true` again). No config file
edited; `--skip-strategy` and `--disable-vsync` are CLI flags.

---

## Round 25 — ❌ R24's frame row was the THROTTLE. The game runs at 482 fps, and W2 is REFUTED.

Two findings, one of which invalidates a row this document published one commit ago.

### ❌ F28 — `render_unfocused_fps 144` masks every frame faster than 6.94 ms

R24 reported the heaviest combat frame at **6.0–6.3 ms (165 fps)** and called it real, on the
strength of a `--disable-vsync` arm that read the same. That arm ruled out *vsync* and nothing
else. The rig's own hygiene rule — *"raise `misc:render_unfocused_fps` or you are measuring
the cap"* — sets it to **144**, which is itself a cap at **6.94 ms**.

Four arms, `144 / 500 / 144 / 500`, seed 424242, 25 s each, load 4–6:

| | `render_unfocused_fps=144` | `=500` |
|---|---|---|
| frame `delta` | 6.05 ms — **165 fps** | **2.08 ms — 482 fps** |
| frames in the run | 4 063 / 4 077 | **11 938 / 11 922** |
| `CombatLoop` total | 0.540 ms | **0.253 ms** |
| ├ `GPU` | 0.338 | 0.120 |
| │  ├ `anim` | 0.147 | **0.052** |
| │  └ `step` | 0.107 | 0.040 |
| ├ `state` | 0.105 | 0.055 |
| └ `visual` | 0.083 | 0.070 |
| **outside `CombatLoop`** | 5.51 ms | **1.82 ms** |

Both settings reproduced to within 0.02 ms across their two reps. **The 6.0 ms was the
throttle.** The tell was there in R24 and was reasoned away rather than tested: 165 fps is
*faster* than the 144 Hz display and the 144 fps throttle, and the idle strategy-phase scene
read the same 6.0 ms as heaviest combat — two scenes of very different cost landing on one
number.

> **The rule was calibrated for the slow engine and silently caps the fast one.** At `-O0` a
> combat frame cost 14–15 ms, far above the 6.94 ms cap, so the cap never bound and the rule
> was harmless. On the optimized engine **everything the game does is under the cap**, so the
> cap is all you measure. Raise the setting **far above the expected frame rate** — 500, not
> the display's 144 — and state the value used.

⚠ **Per-frame bucket figures move with the frame rate too**, because they are per-frame
averages of work that is per-*tick*: at 482 fps there are ~3× the frames doing the same
simulation, so each frame's share is ~3× smaller. Bucket *ratios between two arms measured at
the same setting* are unaffected — which is why **R24's OPT/DEV ratios (3.1–4.5× on script,
1.13× on `step`) all stand**. Its absolutes, and its `delta` row, do not.

### What the game actually costs

**2.08 ms at the heaviest point of the fixture, against a 6.94 ms budget — 30 % of it, at
482 fps.** The document's founding claim, *"the 144 Hz budget is exhausted at about five live
units"*, is an artifact of the unoptimized engine. It is not true of the engine that ships.

### ❌ W2 REFUTED — predicted −0.82 ms, measured −0.014 ms

Built as specified: a memo on the five `AnimationFrameCalculator` queries, one file, every
signature unchanged. Proven equivalent by `AnimationFrameCalculatorMemoTest` — **677 animation
ids, 26 473 comparisons**, zero disagreements. Then measured, interleaved MEMO/BASE/MEMO/BASE,
4 arms of 30 s, quiet box (load ~3):

| bucket | BASE | MEMO | Δ |
|---|---|---|---|
| `anim` — the target | 0.161 ms | 0.148 ms | **−0.014** |
| `CombatLoop` total | 0.530 | 0.522 | −0.008 |
| frame `delta` | 6.075 | 6.100 | +0.025 |

**−0.014 ms against a −0.82 ms prediction**, and not consistent across reports (report 1 is
+0.01, report 4 is −0.03). At the unthrottled frame rate the same saving is ~0.005 ms/frame.

**Why the item was mis-sized, stated plainly.** It was ranked on a scan *count* —
"~23 000 scans/s" — and nobody priced a scan. A scan is a linear walk of a **median of 10
opcodes** (mean 11.2, p90 20, over `type1_seq`'s 227 animations). Removing 3–5 walks of ten
dictionary reads per playback per tick is not worth a millisecond, and is worth even less once
the optimizer is on. The *count* was right; the conclusion drawn from it never followed.

The mechanism claim in W2's own entry does hold: `AnimationPlayback.advance_frame()` really
does call `get_duration`, `is_looping`, `get_frame_at` and conditionally `is_hold_forever` +
`has_pause` every tick (`AnimationPlayback.gd:141–165`). It is the cost of each, not the
number of them, that was never measured.

### Two defects the build surfaced, both invisible to the perf question

1. **`type1_seq` and `wep1_seq` carry a `_timings` key whose value is a Dictionary**, not an
   opcode list. The scanning implementation iterates it — a Dictionary iterates its **keys** —
   and throws `Nonexistent function 'get' in base 'String'` once per key. Nothing asks for
   `_timings` by name so it never fired in production, but any pass that walks *every* key
   hits it immediately.
2. **`const _EMPTY := { "frames": PackedInt32Array(), … }` is a compile error** —
   `PackedInt32Array()` is not a constant expression — and it took the **whole addon** down
   with it: every consumer then resolved to a `GDScript` with no statics. The test reported it
   as `6 animation ids swept, floor is 40`. **Its non-vacuity floor is the only reason that
   read as a failure rather than a green sweep over an empty corpus.**

### Rig notes

`render_unfocused_fps` restored to 60 and `user_settings.json` restored from backup after
every arm (verified). The MEMO/BASE arms differ by a `git stash push` of one file on one
branch — no branch diff, and the trap restores it on any exit path.

---

## Round 26 — W7: the stress fixture. The budget breaks at 64 units, and the cliff has a name.

Three results and two corrections. **The deliverable was a measurement, and nothing found here
was optimised in this pass** — both findings are filed as `TODO`s with fix shapes (W9, W6).

### The fixture — `GPUArena --stress-units=N`

`N` is **per team**, so the cast is `2N`; absent or `0` is the shipped 13-unit cast unchanged.
`_pad_teams_for_stress` clones the roster the scenario already gave the arena. Three things it
has to get right, each of which silently produces a *wrong number* rather than an error:

- **The clone is deep.** `UnitSpawn.bind_for_combat` binds `character.progression` **by
  reference**, so two units built from one `Character` share an HP pool — they take each
  other's damage and die together, and the fixture would report a cast decaying at twice the
  real rate. `Character.from_dict(to_dict())` mints a fresh `UnitProgression`.
  `GPUArenaStressCastTest` pins this: 11 checks, including that writing the clone's HP does not
  move the source's. It asserts **counted state, never wall clock** — W8's ruling.
- **Every clone gets its own free ground cell**, from `Battle`'s own placement policy
  (`PlacementTileGenerator.placement_cells()`, published as a forwarder so the water rule stays
  in the one place ADR-0192 dec. 6 put it), nearest-first to its team's centre so the two sides
  still converge and fight rather than measuring pathfinding.
- **The two sides draw alternately** from one tile pool. Draining team0's request first is not
  a style point: at `--stress-units=64` it gave team0 all 64 and team1 only 47, which sizes
  `units_per_battle` to `2·max(t0,t1) = 128` and leaves **17 slots permanently dead** — a
  roster the sim carries, packs and iterates but that holds no unit. Alternating makes a tile
  shortage degrade symmetrically.

⚠ **Gariland is 10×15 and tops out near 111 units.** Past that the fixture warns and
under-fills. A bigger cast needs a bigger map.

### F30 — the curve, and the breaking point

Seed 424242, `--skip-strategy --combat-autostart --perf-debug`, overlay closed,
`misc:render_unfocused_fps = 2000`, 2 interleaved reps per arm, 25 s each, load 2.0–2.9, swap
flat (no thrash: the collapse is CPU, not paging). Each row is the **worst 3-second `[PERF]`
window** the arm produced, beside its median.

| cast | slots | worst ms | fps | alive @ worst | `CombatLoop` | `GPU` | `state` | `visual` | median ms | windows > 6.94 ms |
|---|---|---|---|---|---|---|---|---|---|---|
| **13** (shipped) | 16 | **1.3** | 745 | 12/16 | 0.55 | 0.08 | 0.06 | 0.41 | 1.20 | **0/6** |
| 16 | 16 | 1.5 | 682 | 14/16 | 0.62 | 0.10 | 0.06 | 0.44 | 1.30 | 0/6 |
| 32 | 32 | 2.6 | 392 | 24/32 | 1.25 | 0.33 | 0.13 | 0.78 | 1.90 | 0/8 |
| **48** | 48 | **3.9** | 258 | 38/48 | 2.14 | 0.65 | 0.22 | 1.26 | 2.30 | **0/12** |
| **64** | 64 | **7.6** | 132 | 39/64 | 3.82 | 1.81 | 0.33 | 1.66 | 4.15 | **1/10** |
| 80 | 80 | 52.8 | 19 | 13/80 | 28.95 | 24.22 | 3.71 | 1.01 | 10.55 | 11/14 |
| 96 | 96 | 29.6 | 34 | 54/96 | 18.36 | 14.11 | 1.36 | 2.88 | 5.05 | 7/16 |

**48 units never crossed the budget in 12 windows; 64 crossed it.** That is the answer, and it
is **five times the shipped cast**.

> The 80 and 96 rows are past the cliff and their *ordering* should not be read: at that cast
> size the battle resolves at wildly different rates between arms, so which one peaks higher is
> a property of how fast the seed happened to kill people. What both show is the same thing —
> the frame is gone.

### F31 — it is a cliff, and the edge is the tick interval, not the budget

`CombatLoop` runs a fixed 60 Hz tick inside `_process`, so `tpf = frame_ms / 16.67`.

| cast | 13 | 16 | 32 | 48 | 64 | 80 | 96 |
|---|---|---|---|---|---|---|---|
| `tpf` at the worst window | 0.1 | 0.1 | 0.2 | 0.2 | **0.5** | **3.2** | 1.8 |
| zero-tick frames in that window | 2063 | 1874 | 1004 | 603 | 218 | **0** | **0** |

Below 16.67 ms/frame **most frames run no tick at all** and per-tick work is amortised across
several frames. Above it, every frame runs one or more ticks and pays that work in full — which
makes the frame slower, which raises `tpf`, which lands more per-tick work on the next frame.
**The real boundary this document has been circling is the 16.67 ms tick interval, not the
6.94 ms budget.** That positive feedback is **W6** — *"the tick catch-up loop is unbounded"* —
which this document carried as `TODO / robustness only / zero at 1×`. It measures zero at 13
units because at 13 units the frame never reaches 16.67 ms. **Re-scoped: it is the amplifier.**

### F32 — the cost is `edge`, and `edge` is one function

| cast | `step` | `cols` | **`edge`** | `anim` | of which `chk` | `cine` | `proj` |
|---|---|---|---|---|---|---|---|
| 13 | 0.03 | 0.01 | **0.01** | 0.04 | 0.01 | 0.00 | 0.00 |
| 32 | 0.08 | 0.03 | **0.04** | 0.18 | 0.04 | 0.00 | 0.00 |
| 48 | 0.18 | 0.03 | **0.08** | 0.36 | 0.08 | 0.00 | 0.00 |
| 64 | 0.39 | 0.09 | **0.55** | 0.78 | 0.55 | 0.00 | 0.00 |
| 80 | 1.88 | 0.45 | **13.26** | 8.63 | **13.24** | 0.01 | 0.00 |

`edge` timed **three** calls as one span — the gated `_check_state_changes()`,
`cinematic_manager.update_edge()` and `projectile_manager.advance_one_tick()`. R26 split them,
and the answer is not close: **`chk` is 99.8–100 % of `edge` in every window of every arm.**
`cine` and `proj` read 0.00 ms throughout. Reporting "`edge` is the cost" would have named a
*span*; the cost is one function, and the fix shape depends on which. That split is the whole
reason this round can file W9 against a function instead of against a timer.

The compute dispatch is still not the problem: `step` is **1.88 ms of a 28.95 ms loop** at 80
units. R11's "the GPU does 0.12–0.19 ms/frame" generalises — at 6× the cast, the GPU half is
still under 2 ms.

⚠ **What this rig cannot separate.** `chk` is reported per frame, and nothing counts how often
the gate opened, so 0.08 → 0.55 → 13.24 is the product of three factors moving together
(per-call cost ∝ slots, gate rate → 1, ticks per frame → 3.2). **Do not read it as a
superlinear per-call cost.** A gate-open counter is one line and is the first thing W9 should
add. R25's W2 is what happens when an item is sized off a number nobody decomposed.

### ❌ F29 — R25's 2.08 ms / 482 fps was the 500 fps cap

The same defect as F28, one setting further out, and the tell was in R25's own table: it
corrected the rule from 144 to **500** and then reported **482 fps** — 96 % of the new cap.
Re-taken as a straight A/B on one code state, 2 interleaved reps each, identical unit states
window-for-window:

| `render_unfocused_fps` | worst window | median window | windows > 6.94 ms |
|---|---|---|---|
| **500** | **2.1 ms — 474 fps** | 2.00 ms — 498 fps | 0/6 |
| **2000** | **1.3 ms — 745 fps** | 1.20 ms — 859 fps | 0/6 |

R25's figure reproduces *exactly* at 500 (2.1 vs 2.08, 474 vs 482) — which is what makes this a
cap and not a code change. **The shipped cast's heaviest frame is 1.3 ms, 19 % of the budget,
not 30 %.** The rule now says to **A/B the setting**, because "far above what you expect" has
failed three times running (60 → 144 → 500) against an engine that keeps getting faster.

### ❌ F33 — the `Units:` histogram counts corpses, and the hygiene rule said to trust it

`get_all_unit_states()` returns one record per **slot** and the report bucketed them by logical
activity. There is no `DEAD` entry in `LOGICAL_ACTIVITY_NAMES`, so a dead unit keeps reporting
whatever it was doing and an unused slot reports `IDLE`. Measured: `Units: ACTING=31,
WALKING=17` on a 48-slot battle — **16 alive**. The two arms of F29 print the *identical*
histogram for three windows running while the live count falls 12 → 8 → 6.

Fixed in the same pass: the line reads `Units: 12/16 alive: WALKING=7, ACTING=6, IDLE=3`. Every
"read the histogram before believing a run" instruction in this document was, until now, an
instruction to read a number that cannot see a death — including F27's, which happened to work
because its failure mode (`IDLE=15`) is about *slots*, not deaths.

### What this round does NOT show

- **Nothing about the navigator.** The whole curve is `GPUArena.tscn`. That is **W10**, and it
  is the item that still decides whether any of this reaches a player. The choice of host is
  argued in W7's entry rather than left implicit.
- **Nothing about a real battle.** No ENTD has 64 combatants. This measures the *engine's*
  headroom on a synthetic cast, not a battle anyone will play.
- **No `alive`-vs-`slots` split of the cost.** `chk` is per slot by construction, so the curve
  is keyed on cast size; the two were never varied independently.
- **No fix.** W9 and W6 are `TODO` with fix shapes and, in W9's case, a stated objection that
  has to be answered against #93 before it is built. ❌ **R27: W9 is `REFUTED`** — its gate
  factor does not exist and its rebuild is 20 % of the call (corrections 13–14). The cliff R26
  found is real and is now **W11**.

### Rig notes

The `edge` split costs six extra `Time.get_ticks_usec()` calls per tick inside the hot loop.
That is real, and it is why `chk + cine + proj` can read fractionally under `edge` rather than
exactly equal to it — the difference is the instrument. It is far below the effect being
measured (`chk` is 99.8–100 % of `edge`), but a future item that needs `edge` to the third
decimal should account for it rather than assume the split is free.

`render_unfocused_fps` restored to 60 and `user_settings.json` restored from backup on every
exit path (verified: the harness traps `EXIT INT TERM`, and the overlay preference is
re-asserted after every arm because Godot rewrites the file on quit). Two other agent sessions
shared the box throughout; load stayed 2.0–2.9 and swap did not grow, so the collapse rows are
CPU, not paging. The 13-unit arms of F29 and F30 are the same configuration measured twice and
agree to 0.1 ms.

---

## Round 27 — W9's premise is FALSE. The cliff is the swing SFX, and it is 3.8× the frame.

**The deliverable was the measurement W9's own entry demanded** — *"count the gate first"* —
and counting it refuted the item. Nothing was optimised in this pass either; the fix that came
out of it is filed as **W11** with an A/B that sizes it, and it lands in a package this round
deliberately did not touch.

The chain, measured end to end, each link named by the link above it:

```
_process tick loop
  └─ gated _check_state_changes()        chk — 100 % of `edge` (R26/F32)
       ├─ build   0.6–0.8 ms  (39 fields x slots)          ~20 %
       ├─ interp  0.1–0.3 ms                               ~5 %
       └─ apply   2.1–6.3 ms                               ~75 %   <-- F35
            └─ STATE_CHANGED  0.7–7.4 ms/event             <-- F36
                 └─ _update_unit_animation   95–99 % of it
                      ├─ get_all_unit_states()  0.4–1.4 ms (the FULL 101 fields)  <-- W12, now DONE
                      └─ ActivityTranslator.translate  0.3–16.0 ms
                           └─ ACTING routing only (IDLE 0.17, WALKING 0.006)
                                └─ _start_attack_animation
                                     ├─ unit.attack()      0.21–0.27 ms  FLAT
                                     └─ SfxRouter.play_system  0.55–27.8 ms  <-- W11
```

### F34 — the gate: it does NOT open more often as the cast grows, and ~1 unit moved

Seed 424242, `--skip-strategy --combat-autostart --perf-debug`, overlay closed,
`misc:render_unfocused_fps = 2000`, 2 interleaved reps per arm. The new `chk split` report line
counts gate opens, movers per open, and cost per call. **The two reps produced bit-identical
counts** (13 units: 10/35/23 opens in windows 1–3; 80 units: 44/55/72/61/52/51/20) — the sim is
deterministic at a seed, so only the *timings* below carry run-to-run variance.

| cast | slots | gate opened, % of ticks | movers per open | per-call ms |
|---|---|---|---|---|
| **13** (shipped) | 16 | 6–19 % | 1.00–1.13 | 0.93–1.47 |
| 32 | 32 | 14–24 % | 1.00–1.27 | 1.35–1.65 |
| 48 | 48 | 5–22 % | 1.00–1.10 | 1.76–2.09 |
| 64 | 64 | 16–30 % | 1.14–1.22 | 2.51–4.14 |
| 80 | 80 | 11–40 % | 1.08–2.59 | 2.86–15.9 |

**W9's factor 2 is refuted.** The entry argued *"`P(any of N units changed state this tick)`
goes to 1 as N grows — at 13 units most ticks skip the call, at 80 almost none do."* The gate
opens on **5–40 % of ticks at every cast size**, with no trend in N. It is flat because a unit
changes logical state on the order of once per second, not once per tick: six times the cast is
six times the *events*, spread over the same ticks, and they collide rather than filling the
gap.

**Movers per open is ~1.** Whatever the cast size, when the gate opens it is because *one* unit
moved. W9's fix shape (refresh the movers, not all slots) therefore has the largest possible
denominator — and it still does not pay, because of F35.

### F35 — inside one gated call: the rebuild is 20 %, the APPLY PUMP is 75 %

`_check_state_changes` splits into the snapshot build, the interpreter's detection pass, and
`_apply_combat_event`'s side effects. Per gated call:

| cast | build | interp | **apply** | events/call |
|---|---|---|---|---|
| 32 | 0.24–0.26 | 0.08–0.13 | **1.10–2.10** | 2.1–6.7 |
| 64 | 0.52–0.62 | 0.12–0.14 | **1.84–2.25** | 1.9–2.5 |
| 80 | 0.54–0.75 | 0.11–0.34 | **2.07–6.27** | 2.0–8.3 |

The per-FRAME call after the loop is a different animal and cheap — 0.02–0.21 ms build,
0.06–0.11 interp, 0.002–0.11 apply, 0.02–0.70 events — because it usually lands on an unchanged
`_battle_version`, so the snapshot cache is warm and the interpreter finds nothing moved.

**This is what kills W9.** Its fix removes the build and most of the interp — about 20–25 % of
the call — and *moves* the apply work to the per-frame call rather than deleting it, because
the events that cost are precisely the state-movers' own. Rank it by the document's own rule
and it is a fix that makes the same work cheaper for one caller, not one that deletes work.

### F36 — apply by event kind: two handlers, and ~1 ms per event

80 units, per applied event:

| kind | n (3 s window) | ms/event |
|---|---|---|
| **DIED** | 5–14 | **0.46–16.8** |
| **STATE_CHANGED** | 24–178 | **0.67–7.41** |
| HP_CHANGED | 4–23 | 0.18–0.59 |
| POSITION_CHANGED | 28–200 | 0.004–0.008 |
| ACTION_COMMITTED | 10–51 | 0.002–0.004 |

Three orders of magnitude between the top two and the rest. Inside `_apply_state_changed` the
split is not close either — log 0.005–0.011, the `state_changed` signal 0.003–0.006, the
charge-VFX branch 0.003–0.008, facing 0.031–0.051, and **`_update_unit_animation` 0.86–7.35,
i.e. 95–99 % of the handler.**

### F37 — and `_update_unit_animation` is the ACTING routing, which is the swing SFX

`translate()` dispatches on the logical activity, so timing it per activity names the routing
without touching generated code:

| logical state | n | ms/call |
|---|---|---|
| **ACTING** | 8–51 | **0.72 → 40.7** (rises monotonically through the battle) |
| IDLE | 8–45 | 0.10–0.18 (flat) |
| WALKING | 5–82 | 0.002–0.007 (flat) |

ACTING with no casting ability is the weapon-attack path, `_start_attack_animation`. Split:

| | ms/call, first window → last |
|---|---|
| the full 101-field snapshot it re-fetches | 0.003–0.006 (warm — W12's copy in the caller pays it) |
| `unit.attack()` — resolution map, layers, weapon | **0.21 → 0.27, FLAT** |
| swing slug resolve | 0.011–0.027 |
| **`SfxRouter.play_system(swing_slug)`** | **0.47 → 27.8** |

The animation half is flat. The **sound** half is the cliff, and it tracks the sound engine's
live-session count (sampled in the same windows: 21, 21, 79, **131**, 29, 45, 1).

### F38 — the A/B: suppressing ONE cue is 3.8× the frame at 80 units

Same fixture, same seed, arms interleaved, 2 reps, the swing cue suppressed at its call site
(the hit/block cue at `CombatLoop.gd:1651` was left in, so this is a **lower bound** on the
audio path's cost). Windows are keyed on alive count, which is identical in both arms:

| alive | SFX on, avg ms (rep1/rep2) | SFX off, avg ms (rep1/rep2) | on, max | off, max |
|---|---|---|---|---|
| 66/80 | 6.27 / 6.23 | 5.88 / 5.40 | 86.7 | 76.7 |
| 55/80 | 4.20 / 4.24 | 4.29 / 4.14 | 14.0 | 14.6 |
| 44/80 | 3.51 / 3.86 | 3.28 / 3.29 | 21.7 | 11.0 |
| 33/80 | 4.41 / 5.38 | **2.59 / 2.57** | 24.4 | 9.7 |
| **22/80** | **7.01 / 7.09** | **1.89 / 1.83** | **45.1** | **12.7** |
| 13/80 | 1.99 / 1.57 | 1.36 / 1.33 | 21.0 | 9.7 |
| 8/80 | 0.97 / 1.10 | 0.93 / 0.93 | 11.6 | 7.4 |

**7.01 → 1.89 ms — 3.8×** in the worst window, and both reps agree to 0.1 ms on both arms. The
shape matters as much as the ratio: with the cue off the frame time **falls monotonically as
units die**, which is what a per-unit cost looks like. With it on the frame time *rises* to a
peak two thirds of the way through the battle — that is the session backlog, not the cast.

At the **shipped 13-unit cast the same A/B is a null result**: 0.55 / 0.39 / 0.29 ms with the
cue, 0.54 / 0.38 / 0.28 without. The cue still costs **0.27–0.47 ms per attack** there; the
frame simply has 6.4 ms of headroom to absorb it.

### ❌ The mechanism, read from the source (NOT measured — see the caveat)

> ❌ **BOTH ITEMS BELOW ARE REFUTED (R28, correction 15).** The caveat this section states was
> the right one and the answer is neither: the load is **0.3 %** of the call, `_pick_unit` is
> **not on this path**, and **99.8 % of the call is `_audio_mutex.lock()`**. Kept as written
> because this round's whole point was that it had not been timed. See **R28/F39–F42**.

`SfxRouter._play_slot` → `ExMateriaEffectSfx.play_one_shot` → `_audition_impl`, which does two
things a per-attack rate cannot afford:

1. **`_FedsBank.load_from_file(feds_path)` — it opens and re-parses the bank file on every
   call.** A cached loader (`_load_bank_cached`) exists eight lines away in the same file, and
   its docstring says the audition path *"keeps the per-call load — they're parity/one-shot
   paths, not per-glyph rates."* For the dialogue typewriter that reasoning holds (it routes
   through `play_click`, which caches). **For combat SFX it is false**: at 80 units this path
   is a per-glyph rate.
2. **Session bookkeeping is O(live sessions) per play.** `_pick_unit()` calls
   `_reap_dead_sessions()`, which walks every session and asks each one's unit for a voice
   count and its play for sequencing state. One-shot sessions are also reaped on the render
   clock (~8×/s); combat opens them faster than that, and the count was measured at **131**.

⚠ **Which of the two dominates is NOT measured.** Splitting them needs a timer inside
`exmateria-sound`, and this round deliberately put none there — the whole finding is measured
from the game side, at `SfxRouter.play_system`'s call site.

### What R27 does not measure

- **The hit/block cue** (`CombatLoop.gd:1651`, `_trigger_physical_reaction`). It is on the same
  path and was left running in both arms, so every number here understates the audio cost.
- **Whether the fix is a cache, a reap, or getting the call off the tick thread.** All three are
  changes to `exmateria-sound`, whose parity contract this document has no standing to rule on.
  That is why **W11 is filed rather than built**.
- ~~**DIED at 0.46–16.8 ms/event.**~~ ✅ **ANSWERED (R28/F46): it was the same defect.**
  `SfxRouter._on_unit_died` funnels through the same `_play_slot` → the same mutex. Measured
  **40.15 → 0.40 ms/event** across the W11 A/B at identical event counts. The guess here was
  right; it is now measured rather than likely.
- **The navigator.** Still W10, still the item that decides whether any of this reaches a
  player. Unchanged from R26.

### Built in this round: W12 only

**W12 is `DONE`** — `_update_unit_animation` takes the caller's snapshot row instead of
re-fetching the full 101-field one per event (see its entry). It is the half of R27 that needed
no ruling from anyone: the fields are already in the union, the guards that keep that true are
already in the tree, and the caller was already holding the row.

**W11 is filed and not built, deliberately.** Its three candidate fixes all change
`exmateria-sound`, and the one that looks cheapest from here — deferring the cue to the frame
boundary — changes when a sound plays relative to the animation frame that triggers it. That is
a ruling about the package's parity contract, which is not this document's to make.

### Rig notes

The instrumentation is 12 `Time.get_ticks_usec()` calls per gated call plus 2 per applied
event, all unconditional (only the printing is gated on `--perf-debug`, matching the existing
buckets). At the shipped cast that is well under the 0.01 ms `chk` reads; at 80 units it is
noise against a 3 ms call. It is committed, because the next session needs `sfx_play` to verify
W11's fix and re-deriving it cost this one four runs.

`user_settings.json` and `misc:render_unfocused_fps` were backed up and restored on every exit
path (`trap EXIT INT TERM`), per correction 11's rule; the F38 arms were taken at
`render_unfocused_fps = 2000` on both sides. Another agent session held the box for part of the
round: **the sweep-1 and sweep-2 arms at 80 units produced identical event counts but per-call
timings differing up to 5×**, which is exactly the contention hazard this document already
records — every ratio above is taken **within one run**, and F38's arms are interleaved.

---

## Round 28 — W11 step 1: the SFX play is 99.8 % **waiting on a mutex**, and both filed mechanisms are FALSE. ❌ CORRECTION 15

R27 sized W11 from the game side and read *two* mechanisms out of `exmateria-sound`'s source
without timing either, stating plainly that "which of the two dominates is NOT measured." This
round put the timers in. **Neither is the cost.** The split is measured, it reproduces across
two interleaved reps, and it re-points the whole item.

### Method

Six `Time.get_ticks_usec()` reads inside `_audition_impl` / `_play_pair_locked` plus four on the
scheduler thread, all unconditional, exposed as cumulative counters through a new
`ExMateriaEffectSfx.audition_split_stats()` that **deliberately does not take `_audio_mutex`** —
`lock_us` measures the wait for that very mutex, so a reader that blocked on it would perturb
its own subject. `CombatLoop` diffs two samples per 3 s window. Same fixture as R26/R27:
`--stress-units=40 --quit-after=35`, seed 424242, `render_unfocused_fps 2000`, arms interleaved,
2 reps. **Event counts reproduce bit-identically between reps** (n=86/51/58/… per window), which
is the correctness check; the timings below also agree between reps to within a few per cent.

### F39 — the split: `lock` is 99.8 % of it, and `load` and `bind` are FLAT

80 units, rep 1. `lock` is the wait for `_audio_mutex`; `load` is `_FedsBank.load_from_file`;
`bind` is the unit picker; `seq` is slot alloc + `play_feds_pair`.

| window | sessions | `sfx_play` | **`lock`** | `load` | `bind` | `seq` |
|---|---|---|---|---|---|---|
| #1 | 15 | 0.49 | **0.47** | 0.052 | 0.036 | 0.118 |
| #3 | 81 | — | **0.53** | 0.082 | 0.015 | 0.149 |
| #4 | 134 | — | **6.38** | 0.087 | 0.020 | 0.169 |
| #5 | 178 | — | **13.81** | 0.089 | 0.023 | 0.176 |
| #7 | 240 | 25.7 | **25.67** | 0.087 | 0.024 | 0.168 |

ms/call. **`load` never moves** (0.052 → 0.087 across a 16× growth in sessions) and **`bind`
never moves** (0.036 → 0.024 — it *falls*). The entire 55× growth in the call is `lock`.

### ❌ CORRECTION 15 — W11's two filed mechanisms are both refuted

1. ❌ **"the bank file is opened and re-parsed on every play"** — true, and it costs **0.087 ms
   of a 25.7 ms call: 0.3 %.** Caching it (the authorised step 2) is a real but negligible win.
2. ❌ **"`_pick_unit()` → `_reap_dead_sessions()` walks every live session per play"** — this
   path **never calls `_pick_unit`**. `SfxRouter._play_slot` uses `play_one_shot`, which marks
   the session `one_shot`, and `_play_pair_locked` routes those to **`_pick_event_unit()`** — a
   walk of `MAX_EVENT_UNITS = 2`, with no reap in it. `_pick_unit` is the fallback taken only
   if the reserved event lane could not be created at all. Making it O(1) (the authorised step
   3) would move **0.024 ms**, on a function this path does not execute.

Both were read from the source rather than timed, and both are the same error R25's W2 and
R27's W9 already recorded: **sizing a fix off an undecomposed number.** Third firing.

### F40 — the other side of the mutex: the scheduler holds it for 31 ms, and the reap is 0.16 % of that

`_scheduler_main` takes `_audio_mutex`, stamps up to `SCHED_CATCHUP_MAX_SUBS` subs, releases,
and yields. Timing that hold:

| window | sessions | hold ms/hold | holds | reaps | reap ms/reap | **reap as % of hold time** |
|---|---|---|---|---|---|---|
| #1 | 15 | 0.30 | 3487 | 23 | 0.178 | 0.4 % |
| #4 | 134 | 4.07 | 628 | 25 | 0.196 | 0.2 % |
| #7 | 240 | **31.49** | 96 | 12 | 0.394 | **0.16 %** |

The reap costs 4.7 ms of the 3 023 ms the scheduler spends holding the lock in window #7. **The
O(live sessions) walk is not the cost.** It is the sequencer work the walk fails to remove.

### F41 — the cost is ~32 µs per sequencer ENTITY per sub, and the entity count is unbounded

`_stamp_unit_group` ticks `unit["rt"]` for every active unit, and that walks the unit's
`_EntityList` — one entry per cast still bound to it. Counting the entities ticked per sub, and
dividing the scheduler's total hold time by (subs × entities):

| window | sessions | entities/sub | ms/sub | **µs per entity** |
|---|---|---|---|---|
| #1 | 15 | 21.2 | 1.00 | 47.1 |
| #3 | 81 | 51.5 | 1.89 | 36.7 |
| #4 | 134 | 107.0 | 3.50 | 32.7 |
| #5 | 178 | 155.7 | 4.97 | 31.9 |
| #7 | 240 | 234.1 | 7.87 | 33.6 |

**Flat at ~30–33 µs/entity across an 11× range, in both reps.** The scheduler's per-sub cost is
linear in the entity count and nothing else. Its real-time budget is **4.16 ms per sub**, so it
goes permanently behind at **≈130 entities** — which is window #4, exactly where `lock` steps
from 0.53 to 6.38 ms. Past that point it is always in a catch-up streak, so it is always
holding the mutex, and the main thread's cue always waits.

### F42 — the root cause: the reap's third condition is a per-UNIT question asked of a per-SESSION decision

`killed` is **71 in window #1 and 0 in every window after it**, while `sessions` climbs 15 → 240.
Counting which condition declines each session:

| window | skip: undispatched | skip: grace | **skip: voices** | skip: sequencing |
|---|---|---|---|---|
| #1 | 0 | 65 | **652 (90.9 %)** | 0 |
| #4 | 0 | 45 | **2 632 (98.3 %)** | 0 |
| #7 | 0 | 15 | **2 796 (99.5 %)** | 0 |

The condition is `if _unit_voice_count(u) > 0: continue  # still audible`. `u` is the **unit**,
not the session. With `MAX_EVENT_UNITS = 2` and `EVENT_SESSIONS_PER_UNIT = 8`, every one-shot
game-event cast in the battle lands on one of two SPU cores, and **as long as any single cast on
that core is audible, every other session bound to it is un-reapable.** In sustained combat both
event cores always have voices, so after the opening lull **nothing is ever reaped** and each
core's entity list grows monotonically for the rest of the battle. An un-reaped session is still
linked into `unit["list"]` — `_end_effect_locked` is what unlinks it — so it is still sequenced
every sub, forever, silently.

The session already knows its own voices: it records `last_slot_idx`, and
`pool.voice_for_slot(slot)` gives the voice pair (this is exactly what
`_click_pair_voices_locked` does). The per-session question is answerable with what is already
stored.

### The chain, end to end

> 80-unit combat opens ~15 one-shot casts/s → all land on 2 reserved event cores → the reap's
> per-unit voice veto never clears → sessions accumulate (240 by t=35 s) → each stays linked in
> its core's entity list → the scheduler pays ~32 µs/entity/sub → past ~130 entities it exceeds
> its 4.16 ms/sub budget → it is permanently in catch-up, so it permanently holds `_audio_mutex`
> → the next `SfxRouter.play_system` on the tick path waits 25.7 ms for that mutex → the tick
> loop stalls → more ticks per frame → more attacks applied per frame → more casts.

That feedback is what R26 saw as the budget *collapsing* at 64 units rather than degrading.

### At the shipped 13-unit cast this does not fire

`lock` is **0.001–0.025 ms**, entities/sub is **1.1–9.8**, and `sessions` returns to **0**
between engagements — the lulls are long enough for `_unit_voice_count` to reach zero, so the
reap works and the backlog drains. Consistent with R27's null A/B at the shipped cast. **W11 is
a headroom item, not a current-cost item**, on the same footing as W6 and W9.

### What this round does NOT do

- **It does not fix anything.** The measurement was authorised; the fix it points at was not.
  The two authorised fixes (cache the bank, O(1) picker) are now measured at 0.3 % and 0.1 %,
  and the fix the evidence points at — making the reap's audibility test per-session — is a
  **reap policy change**, which the standing authorisation explicitly excluded. It is also not
  step 4: nothing here argues for moving the cue off the tick thread, and doing so would move
  the 25.7 ms wait rather than delete it, leaving the scheduler still over budget.
- **It does not explain `DIED` at 0.46–16.8 ms/event.** `SfxRouter._on_unit_died` routes through
  the same `_play_slot`, so the same chain is the likely answer, but it is not measured.
- **The hit/block cue** (`CombatLoop.gd:1651`) ran in every arm here, as in R27.

### ❌ F43 — shape B is UNSAFE, and the claim that killed it was mine

R28 recommended unlinking a sequencing-done entity from its unit's list on the grounds that
`runtime.gd:tick()` opens with `if _entity_done(ent): continue`, so such entities are "already
semantic no-ops". **That was read off the first of THREE loops over `entities` in `tick()`, and
the other two do not skip a done entity.**

| phase | loop | skips done? |
|---|---|---|
| 1 — catchup | `for ent in entities: if _entity_done(ent): continue` | **yes** |
| 1.5 — extras/primaries/drainer | `for ent in entities: … _tick_extras_primaries_drainer(…)` | **no** |
| 2 — KON accumulator scan | `for ent in entities: … for slot in _entity_active_slots(ent)` | **no** |

Two concrete harms:

1. **It would stop the post-EndBar release-decay processing.** Phase 1.5's two halves say so in
   their own comments — `_tick_extra_bindings`: *"they fire per-driver-slot pair, not
   per-channel-state … So just don't skip here"*; `_tick_primary_dispatchers`: the dispatcher's
   internal gate *"skips the work but lets the pre-line recorders fire."* And phase 2 walks
   `_pool.active_slots()`, which `pool.gd` says still processes *"the slot's post-EndBar
   release-decay state."*
2. **It would change `flush_kon_commit()` from one call to two.** Phase 2 sets `has_sfx_entity`
   from the linked entities; phase 3 fires the commit **twice** when it is false. That is a
   named PCSX-parity behaviour: *"Legacy SFX's tick_all_dispatchers fires it ONCE … keeping the
   one-IRQ deferral that matches PCSX entity+0x60 semantics."*

The engine's own notion of "safe to unlink" is `_end_effect_locked`, which unlinks **together
with** `p.release_and_free()` (the key-off) and the `session_count` decrement. Unlinking without
that half is not a subset of it.

**This is the fourth firing of the round's own lesson**, and this time against me rather than
against R27: a claim read from one call site, presented as a property of the system. F39–F42
were measured; F43's predecessor was not, and it was wrong.

### ❌ F44 — shape C is unsafe too, and `release_and_free()` is why the veto exists

The follow-up proposal was to enforce `EVENT_SESSIONS_PER_UNIT` as a real cap by *evicting* the
oldest one-shot cast when the lane packs, on the grounds that `_pick_event_unit`'s own comment
says the packed case already "preempts the oldest pair slot". Reading `release_and_free()`
killed it:

> *"Other casts' slots are untouched — only slots this play owns (its non-null `_dispatchers`
> entries) are released."*

A `_Play`'s `_dispatchers` array is indexed by **pool slot**, and the pool is **per-unit**. When
a slot is preempted and handed to a newer cast, the old play's entry for it goes **stale** — so
`release_and_free()` on that old cast would `emit_koff_now` on a slot someone else now owns.
**`_unit_voice_count(u) > 0` is what makes that safe**: if the unit has no active voices, a
stale key-off cannot hit anything audible. The per-unit veto is not merely over-conservative —
it is load-bearing, and F42 should not be read as "delete it". (`_stat_preempts` was a flat
**10** in every window of every run, so the slots were in fact being recycled cleanly; only the
*session* objects leaked.)

### W11 BUILT — the one-shot silence reap

`ONE_SHOT_SILENCE_SUBS = 120` (500 ms) adds a **second, narrower way past the veto** rather than
removing it. Scoped to `one_shot` casts (the reserved event lane); combat casts, beds and the
click unit keep the veto unconditionally; `is_sequencing_done()` still gates it, so a cast whose
slot was stolen by a live cast reads *not* done and stays. Same family as
`ONE_SHOT_REAP_GRACE_SUBS`, which exists for the same reason: the lifecycle a fire-and-forget
cast actually has is not the one the long grace assumes.

### F45 — the A/B: `sfx_play` 27.00 → 0.25 ms, and the variance goes with it

Arms **interleaved back to back in one time window**, the switch a `sed` on the single condition
reverted between arms, so nothing debug-only ships and both arms see the same box state. Four
reps across two passes; the final window (8/80 alive) of each:

| pass / rep | sessions | entities/sub | `sfx_play` ms | frame avg ms |
|---|---|---|---|---|
| ab / rep2 | 275 → **1** | 267.6 → **6.1** | 27.00 → **0.25** | 21.01 → **0.99** |
| ab2 / rep1 | 355 → **1** | 349.4 → **5.7** | 38.96 → **0.28** | 23.62 → **1.07** |
| ab2 / rep2 | 280 → **1** | 274.8 → **6.4** | 26.19 → **0.35** | 15.60 → **1.05** |
| ab / rep1 ⚠ | 59 → 1 | 3.6 → 3.8 | 0.36 → 0.30 | 6.17 → 5.17 |

**Three of four baselines develop the backlog; all four fixed arms are bounded** (peak sessions
≤ 23, drained to 1). ⚠ **ab/rep1's OFF arm never developed it** — peak 59 sessions, `sfx_play`
never above 1.12 ms — so it is not a baseline, and its frame numbers are contention, not this
path. That the pathology fires on some runs and not others is itself the finding: **the fix
removes the variance, not just the mean.**

**At the shipped cast: no regression and no effect.** `sfx_play` 0.488 → 0.467, 0.331 → 0.277,
0.357 → 0.264; entities/sub 1.1 → 1.1; attack counts identical in both arms. The lane never
packs there, so the new path never fires.

### The regression test, and the arm in it that could not fail

`tests/SfxOneShotSessionDrainTest.gd` pins both halves — a one-shot cast drains **while its core
stays audible**, and nothing else ever takes that path (`silence_freed == 0` for `audition()`).
It runs on a fresh `init_as_capture()` engine deliberately: those units are not streaming, so
`_unit_voice_count` reads `get_active_voice_count()` synchronously instead of the audio thread's
published count, which would make the "is the core still audible" precondition racy.

⚠ **The first version passed with the defect seeded.** At a 20-sub firing cadence the core goes
quiet between reaps, the *ordinary* reap drains everything, and the session-count arm could not
fail. Overlapping the blips (`SUBS_BETWEEN = 4`, 200 casts) reproduces the production pathology
offline: **52 sessions with the fix, 200 — every cast, nothing ever reaped — without.** Both
arms now red on the seeded defect. The seeded-defect run is the only reason that was caught, and
it is why the fixture overlaps.

### F46 — `DIED` was the SAME defect, and W6's perf case largely evaporates

Both were open items in R27 ("nothing here explains `DIED`"; W6 re-scoped to a perf item by
R26). The W11 A/B answers both without new code, because the same four interleaved reps already
carry the numbers. Event counts are identical between arms (`n` shown), so these are per-event
costs, not throughput artefacts.

**`DIED` — 40.2 → 0.40 ms/event.** `_apply_death` emits `unit_died`, `SfxRouter._on_unit_died`
is connected to it, and that handler funnels through the same `_play_slot` → `play_one_shot` →
the same mutex. The three clean reps, final window:

| rep | `DIED` OFF | `DIED` ON | n |
|---|---|---|---|
| ab/rep2 | 21.79 | **0.44** | 5 |
| ab2/rep1 | 40.15 | **0.40** | 5 |
| ab2/rep2 | 28.43 | **0.40** | 5 |

It climbed monotonically with the session backlog on every baseline (0.8 → 3–4 → 11 → 18–24 →
28–40) and is **flat at 0.4–1.2 ms across the whole battle** with the fix. R27 guessed this was
"the most likely answer" and declined to claim it; it is now measured. **`DIED` was never a
second defect.**

**W6 — `tpf` 5.1 → 0.2.** The unbounded catch-up loop was sized off `tpf` reaching 3.2 at 80
units (R26). Measured across the same arms, `tpf` in the final windows goes **3.7 / 5.1 / 4.0 →
0.1 / 0.2 / 0.2**. The backlog was a **symptom of the slow frame, not an independent cost**: a
27 ms frame owes the tick clock ~4 ticks, and the fix removes the 27 ms. W6's loop is still
unbounded and that is still worth bounding as **robustness** — but its perf justification is
gone, and re-deriving it against the shipped engine would now measure ~0.2.

⚠ **ab/rep1 is the contended rep** (its OFF arm never developed the backlog; `tpf` 3.3 → 3.1 and
`DIED` noisy in both directions). Excluded, as in F45.

### Verification

**The code diff is zero deletions** — `git show --stat` reports 190 insertions and **0** deleted
lines across `effect_sfx_engine.gd` and `CombatLoop.gd`. Not one existing line changed; every
addition is a counter, an accumulate, or a comment.

- **Game suite: 728/734 at N=10 (9.5 min), `--no-preflight`.** The six non-passes were
  `stranger:exmateria_battlefield` (the documented named burn-down, goal #5 unmet on record),
  two that passed on a solo re-run, and **three that were `project-assets/` being absent from
  this worktree entirely** — `EffectScreenInsertDeleteAcceptanceTest` names the missing
  `EFFECT/E015.BIN` and `EffectScriptSaverAcceptanceTest` prints `[SKIP] — E019 ROM extract not
  present` (which the runner scores `NO_VERDICT`, not a pass). Symlinked
  `project-assets → fft-monorepo-main` per the root `CLAUDE.md` and all three pass. **Nothing
  in the suite is attributable to this change.**
- ⚠ `--no-preflight` skips the ~25 static guards; #920 still aborts the pre-flight (#929 is the
  five red guards behind it), so this verdict does not cover them.
> Re-run after the fix landed: **suite 732/735**, the new `SfxOneShotSessionDrainTest` passing
> in it; the three reds were `stranger:exmateria_battlefield` (known) plus two Effect Studio
> texture tests that **pass solo** — a concurrent suite from another session was on the box.
> `verify_all.sh` re-run: **G, A, E, S PASS** again.

- **`exmateria-sound`'s own gate — `workspace/regression/verify_all.sh`: G, A, E, S PASS.**
  Gate **E** is the one that matters here: it renders each SMD through both the lockstep loop
  and the audio thread's own queue and diffs them sample for sample, with a red arm that must
  diverge. Gate **C CANNOT RUN** — `extern/godot-cpp` is an uninitialised submodule in this
  worktree, so SCons has no `SConscript` (the `.so` itself is symlinked from the hub and loads
  fine; Gate S confirms `ExMateriaPsxSpu` registers). Gates **B and D NOT RUN** — they need
  `cure_no_music.sstate` and a primed music baseline, neither on this machine.
- ⚠ **Gate B is the one that would exercise this file's path, and it could not run.** The
  effect-sound PCSX probe pairs are the effect-SFX parity arm; G/A/E/S cover the music, stream
  and install surfaces. The zero-deletion diff is what carries the parity argument here, not
  Gate B.

### Rig notes

- The instrument is committed, on both sides of the symlink. Ten `Time` reads on a path that
  fires per *attack*; at the shipped cast the whole `sfx split` line reads under 0.4 ms/call.
- **Two worktree-setup gaps cost this round ~20 minutes each**, both already named in the root
  `CLAUDE.md` and neither reported as a setup error by the thing that hit it: `project-assets/`
  was missing (three suite tests read as real reds), and `exmateria-sound/.godot/` did not
  exist, so gates A and E failed with `Could not find type "ExMateriaSound"` — the repo's own
  `class_name`s, on a cold cache. `godot --path exmateria-sound --import` once, and both gates
  pass. A cold class cache reads exactly like a real break.
- ⚠ **`pgrep -f "run_tests_parallel"` said my suite was still running for 20 minutes after it
  had finished.** It was matching two *other* sessions' waiter shells, which contain the pattern
  in their own command lines and are immortal. The previous handoff records this trap and it
  still fired. Match `python3 …run_tests_parallel.py`, or just read the log for its summary
  block.
- **A first pass of this rig produced two reps that disagreed wildly** (rep 1's sessions climbed
  to 281 while rep 2's stayed under 71, on identical event counts) — the contention hazard R27
  records, on a box with another agent's editor open. The two later passes both reproduced
  cleanly. **Two reps agreeing is the check; one rep is not evidence on this box.**
- `user_settings.json` and `misc:render_unfocused_fps` backed up and restored on
  `trap EXIT INT TERM`, per correction 11.

---

## Round 29 — W10 answered (the intercept is ≈ 0) and W5 attributed. ❌ CORRECTION 16

**Both items were `DIAGNOSE`; both deliverables were measurements and both are now `DONE`.**
Two new `TODO`s came out of them — **W13** ([#955](https://github.com/timbermania/fft-monorepo/issues/955)) and **W14** ([#956](https://github.com/timbermania/fft-monorepo/issues/956)) — and one correction (**16**).

### The rig

- `NavigatorMain` driven live at `time_scale` 1 by setting `"navigator.autoplay": true` in
  `config/tune_overrides.json` — there is no CLI flag. 600 s reaches the Orbonne battle
  (group 3, MAP056) at ~+370 s and the **Gariland** battle (group 9, MAP022 — the arena's own
  map) at ~+560 s. Two walks, interleaved with three 60 s arena arms and two 35 s static arena
  arms, in one time window. `user_settings.json` (`was_visible = false`),
  `config/tune_overrides.json` and `misc:render_unfocused_fps` backed up and restored on
  `trap EXIT INT TERM`. Cap 4 000, A/B'd against 16 000 at matched load — 1.9/1.7/1.3 vs
  2.2/1.7/1.4 ms, i.e. **not a cap** (the fourth time this had to be checked).
- **The W5 instrument, and it is NOT committed.** `PerfMonitor` already runs at
  `process_priority = -100`; a probe node at `1000` was added as its child, so the two stamps
  bracket the whole per-frame script `_process` pass. Every top-level `_process` in `src/` and
  `addons/` (50 of them) was wrapped to bin its own wall cost by script path, and
  `CombatLoop`'s 3 s `[PERF]` report **drains** the bins so the census and the buckets average
  the same frames. Reverted after the run; the doc keeps the numbers, the tree keeps nothing.
  **Validated two ways**: the census billed `CombatHost.gd` 0.4084 ms in a window where
  `CombatLoop`'s own independent timer said `total: avg=0.41ms`, and instrumented vs clean
  arena arms at matched load agreed on frame and buckets to 0.01 ms.

### F47 — the navigator's intercept is smaller than the arena's own rep-to-rep spread

Full table in **W10**. Outside-`CombatLoop`, `[PERF #2]` at tick 360: arena **0.818 / 0.839 /
0.887 ms** over three arms; navigator on the same map **0.881 / 0.916 ms**. **Δ = +0.051 ms
against a control that spans 0.069 ms.** R26's breaking point restates to `64 − (0.05 ÷ 0.07)`
= **63 units**.

The census says why: the navigator adds `ScenarioVM` (0.017), `ScenarioVMDebugPanel` (0.008)
and `DialogueBox` (0.002) and **loses** `TileCursor` (0.023) and `FeedbackHudManager` (0.015).
The two sets cancel. **Twenty-eight rounds of arena numbers transfer to the game's host**, and
the padded-navigator fixture this entry left open is not worth building.

### F48 — W5's block is 0.85 ms, half render and half script, and F19 is refuted

Full table in **W5**. Of the 0.82–0.89 ms outside `CombatLoop`: **0.46–0.49 ms** is engine +
render submit + present, **0.36–0.39 ms** is non-`CombatLoop` script, and the script half is
named down to ≈ 0.30 ms with a ≈ 0.06–0.09 ms remainder. The static floor of the same scene
(units placed, combat never started) is **0.66 / 0.74 ms** — within ~0.15 ms of the block, so
most of the block is the static scene, as the old entry guessed and could not show. And the
block is **65–68 % of the frame and larger than `CombatLoop`** — a *bigger* share than the
quarter the entry claimed, on a frame six times smaller.

**F19's sprite-repaint hypothesis is dead.** `Unit._process` + `CameraRelativeRenderer` across
all 13 units = **0.071 ms/frame**. The largest script item in the frame after the combat loop
is `AudioBusMixerDebugPanel` — a debug panel, running with the overlay closed, at
**0.093–0.103 ms/frame**, bigger than every unit put together. That is **W13**, and its
mechanism is that `DebugDashboard.add_panel()` calls `on_shown()` unconditionally at
registration while **`on_hidden()` has no caller in the repo at all**.

### ❌ CORRECTION 16 — the discriminator's instrument is a per-second MAXIMUM, and it includes the render

Stated in full in the corrections list. `Performance.TIME_PROCESS` is published once a second
from `process_max`, and `process_ticks` spans `RenderingServer::sync()` + `draw()`. The
`cpu_proc:` and `est_other_mean` lines of every `PerfMonitor` summary in this document are
therefore not what they read as — `est_other_mean` has printed **0.00 ms every time**, which
is the arithmetic failing, not the frame being explained. Nothing in the standing diagnosis
rests on it.

### Still open after this round

- **W13** and **W14** are filed and unfixed, on purpose: W5's entry said *"do not fix it in
  the same pass that diagnoses it."*
- **Should the head/tail bracket be committed?** The 50-file census must not be, but the
  three-file bracket (`PerfMonitor` head + tail probe, drained by `[PERF]`) is the only
  instrument here that can split a frame into script and not-script, and W8 wants exactly this
  kind of witness. That is a design call, not a measurement — left to the user.
- **W3's clean optimizer number** still does not exist, and `exmateria-sound` Gate B still has
  never run here.

### Machine state

Blender held a core for the whole session (constant across every arm, which is what
interleaving is for) and another session's suite ran through part of pass 1 — pass 1's later
arms show it (load 2.4 → 12.1) and are not quoted above. Every number in W5, W10 and this
round is from pass 3, run at load 2.6–5.5 with nothing but Blender alongside.

---

## Round 30 — W13 and W14 BUILT. ❌ CORRECTIONS 17, 18

**The first code this effort has shipped since W11**, and the first two items it has taken
whose deliverable was a fix rather than a measurement. Both landed with a **counted** witness,
which is what W8 has been asking for through five landings.

Both of the round's inputs were **partly false**, in the same shape R29 warned they would be:
each item's *mechanism* had been read off the source and its *consequence* had not been
checked. That is corrections 17 and 18, and it is the fourth and fifth consecutive round in
which a read-not-verified claim has died.

### W13 — the gate belongs on the base class, because the filed mechanism was incomplete

The entry said the panel *"does the right thing three times over and is defeated by its
caller."* Two of the three are real. The third — `_build_ui()`'s closing `set_process(false)`
— runs **before the panel enters the tree**, and `Node`'s `NOTIFICATION_READY` calls
`set_process(true)` for any script that defines `_process`, *before* `_ready`
(`scene/main/node.cpp:272`). It has never had an effect in any build.

That is not bookkeeping. Under the filed mechanism the fix is *"give `on_hidden()` a caller"*,
and the census that produced the mechanism only ever saw the panels **the GPU arena
instantiates**. Enumerated instead of sampled: of **41** `BaseDebugPanel` subclasses, **three**
define `_process`.

| panel | its own gate | what its `_process` does | verdict |
|---|---|---|---|
| `AudioBusMixerDebugPanel` | `on_shown`/`on_hidden` + an inert `set_process(false)` | walks every `AudioServer` bus, 4 label rebuilds, 2 live SPU queue reads | **gated** — the measured item |
| `ScenarioVMDebugPanel` | **none at all** — the file never calls `set_process` | `_populate_list` + `_refresh_state` + `_highlight_current_pc`, every frame a `ScenarioVM` is alive | **gated** — a caller-side fix would not have touched it |
| `ScenarioUnitSpriteOffsetDebugPanel` | none | **re-applies** the stored `shared_loc_offset` overrides to the live units | **opted out** — it drives the game, it does not repaint |

So the gate went on `BaseDebugPanel` (`_notification` → `set_process(is_visible_in_tree())`),
`on_hidden()` was deleted with its docstring, and the one panel that must keep running while
hidden says so with `processes_while_hidden`. Full shape and the three reasons behind it are
in **W13**.

The third row is the one worth carrying forward. It is not a perf finding — it is the answer
to *"is this fix free?"*, which the handoff insisted be measured rather than assumed. It is
free for two of the three panels and **would have silently broken the third**: a calibration
set in that rig stops holding the moment the panel folds away, with no error. Two of the three
`set_process(true)` sites the entry flagged (`EffectTimelineView`, `UI3RegistryView`) turned
out not to be `BaseDebugPanel`s at all, and are untouched.

### W14 — the correction was dead, not wrong

Fixed as the entry described: read `PSXDisplay.live_par`, not the editor-only
`RenderingServer.global_shader_parameter_get`. But the entry's consequence is overstated.
`pixel_aspect` **ships at 1.0** (`project.godot [shader_globals]`, no committed
`render.pixel_aspect` override), so the multiply the dead guard was skipping is a multiply by
one: **no frame the player has ever seen was in the wrong place.** What was broken is the
surface's response to a PAR *scrub* — ADR-0036 dec. 2's opt-in, which it silently was not
honouring. Correction 18.

The test asserts both halves on purpose: the stretch happens at PAR 1.5, and the anchor is
**unmoved at 1.0**. A witness that only proved the first would leave the next reader believing
this moved the dialogue box.

**No speed claim is made**, per R29's own A/B, which could not resolve one (arm B +4.5 %, arm
A's two reps 12 % apart). The assertable win is the log — ~286 000 of a 150 s walk's 288 124
lines were this call's error and backtrace — and the correctness.

### Witnesses, and why neither is a stopwatch

Both items are worth ~0.1 ms against a ~1.25 ms frame on a box whose rep-to-rep spread is
larger than that. Neither is measurable here and **neither is claimed as measured**. What both
have is counted work that regresses: a `_process` callback registered while nothing can see the
panel, and a call to an API that cannot work outside the editor. That is W8's ruling, and it is
why W8 is no longer the reason to defer a witness — two now exist.

Both tests are **seed-proven** (6/9 red on the unfixed tree, in both cases on exactly the
claims the fix makes), which is the check that separates a witness from a decoration.

`tools/check_mount_node_paths.py` (ADR-0217 dec. 3) caught the W14 test reaching a mount node
name and refused the pre-flight. Correct catch, and the crossing is now declared rather than
exempted: the coupling runs the wrong way — on a rename, production silently swaps to the tile
origin while a test holding its own copy of the name stays **green**.

### Still open after this round

- **W6** — still `TODO`, still a design decision (a clamp changes the sim's timing contract),
  and still needs a ruling rather than an agent.
- **W4** — still `PARTIAL`. W13 answered the *"expensive while closed"* half of its family.
- **W8** — the ruling stands and is now honoured twice; whether the standing threshold it
  asks for should exist as a *suite-level* assertion is still open.
- **The head/tail frame bracket** — recorded under `## Open`, still unanswered, still the
  user's call.
- **W3's clean optimizer number**, and `exmateria-sound` Gate B: unchanged.

