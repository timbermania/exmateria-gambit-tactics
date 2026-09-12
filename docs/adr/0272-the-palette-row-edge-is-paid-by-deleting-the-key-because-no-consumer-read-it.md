# The palette-row edge is paid by deleting the key, because no consumer read it

`ARM1_BURN_DOWN`'s only row — the one #1025 pass 3 put back after ADR-0184 dec. 4's
six were paid — named `exmateria_catalogue/templates/CharacterTemplateResolver.gd`
reaching `ExMateriaSpriteRig` for one call, `job_body_palette_row(job)`.
[#1071](https://github.com/timbermania/fft-monorepo/issues/1071) proposed to pay it
with an **injected port**, and named one alternative worth pricing first: that
`body_palette_row` may not belong in `resolve()`'s answer at all.

The alternative wins, and it wins on a measurement the ticket already half-stated:
**the key was a pass-through no consumer read.** Both live consumers handed the value
straight to a sprite-layer setter, both already hold the `Character` the row is a
function of, and the host already calls the owning primitive in two other files. So
the edge is severed by the resolver **not answering the question**, not by anyone
answering it differently.

Status: accepted (2026-09-09). Resolves
[#1071](https://github.com/timbermania/fft-monorepo/issues/1071). Discharges
[ADR-0267](0267-the-catalogue-lands-and-the-ninth-published-name-was-a-symbol-census-that-could-not-see-a-path.md)
dec. 3 and its "NOT DECIDED" entry for the palette edge.

---

## Context

`SpritePaletteResolver.job_body_palette_row(job_hex)` is the JOB axis of ADR-0022's
body palette row — Yellow Chocobo 0x5E → 0, Black 0x5F → 1, Red 0x60 → 2, Holy Dragon
0x48 → 3, humanoids → 0. Its own docstring is the reason the burn-down row said the
reach must not be severed *by inlining*: the two-axis `resolve_body_palette_row`
monster branch delegates to it so that *"monster color = the job's row"* lives in
exactly ONE place.

`CharacterTemplateResolver.resolve(character)` is ADR-0072's seam. On its job-routed
branch it answered two keys:

```gdscript
return {
    "body_sprite_id": JobDatabase.get_sprite_id(job, character.is_female),
    "body_palette_row": SpritePaletteResolver.job_body_palette_row(job),
}
```

The second line is the whole edge. `SpritePaletteResolver` is the addon's only
`ExMateriaSpriteRig` alias; delete the line and the token leaves the file.

---

## Decisions

**1. The edge is paid by DELETING THE KEY. `resolve()` no longer answers
`body_palette_row`, on any branch.** Not by inlining the expression (which forks the
rule) and not by an injected port (which keeps the question and adds a mechanism to
answer it). The resolver stops being asked.

**2. The measurement that decides it: the key was a pass-through NO CONSUMER READ.**
Three call sites take `resolve()`'s dict. Two read the row, and neither inspects it:

| consumer | what it did with the row |
|---|---|
| `src/units/UnitSpawn.gd:105` | `unit.body_palette_row = visuals["body_palette_row"]` — straight onto the node; `Unit.gd:98` forwards it to `sprite_layers.set_body_palette_row`. |
| `src/ui3/formation/FormationScene.gd:146` | `"palette_row": visuals.get("body_palette_row", 0)` — carried through `resolve_body_render`'s dict to `set_body_palette_row(render.palette_row)` at `:3329`. |
| `addons/exmateria_catalogue/seeding/AllTemplatesSeeder.gd:276` | **does not read it.** `_renders()` uses `template_folder` and `body_sprite_id` only. |

A value that is fetched, packed into a dict, unpacked, and passed on unexamined is an
indirection, not an abstraction. #1071's body named two consumers; the census found
the third and it is unaffected, so the contract change has exactly two subjects.

**3. It costs the host NOTHING, because the host already calls this primitive.**
`Unit.gd:1481` (`change_job`) and `ScenarioPlayerScene.gd:921` already name
`SpritePaletteResolver` and already ask it for the row. `UnitSpawn.build` now spells
the stamp exactly the way `Unit.change_job` does, from the same owner, with the job it
already routed by. Two new host→addon alias lines are added and one is deleted
(`tests/CharacterRosterParityTest.gd`'s, which the change made unused), and none of the
three is any arm's subject: *"Every arm of `check_addon_portability.py` scans files
UNDER AN ADDON ROOT"*
([ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md),
Context, *"The 35 that were never arm 2's subject"*). They are in `src/` and `tests/`.

**4. The rule still lives in one place, which is what the burn-down row was
protecting.** The row's argument was that inlining
`int(JobDatabase.get_job(job_hex).get("body_palette_row", 0))` into the resolver would
make a second home for the rule. Deleting the key makes no home at all: every consumer
now asks `job_body_palette_row`, which is where the rule already was. The count of
implementations goes 1 → 1; the count of routes to it goes 2 → 1.

**5. The port was rejected on a fact about the function, not on taste: `resolve()` is
`static`.** An injected port into a static function is one of two shapes and both are
worse than the call site asking:

  - a `static var` registry set at boot — global mutable state with an init-order
    hazard, in an addon whose selling point is that it has none; or
  - a parameter threaded through `resolve(character, palette_row_fn)` — which requires
    **every caller** to hold the callable in order to ask a question **two of the three
    do not want**. That is strictly more coupling than the caller making the call.

The port shape `exmateria_sprite_rig` uses on its own outbound edge
(`content/ContentPort.gd`) is an *instance* seam with a host-supplied adapter object.
It is not available to a static free function without inventing the registry above.

**6. 🔴 The DoD item that could not be met as written, and what replaced it.** #1071's
definition of done says *"`tests/CharacterTemplateResolverTest.gd` and
`tests/CombatBodyPaletteRowTest.gd` still assert the same rows for the same jobs (Red
Chocobo 2, humanoid 0)"*. Under this decision `CharacterTemplateResolverTest` **cannot**
assert a row off `resolve()` — the key is gone — so the item as literally written
presumes the port. It is met in substance and the substitution is written down rather
than quietly dropped: `_test_resolve_does_not_answer_the_palette_row` asserts BOTH
halves in that same file — the key is absent on all three branches, AND jobs `60` and
`4a` still answer 2 and 0 from the owner. Without the second half, deleting a key and
losing a value look identical.

**7. `FormationScene.resolve_body_render`'s `palette_row` had NO test, on either side
of this change.** It is one of the two consumers and it drives every roster cell's
`set_body_palette_row`. Three arms added to `CombatBodyPaletteRowTest`: Red Chocobo 2,
humanoid 0, and a **folder-routed unique**, whose `palette_row` is a hardcoded `0` —
the arm that catches the obvious wrong fix, since reading the job's row on the unique
branch would repaint every unique in the formation.

**8. The caveat test is RE-SHAPED, not re-taken, because a pin on the list's SIZE has
now been wrong on both sides.** `test_the_green_sentence_is_qualified_EXACTLY_WHEN_
arm_1_has_a_row` asserted `len(ARM1_BURN_DOWN) == 0` when it was written, `== 1` after
#1025 pass 3, and would now go back to `== 0`. Neither direction is taken from the
shipped list any more: on a clean tree the shipped list **cannot** exercise the
positive one, because a row naming no reach is STALE, so the caveat stays absent and
the run reds for an unrelated reason. The positive direction now **seeds the severed
reach back** into the catalogue and lists it; the negative direction runs the same walk
with `{}`. Both were proved live by mutation: forcing the guard's `if burn:` to `True`
reds the negative arm, forcing it to `False` reds the positive one.

**9. 🔴 ADR-0167 does not contain the sentence four documents attribute to it, and this
decision is the one that had to check.** #1071's body, that ADR's dec. 3, the burn-down
row's own comment and `addons/exmateria_catalogue/README.md` all render the rule as
*"a behavioural change does not ride inside an address move"* — whose only source in
the corpus is ADR-0267, three times (`:54`, `:131`, `:271`). What ADR-0167 says is
*"a behavioural change riding inside a booking correction makes the booking's own
numbers unattributable"*, and ADR-0175:316 and ADR-0183:188 both quote that correctly,
with the right subject. The four downstream sites inherit the swap from there. The
generalisation is defensible — attributability is the reason, and an address move has
its own numbers to keep attributable — but it is a generalisation, not a quotation, and
it was load-bearing for *this* ticket's shape. It does not change this decision either
way: #1071 is a standalone behavioural change in its own commit, riding inside nothing.
The accepted ADRs are **not** edited here; the finding is recorded and the row's comment
no longer repeats it.

**10. 🔴 `addons/exmateria_battlefield/README.md:118` asserted `ARM1_BURN_DOWN` is
EMPTY for the 68 commits in which it was not.** #1025 pass 3 put a row back on
2026-09-08 and that sentence was still standing when this pass opened it. Nothing
caught it because a README is prose, and the corpus already ruled on exactly this shape
(ADR-0196: *a scan that reads its own prose passes through*). It is left as written
because this change makes it true again — which is the point: it was true, then false,
then true, and no instrument was ever involved.

**11. THE SEVERANCE MADE TWO REGISTERS STALE, AND BOTH WERE FOUND BY THE REGISTER
RATHER THAN BY THE AUTHOR.** Neither is in `check_addon_portability.py`, which is why
running that one guard to rc 0 read as finished and was not.

*`addons/exmateria_sprite_rig/exmateria_sprite_rig.gd:231`* cited
`tests/CharacterRosterParityTest.gd` as a host use of `SpritePaletteResolver`, and this
pass deleted that file's alias line. `check_addon_globals.py`'s citation-rot arm caught
it exactly as designed — *"cites `tests/CharacterRosterParityTest.gd`, which no longer
names it — re-read the comment"* — and thirteen of its tests went red together, because
each seeds on top of the shipped tree and a red shipped tree reds them all. The comment
is rewritten rather than trimmed: its whole first paragraph staged a SIBLING NAMER under
ADR-0212 dec. 7, and after this pass every citation on that name is a host file.

*`tools/test_membership_arms.py`'s `Arm1HasALiveSubject`* had the catalogue's one reach
as its subject, and its own docstring said why — *"Arm 1 reads zero on every addon —
that IS goal #5 — so the witness is a proposal."* Paying the row makes
`ma.arms(CATALOGUE, INSIDE)["1"]` empty, and every assertion in that class would then
read `{} == {}` and pass for a stub returning nothing.

**12. Arm 1 now has NO live subject anywhere in the tree, so its liveness witness is
SEEDED — and this is the first control in the corpus that could not be re-based.**
`TwoSpellingsOfOneAutoload` set the precedent at #1025 pass 3: *a control that depends
on the defect expires when the defect is paid; the seed has to move, not be deleted* —
and it moved, to `PerfMonitor`. This one has nowhere to move to. Goal #5 is enforcing
and now fully met, so no file under any addon root reaches any of the eleven systems,
and that is a state the tree is meant to STAY in. So the witness is a file the test
writes under the catalogue root, measures, and deletes, with both directions asserted:
the real membership must read `{}`, and the same walk over the same membership plus one
seeded line must read exactly one row booking to `Sprite Rig`. Mutation-proved by
stubbing arm 1 to `{}` — three of the five arms red, and the two that stay green are
the paid-direction arm and the leak arm, which is the split the class is claiming.

---

## Alternatives

**The injected port, as #1071 proposed.** Rejected at dec. 5 on the static-function
fact, and at dec. 2 on the prior question: a port is a mechanism for answering
`body_palette_row` inside `resolve()`, and no consumer wanted it answered there. It is
the right shape for an edge whose *value* the addon needs; this addon needed the value
zero times.

**Inlining `JobDatabase.get_job(job_hex).get("body_palette_row", 0)`.** The shape
ADR-0267 dec. 3 refused, for the reason it gave: it forks a centralised rule. Nothing
here re-opens that; the key is deleted rather than re-implemented.

**Keep the key, pay the edge by moving `job_body_palette_row` into `exmateria_schema`
(the kernel).** Arm 1's free set is the kernel and the port, so this severs the row
without touching a call site. Rejected: the kernel is types and vocabulary, and this is a
*lookup against jobs.json* — it would put a content read in the one addon that has no
content. It also leaves the pass-through in place, so the dict still carries a value
nothing inspects.

**Keep the key and let the burn-down carry the row until extraction #7.** The row is
one line and green. Rejected because the row's own argument was that the sever is
*cheap and blocked only by the fork*, and the sever turns out not to fork anything —
the reason the row existed does not survive being looked at.

**Move the whole `body_palette_row` field off `Unit` and let the sprite layer read the
job.** Out of scope and larger than the ticket: `Unit.body_palette_row` has a second
writer (ADR-0053's ENTD path via `ScenarioPlayerScene:842`) whose value is *not* the
job's row, so the field is not derivable. Named here so the next reader does not price
it as a missed simplification.

---

## Consequences

- **`ARM1_BURN_DOWN` is empty for the second time.** `check_addon_portability.py` is
  rc 0 with arm 1 at zero reach lines and the OK sentence carrying no arm-1 caveat.
  `exmateria_catalogue` now reaches no system at all.
- **`resolve()`'s job-routed contract is one key smaller.** Any future consumer that
  wants the row asks `SpritePaletteResolver.job_body_palette_row(job)`. Three tests
  assert the absence so a re-added key fails rather than silently returning.
- **`FormationScene.resolve_body_render` gains its first `palette_row` coverage**, and
  the unique branch's hardcoded `0` is now pinned.
- **The register grows by one test** (`test_the_caveat_seed_is_gone_and_the_tree_is_
  green`, the leak arm for the new seed) and one is re-shaped.
- **Two documents that described the debt are now describing history**: the catalogue
  README's arm-1 bullet, and ADR-0267 dec. 3's "NOT DECIDED" entry.
- **`tests/CharacterRosterParityTest.gd` no longer names `ExMateriaSpriteRig` at all.**
  Its alias line was deleted with its last use, so ADR-0211 dec. 4's grep-census stays
  exact.
- **#1059's inherited debt is 53 lines, not 55.** The catalogue's arm-5 resolved
  reading goes `{almanac 53, platform 6, sprite_rig 2}` -> `{almanac 53, platform 6}`,
  because sprite_rig's two lines WERE arm 1's row — the alias and the call it fed. Four
  documents quote the 55: ADR-0262 dec. 5 and its table at `:126`, ADR-0267's soft-spot
  note, and the handoff. **They are not edited here** (same rule as dec. 9); the number
  to use from now on is 53, and `CataloguePinnedToTheTree` carries the re-take.
- **The shape/resolved pair for the catalogue is 11/59, not 12/61**, and the ten-file
  membership is 1,676 lines, not 1,673. Every one of those is a pin this pass had to
  re-take rather than a number it was free to leave.

---

## Soft spots

**S1. The "no consumer read it" measurement is over THIS tree's three callers.** It is
a census of `CharacterTemplateResolver.resolve(` and it is exact today, but it is a
property of the current consumer set, not of the design. A future consumer that wants
to *branch* on the row (rather than forward it) would want it back in the dict — and
the right answer then is still to ask the rig, because the branch would need the job
anyway.

**S2. Nothing here has met a stranger rig.** ADR-0267 dec. 9's seventh rig found three
defects no `tools/` instrument could reach, and this change makes the catalogue's
`plugin.cfg` `deps=` closure *narrower* (it no longer needs `exmateria_sprite_rig` for
this file). The `deps=` line was **not** touched — other members may still need it, and
a `deps=` narrowing measured from one file is exactly the closure-vs-line error that
rig caught. Unmeasured, and named rather than assumed.

**S3. The two new host call sites are not byte-identical to what they replaced — they
are one indirection shorter.** The old route was
`resolve() → SpritePaletteResolver.job_body_palette_row → ContentPort → SpriteRigContent
→ JobDatabase`; the new one drops the first hop. The VALUE is proved identical for the
five-job spread by test, not by construction, and `AllTemplatesSeederTest`'s two
pre-existing reds were A/B'd against `origin/main`'s copies of all three changed runtime
files to confirm they are not this change's (477 passed / 2 failed, byte-identical on
both sides).

**S4. Dec. 9's finding is recorded and not repaired.** Four sites still carry the
address-move rendering of ADR-0167's rule, and one of them is an accepted ADR. Repairing
a phantom citation is a whole-corpus grep, not a line edit
(`check_adr_quotes.py` cannot see a paraphrase), and this pass declines to open it
inside a severance ticket — which is, with a straight face, the rule the paraphrase is a
paraphrase of.

**S5. The mutation proof of dec. 8 was run against `if burn:` only.** It shows the
caveat arm reads that gate. It does not show the *seeded row* is the only thing making
`PORTABILITY BURN-DOWN` print — a second, independent producer of that heading would
satisfy both directions. Arm 7 prints a different heading and was excluded by the
original test's scoping argument, which still holds.
