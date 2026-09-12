# The blueprint's eleven systems

The game-agnostic tactics-RPG domain model names **eleven systems**, each a bundle
that could be installed independently in another game. This ADR is the roster and
its crossings; the working map with diagrams is
[`docs/BLUEPRINT.md`](../BLUEPRINT.md).

Status: accepted (2026-08-20).

## Context

[ADR-0111](0111-the-research-vault-is-ballast-not-blueprint.md) requires a
blueprint that is neither code-derived (tautological) nor vault-derived
(ROM-shaped), and says it is recorded as ADRs. This is that record.
[ADR-0115](0115-a-system-is-a-bundle-that-ships.md) supplies the membership test;
[ADR-0116](0116-a-crossing-needs-a-payload-an-owner-and-an-edge.md) supplies the
bar each crossing must clear.

## Decision

**The eleven systems, each with the parts inside it.**
*(Read "ten" until 2026-08-21; the first line of this ADR has said **eleven**
since `829a1790c` added `Debug`.
[ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md)
caught the count, [ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md)
dec. 2 fixed this heading and `CONTEXT.md`'s. The **filename** still says ten and
is left alone — renaming it breaks every citation.)*

| # | System | Parts |
|---|---|---|
| 1 | **Battlefield** | `Lattice` · `Environment` · `Camera` · `Cursor` |
| 2 | **Battle** | `Combatant` · `Scheduling` · `Action Resolution` · `Agency` · `Performance` · `Body` · the `roster` · `Deployment` |
| 3 | **Character Catalogue** | `Character` · `Holdings` |
| 4 | **Sprite Rig** | templates · shapes · sequences · draw order · attachment |
| 5 | **Effects** | the timeline · the particle simulation · the channel vocabulary |
| 6 | **UI** | the toolkit · preview + commit |
| 7 | **Audio** | the sound driver |
| 8 | **Cutscene** | the interpreter · staging |
| 9 | **Campaign** | the mode · progression |
| 10 | **Render** | `Compositor` · the depth model · colour modes · shader templating · the fold · display aspect |
| 11 | **Debug** | the panel host · field widgets · the override layer · the declaration walk |

**Decisions that were not obvious, each with its reason:**

**1. The map is two things in one system.** `Lattice` is the authoritative
standable space; `Environment` is its dressing. They ship together because the
**standing surface** and the **ambient condition** are agreement crossings — a
unit floating above the ground and a unit sunk into a slope are one bug.

**2. Camera and cursor ship with the map.** The picking projection must equal the
rendering projection or the cursor lands on the wrong cell, subtly and only at
some heights. That crossing may not span a boundary.

**3. Simulation and its presentation are one system.** Nobody would use the
presentation without the simulation, so it is not a separate release. "Headless"
is a mode with no bodies attached.

**4. `Effects` ships alone, and inverts its glue.** It is the most pluckable
thing here and is welded to sound, camera and poses in every game that has one.
It **publishes channel events** over a declared vocabulary and takes a **role
binding** — caster, target, cell mapped to anchors that answer position and
nothing else. It never learns what a combatant is.

**5. `Sprite Rig` does not know what a combatant is.** Give it a pose, a facing,
a quadrant and an equipment set and it draws. `Body` is the thin adapter that
binds a combatant to one.

**6. `Render` is genre-orthogonal.** It is about looking like a PlayStation, not
about tactics. With `Effects` and `Sprite Rig` it forms a retro isometric sprite
toolkit with no tactics RPG in it anywhere — the three a stranger would plunder.

**7. The catalogue owns what you have; the spine owns where you are.** No
overlap. Holdings sit with the catalogue because equipping is a *transfer* —
split the ends across systems and items are lost or duplicated silently.

**8. `Cutscene` has no private door.** Every scripted command goes through the
interface any other caller uses; scripted damage is an effect-log entry with
`cause = script`. It owns no mechanism of its own. A `Scenario`
([ADR-0029](0029-encounter-setup-is-a-scenario-not-an-event.md)) is a record it
is pointed at by, not this system: **`Campaign` picks a `Scenario`, which points
at an event script, which `Cutscene` plays.**

**9. `Debug` is a system, and systems declare their tunables to it.**
[ADR-0113](0113-tunables-invert-at-the-addon-boundary.md) already inverts the
arrow — the addon declares its schema, the dashboard discovers it. This makes the
dashboard a system rather than "the host's", and the **tunable declaration a
published schema**: systems declare, `Debug` renders, neither knows the other.
Panels that know what a gambit slot *means* ship with their system; the panel
host, the widgets, the override layer and the discovery walk are `Debug`.

**10. A projectile is `Battle`, not `Effects`.** The mesh is pure presentation —
[ADR-0032](0032-ranged-damage-waits-in-state-awaiting-impact.md) keeps the flight
tail *in the shader*, counting flight ticks and writing damage at timer-zero. But
the mesh must fly in **lockstep with that GPU timer**, or the hit cloud
desynchronises from the damage. That is an agreement crossing, and the shader
owns the clock, so the mesh ships beside it. An `Effects` play is free-running
once triggered; this one is not.

**11. Authoring tools are assemblers, not systems.** The Effect Studio composes
systems the way the game does. See
[ADR-0115](0115-a-system-is-a-bundle-that-ships.md) dec. 5.

**12. Every system casts a content shadow that stays in the host** — sprite data,
map files, ability tables, event scripts, sound banks, the actual screens. That
is ADR-0110's "the host converges on the FFT content pack", stated per system.

## Considered alternatives

- **The vault's domain clusters.** Rejected by ADR-0111 and re-falsified here:
  `ATTACK.OUT` alone glues an encounter table, a placement table and a
  title-card wipe. **A ROM file is not a responsibility.**
- **A separate `Battle Presentation` system.** Rejected — no independent use.
- **A separate `Roster` system.** Rejected — `CONTEXT.md` and
  [ADR-0066](0066-character-identity-is-a-slug-catalog-above-the-roster.md)
  already make the catalogue the master and the roster a per-side collection. A
  selection is not a system; it lives where it is used.
- **A separate `Campaign` holding flags and holdings.** Half rejected: holdings
  belong to the catalogue, flags to the spine.

## Consequences

- **Eleven branches**, one per system, under ADR-0110 dec. 2.
- The `Effect System` and `Event VM` decomposition
  ([#307](https://github.com/timbermania/fft-monorepo/issues/307)) is handed a
  frame: `Effect System` stays **one** system whose *channels* fan out, and
  `Event VM` becomes `Cutscene` plus `Deployment`.
- **Recorded strains, not smoothed:** status rules span three parts by
  construction; two randomness sources look like one; forkable battle state is
  required by a *searching* AI and dormant while the AI stays declarative
  (a gambit slot asks *does this condition pass*, not *what is best*); and
  goal #8 runs backwards inside `Render`, where a PSX compromise is the product
  and a known drop is a regression.
- **`Render` is deliberately broad**, as broad as `Audio` and `UI` and harmless
  for the same reason. The blueprint names the *role*; the shipped addon gets its
  own name, as `Audio`'s does when it ships as `exmateria_sound`.
