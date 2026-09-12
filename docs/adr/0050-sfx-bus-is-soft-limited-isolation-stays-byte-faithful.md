# The SFX bus is soft-limited; a sound in isolation stays byte-faithful

## Status

Accepted (2026-06-19) — **decision 1 superseded 2026-08-25** by
[ADR-0163](0163-limiting-is-a-bus-stage-and-the-domain-bus-is-where-it-goes.md).

> **Status note (2026-08-25).** **Decision 2 (one cast per unit) stands**, and is
> load-bearing: it is what lets each `Spu` become its own `AudioStream`, so the
> cross-cast sum happens in float on a real bus instead of in an int32 buffer.
> **Scoped 2026-08-28** — it applies to casts that close (`EffectInstance`), not
> to the fire-and-forget `SfxRouter` game-event blips, which now pack into a
> bounded reserved lane. See the amendment at the end.
>
> **Decision 1 (`BusLimiter`) is superseded.** Its job — "the SUM crossing the
> ceiling is ducked smoothly, never chopped" — is now an
> `AudioEffectHardLimiter` at 0 dBFS on the `SFX` and `Ambient` buses, installed
> by `MasterBus`. In GDScript the class cost 2.3x the SPU render it protected
> (`D3` §3), and the brick wall it replaced no longer exists to protect against:
> nothing clamps at the sum any more. See ADR-0163 for the measurement that
> decided *which* bus (Fire x6 drives the untamed SFX sum to 4.26, so a
> Master-only limiter would duck music by up to 12.6 dB).
>
> **One consequence below was already false before that change.** "Isolation is
> byte-faithful... a lone full-scale effect (Shiva, Ifrit) is unchanged" stopped
> holding at follow-up #122, which put a -0.3 dBFS HardLimiter on `Master` —
> that attenuates a lone source sitting at 1.0. It has been true only up to the
> Master rack since 2026-06-19.

The continuous effect-sound engine (`ExMateriaEffectSfx`) mixes every concurrent
FEDS cast and hands Godot a finished stereo buffer. Until now the final
PCM→frames step (`_pcm_to_frames`) **brick-wall clamped** the summed signal to
`[-1, 1]`. When several casts overlapped, their summed samples exceeded
full-scale and got chopped flat — the harsh, buzzy "hardware-issue" distortion.
Per-voice isolation does not prevent this: even with every sound on its own
voice, the master sum (and the shared reverb input) still saturate.

Measurement set the constraint. Played **alone**, effects are not uniformly
quiet: Cure peaks at 0.15, Reraise at 0.48, but the big summons — **Shiva and
Ifrit — already peak at full-scale (1.0)**, clipping inside the C++ SPU core on
their own 3 pairs / 6 voices. The user confirms Shiva *alone* sounds correct, so
that solo character is desired and must be preserved. Because a lone full-scale
effect already uses 100% of the output range, "byte-identical isolation" and
"artifact-free concurrency" are mutually exclusive by conservation of dynamic
range — there is no headroom to fit "Shiva + anything" without either clipping
or lowering the overall level.

## Decision

Four changes, all **downstream of and without touching the C++ SPU parity core**
(GDScript bus stage only). Decisions 3 and 4 arrived on 2026-08-28, when a
dose-response rig showed decision 2's one-cast-per-unit rule is wrong for a cast
nobody ever ends; they are folded in here rather than standing as a second dated
section, because an ADR states the NOW.

