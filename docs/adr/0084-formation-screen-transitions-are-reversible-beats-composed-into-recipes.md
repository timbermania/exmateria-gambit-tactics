# Formation-screen transitions are reversible beats composed into recipes, played by one coordinator over a screen stack

**Status:** accepted (2026-08-08). **Amended 2026-08-19 (invariant 5, below):** the
stack is a **gate**, not a ledger — `enter()` is its only push and `_exit_settled()` its
only unwind, and re-entering the screen you are already on is a no-op. As first built,
the entry/exit *leaves* wrote the stack and nothing ever read it to decide, so a second
○ on the settled Status screen tore the overlay down, rebuilt it, and pushed `DETAIL`
twice — after which one Esc popped one and left the coordinator reporting a screen that
was no longer on the display. **Generalized by ADR-0088 (2026-08-11):** the
coordinator/beat model extends beyond the Formation screen to all of UI3 — a
registered element's `transition` criterion names a beat, its open/close is
`enter`/`leave`, and this ADR's boot-time reversibility audit covers registered
elements. "Element" here and ADR-0088's `UI3Element` are the same term.
Supersedes the ad-hoc per-path transition code in
`FormationDetailTransition` (six parallel hand-rolled steppers) and generalizes the
first-class-motion extractions of `4a2cc7f83` (entry slide) into one owner. Consumes,
does not reverse, the reversible primitives already built: `UnitInfoCluster.begin_slide`
(the shared vitals+nameplate pair, §15.1/§15.5), `DetailScene`'s `_TPhase` chrome
slide + `band_crossfade` (§15.6), the `SpriteSlideAnimator` roster slide, and
`ChangeJobWheel` (§15.24 RE28–RE32).

## Context

The Formation screen has a family of transitions — ○-press Status, START→Item→Equip,
START→Ability, START→Change-Job — that all move the same shared pieces (the top-chrome
vitals+nameplate pair, the roster grid, the dark bands, the lower panel, the job ring)
between resting arrangements. Each was built as its own path: entry code, and a
*separately written* exit. Exits kept getting forgotten or diverging — Esc from Equip
`queue_free`d the overlay with no reverse animation (a teleport), while ○-press Status
animated its close. The motion is smeared across five objects (`FormationScene`,
`DetailScene`, `UnitInfoCluster`, `ChangeJobWheel`, the host coordinator), and the host's
`_process` ran **six parallel hand-rolled state machines**, each with its own `_active`
flag + tick accumulator + `_step` function. Adding a screen meant a seventh machine and
its own forgettable exit. "Undoing is a whole re-implementation" was the author feeling
this weld directly.

The recurring bug class — a transition direction with no routine, silently degrading to a
snap — is the tell that the choreography wants **one owner with explicit states and legal
transitions**, not a method-per-direction.

Design constraints the RE fixes in place:
- **Entry and exit must be the same motion reversed.** A separately-authored exit is the
  bug. This includes asymmetric cases: the Change-Job *exit* is a distinct
  spin-and-enlarge fling (`begin_changejob_exit`, `EXIT_DURATION`), **not** the entry
  contraction run backward (§15.24 RE32) — so "reverse" is a first-class per-beat
  concept, not a naive frame-flip.
- **Menu-tick paced with a `_MAX_CATCHUP` delta clamp.** A stall / `render_unfocused`
  throttle must not collapse a slide into one visible frame.
- **The band cross-fade is a two-scene handshake.** `DetailScene` owns its top stripe
  (`formation_band_factor()`); `FormationScene` owns the bottom band (`set_band_fade`).
  Neither collapses into one node.
- **Screens nest.** Confirm-Job opens *from* Change-Job; Esc there must pop one layer
  back to the wheel, not unwind all the way to the roster.
- **Elements flow between groupings.** The selected unit is a roster member in the docked
  state but breaks out to centre in Equip/Change-Job while its rowmates slide off.

Dependencies are all in-process (Godot nodes, in-memory) — no ports/adapters; the
coordinator is tested by driving its interface and asserting intermediate frames.

## Decision

Model every Formation-screen transition as **reversible beats composed into recipes,
played by one deep coordinator over a screen stack.** Five layers, one orthogonal axis:

- **element** — a persistent node that owns its own transform *and its own keyframes*.
  A transition **never reparents an element** (invariant below).
- **assembly** — *coordinated motion, not ownership.* A permanent container node (e.g.
  `UnitInfoCluster` binding vitals+nameplate) is allowed **only** for elements that
  provably always move together. Otherwise "assembly" is just the set a beat addresses.
- **beat** — one reversible move of its targets between two keyframes. A beat **selects
  its targets by role/predicate** ("the selected unit" vs "the rest"), never by a frozen
  node list. Each beat declares its own forward driver, its own reverse driver, its own
  duration, and its own tick cadence. Reverse is a distinct driver (Change-Job's exit
  fling ≠ entry contraction reversed), defaulting to `forward(duration − n)` only when
  the motion is genuinely symmetric.
