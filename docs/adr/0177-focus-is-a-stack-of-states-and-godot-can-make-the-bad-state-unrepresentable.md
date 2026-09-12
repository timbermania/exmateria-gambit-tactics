# Focus is a STACK of states, and Godot can make the bad state unrepresentable

There is a set of states that may accept input; exactly one holds it; the assembler tier
manages the transitions. Focus is a **stack** — push to hand it down, pop to return it to
whatever was underneath — and it is enforced by `set_process_*input(false)` on every
non-holder, which stops **delivery** rather than action. Two channels, `game` and `debug`,
stay simultaneous.

Status: accepted (2026-08-26) — grilled with the user. **Supersedes ADR-0119 dec. 1's
`focus` row and dec. 5**, which disagree with each other. Owned by `src/core/Focus.gd`
(autoload, `platform`, the `Tune.gd` precedent). Anchored by `tools/check_focus_anchor.py`,
the mandatory code anchor ADR-0119's Consequences asked for and never got. Rescopes issue
#581.

## Context

ADR-0119 named `focus` one of four contested resources in 2026-08-20 and nothing implemented
it. That is the well-known half. Three things found by grilling it are not.

**ADR-0119 disagrees with itself about the shape.** Dec. 1's table gives focus the handoff
edge *"grant / return"* — a token held by a holder. Dec. 5 says something else: *"Focus is a
selector switch, not a router, a mask, or an on/off … Focus is a railway point: the train
goes where it is set, and the point never inspects the train."* A token you hold and a point
that routes are not the same model, and no code ever forced the question.

**The issue's stated blocker had expired.** #581 says *"`GPUArena._unhandled_input` tests raw
keycodes, not actions, which is why `_claim_pad` takes the pad wholesale … a Focus those
consumers do not honour buys nothing."* `_claim_pad`'s own comment says the same. It was true
at `7bb00cab0` (2026-08-21), where GPUArena matched `KEY_SPACE:`. It stopped being true at
`fae7f4c7f` the **same day** — ADR-0137 Amendment 2 made those two keys
`is_action_pressed("battle_start")` and `("battle_pause")`. Today GPUArena's handler holds a
takeover guard, **one** raw keycode (`Ctrl+R`, a dev arena reset), and two named actions. The
wholesale grab has been justified by an expired fact for five days, and the census disagrees
with the scope too: `WorldMapScene` and `TileCursor` have **zero** raw keycodes between them.

**Six mechanisms already answer this one question**, which is the real finding. A boolean
(`WorldMapScene._input_enabled` via `set_suspended`), a named-action list (`_ROSTER_ACTIONS`),
a wholesale grab (`_map_input_owned`), a predicate (`GPUArena._camera_is_taken_over()`), an
enum (`FormationDetailTransition.State`), and a nullable (`_screen_in != null`). Not one of
them knows about the others.

## Decision

### 1. The states are enumerated, and they are NESTED — so the model is a stack

The states that may accept input already exist, at four levels that do not know about each
other: `GameState.State` (8 modes), `FormationDetailTransition.State` × `Host` (5 × 2),
the world map's — which have **no enum at all**, being implicit in `_town != null`, the START
menu, the place list, travelling and suspended — and the battlefield's `camera_mode` /
`_camera_is_taken_over()` / `combat_active`. Plus one transient deaf state,
`screen_in_active()`: visible, deliberately not listening.

