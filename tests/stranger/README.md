# Stranger rigs — a guard that travels with the thing it guards

A **stranger project** is a Godot project that did nothing for the addon: no
autoloads it did not ask for, no bus layout, no assets, no host scripts. It is
the environment an addon has to work in for `docs/GOALS.tsv` goal #5 — *"a system
could ship to another tactics RPG with its interface intact"* — to mean anything,
and it is the vocabulary `CONTEXT.md` → **Test scoping** defines.

🔴 **A rig buys the INSTALL half of goal #5, not goal #5.** The other conjunct is
the cross-system reach count, which a rig cannot see, and a reach count cannot
see whether the addon comes up. Before ADR-0232 both instruments claimed the
whole word and disagreed in silence — `docs/GOALS.tsv` scored `Sprite Rig` goal
#5 `met` on 0 reach lines while this rig printed UNMET naming two files on the
same tree, both green. `tools/score_goals.py` now holds the join and
`_walk_roots.RIGS` is the register that says which addon each rig is about,
including the two that live outside this directory.

One directory per addon, plus `shared/` for the arms more than one rig needs.
**All six in-walk addons have one** — `exmateria_schema`,
`exmateria_battlefield`, `exmateria_platform` and `exmateria_render` as of
ADR-0210 dec. 6, `exmateria_sprite_rig` as of ADR-0229, and `exmateria_almanac`
as of ADR-0251. Before dec. 6 the platform and render addons had no rig, no
`tests/`, and no `engine=` in `plugin.cfg`, so `rig.sh` would have exited 2
(could-not-run) — correctly, and silently as far as any suite was concerned.

🔴 **SOMETHING SAYS A RIG IS MISSING NOW, AND THE SIXTH ADDON IS WHAT PROVED
IT.** This paragraph used to read *"nothing says a rig is missing, and that is
still true"*, and it was the only reminder: `tools/_runner_tests.stranger_rigs()`
GLOBS `tests/stranger/*/run.sh`, so the suite reports however many rigs exist and
never that one is owed, while `classify_blueprint.WALK_ROOTS` is the register of
in-walk addons — two registers, no join. That is how `exmateria_sprite_rig` was
the fifth in-walk addon for three days with no rig and no ticket, found by
noticing the absence of a `[PASS] stranger:…` line in a suite summary.
`_walk_roots.RIGS` closed it (ADR-0229 dec. 8, ADR-0232): `rigs()` RAISES when an
addon root has no row, and raises again when a `run.sh` exists that no row names.
`exmateria_almanac` is the first addon to arrive AFTER that join — its rig's
docstring arm 3 had already named it in the abstract as *"the sixth rig landing
without a row"* — and it landed with its row in the same commit as its root
(ADR-0251 dec. 9). **Every in-walk addon now has a rig**, and the last two arrived the
way the register intends: `exmateria_catalogue` at #1025 pass 3 and
`exmateria_effects` at #1225, each with its row in the same commit as its root.

🔴 **AND THE REGISTER IS WHY THE EIGHTH RIG EXISTS AT ALL.** #1225 put
`addons/exmateria_effects` in `WALK_ROOTS` and `rigs()` raised — which is the join doing
its job, and also a cost a plan ADR did not price: the README's own wording, *"or is
declared as having none"*, has **no code behind it**. `rigs()` requires a row AND requires
the row's `run.sh` to exist, so an addon joining the walk has committed to writing a rig
in that same commit. There is no declaration that stands in for one.

    tests/stranger/shared/rig.sh               # the ONE implementation
    tests/stranger/shared/stranger_install.gd  # the baseline arm, for any subject
    tests/stranger/shared/stranger_fork_absent.gd
    tests/stranger/exmateria_schema/run.sh     # a three-line shim naming its own dir
    tests/stranger/exmateria_schema/project.godot
    tests/stranger/exmateria_battlefield/…     # engine="fork", deps="schema platform"
    tests/stranger/exmateria_platform/…        # engine="stock" — the first, and see below
    tests/stranger/exmateria_render/…          # engine="fork", deps="schema"
    tests/stranger/exmateria_sprite_rig/…      # engine="fork", deps="schema platform"
    tests/stranger/exmateria_almanac/…         # engine="stock", deps="platform schema"
    tests/stranger/exmateria_catalogue/…       # engine="stock", four staged addons
    tests/stranger/exmateria_effects/…         # engine="fork", FIVE staged addons — and the
                                               # only rig with a NON-EMPTY known_failures.tsv
    tests/stranger/exmateria_almanac/…         # engine="stock", deps="platform schema" — see below
    tests/stranger/shared/stranger_burn_down.gd
    tests/stranger/<addon>/known_failures.tsv  # optional, and NAMED (see below)
    tests/stranger/<addon>/stranger_*.tscn     # optional, RIG-OWNED (see below)

