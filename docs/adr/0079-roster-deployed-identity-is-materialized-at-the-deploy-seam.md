---
status: accepted
---

# Roster-deployed identity is materialized at the deploy seam, not stored on the Character

Extends [ADR-0066](0066-character-identity-is-a-slug-catalog-above-the-roster.md)
(the `slug`-keyed Character Catalog is the master identity; a `Form` is the
per-chapter incarnation, resolved from story context and materialized as
`special_name`), [ADR-0201](0201-battle-cast-is-a-replay-derived-view-of-the-catalog.md)
(the battle cast is a replay-derived view; ENTD is a manifest, not a factory),
and [ADR-0078](0078-owned-is-a-catalogue-overlay-and-class-is-derived-per-battle.md)
(owned units deploy from a catalogue overlay, outside the ENTD).

## Context

At the roster-fed Gariland victory beat, the deployed protagonist renders as a
generic **Squire** — wrong body sprite *and* wrong dialogue portrait. Root
cause: the owned `Character` minted by `GarilandMutationScript._ramza_character()`
carries `special_name = 0`. `CharacterTemplateResolver.resolve()` keys uniques
on `special_name` (via `ResidueManifest`), so `0` is not in the residue → Ramza
is **job-routed** to the generic sprite.

The deeper cause is structural, and it is the cost of ADR-0078's move: an
**ENTD-spawned** unit gets its Form for free because `ScenarioPlayerScene._spawn_units`
reads `special_name` off the ROM ENTD slot at spawn. A **roster-deployed** owned
unit is placed *outside* the ENTD (that is the whole point of the roster-fed
path), so it never passes through that seam — it acquires presence (fixed
separately, this branch) and **identity** nowhere. ADR-0066 decision 9 already
promised "context resolves the active Form"; it was simply never built for the
roster-deploy path.

The naive fix — set `c.special_name = 1` when minting Ramza — stamps the Form as
a **durable byte on the persistent identity**. It is safe only because the
navigator currently reaches Chapter 1 alone; the moment a Ch2 battle lands it
renders the wrong Ramza, and nothing re-stamps a persistent unit that is joined
once and deployed many times.

## Decision

**A roster-deployed unit's Form is materialized at the deploy seam, from
ROM-derived data carried by its Catalog `Character` — never stored as a fixed
byte on the identity.**

- **The Catalog holds the identity and its *Form set*, by slug.** A unique
  `Character` carries its chapter-versions (seeded at mint from ROM-derived
  data — the same authority the ENTD encodes; hand-authored now, transform-
  generated later, per ADR-0201 dec. 10). It does **not** carry a single active
  `special_name`.

- **`_deploy_owned_units` → `_spawn_owned_unit` is the seeding seam.** It selects
  the version active for the current story context and stamps its `special_name`
  onto the unit **one line before `resolve()`** — mirroring the *shape* (not the
  source) of the ENTD seam. The resolver stays a pure function of the stamped
  param; it never reads story context.

- **Absence-from-Form-set == job-route.** A unit with no unique Form here misses
  and routes to its `(job, gender)` sprite — which is exactly correct for
  generics. One mechanism gives Ramza his sprite *and* portrait (the dialogue
  box runs the same `resolve()` for the speaker face) and keeps his squadmates
  generic. "Has a Form here" is the definition of "is a unique here."

- **Identity stays context-free; the deploy seam owns every per-battle fact.**
  Form (per chapter), deploy tile (per map), and event-tag (per scene) are the
  same *kind* of fact and are all resolved at deploy — never stored on the slug.
  The `slug` remains the sole cross-system identity; `special_name`, the event
  `uid`/`units_by_id` tag, and the combat buffer-slot are context-local handles,
  kept working now and deprecated toward slug-resolution in a later refactor.

## Considered and rejected

- **Durable `special_name` on the minted `Character`** (`c.special_name = 1`).
  Rejected: models a *per-context* fact as durable identity; correct only while
  Ch1 is the sole reachable chapter, silently wrong thereafter, with no re-stamp
  path for a persist-and-redeploy unit. This is the patch the design session was
  convened to avoid.
- **Decode the Form from event opcodes.** Rejected: the Form is not hiding in
  event scripts — it is the ENTD `special_name` the battle data already records.
  Decoding opcodes invents work for data we already have.
- **A separate scenario-keyed side-car consulted at deploy** (`(scenario, slug)
  → special_name`). Rejected *for now*: it scatters identity back out of the
  Catalog hub. This is the shape the later deprecation refactor adopts; today the
  Form set lives on the `Character`.
- **Route the event-tag (`units_by_id[0x01]`) through `SlugBinding` in this
  slice.** Rejected: orthogonal to the appearance bug (the tag finds the *node*;
  the Form picks the *sprite*), already works, and is on the deprecate-later
  handle pile.

## Consequences

- The fix is one stamp at the deploy seam plus a Form set on the unique
  `Character`; `resolve()`, the residue manifest, and the ENTD path are
  untouched. Body sprite and dialogue portrait are fixed together.
- A new (small) seed surface: a unique `Character`'s Form set, ROM-derived,
  hand-authored for the Ch1 spine in the shape a future transform will emit.
- The story-context → active-Form selection is stubbed while no chapter state is
  reachable (Gariland → the sole Ch1 Form); the seam is built to *select*, so
  Ch2+ drops in without reshaping it.
- Out of scope: the victory-beat occlusion (Ramza behind the central house) is a
  positioning/framing concern (deploy tile × ADR-0077 real-Z), not identity.
