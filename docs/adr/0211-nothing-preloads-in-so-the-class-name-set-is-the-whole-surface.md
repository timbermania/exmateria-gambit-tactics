# Nothing preloads in, so the `class_name` set is the whole surface — and paying an arm-3 row feeds it

`exmateria_battlefield` declares **30** `class_name`s. Godot has no package scope, so all 30 are
engine-global registrations in a consumer's project, indistinguishable from the interface. **Zero
host files reach the addon by `preload` path.** Those two facts together mean the addon's symbol
surface *is exactly its `class_name` set* — which is why a façade closes it completely rather than
shrinking it, and why every cheaper option leaves the hazard behind.

Status: accepted (2026-08-30). Loop **pass 17** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Settles
[#717](https://github.com/timbermania/fft-monorepo/issues/717), the interface question
[ADR-0210](0210-a-stated-host-use-was-green-and-twenty-times-understated.md) filed rather than
answered, and unblocks [#716](https://github.com/timbermania/fft-monorepo/issues/716). Supplies the
missing payment route for
[ADR-0208](0208-a-published-name-pays-a-path-reach-and-the-cameras-static-reach-was-a-class-load.md)
dec. 2. Follows the shape the repo-root `docs/adr/0003-an-installed-addon-owns-five-global-names.md`
built for `exmateria_sound`. Rules the **symbol** axis only — see dec. 3.

## Context

### The headline number in the ticket is stale, and the way it moved is the finding

`#717` was filed saying **15** names are reached by nothing outside the addon. Measured by
`check_lattice_publish.py` on this tree: **17**.

| | count |
|---|---|
| `class_name`s in the addon | **30** |
| declared in `DECLARED_PUBLISHED` | **11** |
| named as a type from outside the addon | **13** |
| **named by nothing outside the addon at all** | **17** |

`PlayerCamera` and `MapStateSelector` are the two that moved, and they moved **because this branch
paid their arm-3 rows** (ADR-0210 dec. 3 and dec. 4). A name that stops being reached from outside
does not leave the problem — it crosses from *named but not declared* into *named by nothing
outside*, which is the population with no owner at all.

🔴 **Arm 3's target of 0 is a pump.** Every row it drains feeds the namespace population. The two
are not independent, and any ruling that treats them as independent is wrong on its own arithmetic.
That is the argument for settling the interface rather than paying rows.

One number in `#717` is **not** a delta and should not be read as one: its "named as a TYPE from
`src/`" is **9**, the register's "named as a type outside the addon" is **13**. Two scopes —
the register also counts `tests/` and `tools/`. Nothing moved there.

### Nothing preloads in, and that is what makes a façade sufficient

Measured across `src/`, `tests/`, `tools/`, `assets/`:

    preload()/load() of a res:// path into the addon, from a host .gd :  0
    the same, from inside the addon                                    : 30

Every host reach into this addon today is a `class_name`, a node path, or a `.tscn`
`path=`/`uid=`. There is no third symbol route. So deleting a `class_name` does not merely
discourage a coupling — it removes the only spelling by which one could be written. This is the
fact that separates this addon from a general case, and it is why dec. 2 buys a *complete* close
where `#717`'s option 2 buys a partial one.

### `#717`'s exemption argument rests on a distinguisher that is not one

Option 3 proposed ruling battlefield host-only, on the grounds that it "is the one addon with a
fork dependency (`engine="fork"`) and a `content_root` project setting." Measured across every
`plugin.cfg` in the monorepo:

| addon | `engine=` |
|---|---|
| `exmateria_battlefield` | `fork` |
| `exmateria_schema` | `fork` |
| `exmateria_render` | `fork` |
| `exmateria_platform` | `stock` |
| `exmateria_sound`, `exmateria_spu` | *(no line)* |

**Three addons declare `engine="fork"`.** The fork half of the distinguisher is false. The
`content_root` half survives — battlefield is the only addon that reads a host-declared project
setting (`ROOT_SETTING`). One leg, not two, and one leg does not carry an exemption from a rule
five registers are built on. See "Alternatives rejected".

### The alias route, measured — the migration is not the rename `#717` priced

`#717` priced option 1 as "a large mechanical rename … it changes every published spelling
(`Lattice` → `ExMateriaBattlefield.Lattice`), which touches ~50 `Lattice` references alone."
That is wrong twice. `Lattice` is **95** host references, not ~50 — and none of them has to change.

A consumer can alias a façade constant back into a bare local name. Probed against the *existing*
`ExMateriaSound` façade under the 4.8 fork, not reasoned:

    const SMDPlayer = ExMateriaSound.SMDPlayer
    var p: SMDPlayer = SMDPlayer.new()
    print(p is SMDPlayer)                         # -> true

Annotation, construction and `is` all resolve through the alias. So the unit of work is **one
`const` line per (file, name) pair**, not one edit per use site:

| | globals left | addon-internal `const` | addon-test `const` | host alias | arm 3 after |
|---|---|---|---|---|---|
| **façade (dec. 2)** | **1** | 90 | 13 | ≤82 | **0 by construction** |
| drop only the 17 | 13 | 48 | — | 0 | 3 names / 14 sites, unchanged |

Forty of the ≤82 host lines are `Lattice`. The façade is roughly 2.5× the work of the cheap option
and it is the only one of the two that ends the problem.

### Three hazards a rename of this size usually carries, all measured at zero

- **No `@export` property anywhere is typed with an addon class**, so nothing serialized into a
  `.tscn`/`.tres` depends on a `class_name` surviving.
- **No `.tscn`/`.tres` names one of the 30 by type.** Scenes reference scripts by `path=`/`uid=`;
  the 15 scene files that reach the addon are untouched by this migration.
- **No `@icon` and no `add_custom_type`.** No editor registration depends on a `class_name`.

### `MapComposer` is the case that shows why this ADR rules symbols only

`check_lattice_scene` reads criterion 4 at **0 sites**, burn-down empty, with three *declared
mounts* reported. `MapComposer` is one of them: `assets/scenes/ProceduralMap.tscn` names
`assembly/MapComposer.gd`, and ADR-0207 dec. 1 collapsed **115** direct host consumers into that
single mount.

So `MapComposer` reads **0** as a symbol and is simultaneously the addon's most-reached file by
path. `PlayerCamera` and `TileCursor` are the same shape through `CombatCamera.tscn` and
`CombatCursor.tscn`. ADR-0205 rules a path reach the *same axis* as a type reach — both are axis A
— and this ADR does not touch that axis. "Named by nothing outside" is a claim about **compiled
symbols**, and restating it as "nothing outside depends on these" is false for at least three of
the 17.

(ADR-0205's own Context measures **139** host path-sites, 115 of them `MapComposer`. That was true
on its tree; ADR-0207's mounts reduced it to 5 sites, 3 of them declared. The register carries the
current number, this ADR does not restate the old one.)

## Decisions

**1. The global namespace binds `exmateria_battlefield`. It is not exempt.** Axis B
(`check_addon_install`) reports **CLEAR, 0/0** and ADR-0202 named this addon installable. An
exemption would retract a shipped verdict and, worse, would leave `check_lattice_publish`,
`check_lattice_scene` and much of ADR-0208 measuring a property nothing is bound by. The two
grounds offered for an exemption are one false (three addons are `engine="fork"`) and one true but
insufficient (`content_root`).

**2. The addon publishes ONE global name, `ExMateriaBattlefield`, carrying 14 constants; the other
16 `class_name`s are deleted and reached by `preload` path.** The name matches `ExMateriaSound` /
`ExMateriaSpu` by convention, and the façade file is named after its folder so the guard can assert
it is where it says it is.

- **The 14 published**: the 11 already on `DECLARED_PUBLISHED` (`Lattice`, `CursorRig`,
  `TileHighlights`, `TileOverlayConfig`, `SkirtConfig`, `MapGridOverlay`, `MapIlluminationDDA`,
  `EventPathfinder`, `MapConstants`, `TileCursorCompositor`, `PaletteTextureGenerator`) plus the
  three arm 3 proves are already named from outside — `Tile`, `MapTextureAnimator`,
  `DynamicGeometryBuilder`.
- **The 16 internal**: `BattlefieldContent`, `DeadzoneBoxOverlay`, `Doodad`, `DoodadLibrary`,
  `DynamicTerrainBuilder`, `IndexedAtlasDilator`, `MapComposer`, `MapLightingConfig`,
  `MapStateSelector`, `PlayerCamera`, `SceneTreeManager`, `SkirtGeometryGenerator`,
  `TileCursorBob`, `TileOverlayColor`, `TileOverlayCompositor`, `VisualGeometryIndex`.
- *Publishing the three arm-3 names is not the hole ADR-0208 dec. 2 forbids.* Dec. 2 forbids
  draining a row by declaring its target *in the commit that closes the row*. These three are
  declared here, in the ruling that states why, and the rows close in a later pass — which is
  exactly the gate dec. 6 built.

**3. This ADR rules the SYMBOL axis alone, and "internal" means "no global symbol" — never
"unreached".** Three of the 16 (`MapComposer`, `PlayerCamera`, and `TileCursor` via its scene)
remain host-reachable through declared mounts that `check_lattice_scene` arm 2 reports. Deleting a
`class_name` does not touch a `$Name` lookup or a `.tscn` `path=`. Any reader who takes dec. 2's
16 as a dependency claim is reading a coupling number off a symbol instrument — the error
ADR-0205 was written to stop, one spelling over.

**4. A host MAY alias a published constant into a bare local name; a host may NOT `preload` an
addon path.** `const Tile = ExMateriaBattlefield.Tile` is legitimate — it names a name the addon
publishes, which is ADR-0208 dec. 2's third payment route, and it keeps 239 use sites unchanged.
`const Tile = preload("res://addons/exmateria_battlefield/…")` is a criterion-4 path row and
`check_lattice_scene` already scores it.

- *Aliasing makes coupling more visible, not less.* Today a coupling is spelled as a bare type at
  239 sites with nothing naming its origin. After this, every coupling in the repo is one line that
  names the façade, so `grep -rn ExMateriaBattlefield` is a complete census — which no instrument
  can produce today.

**5. A test-only host use is a real host use, and its entry must say so.** `Tile`'s only host namer
is `tests/FakeBattlefieldMap.gd`; `MapTextureAnimator`'s are three test files. ADR-0208 dec. 6
requires a name to join in a pass that states the host use it serves, and ADR-0210 dec. 1 requires
that comment to cite a host `.gd` that exists and names the symbol — a fixture satisfies both
literally, and ADR-0208 dec. 4 already published `PaletteTextureGenerator` on a citation that was
half test. Such entries carry the words **test-only namer** so a reader can tell a recorded
production surface from a fixture concession.

- 🔴 *The entries moved channel, and the ratchet had to move with them.* Before this ADR the
  per-name host-use comments lived on `check_lattice_publish.DECLARED_PUBLISHED`, where dec. 6's
  presence requirement and ADR-0210 dec. 1's two rot arms read them. The façade collapses that list
  to one name and carries the other fourteen comments itself — so for one commit the invariant was
  stated in a place nothing checked. `check_addon_globals` arm 3 is that ratchet, rebuilt on the new
  channel: presence, plus *the cited host `.gd` exists* and *it still names the symbol*. It reads
  **14 names stating a host use and 13 resolving citations** today. An entry that cites no path is
  not scored by the rot arms — the same blind spot, stated the same way, because prose naming a
  controller (`TileHighlights`) or saying `⚠️ NO HOST NAMER TODAY` (`TileCursorCompositor`) is house
  style and scoring it would red a correct comment.

- *The alternative is worse.* Without this, arm 3 sits at a target of 0 that no route the ADRs
  permit can reach — `Tile` cannot be faked (a stand-in return reds the typed signature and hands
  the caller `<null>`, measured in ADR-0210 dec. 5) and `MapTextureAnimator` cannot be moved (an
  addon-owned test runs only under the stranger rig, which has no content root, so the move deletes
  the assertion — ADR-0194 dec. 4). A target nothing can reach is not a ratchet.

**6. The register goes first, and it is ENFORCING from the day it lands — around a shrink-only
burn-down of 30.** `godot-learning/tools/check_addon_globals.py` ships before the migration. This is
ADR-0192 dec. 1's build order. It carries both of the root ADR-0003 guard's arms — CREEP (nothing
new becomes global) and ROT (nothing the façade publishes has gone missing) — because a ratchet with
only the creep arm reports green while the surface it protects decays. A third arm, CITATIONS, was
added when the migration landed and dec. 5 records why: it is not new enforcement but ADR-0210
dec. 1's, rebuilt on the channel the comments moved to. **23 seeds, both directions on all three
arms.**

- *The burn-down is 30, not 29.* The façade is a **new** file, so none of the addon's existing 30
  `class_name`s survives the migration. `test_the_burn_down_is_EXACTLY_the_live_class_name_set`
  pins the two together, so a drift cannot make every other seed pass vacuously.
- *"Reporting mode" would have been the weaker design and is not what was built.* Both arms are
  live immediately: a **new** `class_name` outside the burn-down fails today, and a burn-down entry
  that no longer names a live `class_name` also fails today — the ratchet's second arm, without
  which the list rots into a permanent exemption. The run exits 0 while names are owed and prints
  the count as **NOT A PASS**, which is this repo's established burn-down shape, not a guard
  switched off.
- 🔴 *One branch is genuinely inert, and a control pins its expiry.* Until the façade exists there
  is nothing for ROT to check, so it reports `ok` and says `THIS ARM IS INERT`. That is correct
  only while names are owed; the day the burn-down empties, an absent façade means the entire
  public surface is gone, and `test_an_absent_facade_with_an_empty_burn_down_FAILS` is the arm that
  makes the transition fail rather than pass quietly.

- *The shape is lifted, not imported.* `check_addon_install.py` set the precedent for lifting from
  `exmateria-sound/tools/check_globals.py` rather than importing across packages, and a
  cross-package import would couple two packages' tool trees to make one guard.

**7. `check_lattice_publish` arm 3 survives only if it can still fire. DIRECTION-TESTED, and it
STAYS.** After the migration a host naming a deleted `class_name` will not parse, so arm 3 reads 0
because its subject became impossible — the shape of a guard that cannot fail, which this repo has
shipped before (`#421`). The test was to seed a `class_name` back onto an internal and see whether
the arm reds. It does: `test_an_UNLISTED_undeclared_namer_is_RED` and
`test_a_namer_under_tests_is_ENFORCED_by_arm_3` both fire with rc 1 against a seeded pair. The arm
is a live tripwire against a `class_name` creeping back and is not deleted.

🔴 THE TEST RAN ITSELF, AND THE MECHANISM IS NOT THE ONE THIS DECISION PREDICTED. No scratch
worktree was needed. Arm 3's seed suite already carried `ARM3_PROBE`, a name it borrowed from the
shipped tree (`Doodad`) on the assumption that some addon `class_name` would always be undeclared —
and a control, `test_the_arm_3_probe_is_still_an_isolating_probe`, that asserts the probe really is
one. The migration made that assertion false and the control went red on the shipped tree. That red
IS the direction test: it proves arm 3's population is now structurally empty rather than merely
unobserved. The repair is that the probe is **constructed**, not borrowed — each seed now writes the
addon-side `class_name` as well as the host-side namer, so the pair asserts exactly what the arm
claims. The control asserts both halves: absent the seed the name must not exist at all (a leak from
a crashed run would let every seed pass without seeding), and with it the name must be live.

🔴 THE OVERLAP WITH `check_addon_globals` ARM 1 IS DELIBERATE AND THEY ARE DIFFERENT QUESTIONS.
Arm 1 fails on the *re-add* — any `class_name` inside the addon that is not the façade. Arm 3 fails
on a *host naming* one. A tree could satisfy either alone: an internal `class_name` nobody names
reds arm 1 and not arm 3, and if the burn-down were ever re-opened to admit a name, arm 3 would
still be the only thing scoring who compiles against it. Two registers, two subjects; neither
reports the other, and the wrap-up says both numbers.

**8. This ruling was scoped to battlefield because the other addons were unmeasured. They have
since been measured, and [ADR-0212](0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md)
rules them.** `exmateria_schema` (6 names), `exmateria_platform` (3) and `exmateria_render` (1) now
take façades on the same grounds this ADR gives for battlefield. The invariant ADR-0212 states is
that an addon's one global is the **folder-named façade** — a count of 1 was never it, which is why
`exmateria_render` needed ruling despite already declaring exactly one.

- 🔴 *The reasoning this decision originally gave was wrong, and is recorded here rather than
  quietly replaced.* It read: *"a façade there would wrap a namespace in a namespace."* It does not
  survive the numbers — schema is ten files and six types, and `ExMateriaSchema.TerrainCell` reads
  exactly as `ExMateriaBattlefield.Lattice` does. By the collision risk that motivated `#717`,
  schema's names are the **worse** offenders: `Fold`, `ColorStack`, `DepthMode`, `CellMarking` and
  `ColorRecipe` are generic English and `DisplayPort` is the name of a hardware standard, where
  `Lattice` / `MapIlluminationDDA` / `TileOverlayConfig` were distinctive.
- 🔴 *And the obvious replacement argument is also wrong.* That battlefield's façade was a
  **complete** close because nothing preloaded in (16 host script preloads reach schema) does not
  distinguish either: `exmateria_sound` reads **48** and shipped a façade regardless, under the
  repo-root `docs/adr/0003-an-installed-addon-owns-five-global-names.md`. Complete-close is a
  description of scope, never a precondition — ADR-0212 dec. 2.
- *The one leg that stood was scope, and it has expired.* *"Neither has been measured to this ADR's
  standard, and generalising a rule across two unmeasured addons is how an ADR comes to claim more
  than its tree supports"* was correct on the day it was written. Both are now measured by the same
  instrument, which is also why this ADR's `Alternatives rejected` entry *"Generalise the rule to
  every addon in the monorepo"* no longer holds.

**9. The migration lands on the available verification bar, and the full suite is stated as owed.**
Warm `--import` parse check, all five registers, all four stranger rigs, and a scoped run derived
by `scoped_tests.py`. `run_tests_parallel.py -N 12` is not run: the GPU is held at 29 of 32 GB, and
two attempts under that load returned 609/709 and 624/709 with *different* failing names each time,
82 of 722 logs carrying `VkResult error -2`. A number known to be noise is not verification, and
reporting one would be worse than reporting none.

## Consequences

- The addon's global footprint goes **30 → 1**. The monorepo total across six addons goes from 42
  to 13, of which schema's 6 and platform's 3 are explicitly unruled (dec. 8).
- Arm 3's three rows — `Tile`, `MapTextureAnimator`, `DynamicGeometryBuilder`, 14 sites — become
  payable, closing `#716` and the last open half of ADR-0208 dec. 2. They are paid in a later pass,
  not in the commit that declares them (dec. 5).
- The 17-name population dec. 1 measured stops growing, because arm 3's pump is disconnected: a
  name that loses its last outside namer becomes an internal with no global registration, not an
  unowned global.
- `grep -rn ExMateriaBattlefield` becomes a complete census of host→addon symbol coupling. No
  instrument produces that today.
- **The path axis is untouched and stays that way.** Criterion 4 remains 0 with three declared
  mounts; `MapComposer` remains the addon's most-reached file by path while holding no global name.
- A consumer's error messages change shape for the better: a colliding `class_name` today makes the
  *addon's* file fail to parse, pointing the error at a file the consumer did not write. One name
  makes that collision a thousandth as likely and names the addon when it happens.
- The migration is ~185 one-line `const` additions and 29 deletions across 100+ files, verified
  below the full-suite bar (dec. 9). That is the largest unverified-at-full-suite change this
  branch carries, and it is stated here rather than in a commit message.

## Alternatives rejected

- **Drop the 17 and keep 13 globals (`#717` option 2).** 48 internal `const` lines instead of 90 —
  45% of the work — but it leaves 13 engine-global names including `Tile`, `Lattice` and
  `MapConstants`, the generic spellings most likely to collide, and it leaves arm 3 at 3 names / 14
  sites with no payment route, because the three names it must publish are exactly the ones it
  would keep global. It buys a partial close of a surface dec. 2 closes entirely, at the cost of
  never being able to say the surface is closed. *Its second mechanism does not exist*: `#717`
  offers "drop **or** underscore-prefix", and `class_name _MapComposer` is still an engine-global
  registration — the underscore is signalling, not scope.
- **Rule battlefield host-only (`#717` option 3).** Rejected on dec. 1. Its stated distinguisher is
  measurably false for the fork half, and adopting it would retract axis B's shipped CLEAR verdict
  and strand five registers measuring a property nothing is bound by. It is also the one option
  that cannot be cheaply reversed: instruments rot the moment nothing is bound by them.
- **Promote the three arm-3 names into `DECLARED_PUBLISHED` and stop there.** This is the hole one
  level up that ADR-0208 dec. 2 names: a row drained by declaring its target. It would take arm 3
  to 0 while leaving 30 globals and the 17-name population untouched — the number moves and the
  problem does not. Publishing those three is correct *only* as part of a ruling that also removes
  the 16 (dec. 2), which is why they are declared here and not in a payment pass.
- **Rewrite all 239 host use sites to `ExMateriaBattlefield.Lattice` instead of aliasing.** Five
  times the diff for no gain in safety — the coupling is scored at the alias line either way, and a
  239-site mechanical rewrite verified below the full-suite bar is a much larger risk than 82
  one-line additions.
- **Generalise the rule to every addon in the monorepo.** Rejected on dec. 8 *on the day this was
  written*, because neither schema nor platform had been measured the way this ADR measures
  battlefield. **That ground has expired** — both were measured by the same instrument on
  2026-08-30, and ADR-0212 rules all three remaining addons. The other half of the entry, that
  schema's six names are the shared vocabulary rather than an implementation surface, is true and
  turned out not to carry an exemption: a shared vocabulary in a consumer's global scope collides
  exactly as an implementation surface does, and generic English collides more.
- **Wait for the GPU and verify at the full-suite bar first.** The remaining battlefield work is
  static analysis and needs no GPU; holding it would stall the decision `#716` and `#560` both wait
  on, to buy a verification that can be run the moment the GPU frees and is recorded as owed
  either way (dec. 9).
