# Debug UI is a separate OS window with a dashboard grid, not an in-viewport overlay

The debug UI lived as an in-viewport `CanvasLayer` (`DebugOverlay`) with a `TabBar` and ~20
panels routed into 11 tabs. F3 toggled the overlay; tabs selected one category's panel set
at a time; each panel internally used `BaseDebugPanel.create_collapsible_section` to fold
groups of controls.

The shape was wrong on four independent axes for an actively-iterated project:

1. **Tabs hide settings behind navigation.** Eleven categories meant reaching any one
   control required first remembering its category, then clicking that tab — friction with
   no compensating benefit for an author iterating across categories every minute.
2. **Collapsible sections hide settings inside the active tab.** "Where is that slider?"
   became "which tab AND which collapsible?" — two layers of navigation for what is
   conceptually one workbench.
3. **The overlay overlapped the thing it was meant to debug.** A `CanvasLayer` floats above
   the game viewport by construction. The `scale = 0.65` shrink was a partial compensation
   for PSX viewport real-estate (768×720) but did not change the topology — the panel sat
   *on top of* the unit / map / particle being tuned, so toggling off to see the change and
   back on to adjust the next slider was the only workflow that worked. That inverts the
   value of a "live tuning" surface.
4. **One CanvasLayer + one viewport ties the debug surface to game focus.** Keyboard focus
   is shared with the game window, so a focused number field eats `WASD`; clearing it
   requires the `ESC`-clears-focus shim in `BaseDebugPanel._gui_input`.

None of (1)–(4) is fixable inside the in-viewport overlay shape — they are properties of
"tabbed `CanvasLayer` floating over the game viewport."

## Status