`bash tests/run_all_tests.sh` does **not** run the scenes in here as
`res://tests/X.tscn` (ADR-0194 dec. 4) — that would run them in the host project,
which is precisely the project whose absence is the whole claim. They carry a
`stranger` row in `tests/skip_tests.tsv` saying so, and dec. 10's runner phase is
what invokes the rigs instead.

## The contract, which is not new

`exmateria-sound/workspace/acceptance/stranger_sound/` and `stranger_spu/` are
the originals; this is the same rig generalised to the four addons that never
left the walk. Every rig here keeps their contract exactly:

- a `mktemp -d` work dir with a `trap`, **staged fresh every run** — a reused
  tree cannot report a change to what gets staged;
- **one `godot --path "$WORK" -e --quit` import pass before any test.** A cold
  global class cache reads as a real parse error: without it the first test fails
  with `Identifier "ColorRecipe" not declared` and the rig reports a portability
  defect that is entirely its own;
- verdict = a `^[PASS]` line, and **exit 0 pass / 1 fail / 2 could-not-run**.
  A 2 is loudly *not* a pass — a missing engine or an unbuildable subject makes
  the rig report that it could not answer, never that the answer was yes.

Two things are ours rather than inherited:

- **The harness keeps its repo-relative path in the staged project**
  (`res://tests/stranger/<addon>/…`, not flat at the root). `stranger_sound`
  stages flat and can, because no guard reads that package's tree.
  `tools/check_res_paths.py` reads every quoted `res://` source literal under
  `godot-learning/` and resolves it against the HOST root; staged flat, a rig's
  own literals resolve in neither project and the guard is red on a correct
  checkout, which is how a guard gets ignored.
- **Source-copy staging** (ADR-0194 dec. 5/6), and the rig says so on every run.
  `stranger_sound` stages the *published* tree through the real manifest and buys
  the strictly stronger claim, *"this addon installs the way the ZIP installs"*.
  None of these four publishes, so a manifest would assert a publication that
  does not exist. The two claims are different and blurring them is how goal #5
  gets oversold, so the banner names the one being measured.

## The engine is declared, and a `fork` declaration is checked

Each addon's `plugin.cfg` carries `engine="stock"` or `engine="fork"`, and the
rig runs the declared binary. **An addon with no declaration exits 2** rather
than defaulting — a default is how a declaration stops being read.

For a `fork`-declared addon the rig also boots **stock** once and asserts the
fork's compositor primitives are absent there
(`tests/stranger/shared/stranger_fork_absent.gd`). That is what turns *"we think
this needs the fork"* into a checked fact, and the day those primitives land
upstream the arm goes red and reports that the addon can be downgraded — a win
nobody would otherwise notice. `check_addon_portability.py`'s four arms are all
blind to an engine dependency; this is the first instrument in the repo that can
say so.

## Known failures are NAMED, never counted

An addon that carries portability debt does not get a threshold. It gets
`known_failures.tsv` in its rig directory — `path <TAB> ticket <TAB> error signature
<TAB> why` — and the arm is a **set, in three directions**: an unlisted file that
does not compile is red, a listed file that *does* compile is red, and a row naming
a file that is not in the addon is red. A burn-down that only grows is a list
nobody ever deletes from; the second arm is what makes deleting it forced, and the
third is what stops a row describing nothing forever. Same shape as
`check_addon_portability.ARM1_BURN_DOWN`, and deliberately not a count.

