# Scene configuration lives in debug panels, not environment variables

## Status

Accepted

Verified 2026-08-28 — dec. 2 is mechanized at hard zero (`tools/check_no_env_vars.py`,
wired at `tests/run_all_tests.sh:424`), decs. 3–5 are built, and dec. 1 holds across 67
`register_panel` calls but is **violated for three scenario-camera knobs** whose panel
was deleted two days after the env vars it replaced — see `AUDIT.tsv` and issue #677.
See `audit-notes/0051.md`.

## Context

Scene scripts had grown ad-hoc `OS.get_environment(...)` reads to gate behaviour:
`SCENARIO_PLAY_THROUGH` to skip dialog halts in `ScenarioVM`, `SCENARIO_NO_CAMERA` to
disable camera takeover, `SCENARIO_TRACER_SCREENSHOT` plus `SCENARIO_TRACER_DELAY` to
fire a viewport capture and quit. The pattern is appealing — a one-liner, CI-friendly,
and it sidesteps writing a UI. It also produced concrete surprise-behaviour bugs: an
env var leaked across shells made the `ScenarioPlayer` scene silently
`get_tree().quit()` at PC 42 in an editor session that did not know the var existed,
presenting as "the scene closes itself." That class of bug — invisible config, action
at a distance from a different terminal session, no in-editor surface — is the cost of
using process environment as configuration in an interactive editor workflow.

## Decision

1. **All scene-level configuration MUST flow through the F3 DebugOverlay panel
   system.** Toggles, parameters, capture triggers — whatever the knob does, it gets a
   `BaseDebugPanel` subclass surface (checkbox, spinbox, button), registered via
   `DebugOverlay.register_panel(...)`. See `ScenarioVMDebugPanel`, `LoggingDebugPanel`
   and `CombatUIDebugPanel` for the established pattern, plus `docs/debug-panels.md`
   for the `BaseDebugPanel` helpers. **A knob whose panel is later deleted does not
   become source-edit-only by default** — deleting the surface reopens the decision
   that retired the knob's previous one.

2. **`OS.get_environment(...)` is banned in `src/` and `tests/`.** Not as a soft
   preference — as a build-breaker. The function exists in Godot for tools that
   genuinely need OS info (locale, user dirs); the ban is specifically about reading
   env vars to drive scene behaviour, and it covers throwaway debug gating (`*_DIAG`
   prints) as well as real config. A genuine process-state read — headless-vs-headful
   detection and the like — opts out with an explicit `# env-var-exempt: <reason>`
   marker on the same line, which is a code-review call, not a routine convenience.

3. **Automation invokes methods, not env vars.** A harness that needs the scene to
   capture a screenshot calls a verb on the scene (`WorldMapScene.capture_to(path,
   quit_when_done)`, `CombatUITestScene.capture_dialogue_box_to(path)`) or pushes the
   panel button that calls it. The scene script never branches on environment.

4. **Toggles persist as scene-level vars, not autoload globals.** The toggle lives on
   whichever node owns the behaviour — `ScenarioVM.play_through_skip_unknown` is the
   model, a property with a setter that handles mid-run state. The panel and the
   Inspector are thin views onto that property, never the source of truth.

5. **A rig that must choose *before* `_ready` runs sets the exported properties from
   `--` user args.** `OS.get_cmdline_user_args()` in `--key=value` form is the
   sanctioned way to SET a scene's exported configuration at launch. It writes the same
   properties the panel edits (`WorldMapScene`'s `fixture`, `zoom`, `capture_path`,
   `boot_menu`, with `WorldMapDebugPanel` as the view) — it is not a parallel surface,
   it introduces no second reader, and a property with no `--` writer is not thereby
   second-class. Dec. 1's route cannot serve this case: `boot_menu`'s `townopen`,
   `screenin`, `town` and `move` arms render contact sheets, they branch inside
   `_ready`, and a checkbox clicked afterwards needs the process restarted with the
   choice already made — which is a launch argument with extra steps. This is not
   what dec. 2 banned: the failure mode there is an env var *leaking across shells*,
   and a `--` arg is per-invocation and visible in the command typed, so no stale
   `export` can silently arm it. The form is the tree's own — 21 files already take rig
   parameters this way, among them `tools/capture_startmenu.gd` — written a month after
   dec. 2's guard landed — and `src/scenes/UnitInfoWindowViewer.gd`, which proves it
   works for a directly launched scene and not only a `-s` script. **One reader per key**: a test must not
   reuse the scene's own key, or a single capture request arms both the test and the
   scene.

## Considered options

- **Widening the `# env-var-exempt:` hatch to cover launch-time scene config.**
  Rejected: its stated condition is a *process-state* read, and a fixture or a capture
  path is scene config. Dec. 5 is the route instead. The hatch has never been used —
  it appears tree-wide only inside the guard itself, as the docstring example and the
  `EXEMPT` constant. That is the strongest available evidence that dec. 2's absolutism
  was correctly priced.

- **Keeping the env-var one-liner for CI only.** Rejected: it reintroduces a hidden
  conditional that fires only when the var is set, so the path CI runs is not the path
  the editor runs. The harness pays for a method call instead, deliberately.

- **A test reusing the scene's own `--` key.** Shipped in `WorldMapMountTest`, then
  deleted. The test used the scene's `SHOT` key, so one capture request armed both: the
  mounted screen shot on its own and `Focus.pop`ped itself out of the rig's way,
  failing the test's stack assertion. A test's job is its assertions; the facility was
  removed rather than disambiguated.

## Consequences

- The ban is a check, not a convention. `tools/check_no_env_vars.py` fails the build on
  any `OS.get/has_environment` read and runs as a `run_all_tests.sh` pre-flight. It
  scans the walk roots plus `tests/` — so `tools/` is *outside* it, and the pattern can
  still be written there unseen (issue #678).
- A contributor reaching for "let me just check an env var" hits the rule in
  `godot-learning/CLAUDE.md` and `docs/pitfalls.md` and routes through the panel
  system. The "wrong default" failure mode — invisibly enabled because a previous shell
  exported it — cannot happen.
- The F3 debug panel is the canonical place to discover what a scene exposes: a
  contributor opening a scene cold presses F3 and sees every toggle, instead of
  grepping for `OS.get_environment`.
- **The guard only checks the half that was retired.** It asserts the *absence* of env
  reads; it cannot assert the *presence* of the panel whose existence was the argument
  for deleting them. That is how three scenario-camera knobs came to have no writer at
  all — see Verification.

## Verification

- `tools/check_no_env_vars.py` — hard zero across the walk roots and `tests/`;
  `tests/run_all_tests.sh:424` aborts the suite on a violation.
- `tests/WorldMapDebugPanelTest.gd` — dec. 4's view/model split, asserted on the
  world-map panel.
- Dec. 1 has **no** mechanical arm, and it is the one currently violated:
  `camera_disabled`, `camera_backrotate_invert` and `camera_flip_body_depth` on
  `ScenarioCameraDirector` have readers and no writers, because
  `ScenarioCameraDebugPanel` — named by an earlier revision of dec. 1 as an exemplar —
  was deleted at `137b94b40` (2026-07-06), two days after the env vars it replaced.
  Whether to restore that surface or close the knobs is open: issue #677, with both
  readings. The proposed guard arm is in `AUDIT.tsv`.
