# The instruments see the shaders, the assets, and the closure

Prologue pass 4's instrument batch. The blueprint walk extends to **shader
source in all four of its extensions**, `src/data/` and `src/debug/` lose their
catch-alls, `touch_matrix.py` counts **lines** and a fifth shape, and two
instruments that no document had ever built — the **root-set closure** and the
**asset census** — now exist. Everything here moves a published number, so it
lands in one commit, before the baseline.

Status: accepted (2026-08-21). Amends
[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
dec. 5 (a fifth shape) and its Context table, corrects
[ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md) dec. 4's
census, discharges
[ADR-0142](0142-an-asset-belongs-to-the-system-that-owns-its-format.md)'s owed
instrument and dec. 8's missing arm, resolves
[ADR-0143](0143-the-root-set-is-ratified-and-the-formation-cluster-is-its-one-exception.md)
dec. 5, and narrows
[ADR-0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md)
dec. 8's mechanized consequence. Mechanizes
[ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md) dec. 1's
anti-shadow rule, which had been a comment.

## Context

**All figures measured at trunk `de055dc49`, on this branch, 2026-08-21.**
`classify_blueprint.py` before this commit is `34848f14f`; quote the classifier
revision with every reading (ADR-0131's fifth amendment says why).

### The shader census was half the shader body

ADR-0131 dec. 3 rules a line in if it is *"hand-written `.gd` or shader source
under `src/` and `assets/`"*. Two censuses then measured "shader source" by
globbing `.gdshader` and `.gdshaderinc`:

| | files | lines |
|---|---:|---:|
| ADR-0141 dec. 4's census | 86 | 6,290 |
| **`.glsl` + `.glslinc`, never counted** | **12** | **6,081** |
| trunk today, all four extensions | **101** | **12,627** |

Ten `.glsl` compute stages and two `.glslinc` headers sit under
`src/gpu/shaders/` — `stage_compute.glsl` alone is **1,237 lines**, larger than
any `.gdshader` in the tree, and `combat_common.glslinc` (1,267) is the status
bit layout `src/data/StatusRegistry.gd` verifies itself against at load. They
are **48% of all shader lines** and they belong to **`Battle`**.

ADR-0131's own Context table read *"shaders (`src/gpu`, `src/ui3`,
`assets/shaders`) — 194 files, 12,597 lines"*, which is the right body: 12,597
against today's 12,627. The line figure was correct on the day it was written
and the file figure counted `.uid`/`.import` sidecars. What went wrong is that
the **next** census re-derived the number from a narrower glob and nobody
compared the two.

**So ADR-0141 dec. 4's attribution is not merely a floor — it is a floor over
half the subject.** Its finding that shaders *"land mostly on `UI`, which is
already the second-largest system"* was the correction of a standing assumption,
and it is itself corrected here: with the compute half counted, the largest
shader owner is **`Battle` (6,239 lines, 49.4%)**, then `UI` (3,122, 24.7%). The
part of dec. 4 that survives intact is the part that mattered: **`Render`'s size
is not hiding a shader problem** — `Render` reads 258 shader lines, 2.0%.

### `src/data/` and `src/debug/` were the last two catch-alls

`("src/data/", "Battle")` booked **24 files / 2,432 lines**. Inside it:
`AbilityView.gd`, whose first line reads `# AUTO-GENERATED FILE - Do not edit
manually`; nine hand-authored FFT tables; and `JsonAsset.gd`, the shared
`load_dict` body that 21 files across five buckets call.

`src/debug/` matched **filenames as substrings**, and ADR-0140 dec. 1 had already
had to delete three entries for shadowing nineteen rules, closing with *"Keep
every entry here matching an actual file, or the shadow returns."* It was a
comment, so it returned:

- `"Map"` precedes `"Ui"`/`"UI"` in the table, so `UI3OwnerColorMap.gd` (327
  lines) and `UI3OwnerMapPicker.gd` (141) — whose every outbound edge lands in
  `UI` — were booked `Battlefield`;
- `"Cinematic"` books `Cutscene`, but `CinematicDebugProbe.gd` (323 lines) is
  constructed by `src/gpu/CombatLoop.gd`, read by `src/units/Unit.gd`, and reads
  `battle_state`/`GPUConstants`. It is the **combat spell** cinematic;
- `DetailScreenDebugPanel.gd` (158) matched nothing at all and returned `None`.

And when a guard was finally written for the rule, it found the wider version of
the same defect: **14 of the 41 `DEBUG_OWNER` fragments — 34% — can never fire.**
Eleven match no file (`Sfx`, `Music`, `Combat`, `Gambit`, `Gpu`, `Character`,
`Ui`, `Palette`, `Depth`, `Fold`, `Psx`) and three are wholly shadowed by an
earlier fragment. A third of the table read as intent and did nothing.

### Two instruments nobody had built

ADR-0112 dec. 1 — *"dead code is what the root set cannot reach"* — has been
unmechanized in both registers since it was written. Pass 3 built
`check_root_set.py`, which walks **candidacy and the assembler pairing**; it is
the closure's input, not the closure. ADR-0142's Consequences say the same of
assets in as many words: *"The asset instrument does not exist … there is no
committed tool, deliberately"*, deferred here so it lands with this batch.

## Decision

**1. The walk is `.gd` + shader source under `src/` AND `assets/`, and shader
source means four extensions.** `.gdshader`, `.gdshaderinc`, `.glsl`,
`.glslinc`. Sidecars (`.uid`, `.import`) are generated and are not source. The
one `.gd` under `assets/` (`assets/scenes/TuneSandbox.gd`, 33 lines, flagged by
ADR-0135 dec. 6 as *"invisible to classify_blueprint.py"*) is now walked.

`assets/shaders/` gets **exact-path rules, not a directory rule** — ADR-0129
dec. 11's treatment, for ADR-0131 dec. 3's stated reason: it splits by system
exactly as `src/effects/` did. Under `src/`, the existing directory rules
already own them.

`touch_matrix.py` gains **`#include` as a fifth shape**, amending ADR-0131
dec. 5's *"its four shapes are unchanged"*. Without it the 12,627 shader lines
the walk newly sees would contribute zero crossings — a blind spot manufactured
by the pass that closed the last one.

**2. `src/data/` loses its catch-all, and `content` is re-derived from source.**
Exact paths for all 33 files. `content` is CONTEXT.md's *Hand-authored data
asset* — the `JobDatabase` shape: a `class_name` store with a static cache, a
lazy `_ensure_loaded`, and one `JsonAsset.load_dict("res://assets/**.json")`.
That shape is **mechanical**, so `check_blueprint_walk.py` detects it from source
and fails if a store is booked to a system, rather than trusting the list.

`SpritePaletteResolver.gd` has the shape and is the one stated exception: it
implements `EVTCHR_CLUT_RESOLUTION.md`'s two-axis body-row rule *over* a baked
manifest, which is behaviour. That is ADR-0135 dec. 9's shape — *"a library …
not an assembler"* — one domain over.

Five picker-domain files (`AbilityCandidates`, `JobCandidates`,
`EquipCandidates`, `EquipStatDelta`, `LearnableAbility`, 465 lines) are booked
`UI`, where their sole inbound caller is — four of the five are
`FormationDetailTransition.gd`. **Named soft spot:** these are equip/learn
*rules*, and `Character Catalogue`'s chunk has a real claim on them.

**3. The `src/debug/` fragment table gets an exact-stem table in front of it,
and the dead entries go.** Exact before substring, exactly as `RULES` puts exact
paths before directory prefixes. Reordering the fragments would have fixed the
two known cases and hidden the next pair. Fourteen dead or shadowed fragments
are deleted; a future panel no fragment reaches now lands in `UNCLASSIFIED`,
which is the no-catch-all property working, not a hole.

**4. `NavigatorMain.gd` is an assembler. `FormationScene.gd` and
`FormationDetailTransition.gd` are not — and the CHECK was what was wrong.**
This resolves ADR-0143 dec. 5, which stated the question deliberately.

ADR-0135 dec. 8 is one sentence with two halves: *"a root scene is one nothing
instances, and its assembler is the script nothing calls."* Applying it:

| root script | called by | verdict | lines |
|---|---|---|---|
| `src/scenarios/NavigatorMain.gd` | nothing — every `NavigatorMain` mention in `src/` is prose or a duck-typed executor slot | **`assembler`**, out of `Campaign` | 1,185 |
| `src/ui3/formation/FormationScene.gd` | **5 files, 14 non-comment sites** — `FormationMapHost.gd` **`extends`** it; `AllTemplatesFormationBoot.gd` and `FormationDetailTransition.gd` `.new()` it; the two `detail/*Boot.gd` read off it. Published API: `SCREEN`, `PIXELS_PER_UNIT`, `ROWS`, `COLS`, `BREAKOUT_MARK_PX`, `build_changejob_wheel()`, `vitals_view_from_character()` | **stays `UI`** — a base class with a constant API | 3,482 |
| `src/ui3/formation/FormationDetailTransition.gd` | `src/scenes/GPUArena.gd` and `src/scenarios/NavigatorMain.gd`, both via `mount_over_map()` | **stays `UI`** | 2,642 |

The second row is decisive on its own: a script one file `extends` and four more
read constants and factories off is a **library**, and booking 3,482 lines of it as wiring
would say the opposite of what the code does. The third is not a judgement call
at all — *a library called by two roots* is verbatim the case **ADR-0135 dec. 9
already resolved**, away from `assembler`, for `AllTemplatesSeeder.gd`.

So `check_root_set.py`'s check 4 is **narrowed**: it requires a root's script to
be booked `assembler` only where check 3 is clean for that root. It was
asserting a consequence dec. 8 does not reach. Its `KNOWN` set shrinks **6 → 3**;
the three that remain are ADR-0143's ratified findings, not deferrals.

**5. The closure exists: `tools/closure.py`.** Seeds are the 11 declared roots
(scene + script) plus the **27 autoloads**, which Godot instantiates before any
scene and so cannot be reached *from* a root. Seven static edge kinds, including
the `res://`-string-anywhere rule pass 3 needed and a per-**segment** expansion
of built paths.

That last rule is the one that had to be got right. Expanding
`"res://assets/effects/E%03d/frames.json"` to its containing *directory* reached
all 23,827 files from a single literal and reported **0.0%** of assets unread —
a number that looks like an answer. Each `%…`/`{…}` placeholder stands for one
path **segment** (`[^/]+`), and the reading becomes:

| | files | lines / bytes |
|---|---:|---:|
| unreached source | **34** | **5,319 lines** |
| … of which reachable from a **declined** scene | 21 | 4,027 lines |
| … reached by **no declared scene at all** | **13** | **1,292 lines** |
| unreached asset bytes | 1,121 | **56,685,442 (7.4%)** |

**UNREACHED is a CEILING on deadness, not a floor** — the inverse of the reach
count's direction (ADR-0131 dec. 6), and the report says so. Every edge is
static, so the list holds everything genuinely dead *plus* anything reached only
dynamically. The walk publishes its own holes: **117 non-literal `load()` sites**
against 488 `preload("literal")` and 48 `load("literal")`, 20 built paths, and
47 dangling `res://` literals naming nothing on disk.

Three of the thirteen corroborate the shader rules above from the other
direction: `bitmap_char_3d.gdshader`, `ui_nearest.gdshader` and
`cursor_clut_preview.gdshader` are exactly the `assets/shaders/` files the
filename grep found no `.gd` reader for.

**Declined is not deleted** (ADR-0135 dec. 11), so the declined scenes' closure
is walked separately and reported as its own line rather than folded into
deadness. `ProgressionTester.gd` (1,466) and `CombatUITestScene.gd` (164) are in
it — which is the mechanical form of the known-wrong *Test scenes* section of
`godot-learning/CLAUDE.md`.

**6. The asset census exists: `tools/asset_census.py`**, and every content byte
under `assets/` has a **format owner**. It is ADR-0142's own recipe — families
by digit/hex normalisation, booked by grepping `src/` for the quoted filename —
with dec. 1's format-owner override on top, which is the step a read-ownership
census cannot take by itself. It reproduces ADR-0142's three packet-class totals
**to the byte** (208,845,247 / 91,726,944 / 265,127,968).

It also reaches the two classes ADR-0142 never measured, **198 MB**:

| packet class | content bytes | format owner | largest reading system | no reader in `src/` |
|---|---:|---|---|---:|
| `assets/effects/` | 208,845,247 | `Effects` | `Effects` 81.3% | 0.0% |
| `assets/characters/templates/` | 91,726,944 | `Sprite Rig` | `Sprite Rig` 25.2% | 2.3% |
| `assets/maps/` | 265,127,968 | `Battlefield` | `Battlefield` 67.1% | 25.3% |
| **`assets/scenarios/`** | **77,853,620** | `Cutscene` | `assembler` 53.0% | **43.4%** |
| **`assets/sprites/`** | **120,583,297** | `Sprite Rig` | `infrastructure` 13.1% | **68.4%** |

Both new classes make ADR-0142 dec. 1's case better than the three it was
decided on: `assets/sprites/`'s largest *reader* is `infrastructure` — the asset
manifest — and its format owner is plainly `Sprite Rig`. Read-ownership and
format-ownership do not merely disagree at the margin; on 120 MB they disagree
about the top entry.

**7. The reach count is LINES, and the two units are not comparable.** ADR-0131
dec. 5's conversion, done. The change is decomposed so neither half hides the
other:

| reading | unit | value |
|---|---|---|
| published baseline (old classifier, old instrument) | file-edges | **400** |
| **new classifier**, old instrument | file-edges | **342** |
| new classifier, new instrument | file-edges | 350 |
| **new classifier, new instrument** | **lines** | **1,143** |

`class_name` 724 · autoload 358 · `preload` 51 · `#include` 7 · `/root/` 3. The
**−58** is the rebookings alone, measured in the old unit. The **+8** is the
instrument: **7** of it is the new `#include` shape, and the widened `preload`
target set (any walked source file, not only `src/**/*.gd`) nets the eighth. The
floor caveat is unchanged and still printed on every run.

**8. Line totals move by 12,660, and every line of that is the widened walk.**
533 files / 177,748 lines → **635 / 190,408**. The added 102 files are the 101
shaders plus `TuneSandbox.gd`, totalling exactly 12,660 lines; the rebookings
are zero-sum by construction, which is the arithmetic check that they *were*
rebookings. `UNCLASSIFIED` goes 158 → **0**.

| bucket | before | after | Δ |
|---|---:|---:|---:|
| `Battle` | 17,792 | 23,066 | **+5,274** |
| `UI` | 34,219 | 38,432 | **+4,213** |
| `assembler` | 7,201 | 8,419 | +1,218 |
| `Sprite Rig` | 3,928 | 4,957 | +1,029 |
| `content` | 931 | 1,424 | +493 |
| `Battlefield` | 7,790 | 8,247 | +457 |
| `Effects` | 57,145 | 57,480 | +335 |
| `generated` | 19,411 | 19,677 | +266 |
| `Render` | 905 | 1,163 | +258 |
| `schema` | 909 | 1,086 | +177 |
| `platform` | 748 | 863 | +115 |
| `Cutscene` | 16,062 | 16,166 | +104 |
| `infrastructure` | 249 | 313 | +64 |
| **`Campaign`** | 2,308 | **1,123** | **−1,185** |
| `UNCLASSIFIED` | 158 | **0** | −158 |

**9. The rules are guarded: `tools/check_blueprint_walk.py`**, guard #24. It
fails on a `None` (dec. 3's minimum), and on four more things that were prose:
a rule naming a file that does not exist; a rule **shadowed** by an earlier one;
a dead or shadowed `src/debug/` fragment (ADR-0140 dec. 1, mechanized); and a
`src/data/` file with no exact rule or a store booked to a system. It was
negative-tested six ways — each defect reintroduced, caught, and removed again.

## Consequences

- **The baseline pass 5 will take is the reading above**, at a stated commit and
  a stated classifier revision. Instruments are now settled; ADR-0131's
  *"instrument changes land in prologue pass 4"* is discharged.
- **`Battle` overtakes `UI` for second place** and `Campaign` halves. Neither is
  a code change. This is the fifth time the baseline has moved without anyone
  touching the game, and it is the last one the prologue permits.
- **⚠ `psx_par.gdshaderinc` and `psx_dither.gdshaderinc` have the shared kernel's
  exact shape and ADR-0139 does not list them.** `psx_par` is `#include`d by 16
  shaders across six buckets and has its own guard (`check_par_shaders.py`,
  ADR-0060), which is precisely what makes `psx_ot_depth.gdshaderinc` a kernel
  member. They are booked `platform` here rather than silently widening a kernel
  this pass may not redefine. **Pass 6 decides**, and should say why if the
  answer is no.
- **13 files / 1,292 lines are reached by no declared scene**, and 56.7 MB of
  assets by nothing at all. Both are candidate lists for pass 5, not verdicts;
  ADR-0142 dec. 8's *"do not delete the 27.5 MB"* stands, and the closure now
  says the real figure is twice that.
- **`src/data/`'s five picker-domain files are the one placement worth
  re-opening** when `Character Catalogue`'s chunk runs. Nothing else here is a
  judgement call the guard cannot re-derive.
- **The instruments disagree by design.** `asset_census.py` says who owns the
  bytes; `closure.py` says whether anything reads them; a packet can be wholly
  owned and wholly unread. `assets/sprites/` is 68.4% unread and 100% `Sprite
  Rig`'s.

## Considered alternatives

- **Reorder `DEBUG_OWNER` so `Ui` precedes `Map`.** Rejected: it fixes the two
  known cases and leaves the next pair to be found by hand. An exact table in
  front, plus a guard on dead and shadowed entries, fixes the class.
- **Book `FormationScene.gd` `assembler` to satisfy ADR-0135 dec. 8's
  consequence.** Rejected: three files `extend` it or read its constants. The
  check was over-reaching, not the code.
- **Expand a built `res://` path to its containing directory.** Rejected, with
  the measurement: it reported 0.0% of assets unread and 6 dead files, against
  7.4% and 34. A wrong closure that looks decisive is worse than none.
- **Widen ADR-0139's kernel to take `psx_par`/`psx_dither`.** Rejected here: it
  is pass 6's decision and this pass is an instrument pass. Recorded so pass 6
  cannot miss it.
- **Land the six items separately.** Rejected by ADR-0131 and by #331's
  precedent: each moves every published number, so none may ride in a commit
  that quotes them.