The **signature** column carries its weight. A broken script throws whenever any
script naming it is loaded, so the rig cannot simply avoid looking — it has to be
able to say which throws this list already explains. Everything else a
`SCRIPT ERROR` says is still the finding.

Two scenes, because the throws have to go somewhere: `stranger_install` skips the
listed files so it stays clean, and `stranger_burn_down` loads exactly them, where
a throw is the declaration being true. **`exmateria_battlefield` now carries none** —
its `known_failures.tsv` lists nothing, which is the goal state *and* the state in
which the arm passes vacuously, so what keeps it honest is the first direction: an
UNLISTED file that does not compile is still the finding.

Four rows left that list by being fixed, in two pairs, and both pairs are worth
keeping on record. **Two were `ARM1_BURN_DOWN`'s own rows** — the static guard books
those as reach lines to be tidied later; in a project that is not this game they were
a hard compile failure. Same defect, priced differently, and the rig is what priced
it. **The other two were one debt wearing two addresses** — a `.tres` naming an atlas
and its palette as `ext_resource` links, and the `preload` of that `.tres` failing as
a pure cascade with no defect of its own. An `ext_resource` resolves at LOAD time,
before any code runs, so no setting could reach either; the material now takes both at
runtime through the host-injected content root, and both rows had to go together or
the burn-down would have redded on a row it had just fixed.

## Adding a rig

1. `plugin.cfg` gains an `engine=` line with the evidence in a comment beside it,
   and a `deps=` line if the addon needs sibling addons staged with it. Both are
   declarations the rig READS — it never guesses, and an addon that declares
   neither engine nor an existing dep exits 2.
2. `mkdir tests/stranger/<addon>/`, a three-line `run.sh` shim that `exec`s
   `../shared/rig.sh` with its own directory, and a `project.godot` named
   `stranger_<addon>` — the name is how the shared arm learns its subject, and a
   name that does not resolve to a staged directory is a FAILURE, not a skip.
3. **Prove the rig red before trusting it green** (ADR-0194 dec. 12 arm 3): break
   the addon on purpose, confirm a non-zero exit, restore. `exmateria_schema`'s
   was proved five ways — a member preloading into `res://src/`, a shader seam
   that stops compiling, the one resource member deleted, an addon staged with no
   source files at all, and the engine arm run on the engine it must refuse.
4. Add a `stranger` row to `tests/skip_tests.tsv` for any scene the rig owns that
   `tests/` does not already carry one for. A rig with no scenes of its own —
   `exmateria_render` is this today — adds no row: the three `stranger_*` shared
   scenes are already listed. `exmateria_platform` stopped being one at ADR-0238,
   which gave it `global_uniform_unvalidated.tscn`.

## A rig may own scenes, and until ADR-0229 they were staged and never run

`rig.sh` runs four kinds of scene, in this order: the shared `stranger_install`
arm, the shared `stranger_burn_down` arm when the burn-down has rows, every
`addons/<addon>/tests/*.tscn` the subject ships, and **every
`tests/stranger/<addon>/*.tscn` the rig itself owns**.

🔴 That last loop did not exist until ADR-0229, and both ends of the contract had
assumed it did: the staging step has always copied `$HERE/*.gd` and `$HERE/*.tscn`
into the work dir, and step 4 above has always told the author to add a skip row
"for any scene the rig owns". Nobody noticed for the same reason these controls
always go quiet — all four rigs owned zero scenes, so the gap cost nothing until
the day it would have silently swallowed an arm.

**When a scene belongs to the RIG and not to the ADDON.** An
`addons/<addon>/tests/` scene runs in the host suite *and* in the stranger
project, so it may only assert things true in both. A claim the host FALSIFIES
belongs to the rig. `exmateria_sprite_rig`'s viewer arm is the case: it asserts
what `SequenceViewer` does when no host declares
`exmateria_sprite_rig/content_root`, and `godot-learning/project.godot` always
declares one. That is ADR-0194 dec. 4's rule read in the other direction.

**A rig-owned scene is held to the same throw rule as any other** — a
`SCRIPT ERROR` the burn-down does not explain is the finding.

