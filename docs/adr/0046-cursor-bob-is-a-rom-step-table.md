# Cursor bob is a ROM step-table, paced at VBLANK_HZ ÷ vblanks_per_tick

The tile cursor (the on-grid knife/dagger) floats above the active tile and
bobs while at rest. `TileCursor._update_mesh_anim` drove that bob with a
**centered sine** on the mesh's local Y — `cursor_height + sin(phase·TAU)·
cursor_bob_amplitude`, period and amplitude exported as freely-tunable world
units. That motion was invented, not faithful: FFT does not synthesize the
bob from a curve, it reads it from a table the ROM ships.

Static analysis of BATTLE.BIN located the real mechanism. `FUN_8007e304`
(`0x8007e304`, the tile-cursor sprite renderer, called from `FUN_8008924c`)
walks two parallel 8-entry tables — an **offset table** at `0x80067798`
(`{0,1,2,3,5,3,2,1}`) and a **hold table** at `0x800677b8`
(`{16,8,2,2,6,4,4,10}`) — via a phase index (`0x800961f8`, 0–7) and a per-step
frame accumulator (`0x800961f4`) that increments by the global animation speed
`DAT_80045980` (= 1). Raw bytes were verified against the binary. Three facts
fall out of the disassembly: the bob is applied to the cursor's world-space Y
**before** isometric projection, in FFT units where **1 tile = 28 (0x1c)**; it
is **one-sided from the resting pose** (`vy -= (base − offset)`, so the cursor
dwells 16 frames at offset 0 and makes a single excursion to 5, not a symmetric
oscillation); and it is **discrete**, dwelling whole frame counts per step.

The bob's pace is gated by the battle frame loop. `FUN_80093a98` → `FUN_8001dba8`
(the vblank-wait path, `FUN_8001dcf0`) passes **0** to the wait when
`DAT_80045980 == 1` — i.e. **no frame-skip, every vblank, 60 Hz, +1/frame** in
normal play. The ROM's own fast-forward (`DAT_80045980 == 2`) waits 2–4 vblanks
with a +2 increment, which is the engine confirming the pacing is a
vblanks-per-tick divider rather than a continuous rate. Static disassembly fixes
the *rate* (N=1) but not the *direction sign* of the one-sided excursion — only
a frame-by-frame capture settles up-vs-down.

A sibling cursor — the WORLD/menu **glove cursor** — bobs by the same concept
but a different encoding (`[threshold, offset]` signed byte-pairs, 0-terminated,
modulo timer; idle + select tables at `0x80156352`/`0x80156362` in WORLD.BIN @
`0x800E0000`). It has no Godot consumer yet, but its data is parsed alongside the
tile cursor so it is ready when a menu cursor lands.

## Status

Accepted (2026-06-15). Replaces the sine bob in `TileCursor`. Scope is the tile
cursor only; the glove-cursor *data* is parsed-and-ready (`cursor_bob.json`) but
its *implementation* is deferred (no menu cursor exists) — tracked as a GitHub
issue. The resting hover height (`cursor_height`) is unchanged; re-deriving
FFT's `0x3c = 60/28` hover is out of scope.

## Decision

**The tile-cursor bob is the ROM step-table, played by a CPU-driven fixed-step
phase machine: `position.y = cursor_height − (offset/28)·bob_scale`, with the
accumulator advancing at `VBLANK_HZ / vblanks_per_tick`.**

1. **The table is the truth.** Offsets `{0,1,2,3,5,3,2,1}` and holds
   `{16,8,2,2,6,4,4,10}` are parsed from BATTLE.BIN into `cursor_bob.json` and
   consumed verbatim. The amplitude *is* the table; there is no separate
   amplitude knob. `bob_scale` (default 1.0) exists only to exaggerate the
   motion for visual inspection.

2. **One-sided from rest, not centered.** The cursor rests at `cursor_height`
   (offset 0, the 16-frame dwell) and excursions one direction by up to `5/28`
   tile (`PSX_SCALE = 1/28`, the repo-wide convention) — not `±amplitude` around
   a midpoint.

3. **CPU mesh move, not shader.** The bob is a rigid whole-sprite translation of
   a single (non-pooled) `MeshInstance3D`; that is a node transform, and the
   billboard shader already re-centers on the node origin. A shader uniform would
   add GLSL/GDScript split and a per-frame feed for zero benefit (nothing varies
   per-vertex/fragment).

4. **Pacing is a vblank divider.** `const VBLANK_HZ := 60.0` (NTSC field clock —
   fixed) ÷ `var vblanks_per_tick := 1` (debug-tunable integer). N=1 is
   evidence-backed (normal play passes 0 to the vblank wait). The phase machine
   is a pure, unit-tested function (frame → phase index → offset); it advances on
   a fixed-step accumulator (like `AnimationPlayback`), never raw `delta`.

5. **Sign is provisional.** The up/down direction of the excursion is a single
   constant to be confirmed against a hardware/PCSX capture (one full cycle = 52
   ticks).

## Considered options

- **ROM step-table, CPU mesh move (chosen).** Faithful by construction;
  testable pure function; reuses `PSX_SCALE`; the phase machine is reusable by
  the glove cursor later. Costs the px→world conversion and an integer-divider
  pacing knob.
- **Keep the centered sine (rejected, retired).** Simple and tunable, but
  invented — wrong shape (symmetric vs one-sided), wrong timing (continuous vs
  discrete dwells), and amplitude/period values that never existed in FFT.
- **Shader vertex offset (rejected).** A uniform whole-quad translation is not
  what shaders are for; splits the logic, must apply after the billboard basis,
  and the cursor isn't pooled so there's no per-instance need.
- **Continuous "tick Hz" slider (rejected).** Invites meaningless values
  (47.3 Hz). The hardware can only skip whole vblanks, so the knob is an integer
  divider — which also mirrors the ROM's own fast-forward mechanism.
- **Normalize both table formats to a flat per-frame timeline (rejected).**
  Lossy: discards hold counts, thresholds, modulo, and the signed/unsigned
  distinction, making faithfulness un-provable against the disassembly. The
  parser preserves each format natively.

## Consequences

- **`cursor_bob_amplitude` and `cursor_bob_period` are deleted** from
  `TileCursor`; the `CursorDebugPanel` BOB section's Amplitude/Period spinboxes
  become **`vblanks_per_tick`** (integer) + **`bob_scale`**. `cursor_height`
  (Height) is unchanged.
- **New parser + artifact:** `tools/parse_cursor_bob.py` →
  `assets/sprites/cursor_bob.json`, a committed extracted artifact spanning
  BATTLE.BIN (`0x80067000`) and WORLD.BIN (`0x800E0000`, via a new
  `world_bin()` helper in `_repo_paths.py`). Format-preserving: `tile_knife`
  (step_table) + `glove_idle`/`glove_select` (threshold_pairs, signed).
- **The RE findings are documented in `fft-ghidra/`** — `renames_high.tsv`
  (functions, tables, globals; `WORLD`-tagged for the glove fn) and PLATE
  comments in `comments_battle_bin.jsonl` + new `comments_world_bin.jsonl`,
  marked `[STATIC]` (verified by disassembly + raw-byte cross-check, not a probe).
- **Two items await a capture:** the bob **sign**, and re-confirmation that
  **`vblanks_per_tick = 1`** (52-tick cycle frame-count). Both isolated to one
  constant each; the default is the evidenced value, so the cursor is correct
  modulo a possible single sign flip.
- **The glove cursor is unblocked on data** — when a menu cursor exists, it
  reads `glove_idle`/`glove_select` from the same JSON and reuses the phase
  machine (adapted to threshold-pair/modulo timing).

## Amendment 1 — the deferred half shipped, and the one artifact became two

Graded 2026-08-28 against the code and the tests, not against the document. **All five
decisions above still hold on the tile cursor**: `TileCursor._update_mesh_anim` reads
the ROM tables through `TileCursorBob`, moves the mesh on the CPU
(`_highlight_mesh.position.y = cursor_height - bob_units`), advances a fixed-step
accumulator at `VBLANK_HZ / vblanks_per_tick`, and `TileCursorBobTest` asserts the
52-frame cycle and the shipped artifact against the ROM literals. Two *incidental*
facts this ADR states have moved since 2026-06-15, and a reader who trusts the Status
paragraph will get both of them wrong.

- **The glove cursor is built.** Status defers the glove *implementation* because "no
  menu cursor exists". Menus exist. `src/ui3/GloveCursorBob.gd` is the pure
  threshold-pair phase machine (`glove_period`, `glove_offset_for_frame`) mirroring
  WORLD `FUN_800ec504`, and eight files consume it — `DetailScene`, `StartActionMenu`,
  `EquipPickerMenu`, `JobPickerMenu`, `LearnAbilityMenu`, `AbilityPickerMenu`,
  `FormationScene`, `WorldMapStartMenu` — with `FormationStartMenuTest` as its oracle.
  The glove offset is applied to the cursor **X**: its bob axis is left↔right, not the
  knife's vertical. The Status line "its *implementation* is deferred (no menu cursor
  exists)" and the Consequences bullet "the glove cursor is unblocked on data" are
  history, not live state. (`GloveCursorBob`'s own docstring still says "Consumers
  (six, all `src/ui3/detail/`)"; it is eight, and two of them — `FormationScene`,
  `WorldMapStartMenu` — are not under `detail/`.)

- **`cursor_bob.json` no longer exists.** Extraction #3 pass 4 split the single
  artifact into `assets/sprites/tile_knife.json` (owned by `Battlefield`) and
  `assets/sprites/glove_cursor.json` (owned by `UI`), and the single `CursorBob` class
  into `TileCursorBob` and `GloveCursorBob`. Decision 1's *rule* survives the split
  intact — one generator, `tools/parse_cursor_bob.py`, still writes both files because
  the ROM is one source, so the tables are still parsed and consumed verbatim; only
  the **filename** named in decision 1 and in the Consequences artifact bullet is
  stale. `docs/context/29-battlefield-camera.md` carries the before/after mapping and
  the reason the split was made (two systems naming one `res://` path is a duplication
  no instrument scores).

