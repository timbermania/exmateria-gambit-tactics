# Cross-system payloads are published schemas; required services are ports

Nothing crossing a system boundary is a type owned by its producer. A payload
that is **published** becomes a **schema**; a service a system **waits on**
becomes a **port**. Together they are the whole prerequisite for extraction —
and no system is.

Status: accepted (2026-08-20); dec. 4's key narrowed by
[ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md) (2026-08-20).

## Context

A first pass at the dependency graph put `Render` at the bottom, because
everything that draws needed it, and serialised the whole extraction schedule
behind one system. That reading was an artifact of treating payloads as types
belonging to whoever emits them.

It also produced three apparent conflicts with
[ADR-0110](0110-systems-extract-outward-into-addons.md)'s stated order — "the
clean five first, as cheap validation." All three were the same mistake:
comparing a dependency graph against a **risk** ordering and calling the
difference a contradiction.

## Decision

**1. A payload that crosses a boundary is a published schema.** Consumers depend
on the schema, never on the producer — which is how event sourcing already works.
Six of them, plus the **colour model** added by [ADR-0138](0138-a-publish-does-not-imply-an-assembler.md) dec. 6 (2026-08-21):

| Schema | From, to |
|---|---|
| the **compositing key** | every drawable emitter **and** `Render`, on a shared encoding (ADR-0138 dec. 10 — the direction here was wrong; nothing goes *to* `Render`) |
| the **colour model** | `ColorStack` / `ColorRecipe`, to `Battlefield`, `Cutscene`, `Effects` — the sixth, added by ADR-0138 dec. 6 |
| the **effect channels** | `Effects`, to whoever subscribes |
| the **effect log** | `Battle`, to replay, save and its own presentation |
| **pose requests** | `Body`, to `Sprite Rig` |
| **character records** | `Character Catalogue`, to `Deployment` |
| **tunable declarations** | every system, to `Debug` (ADR-0113) |
| the **terrain cell** | `Battlefield`, to `Battle`, `Cutscene`, `Effects` — the **eighth**, added by [ADR-0164](0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md) dec. 2 |
| the **cell marking** | `Battle` (`src/strategy/` decides it), to `Battlefield` (paints it) — the **ninth**, added by [ADR-0196](0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md) dec. 6/7 |
| the **unit-sprite vocabulary** | `Sprite Rig`, to `Battle`, `Cutscene`, `Deployment` and `UI` — the **tenth**, added by [ADR-0215](0215-the-sprite-rig-seam-is-a-scene-a-vocabulary-and-a-content-port-and-two-thirds-of-its-interface-belongs-to-two-adapters.md) dec. 2 / [ADR-0217](0217-the-kernel-publishes-no-names-so-the-vocabulary-move-is-sixty-one-alias-declarations-and-the-rig-needs-a-facade-first.md) dec. 7 |
| the **unit role vocabulary** | the `rules` tier (`JobDatabase.get_job_role` decides it), to `Battle` (`src/gpu/GambitEncoder.gd` packs it) and `UI` (`src/ui3/UIGambitEditor.gd` populates its dropdown) — the **eleventh**, added by [ADR-0280](0280-gambits-stays-in-the-almanac-and-the-tests-that-said-otherwise-were-measuring-a-kernel-vocabulary-in-the-wrong-package.md) dec. 3 |
| the **unit progression vocabulary** | the `rules` tier (`UnitProgression` declares them), to `Character Catalogue` (seeds and serialises them), `Battle` (`src/units/Unit.gd`, `src/gpu/`), `UI` (`src/ui3/detail/`, `src/ui3/formation/`), `Audio` (`src/audio/SfxRouter.gd` picks a voice bank off the body type) and `Cutscene` (`src/scenarios/PromotedRosterSeeder.gd`) — the **twelfth**, added by [ADR-0294](0294-the-catalogues-progression-debt-is-a-vocabulary-and-the-kernel-is-where-a-value-set-lives.md) dec. 2 |

