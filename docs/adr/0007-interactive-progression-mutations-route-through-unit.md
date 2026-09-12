# Interactive progression mutations route through `Unit`; creation-time seeding stays direct

[ADR-0005](0005-one-durable-unit-representation.md) collapsed the two unit
representations into one shared `UnitProgression` `Resource` and named a
follow-up: *"Sealing the discrete interactive mutations (UI/tester
equip/learn/job) behind `Unit` methods remains worthwhile but is a separate,
smaller follow-up."* This ADR records doing that follow-up — and **narrowing
it**, because looking closely changed what was worth sealing.

Two findings reshaped the scope:

- **The interactive seal is thin, not logic-concentrating.**
  `UnitProgression` already owns the mutating methods (`equip_item`,
  `change_job`, `set_sub_job`, `learn_ability`, `learn_ability_from_job`,
  `set_equipped_reaction` / `_support` / `_movement`, `level_up`) **and**
  emits a signal on each one that the live `Unit` already listens to
  (`equipment_changed` → `_on_equipment_changed` → `update_weapon_sprite`).
  So a `Unit.equip_item()` cannot concentrate either the rule (already on
  `UnitProgression`) or the side-effect (already fired by the signal,
  whoever calls the method). Its only payoff is a single discoverable
  mutation surface — callers say `unit.equip_item(...)` instead of
  `_get_progression(unit).equip_item(...)`.
- **The one real duplication was elsewhere.** `EnemyRoster._level_up_unit`
  re-implemented `UnitProgression.level_up()`'s growth loop verbatim — the
  exact drift class [ADR-0004](0004-rosters-share-a-base-script.md) fought
  when it deleted `EnemyRoster._grow_stat`. That, not the interactive path,
  was the locality win.

## Status

accepted

## Decision

Done as two commits:

- **Commit 1 — consolidate level-up.** `EnemyRoster._level_up_unit` now
  delegates to `UnitProgression.level_up()` (`for i in range(levels):
  data.progression.level_up()`), so the FFT growth formula lives in exactly
  one place. (Its signals have no listeners at roster-creation time, so the
  delegation is behavior-preserving.)
- **Commit 2 — route interactive mutations through `Unit`.** Thin `Unit`
  delegators (`equip_item`, `unequip_item`, `set_sub_job`, `learn_ability`,
  `learn_ability_from_job`, `set_equipped_reaction` / `_support` /
  `_movement`; `level_up` / `change_job` already existed) null-guard
  `unit_progression`, pass through to it, and return its bool. Callers
  `UICombatManager`, `UILearnPanel`, `ProgressionTester`, and
  `ProgressionDebugPanel` were repointed off `progression.x()` /
  `unit.unit_progression.x()` onto `unit.x()`.

## Considered options

- **Seal interactive mutations through `Unit` + consolidate level-up,
  leave creation-time seeding direct (chosen).** Names match
  `UnitProgression`'s so a reader greps one symbol across both files. Reads
  are *not* routed — they stay on `_get_progression()` and the existing
  `Unit` proxy properties (`level`, `job_id`, `job_name`); only mutations
  are sealed.
- **Also seal creation-time seeding behind a "mint" API** (`seed_personality`,
  `seed_learned`, `seed_equipment` on `UnitProgression`). Rejected as
  ceremony: `brave` / `faith` are plain value fields with no invariant to
  protect; the default-weapon write already lives **inside** the
  `UnitRosterData.create_default` factory (its construction home); and the
  starter-ability write is one localized helper. Wrapping them buys a "zero
  raw writes" purity target, not safety.
- **Reuse the interactive `equip_item` / `learn_ability` for seeding too.**
  Rejected: they validate against `ItemDatabase` (not guaranteed loaded at
  autoload-time roster creation) and `learn_ability` charges JP. Seeding is
  unconditional and free by design — `create_default` already bypasses them
  deliberately, with a comment saying so.
- **Interactive seal only, skip the level-up consolidation.** Rejected: the
  level-up duplication was the single change with real locality payoff.

## Consequences

- **Creation-time field writes are a construction boundary, not a leak.**
  `create_starter_roster`'s `progression.brave = …` / `faith = …`,
  `_learn_starter_abilities`' `learned_abilities[id] = true`, and
  `create_default`'s `equipment[slot] = …` stay direct on the
  `UnitProgression` `Resource`. They run before any live `Unit` exists, are
  unconditional, and need no signal (no listeners yet) — the same kind of
  boundary ADR-0005 already excused for `to_dict`/`from_dict`. **Future
  architecture reviews should not re-flag these as a leak to seal.**
- **One reach-through remains by design.** `EnemyRoster._level_up_unit`
  calls `data.progression.level_up()` directly: at roster-creation time
  there is no `Unit` to route through. This is the creation path, not an
  interactive mutation.
- **The interactive seal is intentionally thin.** `Unit.equip_item()` etc.
  are pass-through delegators. They centralize the *call surface*
  (discoverability, one symbol to grep), not logic or side-effects — those
  already live on `UnitProgression` and its signals. If a combat-legality
  rule (e.g. "no equipping mid-active-combat") is ever wanted, these `Unit`
  methods are now the seam that would own it.
- **Reads were left alone.** Routing the much larger read surface (job
  name, JP, learned set, equipped items) through `Unit` would be pure churn;
  consumers keep using `_get_progression()` and the existing proxy
  properties.
- **No save-format or GPU-encode impact.** Mutations end at the same
  `UnitProgression` methods as before; ADR-0001/0003's encode path and the
  flat-JSON serialization boundary are untouched.
