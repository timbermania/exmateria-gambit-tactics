# ADR-0263 — Panel applicability is a property of a SLUG, and the instrument must not certify itself

- **Status**: Accepted
- **Date**: 2026-09-08
- **Supersedes**: the per-scene debug-panel list (`GambitBattle`'s deliberate short one)
- **Cites**: ADR-0035 (the dashboard is a Window), ADR-0068 (tunables; R1, R5, R8, dec. 12),
  ADR-0151 (a declarative panel is not built — the widened guard marker),
  ADR-0173 (`reset()` cannot rebuild a class-load declaration), ADR-0153 dec. 3 (the audio adapter)

## Context

Two production scenes `extends CombatHost` — `GPUArena` and `GambitBattle`. Each answered
"which F3 panels do I get" with its own hand-written list, and the two drifted to **twenty
versus one**. `GambitBattle` printed `F3 - debug overlay` in its boot banner while registering
nothing, so the `pacing.*` knobs were unreachable in the only mode that needs them (#1050 fixed
that by adding a single panel — it did not fix the shape that allowed it).

The obvious repair — mount every panel on both hosts — runs straight into a question nobody had
a mechanism for: **which panels even apply here?** The formation screen has no battlefield, so
what happens to the battlefield tunables?

Three cheaper answers were considered and all three are wrong in ways that do not announce
themselves:

1. **Gate on the `setup()` signature.** Four of the nine panels that take a subject never read
   it — `CursorDebugPanel.setup(_rig: CursorRig)`, `CameraFeelDebugPanel.setup(_camera)`,
   `UnitShaderDebugPanel.setup(_scene_root, _get_units_func)` — they migrated to pure `Tune`
   views under ADR-0068 dec. 12 and kept the parameter. Meanwhile `TilesDebugPanel.setup()`
   takes **nothing** and is a pure view onto `tile.*`, owned by
   `addons/exmateria_battlefield/overlay/TileOverlayConfig.gd`. The gate excludes the cursor
   panel for a rig it never reads and waves the battlefield panel through. It fires on the
   wrong axis in both directions at once.

2. **Ask per panel.** A panel is a bag of rows whose owners differ. `FormationScene` mounts
   `DetailScreenDebugPanel` (`detail.*`, ephemeral owner) beside `VitalsLayoutDebugPanel`
   (`vitals.*`, live owner) — two liveness stories, one cell. There is no single answer to give.

3. **Use `Tune._subscriber_count`.** This is the one that would have shipped and looked right.
   `TuneField.build_control` calls `Tune.bind_update` on **every row it renders** — that is how
   a control resyncs when another surface scrubs the same slug — and `on_update` bumps the
   counter. So "is anything consuming this slug" answered with the raw count is **true for any
   slug that has a visible control**, which is every slug the page is asking about. The
   instrument certifies itself, reports every knob live on every screen, and is indistinguishable
   from a working one. The pull side has the mirror defect: `add_dropdown` and the Registry page
   read through `get_value`, which stamps the R8 pull-read clock, so painting a row marks it read.

## Decision

1. **Applicability is a property of a SLUG, not a panel.** A panel's status is *derived* — the
   counts of its rows' states. `TuneField` stamps each row it builds with its slug
   (`TuneField.SLUG_META`, set in `_add_label_and_marker`, the one choke point all three row
   shapes pass through **including the unregistered-placeholder path**); `PanelApplicability`
   walks a built panel and asks `Tune.consumer_state` per slug.

2. **The instrument discounts itself.** `Tune.on_update` / `bind_update` take `as_view`, and
   `TuneField.build_control` passes `true`. `Tune.peek` is the pull-side twin: the coalesced
   read that does **not** stamp the R8 clock, used by `add_dropdown` and `TunablesRegistryView`.
   `consumer_state` subtracts view subscribers from the total.

   **R8's own `_subscriber_count` test is deliberately left counting both.** Tightening it would
   newly warn on every slug whose only subscriber is its panel row — a separate audit with its
   own fallout, not a side effect of adding a dashboard page.

3. **Three states, and only two are claims.** `UNDECLARED` (no `bind` ran this process — the
   owner's class never loaded), `CONSUMED` (a non-view push subscriber, or ≥1 `get_value`),
   `DECLARED` (bound, nothing *observed* consuming it). `DECLARED` is the **absence of evidence,
   not evidence of absence**: a pull consumer that reads once at build time is indistinguishable
   from a dead knob. Every label is phrased as an observation — "declared — no consumer seen",
   never "dead". `PanelApplicabilityTest` mechanizes that as a banned-word assertion.

4. **Bindability is demoted to crash-prevention.** The catalogue skips an entry only when
   mounting it would build a *broken* view. Exactly one entry qualifies today:
   `ProgressionDebugPanel`, whose rows are per-unit and which would otherwise mount permanently
   empty — worse than absent, because it looks mounted.

5. **Nothing is ever hidden.** The presenting complaint was a panel that was not there. A page
   that omitted entries it judged inapplicable would reproduce that bug wearing a justification.
   Off, unmounted, and mounted-with-nothing-consuming-it are all **listed, with the reason**.

6. **One mount, two hosts.** `CombatPanelCatalog.mount(host, into, opts)` is idempotent by id
   and **meant to be called twice**: `GambitBattle` mounts at `_ready` (so the pacing knobs are
   reachable through deployment) and again at `start_battle` (when the roster exists).

7. **The user's on/off set is global**, persisted as the **disabled** ids in
   `UserSettings.debug_window.disabled_panels`. Applicability is already derived per host, so
   this switch only ever means "I do not want to look at this". Storing the disabled set is what
   makes a panel added later default **on**.

8. **The catalogue is a function, not a table.** One `var X = ClassName.new()` paired with one
   `register_panel(X` per panel. A `const PANELS := [preload(...)]` loop is tidier and silently
   deletes every panel from `tools/check_debug_panel_tunables.py`, which reads panel identity
   off exactly that pair (ADR-0151's widened marker). Verified after the refactor: the guard
   still identifies all 13.

## Rejected

- **Subscriber-count as the liveness signal** — self-certifying, see Context 3.
- **A scene-scoped registry clear**, so `DECLARED` would mean "live *here*". `Tune.reset()`
  cannot rebuild a class-load owner's declarations (ADR-0173) and the replay that would fix it
  is the seventeen-script-path enumeration `BLUEPRINT.md` rejects. The staleness is accepted and
  labelled instead: once a battle has booted, its slugs stay declared everywhere for the session.
- **A per-host toggle matrix** — state nobody maintains, re-asking by hand what derivation answers.
- **Fixing the four lying `setup()` signatures** — five call sites, a separate greppable cleanup.
  Recorded here so the next reader knows it was seen, not missed.

## Declined, and named so it is not mistaken for an oversight

**The scoped-slug footgun is out of scope.** `FormationScene`'s own comment records it: the
`vitals.*` slugs are shared with the battle HUD, so dialing them on the formation screen and
committing the value retunes the battle. There the panel is applicable, the rows are consumed,
the knob works — and it is still wrong. That is a *scoping* problem, not an applicability one,
and mounting more panels on more hosts makes it strictly more likely. This ADR does not address
it.

## Consequences

- `GambitBattle` mounts **13 catalogue ids / 12 tracked panels** at `_ready` (verified headful),
  up from one, with `progression` correctly deferred to `start_battle`.
- **A pre-existing debt is now visible on a second host.** Mounting panels at `_ready` builds
  rows whose owners have not bound yet, raising ADR-0068 R3/R5 assertions. Measured: `GPUArena`
  on `origin/main` = **150** `before its bind` errors; `GPUArena` with the catalogue = **147**;
  `GambitBattle` with the catalogue = **150**. So the refactor did not create this and does not
  worsen it per host — it makes the gambit host behave exactly like the arena, **including in
  its debt**. Paying it down is an ADR-0068 R5 job across many panels, not this change.
- `DebugDashboard` grows a fifth page, `Catalogue`, listing entries, bespoke mounts (so the page
  is a census of the *window*, not of the catalogue), and the caveat about what the counts
  cannot know — in the window, because a reader who has to find this ADR will read the column as
  a verdict.
- `GambitBattlePacingPanelTest` arm 1 now spans two files: the host must reach the catalogue
  asking for the playback row, the catalogue must build and register the panel.
