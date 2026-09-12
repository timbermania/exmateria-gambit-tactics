---
status: accepted
---

# "Owned" is a catalogue overlay; unit class is derived per-battle

Extends [ADR-0066](0066-character-identity-is-a-slug-catalog-above-the-roster.md) (the Character
Catalog is the master registry of who-exists) and
[ADR-0201](0201-battle-cast-is-a-replay-derived-view-of-the-catalog.md) (the battle
cast is a replay-derived view; "battle creates nothing").

## Context

The roster-fed battle (wayfinder #234 — clear Gariland from the player's current
roster) needs to answer two questions ADR-0066/0073 left open:

1. **Which units does the player own** (the persistent, deployable subset), as
   distinct from *which units exist at this game-state* (the catalogue — which
   also holds guests like Delita and per-battle enemies)?
2. **What is a unit's class** (player / guest / enemy) at a given battle?

The code was the **inverse** of ADR-0066/0073: `PartyRoster`/`EnemyRoster` were the
persistent serialized store and `CharacterCatalog` was a derived index promoted
*from* them, under positional `party:N`/`enemy:N` slugs (identity = slot — the bug
ADR-0066 dec.4 already ruled out). There was no model for "owned" separate from
"exists," and no model for class beyond the ENTD `team_color`.

## Decision

**Owned membership is a catalogue-internal overlay, and class is derived per-battle
from owned-membership × team_color — never stored.**

- **The catalogue is the one population.** `CharacterCatalog` (`slug → Character`)
  remains the only place `Character` objects live (ADR-0066). The battle cast is a
  transient view over it (ADR-0201).

- **`_owned_order: [slug, …]`** is a catalogue-internal overlay — the *persisted
  player layer* (ADR-0201 §8) — surfaced as queries: `add_owned` / `remove_owned` /
  `is_owned` / `owned_slugs` / `owned_units` / `set_owned_order`. Deploy order = list
  order. It is **not** a field on `Character` (that would couple the player layer onto
  catalogue existence and re-pack order on every mutation). Catalogue membership ≠
  owned membership: Delita is catalogue-yes / owned-no.

- **Class is derived, never stored.** `classify(slug, team_color)` → `player` (owned)
  / `guest` (Blue, not owned — Delita) / `enemy` (else). Only the raw inputs persist
  (`team_color` from the ENTD, owned-membership from the overlay). It is a per-*context*
  role, so the same identity can be a guest here and a party member elsewhere. Class is
  a **view-layer** label (the formation view badges rows by it); the engine team split
  stays binary (`EntdBattle.team_of` — Blue vs rest, the single reopen hook for any
  future N-faction work).

- **The overlay is seeded by the mutation fold, cleared on reset.** For the navigator
  proof the owned set is established by a `create`/`join` delta carrying `own: true`
  ([CatalogueReplay]) — so a story guest (Delita) joins the catalogue *without* being
  owned, while the Gariland roster seed marks its 5 units owned. `reset_to_new_game`
  clears `_owned_order` so a re-seek re-establishes it from the re-folded script
  (keeping the ADR-0201 "before beat *i*, state == fold(0..i-1)" invariant honest for
  the owned layer too).

## Consequences

- The battle seam composes `team0 = deployed-owned ∪ ENTD-blue`, `team1 =
  ENTD-non-blue` (`EntdBattle.compose_teams`); Orbonne is the degenerate empty-owned
  case, unchanged.
- The formation view and deployment both read `owned_units()` (Delita correctly absent).
- **Deferred (fog):** the general minted-uid scheme for generics (the Gariland seed
  uses stable authored slugs); full player-authored stat-diff save/load of the overlay
  (it is *seeded* for the proof — ADR-0066 dec.10's `instance = template + diff` already
  defines the shape).
- **Not done on this branch:** the dissolution/deletion of `PartyRoster`/`EnemyRoster`/
  `BaseRoster` and the rewire of their ~15 consumers (incl. the GPUArena main scene).
  The overlay is *additive* here; the dissolution is a separate, higher-blast-radius
  cleanup leg tracked apart from the Gariland proof.