> **Amended by [ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md)
> dec. 14 (2026-08-21):** the table is **seven** rows, and that is the count.
> `CONTEXT.md` said *"Six"* and listed six — it dropped **tunable declarations**
> and added the colour model, holding the count constant by coincidence; ADR-0138
> dec. 6's *"the sixth"* was the right ordinal against that list and the wrong one
> against this table. The colour model is the **seventh**. ADR-0139 dec. 11 also
> records which rows have code members today (two: the compositing key and the
> colour model) and dec. 12 that **tunable declarations has none by
> construction** — it is realised by a port's signature, so it never enters the
> shared kernel.

> **Amended by [ADR-0164](0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md)
> dec. 2 (2026-08-25):** the table is **eight** rows. `Battlefield`'s lattice port
> answers with a `TerrainCell` payload rather than the `Tile` node, so the terrain
> cell is a published schema and — passing both of ADR-0139 dec. 4's vetoes — the
> shared kernel's **third** code member, written at extraction #3 pass 6. The row
> exists *because* ADR-0139 dec. 3 makes an ADR the gate: the type cannot be
> written until the schema is named here.

> **Amended by [ADR-0196](0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md)
> dec. 6/7 (2026-08-28):** the table is **nine** rows. The payload is *which
> marking a cell wears* — `NONE`, three placement roles, `PLACEMENT_UNAVAILABLE`,
> `CURSOR_ACTIVE` — decided by `src/strategy/` and rendered by the addon, whose
> `TileOverlayConfig` owns the *look* and never the meaning. It becomes the shared
> kernel's **fourth** code member, `CellMarking`, passing both ADR-0139 dec. 4
> vetoes trivially (an enum has zero outbound edges and is not an autoload). It
> lives on its OWN member rather than riding `TerrainCell` as a nested enum —
> `TerrainCell.NONE`'s free ride (ADR-0193 dec. 3) was legitimate because a
> sentinel coordinate *is* a terrain-cell value, and a marking is placement policy,
> which `TerrainCell`'s docstring already rules out by name.

