# The map fades out on the ROM's own out-curve, and the call site is not claimed

Leaving the world map for Mandalia Plains cut to black in one frame. The screen faded
*in* — ADR-0161 built that, ADR-0174 measured it — and then vanished instantly on the way
out, which reads as harsh precisely *because* the entrance is a ramp: the player has just
been shown that this screen knows how to dissolve.

The reason it was missing is an ownership rule, not an oversight. ADR-0172 draws the line
that a **scene-out is chunk-authored and belongs to Cutscene**, while a **screen-in belongs
to the screen's own system** — so the map built the half it owned and nothing authored the
other half for the hand-off to a battle.

## Status

Accepted, built. Verified 2026-08-28 — decisions 1–7 all built. Owned by
`src/world_map/WorldMapScreenOut.gd` (the curve and the constants) and
`WorldMapScene._run_screen_out` (the firing), armed by `WorldMapScene._leave`. Neighbours
ADR-0174 (which measured the out arm this runs), ADR-0172 (whose ownership rule this
applies to a third case rather than superseding), ADR-0161 (the world map's screen-in) and
ADR-0176 (which books `src/world_map/` as `UI`). Adds **Screen-out** to `CONTEXT.md`.

## Decision

1. **The map runs a SCREEN-OUT on the ROM's measured out-curve.** ADR-0174 §2 read
   `FUN_80069400(kind, len)` as ONE routine with TWO arms, bit 1 of `kind` selecting
   direction, and tabulated both. The out arm is not the in arm reversed:

   | | descriptor `0x800D0ADC..DE` |
   |---|---|
   | **out** (`kind & 2`) | `counter*256/len + 32`, ceil `0xFF` |
   | **in** (`!(kind & 2)`) | `0xC0 - counter*256/len`, floor 0 |

   It opens at **32** and saturates at **255**; the in arm opens at 192 and saturates at 0.
   A reversed in arm would open at 0 — a cut, which is the defect — and close at 192, which
   is level 24 of 31 and is *not black*. Both endpoints are wrong in a reversal, in opposite
   directions, which is why `WorldMapScreenOut` restates the formula instead of running
   `WorldMapScreenIn` backwards. ADR-0161 §4's refusal to share a kernel with `{3E}` was
   vindicated by measurement; this is the same refusal for the same reason, one file over.
   The arithmetic is integer, as the console's `div` is, and every value bakes to a whole
   5-bit level before the blend — `CEIL_VALUE` 255 bakes down to 248, which is level 31 and
   is full black. The picture lands at tick 14, two before the 16-tick latch;
   `land_tick()` derives it rather than hardcoding it.

2. **The CALL SITE is not claimed, and that is the whole reason there is a tunable.**
   ADR-0174 read the map's *entry* cue — `0x8006731C`, `FUN_80069400(0, 0x10)`, direction in,
   len 16 — and nothing about the exit. Nothing in the tree establishes that the console
   fires the out arm when the map hands off. The `&2` guard means firing the direction you
   are already in is a no-op, so an unconditional exit fire would be *harmless*; harmless is
   not evidence. So: the CURVE is a fidelity claim and the FIRING is a product choice, and
   `world_map.screen_out` is the seam between them. If someone reads the exit path and finds
   the call site, the switch stops being interesting and the docstring saying so should go.

3. **The tunable's home is `WorldMapScreenOut`, not `WorldMapScene`.** ADR-0068 wants the
   value on its production owner with the panel as a pure view. The owner is the mechanism
   the switch disables. It also *cannot* be the scene: `WorldMapScene` is a declared root's
   assembler, and `tools/check_root_set.py` check 4 requires that nothing CALLS an
   assembler — a panel naming a `const` on it is a call, and the guard reds on it. That was
   found by running the guard, not by reading the rule. The class registers the slug from
   its own `_static_init`, which `tools/check_tune_owner_self_registration.py` keeps it
   doing.

4. **The scrub is a WRITE-BACK (R3), not a pull (R5).** Reading `Tune.get_value` inside
   `_leave` is legal and was the first shape, but a slug consulted only when an *event* fires
   has no consumer in the window between the scrub and the event — so the R8 guard printed
   *"scrubbed but nothing consumed it"* every time the checkbox moved, and the only way to
   silence it was to leave the map. An `on_update` write-back lands the scrub on live state
   immediately. R8 was right and the first design was wrong. The write-back lands on
   `WorldMapScene._screen_out_enabled` and is deliberately not mirrored back onto the
   `static var`: a static is process-global, so mirroring would leak this visit's setting
   into every later mount and stop the member being a *default*. The static var is the
   AUTHORED value; the instance var is the LIVE one.

5. **`dismissed` waits for the fade, and the wait is bounded in PROGRESS.** The host awaits
   that signal to tear the screen down, so emitting it before the ramp finishes would black
   nothing out. `_leave` is therefore a coroutine, with a `_leaving` re-entrancy guard (✕
   pressed twice must not start two fades) and a deadlock bound, because a host that
   suspends the screen mid-leave would otherwise hang the navigator's `await` forever — and
   a hang reads as "nothing happened", not as an error. Three things make that bound
   correct, and each is a statement the obvious shape gets wrong:

   - **The unit is frames that made NO PROGRESS, not elapsed frames.** A waiter resumes once
     per *rendered* frame while the ramp advances once per *vsync* at `VSYNC_HZ` (60), so a
     display at R Hz spends `RAMP_TICKS * R/60` frames on a perfectly healthy fade. A flat
     `RAMP_TICKS * k` has a margin that shrinks as the machine gets faster and inverts around
     480 fps, where the guard fires **on success** and truncates the fade — the one failure
     mode a deadlock guard is least allowed to have. Frames-without-progress has no crossover
     at any refresh: a live ramp advances at least once every `ceil(R/60)` frames, so the
     bound can only expire when nothing is ticking the ramp at all.
     `WorldMapScreenOut.STALL_FRAMES` (240 — four seconds at 60 Hz, ~1.7 s at the 143.9 Hz
     measured on this machine, large on purpose because expiring early is a bug that only
     appears on someone else's monitor) is the one spelling, and
     `WorldMapScene.screen_out_ticks()` is the progress reading, so a waiter outside the
     scene bounds itself the same way.
   - **The bound guards a stall, never a free.** `_run_screen_out` checks `is_inside_tree()`
     on *both* sides of its `await`, because `get_tree()` is null the instant the node leaves
     the tree.
   - **`_leaving` is a ONE-WAY latch, because the screen is single-use.**
     `NavigatorMain.run_world_map` instantiates a fresh scene per visit and `queue_free`s the layer when
     `dismissed` releases, so the next visit gets a fresh `false`. The only place a reset
     could sit is after `dismissed.emit()`, where re-arming buys a second emit of a signal
     the host has already acted on — exactly the double-fire the guard exists to stop. If
     this scene is ever re-mounted rather than rebuilt, that is the line to revisit: a
     re-mounted instance would be permanently un-leavable.

   `screen_out_ticks()` answers PROGRESS only and returns 0 when there is no ramp. "Is there
   a ramp at all" is `screen_out_active()`'s question, and "is there a quad to fade"
   is `has_screen_quad()`'s.

6. **Skipped while capturing.** `_capture` calls `set_process(false)` to freeze the vsync
   clock, and this ramp is ticked *from* that clock, so a fade started under a capture would
   never advance. Same `capture_path` gate the music uses, for the same reason.

7. **A screen-OUT belongs to the SCREEN, and `CONTEXT.md` says so.** ADR-0172 §1's
   discriminator is not DIRECTION, it is authorship: *a scene-out is authored per-scenario in
   the chunk, so it varies beat by beat; a screen-in is unconditional and belongs to the
   screen's own code.* A screen-out is unconditional and lives in the screen's own file, so
   it falls on the same side of that line as a screen-in — and §1's own supporting quote is
   `UI`'s charter row, *"the open **and close** cadence"*, which names the close explicitly.
   So **ADR-0172 is not superseded and not amended**: it is applied to a third case it did
   not enumerate. `src/world_map/` is booked `UI` by ADR-0176, and `WorldMapScreenOut` sits
   there.

   The vocabulary carried a real collision, narrower than it looks. `CONTEXT.md`'s **Host
   cue** entry warned against calling *the host cue* a screen-out — the host cue is the
   *host's*, fires on both sides of running another screen, and its body is in the `WLDCORE`
   overlay where nothing has established that it is even visual. That is not a claim that the
   map cannot strike itself on the way out, which is what decision 1 builds from a measured
   curve. The two referents were one word apart and nothing said so. `CONTEXT.md` therefore
   carries a **Screen-out** entry stating the ownership and the referent, and the Host cue
   `_Avoid_` points at it. The word is kept rather than renamed: it is the ROM's own
   direction bit (`kind & 2`), and it is the name in this ADR's title, in
   `WorldMapScreenOut`, and in `--menu=screenout`. The ambiguity was in the missing
   definition, not in the term.

## Considered options

- **Run `WorldMapScreenIn` backwards.** Rejected by measurement, not by taste: a reversal is
  wrong at *both* endpoints and in opposite directions (decision 1).
- **A second quad for the out arm.** Rejected. On console the two arms ARE one descriptor
  driven by one routine's two directions, so one quad is the faithful shape — and
  `_screen_in_rect` is added to the tree BEFORE the expansion pass, an ordering
  `_build_screen_in` documents at length and a second quad would have to get right again.
- **Null `_screen_out` once the ramp lands.** Rejected. Black at 248 **is** the wanted
  terminal state — the map is handing off — and nothing re-reads `_screen_out` after
  `is_active()` goes false, because `advance()`'s tick is guarded on exactly that. Nor is
  there a second life in which a stale reference could matter: decision 5's latch and the
  fresh-instance-per-visit host see to that. Nulling would buy nothing and would cost
  `screen_out_ticks()` its terminal reading.
- **Extract the stall loop the scene and the two tests each carry.** Deferred, deliberately.
  The tests share no base class (`extends Node` apiece), and the repo's own precedent for a
  test waiter — `_wait_until` — is a private per-file copy in three files with two different
  signatures, whose `max_frames` bounds in *rendered frames*, the exact unit decision 5 calls
  the defect. Extracting toward that shape would reintroduce the bug under a nicer name.
  What is shared is what matters and what drifted: one constant and one progress reading. A
  fourth waiter is the trigger to find the loop a home; the third is not.
- **Fade the music with the picture.** Rejected here as a separate decision with a separate
  cost — see Consequences.

## Consequences

- **The music still cuts.** `music.stop()` fires at the top of `_leave`, so the theme stops
  while the picture is still fading. Fading it would mean a new verb on
  `WorldMapMusicPort` — a widened Audio surface — and the crossing budget for this screen is
  one port with `play`/`stop` (crossing A1). Deliberately left.
- `--menu=screenout` renders the ramp as a contact sheet, the counterpart to
  `--menu=screenin`. A fade is a picture, and the specific thing to LOOK for here is the
  opposite of the in arm's stall — the first cell should already be slightly down, because
  the curve opens at 32. A sheet whose first cell is the clean map means the `+ 32` was
  dropped and the fade is starting from nothing.
- **`_run_screen_out` has THREE skips.** Besides decisions 2 and 6, it returns when
  `_screen_in_rect` is null. That rect is built unconditionally by `_build_screen_in` from
  `_ready`, so a null means `leave()` arrived before the screen finished coming up — and
  running the ramp then would spend all sixteen vsyncs pushing into `_push_screen_out`'s own
  null check, making the host wait out a fade that darkens nothing. Cutting is the honest
  answer when there is no picture to fade. The three are written one per line, because they
  are three different statements about the world rather than one condition.
- Nothing here reaches Audio, and `check_addon_portability` still reports the sound package
  reaching no system. The change is confined to `src/world_map/` (booked `UI` by ADR-0176)
  and one `src/debug/` panel row.

## Verification

- `tests/WorldMapScreenOutTest.gd` — decisions 1–3 and 5. It pins both endpoints, the
  monotonic direction, the 5-bit quantisation and the landing tick, because none of those
  survive a "reverse the other arm" refactor and a filmstrip cannot state them exactly. Its
  tunable arms first rule out the *other two* skips (`capture_path.is_empty()`,
  `has_screen_quad()`), since `screen_out_active()` reads false after all three and an arm
  reading only that flag would pass on a scene that never built a quad.
- `tests/WorldMapMountTest.gd` — decision 5 through the player's ✕, in two arms seeded red
  independently: a stalled ramp reds *"ui_cancel emits dismissed"* alone, a cut reds *"and
  it waited for the fade rather than cutting"* alone. The second asserts that the loop
  **observed the ramp advance**, not that a frame elapsed — `Input.parse_input_event` queues,
  so exactly one frame elapses on the cut path too, and a frame count cannot separate a fade
  from a cut here.
- Both suites and `_run_screen_out` are the three waiters, and all three count with
  `STALL_FRAMES` off `screen_out_ticks()`.
- The picture half is not covered by a suite and is not meant to be:
  `-- --menu=screenout --shot=…` is a contact sheet a person LOOKs at.