- **recipe** (the "meta-assembly") — one screen transition, expressed as a **sequence of
  groups**, each group a set of beats that run **concurrently**; groups run in order with
  a barrier between them. `CHANGE_JOB = [[chrome], [roster_split, ring_build], [title]]`.
  Composition is **flat** — recipes never contain recipes.
- **coordinator** — the deep module. Public seam: `enter(state)` / `leave()` + a
  `settled(to)` signal + `current_state()`/`is_moving()` for input routing. It plays a
  recipe's groups forward on `enter`, the same groups reversed on `leave`, and owns the
  one `_process` accumulator + the `_MAX_CATCHUP` clamp.
- **stack** (orthogonal, temporal) — the coordinator holds a stack of live recipes, and
  it is a **gate**: `enter(state)` consults it before doing anything, so a request for the
  screen you are already on is refused rather than replayed. It has exactly two writers —
  `enter()` pushes the screen it accepts, `_exit_settled()` applies the unwind when a
  reverse animation rests — and **no beat, recipe, or entry/exit leaf may write it.**
  Leaves play animations; the coordinator decides. This is the *only* nesting mechanism;
  recipe composition is spatial/flat, navigation nesting is the stack.

  Two consequences worth stating, because both were learned the hard way:

  - **Which unwind is per-screen, and it is not always one layer.** The `DETAIL` close
    pops exactly one; a sub-screen back-out (Equip/Ability/Change-Job) is a **full unwind
    to the roster** (RE25 — FFT's own Esc returns to the plain roster, not to the Status
    screen underneath). That rule lives in `_exit_settled()` alone, so no teardown gets a
    vote on it. The original wording here — "`leave` pops one layer" — described the LIFO
    mechanism, not the shipped per-screen behavior; this is the correction.
  - **Push at entry start, unwind at exit settle.** A screen is occupied the moment you
    begin entering it and vacated only once you are fully out, so `current_state()` never
    names a screen that is still on its way off — which is what lets the gate hold
    mid-flight rather than only at rest.

  The corollary for routing: **every door onto a screen goes through `enter()`, and every
  door off one through `leave()`** — the coordinator's own dispatch, both menus, the
  roster's ○, and each △/Esc branch alike. A path that reaches an entry leaf directly
  bypasses the gate, which is exactly how the double-○ bug existed.

  And its twin, on the input side: **a screen that is up owns the whole pad.** The roster
  grid does not know when it is covered, so any press the open screen declines to act on
  must still be swallowed by the host rather than fall through to
  `FormationScene._unhandled_input`. Left leaking, ○ on the Change-Job wheel came back as
  `unit_activated` — a DETAIL enter stacked on CHANGE_JOB, which the gate cannot refuse
  because the two states differ — while ↑/↓ moved the hidden selection and L2/R2 re-paged
  the sort behind the ring. What is swallowed is the roster's **named action set**, not
  every event, so the mouse and the F3 debug panels keep working over an open screen.

**Membership is derived, never mutated.** A beat asks "who is my target?" per play and
the role predicate answers; the selected unit is never *moved* from one assembly's list
to another's. This is what makes element-flow free and gap-proof: there is no stored
membership to forget to restore on exit (a mutated membership would resurrect the exact
forgotten-exit bug).

**Transitions are explicit frame-stepped state machines, not `await` coroutines.**
Position is a pure function of frame, so the coordinator can drive any beat `N→0`
(reversibility), honor the menu-tick cadence and `_MAX_CATCHUP` clamp (one explicit
delta accumulator), and be single-stepped by guards. `await`/coroutines are rejected:
they cannot run backward, give one step per rendered frame regardless of delta (the
throttle-collapse teleport), and cannot be hand-driven in a test.

### Invariants (mechanized as guards)

1. **Reversibility is total.** Every recipe `enter` accepts is exitable by replaying its
   groups reversed. There is no separately-authored exit and no instant-teardown path
   that skips the beats. A beat lacking a reverse driver fails a boot-time recipe audit
   (in CI), not at the user's first Esc.
2. **Gaps are observable.** `enter(state)` on a state with no recipe asserts / returns
   false and does not move the chrome — visibly stuck, never a silent snap.
3. **Beats never reparent.** Membership is derived by role; an element is a persistent
   node addressed by whichever beat is active.
4. **No element is driven by two positional beats simultaneously.** Concurrent beats in a
   group must target disjoint element sets. (If a future RE finding shows a genuinely
   *blended* motion — one element driven by two contributions at once — it is added as a
   compositional transform on that element, contained because elements own their
   transform; until then this fires loudly.)
