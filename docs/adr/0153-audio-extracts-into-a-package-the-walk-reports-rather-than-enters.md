# `Audio` extracts into a package the walk reports rather than enters, and its config seam is one host adapter

Extraction #2's scope pass. `Audio`'s destination is the **canonical
`exmateria-sound/` package**, not a new addon inside `godot-learning/` — the
first extraction whose output leaves the walked tree. `WALK_ROOTS` does **not**
follow it; the `extracted` row becomes a re-measured reading instead, or the
relocation reads as a ~1,530-line deletion.

The four autoloads collapse to **one host adapter of about twenty lines**. And
**[#393](https://github.com/timbermania/fft-monorepo/issues/393) is not the open
question it states**: two of its three candidates are already closed by Accepted
ADRs. What is genuinely open is that [ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md)
dec. 8's own stated soft spot came true at extraction #1, and the guard it
declined to write is the owed artifact — **owned by [ADR-0151](0151-an-addon-reaches-no-system-and-a-declarative-panel-is-not-built.md)**, which this pass
consumes rather than restates.

Status: accepted (2026-08-22). Loop passes 3–4 of extraction #2
([ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md) dec. 5).
Discharges [ADR-0136](0136-audio-is-one-opcode-language-in-two-containers.md)
dec. 7's deferred `shared/` rename and **corrects it**; applies
[ADR-0113](0113-tunables-invert-at-the-addon-boundary.md) as amended by ADR-0140
dec. 4–8; consumes [ADR-0118](0118-payloads-are-schemas-services-are-ports.md)
dec. 6; extends [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
dec. 7–8 and [ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md)
dec. 1; amends `BLUEPRINT.md` §7 and its *Subscription, not calls* paragraph.
Closes [#326](https://github.com/timbermania/fft-monorepo/issues/326) and
disposes of #393's framing — #393 itself closes against ADR-0151. Held by
[#392](https://github.com/timbermania/fft-monorepo/issues/392); feeds
[#377](https://github.com/timbermania/fft-monorepo/issues/377).

Code at `78ab1fcd6`, classifier at `1b9ba2ba3`. Both named, per ADR-0131's fourth
amendment. Every census figure below is measured at that commit, not quoted from
a prior pass.

> **Planned into tickets 2026-08-22 at loop pass 5.** Spec
> [#400](https://github.com/timbermania/fft-monorepo/issues/400); slices
> [#401](https://github.com/timbermania/fft-monorepo/issues/401)–[#410](https://github.com/timbermania/fft-monorepo/issues/410),
> sequenced so no commit is ever red. **Three decisions were re-measured before
> the tickets were written and three amendment blocks below record what failed**
> — dec. 6's destination directory does not exist and its rename count is 33 not
> zero, dec. 8's 41 is the wrong number to plan against, and dec. 10 never named
> the symbol it renames. The one sequencing decision pass 5 added is that the
> config seam (#408) and the two file splits (#409) land **in place**, before the
> lift (#410): prefactor, then relocate, or the driver arrives under an addon root
> still naming `Tune` and sits red against ADR-0151's guard between two tickets.

**ADR numbers 0149–0152 are reserved** by the concurrent
`refactor/extraction-1-render-goals` session (goal scoping, `PSXDisplay`
placement, `Render`'s debug panels, a possible RGB555/PAR split). This pass
starts at 0153 by agreement, and **does not touch `docs/agents/refactor-loop.md`'s
goals paragraph** — that artifact is [ADR-0149](0149-the-ten-goals-are-scored-per-extraction-and-three-of-them-are-not.md)'s, landed on that branch at
`5a3708743` with `tools/score_goals.py` and `docs/GOALS.tsv`.

**ADR-0149, ADR-0150, ADR-0151 and [ADR-0154](0154-goal-1-is-about-decisions-and-goal-3-is-about-orphans.md)
were cited here as plain text, not as links, because none of those files existed
on this branch and `check_adr_classification.py`
fails a relative link that does not resolve. Converted 2026-08-22** when PR #399
merged and trunk moved to `b61f7f02b`, which is the merge that brought them
together. The conversion is one-directional for now: **that branch's references
to ADR-0153 stay plain text until extraction #2 merges**, for the same reason.

## Context

ADR-0136 dec. 5 found `Audio`'s real shape — *"15,953 addon lines plus a
1,261-line driver the host still owns, behind four autoload names"* — and called
the extraction a **driver split**. ADR-0141 dec. 6 re-derived the host figure to
8 files / 2,180 live lines. Both are close and both are now stale by a little:
at `78ab1fcd6` the instrument reports `Audio` at **13 files / 2,834 lines**, of
which the five declined-scene entry points ADR-0112 dec. 2 /
[ADR-0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md)
exclude are 637, so the live figure is **8 files / 2,197 lines** and
`EffectSfxEngine.gd` is **1,267 of them (57.7%)**. Correcting a prior pass's
number is the normal cadence here; the conclusion does not move.

What the scope pass found is that `Audio` is the first system whose **destination
already exists, is published, and lives outside the tree the refactor measures**.
Extraction #1 could add one line to `WALK_ROOTS` because `addons/exmateria_render/`
was created inside `godot-learning/`. `Audio` cannot, and the choice was never
faced before.

## The audit (ADR-0126's six checks)

**1 · The crossings, read as a floor.** `touch_matrix.py` at `78ab1fcd6`, unit =
lines. The whole inventory, from `tools/.touch_cache.json`:

| direction | lines | symbol → where |
|---|---:|---|
| in, from systems | **46** | `ExMateriaEffectSfx` **22** (Effects: `EffectInstance` 11, `EffectStudioPage` 10 + 1 preload) · `SfxRouter` **16** (Cutscene 7, UI 6, Battle 2, Battlefield 1) · `MusicPlayer` 4 (Cutscene) · `ExMateriaAudioEngine` 2 (Effects) · `AttackSfxResolver` 1 (Battle, preload) · `SfxCatalog` 1 (Cutscene, preload) |
| in, from `assembler` | 6 | `SpuAudioDebugPanel` 3, `MusicPlayer` 3 |
| out, into systems | **8** | `Battle`: `SfxRouter` → `UnitProgression` 3 · `Debug`: `ExMateriaEffectSfx` → `DebugConfig` 1, `SpuAudioDebugPanel` → `BaseDebugPanel` 1 / `TuneField` 3 |
| out, into `other` buckets | 10 | `platform`: `Tune` 4 · `infrastructure`: `UserSettings` 3, `JsonAsset` 2 · `DELETE`: `EventBus` 1 |
| out, **uncounted** | 8 | into `addons/exmateria_sound/` — the register ADR-0148 dec. 1 prints |

The floor caveat bit here and is worth stating: the printed `Audio → Debug` cell
is 5, but the seam that has to be designed is **17 lines across six symbols**,
because `Tune`, `UserSettings`, `JsonAsset` and `EventBus` land in `other`
buckets, which ADR-0131 dec. 2 excludes from the reach count by design. **A
system's portability seam is not its cross-system column.** The handoff into this
pass named four autoloads; measured, it is four autoloads plus three more host
symbols.

**2 · The blueprint's claim about this system, tested rather than inherited — and
it is false.** `BLUEPRINT.md` §7 says `Audio` *"Subscribes to `Effects`' sound
channel"*, and the *Inside Effects* section states it as a general rule:
*"**Subscription, not calls.** `Effects` never calls `Audio`, `Camera` or
`Body`."*

Measured, the arrow points the other way and there is no subscription at all.
`Audio → Effects` is **zero lines**. `Effects → Audio` is 24, and eleven of them
are `EffectInstance.gd` calling the driver imperatively —
`ExMateriaEffectSfx.begin_effect()`, `.play_pair(tok, bank, pair_idx, sound_id)`,
`.end_effect()`, `.orphan_effect()`. The one signal in the picture,
`pair_triggered`, is emitted by an **addon** object (`effect_sound_controller.gd`)
that `Effects` owns and subscribes to itself, and whose handler then calls the
driver. `Audio` subscribes to nothing.

Recorded in `BLUEPRINT.md` rather than quietly rewritten, per ADR-0126 check 2
and the `BLUEPRINT-AUDIT.md` precedent. This is the second system whose
"knows/subscribes" sentence failed on first contact, after `Effects`' *"never
learns what a combatant is."* **The sentence is written about `Camera` and `Body`
too and has never been tested for either.**

**3 · The muxed slot, and the demux that already exists above it.** It is
`capture_mode`. `ExMateriaEffectSfx` is one class doing two jobs — the always-on
live driver (an autoload with a producer thread and a generator) and an offline
renderer (`init_as_capture`, `render_subs`). The demux **already exists above**:
`EffectStudioPage.gd:3546` does `EffectSfxEngineScript.new()` then
`init_as_capture()`, an instance deliberately not in the tree. And it is
**defeated in the other direction**: the same page sets `capture_mode` on the
*live autoload* across frames (`:3942`, and the "capture-mode dance" documented
at `:4718`), because setting it parks the live producer. So the flag is both an
instance-kind discriminator and a global park switch. Per ADR-0126 check 3 the
existing demux is found before proposing one: the second use is the defect, and
the fix is a `park()` / `unpark()` verb, not a second boolean.

**4 · Units on every typed payload.** The `Effects → Audio` payload is
`play_pair(token, bank, pair_idx, sound_id)`, and it carries **two off-by-one
conventions that the caller is required to know**. `sound_id` is FFT's 1-based
cue id; `pair_idx` is `sound_id - 1`, and the subtraction is done at every call
site on **both sides of the boundary** — `EffectInstance.gd:504` and `:527` in
`Effects`, `SfxRouter.gd:159` in `Audio`. A third `+1` rule, unrelated, governs
WAVESET instrument indexing (`shared/opcodes/instrument.gd`) and leaks out to
`EffectStudioPage.gd:4837`. It also carries `bank` — a parsed `FedsBank`, an
`Audio` format object the caller obtained for itself, which is
[ADR-0142](0142-an-asset-belongs-to-the-system-that-owns-its-format.md)'s
finding arriving as an interface rather than as an asset. ADR-0124 specified this
crossing as *"a code and a time"*. It is a code, a time, an off-by-one, and a
parsed bank.

**5 · Spellings of the contested resource.** The contested resource is the
instrument bank, and it has **three spellings**: `ExMateriaAudioEngine.WAVESET_PATH`
(a literal), `MusicPlayer.WAVESET_PATH` (composed from `MUSIC_DIR`), and the
addon's own `runtime/asset_paths.gd`, which resolves `SOUND/WAVESET.WD` from an
environment root and which the host never calls. The second load is guarded
away in the normal path — `smd_player.gd:82` short-circuits on
`_engine_attached`, and `MusicPlayer.gd:44` attaches `ExMateriaAudioEngine`'s shared
parser — so this costs no duplicate parse today. It costs a **second path
constant that only executes when the first one has already failed**, which is
the worst possible time for it to be independently maintained.

**6 · The live set, before quoting any number.** 13 classified files / 2,834
lines; five are declined-scene entry points (637 lines) that ADR-0135 dec. 11
keeps classified until the deletion pass. **Reason about `Audio` as 8 files /
2,197 lines.** Every prediction below uses 13 / 2,834 for the instrument and
8 / 2,197 for the design, and says which.

## Decision

**1. The destination is the canonical `exmateria-sound/` package, and the walk
REPORTS it rather than follows it.** This is the address question, and it is the
one thing extraction #1's precedent does not settle.

`Audio`'s addon is not created by this refactor. It exists, it is published to
`timbermania/ExMateria-Sound`, and it is authored at
`exmateria-sound/addons/exmateria_sound/` — a sibling package with its own
version. `godot-learning/addons/exmateria_sound/` is a **gitignored deployment
target** written by `godot-learning/tools/sync_exmateria_sound.sh`
(`.gitignore:3`), not a source tree. So pass 6 edits the canonical package and
re-runs the sync; the host copy is a build output.

The three ways to keep the metric honest, and why two fail:

- **Add `addons/exmateria_sound` to `WALK_ROOTS`.** Rejected. It is untracked and
  drifted, so the census stops being reproducible from a checkout; it
  double-counts against the `extracted` row ADR-0131 dec. 8 already reads
  canonically; and `tools/_walk_roots.py` has the reproduction written into it —
  the addon's asset-path resolver legitimately reads eight environment variables
  and `check_no_env_vars.py` goes red immediately.
- **Add `../exmateria-sound/addons/exmateria_sound` to `WALK_ROOTS`.** Rejected,
  and worse: it injects **15,961 lines** of another package's authored code into
  a frozen baseline in one commit, and fuses two independently-versioned line
  counts into one longitudinal series. That is the instrument-changes-mid-series
  failure the whole prologue exists to prevent, arriving as a walk root.
- **Create a second addon `addons/exmateria_audio/` inside `godot-learning/`.**
  Rejected on #392: the refactor models `Audio` as one system → one addon, the
  two-addon split is map #373's `D1`/`B2`, and the driver preloads six files from
  `exmateria_sound` — so a second addon buys a walk root and pays for it with an
  addon-to-addon dependency that answers nothing.

**So `WALK_ROOTS` does not change at extraction #2, and extraction #1's precedent
is narrowed rather than extended.** The rule is: *the walk follows the refactor's
output while that output stays inside the host package; once it crosses a package
boundary the walk stops following and starts **reporting**.* That distinction is
already latent in ADR-0131 — dec. 7 says extracted systems are reported, not
vanished, and dec. 8 says the extracted row is read canonically — and nobody had
needed it as a rule until now.

**What must change is that dec. 7 is a static row, and a static row cannot report
a move.** `check_baseline.py --delta` prints only `SYSTEMS`; the `exmateria_sound`
row sits in `BASELINE.tsv` at 152 / 15,961 and is never re-measured. Move ~1,530
lines into it today and `--delta` prints `Audio −1,530` with no counterpart —
precisely the *"a system \"extracted\" by deletion"* reading ADR-0131 dec. 7 was written to
prevent and ADR-0146 dec. 5 re-found. **`--delta` gains a re-measured `extracted`
reading**, a second walk over the canonical package, printed beside the systems
with its own total. Same shape as ADR-0148 dec. 1 turning ADR-0145 dec. 5's prose
caveat into a reading: an invariant nobody can act on is not an instrument.

It does **not** join the schema check or the frozen data, and it is **reported,
never asserted** (ADR-0145 dec. 4).

> **Amended 2026-08-22, same day, by the concurrent branch's `score_goals.py
> --root`: `--delta` is not the only instrument that goes blind at the package
> boundary, and this decision named only that one.** Three do, and they fail
> differently:
>
> - **`check_baseline.py --delta`** — prints only `SYSTEMS`. Named above; fixed
>   by the reading this decision builds.
> - **`closure.py` / `residue.py`** — `closure.SUBJECT` *is*
>   `classify_blueprint.WALK_ROOTS`, so the unreached set can only ever contain
>   files under the walk. `docs/RESIDUE.tsv` has **35 rows and not one names the
>   canonical package**, and it structurally never will. So goal #3 (*no dead
>   code ships*) scored **met** for `Audio` on a register that had never looked.
> - **`score_goals.py`** — keyed on `_walk_roots.addon_roots()`, so a package
>   outside the walk scores nothing at all.
>
> The second is the one that matters, and it is **ADR-0148 one level up**: a
> guard going green because it no longer looks, found *inside* the instrument
> written to catch guards going green because they no longer look. ADR-0149's
> scorer now has a fourth state, **`unscorable`**, which is a finding and never a
> pass — and `Audio` reads `#3 unscorable`, `#4 open` (nothing watches the
> package), `#5 met` (the addon's cross-system reach is 0 today and must *stay*
> 0), `#7 open` (see dec. 10).
>
> **This does not reverse dec. 1** — every alternative it rejected is still
> rejected, and for the same reasons. It corrects dec. 1's accounting of what the
> decision costs: not one instrument, three, and the residue register is the
> expensive one because pass 8 is the only real safety net and it cannot see the
> destination. **Pass 8 must state that limit explicitly rather than report a
> clean register.**

> **Amended 2026-08-22 at loop pass 6: the second list was built TWICE, in the
> same module, within the hour — and the duplication was silent.** This branch
> landed `_walk_roots.EXTRACTED_ROOTS` at #405; the concurrent branch landed
> `_walk_roots.EXTRACTED` at PR #411 / ADR-0155. Same accessor name
> (`extracted_roots()`), both returning a 3-tuple, `(name, path, present: bool)`
> against `(system, path, why: str)`. Git conflicts on `_walk_roots.py` and on
> **nothing else**: the three call sites are in other files and unpack
> positionally, so `present` would have bound to an always-truthy `why` string
> and the *"package is absent from this checkout"* branch would have died without
> a word. **Neither of us would have caught it in review.**
>
> **Resolved by deleting this branch's copy and taking #411's verbatim**, on two
> counts:
>
> - **The `system` field removes a guess.** dec. 9's per-system conservation form
>   has to pair a system's Δ with the package's Δ. A package-keyed list cannot
>   know which system left, so `--delta` defaulted to `systems TOTAL Δ` and
>   needed `--conserve Audio`. A row that names the system is paired by the
>   instrument. `--conserve` survives as an override; #410 runs a bare `--delta`.
> - **Raise-on-missing, which OVERRIDES [#402](https://github.com/timbermania/fft-monorepo/issues/402)'s
>   written acceptance criterion** (*"says something useful rather than
>   crashing"*). The two only conflict if a raise is not useful. Every consumer
>   reads a short list as *"nothing more to check"*, so a row that quietly
>   disappears is a silent under-report — **the crash, arriving later and in
>   someone else's head.** The override is recorded here rather than resolved
>   quietly.
>
> **The durable finding is neither of those.** It is that the record must not be
> **unpackable**: #411's `Extracted` is a `__slots__` object with no `__iter__`,
> so the positional unpack that would have failed silently raises `TypeError` on
> the first line that tries. That property is worth more than which branch owned
> the file, and it generalises — *a shared record whose fields two authors might
> order differently should refuse to be read positionally.*
>
> **One fact from the deleted copy survives, because it is about the tree rather
> than about the list.** The list must be **declared and not scanned**: `*/addons/*`
> across this monorepo also finds `smd-player/addons/exmateria_sound` (the
> pre-ADR-0136 dec. 4 package name) and `research/addons/gdgifexporter` (a
> third-party tool), neither of which is an extraction destination. #411 reaches
> the same conclusion from the other side — the host's `addons/exmateria_sound`
> is a **per-worktree** artifact, a real rsync'd directory in the canonical
> worktree and a symlink in a secondary one, so a derivation *works where its
> author tests it and fails elsewhere.* **A worktree-dependent defect is strictly
> worse than a uniformly broken one, because the uniformly broken one is found
> immediately.**

> **How far the duplicate-list defect actually reached: 2 of the 5 blind
> instruments, not 5.** The concurrent branch reproduced the two-systems-one-
> package case against `score_goals.py` and found the same shape biting harder —
> `EXTRACTED` is a list of SYSTEMS while the addon is the unit that gets walked,
> so the package scored twice while a path-keyed `out_of_walk[path] = system`
> let the second row's name overwrite the first: two identical scorecard blocks
> **both labelled `Effects`**, with `Audio` absent from the run entirely. Fixed
> there the same way (grouped by package, refuse by name where it is undefined).
>
> The other three — `check_addon_portability.py:42/57` and
> `check_debug_panel_tunables.py:43` and residue's walk half — key on
> `walk_roots()`/`addon_roots()` and **never touch `extracted_roots()`**. That is
> structural immunity rather than luck: the defect requires *a system-keyed list
> walked per row against a path-keyed accumulator*, and `WALK_ROOTS` carries no
> system names for a second key to disagree with. Measured: 4 roots, **no
> duplicates and no nested pairs**, so even the degenerate double-walk cannot
> arise.
>
> **And the two failures are not equally dangerous.** `--delta` produced two
> numbers that disagreed; the scorer produced one number attached to the **wrong
> name**. A wrong number invites arithmetic; a wrong name invites belief. An arm
> for this class should assert on the label before the value.


**2. The driver splits four ways, and only one of the four files splits inside
itself.** Of the eight live files:

| file | lines | goes | why |
|---|---:|---|---|
| `EffectSfxEngine.gd` | 1,267 | **addon** | the driver. Models the PSX SPU, preloads six addon files, owns the pool / producer thread / voice budget / reverb. ADR-0136 dec. 5. |
| `BusLimiter.gd` | 115 | **addon** | pure int32→float DSP with a per-sample smoothed gain. Zero host reaches of any kind — the only file here that is already portable. |
| `SpuAudioDebugPanel.gd` | 146 | **splits** | the click de-click section, its preset row and its live readout are the driver's (≈113); the whole-game **volume slider** is the Master bus's and stays host (≈33). See dec. 4. |
| `AudioEngine.gd` | 131 | **splits** | the waveset + two `Spu`s are the addon's (≈35 lines); the Godot **Master-bus rack** — `AudioEffectAmplify` before `AudioEffectHardLimiter`, `UserSettings` persistence, the +9 dB boost curve — is the host's (≈96). |
| `SfxRouter.gd` | 259 | **host** | game-event cue vocabulary (`combat.unit_died`), `EventBus`, `UnitProgression`. Confirms #377's decision 3. |
| `SfxCatalog.gd` | 74 | **host** | wiki-derived slot labels over a host JSON. Not ISO-derived; names the game's cues. |
| `AttackSfxResolver.gd` | 78 | **host** | weapon-graphic → sound-class, off the game's own item data. Game glue. |
| `MusicPlayer.gd` | 127 | **host** | a facade over the addon's `SMDPlayer` plus `res://assets/music` paths and a scene-local kill switch. Scene policy is the host's. |

**≈1,530 lines move; ≈667 stay, plus the adapter.** The 637 declined-scene lines
are untouched here and leave at the deletion pass, not this one.

**Two files split, and both split on the same line.** The split is not arbitrary:
**the addon owns the SPUs, the host owns the bus** — and because
`SpuAudioDebugPanel` is a view over both, *the panel splits exactly where its
subject splits*. Its volume slider drives `ExMateriaAudioEngine.get/set_master_volume`,
which is host; its live readout reaches
`ExMateriaEffectSfx._click_units[0]["mixer"].get_click_retrigger_fade_ms()`, which is
addon-private knowledge a host panel has no business holding. Keeping them
together would put one half in the wrong package whichever way it went. `AudioStream` + buses is
explicitly map #373's tier in #392's table, so the Master rack staying host is
the division of labour working rather than a compromise. It also keeps
`UserSettings` where ADR-0139 dec. 13 measured it belongs — the eleven systems
reach `infrastructure` three times in 141,837 lines and the three files stay in
the host.

> **BUILT 2026-08-22 (#409, `7f125d00e`) — the split OVERSHOOTS on both halves, and
> the overshoot is a fixed cost PER FILE.** This decision called ≈35/≈96 and ≈113/≈33
> "the softest numbers in the whole plan" and asked for the real ones.
>
> | file | predicted | measured |
> |---|---|---|
> | `AudioEngine.gd` addon half | ≈35 | **43** |
> | `AudioEngine.gd` host half (`MasterBus.gd`) | ≈96 | **107** |
> | *sum* | *131* | **150** |
> | panel addon half (`SpuAudioDebugPanel.gd`) | ≈113 | **180** |
> | panel host half (`AudioMasterVolumeDebugPanel.gd`) | ≈33 | **83** |
>
> The engine's +19 is entirely the second file's **header**: by CODE lines it is
> 17 / 47 = 64 against 62, so the cleave itself is nearly free and the overshoot is
> documentation. *A split of N lines does not produce two files summing to N.*
>
> The panel's numbers are not comparable head-on and saying so is the honest report:
> **#408 grew that file from 146 to 219 before #409 cleaved it.** Measured against the
> pre-#408 file, the volume section occupied **41 lines against a predicted ≈33**, and
> it lands at 83 as its own panel for the engine's reason — a header, a `_make_label`
> both halves need, and a `_on_print_values` a shared panel got for free.
>
> **Which half keeps the name was decided by re-derivation, not by taste.** 24 files
> name `ExMateriaAudioEngine`; every one outside the file itself reaches `ready_ok` / `waveset` /
> `sfx_spu` / `music_spu` — the **addon** half. Only three touch the bus half. So the
> SPUs keep `ExMateriaAudioEngine` and the rack becomes `MasterBus`: two files edited, 22 left
> alone. The opposite choice inverts that ratio.
>
> **And the host panel's name is load-bearing in a way nothing predicted.**
> `MasterVolumeDebugPanel` landed straight in `classify_blueprint.py`'s UNCLASSIFIED —
> no `DEBUG_OWNER` fragment reaches "Master", which is the no-catch-all property working.
> A `DEBUG_EXACT` row would have closed it. Naming it `AudioMasterVolumeDebugPanel`
> closes more: **`("Audio", "Audio")` currently matches exactly ONE file**,
> `SpuAudioDebugPanel.gd`, which dec. 1 lifts out of the walk at #410 — so that fragment
> was one ticket away from going dead and turning `check_blueprint_walk.py` red on
> ADR-0144 dec. 3's own dead-entry arm. One name choice removes a classifier edit now
> and a guard breakage at the lift. **#410 should expect more of these**: every
> `DEBUG_OWNER` fragment and `RULES` path whose only matching file leaves the walk goes
> dead at the same moment.

**3. The config seam is ONE host adapter, the addon declares, and four autoloads
become zero.** ADR-0113's inversion, applied per autoload:

| autoload | lines | becomes |
|---|---:|---|
| `Tune` | 4 | the addon publishes `tunables() -> Array[Dictionary]` (slug, default, hint, setter). The **host adapter** walks it and calls `Tune.bind` + `Tune.on_update`. The addon never names `Tune`. |
| `DebugConfig` | 1 | `audio_monitor_enabled` becomes a `static var` on the driver, read by the driver's own panel as a view. ADR-0140 dec. 5 — *a system logs itself* — and it is a one-line change because `Audio` has exactly one gate. |
| `TuneField` / `BaseDebugPanel` | 4 | retired. The panel becomes a plain `Control` satisfying `DebugOverlay.register_panel(panel, category)`. ADR-0140 dec. 8. |
| `UserSettings` | 3 | **stays**, on the host side of `ExMateriaAudioEngine`'s split. Not the addon's problem. |

That is **one adapter doing two walks** — declared tunables → `Tune`, declared
panels → `DebugOverlay` — and on today's surface it is *one* tunable
(`audio.click_retrigger_fade_ms`) and *one* panel. **ADR-0118 dec. 6 predicted a
twenty-line host adapter for exactly this, and this pass predicts it will land
between 18 and 25 lines.** Pass 9 measures it. A prediction that can be wrong is
the point.

The category is the residue and it is named, not hidden: `Category.AUDIO` is a
**closed enum of 22** in the host (`DebugOverlay`), so the addon must declare its
category as a **string** the adapter maps. ADR-0140's consequences already record
that closed enum as unfixed, and this pass does not fix it — it routes around it
for one panel and leaves the enum where it found it.

> **BUILT 2026-08-22 (#408, `53f318340`) — the adapter is 16 code lines, and the
> prediction MISSES LOW.** ADR-0118 dec. 6 said "about twenty" and this decision
> said 18–25. Measured: **16 code lines** (51 with the docstrings that say why each
> line exists). Not padded to reach the band — a prediction that can be wrong is
> the point, and this one was wrong in the cheap direction.
>
> **What the declaration actually carries is five fields, not four.** `tunables()`
> publishes `slug` / `label` / `default` / `hint` / `setter`; `label` is the addition,
> and it exists because the row itself is a `TuneField` and `TuneField` is the host's.
> So the panel declares an empty `tunable_rows` slot and the **host builds the rows
> into it** — the addon declares, the host renders, which is ADR-0113's inversion
> reaching one step further than this decision's table anticipated.
>
> **And a declaration alone cannot WRITE.** The panel's four preset buttons scrubbed
> the slug through `Tune.set_value`; with `Tune` gone they had nothing to call. The
> fix is a **host-filled write port** — `static var tunable_writer: Callable`, filled
> by the adapter with `Tune.set_value`, and a no-op when unfilled, which is the correct
> standalone behaviour. Two lines on the driver. *An inverted dependency needs an
> outbound port as well as an inbound declaration; only the inbound half is obvious.*
>
> **The `DebugConfig` row is right about the static var and wrong about "one line".**
> The gate moved to `ExMateriaEffectSfx.audio_monitor_enabled` on a NEW slug,
> `audio.monitor_enabled` — `debug.audio_monitor_enabled` was `Debug`'s namespace, and
> ADR-0140 dec. 5 wants the slug in the system that prints through it. That is one line
> in the driver and **four more in the host**: the property leaves `DebugConfig`, the
> row leaves `LoggingDebugPanel`, the flag leaves `DebugLoggingFlagsTunableTest`, and
> `--audio-monitor` writes the declared slug instead of a host property. Direction-tested
> end to end at 300 frames: **18 `[audiomon]` prints with the flag, 0 without.**
>
> **`JsonAsset` and `EventBus` needed no decision.** #408 asked for them to be
> "accounted for explicitly — kept host-side or given a port". All three reaches are in
> `AttackSfxResolver`, `SfxCatalog` and `SfxRouter`, which dec. 2 already keeps host,
> and the classifier books both symbols `infrastructure` — not a system, so goal #5's
> own instrument would not flag them even if they moved. Nothing to port.

**4. #393's three candidates are not three, and the question it asks is already
answered.** Read against ADR-0140 at HEAD:

- **Candidate 1 — `Debug` extracts like any other system.** This is ADR-0140
  dec. 2, decided. `Debug` is 15 files / 2,884 lines with **zero outbound edges**,
  passing ADR-0139 dec. 4(a)'s sink veto outright.
- **Candidate 2 — `Debug` is host machinery that never extracts.** Not open.
  ADR-0140's *Considered alternatives* rejects it verbatim, under that heading,
  on dec. 2's evidence.
- **Candidate 3 — promote the panel base to the kernel.** Correctly dead on
  ADR-0146 dec. 3's admission test, as #393 itself says.

**So `Debug` extracting is not what blocks goal #5.** What blocks it is a
different thing, and ADR-0140 dec. 8 predicted it in writing: *"nothing in this
ADR stops the 40th panel from extending the base class again. A guard would, and
this ADR does not write one."* Extraction #1 shipped exactly that — two panels
into a portable addon, still `extends BaseDebugPanel`, still naming `TuneField`.
The soft spot came true within one extraction.

**The rule that follows** — *a system's debug panel ships with the system, as a
plain `Control` satisfying the host's registration signature; no file under an
addon root may `extends BaseDebugPanel` or name `TuneField`* — **is ADR-0151's,
not this pass's.** It is stated here only as the premise dec. 2 rests on. The
concurrent session holds the live violation and the goal-scorecard instrument
that scores it, so the rule, its guard, `exmateria_render`'s un-inheritance and
the guard repair in dec. 5 land together in one commit on that branch. **This
pass consumes ADR-0151 and cites it; it does not restate the rule.**

What it does settle for `Audio` is the one question ADR-0151 hands back per
system: **is this panel bespoke UI, or is it only `TuneField` rows?** ADR-0068
dec. 9 says the registry generates the declarative kind, so a purely declarative
panel is **deleted, not un-inherited** — which is what `Render`'s two turned out
to be.

`SpuAudioDebugPanel` is the other case, and the count is not close. **Exactly one
of its 146 lines is a `TuneField` row** (`:44`). The rest is bespoke: a
hand-built master-volume `HSlider` with live-apply-on-drag / persist-on-drag-ended
semantics no registry generates (`:67–99`), four A/B preset buttons that write the
slug (`:47–56`), an `on_shown` resync, and a live readout that reaches
`ExMateriaEffectSfx._click_units[0]["mixer"].get_click_retrigger_fade_ms()` to
confirm the value actually reached the native core (`:112–131`). **So it
un-inherits rather than being deleted** — and then it splits, per dec. 2, because
its two sections have two different owners.

The mechanics were checked rather than assumed. `DebugOverlay.register_panel` is
duck-typed on an **untyped** `panel` parameter and touches exactly
`set("panel_category")` and `get("panel_title")`; `DebugDashboard` guards every
lifecycle call with `has_method` (`:348–351`). A plain `PanelContainer` satisfies
all of it. What un-inheriting **does** cost is four trivial widget helpers the
panel calls off the base class — `add_separator`, `add_section_title`,
`add_label`, `add_print_values_button`, **24 lines between them** — which the
addon re-provides. That is the honest price of the rule on this system, and it is
authored lines rather than moved ones, so dec. 9 counts it separately.

That also disposes of #393's stated cost. Candidate 2 would have made extraction
#1's membership retroactively wrong; the answer that actually holds makes
extraction #1's membership **right** and its *coupling* wrong — a two-line-per-
panel fix, not a boundary reversal.

**5. Un-inheriting a panel silently deletes it from a *guard*, and that is why
the guard cannot land alone.** `tools/check_debug_panel_tunables.py` runs with
`ENFORCE = True` and keys its entire contract on
`PANEL_MARKER = ^extends BaseDebugPanel`. A panel that stops extending the base
class stops being scanned — it does not fail, it **disappears**. That is
ADR-0148's stale-scan-root failure wearing a **marker** instead of a root, and it
is the second instance of that class in two extractions.

Found by this pass's audit and **discharged by ADR-0151**, which widens the
marker so that a panel is `^extends BaseDebugPanel` **or** a class some walked
file mounts through `DebugOverlay.register_panel` — paraphrased, not quoted — in
the same commit that bans the inheritance. Recorded here because the finding is
this pass's and because the pairing is the load-bearing part: the new guard alone
buys four edges and pays a whole guard's coverage for them.

Direction-test both arms, per extraction #1's lesson: a new violation must fail,
and removing a real entry must fail. A guard that only proves the first arm is
what let fourteen stale roots stay green.

> **Discharged 2026-08-22 — ADR-0151 landed with both halves in one commit
> (`refactor/extraction-1-render-goals`, PR #399).** The guard is
> `tools/check_addon_portability.py`, and the rule generalises past debug
> panels: *no file under an addon root may name a symbol the classifier books to
> a **system**; a `platform` port and the `schema` kernel are fine, which is what
> a port is for.* `check_debug_panel_tunables.py`'s marker is widened in the same
> commit — a panel is now `^extends BaseDebugPanel` **or** a class some walked
> file mounts through `DebugOverlay.register_panel` — which finds 31 classes and
> was direction-tested with a registered `PanelContainer` holding a raw
> `SpinBox`, a case the old marker misses. **So un-inheriting
> `SpuAudioDebugPanel` costs no coverage**, and the contingency in this
> decision's consequences is spent.

> **AMENDED 2026-08-22 (#408, `53f318340`) — the widened marker has a SECOND blind
> spot, and #408's first draft walked straight into it.** ADR-0151 dec. 6 widened panel
> identity so that a panel is either a file extending the base class or a class some
> walked file mounts through `DebugOverlay.register_panel` — *"the registration is the
> identity"*. The second half is read mechanically as `var X = ClassName.new(` paired
> with `register_panel(X` — so it sees a mount that **names the class** and is blind to
> a mount that computes it.
>
> #408's first adapter did exactly the tidy thing: `const PANELS := [preload(...)]` and
> `for script in PANELS: var panel = script.new()`. A loop variable satisfies neither
> half of the pair, so `is_debug_panel(SpuAudioDebugPanel.gd)` went **False** and
> `check_debug_panel_tunables.py` went GREEN BECAUSE IT HAD STOPPED LOOKING —
> ADR-0148's defect for the **third** time, inside the very commit that retires the
> inheritance the widening was built to replace. *A marker that reads a naming
> convention is a scan root wearing a syntax.*
>
> **Fixed in the adapter, not in the guard.** The mount names its class; the "walk" it
> replaced was abstracting over a list of one and buying only invisibility. Widening the
> marker a second time, in the commit that broke it, is chasing the marker rather than
> making the code legible — and the generic-mount hole is real but belongs to the first
> extraction that actually needs a generic mount. **Both arms re-tested:** the panel is
> SEEN (via registration, not inheritance, `PANEL_MARKER` False / `PANEL_CLASSES` True),
> and a raw `SpinBox` planted in it is CAUGHT at the right line.
>
> **The question ADR-0155 dec. 5 handed here is answered: `check_debug_panel_tunables.py`
> does NOT follow the package out.** Its subject is a *host* contract — every value
> control routed through `TuneField`, the host's factory — and an extracted package has
> no `TuneField` to route through, by this pass's own rule. What follows the package out
> is `check_addon_portability.py`, which forbids naming `TuneField` at all; the two
> guards are the same rule read from opposite sides, and running the panel guard over a
> package that may not use `TuneField` would assert a contract the package is forbidden
> to satisfy. The coverage that ends at the lift is therefore **the raw-widget net**, not
> the routing rule, and #405's pass-8 output is where that limit is stated.
>
> **`check_addon_portability.py` cannot testify about #408 at all, and the ticket's own
> comment is wrong on that half.** It says *"while this ticket's work sits under `src/`
> both guards see it"*. Its subject is `_walk_roots.addon_roots()` —
> `addons/exmateria_render` on this branch — so it never looks at `src/`, before or after
> the lift. What CAN testify is its own reach scan, `score_goals.outbound_reaches`, one
> implementation and not two, run over the moving set: **5 reach lines to `Debug` before
> #408, 0 after.**
>
> | before | |
> |---|---|
> | `EffectSfxEngine.gd:1150` | autoload → `Debug.DebugConfig` |
> | `SpuAudioDebugPanel.gd:2` | class_name → `Debug.BaseDebugPanel` |
> | `SpuAudioDebugPanel.gd:13,44` | class_name → `Debug.TuneField` |
> | `SpuAudioDebugPanel.gd:13` | preload → `Debug.src/debug/TuneField.gd` |
>
> `Tune`, `UserSettings`, `JsonAsset` and `EventBus` never appear in that scan: the
> classifier books them `platform` / `infrastructure`, which are not systems. **#408's
> stated seam of 17 lines across six symbols and goal #5's guard disagree by design** —
> the seam is what ADR-0113's inversion removes, the guard is what goal #5 forbids, and
> the inversion is the stricter of the two.

**6. `shared/` — the name is right and the MEMBERSHIP is wrong.** ADR-0136 dec. 7
deferred this rename here, calling `shared/` *"the one name inside the addon that
is wrong… it is the effect-sound dispatcher's tree."* Measured at `78ab1fcd6`,
by **files** (dec. 7's own figures are by opcode byte, and the two units disagree):

| `shared/` membership | files |
|---|---:|
| bound by **both** dispatch tables | **32** |
| bound by the **effect-sound** table only | 31 |
| bound by the **music** table only | 2 — `tempo.gd`, `time_signature.gd` |
| bound by neither — walker, dispatcher, channel/slot state, note handler, LFO helpers, per-tick | **19** |
| **total** | **84** |

**Dec. 7's premise does not survive its own measurement.** 32 of the 65
table-bound files are genuinely shared, and all 19 unbound support files are used
by both paths, so **51 of 84 (61%) belong under a name that means "shared"** and
only 31 (37%) are effect-sound-only. The tree is not the effect-sound
dispatcher's; it is the common tree with an effect-sound tree accidentally
inlined into it.

So the corrected decision is **a three-way move, not a rename**: 31 effect-sound-
only handlers go to `runtime/effect_sound/opcodes/` (a sibling directory that
already exists), the 2 music-only handlers go to `runtime/sequencer/opcodes/`
where their bindings already live, and `shared/` keeps its 51 and its name.
Thirty-three files move; zero are renamed; the ADR-0136 dec. 1 figures it rests
on (32 delegating entries, 30 doubled bytes, 5 music-only opcodes) are
independently reproduced by this count and stand.

> **Amended 2026-08-22 at loop pass 5, on two premises that do not survive an
> `ls`.** The **32 / 31 / 2 split itself reproduces exactly** and is not in
> question — re-derived here from `preload(` lines in `shared/opcodes/_table.gd`
> (63 binds) against `sequencer/opcodes/_table.gd` (34 binds): 32 both, 31
> effect-sound-only, and the 2 music-only are `tempo.gd` and `time_signature.gd`
> by name. Zero of the 31 are preloaded from the music side. What is wrong is the
> two clauses either side of it:
>
> - **`runtime/effect_sound/opcodes/` does NOT already exist.** The parenthetical
>   *"a sibling directory that already exists"* is true of
>   `runtime/sequencer/opcodes/`, which takes 2 of the 33 files, and false of the
>   destination that takes the other 31. Pass 6 creates it.
> - **"Zero are renamed" is false under the tree's own convention.** Every file
>   in an opcode tree declares `class_name <Tree>Op<Name>` and it is held
>   strictly — 36 `SequencerOp*` beside ~60 `SharedOp*`, with `SharedOpFermata`
>   and `SequencerOpFermata` coexisting as separate implementations. So the move
>   implies **33 `class_name` renames**: 31 `SharedOp*` → `EffectSoundOp*`
>   (matching `EffectSoundPool` / `EffectSoundResolver` in the destination tree),
>   and `SharedOpTempo` / `SharedOpTimeSignature` → `SequencerOpTempo` /
>   `SequencerOpTimeSignature`, neither of which collides today. Leaving 33
>   symbols named `Shared*` outside `shared/` would reproduce at the symbol level
>   exactly the defect dec. 10 renames `SMDOpcodes` for, in the same commit.
>
> Dispatch binds by **preload path**, not by `class_name`, so the renames are not
> what makes the move work — they are what keeps the tree readable after it. Both
> are one ticket.
>
> **A third correction was drafted and withdrawn, recorded because the method is
> the lesson.** A first pass found 13 of the 31 "effect-sound-only" files
> apparently reached from the music side, which would have made the destination
> directory's name a lie. It was an artifact: `sequencer/opcodes/*.gd` handlers
> *cite* their `shared/opcodes/` counterpart in a docstring (*"Mirrors
> shared/opcodes/adsr_attack.gd"*) and a path-shaped grep cannot tell a comment
> from a binding. Restricted to `preload(` lines the number is **zero**. The
> mirror of the citation failure this ADR chain keeps finding: there, a citation
> recorded WHERE and not WHAT; here, a mention was read as a reach.

> **Amended 2026-08-22 at loop pass 6, on building it (#406): the split held to
> the file, and the 2-file half turned out to be a REVERSAL that neither this
> decision nor #400 knew it was proposing.**
>
> Re-derived at build time as the ticket required, and the numbers reproduce
> without adjustment: 63 shared-table binds into `shared/opcodes/`, 34
> sequencer-table binds into it, intersection 32 — so **31 effect-sound-only, 2
> music-only**, and the 66th file is `_table.gd` itself, bound by neither.
> `shared/` goes **84 → 51** `.gd`, which is this decision's "51 files stay"
> arriving from the other direction. **Zero code anywhere binds any of the 33 by
> `class_name`** — the only `Shared*` symbol echoes outside a declaration were two
> docstrings — which confirms the amendment above: the renames are readability,
> not wiring.
>
> - **`tempo.gd` and `time_signature.gd` were moved INTO `shared/opcodes/` on
>   purpose, by `b80e3c0cb` (music-parity pass 7.D.h), whose stated reason was
>   that they *"should live in `shared/opcodes/` for Pass 9's unified table"*.**
>   #406 moves them back. Neither this ADR nor #400 cites that plan, so the
>   reversal was not weighed — it was invisible.
> - **The same plan's end state contradicts this whole decision, not just the
>   pair.** `MUSIC_FFT_PARITY_REFACTOR_PLAN.md` → *"Pass 9 — Final cleanup"*
>   targets *"delete the now-empty `sequencer/` subdir (all bodies moved to
>   `shared/`)"*. That is the opposite direction from dec. 6.
> - **It is an orphaned plan, and the test is inbound citation.** Nothing in the
>   repo cites `MUSIC_FFT_PARITY_REFACTOR_PLAN.md` or
>   `MUSIC_FFT_PARITY_REMAINING_WORK.md` — 0 references. Its sibling
>   `MUSIC_OPEN_BUGS_DEEP_REFACTOR_PLAN.md` is cited from **live runtime code in
>   6 places**, so "docs are never cited in this repo" is not the explanation.
>   Its Pass 7 — the prerequisite for Pass 9's own premise — is self-described as
>   ~5 unstarted working days, and `sequencer/opcodes/` still holds 36 files, so
>   the "now-empty" state it cleans up was never reached.
>
> **So dec. 6 stands, and the revert is the point rather than an embarrassment.**
> Membership is decided by the binding form at the time you ask; if the tables
> ever unify, the same `preload(`-derived rule re-derives the answer and may move
> these two a third time. What made `shared/` wrong was **placing files for an
> anticipated consumer instead of an actual binding** — and the pair is a worked
> example of that failure, sitting inside the tree the decision was written to
> fix. Dec. 6's thesis arriving from behind it.
>
> **The last correction is about instruments, and it is #415.** This ticket's
> acceptance criterion names the parity suite, and the parity suite's Gate A
> cannot answer: it dies on `Parse Error: Identifier "SPUMixer" not declared`.
> `19d8ad873` (2026-05-28) renamed `SPUMixer` → `Spu` and its own message scoped
> itself *"Pure token rename across 11 addon files"* — `exmateria-sound/workspace/`
> was not among them, and **7 workspace files still name the dead class**, killing
> Gate A and 5 harness renderers for ~12 weeks. It is pre-existing, verified at
> HEAD, and untouched by #406, whose binding instrument is #401's frozen
> `TEST-BASELINE-E2.tsv` instead. ADR-0148's shape once more: a rename that named
> its own blast radius, and was wrong about it.

**7. #326 is closed, and it was a stale deployment rather than a defect.** The
host's copy differed from canonical across 6 files / 72 lines and was **strictly
behind** — the `smd-player` → `exmateria-sound` rename from ADR-0136 dec. 4 plus
three real features: `play_sound.single_track`, `pair_triggered`'s fourth
`from_phase` argument, and `SMDOpcodes.param_count_of()` with the `offset`/`size`
patch anchors. `src/effects/studio/FedsOpcodeCatalog.gd` calls `param_count_of`
on three lines, which is the parse error that took the Effect Studio down.

`bash tools/sync_exmateria_sound.sh` fixes it — the trees are now byte-identical
and `godot --path . --quit-after 120 res://assets/scenes/EffectViewer.tscn`
produces **zero script or parse errors**. The host was never wrong: it was
written against the canonical package and the deployment had not been re-run.
`EffectInstance._on_sound_pair_triggered` already declares `from_phase: String =
""`, so it was compatible with both copies and the arity change was invisible.

**This is dec. 1's evidence, not a coincidence.** A "drift" that is a pure
fast-forward from a source of truth is what a *deployment target* looks like, and
it is why the canonical package is the address and the host copy is an artifact.

**8. The vault anchors follow the code into the package.** Pass 2 anchored the 9
notes whose `R:` lines cite a host `Audio` file and left the finding that **41
cite `addons/exmateria_sound/`** — a 4:1 footprint in a tree the walk does not
enter. Those anchors are written into the canonical package at pass 6, and
`check_vault_anchors.py` gains it as a **second scan root for rule enforcement
only** — its two rules are about the marker's form and resolution, it does not
feed the baseline, and it is not `WALK_ROOTS`. Verified safe: the canonical
package contains **no `Vault:` string today**, so the guard cannot go red on
adoption it has not been given. Coverage stays reported, never asserted.

> **Amended 2026-08-22 at loop pass 5: the 41 is arithmetically right and is the
> wrong number to plan against — the scope is 48 notes over 67 files.** Measured
> on `main`'s `vault/`: **48** notes carry an `R:` citation into
> `addons/exmateria_sound/`, and **41 = 48 − 7**, the 7 being notes pass 2
> already anchored on the host side. That subtraction is what makes 41 wrong as a
> work list: 6 of those 7 are anchored in `SfxRouter.gd`, `SfxCatalog.gd` or
> `AttackSfxResolver.gd`, **which dec. 2 keeps in the host**, so their addon-side
> edge is unanchored and stays unanchored. An anchor in a host file does not
> anchor the addon file the same note also cites.
>
> The work is fully mechanical and was verified end to end: the 48 notes name
> **67 distinct `.gd` paths** under the addon, and **all 67 resolve in the
> canonical package today, 67 hit / 0 miss**. Only the *prefix* is dead — 339 of
> the 340 citation instances read `smd-player/addons/exmateria_sound/`, the
> pre-ADR-0136-dec.-4 package name, which is 70 of the vault's 81 dead paths in
> one place. So no crosswalk is needed; strip the prefix and the path lands.
>
> **Separately, the anchor rule's stated premise is a phantom, and the conclusion
> survives on a better reason.** ADR-0154 dec. 1 found *"analog, authored fresh"*
> asserted in four places all citing ADR-0112, which contains no such words —
> re-verified here by whitespace-collapsed match. **A fifth site is
> `godot-learning/tools/check_vault_anchors.py`'s own docstring**, unfixed on
> both branches and not in ADR-0154's table; it is the *instrument* this decision
> modifies, so it is repaired in the same ticket. The rule with a source is
> **ADR-0110 dec. 1** — *"Systems are lifted out of the host into addons"* — and
> for `Audio` that changes the shape of the work in the cheap direction:
>
> - **The moving files' anchors travel for free**, because dec. 2's move is a
>   lift. It is a *verification*, not authoring — and it is **5 anchors in 1
>   file**, not the 12 a handoff into this pass stated. All 12 `Audio` anchors sit
>   in 5 files, of which only `EffectSfxEngine.gd` (5 anchors) moves;
>   `BusLimiter.gd`, `AudioEngine.gd` and `SpuAudioDebugPanel.gd` carry **zero**
>   anchors between them.
> - **The 48 notes are genuine fresh authoring**, into addon code that predates
>   the refactor and was never anchored. What licenses that is ADR-0111 dec. 7's
>   own argument — a `res://` path citation rots and a comment does not — which
>   the 339 dead-prefix citations above demonstrate rather than assert.

> **BUILT 2026-08-22 at #404, and the amendment above is wrong about the scope in
> a way that matters. It is 39 notes, not 48 — and the two numbers it reconciles
> are measurements of different things.** Re-derived from `main`'s `vault/` at
> build time, which is what acceptance criterion 2 exists to force:
>
> | measurement | notes |
> |---|---:|
> | contain the **token** `exmateria_sound` anywhere | 48 |
> | contain the **substring** `addons/exmateria_sound/` | 41 |
> | cite an addon **`.gd` file** — the anchorable set | **39** |
>
> The 9 notes in 48 and not in 39 all read `R: none — ... not present in ...
> (probed smd-player/addons/exmateria_sound ...)`. They name the package as a
> place they **searched and did not find**; there is no file to anchor, and an
> anchor there would write into the code a claim the note itself denies. The 2
> extra inside 41 are those same nine matching on a bare directory. **Named, because
> criterion 6 asks for the skips listed rather than characterised** — [[Bow Arrow Arc
> System]], [[Effect Frame Pacing]], [[Effect Script Branching]], [[Emitter Anchor
> Modes]], [[Hit Reaction Particle Burst]], [[Projectile Arc System]], [[Spell Charge
> Effect System]], [[Summon Charge Lines System]], [[TRAP Charge Particle System]].
> Every one is an `Effects` note whose `R:` verdict is that the behaviour is absent
> from the reimplementations, so the addon is named as a place searched. So `41 = 48 −
> 7` is a coincidence: the real gaps are `48 − 39 = 9` and `41 − 39 = 2`, and
> neither is the 7 host-side anchors. The amendment reached the right *verdict*
> about 41 (it is the wrong work list) by an argument that does not hold.
>
> **The 67 is exact, and it is the number that mattered** — 67 distinct `.gd`
> paths, 67 anchored, 0 miss. **159 anchors into 67 files**;
> `check_vault_anchors.py` reports **164 in 68 files, naming 39 distinct notes**
> under EXTRACTED, green on both rules, the extra 5 being
> `effect_sfx_engine.gd`'s, which travelled with the lift exactly as predicted.
>
> **"No crosswalk is needed" was true when written and false when built.** Strip
> the prefix and **54 of 67** land. The other **13** are `runtime/shared/opcodes/
> *.gd` and `runtime/smd_opcodes.gd`, which **#406 and #407 moved after this
> derivation** — 33 files out of `shared/opcodes` into `effect_sound/opcodes` and
> `sequencer/opcodes`, plus `smd_opcodes.gd` → `sound_opcodes.gd`. Criterion 2
> named this exact risk (*"the tree moves under #406 and #407 first"*) and it is
> the only reason the 13 were not silently skipped. The prefix claim itself holds:
> every citation that names a FILE carries `smd-player/`.
>
> > **Corrected 2026-08-22 by this ADR's own pass-7 review, and the correction is
> > ADR-0145 dec. 1 happening again.** This paragraph first read *"335 of 335
> > citation instances carry `smd-player/`; there is no live second prefix anywhere
> > in the vault"*. Both halves were wrong, and for the same reason: **a count was
> > published without its subject**, so it could not be reproduced. Three regexes
> > give three totals over the same unchanged vault — `.gd` citations **334**,
> > any-suffix citations **335**, any mention of the string **358**. The ticket's
> > original *"339 of the 340"* was a fourth. None of them is *the* number; the
> > number is meaningless until the subject is stated, which is the whole of
> > ADR-0145 dec. 1 and of `docs/RESIDUE.tsv`'s first line.
> >
> > **And a live second prefix does exist.** `vault/Event Sound OpCodes.md:106`
> > reads `synced into `godot-learning/addons/exmateria_sound/` via
> > tools/sync_exmateria_sound.sh` — the host's DEPLOYMENT COPY (ADR-0131 dec. 8,
> > #326), named as a directory with no file after it. It is not a code citation
> > and #404 rightly did not anchor it, but *"no live second prefix anywhere"* is
> > false, and the derivation missed it because its regex required a filename after
> > the slash. **A negative claim inherits the blind spot of the instrument that
> > failed to find a counterexample** — the same shape as ADR-0148 dec. 1's guard
> > going green because it no longer looks.
>
> **And the crosswalk cannot be built with one wide diff.** `git diff -M90%
> <pre-#406> HEAD` finds **28 of the 34** renames. `pan.gd`, `slur_on.gd`,
> `set_subslot1_active.gd`, `tempo.gd` and two others fall under any single
> threshold because both commits edited them *across* their own move, so the
> end-to-end similarity is lower than either step's. Each commit's own rename
> detection saw all 34; the crosswalk chains per-commit renames. A threshold that
> looks safe drops 4 of the 13 files this ticket exists to reach.
>
> **One `R: none` line is still a real edge, so the filter was not applied.**
> [[PCSX-Redux Capture Rig]]'s verdict is `R: none` for capture-file semantics,
> but its parenthetical names `runtime/shared/flush_tick.gd::_commit_kon` as the
> Godot-side counterpart — a genuine citation of live code. It is anchored.
> Checked rather than assumed: no cited path is negative-only, so filtering on
> `R: none` would have cost that one edge and saved nothing.

**9. The predicted metric, before building.** ADR-0126 and the loop require it,
and extraction #1's lesson is applied: **this table is re-derived from the prose
above, not written alongside it.** Three of ADR-0147 dec. 9's four misses were
the table disagreeing with its own paragraph.

| reading | at `78ab1fcd6` | predicted after extraction #2 |
|---|---:|---:|
| `Audio` files / lines (instrument, incl. declined scenes) | 13 / 2,834 | **11 / ≈1,326** |
| `Audio` live files / lines (design figure) | 8 / 2,197 | 6 / ≈689 |
| `Audio` → systems (lines) | 8 | **4** |
| `Audio` → `Debug` (lines) | 5 | **1** |
| systems → `Audio` (lines) | 46 | **22** |
| **addon-side** reaches into a host symbol | 8 | **0** |
| `Debug` inbound (lines) | 528 | 524 |
| `exmateria_sound` extracted (files / lines) | 152 / 15,961 | ≈156 / ≈17,515 |
| systems TOTAL lines | 158,615 | **≈157,107** |
| cross-system total (lines) | 1,132 | **1,104** |
| UNCOUNTED reaching `addons/exmateria_sound/` | 22 (Effects 14, Audio 8) | **≈38 (Effects ≈38, Audio 0)** |

**Rows 5 and 10 are the ones that matter and they must be read together.** The
cross-system total falls 28, and **only 4 of the 28 are a retired dependency.**
The other 24 are the 22 `ExMateriaEffectSfx` lines and the 2 `ExMateriaAudioEngine` lines,
whose *target* leaves the walk: `touch_matrix.record()` resolves the destination
through `sysof`, and a path outside `WALK_ROOTS` returns `None`, so the edge is
not recorded. `Effects` will still call the driver on exactly as many lines the
day after as the day before. That fall is bookkeeping, and the UNCOUNTED register
is where it goes — which is what ADR-0148 dec. 1 built that register for, one
extraction before it was needed.

`Audio`'s own 8 uncounted reaches go to **zero**, and *those* are real: they
become intra-package references.

**The earned fall is four lines, and `Audio → Debug` does NOT reach zero.** An
earlier draft of this table predicted 0 and it was wrong for a reason worth
keeping: dec. 2 splits the panel, and the host half — the whole-game volume
slider — is a **host** panel, so it keeps `extends BaseDebugPanel` legitimately.
ADR-0151's rule binds files under an *addon* root; a host panel inheriting a host
base class is the published interface working as intended. So the retired lines
are `DebugConfig` 1 and the addon half's `BaseDebugPanel` 1 + `TuneField` 2, and
one `BaseDebugPanel` line survives on purpose. **Four lines is what portability
costs to buy on this system**, and buying it is goal #5. A prediction of zero
would have looked better and been false.

Line arithmetic **is** asserted, in two parts that must not be added together:

- **Moved lines are conserved.** `Audio` **−1,530** against `exmateria_sound`
  **+1,530**, every other bucket **+0**, and the two must be *equal*. If
  `--delta` shows `Audio` falling and the extracted row not rising by the same
  number, the move dropped code. That check does not exist today; dec. 1 builds
  it, and it is the reason dec. 1 is a decision rather than a note.
- **Authored lines are named separately** — ≈22 for the host adapter (dec. 3) and
  ≈24 for the four widget helpers the un-inherited panel re-provides (dec. 4).
  They are additions on each side, not a transfer, and folding them into the
  conservation check would hide exactly the discrepancy it exists to catch.

**Predicted to be wrong, named in advance:** the two split ratios are the softest
numbers here — ≈35/≈96 for `AudioEngine.gd` and ≈113/≈33 for
`SpuAudioDebugPanel.gd`. Both are judgements about where a small file cleaves,
made by reading it rather than by cutting it, and together they carry almost all
of the uncertainty in the ≈1,530.

> **Amended 2026-08-22 at loop pass 6: the conservation line's first draft paired
> the extracted Δ with "the largest falling system", and that heuristic is
> withdrawn.** Run at pass 6 it picked **`Render −491`** — extraction #1's
> *within-walk* rebooking, which has nothing to do with this package. It would
> have printed a confident, wrong pairing at every commit except the one its
> author had in mind.
>
> **A heuristic that is right only at the commit you were thinking of is a
> heuristic that lies at every other one**, and it fails in the direction that
> looks like an answer. It is the same shape as the subject/question drift this
> ADR chain keeps finding: the instrument kept computing something after the
> thing it was computing stopped being the thing anyone asked about. What
> replaces it needs no guess — the quantity that left the walk is the systems
> TOTAL Δ, the quantity that arrived is the extracted Δ, and for a pure
> relocation their sum is 0 — and dec. 9's per-system form is now **read** from
> `_walk_roots.EXTRACTED`'s `system` field rather than inferred (see dec. 1 as
> amended).
>
> **And the replacement has a hole of its own, found by the arm that was aimed
> elsewhere.** Two systems declared into ONE package made `--delta` measure that
> package twice — `ext_dl` doubled while the package-keyed TOTAL did not, so the
> two disagreed by exactly the amount nobody reads. Grouped by package now; and
> where a package receives more than one system the per-system pairing is
> **refused by name**, because a package Δ cannot say which system's lines
> arrived. Splitting it on a share would be the withdrawn heuristic wearing a
> different hat.


> **MEASURED 2026-08-22 at the lift (#410, `e9210bafa`).** Every row below is read
> off `check_baseline.py --delta` and `score_goals`'s own reach scan at the move
> commit, not re-derived from prose. Pass 9 scores these; they are recorded here
> because the lift is the last moment the before-figure and the after-figure are
> both in hand.
>
> | reading | at `78ab1fcd6` | predicted | **measured** |
> |---|---:|---:|---:|
> | `Audio` files / lines (instrument) | 13 / 2,834 | 11 / ≈1,326 | **12 / 1,416** |
> | `Audio` live files / lines | 8 / 2,197 | 6 / ≈689 | **7 / 779** |
> | `Audio` → systems (lines) | 8 | 4 | **7** |
> | `Audio` → `Debug` (lines) | 5 | 1 | **4** |
> | systems → `Audio` (lines) | 46 | 22 | **22** ✅ |
> | addon-side reaches into a host symbol | 8 | 0 | **0** ✅ |
> | `Debug` inbound (lines) | 528 | 524 | **522** |
> | `exmateria_sound` extracted (files / lines) | 152 / 15,961 | ≈156 / ≈17,515 | **156 / 17,603** |
> | systems TOTAL lines | 158,615 | ≈157,107 | **157,177** |
> | cross-system total (lines) | 1,132 | 1,104 | **1,102** |
> | UNCOUNTED into `addons/exmateria_sound/` | 22 (E 14, A 8) | ≈38 (E ≈38, A 0) | **17 (E 15, A 2)** |
>
> **THE EARNED FALL IS ONE LINE, NOT FOUR, AND THE REASON IS THE ADAPTER.** This
> decision's most careful paragraph argues `Audio → Debug` retires 4 of 5 lines and
> that predicting 0 would have been false. It was right to refuse 0 and wrong about
> the 4: **measured 5 → 4.** Inverting a dependency does not remove it from the
> census, it RELOCATES it into the host adapter — and the adapter is `src/audio/`,
> which the classifier books to **`Audio`**. So `AudioHostAdapter.gd` contributes
> three fresh `Audio → Debug` lines (`DebugOverlay` ×2, `TuneField` ×1) that no
> prediction here considered, and the host panel half keeps its one
> `BaseDebugPanel`. Four lines, of which only one is a genuine retirement.
>
> *Goal #5's guard and the cross-system column measure different things and this
> pass conflated them.* The guard asks what is inside the ADDON: **0**, exactly as
> predicted, and that number is the portability claim. The column asks what the
> SYSTEM couples to, host residue included, and an adapter is residue. Both are
> correct; only one of them is goal #5.
>
> **THE UNCOUNTED REGISTER RECEIVED 1 OF THE 24 EDGES IT WAS SUPPOSED TO CATCH.**
> This decision says the 24-line fall in the cross-system total "is bookkeeping, and
> the UNCOUNTED register is where it goes". It is not where it went. Measured, the
> 24 decompose as **23 lines naming `ExMateriaEffectSfx.` / `ExMateriaAudioEngine.` as
> AUTOLOADS** (12 in `EffectStudioPage.gd`, 11 in `EffectInstance.gd`) and **1
> preload path**. The register counts lines naming an addon PATH, so it moved by
> exactly one — Effects 14 → 15 — and the other 23 are recorded nowhere at all.
> `Audio`'s own uncounted went 8 → **2**, not 0: six were `EffectSfxEngine.gd`'s own
> preloads, now intra-package, and two are `SfxStressTest.gd`'s, which stays host.
>
> *A compensating register only compensates for the shape it counts.* This is
> ADR-0148 dec. 1's register doing what it was built to do and still missing 96% of
> this event, and it is the sharpest available statement of what dec. 1 costs. #405
> states the limit in pass 8's output; the limit is bigger than pass 8.
>
> **The conservation assertion HELD, exactly.** Across the move commit — the
> interval this decision names, not baseline→HEAD — `Audio` fell **1,636** and the
> package rose **1,636**, files +4. `1,636 = 1,298 + 115 + 43 + 180`, the four files.
> The predicted ≈1,530 was low because #408 and #409 added 106 authored lines to
> those files before they moved, which is the authored/moved split working: the
> authored lines were counted separately and then moved with their file.
>
> **Two file counts are each low by one, and it is the same one.** Predicted 11
> instrument / 6 live against **12 / 7**: dec. 2 says the panel splits, but dec. 9's
> counts added the adapter and `MasterBus` to the host side and not the panel's host
> half. A decision's prose and its table disagreed again — the failure extraction #1
> logged as ADR-0147 dec. 9's, and which this decision's own opening line warns
> about.

**10. `SMDOpcodes` is the shared VM wearing one container's name, and it is
renamed. The rest of `Audio`'s "jargon" is not jargon.** Goal #7 scores `Audio`
**open** on ~200 content-vocabulary lines, and unlike `Render` there is no
platform exemption available — [ADR-0150](0150-psxdisplay-stays-because-render-is-the-playstation-look.md) dec. 6 restricts that to `Render` on
ADR-0117 row 10, and ADR-0117's `Audio` row names sequencing, mixing and banks,
which are jobs rather than a platform. Arguing one by analogy would be the
weakest possible move. Measured instead, over the canonical package's 152 `.gd`
files with comments stripped and literals kept (ADR-0149's rule):

| term | code lines | verdict |
|---|---:|---|
| `SMDOpcodes` | **103** | **debt — renamed** |
| `waveset` / `WAVESET` | 22 | not jargon |
| `SMDParser` / `SMDPlayer` / `SMDFile` / `smd_file` | 16 | not jargon |
| `smd_interpreter_*` probe keys, `smd_tempo`, `smd_expression`, other | ~30 | not jargon |
| **total** | **171** | |

**Sixty percent of the count is one symbol, and that symbol is a real defect.**
ADR-0136 dec. 4 kept three names — *"`smd_player.gd`, `SMDParser` and
`SMDOpcodes` keep their names because they genuinely name the SMD container"* —
and the justification is true of the first two and **false of the third**.
`SMDOpcodes` is the decoder and event vocabulary of the *one opcode language*
ADR-0136 dec. 1 established, not of the `smds` container:

- **69 files under `runtime/shared/` and `runtime/effect_sound/` name it**, on 83
  references, and **80 of those are `SMDOpcodes.OpcodeEvent` / `.NoteEvent`** —
  the payload types every effect-sound handler's `apply()` signature is written
  against.
- `feds_bank.gd` calls `SMDOpcodes.decode_track`, and the host's
  `FedsOpcodeCatalog.gd` calls `SMDOpcodes.param_count_of` on three lines. The
  FEDS path decodes through a class named for SMD.
- Its own docstring says *"SMD opcode definitions and track decoder"* and it
  decodes both containers.

**This is dec. 6's finding at the symbol level.** `shared/` had the right name
and the wrong membership; `SMDOpcodes` has the right membership and the wrong
name. Both are ADR-0136 dec. 1's *one opcode language, two containers* not having
propagated into the tree that implements it. Renamed at pass 6 with the `shared/`
move, and **ADR-0136 dec. 4 is corrected to two symbols, not three.**

> **Amended 2026-08-22 at loop pass 5: this decision says "renamed" and never
> says to what, so pass 5 names it — `SoundOpcodes`, in
> `runtime/sound_opcodes.gd`.** It drops the container name, which is the whole
> defect, and keeps the domain word the package is already named for. It does not
> collide with any of the 152 `class_name`s in the package, and it deliberately
> avoids `FFT*`: introducing a product-content term to fix a container-content
> term would trade one goal-#7 `membership` hit for another.
>
> **The blast radius is smaller than the reference count implies, and it is
> lopsided.** 106 references over 77 files in the addon, all through the global
> `class_name` — a mechanical sweep. But the **host binds the class by preload
> path, never by the global name**, on two lines:
> `src/effects/studio/FedsOpcodeCatalog.gd:32` (bound as `SMD`, which is why a
> grep for `SMDOpcodes` misses all three of its `param_count_of` calls — dec. 7's
> claim is right and reading it needs the alias) and
> `src/effects/studio/EffectStudioPage.gd:53` (bound as `SMDOpcodes`). Two test
> files use the global name for `OpcodeEvent`. So the host cost of the rename is
> **the file rename, on 2 preload lines and 2 test references** — and the file
> rename, not the symbol rename, is the part that can break the host.

The other ~68 lines are **not** renames, and the first version of this decision
proposed a rule for why: *a term is jargon when a better word exists; it is
vocabulary when the thing has no other name.* **That proposal is withdrawn.**

> **Withdrawn 2026-08-22 by ADR-0150 as amended (`8c103aedd`), on a counterexample
> this ADR could not see from its own branch — and the replacement is better.**
>
> - **It breaks the case ADR-0150 already settled.** `pixel_aspect_ratio` is a
>   better word for `psx_par` and it is *already in the tree* for the same
>   quantity — verified here at `src/ui3/elements/UIChar.gd:75`, and it is not
>   one site: `UIFrame.gd:120`, `UI3Element.gd:538`, `UIUnitNameplate.gd:125`,
>   `OpeningScene.gd:36`. So the rule marks `psx_par` jargon and flips `Render`'s
>   goal #7 from met back to open. The platform exemption and *"a better word
>   exists"* are not composable; only one can be the test.
> - **It is not mechanizable.** *"A better word exists"* is a judgement, and
>   encoding it means a hand-maintained list of which terms have better words —
>   an allowlist wearing a principle's clothes, which ADR-0149 dec. 3 refuses.
> - **It exempts the hits that most deserve flagging.** A term naming a ROM
>   container or a disc artifact is *content*, and ADR-0117 dec. 12 keeps content
>   in the host — *"sound banks"* is in its list by name. So a container codec
>   inside a portable addon is a **membership** finding, not a rename finding,
>   and the withdrawn rule would have waved it through.

**What replaces it is a sorting, not an exemption**, and it is ADR-0150's: a #7
count is a *work list*, every hit sorts into exactly one of **rename**,
**membership**, or **exempt**, the sorting is human and cited in the register's
`evidence` column, and **no system scores #7 met while holding a hit of kind 1 or
2.** The count stays blunt and ungameable, which is the property the withdrawn
proposal gave away. `Audio` takes no `exempt` at all: ADR-0117's row 7 reads
`| 7 | **Audio** | the sound driver |` — a job, not a platform.

`Audio`'s 171, sorted:

| kind | lines | what |
|---|---:|---|
| **rename** | 103 | `SMDOpcodes` — decided above |
| **membership** | 38 | `waveset`/`WAVESET` 22, `SMDParser`/`SMDPlayer`/`SMDFile`/`smd_file` 16. **Not renames — the question is whether an FFT container codec belongs inside `exmateria_sound` at all.** Per [#392](https://github.com/timbermania/fft-monorepo/issues/392) that is map [#373](https://github.com/timbermania/fft-monorepo/issues/373)'s tier, not extraction #2's, and this ADR does not answer it |
| **unsorted** | ~30 | the `smd_interpreter_*` probe keys — see below |
| **exempt** | 0 | |

**The ~30 fit none of the three, and that is reported rather than ruled on.**
`smd_interpreter_tick`, `smd_interpreter_gate_skip` and `smd_interpreter_post_gates`
are **PCSX-side routine names**, carried deliberately so the Godot trace rows and
the emulator's diff row-for-row — `probe_emit.gd:41` says so outright (*"PCSX's
`smd_interpreter_tick` walks all…"*, *"PCSX 1635 vs Godot 403 pre-fix"*). Renaming
them breaks the parity diff. They are **RE citations**, the same class
`fft-ghidra/README.md`'s address-citation rule governs, and they are neither our
jargon nor a membership question. Handed to ADR-0150's owner as evidence for a
fourth kind; **not proposed as a rule here**, because a rule is what was just
declined and one instance is not a hole.

**And the sorting question mostly dissolves, at the sink rather than the call
site.** Asked whether the probes belong in `exmateria-sound/workspace/` (the L3
parity rig) rather than `addons/exmateria_sound/` (the L1/L2 product), measured:

- **The 69 emit call sites cannot move**, and that is deliberate rather than
  accidental. `trace_writer.gd:10` states the design: *"When disabled, every
  `emit()` is a fast no-op so the dispatcher can leave its emit calls in place
  without conditional gating at every site."* Hooks in the runtime, sink inert.
- **The sink can, and it is 654 lines — 4.1% of the addon.**
  `probes/probe_counters.gd` 184, `probes/probe_emit.gd` 246,
  `effect_sound/trace_writer.gd` 141, `sequencer/trace/trace_writer.gd` 53,
  `sequencer/trace/trace_opcode.gd` 30.
- **The only thing that can switch it on is not shipped with it.** The
  `--trace-effect-sound=<dir>` flag is parsed in exactly two places, both under
  `exmateria-sound/workspace/harness/` — `render_feds_pair.gd:136` and
  `render_effect_sound.gd:878`. A stranger consuming `exmateria_sound` ships 654
  lines of PCSX-diff machinery with no reachable activator.

That is a goal #5/#6 finding with a number, and it is **stated and not decided**,
for the same reason as the 38: the addon's internal L1/L2-vs-L3 composition is
map #373's tier under #392, not extraction #2's. What extraction #2 takes from it
is that the ~30 probe keys are a symptom of a membership question, not a naming
one — which is what ADR-0150's third reason predicted, arriving one level deeper
than either of us looked.

**One caveat on the replacement, stated because this pass just spent a day on
exactly this failure.** ADR-0150's third reason rests on *"the opcode language is
engine, the container is content"*, attributed to ADR-0136 dec. 1. Dec. 1's text
says *"one opcode language in two containers … below the header they are the same
bytecode"* — a claim about **format structure**, not about engine-vs-content
ownership. The extension is plausible and probably right, and it is an
**extension**, not a citation. It is worth arguing on its own evidence before a
membership finding is built on it, for the reason ADR-0154 found four citations to
a phrase ADR-0112 does not contain: a link that resolves is not a link that
supports.

> **Amended 2026-08-22 at loop pass 6: this decision's 171 and the concurrent
> scorer's 210 are BOTH right, and the reconciliation is that they count
> different units.** `score_goals.py` prints `Audio #7 open — 210 lines across 82
> files`; the sort above rests on **171** over the same 152 files. Neither is an
> error and **it must not be settled by whichever ran last.** The 39 decomposes
> exactly:
>
> | gap | why |
> |---:|---|
> | **+20** `waveset` | the scorer matches the SUBSTRING, so `waveset_id`, `_waveset` and local variables count; the sort above counted `waveset`/`WAVESET` as symbols |
> | **+9** `fft` | in the scorer's content lexicon and **absent from this sort entirely** — the sort has no `fft` row |
> | **+~10** loose `smd` | a local `var smd`, the path template `MUSIC_%02d.SMD`, and diagnostic strings |
>
> **So the unit is stated rather than the number changed.** This decision counts
> **symbols worth an edit**, because that is what a `rename` / `membership` /
> `exempt` sorting acts on; the scorer counts **lines containing a jargon token
> in code**, because that is what an ungameable census needs. Both stand.
>
> **And a documented part of the excluded tail is unrenameable BY CONSTRUCTION,
> not merely trivial.** Measured — seven `SMD` string literals in the package:
> `runtime/asset_paths.gd:83` is `"SOUND/MUSIC_%02d.SMD"`, **a path on the PSX
> disc**; `smd_parser.gd:34/43/48` are `"Cannot open SMD: "`, `"SMD too small"`,
> `"Invalid SMD magic"`, which name **the on-disc format**, and the format really
> is called SMD. #407 must leave every one of them alone — renaming them would be
> a defect, not progress. Only `smd_player.gd:111/114`'s `"SMDPlayer: …"`
> prefixes are symbol echoes that follow their symbol.
>
> **A proposed lexicon refinement — skip literals passed to
> `push_error`/`push_warning`/`print*` — was offered and DECLINED**, and the
> reason is the distinction above. It would exclude `"Invalid SMD magic"` because
> of *where the literal is passed*, when what actually protects it is *what the
> token denotes*: right answer, wrong rule. A `push_error("smd_interpreter tick
> overflow")` is a symbol echo and should still count. Goal #7 keeps reading
> string literals — ADR-0153's own consequence (the scorer read `Render` as **3**
> where the truth was **34**, because literals were stripped) was bought at too
> high a price to spend here.


## Considered alternatives

- **Defer the config seam to `D4` (#377).** Rejected — #377 was re-scoped
  mid-flight to hand the mechanism back to this pass, and #392 assigns it here
  outright. Two efforts answering it differently is the specific failure #392
  exists to prevent.
- **Answer #393 with a new ADR about `Debug`.** Rejected. Two of its three
  candidates are closed by an Accepted ADR, and re-deciding a decided question in
  a new ADR is how a repo grows two answers. The residue is an enforcement gap,
  and an enforcement gap is a guard.
- **Move `SpuAudioDebugPanel.gd` to the host instead of the addon.** Rejected on
  ADR-0140 dec. 2 and dec. 8 together: per-system panels ship with their system,
  and the panel is a view over a value `ExMateriaEffectSfx` owns. Splitting them
  puts a view in one package and its subject in another for no gain.
- **Keep `ExMateriaEffectSfx` as a host adapter autoload forwarding to the addon.**
  Rejected: it preserves all 22 inbound lines against a ~30-line forwarding file,
  so the metric would show the extraction as free and the coupling would be
  exactly as it is now. The honest reading is the one where the lines move to the
  uncounted register and get named.
- **Rewire `Effects`' eleven imperative driver calls into ADR-0124's channel as
  part of this pass.** Rejected, though it is the right end state and dec. 2 of
  the audit shows why. It changes a file in another system, it is what ADR-0127's
  two ports are for, and it belongs to `Effects`' extraction. Recorded as the
  residue that keeps `Audio`'s inbound at 22 rather than near zero.
- **Rename `shared/` to `effect_sound_vm/` as ADR-0136 dec. 7 describes.**
  Rejected on dec. 6's measurement: 61% of the tree is genuinely common, so the
  rename would put the wrong name on the majority to fix the minority.
- **Fix `capture_mode`'s second use in this pass.** Rejected — it is a live-audio
  behaviour change inside the file being moved, and pass 6 moves it. Recorded as
  a soft spot on the file, per ADR-0147's precedent with the fold-order call site.
- **Take the `--delta` extracted reading from the host's deployed copy** rather
  than the canonical package. Rejected by ADR-0131 dec. 8 for the reason #326
  just demonstrated: the copy was 72 lines behind for weeks and nothing noticed.

## Consequences

- **`Audio` becomes the smallest system in the package**, at ≈1,300 lines against
  `Campaign`'s 1,123 and `Render`'s 699 — third smallest. The system that
  `BLUEPRINT.md` called *"The closest system to finished"* was, at 2,834 lines in the
  host, the seventh largest.
- **The systems total falls for the first time in the series** (≈−1,508 net:
  ≈−1,530 moved, ≈+22 authored adapter).
  Extraction #1 moved code *within* the walk and the total held; extraction #2
  moves it *out*. Anyone reading `BASELINE.tsv --delta` after this must read the
  extracted row in the same glance, which is the reason dec. 1 makes it a
  reading.
- **#377 can close citing this ADR** for its decisions 1–4 — mechanism, split,
  what `DebugConfig` becomes, and which lines are addon vs game glue. What it
  keeps is its narrowed half: whether a *stranger's* config surface is served by
  a `tunables()` declaration that only `godot-learning`'s adapter consumes. This
  pass does not answer that and does not claim to.
- **#392 gets its transcription:** the boundary falls at the SPU/bus line, the
  driver split is dec. 2, the `shared/` outcome is dec. 6 (a move, not a rename —
  `D1`/#374 should be re-read against it), and the metric is dec. 9.
- **#326 is closed and the closing move is a `rsync`.** The lesson is worth more
  than the fix: a gitignored deployment target with no freshness check went 72
  lines stale and surfaced as a parse error in a *different* package's UI.
  Nothing tells anyone to re-run the sync. That is fog, and it is recorded as
  such rather than fixed here.
- **`BLUEPRINT.md` §7 and the *Subscription, not calls* paragraph are both
  wrong for `Audio`**, and the same sentence is untested for `Camera` and
  `Body`. Recorded, not silently repaired.
- **Two guards are owed and both are ADR-0151's**: the addon-side debug-coupling
  ban (ADR-0140 dec. 8's unwritten guard) and the widened panel marker that keeps
  `check_debug_panel_tunables.py` from losing its subjects (the trap that guard
  sets). Extraction #2's pass 6 is a **consumer** of both. If ADR-0151 has not
  landed when pass 6 runs, `SpuAudioDebugPanel` un-inherits anyway and the
  coverage gap is carried openly rather than papered over with a local guard that
  would then need retiring.
- **`Audio` gets no goal scorecard from `tools/score_goals.py`, and that is a
  real cost of dec. 1.** ADR-0149's instrument scores every addon in
  `_walk_roots.addon_roots()`, which filters `WALK_ROOTS` for a parent named
  `addons` — and dec. 1 keeps `exmateria_sound` out of `WALK_ROOTS` deliberately.
  So the first system to extract into a published package is the first one the
  goals instrument cannot see. Dec. 1 buys baseline integrity and pays for it
  here. The fix is the same shape as dec. 1's `--delta` reading — a second,
  package-boundary root list that the scorecard reads and the census does not —
  and it is **owed at pass 9, not solved here**, because the right list is not
  knowable from one member.
- **`Audio` is the first real test of ADR-0149's per-domain goals.** `Render`
  could only score 8 of 10; `Audio` owns the SMD/WAVESET formats and has an
  authoring surface, so goals 6 and 10 should score for real rather than `n/a`.
  If a jargon count is written for `Audio` at pass 9, **do not strip string
  literals** — ADR-0149 found that borrowing `touch_matrix.strip_noncode` whole
  scored `Render` 3 where the truth was 34, because a `Tune` slug is the most
  public vocabulary an addon has and it lives in a literal.
- **Soft spot, stated plainly:** dec. 1 declares a rule — *the walk reports
  across a package boundary rather than following* — on a sample of one. It is
  right for `Audio` because the destination package predates the refactor and is
  independently versioned. It is **not** obviously right for a future system that
  gets extracted into a *new* sibling package, where following the code would
  cost nothing. The rule as written would send that case to the reporting path
  too, and the reason it should is weaker there. If a second such case arrives,
  re-read this decision before applying it.
- **Second soft spot:** the ≈1,530 rests on judgements about how two small files
  cleave — `AudioEngine.gd` and `SpuAudioDebugPanel.gd` — and dec. 9 asserts an
  equality (`Audio −N`, `extracted +N`) that will hold whatever N turns out to be.
  The *assertion* is safe; the *prediction* is the part that can miss, and it is
  two files' worth of arithmetic.
- **The panel split was found by a peer's question, not by this pass's audit.**
  ADR-0126's six checks did not ask *"is this panel bespoke or declarative"*, and
  without that question the panel would have entered the addon whole, carrying
  `ExMateriaAudioEngine.get_master_volume()` — a reach back into the host — into a package
  whose whole purpose is not to have one. **The check generalises and is owed a
  slot: for every view that moves with its subject, ask whether the view has more
  than one subject.** Recorded here rather than added to ADR-0126, because one
  instance is not a hole (extraction #1's lesson) and the second instance should
  be the one that amends the loop.
