# The blueprint

The game-agnostic tactics-RPG domain model — what the systems are and where each
boundary falls (ADRs [0115](../adr/0115-a-system-is-a-bundle-that-ships.md)
–[0120](../adr/0120-battle-state-has-one-write-path.md); the working map with
diagrams is [`docs/BLUEPRINT.md`](../BLUEPRINT.md)). Distinct from
[Refactor projection](36-refactor-projection.md), which is the vocabulary of *how the
refactor is run*; this is the vocabulary of *what is being built*.

#### The eleven systems

**Battlefield**:
The place, how you see it, and how you point at it — `Lattice`, `Environment`,
`Camera`, `Cursor`. _Avoid_: map (that is content, and it is two things — a
lattice and its dressing), terrain (that is `Environment` alone).

**Battle**:
Simulate a tactical battle and show it. Holds `Combatant`, `Scheduling`,
`Action Resolution`, `Agency`, `Performance`, `Body`, the `roster`, and
`Deployment`. The presentation is inside it because nobody would use the
presentation without the simulation. _Avoid_: combat (fine informally),
battle presentation (it is not a separate thing).

**Character Catalogue**:
What you have — the durable slug-keyed `Character` record every unit is, plus
`Holdings`, the party's money and item pool. The master identity layer above the
battle roster (ADR-0066). _Avoid_: roster (that is a per-side *selection*, and it
lives in `Battle`), party.

**Sprite Rig**:
Posing a composite character — templates, shapes, sequences, draw order,
attachment points. **It does not know what a combatant is.** _Avoid_: sprites
(sounds like assets; this is machinery), animation.

