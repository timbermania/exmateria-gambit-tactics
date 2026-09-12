# ExMateria Catalogue

**Who exists.** A unit's durable identity, the live slug-keyed registry that holds
them, the ROM name and birthday tables, the identity-to-template resolver, and the
two seeders that build a roster. **Extraction #6** of the `godot-learning` refactor
— selected at [ADR-0257](../../docs/adr/0257-a-debug-panel-is-not-a-member-and-the-order-that-counted-it-as-one-is-an-artefact.md),
audited at [ADR-0262](../../docs/adr/0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md),
moved here at [ADR-0267](../../docs/adr/0267-the-catalogue-lands-and-the-ninth-published-name-was-a-symbol-census-that-could-not-see-a-path.md).

**Ten members, 1,673 lines, six directories.** Plus the façade, `plugin.gd` and the
install port, which are addon files and not members — that distinction is what
`tools/test_arm7_membership.py` pins, and it is why the classifier books
**sixteen** files here while the membership is ten.

| directory | files | what it is |
|---|---:|---|
| `identity/` | 4 | `Character` (the durable record, 499 lines), `SlugBinding`, and the two ROM tables `UnitNames` / `UnitBirthdays` with their JSON |
| `registry/` | 1 | `CharacterCatalog` — the live registry, and the addon's one autoload |
| `templates/` | 2 | `CharacterTemplateResolver` (identity → sprite template) and `ResidueManifest` over `template_residue.json` |
| `seeding/` | 2 | `AllTemplatesSeeder` (build a roster from the template store) and `CatalogueReplay` |
| `inspection/` | 1 | `RosterDebugView` — a debug *helper*, deliberately **not** a `BaseDebugPanel` |
| `install/` | — | `CatalogueContent`, the host content port. Not a member; see below |

## The one global name

`ExMateriaCatalogue`, and nothing else ([ADR-0212](../../docs/adr/0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md)
dec. 1). Godot has no package scope — a `class_name` is engine-global, so every one
an addon declares lands in *your* project's global scope. Everything here is a
constant on that one name, and `tools/check_addon_globals.py` holds both directions:
nothing else in this addon may declare a global, and nothing published may dangle.

| published | what it is |
|---|---|
| `ExMateriaCatalogue.Character` | the durable identity record — slug, name, birthday, job, the template binding |
| `ExMateriaCatalogue.SlugBinding` | the slug ⇄ ROM-id binding |
| `ExMateriaCatalogue.UnitNames` | the ROM name table, over `identity/unit_names.json` |
| `ExMateriaCatalogue.UnitBirthdays` | the ROM birthday table, over `identity/unit_birthdays.json` |
| `ExMateriaCatalogue.CharacterCatalog` | the registry **script** — see the warning below |
| `ExMateriaCatalogue.CharacterTemplateResolver` | identity → sprite template |
| `ExMateriaCatalogue.ResidueManifest` | the template residue manifest |
| `ExMateriaCatalogue.CatalogueReplay` | replay a mutation script into a catalogue |
| `ExMateriaCatalogue.AllTemplatesSeeder` | seed a roster from the template store |
| `ExMateriaCatalogue.RosterDebugView` | the roster inspection helper |

Alias any of them back if you want the bare spelling ([ADR-0211](../../docs/adr/0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md)
dec. 4):

```gdscript
const Character = ExMateriaCatalogue.Character
```

An alias is a **per-class** declaration, not a per-file one — a script extending one
that already aliases the name must not repeat it, or the parse error takes the whole
child out.

### 🔴 `CharacterCatalog` is published, and that is NOT how you reach the registry

The tenth entry is the **script**, published for the two callers that want a *fresh,
empty* catalogue rather than the live one. The live registry is the autoload, reached
by its name or by node path:

```gdscript
var live := get_node_or_null(^"/root/CharacterCatalog")   # the roster
var scratch := ExMateriaCatalogue.CharacterCatalog.new()  # an empty one, for tests
```

