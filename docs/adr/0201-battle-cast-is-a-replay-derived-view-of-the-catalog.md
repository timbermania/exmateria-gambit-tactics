# Battle cast is a replay-derived view of the Character Catalog; ENTD is a slug-binding manifest, not a factory

**Status:** accepted — first slice implemented (spec
[timbermania/fft-monorepo#185](https://github.com/timbermania/fft-monorepo/issues/185),
tickets #186–#191). The `CatalogueReplay.fold` pure module, the `SlugBinding`
resolver, the `NavigatorRunner` fold-before-dispatch invariant, the hand-authored
Chapter-1 `MutationScript`, and the battle read-path refactor all landed and are
guard-tested (`CatalogueReplayTest`, `SlugBindingTest`, `NavigatorRunnerTest`,
`Ch1MutationScriptTest`, `SeekIntegrationTest`) + verified headful via the F3
navigator seek (Orbonne comes up clean, Ramza catalog-bound, unbound cast falls
back). Deferred (edges, unlabeled): #192–#196 — cross-run seek (world-map
dispatcher §2.7), ROM-generated mutation data, player-authored save/overlay layer,
formation-screen view, and `leave`/`die` divergence.

**Builds on [ADR-0066](0066-character-identity-is-a-slug-catalog-above-the-roster.md):**
that ADR makes the `CharacterCatalog` the master of *who exists* and the
`slug` the cross-system identity key. This ADR gives the Catalog its first
real runtime customers on the navigator path — **replay writes it, battle
reads it** — and defines how a battle's on-screen units bind to it.

## Context

The game navigator walks the story graph and can **seek** to a beat
(`NavigatorRunner.begin_at(N)`). Today seeking *skips* beats `0..N-1`
entirely, and those skipped beats are the only thing that would populate who
exists — guests (Delita, Gafgarion), units that join the roster, ephemerals
that appear for one fight. The first battle (Orbonne) hides this: it is the
one encounter with zero upstream party state, so it just partitions the units
the scenario itself spawned (`NavigatorMain._start_entd_battle` reads
`_units_by_id`, keyed by ENTD `uid`). Every later battle depends on
**accumulated, path-dependent world-state** that seeking discards.

The catalog machinery from ADR-0066 exists (`register`/`get_character`/slug +
alias index) but has almost no customer on this path: `CharacterCatalog._ready`
seeds only `ramza`, and the sole scenario reader is `TypewriterController`
name-macro resolution. Both the scenario spawn and the battle build a
`Character` ad-hoc from the raw ENTD slot (`Character.from_entd_slot`),
neither routed through the Catalog. So identity is not shared between the unit
on screen, the name in dialogue, and the unit in combat.

## Decision

1. **The Catalog is the seekable object; the battle cast is a *view* of it.**
   The battle path stops treating "the units the scenario spawned" as the
   source of who exists and reads the Catalog. Persistence = "not removed by
   the script"; there is one population, added to and removed from.

2. **ENTD is a manifest, not a factory.** ENTD selects Catalog entries, forces
   positions, and opens player-deploy slots. It mints no identities. The
   character-builder factory is the sole creator of `Character`s ("battle
   creates nothing"); its output always lands in the one Catalog.

3. **Replay-derive is the mechanism, and it *is* the new-game forward path.**
   The Catalog at beat `N` is the fold of an ordered **mutation script** —
   authored `create` / `join` / `leave` / `die` deltas keyed to each beat.
   `create` mints an ephemeral via the factory; `join` promotes into the
   persistent Catalog; `leave`/`die` remove. Seeking and a real new game are
   two callers of one engine.

4. **Seek = reset → silent canonical replay → boot.** `begin_at(N)` resets the
   Catalog to new-game state, fast-replays deltas `0..N-1` **without booting a
   world, rendering, or simulating prior battles**, then dispatches beat `N`.
   `begin_at(0)` ≡ new game. Replay assumes **canonical battle outcomes** — it
   applies each prior beat's authored canonical deltas, it does not fight the
   battles.

5. **The fold rides the action plan; one invariant governs both paths.**
   `GameNavigator.plan_actions` emits each action with its `mutations`.
   Live `_advance` applies each beat's delta as it is reached; `begin_at(N)`
   bulk-folds the skipped ones. Invariant, provable for walking and seeking
   alike: **before beat `i` dispatches, `catalog == fold(0..i-1)`.**

6. **`slug` is the global identity; `uid` is a context-local handle.** The
   `slug` is the single join key across four systems — the Catalog entry,
   dialogue name macros, on-screen event units, and battle units. A binding
   resolver maps `(scenario/ENTD context, uid) → slug`. `uid` is *not*
   globally unique (a per-ENTD slot byte), so the mapping is always
   context-scoped; two battles' `uid 3`s resolve to different slugs.

7. **Binding has an escape hatch.** On a resolver **hit**, the battle pulls the
   Catalog `Character` (its replayed identity/progression flows in). On a
   **miss** (no slug, or slug unregistered), it **falls back** to constructing
   the `Character` from the raw ENTD slot exactly as today. The resolver
   **records fall-back slots** as an explicit, shrinking coverage gap — so the
   migration is safe and incremental, and divergence is visible, not silent.
   Named/special units bind first via `UnitNames.slug_of`.

8. **Fidelity is scripted-canonical only (this slice).** Replay reconstructs
   the *scripted* layer (guests, forced joins, ephemerals at scripted stats).
   The **player-authored layer** (recruited generics, chosen levels/jobs/
   equipment, gil, learned abilities) has no authored source to replay from and
   is a later save/overlay concern. Branch-gating flags are flattened: the
   canonical script simply says "at beat `N`, `join`," so no flag engine is
   required now.

9. **Scope is Catalog-only; reach is within-run.** The mutation script models
   unit ops only (an extensible op-list, so gil/items/flags become new op kinds
   later without re-architecting). The first slice covers the reachable Ch1
   spine (Orbonne → Military Academy); cross-run seek is bounded by the un-RE'd
   world-map dispatcher (`GAME_STATE_TRANSITIONS.md` §2.7) and falls out for
   free once that lands.

10. **Data is hand-authored now, ROM-generated later.** The Ch1 mutation script
    is authored by hand against existing ENTD/unit data, in the *same shape* a
    future generator (from RE'd ENTD join-flags + event opcodes) will emit.
    Swapping the source touches no engine or seam code.

## Considered options (rejected)

- **Snapshot/save as the seek mechanism.** Serialize the Catalog per beat and
  load the nearest. Rejected as the primary mechanism: the scripted layer is
  authored ROM data we must model anyway (it *is* the new-game path), and a
  save cannot exist before there is a game to save. Save/overlay returns later,
  for the *player-authored* layer only.
- **Synthesize a plausible party per beat.** A canned chapter-appropriate cast.
  Rejected: debug-only, no continuity, and it cannot grow into the real game.
- **Replay by simulating each prior battle.** Rejected: slow, and it reintroduces
  outcome-dependence the canonical assumption deliberately removes.
- **One registry holding every unit including anonymous enemies with churned
  slugs, vs. a factory + persistent-Catalog + battle-scoped session split.**
  Chose the single add/remove Catalog for simplicity; the factory is still the
  sole creator, and ephemerals are add-then-remove rather than a separate scope.
- **Bind battle units by `uid` alone.** Rejected: `uid` is context-local and
  collides across battles; only the `slug` is a global identity (ADR-0066 dec.4).
- **Route battle through the Catalog with no fallback.** Rejected: binding
  coverage is currently near-zero; a hard cutover breaks every unbound generic.
  The escape hatch makes coverage a dial, not a cliff.

## Consequences

- The Catalog gains its first real navigator-path customers: `CatalogueReplay`
  writes it, the battle bridge reads it. `TypewriterController` name resolution
  is unchanged and now shares identity with the units it names.
- `NavigatorMain._start_entd_battle`'s coupling to `_units_by_id` is removed
  incrementally; the fallback preserves today's behavior on a binding miss.
- The pure seams (`CatalogueReplay.fold`, the `NavigatorRunner` invariant, the
  `(context, uid) → slug` resolver) are unit-testable with no scene; the scene
  glue is verified headful, per the existing navigator convention.
- The F3 navigator "Seek here" becomes trustworthy: a later beat comes up with
  the scripted cast instead of an empty or hardcoded one.
- A new maintenance surface: the hand-authored Ch1 mutation script and the
  slug-binding coverage, both of which shrink toward ROM-generated data as the
  ENTD/event-opcode RE lands.

## Open questions

- The exact `(context, uid) → slug` binding-table schema and where it is
  authored (alongside the mutation script vs. derived from ENTD `special_name`)
  — an implementation detail to settle when the resolver is built.
- Whether `leave` and `die` need to differ at the Catalog level in this slice
  (both remove; distinction may matter only once the player-authored layer and
  permadeath land).
- The world-map dispatcher (§2.7) remains the gate on cross-run reach — tracked
  separately, not by this ADR.