**Effects**:
The effect timeline player — a multi-channel script over time, its particle
simulation, and the **channel vocabulary** every consumer implements. Depends on
nothing. _Avoid_: VFX, effect system (the vault's ROM-shaped cluster). ⚠️ *"Depends on nothing"* is **measured false** (arm 1 = 67, arm 2 = 72, arm 5 = 63, arm 7 = 3) and is kept unrewritten with its falsifier; that record and this entry's two other claims — one confirmed, one true-in-behaviour — are in [`docs/BLUEPRINT.md`](../BLUEPRINT.md) → `Effects`, ADR-0288 dec. 3 / ADR-0290 dec. 9 under ADR-0126 check 2. The three parts named above are **exactly** extraction #7's 67-file membership.

**UI**:
The toolkit — windows, panels, fonts, lists, focus movement, open and close
cadence — plus preview + commit. The individual screens are content. _Avoid_:
screens (that names the content, not the system), HUD, menus.

**Audio**:
Cues to sound. Ships today as `exmateria_sound`. _Avoid_: SFX (that is one half),
sound.

**Cutscene**:
The script player — an interpreter over an ordered program, and staging: placing
and moving bodies, framing the camera, showing text. **It has no private door.**
_Avoid_: event (ADR-0029 reserves it twice), scenario (that is a *record*),
story scene (`scene` is the most overloaded word in a Godot project).

**Campaign**:
The spine — which mode is active, the transitions between them, story position,
world flags, what is unlocked. **The catalogue owns what you have; the spine
owns where you are.** _Avoid_: world map (that is a screen over this), game
state, flow.

**Render**:
The retro look — the compositor, the depth model, colour modes, shader
templating, the fold, display aspect. Genre-orthogonal: about looking like a
PlayStation, not about tactics. Deliberately broad, as `Audio` and `UI` are —
**the blueprint names the role; the shipped addon gets its own name.** _Avoid_:
PSX Render (two words), compositor (that is one part).

**Debug**:
The panel host — full-screen panels in their own window, field widgets, the
override layer, and the walk that discovers what loaded systems declare. Systems
declare their tunables; `Debug` renders them and neither knows the other
(ADR-0113). Genre-neutral and still a system: you would install it, not write it. _Avoid_:
debug panel (that is one, and per-system panels ship with their system),
DebugConfig (the ambient autoload this replaces).

> **Sharpened by [ADR-0140](../adr/0140-debug-is-a-system-and-a-system-logs-itself.md)
> (2026-08-21).** The heading above said *"ten"* and listed eleven — the same
> constant-count-over-a-changed-list bug ADR-0139 dec. 14 found in the schema
> list; corrected. This entry was already right and already load-bearing: *"per-
> system panels ship with their system"* and *"the ambient autoload this
> replaces"* are ADR-0140 dec. 2's answer, written before the question was asked.
> `classify_blueprint.py` could not execute it — a stale `"DebugPanel"` entry in
> `DEBUG_HOST` matched as a substring and held 30 per-system panels inside
> `Debug`, so it read **45 files / 6,911 lines** against a true **15 / 2,884**.
> Corrected, `Debug`'s outbound edges into systems are **0** — a pure sink, so it
> may extract at any point in the order. **There is no inter-system logging**: a
> system declares and prints its own diagnostics through its own `static var`
> (ADR-0068), its panel reads that flag as a view, and `GameLogger` is deleted
> rather than promoted (dec. 5).

#### Structural vocabulary

**Assembler**:
A composition over systems that implements the [ports](37-the-blueprint.md) and wires
them together. **The game is one; each authoring tool is another** — the Effect
Studio is a second assembler, not a system and not host code. Each assembler is
a [root set](36-refactor-projection.md), which is why ADR-0112 declares two. It wires
once and leaves; it is not in the per-frame loop (ADR-0127). **One file, and
`O(10^3)` lines** — a *directory* in the assembler list is a defect, because
assembler is the one category that never becomes a system, so whatever is parked
there is permanently exempt from extraction (ADR-0134 dec. 2). The Effect
Studio's assembler is `EffectViewerScene.gd` alone; the 21,986 lines of
`src/effects/studio/` are `Effects`. **And nothing calls it** — the root-set
criterion applied to the script instead of the scene: a root scene is one
nothing instances, and its assembler is the script nothing calls, which is what
makes the pairing machine-checkable (ADR-0135 dec. 8). A file with many callers
is a shared library, however much wiring it does; `CompositorAutopilot.gd` is
the one recorded exception, and it dissolves when ADR-0129's split lands.
_Avoid_:
host (that is one particular assembler), app, composition root, coordinator
(implies it stays in the loop, which would make it the god object every crossing
routes through).

**Crossing**:
What passes between two systems, named only when it states all three of
**payload**, **owner after**, and the single **handoff edge**. Two of three is
the dangerous state, not zero — ADR-0020 named a payload alone and the
double-pump stood for months. _Avoid_: interface (that is the whole surface),
boundary (say seam), contract.

**Binding**:
How a consumer reaches a [publish](37-the-blueprint.md) — the one thing ADR-0118
dec. 3's *does the caller need an answer?* does not settle. **Assembler-wired**
when the consumer set must stay open (the producer must not know who listens):
the producer emits, the assembler wires the sink, neither names the other — the
effect channels, the effect log. **Direct**, by name, when the set is closed and
what it reaches is a stable published surface — `Fold.add`, `DepthMode`,
`#include pixel_aspect`, `ColorRecipe`. Direct is the *default*: an assembler is
machinery you add for an open sink set, and adding it to a closed one costs a
wiring step and buys nothing. **A publish describes the payload's ownership, not
its delivery mechanism** — reading "publish" as "assembler-wired" is what made
ADR-0200 dec. 8 coin `Leaf`, retired by ADR-0138. _Avoid_: leaf (retired — it
named a property of the housing system to license a property of the thing
named), coupling, wiring (that is the assembler's whole job).

**Schema**:
A published payload that crosses a boundary, depended on by consumers instead of
the producer. **Eight**: the compositing key, the **colour model**
(`ColorStack` / `ColorRecipe` — 16 cross-system edges, more than any other, and
missing from both ADR-0118 dec. 1 and this list until ADR-0138 dec. 6), the
effect channels, the effect log, pose requests, character records, and **tunable
declarations** (every system → `Debug`, ADR-0113 — on ADR-0118 dec. 1's table
and dropped from this list until ADR-0139 dec. 14, which is why the count read
"six" while the colour model was called *the sixth*; it is the **seventh**), and
the **terrain cell** (`Battlefield` -> `Battle` / `Cutscene` / `Effects`, ADR-0164
dec. 2 — the **eighth**, declared at extraction #3 pass 5, written at pass 6).
The list is the [shared kernel](37-the-blueprint.md)'s **admission test**, not just an
inventory. A schema is named for what it *is*, never for how a consumer reaches
it — see [binding](37-the-blueprint.md). Two — pose requests and character records —
were declared publishes with no consumer-set test and are recorded as untested
(ADR-0138 dec. 9). Only **two have code members today**, both already in the
kernel — the terrain cell becomes the **third** when pass 6 writes `TerrainCell`
(ADR-0164 dec. 2); **tunable declarations has none by construction**, being
realised by a port's signature (`Tune.bind`) rather than by a type (ADR-0139 dec. 11-12).
_Avoid_: message, event type, DTO; counting the schemas from this list alone
(ADR-0118 dec. 1's table is the register).

**Shared kernel**:
The one addon every system may depend on — **`addons/exmateria_schema/`**,
**BUILT 2026-08-21** in the prologue pass immediately after the baseline and
before any extraction (ADR-0121 dec. 5, ADR-0139 dec. 8-9, ADR-0146). Six source
members, **1,086 lines** — `Fold.gd`, `DepthMode.gd`, `ColorStack.gd`,
`ColorRecipe.gd`, and the two `.gdshaderinc` **GPU halves** of the last three,
`ot_depth` and `color_stack`, which move with their `.gd` halves because
a codec split across two addons drifts invisibly (ADR-0139 dec. 7) — **plus
`fold_layer.tres`**, the resource half ADR-0139's source table did not count and
`asset_census.py` had already booked `schema` (ADR-0146 dec. 1). Laid out **one
directory per schema**, `compositing_key/` and `colour_model/`, so the admission
list is `ls` and a new schema is visible in a diff as a new directory. The
`plugin.cfg`/`plugin.gd` scaffolding realises no schema, so it is **not** a
member and the classifier books it out of the `schema` bucket. A file enters **only by
realising a named [schema](37-the-blueprint.md)**, so adding a member means adding a
schema first: an ADR act, which is what stops a shared kernel becoming a junk
drawer. Two mechanical vetoes back it, both readable from
`tools/.touch_cache.json`: **zero outbound edges** into any system (measured: 0
— `Character.gd` fails with 3, which is why character records has no member),
and **never an autoload** (an ambient global you ask for an answer is a
[port](37-the-blueprint.md), which is how `Tune` at 42 edges and `DebugConfig` at 55
stay out). A member **may compute** — exactly what both sides must compute
identically, and nothing that decides *which* or *when*. _Avoid_: ranking by
reach (`Debug` 88 and `platform` 50 both outrank the kernel's 45); "shared
library", "common", "core" (`src/core/` is the residual category this replaces —
only 3 of its 10 files are members).

**Port**:
A service a system waits on and declares as a required interface, implemented by
whoever assembles the game. Four: **clock**, **focus**, **lattice**, and
**fold capability** — *can I fold?*, a build fact 4 systems branch on and
today reach by hardcoded autoload name (ADR-0129 dec. 8). The test against a
[schema](37-the-blueprint.md) is whether the caller needs an answer back, and a
**static** answer is still an answer: a capability queried once at startup is a
port, not a publish. _Avoid_: dependency, adapter (that is the implementation),
service.

**Membership interface**:
What `Render` publishes so a drawable can join the [fold](26-display-space-fold.md):
declare `render_mode … compositor_layer`, and join through **`Fold.add`** — the
sole sanctioned entry, which defaults the layer because there is exactly one.
A producer never names `FOLD_LAYER` itself — including the batch producer, which
built its own carriers and self-stamped until ADR-0200 dec. 1 collapsed it onto
the same call, so there is now **one** way in and no batch payload. Distinct from the
[shader library](37-the-blueprint.md): membership says *you are in the pass*, the
library says *how you shade* (ADR-0129 dec. 4, dec. 7). _Avoid_: calling it the
compositing key (that named four fields, two of which are library entries);
setting `render_layer` by hand.

**Shader library**:
The generic `.gdshaderinc` set `Render` publishes and producers `#include` while
keeping their **own** shaders — **three** since ADR-0139 dec. 7 split it:
`par`, `screen_blend`, `dither`. `ot_depth` and `color_stack` left for the
[shared kernel](37-the-blueprint.md): they are the GPU halves of `DepthMode` and
`ColorStack`, one encoding in two languages, while the three that remain have no
CPU counterpart and are shared *implementation* rather than a crossing. **That
distinction is the admission test, sharpened by ADR-0146 dec. 3**: a kernel
shader member is half of a **codec**, an encoding implemented twice — once per
language — that must agree byte for byte. `pixel_aspect` and `psx_dither` are
implemented **once**, in GLSL; their CPU side is a single
`global_shader_parameter_set` through a port (`PSXDisplay._apply_par`,
`DebugConfig._apply_dither`). A **writer is not a counterpart**, so there is
nothing for two sides to disagree about and nothing to publish. `pixel_aspect` being
`#include`d by 16 shaders across six buckets does not change that — reach is not
the test (ADR-0139 dec. 2). All three are bucketed `platform`, not `Render`,
which corrects ADR-0139 dec. 7's *"stay `Render`'s"*: a display fact six buckets
include cannot sit inside the first system to extract. Counts,
`.gdshader` entry points with `tests/` excluded (2026-08-21): `par` **11**,
`screen_blend` **4**, `dither` **1**; the departed `ot_depth` **16** and
`color_stack` **3**. It is the *shader templating* Part, and
it is what makes ADR-0074's *"material contract, not a module"* buildable: the
producer's shader carries the rest of the contract, which is why `Fold.add` is 33
lines. Tier 2 — `effect_particle_stp`, `unit_sprite_body`, `tile_overlay` — is
**not** in it and leaves with its own system. _Avoid_: the `psx_` prefix (inside
`Render` everything is PSX; the marker is the extraction path); "the shaders are
Render's" (`assets/shaders/` splits by system).

**Content shadow**:
The FFT-specific data a system leaves behind in the host when it extracts —
sprite data, map files, ability tables, event scripts, sound banks, the actual
screens. ADR-0110's *"the host converges on the FFT content pack"*, stated per
system. _Avoid_: assets (too narrow), leftovers.

**Content schema**:
What crosses the content-pack boundary — the format a departing system declares
and the host's content tree fills in
([ADR-0132](../adr/0132-assets-are-filed-by-consuming-system-not-by-provenance.md)).
A [content shadow] is what stays; the content schema is how the system that left
still asks for it. Addressed in **system vocabulary**, never ROM vocabulary: the
built precedent is `exmateria_sound`'s `runtime/asset_paths.gd`, which carries
zero content and gets the mechanism right, then asks for
`SOUND/MUSIC_%02d.SMD` — the disc directory and the ROM filename — which is the
half to fix. A second schema family beside ADR-0121 dec. 5's six published
*payload* schemas, and like them it has no owner and no place in the extraction
order. _Avoid_: asset format (that is one class's encoding, not the boundary),
manifest.

**The three asset places**:
An asset store is segregated by **the system that owns the format**, never by
whether it was extracted or authored (ADR-0132 dec. 1 as amended by
[ADR-0142](../adr/0142-an-asset-belongs-to-the-system-that-owns-its-format.md)
dec. 1 — the axis is unchanged, the test is no longer readership). Provenance
decides gitignore and nothing else — `MUSIC_00.SMD` is extracted and belongs on
the system side, because it is `Audio`'s format. So: the **extract** is ROM-shaped, gitignored and
**input only — nobody's read surface**; the **content tree** is segregated by
system and *is* the read surface; the **workspace** lives outside the project
and is where an authoring tool saves *and loads*. Getting an authored asset into
the game is an explicit placement into the content tree, not a side effect of
Save. _Avoid_: an `authored/` tree beside `extracted/` (the distinction that
looks right and is not — it is how `authored_effects/` ended up with 11 writers
and no reader), assets dir (says which folder, not which of the three jobs).

**Format owner**:
The system an asset belongs to: the one whose code would have to change if the
asset's **encoding** changed
([ADR-0142](../adr/0142-an-asset-belongs-to-the-system-that-owns-its-format.md)
dec. 1). Not the system that calls `load()` — a reader that is not the format
owner is a [crossing](37-the-blueprint.md), and counting readers files the
unit portrait under `UI` against ADR-0132's own worked example. The rule reaches
both directions: `UI` reads `Sprite Rig`'s portrait pixels, and `Effects` reads
`Audio`'s `feds.bin`. It also has an answer where readership has none — the
**27,513,574 bytes** across the three measured packet classes that no code opens
at all still have an owner. _Avoid_: consuming system (that is the store-level
axis, and at file level it is the test this replaces), producer (the parser that
writes it is not a system), provenance.

**Asset packet**:
A derived folder per key — one per character, per effect, per map (ADR-0072
dec. 3, upheld by
[ADR-0142](../adr/0142-an-asset-belongs-to-the-system-that-owns-its-format.md)
dec. 3). It stays **entity-shaped and flat**: a system-named subdirectory
appears only where two [format owners](37-the-blueprint.md) genuinely share
one packet, which across the three measured classes is `effects/E###/` alone.
A `sprite_rig/` folder inside a packet that is entirely `Sprite Rig`'s is
redundant and is not written; the class declares its default owner in its
[content schema](37-the-blueprint.md) and in `BLUEPRINT.md`'s packet table
instead. _Avoid_: template (ADR-0072's word, and it also names the `job×gender`
key), bundle, per-entity folder (says the shape, not that it is the read
surface).

**Capability**:
An unforgeable handle whose possession *is* authority, minted for a contested
resource with exactly one holder. Four: **the pump**, the **camera** claim,
**focus**, the **cell** claim. A flag prevents the bad state; a capability makes
it unrepresentable. _Avoid_: permission, token, lock.

**Focus**:
The right to receive device input, held by exactly one consumer **per channel**.
A selector switch, not a router (no table, no inspection) and not a mask (a mask
can have two bits set, and that is the bug). Channels — `game`, `debug` — are
parallel, which is how F3 opens the overlay while a modal is up. _Avoid_: input
(true of everything), focus mode (that is Godot's `Control` focus, the same idea
at a smaller scope).

**Landmark**:
A named moment in a performance — *impact*, *cast*, *recoil* — that body, effects,
audio and camera each schedule against, never against each other. One of
`Effects`' **lanes**, carrying opaque codes resolved through a per-effect event
table (ADR-0123). Its events are `reaction` (a **span**) and `hit` (a
**trigger**), so "moments rather than instructions" is right about *addressing*
and wrong about *extent*. _Avoid_: keyframe, cue point, `refresh_tile` (a ROM
name describing neither cause nor effect — say `reaction.end`). **"Trigger" is
no longer an avoid**: it now names an event with no extent, and a landmark lane
carries one.

#### Lanes and events (ADR-0122)

**Lane** (blueprint):
A track of events that do not overlap. Two verbs that can be active at the same
time belong in different lanes — which is what fixes the lane count, not the file
layout. `Effects` publishes a fixed list of them; `landmark` is the one
open-ended door. _Avoid_: channel (the ROM's storage word, and `camera` and
`palette` each store several lanes in one), track (means a FEDS opcode track).

**Span** / **Trigger**:
An event's **extent**. A span has a start and an end; a trigger is a moment. The
event declares it, never the lane — a lane may carry both. An event with extent
that does not say so forces every consumer to invent its own ending, which is
what `reaction` cost before it was named. _Avoid_: keyframe (a storage slot, not
an event), duration.

**Typed** / **Opaque**:
An event's **payload kind**, independent of extent. A *typed* payload is
subject-shaped — pitch/yaw/roll, RGB — and `Effects` knows its vocabulary. An
*opaque* payload is a code whose meaning lives entirely in the subscriber. **Both
kinds publish** — ADR-0127 dec. 1 applies the ADR-0118 dec. 3 test and finds no
lane needs an answer, superseding the earlier reading that only the opaque lanes
(`sound`, `landmark`) were genuinely pub/sub while typed ones took *"the cheapest
legal shape"*. Typed vs opaque decides who knows the vocabulary, not how it
travels. _Avoid_: generic, untyped.

**Colour op**:
The unit of a colour crossing — `{scale, bias, duration, mode_token}`: multiply,
add, ramped over frames, plus one integer the wire does not interpret
(ADR-0128). It is what unifies `screen`'s `Color` deltas with `palette`'s
`ColorStack`; a folded colour is the scale=1 case, which
`MapTintOverlay.update_layer` already builds. The recipe is published, never the
folded result — several casts tint one surface and colour ops do not commute, so
the **surface owner** folds them in order. _Avoid_: tint (that is the outcome),
ColorStack (that is `Render`'s fold machinery, not the payload).

**Event table**:
The per-effect map from an opaque code to a named event. `sound` has had one
since the ROM (`SoundContainer`); `landmark` gains one. It is what lets the lane
list stay fixed — a new named event is a table row, not a schema change.
_Avoid_: registry, enum.

**Carrier**:
A keyframe written only to give an event a slot on a borrowed time grid —
`emitter_id = 0` plus the landmark bits. The ROM already writes them (937 of 946
landmark keyframes), so manufacturing one on export transcribes an existing
idiom rather than inventing an encoding. _Avoid_: spacer, rest (both are FEDS
sound-lane words with their own meanings).

**Port**:
A required interface a system declares and the assembler satisfies — the clock
port, the focus port, and `Cutscene`'s one-per-system verb surfaces (ADR-0125).
A port lets a system depend on nothing while still causing things. **The test is
whether the caller needs an answer** (ADR-0118 dec. 3): if nothing waits on a
reply it is a publish, not a port. Applied to `Effects`, that leaves exactly two
— clock and anchor — and makes camera, sound, screen, palette and landmark all
publishes (ADR-0127). _Avoid_:
facade (a single wide one hides the crossings), service, adapter (that is the
thing satisfying the port, not the port), autoload (a global name is never a
crossing mechanism — an addon cannot ship `project.godot` entries).

**Role binding**:
The map from an effect script's roles — caster, target, cell — to anchors that
answer position and orientation and nothing else. It is what keeps `Effects`
ignorant of what a combatant is. _Avoid_: target list, context.
