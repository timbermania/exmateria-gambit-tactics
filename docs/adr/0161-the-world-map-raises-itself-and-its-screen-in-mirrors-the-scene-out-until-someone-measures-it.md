# The world map raises itself, and its screen-in mirrors the scene-out until someone measures it

The world map owns the ramp that brings it up. It mounts under its **own**
full-screen **abr 2** subtractive quad and clears it over **60 vsyncs**, stepping
every **2**, on its own vsync clock — not under a `ColorRect` the navigator
tweens. Those two numbers are **borrowed from the scenario `{3E}` on the other
side of the same hand-off, not measured from `WLDCORE`**, and this decision
expires the moment somebody measures the real one.

Status: accepted (2026-08-25). Implements
`research/working_documents/WORLD_MAP_SCREEN.md` §24.1 (the primitive) and
mirrors `COLOR_SCREEN_OPCODE_3E.md` (the ramp). Owned by
`src/world_map/WorldMapScreenIn.gd` + `src/world_map/screen_in_mode2.gdshader`;
awaited by `src/scenarios/NavigatorMain.gd`. Guarded by
`tests/WorldMapScreenInTest.gd` and by the `--menu=screenin` contact sheet.
Adds **Screen-in** to `CONTEXT.md`.

## Context

The port cut to the overworld in one frame, which read as a pop. That was fixed
with a plain cross-fade through black — a `create_tween()` on the `color:a` of an
opaque `ColorRect`, 0.45 s each side — and the constant that held it said so
about itself: *"Not a faithfulness claim… when the real ramp is read off
`WLDCORE`, this constant and both tweens are what it replaces."* This is that
replacement, and it is worth recording that reading the code turned up two
things the framing had wrong.

