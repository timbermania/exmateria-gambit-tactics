# An addon reaches no system, and a panel that declares nothing is not built at all

Goal #5's mechanical rule, the guard [ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md)
dec. 8 named and declined to write, and its first application: **`Render`'s two
debug panels are deleted, not re-homed.** They declared nothing —
every slug they showed is bound by an owner elsewhere — and ADR-0068 dec. 9
already renders every registered slug. `Render` now reaches **zero** systems.

Status: accepted (2026-08-22). Discharges ADR-0140 dec. 8's owed guard. Applies
[ADR-0113](0113-tunables-invert-at-the-addon-boundary.md) as amended by ADR-0140
dec. 7. Answers [#393](https://github.com/timbermania/fft-monorepo/issues/393)
for `Render`. Scored by
[ADR-0149](0149-the-ten-goals-are-scored-per-extraction-and-three-of-them-are-not.md).

Code at `a785fbd0b`, classifier at `a785fbd0b`.

## Context

`addons/exmateria_render/` shipped with five reach lines into the host, all
`Debug`'s: `extends BaseDebugPanel` ×2 and `TuneField` ×3. That was the only
thing between `Render` and goal #5, and #393 framed it as blocked on *"does
`Debug` extract?"*

**It was not blocked.** ADR-0140's *Considered alternatives* rejects "`Debug` is
host machinery" verbatim; dec. 2 decides "`Debug` extracts like any other
system"; ADR-0146 dec. 3's admission test already kills "promote the panel base
to the kernel". All three of #393's candidate answers were settled by Accepted
ADRs before the ticket was written. What was genuinely open is the thing
ADR-0140 dec. 8 said about itself:

> *"nothing in this ADR stops the 40th panel from extending the base class
> again. A guard would, and this ADR does not write one."*

Extraction #1 shipped the 40th panel. Twice.

## Decision

**1. No file under an addon root may name a symbol the classifier books to a
SYSTEM.** A `platform` port and the `schema` kernel are fine and are the point —
a port is what a portable addon is *allowed* to reach (ADR-0139 dec. 12,
ADR-0140 dec. 9). `Render` still names `Tune` and that is the rule working, not
an exception to it.

**2. `tools/check_addon_portability.py` enforces it.** It reuses
`score_goals.outbound_reaches`, so "a reach" has one definition in the package.
It is an **enforcing gate**, unlike the scorecard: `score_goals.py` is green
while a goal is honestly `open`, and this is red the moment an addon acquires a
system reach. Direction-tested on a real violation, not on the guard existing —
a probe naming `BaseDebugPanel` and `TuneField` inside the addon reports both
lines and exits 1.

> **Corrected 2026-08-22: "enforces it" was true of the walk, not of the rule.**
> The guard's subject is `classify_blueprint.WALK_ROOTS`, which **deliberately
> excludes a system that extracts into a published package** (ADR-0153 dec. 1,
> and `tools/_walk_roots.py` carries the reproduction). Measured: the canonical
> `exmateria-sound/addons/exmateria_sound/` is inside no walk root and is not an
> addon root. So for `Audio` — the very next extraction — a file **would not
> leave this guard because it stopped inheriting; it would leave because it left
> the walk**, and this decision's rule would revert to a convention at exactly
> the moment it began to matter. `check_debug_panel_tunables.py` has the same
> subject and the same limit, which makes **two** instruments blind at the package
> boundary in addition to the three already recorded (`--delta`,
> `closure`/`residue`, `score_goals.py`) — and these two are the ones this ADR and
> ADR-0153 dec. 4 lean on hardest.
>
> **Fixed rather than caveated**, for the portability half: `--root <path>
> --system <name>` runs the same scan over a package the walk does not own, so
> the rule is mechanized on demand instead of lapsing. Explicit arguments on
> purpose — the walk keeps its single definition and a caller has to name the
> package and can be asked why. Direction-tested against the real canonical
> package: a probe there naming `BaseDebugPanel`, `TuneField` and `DebugConfig`
> reports three lines and exits 1. **Run it at pass 9 against the destination
> package**; that is the moment the rule is otherwise unenforced.
>
> Found by extraction #2 checking a claim of mine before building on it. The
> claim was in a message and then in this decision, which is the difference
> between a slip and a defect.

**3. The exclusion is the addon ROOT, not the system's bucket.** An addon
reaching a file still booked to its own system scores zero under a
bucket-keyed test, and every extraction after `Render` leaves host-side residue
— a screen that stays behind, a panel whose subject splits. Goal #5 would fail
while the test passed. (Found by extraction #2 reading this instrument before it
shipped; `Render`'s own number is unchanged either way.)

**4. A system's bespoke panel ships as a plain `Control`, and the mounting half
is already inverted.** `DebugOverlay.register_panel(panel, category)` takes an
**untyped** `panel` and touches only `set("panel_category")` and
`get("panel_title")`; `DebugDashboard` guards `on_registered` / `on_shown` with
`has_method`. A `PanelContainer` satisfies the whole lifecycle. The priced cost
of not inheriting is `BaseDebugPanel`'s **11 helper functions / 104 non-blank
lines** of separators, section titles, fold sections and spinbox accessors,
which the addon re-provides for itself. That is the only cost of this rule and
it is worth naming rather than discovering.

**5. A panel that is only `TuneField` rows is not built at all — and that is
what `Render`'s two were.** ADR-0068 dec. 9 already says the dashboard is
*generated from the registry* and *"hand-built panels stay for **bespoke** UI"*.
Measured, both of `Render`'s panels are pure declaration, and every slug they
showed is bound by someone else:

| slug | bound by | line |
|---|---|---|
| `debug.show_depth` | `DebugConfig` | `DebugConfig.gd:432` |
| `render.psx_dither_enabled` | `DebugConfig` | `DebugConfig.gd:427` |
| `render.psx_gamma` | `PSXDisplay` | `PSXDisplay.gd:91` |

So the panels owned nothing, declared nothing, and duplicated a surface that
already exists. **They are deleted**, with their five call sites across four
host scenes. This is ADR-0113's inversion completed for `Render` — and it needed
no new machinery, because the *host renders it* half was built by ADR-0068
dec. 9 and nobody had noticed the inversion was already finished.

**6. `check_debug_panel_tunables.py`'s marker is widened in the same commit, and
it had to be.** That guard keys its entire contract on `^extends
BaseDebugPanel`, with `ENFORCE = True`. Dec. 4 retires that line from inside an
addon, so a panel that follows this ADR becomes **invisible** to it: four edges
bought, coverage silently lost — ADR-0148's defect with a marker in the role of
a scan root. A panel is now *either* a file that extends the base class *or* a
class some walked file mounts through `DebugOverlay.register_panel`. **The
registration is the identity**, read directly rather than replaced with a new
convention nobody enforces. It finds 31 classes; direction-tested with a
registered `PanelContainer` holding a raw `SpinBox`, which the old marker misses
and the new one catches.

## Considered alternatives

- **Move the two panels back into `src/debug/`.** Rejected: it satisfies goal #5
  by growing the host, and [ADR-0121](0121-systems-land-in-addons-src-only-shrinks.md)
  dec. 2 is *"`src/` is never reorganised... It only ever gets smaller"*. It also keeps a hand-built duplicate of a generated surface alive.
- **Un-inherit them — keep the panels, drop the base class.** Rejected for
  `Render` specifically. It is the right answer for a *bespoke* panel and is what
  dec. 4 provides; these two are not bespoke, and un-inheriting them would
  preserve 65 lines whose entire content the registry already renders.
- **Build a generated categorised panel in `Debug`** — group registered slugs by
  a declared `panel` / `category` in their `Tune` meta and mint one card per
  group. Genuinely attractive, and it is what ADR-0113's sentence sounds like it
  asks for. **Rejected because it re-adds what ADR-0068 dec. 9 already
  superseded**: the generated `TuneDashboardPanel` masonry cell was removed in
  favour of the full-width Registry page. Building it back to avoid deleting two
  panels would have been the expensive mistake in this ADR.
- **Promote `BaseDebugPanel` to the shared kernel.** Rejected by ADR-0146
  dec. 3's admission test — a member has a counterpart, and it has no second
  implementation. #393 already listed this and it was already dead.
- **A `# portable-exempt:` escape hatch on the rule**, mirroring
  `check_debug_panel_tunables.py`'s `tune-exempt:`. Rejected: that hatch exists
  for a control that genuinely cannot be Tune-backed. There is no reach into a
  system that an addon genuinely cannot avoid — if there were, the seam is in the
  wrong place, and an exemption would hide exactly that.

## Consequences

- **`Render` reaches zero systems. Goal #5 is met**, and `Render` scores **5 met,
  2 n/a, 3 open** against an achievable 8.
- **Nothing was lost, and this was measured rather than argued.** With the panels
  deleted, all three slugs appear on the Registry page with their type, range and
  default intact — `debug.show_depth` (bool), `render.psx_dither_enabled` (bool),
  `render.psx_gamma` (float, `0.5..3.0 /0.1`, default `1.4`) — 77 rows in total.
  The four scenes that built the panels (`EffectViewer`, `GPUArena`,
  `ScenarioPlayer`, `TrapViewer`) boot with no script error.
- **What IS lost is a categorised card**, and it is worth stating plainly: the
  DISPLAY tab no longer carries a "Display" card with two toggles, and the
  SHADERS tab no longer carries "PSX Color". A developer who used them now finds
  those slugs on the Registry page. The DISPLAY tab is not empty —
  `UIDisplayDebugPanel` is `UI`'s and stays in the host.
- **`ShaderCalibrationPanelTuneFieldTest` is deleted with its subject.** What it
  guarded — bind, project, render an editable row — is held by
  `PsxColorCalibrationTuneTest` (ownership + coalescing),
  `TunablesRegistryModelTest` (*"one row per registered slug"*) and
  `TunablesRegistryViewTest` (the row renders). Its one unique assertion, that
  the retired Brightness row is absent, is vacuous without a panel and is held
  properly by `check_no_psx_brightness_in_fold.py`.
- **#393 does not need an ADR of its own.** It asked whether `Debug` extracts;
  the answer was in ADR-0140 dec. 2 before the ticket was filed, and the part
  that was actually open was dec. 8's unwritten guard. Filed as a question about
  a system, it was a question about a missing instrument.
- **Extraction #2 consumes this rule rather than restating it** (ADR-0153 dec. 4
  and dec. 5), and it has already stress-tested dec. 5: `SpuAudioDebugPanel` is
  **bespoke** — 1 of its 146 lines is a `TuneField` row — so it un-inherits under
  dec. 4 rather than being deleted. Asking dec. 5's question of it found that the
  panel has **two subjects**, a host-owned master-volume slider and an
  addon-private readout, and so splits where its subject splits. **A view splits
  where its subject splits** is the general form, and no check in ADR-0126 asks
  for it; recorded as owed there, not amended on one instance.
- **`Audio` reaches zero systems today too**, measured through
  `score_goals.py --root ../exmateria-sound/addons/exmateria_sound --system
  Audio`. Its open goals are #4 (it is outside `WALK_ROOTS`, so no guard watches
  it) and #7 (210 content-jargon lines — `smd`, `waveset`, `fft`). Neither is a
  reach.
