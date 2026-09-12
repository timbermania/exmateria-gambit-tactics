# A guessed constant expired to a static scan, not to the capture rig its own ADR named

The world map's fade is `FUN_80069400(kind, len)` in `WLDCORE`, and `len` is a **frame
count** passed as a literal at every call site. It is **16** at twenty of the twenty-two
readable sites, **32** at exactly one, and **16** at the world map's own entry. ADR-0161
shipped **60**, stepping **2**, `255 -> 0` linear, and said only a per-vsync capture could
settle it. A twenty-line scan of `WLDCORE.BIN` settled it instead.

Status: accepted (2026-08-25) — grilled with the user. **Supersedes
`0161-the-world-map-raises-itself-and-its-screen-in-mirrors-the-scene-out-until-someone-measures-it.md`
§2, and refutes the constants §3 and §4 shipped.** Adds **Host cue** to `CONTEXT.md`.
Neighbours ADR-0172 (whose own guessed 30 is a DIFFERENT mechanism and is untouched here).

## Context

ADR-0161 §2 held its length open as a standing bet:

> **This decision expires** when §20.5's load recorder is re-run logging, per vsync across
> the load, the four words §24.1 names — `0x800D0AB8` (enable), `0x800D0AC0` (OT slot), and
> the descriptors' rgb at `0x800D0ADC..DE` / `0x800D0AEC..EE`. The rgb sequence *is* the
> ramp.

That is true, and it is also the expensive way. The rgb sequence is *computed* from two
words, and both are literals in the instruction stream.

The reason nobody found them is a **scope** defect in the instrument, not a hard one.
`project-assets/fft-rom/world_disassembly.txt` covers `0x800E0000..0x801CD957` — the
`WORLD.BIN` overlay, and nothing else. Every `WLDCORE` address (`0x80067000`+) is absent
from it, so a grep for the fade in "the world disassembly" returns nothing and reads as
*"the fade is not statically visible."* `WLDCORE.BIN` was sitting in
`project-assets/fft-extract/WORLD/` the whole time, and `mipsdis.py` takes a base argument.
The base is **`0x80067000`**: it decodes `0x80069400` as `addiu sp,sp,-24 / sw s0,16(sp)`,
and it puts §32.4's SCUS-called entry `0x800672F8` at file offset `0x2F8`.

## Decision

### 1. `FUN_80069400(kind, len)` is the arm; `FUN_800694A8` is the tick

```
FUN_80069400(kind, len):                       # 0x80069400
  if ((fade.enable & 2) == (kind & 2)) return  # idempotence guard
  0x8004D950 |= 8                              # the busy latch
  fade.enable  (0x800D0AB8) = kind | 1
  fade.counter (0x800D0AC8) = 0
  fade.length  (0x800D0ACC) = len
  if (kind & 0x20) FUN_80090D50(1,0x11b), FUN_80090D50(3,0x10)   # sound, conditional
  if (kind & 0x10) FUN_80090D50(2,4),     FUN_80090D50(4,2)      # sound, conditional
```

`0x800D0AB8` is the enable word §24.1 already names. The block is a struct: `+0x00` kind,
`+0x10` counter, `+0x14` length. `+0x14` is written **once** in the whole game, here, and
read only through the base pointer — which is why an `imm`-based grep for it finds one
store and no loads.

Bit 1 of `kind` is the **direction**, and the guard at the top means firing the direction
you are already in is a no-op. `FUN_80090D50` is the sound driver and is *conditional on
kind bits* — so §32.3 listing this function under a row labelled "cue" is right, and
reading "cue" as *audio* is what kept it out of the fade's story.

### 2. `len` is a frame count, and the ramp is not linear from 255

`FUN_800694A8` runs per frame. `counter += 1` **every tick** — there is no quantisation —
and the two outputs are computed from `counter/length` with offsets and clamps:

