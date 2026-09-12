# A screen-in belongs to the screen's own system, so Formation's is UI's

The Formation screen raises **itself** under an **abr 2** subtractive quad over **30
vsyncs**, stepping every **2**, on its own vsync clock. The ramp is `UI`'s — not
`Render`'s, not `Battlefield`'s, not `Cutscene`'s — and the length is borrowed from
`WorldMapTownPage`'s **measured** `world_menu_open_curve` span, not from the world map's
own guess. Nothing has observed how `WORLD.BIN`'s Formation screen comes up.

Status: accepted (2026-08-25) — grilled with the user. **BUILT 2026-08-25.** Owned by
`src/ui3/formation/FormationScreenIn.gd`, armed by
`FormationDetailTransition.begin_screen_in()`. Guarded by
`tests/FormationScreenInTest.gd` (17 assertions, three arms seeded red) and by
`NavigatorWorldMapFormationRenderTest`'s route arm. Neighbours ADR-0161 (the world map's
screen-in), ADR-0162 (the overlay-quad hazard), ADR-0181 (the mount that exposed the pop)
and ADR-0129/0147 (why this is not `Render`'s). Adds **Screen-in ownership** to
`CONTEXT.md`.

## Context

With ADR-0181's mount landed and ADR-0162's `{3E}` quad freed, Formation **pops** in from
the world map. The standing suggestion was to promote `src/world_map/WorldMapScreenIn.gd`
into a generic screen-in. Two things had to be settled before writing a line, and the
refactor answered one of them better than the RE did.

**There is no measurement, anywhere.** `WORLD_MAP_SCREEN.md` §33.7 records only that
Formation is an ordinary blocking call into `WORLD.BIN`. `FORMATION_SCREEN.md` does have
a measured "fade ramp" at `0x8018C88C` = `{20,35,50,65,80,90,100,128}` — but that is the
selection box's **8-slot cursor trail**, a per-slot grey multiply on the gouraud colour.
It is easy to mistake for the answer and it is not one.

**And the world map's constant is a guess with a real thing behind it that Formation does
not have.** ADR-0161's 60 mirrors scenario 12's `{3E} Time 60`, which IS measured — two
sides of one hand-off. Formation's neighbour is that guess. Copying it would make
constant #2 justified by constant #1 and nothing else.

## Decision

### 1. A screen-in belongs to the screen's own system; `UI` owns Formation's

`CONTEXT.md` already states the pair, and the statement is an ownership rule nobody had
applied to the refactor: *a scene-out is authored per-scenario in the **chunk**, so it
varies beat by beat; a screen-in is **unconditional** and belongs to the screen's own
code.* A scene-out is therefore an event-script instruction — and the classifier agrees,
booking `ScenarioColorScreen.gd` and all four `screen_color_mode*.gdshader` as
`Cutscene`. A screen-in is the screen's, and both `FormationScene.gd` and
`FormationDetailTransition.gd` classify `UI`, whose very first charter row is *"the
toolkit — windows, panels, fonts, lists, focus movement, **the open and close cadence**."*

Three ramps, three owners, and that is correct rather than a smell: the scenario's way out
is `Cutscene`'s and measured; the world map's way up belongs to whatever system the
overworld lands in and is guessed; Formation's way up is `UI`'s and is this file.

### 2. Not `Render`, and the reason is measured

ADR-0129 puts the **fold bracket** in `Render` and keeps a producer's shader with the
producer. ADR-0147 then counted it: of the sixteen shaders declaring `compositor_layer`,
`UI` has 7, `Battlefield` 4, `Effects` 4, `Sprite Rig` 1, and **`Render` 0** — *"the
system that owns the bracket is not a producer into it."* A screen fade is a drawable
somebody submits into the fold, so it could never be `Render`'s. `Battlefield` owns the
place, and a fade is not part of the place.

### 3. Not a `UI3Beat` — ADR-0161 §5 stands, on narrower grounds than it claims

A beat declares a forward **and** a reverse driver, and ADR-0084's boot audit refuses to
start without one. A screen-in has no reverse: how the Formation screen LEAVES is
undecided, exactly as ADR-0161 §6 holds the world map's exit open on `transition_mode`.
§5's stated reasons were *"no element, no recipe and no reversal"*; on the `ROSTER` host
the coordinator **is** a UI3 screen root, so "no element" is weaker here than it was
there — but extent and reversibility carry the decision on their own, and `UI` owning the
file does not make it a beat.

### 4. It reuses the quad, restates the arithmetic

`FormationScreenIn extends ScenarioScreenOverlay` — the base class that owns the one
fiddly recipe: a full-screen NDC quad whose vertex shader rewrites the corners out of the
mesh's local AABB, so it needs an oversized `custom_aabb` or Godot's culler silently drops
it. Its own docstring says that recipe *"was copy-pasted across all four effects"* before
it existed; writing a fifth copy is the thing it exists to prevent. Its shader is
`screen_color_mode2.gdshader` — `shader_type spatial`, `blend_sub`.

That is the split ADR-0161 §4 asks for, and this file lands on the same side of it: the
**arithmetic** stays local (`RAMP_TICKS`, `STEP_TICKS`, `START_VALUE`), the **quad and the
blend** are shared, because those are one question asked twice. The base class already
draws that line itself — *"timing, shaders, blend modes and barrier semantics stay in the
subclass."*

The family classified `Cutscene`, so extending it booked a **`UI -> Cutscene` crossing** —
openly, rather than by copying eight lines to avoid it. A crossing the instrument can see
beats a copy it cannot, and this one immediately paid: it is what made the base class's
misfiling visible. **The base is now `platform`** — `src/core/ScreenOverlayQuad.gd`, moved
in this ADR's second commit. Its whole reason to exist is a **Godot** fact (an NDC-rewritten
quad falls outside its own AABB and the culler drops it), which is `platform`'s bucket by
ADR-0147's own precedent: `psx_par` and `psx_dither` went there as *"a fact six buckets
`#include` cannot live inside the first system to extract"*. It sat in `Cutscene` only
because the VM happened to be its first caller — and `Cutscene`'s charter is that it *"owns
no mechanism of its own"*, so hosting a base class other systems extend was never right.
`UI` and `Cutscene` now both reach `platform`, and neither reaches the other.

