# `Effects` publishes into surfaces it does not own, and requires two ports

Everything that leaves `Effects` is a **publish** — fire-and-forget, on a
declared schema, with an assembler wiring the listener. `Effects` requires
exactly two **ports**: the **clock** and the **anchor**. No autoload is ever a
crossing mechanism.

Status: accepted (2026-08-20); dec. 2's port table extended by
[ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md) (2026-08-20).

## Context

`BLUEPRINT.md` says of `Effects`: *"**It depends on nothing.** It emits;
consumers subscribe. With no `Audio`, no `Camera` and no `Body` installed, the
events go unheard and the particles still play."*
[ADR-0110](0110-systems-extract-outward-into-addons.md) calls it *"the most
pluckable thing on this list, and the reason it ships alone."*

That claim had never been tested against what a stranger would have to
implement. [#315](https://github.com/timbermania/fft-monorepo/issues/315) is the
audit.

**One lane of ten actually subscribes.** Surveyed against `src/effects/`, the
ten lanes of [ADR-0122](0122-an-effect-lane-is-a-track-of-non-overlapping-typed-events.md)
leave the system like this:

| lane | how output crosses today | mechanism |
|---|---|---|
| `landmark` | `signal ability_react_triggered(frame)` + two more | **subscription** |
| `sound` | `ExMateriaEffectSfx.play_pair(token, feds_bank, pair_idx, sound_id)` | autoload call |
| `screen` | `ScreenEffectOverlay.update_layer_gradient(owner_id, ...)` | autoload call |
| `palette.affected_units` | `MapTintOverlay.update_stack(owner_id, ColorStack, frame)` | autoload call |
| `palette.caster` / `.target` | `UnitTintOverlay.update_stack(unit.get_instance_id(), ...)` | autoload + a `Unit` node |
| `camera.angle` / `.position` / `.zoom` | nothing is emitted — the assembler polls public fields and writes them back | shared mutable struct |
| `particle` | `EffectParticleRenderer` -> `EffectMultiMeshPool` -> `EngineFoldCompositor` | does not cross |

The blueprint's *"consumers subscribe"* describes `landmark` and nothing else.

**The mechanism, not the units, is the first-order problem.** #315 framed the
leak as number systems and colour models. Both are real, and
[ADR-0128](0128-a-colour-crossing-is-an-affine-op-with-an-opaque-mode-token.md)
takes the colour half. But five lanes reach their listener by a **hardcoded
global name**, which no unit conversion fixes.

**An autoload is a seam and a bad interface.** Godot resolves the name from the
host's `project.godot`, so a stranger genuinely *can* substitute a script —
that is why this has worked. What it cannot do is *declare* anything: `Effects`
never states that it requires a tint surface, so the requirement is discovered by
crashing. And it cannot be satisfied by an addon at all — an addon that only runs
once the host has registered `ScreenEffectOverlay`, `MapTintOverlay`,
`UnitTintOverlay`, `EffectMultiMeshPool` and `ExMateriaEffectSfx` ships with a
five-line installation ritual and a runtime crash if a line is skipped.

**The benchmark holds, and it is zero.** `BLUEPRINT.md` §7 claims
`exmateria_sound` *"references zero of the host's 24 autoloads."* Verified: two
apparent hits (`spu.gd:282`, `runtime.gd:63`) are both comments. The one finished
system reaches zero globals. That is the calibration `Effects` is measured
against.

**#315's own survey comment is wrong about the overlays.** It records that each
of the three tint overlays has a writer outside `Effects`, concluding `Effects`
owns none of them. The outside calls are `register_material()`,
`register_unit()` / `unregister_unit()` and `set_default_gradient()` —
**enrolment and baseline, not tint**. The single genuine second layer-writer is
`ScenarioVM` (`Cutscene`) calling `overlay.set_corners(...)`. So
`ScreenEffectOverlay` carries three writers using three different verbs through
one global name with no declared interface, and the other two carry one.

**A second assembler already exists and already proves the seam.** The Effect
Studio (85 files, its own root set per ADR-0112) plugs the same `EffectInstance`
into a different set of listeners: the game pumps the clock from
`_process(delta)` while the studio parks it and drives `seek(frame)`
(ADR-0070); the game supplies caster/target units while the studio supplies
none — `PaletteSubsystem._deliver_output` notes *"Unit tints are runtime-only —
no live caster/target in the editor preview."* Two adapters for the clock port,
and a tint listener that is already optional in practice.

## Decision

**1. Everything leaving `Effects` is a publish.**
[ADR-0118](0118-payloads-are-schemas-services-are-ports.md) dec. 3 gives the
test — *"whether the caller needs an answer"* — and no lane needs one. An effect
that says *yaw 90 degrees over 15 frames* proceeds identically whether or not a
camera exists. `camera`, `sound`, `screen`, `palette` and `landmark` are all
published schemas, not ports. This corrects the working assumption during #315
that camera and sound were port-shaped.

**2. `Effects` requires exactly two ports: `clock` and `anchor`.** These are the
only two places the effect cannot proceed without a reply — *what frame is it*
and *where is the caster*. Both are already ADR-0118 dec. 2 shapes; the clock
already has two adapters in-tree.

> **Amended by [ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md)
> dec. 8 (2026-08-20): a **third** port. `owns_compositing()` — *can I fold?* — is
> reached from 8 call sites across 4 systems by hardcoded autoload name, and every
> caller branches on the answer. This ADR did not look at it because it lives in
> `Render`'s file rather than in one of the ten lanes.

**3. No autoload is a crossing mechanism.** A crossing is satisfied by a
reference the assembler hands in, never by a name resolved at global scope. This
is what ADR-0121 dec. 1 requires in practice: a system that lands in
`addons/<system>/` cannot demand entries in the host's `project.godot`.

**4. Four of the five globals are not crossings at all.**
`ScreenEffectOverlay`, `MapTintOverlay`, `UnitTintOverlay` and
`EffectMultiMeshPool` all classify as `Effects` — this is the system reaching its
own parts ambiently. They stop being autoloads and become objects the system
constructs and holds. No port, no schema, no other system affected.

**5. The tint seam already exists under another name, and it is real.** Outside
systems already enrol their surface — `DynamicGeometryBuilder.register_material`,
`Unit.register_unit`, `MapComposer.set_default_gradient` — and `Effects` already
pushes keyed layers onto what was enrolled. That is the *tintable surface handle*
#315 proposed, half-built. Three adapters (map, unit, screen), so by the
two-adapters test it is a real seam and not a hypothetical one. The work is
inverting who holds the reference, not inventing the interface.

**6. `landmark` stays a signal.** It is the one lane that already works and the
one ADR-0123 designates the extension point, with fan-out to several listeners.
Routing it through a global would mean rebuilding a subscriber list inside the
global to reach parity with what it already does.

**7. Ten lanes carry three payload types, not ten.** ADR-0118 dec. 1 declares
*"the effect channels"* as **one** schema, and ADR-0122 fixed the granularity —
*"extent and payload kind are declared per EVENT, not per lane."* Enumerating the
kinds, nine of the ten lanes collapse onto three:

| payload type | lanes | established by |
|---|---|---|
| an **opaque code at a frame** | `sound`, `landmark` | ADR-0123 (same kind of thing), ADR-0124 |
| an **affine colour op + opaque mode token** | `screen`, `palette.affected_units`, `palette.caster`, `palette.target` | [ADR-0128](0128-a-colour-crossing-is-an-affine-op-with-an-opaque-mode-token.md) |
| a **camera move in game units** | `camera.angle`, `camera.position`, `camera.zoom` | ADR-0122 dec. 8 |

A stranger implements three listeners, not ten. `particle` is the tenth and is
left open — see Consequences.

**8. The honest statement, replacing *"it depends on nothing":***

> `Effects` **publishes, and requires two ports — clock and anchor.** It is
> genuinely pluckable, and a second assembler already proves it. What is not
> true is that it depends on nothing: five lanes reach their listener by a
> hardcoded global name instead of publishing, and `camera` does not publish at
> all — the assembler reads the effect's internal fields every frame. Those are
> unfinished wiring, not a broken thesis.

## Consequences

**The extraction thesis survives the calibration case, with a named debt.**
ADR-0110's *"the most pluckable thing on this list"* stands. What #315 disproves
is the stronger *"depends on nothing"*, and the gap is wiring rather than
architecture — which is why the studio can already do most of the substitution.

**`camera` is the worst lane and the only one with nothing built.** The other
five have a listener and a verb; camera has neither. `current_position`,
`current_angles`, `current_zoom` and the `saved_*` trio are public fields the
assembler reads *and writes back*, so the coupling is a shared mutable struct in
the ROM's number system. ADR-0122 dec. 8 already decided the payload publishes in
game units; this ADR adds that there must be a publish at all.

**`camera` also learns what a combatant is, which #315 did not record.**
`CameraSubsystem` holds `caster_unit`, `target_unit`, `cursor_unit` and a
`facing_resolver`, keying a yaw cache on `get_instance_id()`. The
`BLUEPRINT.md` note marking *"the effect never learns what a combatant is"* false
cites `PaletteSubsystem` only; the leak is in two lanes, and the same
role-resolves-to-a-handle fix covers both.

**The shared schema addon is now a scheduling dependency, not just a
prerequisite.** ADR-0121 dec. 5 says the six published schemas get one shared
addon *"built before any extraction"*. `Effects` cannot publish before the
effect-channel schema exists to publish on. Nothing currently schedules that
addon; recorded as fog on map #305.

**`Effects` contains a renderer, and the classifier books it as `Effects`.**
`EffectMultiMeshPool`, `EngineFoldCompositor`, `Fold`, `FoldSurface`,
`UnifiedPrimStager`, `EffectParticleRenderer`, `OTDepthPrimOrder` and the three
compositors are **2,088 lines** of the 16,270 in non-studio `src/effects/`,
assigned to `Effects` by `classify_blueprint.py`'s directory rule. So the
`particle` lane has no crossing to audit — the system draws its own particles
through a bespoke compute-shader fold. Whether that is `Effects`' or `Render`'s
is not decided here, and it is the one lane whose schema is undetermined.

**`particle` may already have a schema, and it is not the effect-channel one.**
ADR-0118 dec. 1 lists *"the compositing key — every drawable emitter, to
`Render`"* among the six, which assumes particle drawables cross. Today they do
not. Both cannot hold: if the renderer above is `Render`'s, particle crosses on
the compositing key — already declared, and already split by ADR-0118 dec. 4
into generic fields plus an opaque `colour mode` token, the identical move
ADR-0128 makes for tint. If the renderer is `Effects`', particle never crosses
and needs no schema at all. Resolving that is the remaining decision on this
lane.

**Who owns the unit-tint surface is contested, and the classifier is the
suspect.** `Unit.gd` classifies as `Battle`, which would make the tint schema's
endpoints `Effects` -> {`Battlefield`, `Battle`}; `BLUEPRINT.md` assigns the
unit's material to `Sprite Rig`. Recorded, not resolved — but the precedent runs
against the classifier. `CrystalSpriteCompositor` was booked to `Battle` by the
same `src/units/` -> `Battle` directory rule and ruled `Sprite Rig`'s on review
([#316](https://github.com/timbermania/fft-monorepo/issues/316)), on the grounds
that frame assembly from sheet regions, an animation timeline and a drawable with
a compositing key are three of `Sprite Rig`'s declared parts. `src/units/` holds
at least two systems, exactly as `src/effects/` does, so a directory rule cannot
settle either.

**ADR-0124 is a decision, not a description.** It says what crosses to `Audio` is
*"one opaque code and one frame"*. What crosses today is
`(token, FedsBank, pair_idx, sound_id)` — `Effects` hands `Audio` back `Audio`'s
own parsed bank object. The ADR remains right; nothing had told it that the code
does not match it yet.

**No code moves here.** This is a decision ticket on a planning map. Pass 6 gates
every extraction and is itself gated on
[#299](https://github.com/timbermania/fft-monorepo/issues/299).