| | modulation `s0` -> `FUN_80106a28` + `0x800AF19C..9E` | descriptor `s1` -> `0x800D0ADC..DE` |
|---|---|---|
| **out** (`kind & 2`) | `0x70 - counter*128/len`, floor 0 | `counter*256/len + 32`, ceil 0xFF |
| **in** (`!(kind & 2)`) | `counter*128/len + 16`, ceil 0x80 | `0xC0 - counter*256/len`, floor 0 |

The latch (bit 3 of `0x8004D950`) clears on the tick where `counter + 1 == length`, and the
enable bits clear the tick after. So a caller that fires the cue and blocks on bit 3 is
waiting exactly `length` frames.

At `len = 16`, a fade **in** therefore starts its descriptor at **192**, not 255, and
saturates at 0 on frame **12 of 16** — it is over four frames before the wait is.

### 3. The three constants ADR-0161 shipped are all refuted, and one of its arguments is not

- **`RAMP_TICKS = 60` -> 16.** Read at `0x8006731C`, the fourth statement of §32.4's
  SCUS-called world-map entry `0x800672F8`: `a0 = 0`, `a1 = 0x10`.
- **`STEP_TICKS = 2` -> 1.** The tick increments by one and divides by `length`. The
  2-frame step is a fact about `{3E}`'s worker `FUN_801467dc` — a *scenario* mechanism in a
  different overlay — and ADR-0161 §4 said so, then shipped it anyway.
- **`START_VALUE = 255.0` linear -> `0xC0` with an offset and an early saturation** (§2).

**§4's refusal to share a kernel with `ScenarioColorScreen` is VINDICATED, not refuted.**
Its argument was that the two ramps *"share a measured blend and an assumed curve"* and
that collapsing them would encode the assumption as structure. Measured, the curves are
genuinely different — different step, different endpoints, different clamps. Extracting a
shared kernel would have been wrong, and would now need un-picking.

### 4. The census is the evidence, not the single call site

All 26 call sites were read — 22 in `WLDCORE`, 4 in `WORLD.BIN`. Twenty of the twenty-two
readable lengths are `0x10`. The **one** `0x20` is at `0x800804BC`, and §32.3 independently
records that site as `FUN_80069400(2, 0x20)` — the light scenario transition. A decode that
reproduces a number this document already wrote down, from a function this document never
disassembled, is checked rather than merely plausible.

## Alternatives rejected

- **Amend ADR-0161 in place.** The interesting content is not `60 -> 16`; it is that the
  expiry condition was overspecified into a rig nobody was going to run, while the answer
  was a literal. An amendment buries that where the next guessed constant cannot see it.
- **Run the capture rig anyway to confirm.** It would confirm the *rendered* result, which
  is worth having, but it is not a precondition: the arithmetic is fully determined by two
  words and one function, and the 0x20 agreement already gives an independent check.
- **Extract a shared ramp kernel now that both curves are measured.** Rejected for §4's
  reason, which the measurement strengthens rather than weakens.
- **Treat this as also settling ADR-0172's 30.** It does not. Formation's own screen-in is
  `WORLD.BIN`'s, a different mechanism at a different altitude; this ADR measures the
  **host cue** around it, not the screen's own ramp.

## Consequences

- **`WorldMapScreenIn` is wrong in three constants and one shape**, and its test pins the
  shape rather than the number precisely so this can land without re-basing a golden.
  `WorldMapScreenInTest`'s refusal to assert 60 is what makes the correction cheap — the
  refusal paid.
- **The map's screen-in gets a third shorter**, 60 frames to 16, reversing ADR-0161's
  *"the black gets longer"* consequence. Its stated failure mode was *"it stalls"*; the new
  one is a pop, and `--menu=screenin`'s contact sheet is the instrument for both.