- **Decision 5 is still open, and so is decision 4's re-confirmation.** No capture has
  landed. `_update_mesh_anim` still carries "the provisional sign (capture-only
  unknown)" beside its `−`, and `vblanks_per_tick` still ships at the evidenced
  default of 1. Both remain isolated to one constant each, exactly as Consequences
  says.

### What is not amended: scope

This ADR still decides the **tile** cursor. Two other readings of the number have grown
around it. Neither contradicts a decision here, but they are worth separating before
someone pins an `ADR-0046 dec. N` citation to them:

- **The divider as a precedent.** `src/ui3/elements/NumberPopupTrend.gd`,
  `src/ui3/elements/DamageNumber3D.gd` and `assets/sprites/number_popup_trend.json`
  cite ADR-0046 for the `vblanks_per_tick` pacing model applied to a different ROM
  table. That is **decision 4**, reused — legitimate, and `dec. 4` is now the citable
  form for it.

- **"ROM-parsed, not transcribed" as a method.** `tools/parse_number_popup.py` ("Memory
  layout (ADR-0046 style)"), `tools/test_parse_number_popup.py`,
  `tools/bootstrap_assets.sh` (the Q12 scale ramp, the box-trail fade ramp) and
  `FormationScene._load_rom_tables` cite ADR-0046 for tables this ADR never saw. The
  decision they actually mean is the **root** `docs/adr/0001-iso-derived-assets-reproducible.md`
  — which `parse_number_popup.py` names in full ("Per root ADR-0001") and
  `bootstrap_assets.sh` abbreviates to a bare `ADR-0001`. Inside `godot-learning/` a
  bare `ADR-0001` resolves to *this* package's 0001 (the GPU combat buffer layout),
  so those citations point at the wrong document by spelling; ADR-0046 is only the
  first instance of the root rule, not its statement.
