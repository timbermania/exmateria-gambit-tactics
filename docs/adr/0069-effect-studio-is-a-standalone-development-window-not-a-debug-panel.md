# The Effect Studio is a development workspace, hosted as a page in the debug window

## Status

Accepted

Verified 2026-08-28 — decs. 3–6 built across `src/effects/studio/` (116 scripts,
~40,600 lines) and 87 `tests/EffectStudio*Test` suites. Decs. 1 and 2 shipped on
2026-07-13, were reversed in writing the same day, and were deleted from the tree
the next; their numbers are retired and the design they named is in
`## Considered options`. The filename still spells the
retired decision — it is kept as the address four ADRs and a dozen in-code
comments cite; this H1 is the claim. See `audit-notes/0069.md`.

**Relates to:** [ADR-0035](0035-debug-ui-is-a-separate-os-window.md) — the debug
UI's separate OS window is the window this page lives in, and ADR-0035's third
amendment now names the Studio host page as the precedent for its whole-surface
pages. [ADR-0070](0070-effect-replay-is-deterministic-within-an-instance-via-a-per-instance-seeded-rng.md)
makes the scrub frame-exact. [ADR-0004](0004-rosters-share-a-base-script.md)'s
surviving half — extend by path, not by `class_name` — governs the scripts.

## Context

The first cut of the effect timeline shipped as a `CanvasLayer` strip pinned to
the bottom of the `EffectViewer` scene, plus an `EffectViewerPanel` living in
the F3 debug overlay for selection and play. In use it read as a *debug HUD*:
born on Play, cleared on Stop, cramped into the effect scene, watch-only. The
user's correction was categorical — **"this isn't really debugging, it's
development."** It is a workspace you *work in* (select an effect, scrub it
frame by frame, inspect a keyframe, author), not an observability readout you
glance at while something else is the task.

That categorisation is the durable half of this ADR. *Where* the tool lives
changed once, a day after it first shipped; *what it is* did not. The two
are easy to conflate now that the tool lives inside the debug window, which is
why the distinction is written down rather than left to the hosting.

## Decision

### Decision 3 — The Studio drives, but does not contain, the 3D preview

The effect renders in the primary window's stage. The Studio sends
transport and seek commands — `EffectInstance.seek()` and `set_paused()` — to
the one live parked instance there, and holds no `SubViewport` of its own. This is the audio-editor split — controls in the tool
surface, output in the stage — and it is the reason a second render target and a
second instance are not worth their cost.

It is the only original decision still standing, and the rehost in dec. 4 made
it *more* literal rather than less: the output is now in a different OS window
from the controls, not merely a different rect.

### Decision 4 — The Studio is a full-width page in the ADR-0035 dashboard window, built and injected by its host scene

The Studio (`EffectStudioPage`, with the transport, `EffectScoreTimeline`,
`EffectKeyframeInspector` and `EffectCurvePainter`) is a `Control` page in the F3
`DebugDashboard` — a peer of the masonry "Panels" and "Registry" pages, reached
through the header page switcher — not a window of its own. The host effect scene constructs it, binds itself as
host, and injects it:
`EffectViewerScene._setup_studio_page()` → `DebugOverlay.set_studio_page(page)`
→ `DebugDashboard.set_studio_page()`. `DebugOverlay.show_studio_page()` opens
the dashboard straight to it.

The route is one-way by design: the dashboard offers a slot and does not know
what fills it, so an effect scene is the only thing that decides a Studio page
should exist. The boot target you enter is therefore the effect scene
(`res://assets/scenes/EffectViewer.tscn`), which raises its own tool surface —
not a tool scene that raises a stage.

### Decision 5 — The content is Godot Controls; no embedded native surface

The whole surface is pure-GDScript Godot `Control`s. An embedded native UI
toolkit is disqualified regardless of whether it works, because the editor must
stay web/WASM-exportable — see the spike in `## Considered options`, which
passed and was declined anyway.