- **The `&2` idempotence guard means the map's entry cue can be a NO-OP.** `FUN_80069400(0,
  0x10)` at `0x8006731C` fades *to* the un-faded state; if the block is already 0 — which
  §24.1 reports is true of **every** capture the repo holds — it returns without arming.
  So the map's own entry does not unconditionally fade itself in, and ADR-0161 §1's *"on
  console the world map fades itself in"* is conditional on who left the block set.
- **An instrument's coverage is part of its answer.** `world_disassembly.txt` is named for
  a disc directory and holds one overlay of it. Any negative result taken with it is
  scoped to `0x800E0000..0x801CD957`, and this ADR exists because a negative result was
  read as a fact about the game.
- **Not verified here:** the writer of the second descriptor pair (`0x800D0AEC..EE`);
  whether the port's single subtractive quad corresponds to descriptor 1 or to the pair;
  and the rendered result of any of it. The arithmetic is static; the picture is not.

## Built

Landed 2026-08-25, same day. Three things the measurement did not settle on its own.

**The contact sheet reproduces the arithmetic frame for frame.** `--menu=screenin` now renders
**all seventeen** frames rather than eleven sampled from sixty — at this length the whole
ramp fits in one sheet, so there is no spacing left to defend. Peak luminance per cell reads
`47, 63, 79, 96, 112, 129, 145, 162, 178, 195, 211, 228, 244` and then **244 four more
times**. Predicted, from `240 - value_at(t)` with the map's own brightest pixel at level 30:
`48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 240`. Within ±4 on every frame, and
the flat tail is the latch overhang made visible — the picture is finished at 12 while a
console host is still blocked to 16.

**The `0xC0` start does NOT hide the mount frame, and that turned out not to matter.** At
tick 0 the brightest pixel on screen is 47 of a settled 244 — 19% — and the mean is 0.8% of
settled. The map IS faintly legible. But what shows is a *coherent* map, not a half-built
frame, so the job ADR-0161 §1 handed this quad (cover the mount, because the navigator's
`_fade_rect` provably cannot) is satisfied by accident: there is nothing ugly to cover. The
two alternatives drafted for this — hold 255 for one frame, or keep 255 outright — would
each have invented a constant to solve a problem the picture says does not exist.

**`STEP_TICKS` is GONE rather than set to 1.** Once `value_at` stopped quantising, the
constant drove nothing and only the test referred to it. A constant equal to 1 is not a step
size, it is an invitation to reintroduce one — and `FormationScreenIn` keeps its own
`STEP_TICKS` because that ramp genuinely quantises, so the asymmetry between the two files
is now the measurement rather than an oversight.

**A grader read the wrong pixels twice before any of the above was true.** `magick <sheet>
-crop WxH+X+Y +repage -format "%[fx:mean]" info:` reported mean 127.9 / max 255 for a region
whose real values are 0.8 / 47 — the `fx:` evaluation was not seeing the crop, and it varied
per cell just enough to look like data. It produced a smooth-looking table that would have
been reported as confirmation. Cropping to a FILE and reading raw `gray:-` bytes is the
grader that agrees with the picture. The check on the check was that cells 3-6 looked like a
smooth ramp while the numbers claimed a discontinuity between 4 and 5.

Green after: `WorldMapScreenInTest` 30/30 (each of the three constants seeded red
separately — 24/31, 26/31 and 30/31 against the pre-change values), `FormationScreenInTest`,
`ScenarioColorScreenTest`, `ScenarioSettleScreenEffectsTest`,
`NavigatorWorldMapArrivalTest` 16/16, `NavigatorWorldMapPressPrecedenceTest` 36/36,
`NavigatorWorldMapFormationRenderTest` 12/12. `check_root_set`,
`check_adr_classification`, `check_baseline`, `check_path_extends` all OK;
`check_adr_quotes` still red at its pre-existing 44 spans, none of them from this work.

**Amendment (2026-08-26, #612):** the `MENU=` / `SHOT=` / `FIXTURE=` / `ZOOM=` environment rig this ADR originally named is now `--` user args (the body above is converted) — `-- --menu=screenin --shot=/tmp/x.png`. The env spelling does not error, it is ignored, so following the text above verbatim yields a default capture and no warning. See ADR-0051 dec. 5.
