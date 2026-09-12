class_name ExMateriaCatalogue
extends RefCounted

## The whole public surface of `addons/exmateria_catalogue`, and the only name it
## puts in your project.
##
## Godot has no package scope: a `class_name` is engine-global, so every one an
## addon declares lands in YOUR global scope — and when you declare a colliding
## one, the ADDON's file is what fails to parse, pointing your error at a file
## you did not write. ADR-0212 dec. 1 answers that with one brand-prefixed name
## per addon, named after its folder; this file is that name.
##
## A script constant is a full type — annotation, `is` check, `.new()`:
##
##     var c: ExMateriaCatalogue.Character = ...
##
## and a consumer may alias one back to a bare local name, which is what keeps
## every existing use site spelled the way it was (ADR-0211 dec. 4):
##
##     const Character = ExMateriaCatalogue.Character
##
## **This list IS the supported surface.** If a script is not named here it is
## internal, whatever its visibility says — and `tools/check_addon_globals.py`
## holds both directions: nothing else in this addon may declare a global, and
## nothing named here may dangle.
##
## 🔴 TEN NAMES, AND `CharacterCatalog` IS THE ONE THAT ALMOST WAS NOT. The
## registry is an `[autoload]` (`registry/CharacterCatalog.gd`) reached by its
## autoload name in 63 host files, and an autoload needs no alias — it is already
## a global the host's `project.godot` declares. That is the install step this
## addon charges, and it is the same one `exmateria_platform` charges for
## `PSXDisplay` and `exmateria_sound` charges twice over (ADR-0262 dec. 6). It is
## published anyway, and the reason is TWO files, not sixty-three:
## `tests/CharacterCatalogOwnedTest.gd:13` and `tests/StoryMutationScriptTest.gd:32`
## each `preload` the script and `.new()` a FRESH catalogue, deliberately not the
## autoload, so the test owns its own universe. Without a published name those two
## would have to spell `res://addons/exmateria_catalogue/registry/...` in host code
## — the exact hole the alias route closes (ADR-0211 dec. 4), and the one
## `exmateria_platform`'s burn-down note calls "complete symbol close: zero host
## `.gd` files preload a `res://` path into this addon".
##
## ADR-0262 dec. 7 counted NINE. Nine is the count of names with a bare-identifier
## namer in the host; it missed these two because they reach the class by PATH and
## a symbol census cannot see a path. Ten is the published surface.
##
## Inside the addon the live node is reached by NODE PATH and never by the bare
## identifier — `registry/CharacterCatalog.live()` says why.
##
## 🔴 THIS IS THE SYMBOL SURFACE, NOT THE COUPLING SURFACE (ADR-0211 dec. 3,
## ADR-0212 dec. 4). Four JSON payloads travelled with this addon and are read by
## `res://addons/exmateria_catalogue/...` paths from INSIDE — no host file names
## one. TWO content trees did NOT travel, because they are ROM-derived and
## gitignored, and the host supplies them through
## `install/CatalogueContent.gd`'s `exmateria_catalogue/content_root`
## (ADR-0202 dec. 5). Neither axis is visible here.


## A unit's durable IDENTITY — slug, aliases, display name and name provenance —
## and the record a live `Unit` is spawned from (ADR-0066). The heaviest published
## name by namer count: 24 files outside this addon, over half of them annotating
## `-> Character` or `Array[Character]`.
## Host use: `src/scenarios/ScenarioCast.gd` builds one per ENTD slot;
## `src/units/UnitSpawn.gd` spawns from it; `src/ui3/formation/FormationScene.gd`
## renders the roster row; `tests/EntdBattleInitTest.gd` is its heaviest namer at
## 13 lines.
const Character = preload("res://addons/exmateria_catalogue/identity/Character.gd")

## The battle-local `(context, uid)` -> global `slug` binding, with the recorded
## coverage gap that makes divergence visible instead of silent (ADR-0201 dec. 6/7).
## Host use: `src/scenarios/NavigatorMain.gd` holds the live binding for the
## running battle; `tests/SlugBindingTest.gd` and
## `tests/RosterBindingIntegrationTest.gd` drive both the hit and the fallback arm.
const SlugBinding = preload("res://addons/exmateria_catalogue/identity/SlugBinding.gd")