Publishing it was found late and by a different instrument than the other nine: a
symbol census over the members counts `class_name` declarations and **cannot see a
`preload` path**, so it read nine. Re-reading the host preloads found the tenth. If
you are counting this surface, count paths as well as names.

## Install

Copy `addons/exmateria_catalogue/` into your project's `addons/` and enable the
plugin. Unlike most addons here, **there is an install step**: `plugin.gd` registers
one autoload.

```
CharacterCatalog → res://addons/exmateria_catalogue/registry/CharacterCatalog.gd
```

It is registered by the plugin rather than left to you because a registry has to be a
singleton and this addon's own files reach `/root/CharacterCatalog` by node path — so
the *name* is load-bearing. If you would rather declare the `[autoload]` line
yourself (to control autoload order, as `godot-learning` does), do — `plugin.gd`
tests `has_setting` first and will not duplicate it, and removes on the way out only
what it added. Use **that name**.

`plugin.cfg` declares `engine="stock"` and
`deps="exmateria_almanac exmateria_platform exmateria_schema"`. The deps are
**measured, not assumed** — `check_addon_portability.py` arm 5 reports **43 lines over
those three roots** (`exmateria_almanac` 30, `exmateria_schema` 7,
`exmateria_platform` 6) — and all three must be staged for this addon to parse alone.
Since #1241 that correspondence is ENFORCED, not just recorded: arm 8 fails in both
directions — a sibling reach `deps=` does not name, and a name `deps=` carries that
nothing reaches (#1239's defect). Arm 8b prints the `stock` above beside the binary the
rig actually boots, which is the closure's **fork**, and registers the divergence.

`exmateria_sprite_rig` was in that list and was **dropped at #1239**, having reached
nothing since #1071 (ADR-0272) paid its one edge by deleting the key. Arm 5 reports 0
rows and 0 lines onto `ExMateriaSpriteRig`; the mentions left in this package are
comments about shared texture trees, not a parse-time need. The engine the rig boots is
the **closure's**, not this addon's, so note that the drop did not change it only
because `exmateria_schema` is `fork` too.

## Content the host must supply

**This addon ships four JSON payloads and no art.** The four that travelled with it —
`identity/unit_names.json`, `identity/unit_birthdays.json`,
`templates/template_residue.json`, `seeding/template_jobs.json` — are ROM-derived
tables that are small, tracked, and beside the file that reads them
([ADR-0251](../../docs/adr/0251-the-almanac-is-thirty-two-names-behind-one-and-the-address-collapsed-while-the-buckets-did-not.md) dec. 2). You
do not have to do anything about those.

**Two content trees could not travel, and you supply them.** Both fail the same test —
`git check-ignore` names them and `git ls-files` does not — so "move them into the
addon" was never available:

| tree | what it is |
|---|---|
| `characters/templates/` | the ROM-derived character template store, emitted by the #201 character-alignment transform |
| `sprites/textures/` | the flat body sheets, shared with `exmateria_sprite_rig` and five host files |

Point the addon at the directory holding them with one `project.godot` line
([ADR-0202](../../docs/adr/0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 5):

```ini
[exmateria_catalogue]

content_root="res://assets/"
```

🔴 **The default is empty on purpose.** A default of `res://assets/` would leave that
literal inside an addon file — the portability arm that scores host-path reaches
would still count it, and the fix would be booked into the bucket it drains
([ADR-0167](../../docs/adr/0167-the-mount-inverts-to-the-host-and-the-fix-was-booked-into-the-bucket-it-drains.md)).
It would also re-create the failure ADR-0202 dec. 5 names: a bare project silently
resolving paths that do not exist and loading nothing. Empty means
`install/CatalogueContent.gd` refuses **once**, in words that name the setting.

With no root declared the addon loads and runs; the formation catalogue view lists
nothing and the roster seeds no sprites.

## What is deliberately NOT published

- **`install/CatalogueContent.gd`** — it is the seam a *host* configures through
  `project.godot`, not a symbol a caller uses. Publishing it would give one binding
  two spellings.
- **`plugin.gd`** — an editor entry, and `infrastructure` to the classifier.

## Known debt

- ~~**One arm-1 line.**~~ **PAID at #1071 (ADR-0272).** This addon now reaches no
  system at all: `ARM1_BURN_DOWN` is empty again. It was
  `templates/CharacterTemplateResolver.gd` calling `job_body_palette_row(job)` on
  `ExMateriaSpriteRig`, carried as a named row because severing it *by inlining*
  would have made a second home for a rule the rig centralises, and a behavioural
  change must not ride inside an address move (ADR-0167). It was paid by neither
  inlining nor the injected port this line used to promise: the resolver simply
  **stopped answering** `body_palette_row`. It was a render fact the resolver
  fetched from the rig and passed through, and both consumers already held the
  `Character`, so they ask the rig themselves. The rule still lives in one place;
  the edge is gone; no port exists to maintain.
- **13 arm-5 DEBT lines onto `exmateria_almanac`**, the end of the arc
  **55 → 53 → 36 → 13**. ADR-0262 dec. 5 accepted 55; the tree read 53 the same day
  because #1071 had already paid the `exmateria_sprite_rig` row (ADR-0272).
  **#1059 phase 2 (ADR-0273) paid 17 of them and could not pay the rest**, and which 17
  is the whole content of that decision: free-ness inside the `rules` tier is asked of
  the MEMBER, against the kind the almanac's façade declares, so 15 lines naming
  `JobDatabase` and 2 naming `SpriteDatabase` are `table` reads — ADR-0115 dec. 4's
  content shadow, which every system is expected to cast — and moved into arm 5's free
  block, still printed as the install-time dependency they are. **Then #1180 (ADR-0294
  dec. 2) paid 23 more**, admitting `EquipSlot`, `BaseStatType` and `Zodiac` to the
  shared kernel as ADR-0118 dec. 1's twelfth schema row; reaching the kernel is free.
  *(This bullet read "36 … 32 `UnitProgression` and 4 `GambitList`" until #1239 —
  #1180 updated `plugin.cfg`'s arc and left the README on the pre-#1180 number.)*
  **The 13 that remain are 9 `UnitProgression` and 4 `GambitList`, both declared
  `state`, and they are not a free-set question at all** — every one HOLDS or
  CONSTRUCTS the object rather than spelling a value. ADR-0241 dec. 1 already ruled
  `UnitProgression` *this addon's* by ownership and dec. 3 ruled that it does not
  split, and ADR-0271 soft spot S4 names both as members that pass the almanac's own
  purity predicate by its letter and fail it by its intent. They were to be paid by a
  MOVE — **#1059 phase 3** and **#1060** — and BOTH moves are now refused: ADR-0280
  dec. 2 rules `GambitList` costs 4 and pays 9, and **ADR-0300** rules
  `UnitProgression` retires 9 and pays 10 with a seventh reach
  (`BaseStatsDatabase`) that has no published name at all. **ADR-0280 dec. 6 rules
  this remainder the accepted price and not a countdown** and ADR-0300 dec. 6 names
  **13 as the floor**, so a pass that drives it to zero argues against two standing
  rulings rather than merely implementing something.
- **`src/debug/RosterViewDebugPanel.gd`** was dead and stayed in the host
  (ADR-0262 dec. 8). **#1070 deleted it.** It declared a `class_name`, was named by
  no `CombatPanelCatalog.register_panel` pair and constructed nowhere, and its knobs
  were unaffected because `UICombatManager` owns them (ADR-0068 decision 12).
  `classify_blueprint.py`'s `("Roster", "Character Catalogue")` DEBUG_OWNER fragment
  **stays** — its remaining subject is `RosterUniverseDebugPanel.gd`, which no
  `DEBUG_EXACT` row names.

## Design

`docs/adr/0267`, `docs/adr/0262`, `docs/adr/0257`, `docs/adr/0212`, `docs/adr/0211`,
`docs/adr/0202`.
