# Unit roster

The vocabulary for a unit's durable state and the live node that fights.
There is **one** durable representation of a unit's stats — see
`UnitProgression`; the live node holds a *reference* to it, not a copy. See
ADR-0005. The per-side collection that used to own them across battles is
**retired** — see the two entries below and [Roster (retired)](04-character-catalog.md);
durable ownership is the [Character catalog](04-character-catalog.md)'s.

**Unit**:
The live, in-scene node (`src/units/Unit.gd`) that fights: sprites,
animation, `UnitStats`, equipped-ability component. Exists only while a
battle (or test scene) is loaded. It **references** a `UnitProgression`
(by reference, it does not own a private copy) for the unit's durable
stats; transient combat state (current HP/MP, status, position) lives on
`UnitStats` / the GPU buffer, not in the progression. `Unit` is also the
**interactive mutation surface** for that progression: in-play equip /
learn / job changes go through `Unit` methods, never by reaching past it
into `UnitProgression` (see ADR-0007). Creation-time *seeding* of a fresh
progression (a roster minting its starter brave/faith, default weapon,
starter abilities) is the exception — it writes the `UnitProgression`
`Resource` directly, before any live `Unit` exists, the same construction
boundary `to_dict`/`from_dict` occupy.

**UnitProgression**:
The single durable representation of a unit's stats — level, raw stats,
current job, job levels/JP, equipment, learned abilities, equipped
ability slots, brave/faith. A `Resource` (not a `Node`), so it outlives
any one scene and serializes itself. The **same** object is held by a
roster entry and by the live `Unit` spawned from it; mutating it in play
(equip, learn, level) is therefore persistent with no copy-back step.
_Avoid_: "stats" alone — `UnitStats` is the live combat-state component
(current HP/MP, team), a different thing.

**UnitRosterData** (retired):
The persistent **roster entry** — a unit's identity (name, gender, derived
sprite) plus the `UnitProgression` and `GambitList` it shared by reference with
the live `Unit`, and the save-file shape of `user://roster.json`. Retired with
the collection that held it (ADR-0180); the durable record a unit *is* is a
[Character](04-character-catalog.md), and its progression is reached through that.
ADR-0066 had already called retiring this "deferred" — ADR-0180 is when it came
due.
_Avoid_: reintroducing a flat per-side save entry beside `Character`; reading
`user://roster.json` (orphaned).

**Spawn seam**:
The one operation that turns a durable [Character](04-character-catalog.md) into a live
`Unit`, and the one place that knows how — `UnitSpawn` (`src/units/UnitSpawn.gd`):
`build(character)` instances the scene, resolves the visuals through the ONE
template resolver seam and stamps the `character_slug` meta; `bind_for_combat(unit,
character, team)` shares the `UnitProgression` and `GambitList` by reference and
seeds the job's starter abilities. Named for what it does, not for who calls it —
it used to be `BaseRoster.spawn_unit(index, team)`, keyed by a **roster index**,
which is why the story path (which has no roster to index) carried a second copy and
the ENTD path a third. Re-rooted on the Character by ADR-0180, all three collapse.
The per-host TAILS stay at their call sites and are not part of the seam: the arena
tops HP/MP up, the navigator stamps the active [Form](04-character-catalog.md)'s
`special_name` before resolving, initializes the logical tile and holds the clock at
`SCENARIO` until go-live.
_Avoid_: resolving a live unit back to its Character by `name` — Godot uniquifies a
colliding node name, so the display name is not an identity; `character_slug` is
(and is how `FormationMapHost.character_for_unit` answers).

**Roster** (retired — see [Roster (retired)](04-character-catalog.md)):
The per-side persistent collection (`PartyRoster` / `EnemyRoster` /
`BaseRoster`) that spawned live `Unit`s from its entries and persisted itself to
disk. ADR-0066 dec. 1 demoted it to "a selection/view over the catalogue"; the
code stayed the inverse — the roster **promoted itself into** the catalogue
under positional `party:N` / `enemy:N` slugs — until ADR-0180 deleted it. The
player side is now the [owned roster](04-character-catalog.md) overlay and the enemy
side is the ENTD.
_Avoid_: conflating the retired **Roster** with **Team** — a `Team`
(`UnitStats.Team.PLAYER / ENEMY`) is a unit's combat-time allegiance and is very
much live; what a unit *is* per battle is its [class](04-character-catalog.md),
derived, never stored.