Accepted (2026-06-10). Verified 2026-08-28 — decs. 1 and 3–8 built. **Decision 2 is
unresolved**: the shipped dashboard grew an opt-in, persisted per-category cell collapse
that no decision sanctions, and whether that is a fifth exception or a drift back toward
problem (1) is an open product call (#686).

## Decision

`DebugOverlay` is a thin manager whose `_dashboard` field is a `DebugDashboard` — a
top-level `Window` node that pops out as a real OS-level window separate from the game
viewport, with all categories' panels visible at once in a single dashboard grid.

1. **Separate OS window, not a `CanvasLayer`.** The dashboard is a `Window` node;
   `display/window/subwindows/embed_subwindows = false` in `project.godot` makes Godot 4
   render it as a true OS window. The user drags it to a different monitor (or tiles it in
   their WM) and it no longer overlaps the game viewport. Keyboard focus follows the OS
   window, so the game receives `WASD` regardless of what is focused in the dashboard.
2. **Dashboard masonry replaces the tab bar.** A `ScrollContainer` →
   `DebugMasonryContainer` (Pinterest-style packing). Column width is **the widest visible
   cell, clamped into `[min_column_width, max_column_width]`** so a wide cell never spills
   sideways into its neighbour; the column count then follows from how many such columns
   fit. Each cell drops into the shortest column at the moment of placement — that packing
   is why a grid was rejected: rows top-align their cells, leaving dead vertical space below
   short ones. One cell per `Category`; each cell is a `VBoxContainer` with a title label
   followed by the panels `register_panel(panel, category)` routes there. Empty cells are
   hidden. Every category is visible simultaneously, and when the assembled content exceeds
   the window height the whole dashboard scrolls as one page — not the cells.
3. **Collapsible sections collapse, lists stay lists.**
   `BaseDebugPanel.create_collapsible_section(parent, title, start_open)` is a **plain
   titled section** (bold label + `VBoxContainer`, no toggle, no folded state); the third
   parameter is kept in the signature as a no-op — it is literally `_start_open`, unread —
   so its call sites compile unchanged. *Naturally-long list controls* (the scenario picker,
   sprite browser, any future ItemList-shaped browser) are deliberately not flattened: they
   were always a scrollable list, not a foldable section, and a 490-row scenario list cannot
   "be flat."
4. **F3 toggles the dashboard; position, size and visibility persist.** First press lazily
   instantiates the `Window` at the position/size saved in `UserSettings.debug_window`.
   Subsequent presses toggle visibility. The window's `close_requested` calls back into
   `DebugOverlay.hide_overlay()`. Move, resize and close write back to
   `UserSettings.debug_window`, and `was_visible` is part of that layout — `_ready`
   restores it into `DebugConfig.debug_overlay_visible`, so the dashboard reopens at launch
   **iff** it was open when the game last quit. The first-run default is
   closed (`DEFAULT_DEBUG_WINDOW`): a fresh checkout starts with no debug UI, and it can
   only appear unasked if you left it open yourself.
5. **Public API preserved.** `register_panel(panel, category)`, `switch_to_tab(category)`,
   `show_overlay()`, `hide_overlay()`, `toggle_overlay()` keep their signatures. The
   boot-site calls in `GPUArena.gd`, `EffectViewerScene.gd`, `TrapViewerScene.gd`,
   `UnitAnimationViewerScene.gd`, `ProgressionTester.gd`, `MapComposer.gd`,
   `CombatUITestScene.gd` continue to work without edits — the rule names the files, not
   their paths, which is why `MapComposer.gd` moving into
   `addons/exmateria_battlefield/assembly/` costs nothing. `switch_to_tab` becomes a
   scroll-to-cell (it has scene-launch semantics in three callers — "open the dashboard
   already showing the right category").
6. **A calibration panel whose rows outnumber what a cell can usefully show flat MAY group
   them into real collapsible sections** — one fold per *target game panel* (stats band,
   equip picker, …), via `BaseDebugPanel.add_fold_section(parent, title, start_open)`,
   folded by default so the section titles read as a table of contents.

   Decision 3's flatten rule was written against the old tabbed overlay, where a dozen
   controls hid behind *two* navigation layers and unfolding everything made each panel
   scannable at a glance. It assumed panels stay roughly that size.
   `DetailScreenDebugPanel` broke the assumption: live placement calibration for the
   Detail/Status screen plus the equip picker grew it past 40 rows (heading toward 80 as
   every element becomes tunable, ADR-0068). Flat, it is a wall of look-alike SpinBox rows
   where "which knobs drive which game panel?" has no visual answer — the exact "where is
   that slider?" failure decision 3 was meant to retire, now caused *by* flatness instead of
   by folding. This is an exception inside one panel's own body, not a return of tabs:
   `create_collapsible_section` stays flat for the small panels where decision 3's reasoning
   still holds, and the dashboard itself stays a single scrolling masonry page.
7. **Inside a category cell, each registered panel mounts under its own titled fold.**
   `DebugDashboard.add_panel` originally stacked panels into a cell with no per-panel title,
   so a cell holding several (Designer in the formation scene: Formation Placement + Detail
   / Status Screen + Vitals Layout) read as one untitled blob — the user could see "the
   designer panel" but not "the debug panels for all the panels". Each panel now mounts
   inside a fold header showing its `panel_title`. A cell's **only** panel starts open —
   nothing to disambiguate, and a lone list-shaped panel keeps its list visible, preserving
   decision 3's "lists stay lists"; when a second panel registers into the cell, its folds
   collapse to the table-of-contents state. Everything remains one scrolling page, and a
   fold is a disclosure within it.
8. **A whole dev *surface* may take a dashboard page; a category of panels may not.** This
   is the sanctioned exception to "no tabs", and it is scoped by what a page hosts. The
   dashboard carries four: **Panels** (the masonry), **Registry**, **Studio** (ADR-0069's
   Effect Studio host, mounted through `set_studio_page` — the precedent) and **UI3** — a tree mirroring the live registered
   element hierarchy from ADR-0088's registry, screens at the root, elements nested as
   registered, each node unfolding to its criteria rows (rect spinboxes, enum dropdowns,
   resolved inherited values, dirty/pin state), **generated from the registry, never
   hand-authored**. That tree is navigation the masonry cell cannot express past ~40 rows —
   the same overflow that forced decision 6 — and it live-follows the running scene. As
   elements register, `DetailScreenDebugPanel`'s hand-built rows are superseded by the
   generated page and the panel shrinks to whatever legacy remains unregistered; decision
   6's folds stay for that interim.

## Considered options

- **Separate OS window with dashboard grid (chosen).** Solves (1)–(4) in one move: no tabs
  (everything visible), grid scrolls as one page (no per-cell hiding), separate OS window (no
  game overlap), OS-level focus (no shared-focus shim). Costs: a rewrite of `DebugOverlay.gd`
  and one project setting flip. The `embed_subwindows = false` flip is global, so any other
  `Window` popup in the project also becomes a real OS window — acceptable because the
  project doesn't otherwise use `Window` (no `FileDialog`, no `AcceptDialog`; UI is
  custom-drawn through `ui3/`).
- **Multiple tear-off `Window`s, one per category** (Unity/Unreal inspector style). Solves
  (1)–(4) more aggressively but rejects the user's stated "BIG window" framing and forces
  managing eleven windows. The dashboard achieves the same "everything visible" goal with one
  window to position once.
- **Keep the `CanvasLayer` overlay, expand collapsibles, add a hotkey to cycle tabs.**
  Cheapest change; addresses (2) and partially (1). Leaves (3) and (4) — the overlap and the
  shared focus — exactly as they were, and most of the friction the rewrite retires lives in
  (3).
- **`CanvasLayer` overlay coexists with a new BIG `Window`.** Every panel wires to two
  parents; the two surfaces drift; maintenance compounds. Retiring one debug surface is part
  of the value.
- **Always-open dashboard at game launch.** Pops the `Window` on every start. Rejected: a
  non-dev playthrough — testing a feature end-to-end, recording a clip, or just playing —
  shouldn't open a debug UI. Decision 4's persisted `was_visible` is not this option: the
  first-run default is closed, so the dashboard never appears on a start where the user did
  not leave it open.

## Consequences

- **Dev workflow.** Iterate on a slider in the dashboard, see the change in the unobstructed
  game viewport on the other monitor; no panel-hide-reshow cycle. Categories the user reaches
  together (shader calibration + camera) are visible at the same time, not one tab apart.
- **`project.godot` becomes the home of one new global concern.** Any future `Window` node in
  this project renders as a real OS window. Reversible — flip the setting back — but it
  changes the default contract for the type.
- **`switch_to_tab(category)` is a scroll, not a state change.** The three scene-boot callers
  (`TrapViewerScene`, `EffectViewerScene`, `GPUArena.gd` for the strategy phase) want "open
  the dashboard with this category in view"; `_dashboard.scroll_to_category(category)`
  delivers that.
- **`BaseDebugPanel._gui_input` and the `ESC`-clears-focus shim are obsolete in the dashboard
  path.** Mouse and key events go to the focused OS window. The code is left as a harmless
  no-op rather than ripped out, because the same panels can still be hosted by ad-hoc viewers
  (UnitAnimationViewer, TrapViewer) that may or may not route through the dashboard.
- **Lists are first-class.** Decision 3's flatten rule explicitly does not apply to
  inherently list-shaped controls; future browser panels (scenario / sprite / ability) keep
  their scroll affordance. `CONTEXT.md` gains no new term — the dashboard is dev tooling, not
  domain language.
- **The category count doubled, and the cell learned to fold.** `Category` has grown from the
  eleven the Context enumerates to **22**, and its name list is still called `TAB_NAMES` — a
  noun this ADR retired. Twenty-two simultaneously-visible cells is a different surface from
  eleven, and `DebugDashboard.set_category_collapsed(category, collapsed)` now hides a cell's
  content behind a `▶`/`▼` button, persisted as `UserSettings.debug_window.collapsed_categories`
  and restored on boot. **No decision sanctions that.** Decision 6 is scoped inside one
  panel's body, decision 7 to panels within a cell, decision 8 to whole surfaces; folding an
  entire category cell is a fourth fold layer and the closest thing in the tree to problem
  (1), differing in that it is opt-in and persistent rather than exclusive. Whether it is a
  sanctioned fifth exception or a drift is open — see Verification.

## Verification

- **Decision 2's open question (#686).** Two readings are defensible from the code and this
  ADR chooses neither. *A fifth exception:* the masonry still scrolls as one page and a
  collapsed cell is a disclosure within it, which is exactly decision 8's defence of pages.
  *A drift:* it reintroduces "reaching a control means first un-hiding its category", which is
  problem (1) with a persisted rather than exclusive selector. What is certain is that no
  decision says, and that the enum doubling is the visible cause.
- **`tests/UI3RegistryPageTest.gd`** pins decision 8's fourth page — "DebugDashboard grows a
  4th page 'UI3' hosting the view" — and that the view is generated from the registry
  (`UI3RegistryView`), rebuilding on register/unregister while visible.
- **Decision 6 held its scope.** `add_fold_section` has exactly **one** consumer panel,
  `DetailScreenDebugPanel`, the panel it was written for, while
  `create_collapsible_section` serves 38 flat call sites.
- **Decision 3's no-op is real, not nominal.** The parameter is `_start_open` —
  underscore-prefixed and unread — so a caller passing `false` gets a flat section, which is
  the compile-unchanged promise rather than a silently honoured toggle.
- **No automated guard covers decisions 1, 2, 4 or 5.** The window-vs-CanvasLayer topology,
  the masonry sizing rule, the persistence round-trip and the five API signatures are all
  verified by reading. A boot-site smoke arm over the seven named scenes would be the
  cheapest thing to add.