1. **`BusLimiter` replaces the clamp** (`src/audio/BusLimiter.gd`, wired into
   `_pcm_to_frames`). It derives a per-block **target** gain (`ceiling/peak`) — a
   constant scale across the block, so the waveform is uniformly scaled (shape
   preserved), never chopped — but applies it **per-sample with attack/release
   smoothing**, the gain a continuous state that carries across block seams.
   **At rest gain == 1.0**, so any single source at or below full-scale —
   including a lone full-scale Shiva — passes through bit-for-bit unchanged. The
   threshold sits at 0 dBFS: it acts only on the *sum* crossing the ceiling,
   never on a single source sitting at it.

   *Per-sample (not per-block instant) attack matters:* the first cut applied the
   block target by an instant snap, which stepped the gain at each 4 ms IRQ seam
   and produced an audible **click when multiple casts overlapped** (diagnosed
   with `SfxPopDiagTest` + the limiter/engine counters below — the limited
   boundary discontinuity exceeded the raw signal's). Smoothing the gain
   per-sample removed it; the only residual is a sub-millisecond onset clamp when
   a block starts at high amplitude before the attack catches up — far gentler
   than the seam click or the original brick wall, and tunable via `ATTACK_COEF`.

2. **One cast per unit** (`_pick_unit`, UNLOCKED). Each cast binds to an empty
   SPU unit (spawning one if needed, up to `MAX_UNITS`, raised 4→8), doubling up
   only at the cap. This moves cross-cast summation out of a single unit's
   in-core brick-wall clip and onto the downstream bus limiter, where it is
   governed smoothly — and gives each cast its own reverb tank (no cross-cast
   tail smear). Within one cast, its own voices still sum + clip in-core: that is
   the faithful solo sound, left untouched.

   *Routing is leak-proof.* The binding metric is `session_count` (it spreads
   casts dispatched in the same frame, before their voices register). But a cast
   whose `end`/`orphan` never arrives would otherwise wedge its unit forever, and
   with one-cast-per-unit that accumulates: over a combat the 8 units fill with
   phantom sessions, every new cast is forced to double up, and in-core clipping
   grows until **every spell pops by end of combat** (diagnosed live in GPUArena
   via the audio monitor: `sessions` ratcheting 2→52 and sticking, `cap_doublings`
   climbing in lockstep). So `_pick_unit` first runs **`_reap_dead_sessions`**: a
   cast whose sound is provably over — dispatched, sequence finished, no active
   voices on its unit, idle past `REAP_GRACE_SUBS` (~2 s, longer than the gap
   between a cast's pairs) — is reclaimed even if its cleanup never came. A
   per-session `last_sub` activity stamp gates the grace. After the fix `sessions`
   oscillates and settles low; `cap_doublings` plateaus.

   🔴 *And it does NOT apply to fire-and-forget game-event SFX.* This rule is
   right for the casts it was written about — `EffectInstance` combat spells,
   which open a token and close it, and whose reverb tanks must not smear into
   each other. It is wrong for the `SfxRouter` game-event blips (swing, hit,
   invalid, page-flip, `unit_died`, event-script `{0x21}`), which open a token
   nobody ever ends. Charging a 200 ms blip a whole SPU unit plus the
   `REAP_GRACE_SUBS` (~2 s) grace means a cue with any repeat rate walks the pool
   to `MAX_UNITS` and holds it there. Decision 3 is the answer.

3. **A bounded, reserved, PACKING event lane.**
   `ExMateriaEffectSfx.play_one_shot()` (a `one_shot: true` flag on the session;
   `audition()` keeps the old behaviour for the bank/FEDS test scenes, which DO
   end their tokens) routes through `_pick_event_unit()` instead of `_pick_unit()`.
   That picker is the **inverse** of decision 2: it packs, filling one unit up to
   `EVENT_SESSIONS_PER_UNIT` before spawning a second, and never exceeds
   `MAX_EVENT_UNITS = 2`. Game-event blips therefore cannot take a unit combat
   wants, and cannot move the scheduler's per-sub cost. They also get a shorter
   reap grace (`ONE_SHOT_REAP_GRACE_SUBS`, ~0.1 s) because a cast the caller never
   intends to close has no later pair to wait for. The cost is the one decision 2
   bought: game-event SFX now share a reverb tank and sum in-core with each other.
   They do not share one with a combat cast, which is where the audible stake was.

4. **The scheduler yields unconditionally.** One lock per iteration,
   a bounded catch-up batch (`SCHED_CATCHUP_MAX_SUBS = 4`), and an
   `OS.delay_usec(SCHED_YIELD_USEC)` after a stamping iteration as well as the
   `SCHED_IDLE_MS` sleep after an idle one. A larger batch was tried and rejected:
   8 subs traded a ~7 ms hold for a ~57 ms one.

## Consequences

- **Isolation is byte-faithful.** A single effect ≤ full-scale is unchanged; a
  lone full-scale effect (Shiva, Ifrit) is unchanged. Guaranteed by the
  unity-gain-at-rest limiter, locked by `SfxBusLimiterTest` (transparent below
  ceiling; lone full-scale unchanged).
- **Concurrency is smoothly ducked, not shattered.** An over-ceiling sum comes
  out ≤ 1.0 with the waveform scaled, not flat-topped (`SfxBusLimiterTest`
  over-ceiling case: bounded, only the apex grazes the ceiling). The unavoidable
  cost: when a quieter sound overlaps a full-scale one, the bus-wide duck pulls
  the loud one down a hair while they overlap — inaudible-grade for short combat
  SFX, and far better than the prior clip.
- **CPU tracks concurrency, capped at 8 units.** Idle units sleep
  (`UNIT_IDLE_TAIL_SUBS`), so the cost is only paid while casts actually overlap;
  8 simultaneous casts is the worst case before they double up.
- **The capture suite is unaffected.** `EffectSoundCaptureTest` reads the raw
  pre-limiter `render_subs` path, so it still measures the unlimited sum (and now
  doubles as a regression guard); its `concurrency_hi` case confirms
  one-cast-per-unit (8 casts → 8 units).
- **Pop/crackle is observable "in the data."** `ExMateriaEffectSfx.debug_snapshot()`
  exposes per-mechanism counters so a future click report can be attributed
  instead of guessed: `preempts` (voice stolen mid-flight), `cap_doublings`
  (cast forced to share a unit at the cap → in-core clip), `underruns` (producer
  fell behind → buffer gap), and a `limiter` block (`gain_steps`, `overflow_blocks`,
  `min_gain`, `max_peak`, `clamp_hits`). `tests/SfxPopDiagTest.tscn` is a kept
  diagnostic harness (not a pass/fail regression) that fires N simultaneous casts
  and prints these. Note `underruns` is **live-only** — `capture_mode` parks the
  producer, so offline harnesses read 0; watch it in the running game.
- **Follow-up RESOLVED — the leak source (#121).** Two real sources were found and
  fixed, so `sessions` now returns to ~0 once a battle goes quiet (verified live in
  GPUArena: drains to 0 after victory/defeat, was sticking at a handful).
  (1) Game effects were parented to the *persistent root viewport*
  (`get_viewport().add_child`), so a scene reset (`reload_current_scene`) orphaned
  them — their `_exit_tree` never fired and `orphan_effect` never reached the engine
  (and the node itself leaked). They now parent to the in-scene `CombatLoop` node
  (`EffectManager.spawn_*`), so they die with the scene and clean up. (2) The
  fire-and-forget game-event SFX path (`SfxRouter.audition`) opens casts it never
  ends — it relies entirely on `_reap_dead_sessions`, which only ran *at bind time*,
  so the last casts before a lull/combat-end stuck until the next cast arrived.
  `_reap_dead_sessions` now ALSO runs on the render clock (`_render_sub_pcm`,
  ~8×/sec), making the reap a true belt-and-suspenders. The defensive reap is
  retained as designed.
- **Follow-up RESOLVED — the underrun counter (#123).** `_stat_underruns` no longer
  ticks merely on an empty hand-off queue. It counts a TRUE underrun only when the
  generator's own buffer is *also* drained below ~20 ms (`_underrun_fill_thresh`),
  i.e. an audible gap is imminent. Live in GPUArena it now stays flat (boot warmup
  only) instead of climbing into the thousands.
- **Follow-up RESOLVED — the Master-bus limiter (#122).** The SFX stream + music
  stream summed at Godot's `Master` bus and clipped at the device output (measured
  1.15–1.34). A Godot `AudioEffectHardLimiter` (ceiling −0.3 dBFS) now sits at the
  head of the Master bus (`ExMateriaAudioEngine._install_master_limiter`), ahead of the
  lazily appended monitor taps. Live `master clip/s` now stays 0 even under heavy
  SFX over battle music.


**The dose-response measurement behind decisions 3 and 4.** Two independent
defects, on `GPUArena` with an interleaved REST/FIRE rig (2/s, 5/s, 10/s;
`+probe`/`-probe` control arms):

1. **Allocation.** The 10/s arm sat at 8 units / 35 live sessions,
   `cap_doublings` 41–49, and the audio clock fell from 240 subs/s to
   **121–142** — `_schedule_sub_locked`'s cost scales with the number of ACTIVE
   units, so a saturated pool overruns the 4.16 ms IRQ budget.
2. **Lock fairness.** `_scheduler_main` locked, stamped one sub, unlocked, and
   — while `behind` — immediately re-locked with no yield. glibc mutexes barge,
   so a main-thread `SfxRouter` cast could lose that race indefinitely: measured
   **3591 ms** blocked in `_audio_mutex.lock()`, on the same thread that stamps
   the music register writes. Filed as its own defect because it survives any
   fix to (1); real combat casts also put several units live.

Measured on the same rig, same process shape, before → after:

| metric | before | after |
|---|---|---|
| max frame, 10/s burst | 6347 ms | 29.7 ms |
| max frame, 5/s burst | 4878 ms | 28.4 ms |
| max frame, 2/s burst | 155 ms | 22.9 ms |
| frames > 33 ms, all blocks | ~330 | **0** |
| max `_audio_mutex` wait | 3591 ms | 11.9 ms |
| audio clock during burst | 121–142 subs/s | **240 subs/s** |
| transient SFX units | 8 (cap) | **1** (never spawns) |
| `cap_doublings` | 41–49 | **0** |

`tests/SfxOneShotPoolTest.tscn` is the standing guard — it drives the real
`SfxRouter.play_system()` in `capture_mode` and asserts the transient pool does
not grow, the burst lands on the event lane within `MAX_EVENT_UNITS`, the lane
packs, and one-shot sessions drain well inside `REAP_GRACE_SUBS`. Seeding the
defect back (`_play_slot` → `audition`) fires all four arms.

**What this does NOT fix (#668).** `_schedule_sub_locked` still costs more per
sub as `_units` grows, and still overruns its budget past roughly half the
transient pool. `EffectInstance` combat casts legitimately spread one-per-unit
under decision 2, so a busy enough battle reaches the same cliff by a route
decisions 3 and 4 do not touch. `MAX_UNITS = 8` was chosen for voice overlap with no
reference to the scheduler's 4.16 ms budget; #668 holds that.

## Amendment (2026-08-28, later) — #668 was a parity probe, not the unit count

The amendment above is right that `_schedule_sub_locked` costs more per active
unit, and #668 held the cliff open on that basis. It was wrong about the
magnitude, and therefore about what to do: **76% of the per-unit cost was a
PCSX-parity trace probe running with no trace sink open.**

`_EffectPlaySound.tick_irq_start_for_runtime` is called once per 240 Hz IRQ per
active unit, and its whole body is capture: `_emit_envelope_tail_for_runtime`
plus the two noise emits call `mixer.get_voice_debug_info()` **49 times** (24
voices, twice, plus one), each building a Dictionary across the GDExtension
boundary. `_Trace.emit` is cheap when disabled — its *arguments* are not, and
nothing gated them. The gate read `if _cadence_anchored:`, which is a
parity-anchor condition, not a "is anyone recording" one. Four emit sites further
down the same file (in `tick`'s entity-catchup loop) already read
`_cadence_anchored and _Trace.is_enabled()`; this one had only the first term.

Measured on the LIVE scheduler with N concurrent `audition()` casts held on the
transient pool (`_perfscratch/SchedLoad`, two passes, same process):

| | before | after |
|---|---|---|
| `tick_irq_start` per active unit per sub | **818 µs** | **2.2 µs** |
| cliff | **N = 4** (half the pool) | none through N = 8 |
| audio clock at N = 8 | 115 subs/s | **240 subs/s** |
| scheduler lead at N = 8 | **−6106 ms** | +25.2 ms (target 25.0) |
| overdue register writes, 3 s at N = 8 | 5155 | 125 |
| main-thread `_audio_mutex` wait, mean | 32.9 ms | 1.3 ms |
| main-thread frame p50 | 34.3 ms (29 fps) | 16.0 ms (60 fps) |

Two things follow.

**`MAX_UNITS = 8` and the 4.16 ms budget do agree, and #668 closes.** The
residual per-unit cost is `rt.tick()`'s ~250 µs — 2.0 ms of the 4.16 ms budget
at the full pool, so the ceiling is ~16 units, not 4. (That 250 µs is the same
species — Dictionary literals built as arguments to disabled `_Trace.emit` calls
across `dispatcher.gd` / `flush_tick.gd` / `spu_irq_walker.gd` — and is worth
its own pass, but it is headroom now, not a cliff.)

**Decisions 3 and 4 stand, on their own reasoning, not on these numbers.**
Packing the fire-and-forget lane still keeps a repeated cue off the units combat
wants, and the scheduler still must not barge. What changes is that the earlier
amendment's "the pool cannot afford 8 units" reads as a property of the design
when it was a property of a probe; a lane bound chosen against a false ceiling
should be re-derived if it is ever tightened further.

**The symptom this explains.** SFX degrading under concurrency while music never
does is the same stall seen through two lead depths: music is stamped on the main
thread with `TARGET_LEAD_SECONDS = 2.0`, SFX by the scheduler thread with
`SCHED_LEAD_SUBS = 6` — **25 ms, 80× shallower**. A negative-lead scheduler is
inaudible in one and continuous in the other.

`tests/SfxTraceProbeGateTest.tscn` is the standing guard. It asserts a RATIO
(the gated entry point against the payload it must not build) rather than an
absolute time, so it does not encode this machine's speed, and it asserts its own
preconditions — tracing off, cadence anchored on — because either one silently
sends the measurement down the wrong branch. Seeding the defect back moves it
from 253× to 0.7×.