### Decision 6 — The page reaches its host only through `studio_*` verbs

Everything the page needs from the scene is a `studio_*` method on the bound
host, probed with `has_method` and called; the page holds no reference to the
scene's internals and no scene type. That keeps the page testable against any
host that answers the verbs, and it is what lets dec. 3 hold — the page cannot
reach into the stage even accidentally.

The verb set is not fixed and not small. It began as four transport verbs —
`studio_select_effect`, `studio_seek`, `studio_set_playing`,
`studio_current_frame`, which is still the list `EffectStudioPage`'s own header
documents — and is
the tool's entire authoring surface today (40 methods on `EffectViewerScene`:
save, texture import/export, edit/compound apply, undo, move begin/preview/end,
event insert/delete/paint/drag, colour add/delete/author, audition, and more).
A verb is added by adding it to the host; nothing enforces the set, which is the
cost of the duck-typing and is recorded as a proposed guard in `AUDIT.tsv`.

## Considered options

- **A masonry panel in the ADR-0035 dashboard** — rejected: the score plus a
  full transport plus a docked inspector do not fit a column-packed cell, and
  filing a development workspace under "debug" miscategorises it. Note the
  hosting this ADR settled on is a *page*, not a panel; the objection was to the
  cell, not to the window.
- **A standalone top-level `Window` plus its own boot scene `EffectStudio.tscn`
  owning both stage and window** — *(decs. 1–2, shipped 2026-07-13 at
  `c6b058015`, reversed the next day: the timeline `Control` was an opaque full
  rect and occluded the effect, which defeats the audio-editor split the tool
  exists for. `src/effects/studio/EffectStudio.tscn` was deleted at `086f871e4`,
  inside a commit about the SCREEN blend parameter.)*
- **An embedded JUCE surface for the content** — *(spiked to a pass and declined
  2026-07-13. `sandbox/juce-godot-embed/` took all four rungs: JUCE inits
  in-process, renders a `Component` to a `juce::Image` blitted to an
  `ImageTexture` with the `MessageManager` pumped from `_process`, input
  forwards, and a JUCE→GDScript callback fires. It was declined anyway — a
  native surface cannot export to web/WASM.)* imgui is out for the same reason.
- **A persistent in-scene strip** (keep the `CanvasLayer`, just make it stay) —
  rejected: it keeps fighting the effect scene for space and cannot host a real
  control suite.
- **A self-contained window with its own 3D `SubViewport`** — rejected: a second
  3D render target and a second `EffectInstance` for no gain; remote-driving the
  existing stage keeps one source of truth for playback.

## Consequences

- There is **one** debug/dev window, not two. This ADR is not an exception to
  ADR-0035 — it is the precedent ADR-0035 dec. 8 cites when it adds
  a fourth page, and "no tabs" survives as a rule about panel *categories*.
- The Studio and the primary window are coupled through the live
  `EffectInstance` playback API and dec. 6's verbs, never through UI.
- A future development tool follows this shape — a page in the one window,
  driving the game window — rather than minting a second window.

## Verification

- `src/effects/studio/` declares zero `SubViewport` across 116 scripts, which is
  dec. 3 as a one-line grep. It is not yet a guard; `AUDIT.tsv` proposes it.
- 87 `tests/EffectStudio*Test` suites drive the page through `bind_host` against
  the real `res://assets/scenes/EffectViewer.tscn`, so dec. 4's route and dec.
  6's verbs are exercised by every one of them.
- The tool's vocabulary is
  [`docs/context/16-effect-studio-authoring-tool.md`](../context/16-effect-studio-authoring-tool.md),
  which states this hosting too and is corrected alongside this ADR.
- `tools/check_path_extends.py` enforces ADR-0004's extends rule green. 21 of
  the 116 studio scripts declare a `class_name`; that is permitted — the rule
  bans a `class_name` on a script that is *extended by path*, not everywhere.