**No 5-bit quantisation.** `WorldMapScreenIn` bakes to whole 5-bit levels because the world
map composites in the GPU's own 5-bit channels and expands once at end of frame
(`psx_expand_555.gdshader`, a `BackBufferCopy`). Formation has no such pass —
`psx_expand_555` is referenced only under `src/world_map/`. That, plus `canvas_item` vs
`spatial`, is why "promote `WorldMapScreenIn`" was a **rewrite wearing a shared name**
rather than a reuse.

### 5. 30 vsyncs, 2-frame step, and the file says what that is

`RAMP_TICKS = 30` is `WorldMapTownPage.OPEN_VSYNCS` — `world_menu_open_curve @0x801533B8`
(§38.7), a 21-vsync hold plus a 9-entry curve read one index per vsync, **measured**, for a
`WORLD.BIN`-era window coming up. It animates panel geometry rather than brightness, so
the length is an analogy — but an analogy to a measurement, in the right category. The
world map's 60 was the alternative and mirrors a scenario *transition*.

`STEP_TICKS = 2` is the quantisation three independent console tables agree on: `{3E}`'s
worker `FUN_801467dc`, `world_menu_open_curve`'s doubled entries, and (mirrored) the world
map's screen-in.

**This decision expires** when `WORLD.BIN`'s Formation overlay is captured across the
world-map hand-off and its fade descriptors logged per vsync. The overlay is already
mapped — `FORMATION_SCREEN.md` live-dumped its const block at `0x8018C884` — so this is a
**cheaper** measurement than ADR-0161's, not a harder one. Two integers change and nothing
else does.

### 6. Gated to `Host.ROSTER`, and armed by the host rather than by `_ready`

ADR-0181's rule carries: `Host.ROSTER` is a screen with a lifetime and gets both the ramp
and the hand-back; `Host.MAP` is a persistent overlay on somebody else's battlefield and
gets neither — a full-screen subtractive quad there would black out the battle it is
mounted over.

The ramp **starts settled** and is opt-in through `begin_screen_in()`, which is the call
ADR-0161 already made one level down: `WorldMapTownPage._open_frame` begins at
`OPEN_VSYNCS` on purpose because *"a page that animated by default would make every one of
those assertions read a frame nobody asked it about."* That is a trigger, not an ownership
change — the ramp is still the screen's, on the screen's own clock, under the screen's own
quad, which is ADR-0161 §1's point (*"a screen that covers itself cannot have that bug"*).

