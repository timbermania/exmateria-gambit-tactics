# One durable unit representation: `UnitProgression` is a `Resource` the roster shares with the live `Unit`

A unit's durable stats existed in [two parallel representations](../context/03-unit-roster.md):
`UnitProgression` (a `Node`, the live in-scene component) and the
progression-mirroring fields of `UnitRosterData` (a `Resource`, the
persistent save form). `UnitRosterData` even commented its block
"Progression (mirrors `UnitProgression`)". The two were kept in step by a
hand-written field-by-field copy in both directions — `Roster`'s
`_sync_progression_from_roster` (data → live, ~15 fields) on spawn and
`update_unit_from_combat` (live → data) after combat. The split existed
for one reason only: a `Node` is bound to scene lifetime and cannot
persist across scenes, while the roster autoload needs something that
outlives a battle. Nothing about progression actually required a `Node`
(its only `Node` usage was a trivial lazy-init `_ready`; its signals work
on a `Resource`). We remove the second representation: `UnitProgression`
becomes a `Resource`, a roster entry **holds** one and the live `Unit`
**shares the same object by reference**, so the mirror and both copy
directions cease to exist.

## Status

accepted

## Considered options

- **Collapse to one representation (chosen).** `UnitProgression extends
  Resource`. `UnitRosterData` drops its ~15 mirrored stat fields and
  instead composes a `progression: UnitProgression` (alongside identity
  and gambits). `Roster.spawn_unit` binds `unit.progression =
  entry.progression` — by reference, no copy. Mutating progression in play
  (equip, learn, level) mutates the persistent object directly, so
  persistence needs no hydrate and no writeback. Chosen because it deletes
  the friction at the root rather than automating it.
- **Schema-driven copy (rejected).** Keep both representations but drive
  the bidirectional copy from one `PROGRESSION_FIELDS` table (the
  [ADR-0002](0002-unit-state-snapshot-stays-string-keyed.md) /
  [ADR-0003](0003-unit-encode-is-a-single-looped-schema.md) "one looped
  schema, can't drift" move). Kills the *maintenance* and drift, but the
  live copy between two coexisting in-memory objects remains — the actual
  thing we wanted gone.
- **Backing store (rejected).** `UnitProgression` stays a `Node` but reads
  and writes a bound `UnitRosterData` it holds, so there is one field
  store and no copy. Avoids the `Node→Resource` change but leaves a
  `Node`-holding-a-`Resource` shape and redirects every internal field
  access; more churn inside `UnitProgression` for a worse object model.
- **Status quo (rejected).** Two representations plus the hand-written
  copy. This is what [ADR-0004](0004-rosters-share-a-base-script.md)
  concentrated into one `BaseRoster` method and deferred; see below.

## Consequences

- **Resolves the leak ADR-0004 deferred — by deletion, not by a seam.**
  ADR-0004 moved the `prog.raw_hp = data.raw_hp` writes verbatim into one
  `BaseRoster` method and left deepening them to "a later Unit-mutation-
  interface change." That change is now moot for the *bulk* path:
  `_sync_progression_from_roster` and `update_unit_from_combat` are
  **deleted** (the latter had only debug-panel callers, removed too).
  Sealing the *discrete* interactive mutations (UI/tester equip/learn/job)
  behind `Unit` methods remains worthwhile but is a separate, smaller
  follow-up — no longer load-bearing, since those edits now persist
  automatically by hitting the shared object.
- **Roster stops being a copy-bridge.** `spawn_unit` binds the entry's
  progression to the `Unit`; `configure_spawned_unit` no longer hydrates.
  Equipment defaulting (job-default weapon when unset) moves into
  `create_default`, seeding the persistent progression once at creation
  rather than re-applying on every spawn. Per-spawn work shrinks to:
  bind progression, bind the shared gambit list, derive the runtime
  equipped-ability component from the job skill set (this stays — it is
  derived, not durable), init `UnitStats` from progression, reset current
  HP/MP to full.

- **Gambits use the same shared model.** A unit's `GambitList` is
  `RefCounted` (scene-independent, like the progression `Resource`), so the
  roster entry holds it and binds it to the live unit by reference. The
  gambit editor mutates it in place, so edits persist with no writeback —
  the same reason progression needs none. Only the flat-JSON boundary maps
  `GambitList` ↔ array (`to_array`/`from_array`). It is a plain `var` (not
  `@export`) on the entry because `RefCounted` types are not exportable.
- **Standalone (non-roster) units keep a mint path.** `ProgressionTester`
  instantiates a `Unit` directly and still calls
  `initialize_with_progression(base_stat_type, job_id, team, level)` to
  *create* a fresh progression. The collapse adds a bind path for roster
  units; it does not remove the create path for standalone ones.
- **Aliasing invariant: one live `Unit` per roster entry at a time.**
  Sharing by reference is correct because each roster index is spawned at
  most once per scene (`GPUArena`, `CombatUITestScene`). If a future flow
  needs the same entry in two live units simultaneously, it must
  `entry.progression.duplicate()` — binding-by-reference is deliberate
  sharing, not accidental.
- **Signal lifecycle must be cleaned up.** The progression now outlives
  the `Unit`, so the `Unit` connects to its signals on bind and
  **disconnects in `_exit_tree`**; the previous free-lambda connection
  (`stats_changed`) becomes a bound method so Godot's auto-disconnect on
  receiver-free also applies. Otherwise a freed unit's handlers would fire
  on the persistent resource.
- **Save format unchanged on disk.** `UnitRosterData.to_dict`/`from_dict`
  keep emitting and reading today's flat JSON schema (`raw_hp` at top
  level), mapping to/from the nested `progression` at the serialization
  boundary. Existing `user://roster.json` / `enemy_roster.json` keep
  loading — no migration. This boundary mapping is object↔disk
  serialization done once per save/load, not a live mirror between two
  in-memory objects, so it is not the friction this ADR removes.
- **GPU encode is unaffected.** `GPUBatchSimulator`'s `UNIT_CONFIG_SCHEMA`
  reads the live `Unit`'s progression accessor and methods
  (`get_weapon_power()`, effective-stat getters); those are preserved on
  the now-`Resource` `UnitProgression`, so ADR-0001/0003's encode path is
  untouched.