## The FFT `special_name` -> canonical story name table — the battle-cast SOURCING
## KEY (decision #181): a slot that resolves here is a canonical story unit, one
## that does not is a factory-derived generic. Ships `identity/unit_names.json`.
## Host use: TEST-ONLY NAMER, and that is why it is published. ADR-0211 dec. 5
## rules a test-only host use a real host use; `tests/EntdBattleInitTest.gd` names
## it on 11 lines and `tests/AllTemplatesSeederTest.gd` once. `tests/` is not one
## of `classify_blueprint.WALK_ROOTS`, so the instrument that selected this
## membership could not see either namer (ADR-0262 dec. 7).
const UnitNames = preload("res://addons/exmateria_catalogue/identity/UnitNames.gd")

## The FFT `special_name` -> birthday (month, day) table behind a unique's zodiac
## glyph in the formation info panel. FFT stores no zodiac byte; the sign is
## derived from the birthday. Ships `identity/unit_birthdays.json`.
## Host use: TEST-ONLY NAMER, published on ADR-0211 dec. 5's rule for the reason
## above — `tests/ZodiacFromBirthdayTest.gd` names it on four lines and is the only
## file outside this addon that does.
const UnitBirthdays = preload("res://addons/exmateria_catalogue/identity/UnitBirthdays.gd")

## The persistent character universe — the `[autoload]` every host file reaches by
## its autoload name, published here for the two hosts that want a FRESH one
## instead (see the note above). A consumer that wants the running catalogue must
## keep using the autoload: this const is the SCRIPT, and `.new()` on it is a
## second, empty universe.
## Host use: `tests/CharacterCatalogOwnedTest.gd` mints its own to test ownership
## without the autoload's state; `tests/StoryMutationScriptTest.gd` does the same
## to replay a mutation script into a clean catalogue.
const CharacterCatalog = preload("res://addons/exmateria_catalogue/registry/CharacterCatalog.gd")

## The seam between a `Character` and its visual template (ADR-0072): the one place
## that maps `Character (identity + job) -> template key -> assets`, and part of
## neither the character nor the template.
## Host use: `src/ui3/formation/FormationScene.gd` resolves each catalogue row's
## sheet through it; `src/units/UnitSpawn.gd` resolves a spawning unit's;
## `tests/CharacterTemplateResolverTest.gd` is the dispatch's own guard at 20 lines.
const CharacterTemplateResolver = preload("res://addons/exmateria_catalogue/templates/CharacterTemplateResolver.gd")

## The unique <-> asset residue manifest (ADR-0072, #202) — the hand-authored bridge
## from a unique's ROM `special_name` to its owned template folder, and the single
## authority for "which special_names are unique". Ships
## `templates/template_residue.json`.
## Host use: `src/scenarios/ScenarioPlayerScene.gd` asks it whether a slot's
## special_name is a unique; `tests/ResidueManifestTest.gd` is its guard at 13 lines.
const ResidueManifest = preload("res://addons/exmateria_catalogue/templates/ResidueManifest.gd")

## The replay engine that turns a beat-keyed mutation script into catalogue
## membership (ADR-0201). Pure and scene-free; the catalogue it writes into is
## duck-typed, so the live autoload and a test fake take the same path.
## Host use: `src/scenarios/ScenarioCast.gd` folds a plan through it before booting
## a battle; `src/ui3/testing/CombatUITestScene.gd` seeds its cast the same way;
## `tests/CatalogueReplayTest.gd` is its guard at 13 lines.
const CatalogueReplay = preload("res://addons/exmateria_catalogue/seeding/CatalogueReplay.gd")

## Mints an owned `Character` per catalogue VARIANT — the roster behind the
## formation "show all templates" view (ADR-0081). Ships `seeding/template_jobs.json`
## and reads the host-supplied template store through `install/CatalogueContent.gd`.
## Host use: `src/ui3/formation/AllTemplatesFormationBoot.gd` seeds the view;
## `src/scenarios/PromotedRosterSeeder.gd` reuses its roster builder;
## `tests/AllTemplatesSeederTest.gd` is its guard at 17 lines.
const AllTemplatesSeeder = preload("res://addons/exmateria_catalogue/seeding/AllTemplatesSeeder.gd")

## The read-only VIEW-MODEL behind the two F3 ROSTER debug panels — pure functions
## over plain `Character` + `SlugBinding` inputs, so the panels stay dumb renderers
## and the row logic is unit-tested. The panels themselves stay in the host
## (ADR-0257 dec. 1) and reach the addon through this name and the `[autoload]`.
## Host use: `src/debug/RosterUniverseDebugPanel.gd` and
## `src/debug/BattleBindingDebugPanel.gd` render its rows;
## `src/scenarios/NavigatorMain.gd` raises them; `tests/RosterDebugViewTest.gd` is
## its guard.
const RosterDebugView = preload("res://addons/exmateria_catalogue/inspection/RosterDebugView.gd")