> **Amended by [ADR-0215](0215-the-sprite-rig-seam-is-a-scene-a-vocabulary-and-a-content-port-and-two-thirds-of-its-interface-belongs-to-two-adapters.md)
> dec. 2 and [ADR-0217](0217-the-kernel-publishes-no-names-so-the-vocabulary-move-is-sixty-one-alias-declarations-and-the-rig-needs-a-facade-first.md)
> dec. 7 (2026-09-01):** the table is **ten** rows. The payload is the value
> vocabulary a unit sprite is described with — *which way it is turned*, *which of
> its three composed layers*, *which pump advances its clock*, *which blend it is
> drawn with*. A caller of one of these learns a **value set**, not a contract: no
> ordering, no invariant, no error mode. Until this row they were nested in the
> classes that happened to own the behaviour, so a host compiled against an
> 888-line Node in order to say *"weapon layer"* — 149 crossing uses over four
> enums. It becomes the shared kernel's **fifth through eighth** code members —
> `Facing`, `SpriteLayer`, `ClockOwner`, `UnitMaterialVariant` — each passing both
> ADR-0139 dec. 4 vetoes trivially, as `CellMarking` did.
>
> 🔴 **ONE ROW, NOT FOUR, AND THAT IS A RECORDED CHOICE RATHER THAN A COUNT.**
> ADR-0196 gave the cell marking its own row beside the terrain cell, so the
> precedent for splitting exists. It is not followed here because ADR-0215 dec. 2
> and ADR-0217 dec. 7 decided these as **one vocabulary** — one decision, one
> table of published names, one directory (`unit_vocabulary/`), one README
> section — and pass 6 builds what those passes decided rather than re-cutting it
> into four schemas nobody ruled on. The row is written to hold a fifth member:
> ADR-0217 dec. 8 puts the generated activity taxonomy here too, published as
> `UnitActivity.Display` / `.Logical` from the same YAML rows that emit `Battle`'s
> half (issue #740), and that lands **without another amendment**.

> **Amended by [ADR-0280](0280-gambits-stays-in-the-almanac-and-the-tests-that-said-otherwise-were-measuring-a-kernel-vocabulary-in-the-wrong-package.md)
> dec. 3 (2026-09-10):** the table is **eleven** rows. The payload is *which combat
> archetype a unit is* — `ANY`, `MELEE`, `RANGED`, `MAGE`, `HEALER`, `HYBRID` — decided by
> the `rules` tier's `JobDatabase.get_job_role` and consumed by `Battle`'s gambit encoder
> and `UI`'s gambit editor. It is a **vocabulary rather than a payload**, which the tenth
> row already established as admissible, and it is the first row whose producer is the
> `rules` tier rather than a system. `addons/exmateria_almanac/jobs/UnitRole.gd` realises
> it as the shared kernel's next code member: 47 lines, `extends RefCounted`, an enum plus
> three static functions, passing ADR-0139 dec. 4's sink veto with an outbound edge count
> of **0** and its autoload veto by construction. The row exists for ADR-0164 dec. 2's
> reason — ADR-0139 dec. 3 makes an ADR the gate, and the file cannot move until the schema
> is named here.

> **Amended by [ADR-0294](0294-the-catalogues-progression-debt-is-a-vocabulary-and-the-kernel-is-where-a-value-set-lives.md)
> dec. 2 (2026-09-11):** the table is **twelve** rows. The payload is the value vocabulary a
> unit's *progression* is described with — **which slot a piece of equipment occupies**
> (`RIGHT_HAND`, `LEFT_HAND`, `HEAD`, `BODY`, `ACCESSORY`), **which base-stat curve it grows
> on** (`MALE`, `FEMALE`, `MONSTER`), and **which zodiac sign it was born under** (twelve
> signs plus `SERPENTARIUS`). Like the eleventh its producer is the `rules` tier rather than
> a system, and like the tenth it is a **vocabulary rather than a payload**. Until this row
> all three were enums nested in `progression/UnitProgression.gd`, a ~1,000-line `Resource`
> over five ROM databases, so a caller compiled against the whole simulator in order to say
> *"head slot"* — 23 of the Character Catalogue's 36 arm-5 debt lines, plus 33 lines across
> five systems that arm 5 cannot see because it does not walk `src/`. They become the shared
> kernel's next three code members — `unit_vocabulary/EquipSlot.gd` (41),
> `unit_vocabulary/BaseStatType.gd` (37), `unit_vocabulary/Zodiac.gd` (93) — each passing
> ADR-0139 dec. 4's sink veto with an outbound edge count of **0** and its autoload veto by
> construction (`extends RefCounted`, no `[autoload]`).
>
> 🔴 **ONE ROW, THREE MEMBERS, ON THE TENTH ROW'S PRECEDENT AND NOT THE NINTH'S.** ADR-0196
> gave the cell marking its own row, so splitting has a precedent; ADR-0294 dec. 2 follows
> ADR-0215 dec. 2 instead, because these three were decided as one vocabulary in one
> directory and three of the eleven rows above would have to be re-cut before a per-enum
> rule was consistent. The row is written to hold `abilities/AbilitySlot.gd` too, if
> anything outside the almanac ever names it — ADR-0294 dec. 5 measures that at **zero**
> today, which is why it did not travel, and that arrival would land **without another
> amendment**.
>
> 🔴 **`UnitProgression` ITSELF DID NOT MOVE AND IS NOT ADMISSIBLE.** It names five
> databases on 56 static calls (ADR-0241 dec. 3) and would fail dec. 4(a)'s sink veto on
> every one of them. It re-exports the three members so no call site is respelled, and the
> 13 arm-5 lines that survive are it and `GambitList` being held and constructed — the
> residue ADR-0280 dec. 6 rules the accepted price.

**2. A service a system waits on is a port**, declared by the system and
implemented by whoever assembles the game. Three of them: **clock**, **focus**,
**lattice**.

**3. The test that separates them is whether the caller needs an answer.** A port
is a synchronous dependency — nothing proceeds without the reply. A schema is
fire-and-forget; whether anyone consumes it is not the emitter's business.
Submitting a drawable is a publish, which is precisely why `Render` is
swappable: nothing calls into it, things publish past it.

> **Amended by [ADR-0138](0138-a-publish-does-not-imply-an-assembler.md)
> (2026-08-21):** **the test stands and is complete** — it is the whole of
> publish-vs-port and needs no third category. The *illustration* is false as
> written: eight files across four systems name `Fold` by `class_name`, so
> things do call into `Render` by name. It is true of `Render`'s **runtime**,
> which has 0 inbound edges. What dec. 3 does not settle is a publish's
> **binding** — assembler-wired (open consumer set) or direct by name (closed
> set reaching a stable published surface). ADR-0138 dec. 3 adds that test;
> ADR-0137 dec. 8's `Leaf` was an attempt to get the same result without it.

**4. The compositing key is split so it can be published.** `layer`, `depth` and
`anchor space` are generic; `colour mode` travels as an **opaque token** the
emitter never interprets. `anchor space` is also what keeps `UI` free of any
camera — it tags drawables `screen` and the compositor decides what that means.

> **Amended by [ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md)
> dec. 5-6 (2026-08-20).** `anchor space` is **not** a key field — it is a shader
> library entry (`psx_par.gdshaderinc`, ten includers), as is colour mode on the
> direct path, where the opaque token *is* the `Material`. `layer` is currently
> degenerate: exactly one `FOLD_LAYER`, deliberately. What a producer actually
> surrenders is **membership and order**. The mechanism this decision claims for
> `UI` is real and already built — five `Fold.add` sites — it just is not a field.

**5. Extraction order is therefore free**, chosen by risk and parallelism.
ADR-0110's "clean five first" is a risk ordering and was never in competition
with this graph. Seven of ten systems depend on nothing but schemas and ports.

> **Amended 2026-08-21 by [ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md)
> (#331).** *"Free"* is upheld and is now exercised: ADR-0110's clean five is
> **withdrawn as an order** and replaced by a measured-isolation reading, with
> **`Render` first**. This decision's own framing — a risk ordering, not a
> dependency one — is what made the replacement a free choice rather than a
> re-derivation.

**6. A port is cheaper than a shared library, and better for pluckability.** A
stranger pulling `Sprite Rig` writes a twenty-line clock adapter rather than
adopting our clock, our conventions and our version.

## Considered alternatives

- **`Render` as a hard wave-1 dependency.** Rejected: it serialises the schedule
  behind one system and destroys the parallelism ADR-0110 dec. 2 exists for.
- **The clock inside `Render`.** Rejected: it undoes the swappable-renderer
  decision (everything loses time on a swap), gives a headless simulation a
  rendering dependency, and hands `Audio` — which today references zero host
  autoloads — one it does not have.
- **One shared `infrastructure` addon for everything generic.** Partly rejected:
  clock and focus are port-shaped and need no library. What remains —
  definition resolution, persistence — is small enough that an addon may not be
  warranted. Recorded as open.
  **Closed by [ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md)
  dec. 13 (2026-08-21): no.** Measured, the eleven systems reach the
  `infrastructure` bucket **three times** in 141,837 lines (`UserSettings` twice,
  `ValidationUtils` once; `AssetManifest` zero). The three files stay in the host.
- **Three libraries split by dependency ceiling** (pure / framework-bound /
  genre-shared). Rejected as premature: every candidate member wraps Godot, so
  the pure tier has zero members and the two-user rule says do not create it.

**7. A global event bus is not a schema and has no place here.**
`src/core/EventBus.gd` — 39 lines, six users — is an untyped ambient channel,
which is exactly what a declared vocabulary replaces. **Delete it in the
refactor**; each of its six uses resolves to a channel with a schema, a query, or
a capability.

## Consequences

- **The schemas are the architecture.** They are what every system is written
  against and the thing that cannot be changed later without touching
  everything. They are the first work, and designing one is not an extraction —
  it is a different unit of work than ADR-0110 dec. 2 describes.
- Waves, for reference rather than as a schedule: **1** — `Render`, `Audio`,
  `Sprite Rig`, `Effects`, `Battlefield`, `UI`, `Character Catalogue`; **2** —
  `Battle`, `Cutscene`; **3** — `Campaign`.
- **Event sourcing brings its costs with its benefits.** Replay, undo and
  time-travel debugging come free; log versioning and upcasting come as the bill,
  and land on persistence.
- The GPU simulator produces *state* where an ordered log is wanted. That tension
  is internal to `Battle` — see
  [ADR-0120](0120-battle-state-has-one-write-path.md).
