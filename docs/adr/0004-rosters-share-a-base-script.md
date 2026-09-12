# Party and enemy rosters share a `BaseRoster` script and stay two autoloads

> **PARTLY SUPERSEDED by [ADR-0180](0180-the-rosters-are-retired-and-the-arena-boots-a-real-battle.md)**
> (2026-08-25). The **roster decision** is dead: `PartyRoster`, `EnemyRoster` and
> `BaseRoster` are deleted, so there is no base to share. The player population is the
> Character Catalogue's owned overlay; the enemy population is the ENTD.
>
> **The "extend by path, not by `class_name`" decision below is NOT superseded.** It is
> a host-wide convention cited by 95 files across 8 systems, and its reason — a
> newly-added `class_name` script is invisible until Godot's global class cache is
> rebuilt — has nothing to do with rosters. Keep it.

The party and enemy [rosters](../context/03-unit-roster.md) were two autoloads
(`PartyRoster.gd`, `EnemyRoster.gd`) whose spawn / progression-sync /
equip / ability-setup / save-load / post-combat-writeback bodies were
near-character-for-character identical. The handful of real differences
were the save path, the log prefix, the `create_starter_roster()` body,
and enemy-only level-on-create. The duplication had no locality: a fix to
`_sync_progression_from_roster` or `update_unit_from_combat` had to land
twice or the two would drift, and a third copy of the FFT growth formula
(`EnemyRoster._grow_stat`) had already diverged from the canonical
`StatCalculator.grow_stat`. We collapse the shared implementation into one
`BaseRoster` script that both rosters extend.

## Status

accepted

## Considered options

- **`BaseRoster` base script, keep two autoloads (chosen).** `BaseRoster`
  (a plain `extends Node` script, extended by path — see Consequences)
  holds every shared method; `PartyRoster.gd` / `EnemyRoster.gd` extend it
  and remain the registered autoloads. Subclasses express their differences through
  virtual dispatch — `_save_path()`, `_log_prefix()`, and an abstract
  `create_starter_roster()` the shared `_ready()` (load-or-create) calls.
  Call sites are **unchanged**: every consumer still says
  `PartyRoster.spawn_unit(...)` / `EnemyRoster.get_unit(...)`. Chosen
  because it gives the shared logic one home with zero blast radius across
  the ~5 call sites (`GPUArena`, `CombatUITestScene`, `UICombatManager`,
  `ProgressionDebugPanel`).
- **One `Rosters` autoload composing two `Roster` instances.** A single
  autoload exposing `.party` / `.enemy`, each a plain `Roster` object
  (no `Node`, no autoload-per-side). The cleaner object model — a roster
  is data, not an engine singleton — but it rewrites every call site from
  `PartyRoster.x` to `Rosters.party.x`. Rejected: the call-site churn buys
  no behavior, and access-by-autoload-name is this project's established
  pattern for persistent singletons.
- **Leave the duplication; dedup only the obvious bodies.** Rejected: it
  leaves the growth-formula copy and the writeback twins live, which is
  the drift this collapse exists to kill.

## Consequences

- **Subclasses extend `BaseRoster` by path, not by `class_name`.**
  `PartyRoster` / `EnemyRoster` say `extends
  "res://src/roster/BaseRoster.gd"`, and `BaseRoster` itself omits
  `class_name`. A first cut gave `BaseRoster` a `class_name` (to be a
  resolvable supertype), but a game-mode run then failed at autoload parse
  with *"Could not find base class BaseRoster"*: a newly-added
  `class_name` script is invisible until Godot's global class cache is
  rebuilt in the editor, and deleting the cache file does not suffice (a
  documented project gotcha). Path-based `extends` resolves the supertype
  directly with no cache dependency, so a fresh checkout runs headless
  without an editor round-trip. No caller references a `BaseRoster` type —
  every consumer uses the `PartyRoster` / `EnemyRoster` autoload names —
  so the global symbol bought nothing to offset that fragility.
- **This pass is a behavior-preserving collapse only.** The moved
  `_sync_progression_from_roster` / `_equip_starting_gear` /
  `update_unit_from_combat` keep writing `UnitProgression` internals
  verbatim (`prog.raw_hp = data.raw_hp`, `prog.equip_item(...)`). That leak
  — `Roster` and UI reaching *past* `Unit` into `UnitProgression` — is
  deliberately **not** addressed here; collapsing it into one `BaseRoster`
  method is precisely what concentrates it into a single place for a later
  `Unit`-mutation-interface change to deepen. One refactor at a time.
- **The growth formula stops being triplicated.** `EnemyRoster._grow_stat`
  is deleted in favor of `StatCalculator.grow_stat` (already used by
  `UnitProgression.level_up`), so the persistent-data level-up
  (`_level_up_unit`) and the live-progression level-up share one formula.
  `_level_up_unit` itself stays in `EnemyRoster` — it is the only caller,
  and party has no level-on-create need, so promoting it to `BaseRoster`
  would be a hypothetical seam, not a real one.
- **The write-only `roster_source` meta is dropped.** It was set by
  `EnemyRoster.spawn_unit` and read nowhere; `roster_team` already carries
  a unit's side. Removing it makes `spawn_unit` fully shared, with no live
  behavioral difference between the two rosters' spawn paths.
- **`save_to_file` / `load_from_file` default-arg shape changes.** The
  old `path: String = ROSTER_SAVE_PATH` used a per-subclass `const` as a
  default; a `const` cannot reference the overridable `_save_path()`, so
  the signature becomes `path := ""` and resolves to `_save_path()` inside
  when empty.
