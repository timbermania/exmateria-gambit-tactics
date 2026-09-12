# The catalogue lands, and the ninth published name was a symbol census that could not see a path

[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
audited extraction #6 and priced the move: nine published façade names, 59 alias lines,
five travelling payloads, one unmovable content root, twenty test files to re-point. This
pass does the move. Three of those five numbers are wrong, and each was wrong for a reason
worth keeping rather than quietly correcting:

- **Nine published names is TEN.** The nine came from a symbol census over the membership
  — a count of `class_name` declarations, which is what a shed produces. `CharacterCatalog`
  is published too, and it was found by re-reading the host `preload` lines, not by counting
  identifiers. A census that scans symbols cannot see a path.
- **Fifty-nine alias lines is 71, over 46 files.** The 59 was produced by a string-stripping
  pass whose regex ran across newlines and blanked live code; two offsetting errors landed
  it on a number that matched the audit's, which is the worst possible way to be wrong.
- **One unmovable content root is TWO.** `assets/characters/templates/` is
  `git check-ignore`-matched, untracked and a symlink, exactly like `assets/sprites/textures/`.
  ADR-0262 dec. 9 read it as a payload that travels.

The move itself is uneventful and the instruments say so: arm 6 goes from six paths over
seven lines to **zero**, arms 2 and 2b are **both zero** where the audit priced two lines,
and `classify()` re-books **nothing** — every one of the ten members books
`Character Catalogue` at the new address exactly as it did at the old (#744).

The finding is at the other end. The seventh stranger rig, built here because
`_walk_roots.RIGS` demands a row for every addon root, **failed on its first run** and found
a defect no instrument in `tools/` can reach: shedding `class_name Character` left nine
lines inside `Character.gd` naming a type that no longer exists. The host tree does not
report it, and the reason is on disk — `.godot/global_script_class_cache.cfg` line 227 still
registers `Character` against `res://src/characters/Character.gd`, a path this commit
deletes. Every host suite parses off that stale entry. This is ADR-0262 soft spot S4
arriving in the exact shape it was written in, and it is the argument for building the rig
in the same pass as the move rather than the one after.

Status: accepted (2026-09-08). This is
[ADR-0126](0126-every-system-pass-audits-before-it-designs.md)'s **pass 3** for extraction
#6 — the `git mv`. Reads
[ADR-0257](0257-a-debug-panel-is-not-a-member-and-the-order-that-counted-it-as-one-is-an-artefact.md)
dec. 2 for the membership (dec. 1 is the panel rule that produced it),
[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
dec. 11 for the four questions it reserved,
[ADR-0212](0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md)
dec. 1 and dec. 7 for the façade and the sibling-namer rule,
[ADR-0211](0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md) dec. 4
for the alias route,
[ADR-0251](0251-the-almanac-is-thirty-two-names-behind-one-and-the-address-collapsed-while-the-buckets-did-not.md)
dec. 2 for payloads travelling beside their readers,
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 5 and
[ADR-0203](0203-an-addon-provides-the-names-it-can-and-injects-the-content-it-cannot.md)
dec. 1 for the host-injected content root,
[ADR-0184](0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md) dec. 4
for the shape of an `ARM1_BURN_DOWN` entry,
[ADR-0167](0167-the-mount-inverts-to-the-host-and-the-fix-was-booked-into-the-bucket-it-drains.md)
for why a behavioural change may not ride inside an address move, and
[ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) decs.
3, 5 and 7 for the stranger rig.
**Supersedes nothing.** ADR-0262 stays accepted; decs. 7 and 9 are CORRECTED on the record
by decisions 5 and 6 below, and soft spots S1 and S4 are discharged by decisions 4 and 9.

## Context

### What the audit handed over, and what it could not

ADR-0262 dec. 11 reserved four calls for this pass and named a fifth as out of scope. The
four are answered below as decisions 1, 2, 7 and 8. The fifth — whether arm 5's free set
should stop asking `_system_of` — is [#1059](https://github.com/timbermania/fft-monorepo/issues/1059)
and is still open, so **this extraction lands in the world dec. 5 described**: 55 of the
61 arm-5 lines arrive as DEBT rows in `check_addon_portability`'s ledger because
`_system_of` reports `exmateria_almanac` as the *Battle* system's addon. That is not a
regression introduced here and it is not evidence against the address; it is the artefact
the audit accepted in writing.

### The stale cache, which is the reason the rig exists

`tests/stranger/<addon>/run.sh` stages a throwaway project with nothing in it but the
addon and its declared dependencies, imports once, and loads every source file. The host
project cannot make that claim about itself, and here it actively hid a break: the shed
removed `class_name Character` while nine lines in the same file still named `Character` as
a type. Godot resolved them anyway, off a global-class-cache entry pointing at a path that
no longer exists.

```
.godot/global_script_class_cache.cfg:227  "class": &"Character",
.godot/global_script_class_cache.cfg:232  "path": "res://src/characters/Character.gd"
```

A fresh checkout has no such entry. The rig's first run reported it in two lines and named
both files.

## Decision

**1. The addon is `addons/exmateria_catalogue/`, `class_name ExMateriaCatalogue`, six
member directories, and the layout is the `ls` test's answer rather than a taxonomy.**
`identity/` 4, `templates/` 2, `seeding/` 2, `registry/` 1, `inspection/` 1, plus
`install/` for the content port, which is not a member. ADR-0146 dec. 2's test is that a
reader can see what the addon is from `ls`; ADR-0184 dec. 2 is *name the directory after
the fact*. `catalogue` is the fact — it is the word ADR-0241, ADR-0257 and ADR-0262 all
use for this system, and `CharacterCatalog` is its centre. **The cautionary precedent was
read rather than cited:** ADR-0251 dec. 1 named a package by taste and
[#1060](https://github.com/timbermania/fft-monorepo/issues/1060) exists to re-open it. The
difference is that `almanac` was a metaphor chosen for a set of tables that had no shared
word; `catalogue` is already the corpus's own name for this set, in three ADRs written
before this one.

**2. The autoload TRAVELS, `plugin.gd` registers it, and both host reach sites are paid by
NODE PATH — so arms 2 and 2b are both ZERO, not the two lines dec. 6 priced.** Dec. 6 ruled
that the class moves and that the exposure is two lines rather than 35; it explicitly did
not pick the spelling. The spelling is `get_node_or_null(^"CharacterCatalog")` at both
sites, which is the shape ADR-0202 dec. 7 already blesses for a soft, null-guarded reach to
a host autoload. `AllTemplatesSeeder.seed(catalog = null)` already injected, so only
`Character.gd`'s site needed the change. The measured result is better than the price:

```
arm 2  (foreign autoload, bare identifier)   0
arm 2b (foreign autoload, node-path string)  0
```

Arm 2b has an own-singleton exemption decided on the `res://` path in the `[autoload]`
line, which `plugin.gd` writes and the host's `project.godot` carries, so the addon
reaching its OWN singleton by path scores nothing. **This is a case where the guard's zero
is the interesting number and the burn-down entry is the one that was not needed.**

**3. `ARM1_BURN_DOWN` gets ONE row, and the row says the reach is severable and must not be
severed here.** `templates/CharacterTemplateResolver.gd:44` names `ExMateriaSpriteRig`,
which books to the `Sprite Rig` system, for one call — `job_body_palette_row(job)` on line
108. It is severable: `SpritePaletteResolver.job_body_palette_row` is itself a one-line
delegation, this file already names `JobDatabase` on line 49, and inlining the expression
would cut the edge today. It is not severed because doing so forks a rule the rig
deliberately centralises — `job_body_palette_row`'s own docstring says the two-axis monster
branch delegates to it so that *"monster color = the job's row"* lives in one place — and
because ADR-0167's rule is that a behavioural change does not ride inside an address move.
Owner [#1071](https://github.com/timbermania/fft-monorepo/issues/1071), which pays it with
an injected port, the shape `exmateria_sprite_rig` already uses on its own outbound edge.
Shape per ADR-0184 dec. 4: a NAMED row with an owner and an argument, never a pattern.

**4. The published surface is TEN names, not nine, and the tenth is the correction ADR-0262
dec. 7 needs.** `CharacterCatalog` is on the façade because two host files mint a FRESH,
empty catalogue rather than using the live one — `tests/CharacterCatalogOwnedTest.gd:13`
tests ownership without the autoload's state and `tests/StoryMutationScriptTest.gd:32`
replays a mutation script into a clean one. **The way the ninth-vs-tenth error happened is
the part worth keeping.** The audit's nine came from counting `class_name` declarations in
the membership, which is exactly the set a shed converts one-for-one into `const X =
preload(...)`. Ten names shed and ten published is a coincidence of two different routes,
and the two counts agreeing is the thing to distrust: the tenth name has no `class_name` to
shed (it is an autoload) and arrives on the façade by a `preload` path, invisible to the
census that produced the nine.

**5. Four payloads travel; TWO content trees stay and are injected; arm 6 opens at zero.**
ADR-0262 dec. 9 read the split as five travelling and one staying. The measurement here is
4 / 3 lines over 2 roots:

```
travelled (ADR-0251 dec. 2)          identity/unit_names.json
                                     identity/unit_birthdays.json
                                     templates/template_residue.json
                                     seeding/template_jobs.json
injected (ADR-0202 dec. 5)           assets/characters/templates/   2 lines
                                     assets/sprites/textures/       1 line
```

`assets/characters/templates/` is ROM-derived, `git check-ignore`-matched, untracked and a
symlink into the asset hub — the same four properties that made the textures tree
un-shippable. Both route through `install/CatalogueContent.gd`, whose default root is
**empty on purpose**: a default of `res://assets/` would leave the literal in an addon file,
arm 6 would still score it, and the fix would be booked into the bucket it drains
(ADR-0167).

**6. `classify()` gains the addon root and a tests rule, and RE-BOOKS NOTHING.** The two
retired rows (`src/characters/` as a prefix, `src/scenarios/AllTemplatesSeeder.gd` as an
exact row under ADR-0135 dec. 9) are replaced by one prefix on the new root plus an
`infrastructure` row for `plugin.gd`. Zero re-bookings is not an inference: `origin/main`'s
`classify()` was run over the old paths and this tree's over the new ones, and the two
agree row for row. The `src/debug/` branch's `DEBUG_OWNER` "Roster" fragment STAYS, because
`RosterViewDebugPanel.gd` is still there (decision 8).

**7. `src/debug/RosterViewDebugPanel.gd` is dead, stays in the host, and gets its own
ticket.** ADR-0262 dec. 8 found it unreachable. Retiring it is a deletion, which is a
behavioural change and therefore not this pass's (ADR-0167 again). Filed as
[#1070](https://github.com/timbermania/fft-monorepo/issues/1070).

**8. Soft spot S1 is discharged EXACTLY, and the exactness is the result.** S1 said the 61
was measured on the membership in `src/` and could only go up once the folder existed. Run
on the moved membership it is 61, row for row and line number for line number:

```
exmateria_almanac    53
exmateria_platform    6
exmateria_sprite_rig  2
```

That the number did not move is the claim, not the absence of one: it says the arm-5
reading is a property of what these files REACH and not of where they sit, which is the
same thing decision 6 says about `classify()` from the other side.

**9. The seventh stranger rig is built in THIS pass, and it earned its place on the first
run.** `_walk_roots.RIGS` requires a row per addon root and an absent row reads as
*installs clean* to `tools/score_goals.py` goal #5. The rig found three defects, one in the
subject and two in the shared harness, and none of the three is visible to any static
instrument in `tools/`:

1. **The shed self-reference.** Nine lines in `Character.gd` named `Character` as a type
   after its `class_name` was removed. Paid with `const Character = preload(<own path>)`,
   which is the corpus idiom (`exmateria_schema/colour_model/ColorRecipe.gd`,
   `exmateria_render/fold_bracket/FoldSurface.gd`, four battlefield members).
2. **`deps=` was staged as a LINE, not a CLOSURE.** `rig.sh` staged the subject's declared
   deps and stopped. That was indistinguishable from correct for six rigs because every
   declared dep in the corpus was a leaf: `exmateria_platform` and `exmateria_schema`
   declare no deps of their own and were the only things anyone depended on. The catalogue
   is the first addon whose deps have deps — it names `exmateria_sprite_rig`, which names
   `exmateria_schema` — and the rig put it in a project where a STAGED addon could not
   parse. Fixed by staging the transitive closure; the banner prints the line AND the
   closure, because a reader who sees only the closure cannot tell what the addon said
   about itself.
3. **`engine=` was read the same way, and gets the same answer with the opposite
   emphasis.** The catalogue truthfully declares `engine="stock"` — no file in it names a
   compositor primitive — and its closure contains two `"fork"` addons. Booting stock
   produced five throws from `exmateria_schema/compositing_key/` that are that addon's
   declared fork dependency wearing the subject's name. The DECLARATION stays the
   subject's and the RUN follows the closure. Promoting the subject's own `plugin.cfg` to
   `"fork"` was rejected: it would make the file claim the catalogue needs a primitive it
   does not name, and `plugin.cfg` is the document the whole rig treats as authoritative.

Final run: 33 passed, 0 failed, 32 files, `[PASS]`, and the fork-absence arm green.

**10. The two pins are RE-TAKEN, and three of their tests had their PREMISE expire rather
than their value.** `tools/test_membership_arms.py` (30 tests) and
`tools/test_arm7_membership.py` (14) both red on the move, which is the pin working. Every
number in them is re-measured on this tree. Three tests could not be re-pinned by changing
a number, and each is recorded in its own docstring:

- **`TwoSpellingsOfOneAutoload`** was seeded on `CharacterCatalog`, whose two reach sites
  decision 2 PAID. Re-pinning it there would assert `[] == []` and pass for a broken
  predicate. Re-based on `PerfMonitor` under `src/debug/`, live at 5 dotted and 4 bare. A
  control that depends on the defect expires on success; the seed moves, it is not deleted.
- **`TestsAreNotOutsideTheFacade`** read the façade's reach off `ma.inbound()`, which
  resolves identifiers against the engine-global table. After the shed there is no
  `class_name` in the membership, so `inbound()` returns `{"CharacterCatalog"}` for every
  possible caller — it is not broken, it has become structurally unable to see this addon,
  which is what ADR-0212 dec. 1 does to every extracted system. The reading moves to the
  ADR-0211 dec. 4 alias lines, where the reach now lives. The finding is unchanged: SEVEN
  names from a `src/`-only reading, TEN from the whole tree.
- **`test_the_green_sentence_carries_arm_1_unqualified`** was written the day
  `ARM1_BURN_DOWN` went empty and asserted the OK line had SHED its caveat. Decision 3 puts
  a row back. Re-pinned as an IF AND ONLY IF, in both directions, which is what the test was
  protecting.

`tools/test_arm7_membership.py`'s `test_a_debug_helper_that_is_not_a_panel_stays` was
passing VACUOUSLY after the move — it asserted `assertNotIn("src/debug/RosterDebugView.gd",
...)` about a path that no longer exists, which is true for every possible detector
including one returning everything. Re-pointed, with a `is_file()` guard so it cannot go
vacuous the same way again.

**11. What this does NOT decide.** Whether arm 5's free set stops asking `_system_of`
(#1059, still open, and the 55 debt rows above are its consequence); whether
`RosterViewDebugPanel` is deleted (#1070); whether the sprite-rig palette edge is severed
(#1071); and whether either pin is wired into `tests/run_all_tests.sh`
([#1055](https://github.com/timbermania/fft-monorepo/issues/1055) — and see soft spot S3).

## Considered alternatives

**Fold the catalogue into `exmateria_almanac` rather than give it its own root.** 53 of its
61 sibling lines target the almanac, so the fold erases most of the visible debt. Rejected
on ADR-0262 dec. 5's ground, restated here because the number is now measured rather than
projected: folding severs no edge, it only stops the guard printing one. The almanac is a
book of tables (ADR-0251 dec. 1) and the catalogue is a live registry with an autoload;
merging them would put a singleton inside a package whose whole claim is that it registers
nothing.

**Sever the sprite-rig palette edge while the file was already moving.** Rejected under
decision 3 — it is a design change to where a centralised rule lives, and ADR-0167 is the
rule against letting one ride inside an address move. The cost of not doing it is one named
burn-down row with a ticket, which is the shape ADR-0184 dec. 4 built the list for.

**Declare `exmateria_schema` in the catalogue's `deps=` to make the rig green.** Rejected:
the catalogue reaches no `ExMateriaSchema` symbol, and `check_addon_portability` says so.
The line describes what the addon reaches; making it describe what the rig needs to stage
would break the one document the rig trusts. The closure is derived instead (decision 9).

**Give the rig a `known_failures.tsv` for the schema throws.** Rejected for the same
reason one level down: those rows name files in the SUBJECT addon, and the throws were in a
staged dependency. A burn-down that absorbed another addon's declared fork dependency would
be recording the harness's defect as the subject's debt.

## Consequences

1. `check_addon_globals` now reads **seven** global names, one per addon, and the catalogue
   opens with an EMPTY `BURN_DOWN` — no member kept a `class_name`.
2. `check_addon_portability` returns rc 0 with one `ARM1_BURN_DOWN` row and 55 arm-5 DEBT
   lines, all nine rows the catalogue's. The green sentence is qualified, and decision 10's
   re-take is what keeps that qualification honest.
3. The blueprint walk gains a root and a tests rule. Its one red —
   `src/debug/CombatPanelCatalog.gd` and `src/debug/PanelApplicability.gd` UNCLASSIFIED —
   is identical on `main` and belongs to ADR-0263.
4. `tests/stranger/shared/rig.sh` changed for all seven rigs. Every earlier rig's closure
   already equalled its direct deps and every earlier subject's engine already dominated its
   closure, so nothing about their runs moves; the almanac, sprite-rig and schema rigs were
   re-run to say that rather than assume it.
5. Four generators now write into the addon (`build_unit_names.py`,
   `parse_unit_birthdays.py`, `derive_template_residue.py`, `derive_template_jobs.py`), and
   `build_roster_timeline.py` reads one payload back out of it through a SECOND loader
   rather than a base-path argument — a default-argument base is the shape that keeps
   resolving silently after the next move. ADR-0251 dec. 8: the generator moves with its
   output.

## Soft spots

- **S1. `plugin.gd` books `infrastructure` and the façade does not, and the stated reason
  does not distinguish them.** The catalogue's `plugin.gd` follows the unanimous precedent
  of the other three system-addons (battlefield, sprite_rig, almanac all book their plugin
  entry to `infrastructure`), and all four façades book to their system. The rule that would
  separate them — a file with no behaviour is infrastructure — is false of the façades,
  which also declare zero funcs. The majority was followed and the disagreement is written
  down rather than settled, because settling it re-books files in three other addons.
- **S2. The stranger rig proves the four payloads TRAVELLED; it does not prove the two
  injected trees resolve.** The rig deliberately declares no `content_root`, so what it
  witnesses is `CatalogueContent.resolve()` refusing once and naming the setting. Nothing
  automated exercises the branch where a host DOES declare one — the host suite does, but
  the host is the project that cannot make a stranger's claim.
- **S3. Neither pin is in `tests/run_all_tests.sh`, and this pass did not wire them in.**
  #1055's rule stands: a red guard added to the pre-flight reds it on arrival. Both are
  green on this tree now, which removes the stated obstacle and does not by itself rule the
  pin — that is #1055's call, not this ADR's.
- **S4. The 71 alias lines were counted by a scanner that had already been wrong once.** The
  count is now taken per line rather than over the whole file, and the sweep that applied
  them touched 46 files, which agrees. But the instrument that produced the audit's 59 was
  the same kind of instrument, and agreement between a fixed scanner and its own output is
  weaker evidence than it looks. The check that would settle it is a parse, not a grep.