A flat selector cannot express those levels. **The console's model is a stack, twice over**
(`WORLD_MAP_SCREEN.md` §33.7): WLDCORE keeps a page stack at `0x800BB4F0`, and `WORLD.BIN`'s
own screens are stacked by a cooperative task system, *"slots of stride `0x400` … each nested
page takes the next slot down"*, whose waiting poll is literally *"is any of slots 3…8 still
alive?"*. Its rule — *"the world map has **two** ways to show another screen: push a page
mode, or call into `WORLD.BIN` and block"* — is the same two shapes the port has: a **mode
transition** (Campaign's) and a **host cue** (ADR-0174, `CONTEXT.md`). A host cue is what a
transition looks like; focus is what the state looks like.

The port already has the nesting whether the model admits it or not: `NavigatorMain` suspends
the map, runs Formation, restores. That is a hand-rolled push/pop, and it is exactly where
`set_suspended`'s rejected boolean lives.

### 2. Enforcement is `set_process_*input(false)`, and it gates DELIVERY

Measured with a probe driven through `get_viewport().push_input`, never by calling a callback
(ADR-0172's *Built* lesson):

```
all enabled     -> ["C", "B", "A"]
only B enabled  -> ["B"]            # A and C never receive it at all
A re-enabled    -> ["B", "A"]
```

So a non-holder is not asked to decline — it is **not called**. That is ADR-0119 dec. 2's
*"you cannot obtain two handles for one thing"* achieved with an engine primitive, and it is
a switch rather than a router or a mask, which is dec. 5's requirement met by the mechanism
instead of by discipline. `Control._gui_input` is a separate path and is untouched, so
text fields in the debug panels keep working.

### 3. Participants REGISTER a subtree root; the anchor proves the registry is complete

The runtime deafens registered roots other than the top of the stack. Registration is what
makes the state set **enumerable** — the stack prints — which is the property that is missing
today and the reason a whole-tree walk was rejected: a walk knows which nodes are currently
deaf, but it cannot say what the states *are*.

The hole in registration is the unregistered consumer, and that is closed by a **guard, not
by discipline**: `check_focus_anchor.py` asserts that every file defining an input callback
or polling the `Input` singleton is either registered or on a shrink-only allow-list. This is
the *mandatory code anchor* ADR-0119's Consequences demanded — *"one system polling the device
directly breaks the invariant for everyone, silently"* — and its absence is why focus was
*"a discipline, not a guarantee"*.

### 4. The allow-list is a RATCHET, and the conversion is staged

42 files carry an input surface today; 13 of them are effect-studio authoring tools. Landing
the mechanism and converting all 42 are not the same task, and pretending otherwise is how
this stayed unbuilt for six days. The guard grandfathers the current set and can only shrink,
so the surface cannot grow silently while the conversion proceeds file by file.

**Amendment 1 (2026-08-26) — the first staged conversion, and what it cost.**
`WorldMapStartMenu`, `WorldMapPlaceList` and `WorldMapTownPage` are participants now.
They had **no input callback at all**: `WorldMapScene._unhandled_input` dispatched to
them through `handle_input(event)` in an if-chain ordered by nullable precedence — a
hand-rolled focus stack, and the map's own comment already named the semantics
(*"record 4's `+0x20 = 1`: one level"*). Each window now pushes itself in `_ready` and
carries its own `_unhandled_input`, so the if-chain **is** the stack and the push order
of the openers **is** the precedence the chain encoded.

Three things this actually settled:

- **`held_direction()`'s three nullables are gone.** They were the same question as the
  `_input_enabled` boolean dec. 1 retired, asked three more times. An open window makes
  `Focus.holds(self)` false, which covers every case all four did. Removing them *before*
  the windows grew callbacks was a real regression and `WorldMapMountTest` caught it; the
  ordering constraint was the whole content of the "not yet" note this amendment replaces.
- **The grandfathered list did not shrink, and should not have.** `WorldMapScene.gd` stays
  listed because it POLLS, and dec. 4's asymmetry is exactly that a poll is not discharged
  by registering. What the conversion bought is three files that carry a new input surface
  and are *not* new debt: 4 discharged by registering, 29 grandfathered, unchanged.
- **A window can leave the tree inside its own input callback.** `handle_input` emits
  `cancelled`, whose handler is the opener's `_close_*`, which calls `remove_child(self)` —
  so `get_viewport()` is null on the way back out. It printed `SCRIPT ERROR` four times a
  run **while the suite stayed green**, because a script error is not an assertion failure.
  The viewport is now read before the dispatch. Anything else adopting this shape inherits
  the trap: the node you are running inside may be gone before the function returns.

**Amendment 2 (2026-08-26) — the POLL leg is done, and it needed four different shapes.**
Amendment 1 recorded that the grandfathered list did **not** shrink, because a poll is not
discharged by registering. That leg is now finished: `WorldMapScene`, `TileCursor`,
`PlayerCamera`, `ProjectileTester` and `ScenarioVM` no longer read the `Input` singleton, and
`check_focus_anchor` reports **0 POLL** where it reported 5. The list shrank by exactly one —
`WorldMapScene`, the only one of the five that also registers. The other four are still
unregistered callback consumers, which is dec. 4's schedule, not this leg.

The finding is that "remove the poll" is not one refactor. It was four:

- **A held VECTOR from events** (`WorldMapScene._held_dir`). This is the one that mattered
  beyond its own file: `held_direction()` had to test `Focus.holds(self)` by hand, and that
  branch — a branch on the flag this ADR exists to delete — survived Amendment 1 only because
  the poll underneath it forced the ask. Stop asking and the branch dies with it. The `_travel`
  gate stays and is now the only one, correctly: it is game state, not focus.
- **A held SET, in press order** (`TileCursor._held`, `PlayerCamera._pan_held`). `TileCursor`'s
  poll was also answering "which direction takes over when this one is released", and it
  answered it in `CURSOR_ACTIONS` **table** order in a machine whose whole rule is
  latest-press-wins. The list is the better answer, not just the poll-free one.
- **Nothing at all** (`ProjectileTester`). `InputEventMouseMotion` already carries
  `button_mask` — the button state at the moment the motion was generated. The poll was asking
  the singleton a frame later for something the event was holding.
- **The press itself** (`ScenarioVM`). `is_action_just_pressed` is an EDGE query, so there is
  no held state to track; it converts into an `_unhandled_input` callback, which is the thing
  it was emulating. Deliberately does **not** consume: the poll took the event off nobody, and
  adding a swallow under a refactor would silently stop a confirm other listeners see today.

**What a poll gets for free, and tracking has to be told.** Every one of these is a stuck
input with nothing in the log — the failure mode ADR-0119's Consequences name when they say
"one system polling the device directly breaks the invariant for everyone, silently."

- **The release that is never delivered.** Under Focus the map is deaf while a window is up,
  so the press cannot arrive *and neither can the release*. Delivery gates growth for free and
  cannot gate shrink; `WorldMapScene._on_focus_changed` clears on any transition it loses.
- **Alt-tab.** The key comes up while the window is unfocused and the release reaches nobody.
  `TileCursor` and `PlayerCamera` clear on `NOTIFICATION_WM_WINDOW_FOCUS_OUT`. `_input_allowed`
  and the TAKEOVER hand-off already covered the in-game cases; this is the one outside the game.
- **The rolled pad.** LEFT down, RIGHT down, LEFT up. A poll re-read both keys and the newer
  simply won; a tracked release must check which way the axis points before zeroing it.
- **The duplicate press.** An OS key-repeat past the echo filter must move-to-back, not append,
  or its single release leaves a copy behind and the cursor walks on its own.

**Two things about the instruments, both found by running them.**

- **The guard was scoring PROSE.** After `TileCursor` converted, `check_focus_anchor` still
  called it a poller — because the comment explaining the removal contains the string
  `Input.is_action_pressed`, and every conversion commit writes that phrase naturally. It now
  strips `#` comments (quote-aware). Verified over all 547 `.gd` files in the walk: exactly one
  verdict changes, and no file loses its `Focus.push` to the stripper.
- **The guard and the tests do not overlap, and neither is redundant.** Putting a real
  `Input.is_action_pressed` back into `PlayerCamera._execute_translation` leaves the new test
  arms GREEN — they observe the tracker, and the consumer's read is not reachable from them
  (`move_and_slide()` on a body in a floorless scene is not an observable). Only the guard
  catches it. The reverse also holds: the guard cannot see a missing alt-tab clear at all.

## Alternatives rejected

- **Grant/return handles (ADR-0119 dec. 1).** A handle answers *"may I?"*; it cannot answer
  *"who is underneath me?"*, so every caller would store its own predecessor — the **ledger**
  ADR-0084 warns against, and precisely what `NavigatorMain`'s save/restore of `_fade_rect`
  and `set_suspended` already is.
- **A flat selector (ADR-0119 dec. 5, read literally).** Same defect: `WorldMapScene` would
  have to know that Formation returns to *it*.
- **Whole-tree walk on transition.** Strictly stronger at runtime and leaves the state set
  implicit in the tree again; also needs a standing debug exemption and a `tree_entered` hook.
- **Build nothing; narrow `_claim_pad` and add the anchor only.** This was the recommendation
  the measurement supported and the user overruled it, correctly: the census shows the
  invariant is *nearly* held by accident, which makes a real switch cheap now, and "nearly"
  is the state ADR-0119 exists to end.
- **Convert all 42 files.** Not a decision, a schedule; see dec. 4.

## Consequences

- **`_claim_pad`'s wholesale grab loses its justification** and narrows to the named-action
  swallow it already uses on the ROSTER host. Its comment is corrected rather than deleted —
  the stale-within-a-day failure is worth keeping visible.
- **`set_suspended`'s `_input_enabled` boolean goes**, which is ADR-0119 dec. 5's named
  offender and the one ADR-0181 pointed at.
- **The stack is inspectable**, so "which state has input" stops being six questions.
- **ADR-0119 keeps decs. 2/3/4/6 and its through-line.** Only the `focus` row of dec. 1 and
  the whole of dec. 5 are superseded; the pump, the camera and the cell are untouched.
- **Not done here:** the 13 effect-studio tools, `OpeningMenu.gd`'s six raw keycodes, and
  whether `the camera` (dec. 1's second row) wants the same stack treatment — `_camera_is_
  taken_over()` is suspiciously the same shape.

**Amendment 3 (2026-09-09) — the BATTLEFIELD leg is scheduled, and skipping it cost four bugs.**

Decision 1 lists four levels of state that "do not know about each other" and the
fourth is *"the battlefield's — `camera_mode` / `_camera_is_taken_over()` /
`combat_active`."* Amendment 1 converted the world map's three windows. **The
battlefield was never converted**, and this amendment records what that cost and
what the conversion is.

**The measurement.** `NavigatorMain` pushes exactly one focus state — `"formation"`
(`:1105`) — and pops it (`:1115`). It never pushes a battle state at all.
`GambitBattle` pushes `"gambit_battle"` once (`:360`) and **never pops**. So the
battlefield is not in the stack in either host: in one it is absent, in the other it
is a push with no counterpart.

**The four bugs, reported at the keyboard on Orbonne 2026-09-08 while 745 of 757
tests were green.** Every one is a claim taken on entry and not returned:

| Report | The claim not returned |
| --- | --- |
| the map cursor and camera outlive the battle | `CursorRig`, the map-hosted Formation screen, `PlayerCamera.camera_mode` |
| survivors "snap" into scenario 6 | `clock_owner` — see ADR-0083 Amendment 2 |
| no stops on any turn | the steerable set — see ADR-0265 Amendment 1 |
| no cursor until combat starts | the cursor is mounted from a roster-fed-only branch |

`_go_live` is a real, named entry edge. There was no named counterpart, so nothing
had a place to return to — which is this ADR's thesis stated as a defect rather than
as a design.

**The conversion.** `_go_live` pushes `"battle"`; a handback edge pops it. Deployment
pushes `"deployment"` **on top of** `"battle"` rather than replacing it — one host,
one scene, but the stack shows which phase owns ○, which is what a stack is for and
why "deployment mode" and "a phase inside the battle host" are both true.

**What Focus does not carry, and must not be assumed to.** `set_process_*input(false)`
gates *delivery*. It does not free the cursor rig, return `camera_mode`, or flip a
clock. Those three ride the same push/pop edge but stay three named operations —
conflating "who gets keys" with "who owns the clock" is how the four bugs above
happened, and folding them into the focus primitive would repeat it one level up.

**Grandfathered-list effect: none yet.** Both hosts already register, so this leg
discharges no entries — dec. 4's asymmetry again. What it buys is the *stack*
becoming true of the battlefield, which is the property dec. 3 says registration
exists for.

**The instrument comes first.** Dec. 3 argues the stack's value is that it *prints*,
and `describe()`'s own docstring says it is "for the F3 panel" — a panel that was
never built. It is built before this conversion, and it shows one row per mechanism
(`NavigatorRunner.current_state`, the focus stack, `camera_mode` + takeover,
`combat_active` / `_pre_battle_active` / `survey_frozen`, the director's state and
steerable count, a clock-owner census, cursor and screen liveness). A panel showing
only the focus stack would have read `game: (nobody)` through all four bugs. The
point is not the stack — it is the **disagreement between rows**, which is decision
1's finding made visible.