5. **The stack is a gate with two writers.** `enter(state)` where `state` is already
   `current_state()` is a **no-op** — no teardown, no rebuild, no second push, no
   animation started. Only `enter()` pushes and only `_exit_settled()` unwinds; every
   other function treats `_stack` as read-only. The guard presses the same screen twice
   from both doors, because they differ: at the seam (`enter(state)` twice, for DETAIL,
   EQUIP **and** CHANGE_JOB — all three duplicated before the amendment) and through the
   **real viewport** (`get_viewport().push_input`), since the roster's ○ arrives via
   `FormationScene.unit_activated`. A guard that calls `_unhandled_input` directly cannot
   see this class of bug and will pass against it.
6. **An open screen consumes the roster's action set.** While `current_state() != IDLE`, no
   press in that set reaches the covered grid — whether a branch acted on it or declined.
   The settled DETAIL screen therefore needs its own △ branch (it previously closed *via*
   the leak, through `FormationScene.dismissed`), and the Change-Job wheel claims ○ as its
   job **commit** rather than letting it through. Guarded by pressing ↑/↓ and ○ on the
   wheel through the real viewport and asserting the roster's `selected_cell` and the stack
   are both untouched.

## Consequences

- The host's six parallel steppers, the duplicated `_MAX_CATCHUP` clamps, and the
  separately-authored exits (`_exit_equip_to_main_menu`'s teleport, `_teardown_changejob`,
  `close_detail`'s reverse) collapse into `enter`/`leave` over the coordinator. The
  Esc-teleport bug becomes *unrepresentable*, not fixed — there is no free-and-snap path.
- Adding a screen (Confirm-Job, the L1/R1 pager re-slide) is a new state + one recipe row
  composed from existing beats, plus at most one new beat adapter — no new `_process`
  machine, no new exit path.
- The Change-Job asymmetric exit is modeled honestly: the ring beat carries a distinct
  reverse driver (`begin_changejob_exit`/`EXIT_DURATION`), so "reverse a recipe" does not
  assume symmetric beats.
- Locality: "how the chrome raises/lowers" lives in one coordinator; "what this screen
  moves" is that screen's recipe; you read a transition without tracing five objects.
- Cost: the beat/recipe machinery is more structure than four screens strictly need
  today. It is justified by the stated growth (more nested screens) and by eliminating a
  whole bug class. The bet is that FFT's menu transitions stay **flat recipes + a LIFO
  stack** (no arbitrary screen↔screen jumps); if RE ever shows a non-LIFO jump, the
  stack generalizes to a transition graph behind the same `enter`/`leave` seam — a
  contained change, not a redesign.
- Steady-state interaction stays **out** of the engine: the Change-Job ring rotation
  (←/→) and Confirm-Job's live cursor are not entry/exit choreography and remain their
  own small handlers. The coordinator owns only the reversible enter/exit envelope.

  **Amendment (2026-08-20) — self-clocked in-place cutscenes are out too.** The RE of the
  Change-Job COMMIT (`research/working_documents/CHANGE_JOB_COMMIT.md`) turned up a beat
  this clause did not obviously cover: a **240-frame (4.00 s) animation that pushes no
  screen, pops none, and applies its effect on the final frame**. It is not steady-state
  interaction — it is choreography, with four concurrent mechanisms — yet it is not an
  entry/exit envelope either, and invariant 1 cannot hold for it: the only reverse driver
  a "commit" beat could have would have to **un-commit a job**, which the ROM has no
  notion of. So the rule generalizes: **the coordinator owns transitions BETWEEN screens;
  an animation that begins and ends on the same screen belongs to that screen**, however
  long or elaborate. `ChangeJobCommitCutscene` is the first of these — a pure
  frame-indexed model beside the screen, with its own clock (the ROM ticks it per VSYNC,
  not on the ~30 Hz menu tick), driven by the host the same way the ring rotation is.

  The test that separates the two cases is not duration and not complexity: it is
  **whether `leave()` could ever have to play it backwards**. If yes it is a beat; if the
  motion is irreversible by nature, forcing it into a recipe would either weaken
  invariant 1 for every recipe or produce a reverse driver that lies.

## Verification

Guard at the coordinator seam (one owner, one test): `enter(EQUIP)` drives the cluster
through intermediate frames (not a snap) and the band cross-fade forward; `leave()`
reverses both and pops the stack; a round-trip per screen asserts the world is
byte-restored to the docked baseline; a boot-time audit asserts every recipe is fully
reversible; and a redundant `enter` — at the seam and through the viewport — leaves the
stack, the overlay instance and `is_moving()` untouched, with one Esc afterwards landing
back on `IDLE` with an empty stack (invariant 5). Oracle: confirm the Change-Job exit fling on
`reference-assets/formation_changejob_source.sstate` (pcsx `:8080`) is the RE32
spin-and-enlarge, distinct from the entry contraction — the asymmetry invariant 1 must
model.
