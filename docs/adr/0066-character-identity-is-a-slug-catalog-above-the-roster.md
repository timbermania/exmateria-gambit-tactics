# Character identity is a slug-keyed Catalog above the roster; assets are Form templates materialized as instances

**Status:** proposed (agreed design target; the `CONTEXT.md` "Character
catalog" cluster is the ubiquitous language for it). **First slice landed:**
the `CharacterCatalog` autoload (flat `{slug: name}` seed) + the shared
`TypewriterController.macro_text` render seam resolve `0xE0`/`{Ramza}` →
`catalog["ramza"]` live, so dialogue renders the name (no braces) and tracks a
rename (guard: `tests/ScenarioNameMacroTest.gd`). Remaining decisions
(Forms, Profiles, the transform tier, parse-time `Name macro` token) are still
design-only.

**Refined by [ADR-0072](0072-a-template-is-a-derived-folder-per-key-asset-packet-that-is-the-runtime-read-surface.md):**
the asset "template" is a *derived, folder-per-key packet* (the runtime read
surface) — generics have templates too (`job×gender`), and a template is
*assets only* (no stat block). ADR-0072 supersedes the "Character Profile"
term but keeps this ADR's derived/reproducible contract.

**Extended by [ADR-0201](0201-battle-cast-is-a-replay-derived-view-of-the-catalog.md):**
the Catalog gets its first runtime customers on the navigator path — replay
writes it (a beat-keyed mutation script), battle reads it (ENTD demoted to a
slug-binding manifest with a `(context, uid) → slug` resolver + ENTD-slot
fallback). Seeking a beat becomes "replay the Catalog to that beat."

## Context

A dialogue box in scenario 8 renders `{Ramza}` — braces and all — because
`0xE0` is FFT's name-insert control code for the player-nameable protagonist,
and we render the FFTPatcher marker literally instead of substituting a name.
Chasing "where should the name come from" exposed that the game has **no home
for character identity**:

- The battle **`Roster`** (`UnitRosterData.unit_name`, `user://roster.json`)
  is the only durable name store, but it is battle-scoped and currently holds
  hardcoded demo units — the protagonist is not in it.
- **Scenario actors** are keyed by an event-local `unit_id` (Ramza = `uid
  0x02`), carry no name, and have zero link to the roster.
- PSX hardwires the protagonist's name via `0xE0` and **bakes every other
  name literally** into the text bytes, because in PSX only the protagonist is
  variable.

We want a **superset of PSX**: every unit as addressable as a story character
(nameable in dialogue, recruitable, job/equipment), a single clean identity
store, and an offline layer that stops the runtime doing ad-hoc asset assembly
(today `ENTD → special_name → asset store` is resolved live).

## Decision

1. **One population, one master.** A slug-keyed **Character Catalog** is the
   source of truth for who exists. The battle **`Roster` demotes to a
   selection/view** over it (who is enlisted for a fight), not the master list.

2. **`Character` = identity.** Canonical `slug` (+ optional aliases), name,
   name-provenance, and its functional attributes (job/equipment/abilities via
   the existing `UnitProgression`/`GambitList`). Unique within the active
   Catalog. A `Character` **groups one-or-more `Form`s**.

3. **`Form` = a chapter/job incarnation.** The per-`special_name` sprite+stat
   bundle. **1:1 with a ROM `special_name`, N:1 onto a `Character`** — Ramza's
   `RAMZA`/`RAMZA2`/`RAMZA3` are three Forms of one identity. Job/appearance
   change over time is *state, not a new identity* (the same rule the job
   system already applies to generics).

4. **`slug` = the cross-system identity key.** Human-authored, stable. Many
   `special_name` bytes map to one slug (`0x01/0x02/0x03 → ramza`). It is *not*
   the event-local `unit_id` nor the raw `special_name`.

5. **`Name macro` = a first-class dialogue token, decided at parse time.**
   Resolves `catalog[slug].name` at render — distinct from word macros
   (`{Serpentarius}`) and formatting (`{Newline}`). `0xE0`/`{Ramza}` imports as
   `{Name ramza}`; authored content targets a slug explicitly (`{Name agrias}`).

6. **The Catalog is a runtime registry with two lifetimes.** Persistent
   `Character`s (serialized) and transient throwaways (minted from a **default
   Character template**, scene-scoped, never serialized). Populated lazily.

7. **A `character-alignment transform` (offline ACL tier)** does two jobs:
   (a) emit per-`Form` **`Character Profile`s** from scattered parser output,
   and (b) **rewrite scenario event instructions to be slug-addressed**,
   removing the runtime `ENTD → asset store` coupling. **Parsers stay
   ROM-faithful and reproducible** — this is a downstream derivation stage.

8. **The Profile set is derived, the asset residue is hand-authored
   (hybrid).** The cast = union of `special_name != 0` slots across all
   scenario ENTDs (superset of speakers). Clean ROM associations are derived;
   the ambiguous ones (EVTCHR entry → character) come from a small curated
   `slug ↔ asset` mapping.

9. **Context resolves the active `Form`.** A slug-only instruction is enough;
   the active Catalog picks the Form from story state. The transform preserves
   an explicit form-override **only** when the source `special_name` disagrees
   with what context would pick (rare escape hatch).

10. **Profiles/Forms are immutable templates; the active Catalog holds live
    instances.** An instance materializes from its Form template; its asset
    linkages (and other state) are mutable via **overrides stored as a diff
    against the active template** (copy-on-write — no before/after history;
    `instance = template + diff`). Runtime re-skinning is a *permitted
    capability*, YAGNI-gated: build the override seam, not a re-skinning
    system, until a use case exists.

11. **Name provenance is a per-`Character` `Fixed` vs `Player` flag.**
    `Fixed` = canonical, seeded from `UnitNames.xml`, not player-editable
    (Agrias is always "Agrias"). `Player` = player-authored, editable —
    generics, and the **protagonist as a deliberate `Player`-with-canonical-
    default** (ships as "Ramza", the name-entry flow may override). The flag
    drives two behaviors off one field: which units the naming UI lets you
    rename, and whether a re-import may overwrite a name (`Fixed`: yes;
    `Player`: never clobber the player's choice).

## Considered options (rejected)

- **Two identity spaces bridged by a separate `Character` concept above both
  roster and scenario.** Over-abstraction — the roster already models
  identity+name; a parallel concept duplicates it.
- **Render-time catalog dispatch for name macros** (treat any macro that hits a
  slug as a name). Fragile: a word macro colliding with a slug silently becomes
  a name. Decide name-vs-word at parse time instead.
- **Three separate "Ramza" characters** (ROM-faithful `special_name` 1:1).
  Breaks naming/identity — renaming the protagonist would touch three records
  and the slug would be ambiguous. Inconsistent with "job change is state."
- **Fully hand-authored or fully derived asset mapping.** Hand-authored rots
  and re-authors free ROM data; fully derived encodes a guess (this is how the
  1-row EVTCHR bake bug happened). Hybrid quarantines the hard-won knowledge.
- **Storing full before/after overrides.** Unnecessary — diff against the
  active template.

## Consequences

- The parser tier is untouched and stays faithful; a new offline transform tier
  owns all character-alignment "wrangling."
- The runtime becomes slug-driven; the `ENTD → asset store` coupling is removed
  incrementally (EVTCHR is the pilot, per `EVTCHR_FRAME_RESOLUTION.md`).
- The curated `slug ↔ asset` residue is a **maintenance surface**: a new
  scenario character means adding a mapping row.
- **Incremental path:** the first shippable slice is narrow — seed the `"ramza"`
  `Character`, wire the `Name macro` → `catalog["ramza"].name`, and scn8
  renders correctly. Everything else (full cast import, ENTD→Character binding,
  the transform tier, template/instance materialization) lands against the same
  model with no rework.

## Open questions

None outstanding — name provenance is resolved as decision 11 above. The
remaining unknowns are implementation details (the exact `slug ↔ asset`
residue schema, where the active-Form context state lives), to be settled when
the transform tier and Catalog are built.