**The exit was already right.** A group whose successor is `world-map` normally
ends on its own scene-out. Scenario 12's tail — `assets/scenarios/chunks/
scenario_012_chunk.json`, offset 148 and 151 — runs `{60} Fade Sound Time=60`
and `{3E} Color Screen Mode 2, (0,0,0)->(255,255,255), Time 60` together, and the
port decodes and runs both. So the way *out* was a faithful 60-frame subtractive
ramp all along; only the way *in* was a 27-frame alpha tween. "0.45 s for each
half" described one half.

**And the invisible half is not the one you would guess.** `run_world_map` does
not call `_teardown_world()`, so the VM and its `ScenarioColorScreen` quad are
still up during the mount. `_fade_battlefield_out()` therefore ramps a black rect
over an already-black screen: on the measured path it shows nothing at all.

What §24.1 *did* measure is the world map's own fade: two full-screen monochrome
rectangles, 256×240 at (−128,−120), OT slot 15, command `0x62` — **abr 2,
`B − F`**, the same blend family `{3E}` Mode 2 uses. What it could not measure is
the ramp, and the reason is structural rather than an oversight:

> On **every** world-map capture the repo holds, the pair is armed at **zero
> strength and disabled** (`enable 0x800D0AB8 = 0`, rgb `0x800D0ADC..DE =
> 000000`), so `FUN_800E0E34` is never reached and no `0x6x` primitive appears in
> any frame dump.

Every savestate is **settled** — taken after the fade finished. So the blend is
known and the timing is not.

## Decision

### 1. The map raises itself

§24.1's fade block is `WLDCORE` BSS, emitted from `FUN_80069810` inside
`WLDCORE`'s own render loop. On console the world map fades *itself* in. The port
now matches: `WorldMapScene` builds the quad, advances it inside its existing
`advance(delta) -> int` vsync loop beside `_town.advance_open()`, and emits
`screen_in_finished`. The navigator holds black around the mount and waits.

Three things fall out of that and each is worth more than the tidiness:

- **The clock is exact.** `WorldMapScene` already counts vsyncs at 60 Hz with a
  fractional debt, and already refuses tweens for this exact reason: *"a
  delta-driven tween would run the ramp at the display's rate and finish the open
  in a third of the time on a 144 Hz panel."* The ramp inherits that.
- **The rate is testable without a wall clock**, because `advance()` was split
  out of `_process` for precisely that.
- **A layering trap retires.** A navigator-owned cover could not be the inherited
  `_fade_rect` — that lives in `FadeLayer`, *also* layer 100, and the map's layer
  joins the tree later, so the map drew on top of the rect meant to hide it. A
  screen that covers itself cannot have that bug.

### 2. The ramp is a MIRROR, and it says so

60 vsyncs, stepping every 2, `255 → 0`. That is scenario 12's `{3E}` run
backwards: same blend, same length, same quantisation. It is defensible because
the two screens hand off to each other and the primitive is measured identical —
but it is **not a measurement**, and nothing in the code or the tests may claim
otherwise. `WorldMapScreenInTest` deliberately does **not** pin 60 as truth; a
test that did would entrench the guess.

**This decision expires** when §20.5's load recorder is re-run logging, per vsync
across the load, the four words §24.1 names — `0x800D0AB8` (enable),
`0x800D0AC0` (OT slot), and the descriptors' rgb at `0x800D0ADC..DE` /
`0x800D0AEC..EE`. The rgb sequence *is* the ramp: its length gives the frame
count and its steps give the quantisation, exactly as scenario 8's
`0,51,102,153,204,255` gave `{3E}` its 2-frame step. `round5_load_trace.csv` does
not sample those words; the rig needs them added. When that lands, two integers
in `WorldMapScreenIn` change and nothing else does — which is the point of
keeping the ramp local (§4 below).

### 3. Subtractive, baked to 5-bit levels, drawn before the expansion pass

The quad is `blend_sub` with `ALPHA = 1.0` — `dst - src`, the console's `B − F`.
Not an alpha ramp over black: `B·(1−a)` is a proportional dim, while `B − F` is a
floor lift that holds black until the ramp drops below the brightest pixel and
then emerges highlights-first. They do not look the same, and the measured one is
subtractive.

Two constraints come from `psx_expand_555.gdshader`, which states the map's
compositing rule: *"the world map composites in the GPU's own 5-bit channels;
every quad is baked as `8 * v` for a level v in 0..31"*, with the expansion to 8
bits running **once** on the finished frame. So the ramp **quantises to whole
5-bit levels**, and its quad is added to the tree **before** the `BackBufferCopy`
— otherwise the frame computes `e(B) − e(F)` where the console computes
`e(B − F)`, reintroducing the ±1-on-25.9%-of-the-frame error that shader exists
to close.

A `canvas_item` shader is unavoidable, and that is what forced a new file rather
than a reuse: `assets/shaders/screen_color_mode2.gdshader` is `shader_type
spatial` and its include writes `POSITION`, which canvas_item has no equivalent
for — and the map mounts as a `CanvasLayer`, which composites *over* the 3D
viewport that quad lives in, so it could not cover the map in any case.

### 4. The arithmetic is restated, not shared

`WorldMapScreenIn` duplicates six lines of `ScenarioColorScreen.tick()`. That is
deliberate. **The 2-frame step is a fact about `FUN_801467dc`** — the `{3E}`
worker — and the world map's fade is `FUN_80069810`, a different function whose
step size nobody has observed. The two ramps share a *measured blend* and an
*assumed curve*; extracting a shared kernel would encode the assumption as
structure, which is the trap §24.1 opens on: *"a model that reproduces the output
is not the mechanism."*

Duplication is worth removing when two copies are two answers to one question.
These answer two — *"how does `{3E}` step?"* (measured) and *"how does `WLDCORE`
step?"* (guessed) — and collapsing them would turn the pending measurement into a
change to a shared file with a Cutscene consumer. It would also open a
`world_map → Cutscene` edge where there is currently none. ADR-0097 declined a
global curve vocabulary for the same reason: *"the units are not
interchangeable."*

The contact-sheet renderer **is** shared, because that genuinely is one question
asked twice.

### 5. This is not a `UI3Beat`

ADR-0084 and ADR-0097 govern element transitions — `open()` / `close()` /
`place_at()`, cadence declared per verb, validated by the beat that owns it. A
screen-in is not an element verb: it is a screen-level ramp on the screen's own
vsync clock, with no element, no recipe and no reversal. Asking it to be a beat
would give it a vocabulary built for a different thing.

### 6. The exit stays as it is, and that asymmetry is deliberate

`WorldMapScene._leave()` still tears down in one frame, so the map goes soft-in /
hard-out. That is not an oversight. The way *out* of the map is **data**: an
`enter` emit's second operand is a **transition mode**, `1` or `2`, light or
heavy, and `Campaign.enter_at()` already returns it while `NavigatorMain`
explicitly carries it *"logged, not acted on."* Bolting one fade onto `_leave()`
would invent a constant exactly where the console has a branch, and would quietly
close a decision that is currently, correctly, held open. The exit is blocked on
`transition_mode` becoming load-bearing — on both arms and their own RE question,
not on a number.

## Consequences

**The black gets longer.** ~0.45 s of hold plus a 1 s ramp, against ~0.9 s
before — and subtractive holds black longer at the *start* than the tick count
suggests, because nothing is visible until the ramp drops below the brightest
pixel on screen. The failure mode of this change is "it stalls," and no
assertion can see it: that is why `--menu=screenin` renders a contact sheet whose
early frames are weighted toward the start of the ramp, and why the frame count
is the dial if it reads slow.

**The suspend handshake became a poll, then an await.** `NavigatorMain` used to
sequence `set_suspended(false)` off `await _fade_cover_out()`. It now checks
`view.screen_in_active()` and only then awaits `screen_in_finished`. The order is
the safety argument: an `await` armed after the signal has already fired never
returns, which is §18.2's hang reached by a second route. The ramp advances only
inside `advance()`, which runs in `_process`, so nothing can land between the
poll and the await within one frame.

**Every `--shot=` capture settles the ramp.** `_capture` freezes the vsync clock,
so without an explicit settle a capture would freeze on whatever frame the
warm-up reached — the same guarantee `_town.set_open_frame(OPEN_VSYNCS)` already
gives §38.

**A ramp that wants a contact sheet must be seekable.** The rig seeks rather than
ticks, so `WorldMapScreenIn.value_at()` is a pure function of the tick and the
test pins seek, tick and `value_at` to agree on every frame — otherwise the
picture you approve is not the picture that ships.

**The music is now early by a second.** `WorldMapScene._ready` starts `MUSIC_27`
at full volume at mount, under black. That mismatch was ~27 frames wide and is
now 60. `Fade Sound Shift=0 Time=60` is the measured other half of scenario 12's
exit and `MusicPlayer` already has the primitive (`start_master_fade` ramps from
the *current* master volume, so a fade-in needs a snap to 0 first, and `{60}`
Time converts as `ticks = Time * 4` — 240 sequencer ticks, not 60). Deliberately
out of scope here; this ADR does not decide it.

**Amendment (2026-08-26, #612):** the `MENU=` / `SHOT=` / `FIXTURE=` / `ZOOM=` environment rig this ADR originally named is now `--` user args (the body above is converted) — `-- --menu=screenin --shot=/tmp/x.png`. The env spelling does not error, it is ignored, so following the text above verbatim yields a default capture and no warning. See ADR-0051 dec. 5.