🔴 **AND IT MAY NOT SPELL ITS SUBJECT'S PATH.** Learn the addon root from
`application/config/name` the way `shared/stranger_install.gd:_subject()` does,
and reach in with a relative subpath. Two reasons, and the first is the rig's
own thesis: a guard that hardcodes its subject's directory breaks the day the
subject moves, which is the single event this whole family exists to survive.
The second is mechanical — `tools/check_lattice_scene.py`'s criterion 4 fails
any file outside the addon that names an `res://addons/<subject>/` path, and a
rig row could never be paid off, because ADR-0194 dec. 3 puts the rig outside
the addon *by rule*. The first draft of the viewer arm did spell it, and the
guard caught it before the branch landed.

### `engine="stock"` is a claim too, and a different arm checks it

`exmateria_platform` is the first `stock` declaration here, and `exmateria_almanac`
(ADR-0251 dec. 9) is the second. It is the **stronger** statement, not the weaker
one: it says the layer carries no fork dependency at all. 🔴 **dec. 7's absence arm does not check it** — that arm
runs only for `fork`, because its subject is primitives being missing. What checks
a `stock` declaration is the install pass itself: `RUN_GODOT` *is* the stock
binary, so it is stock that loads every staged file, and a fork-only API
creeping into the addon reds the rig.

🔴 **AND THAT MECHANISM HAS ONE MOVING PART, WHICH MOVED (#1099).** It holds only
while `RUN_GODOT` is the subject's declared binary. Since the closure-engine block
`RUN_GODOT` follows the dependency CLOSURE, so for a subject that declares `stock`
and depends on a `fork` addon the install pass runs on the **fork** and checks
nothing about the declaration. `exmateria_catalogue` was the first such addon and
`exmateria_almanac` is the second since #1159, which gave it a `deps=` on the
`fork`-declaring `exmateria_schema` so that `UnitRole` could leave for the shared
kernel (ADR-0280 dec. 3). The catalogue was born that way; the almanac was MOVED
into it, which is the first time this repo has spent this guarantee rather than
inherited it. Seeding the fork-only call that once redded the almanac
(rc 1, named) leaves the catalogue rig at **rc 0, `33 passed, 0 failed`**, and
the almanac's rig now has the same blind spot. The rig
now says so in the absence arm's trailing lines rather than implying the opposite,
but saying so is not checking it — goal #5 is unmet on the declaration axis there.

A static grep for the primitives is **not** the missing arm, and this file's own
corpus says why: `exmateria_sprite_rig/plugin.cfg` notes that
`render/unit_flat.gdshader:53` names a primitive *"only in a comment — a comment is
not a primitive, and the grep that finds both is not the measurement."* The surface
is wider than the two names `stranger_fork_absent.gd` holds — `render_mode …
compositor_layer` in four `exmateria_battlefield` shaders, `CompositorEffect`'s
`render_layers` and `get_layer_texture` in `exmateria_render` — and a naive scan
matches every `plugin.cfg`, because the evidence comments beside each declaration
name the primitives too.

🔴 For `exmateria_almanac` that arm is doing more work than it does anywhere else,
because **thirteen JSON payloads moved into the addon with their readers**
(ADR-0251 dec. 2) and the install pass is the only instrument that resolves a
staged `res://addons/exmateria_almanac/**.json` under a foreign `project.godot`.
A payload left behind in `assets/` would not be a parse error and no static guard
in `tools/` would see it; the rig comes up empty-handed and says so. Proved by seeding exactly that (a
`RenderingServer.is_compositor_layer_supported()` call in `PsxNum.gd`): rc 1,
reported as a parse error, which is what a fork-only static call is on 4.7.1.

### The absence arm cannot be pointed at the wrong engine

Proving dec. 7's arm red for a new rig by exporting `GODOT_STOCK=<the fork>` does
**not** work, and that is the rig defending itself rather than a gap: `resolve
stock` rejects any binary whose `--version` contains `custom_build` and falls back
to `/usr/bin/godot`, so the run comes back green having quietly used the right
binary. Run the shared scene directly under the fork instead —
`godot --path . res://tests/stranger/shared/stranger_fork_absent.tscn` — which
reports `[FAIL]` naming both primitives.