## Alternatives rejected

- **Promote `WorldMapScreenIn` into a generic screen-in.** Not a reuse: `canvas_item` vs
  `spatial`, a 5-bit bake that only the world map's compositing justifies, and a guessed
  constant that sharing would encode as structure — ADR-0161 §4's exact refusal.
- **A beat in the coordinator's recipe.** Needs ADR-0161 §5 superseded and a reversal
  invented for a ramp nobody has measured forward.
- **Measure it first and ship the pop.** The measurement is filed; the pop is a real
  quality problem and ADR-0161 set the precedent that a labelled guess beats an unlabelled
  tween.
- **Don't fade at all.** Honest, free, and it looks bad.

## Consequences

- **The quad is FREED when the ramp lands, not zeroed.** ADR-0162: an NDC overlay quad
  *"fills the screen of any camera that renders it, from anywhere, at any zoom, over
  everything"* — a standing quad at value 0 is invisible only until the next camera enters
  this `World3D`, and a `{3E}` quad outliving its scene is exactly what rendered Formation
  black on this route twice. Landing is the end of the object's life.
- **The ramp gates input by SWALLOWING, not by returning.** `CONTEXT.md` defines a
  screen-in as running "before it accepts input". A bare `return` in the coordinator's
  `_input` leaves the event unhandled, so it falls through to the roster grid's
  `_unhandled_input` — which is where ○ on the plain roster actually opens a Status
  screen. Mouse and F3 stay exempt, per `_claim_pad`'s reasoning.
- **The exit is deliberately not decided**, mirroring ADR-0161 §6. Formation goes soft-in /
  hard-out, and closing that is a separate question with its own RE.
- **The test pins the ramp as a SHAPE, never as truth** — starts covering, steps every 2,
  lands exactly *on* `RAMP_TICKS`, `seek`/`advance`/`value_at` agree, counted in vsyncs
  not display frames. It does not assert that 30 is right, the same refusal
  `WorldMapScreenInTest` makes about 60. A test that pinned the number would entrench the
  guess.

## Built

Landed 2026-08-25. Three things the design did not know.

**1. A gate that ignores is not a gate.** Written first as `if screen_in_active(): return`,
and `FormationScreenInTest` arm D passed — because the arm drove `host._input(...)`
directly. Pushed through the viewport instead, the press travelled the route a real key
travels, fell through to `FormationScene._unhandled_input`, and opened the Status screen
behind a fully black ramp. Ignoring an event and consuming it are different verbs, and a
test that calls the callback instead of pressing the key cannot tell them apart.

**2. A ramp that runs by default makes every existing assertion read a frame nobody asked
about.** Built into `_ready` and measured, three of the first five formation tests went red
— a 30-vsync input gate is invisible to a test that waits 4 frames and then presses a key.
`WorldMapTownPage` had already paid for this lesson and written it down; `begin_screen_in`
is `begin_open` under another name.

**3. Nothing proved the ramp was ARMED on the player's route until an arm was added that
could see it.** `FormationScreenInTest` proves the ramp in isolation, and a screen-in that
never fires is invisible to every other assertion — the settled frame is identical either
way. `NavigatorWorldMapFormationRenderTest` now samples 6 frames into the mount and again
at rest: **13.6% lit -> 89.1% lit**, and with `begin_screen_in()` removed from the route it
reads **89.1% -> 89.1%** and fails. A direction check, not a pinned value, for the reason
decision 5 gives.

**4. The crossing found the misfiling within the hour, and the term did NOT move with the
class.** `ScenarioScreenOverlay` became `ScreenOverlayQuad` under `src/core/`, booked
`platform`; `Cutscene` drops 45 lines and `platform` gains them, its five subclasses and one
test rename with it. But `CONTEXT.md`'s **Scenario screen overlay** stays exactly what it
was, because its defining clause is not the quad — it is *"its lifetime is the VM's… freeing
the VM frees the family."* `FormationScreenIn` shares the mechanism and frees ITSELF the
vsync its ramp lands, so it is not one. One mechanism, two families; the class is named for
the mechanism and the term keeps the family. Green after the move:
`ScreenOverlayQuadTest`, all five scenario overlay tests, `FormationScreenIn` 17/17,
`NavigatorWorldMapFormationRender` 12/12, and `check_baseline` still balanced at 1,143
cross-system reaches.
