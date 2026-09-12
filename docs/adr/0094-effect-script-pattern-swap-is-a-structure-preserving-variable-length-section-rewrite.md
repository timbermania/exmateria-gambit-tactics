# Effect script-pattern swap is a structure-preserving, variable-length section rewrite

## Status

accepted

## Context

The Effect Studio surfaces an effect's **script pattern** — `3-phase`
(phase-1 + for-each + phase-2; opcode 41 outer + opcode 40 for-each) or
`1-phase` (for-each only; opcode 40) — and lets the author **swap** it, which
rewrites the effect-script bytecode. The Lua effect editor
(`effect-editor/ui/script_tab.lua`) already does this via two "Convert to
1-phase / 3-phase" buttons that stamp fixed 30-/62-byte templates.

Porting that verbatim looked simple, but a corpus audit (399 DATA effects)
showed the Lua templates are a **simplification that would corrupt real
effects**:

- Every real script opens with a **per-effect prologue** the templates omit:
  `set_texture_page` whose flags byte encodes the texture page (observed
  `{8,16,24,32,56}`, **never** the template's `0`), optionally followed by
  **0–4 `load_callback`** instructions (per-effect sprite/anim callback
  registrations). Stamping a template zeroes the page and deletes the
  callbacks.
- The real byte sizes are not 30/62. A 3-phase **section** is 64 bytes (root
  36 + for-each child 28, incl. a 2-byte tail pad); a callback-free 1-phase is
  ~36. Callbacks add 4 bytes each.
- `parse_effect.parse_script` stops at the first `end` (0x04), so `script.json`
  holds only the **root** — the for-each child bytecode is not on the Godot
  side at all. Pattern detection still works (opcodes 41/31 live in the root).

Two structural invariants hold across the whole corpus and make a faithful
swap well-defined:

- **3-phase** prologue is always `set_texture_page + [callbacks] +
  init_physics_params` (238/238); **1-phase** prologue is always
  `set_texture_page + [callbacks] + clear_timeline_a + init_physics_params`
  (161/161). The `clear_timeline_a` (opcode 42) marker is the real difference —
  present in every 1-phase, absent from every 3-phase. **The Lua templates omit
  it entirely.**
- After the prologue, the control-flow body is a single **canonical shape** per
  pattern (opcode sequence identical; only branch offsets shift with callback
  count). The 3-phase for-each **child** is structurally the 1-phase loop.

The file layout also matters: the script section sits near the top (header
offset 0x08), so resizing it shifts **every** downstream section. A corpus
check found that all sections are located **only** through the 40-byte header
pointer table; no internal absolute cross-section pointers exist (E001's tail
has zero words equal to any header pointer). So a whole-tail shift plus a
header-pointer fix-up is sufficient — the resize needs no interior relocation.

## Decision

1. **Structure-preserving swap, not template stamp.** A swap **preserves the
   effect's real prologue verbatim** (texture page + every `load_callback` +
   `init_physics_params`) and regenerates only the control-flow body, adding or
   removing `clear_timeline_a` and the for-each child as the target pattern
   requires. Canonical bodies are derived from **real effects** (E001 for
   3-phase incl. child; E043 for 1-phase incl. `clear_timeline_a`), **not** the
   Lua templates.

2. **A swappable script is fully determined by `(pattern, texture_page,
   callbacks[])`.** All three live in the root that `script.json` already
   captures, so the writer **regenerates** the entire canonical section
   (including the for-each child) from those values — it never needs to read
   the child bytes.

3. **Strict-canonical + DATA-only gate.** The editable swap is offered **only**
   when the script exactly matches a canonical template (prologue shape +
   canonical body) **and** the file is DATA-format. This makes the byte-exact
   round-trip **provably lossless and reversible**. Everything else shows the
   mode **read-only** with a reason: Custom (E000, E306), CODE-format (E015 and
   ~106 others — the writer is DATA-only), and the one non-canonical 1-phase
   outlier.

4. **Keep-dormant timeline.** A swap rewrites **only** the script section. The
   timeline section's phase-1/phase-2 channels are left untouched; on 1-phase
   they simply stop executing (no opcode 41) and the Studio score hides those
   lanes. Swapping back restores them intact — non-destructive and fully
   reversible (faithful to the Lua editor, which never touches the timeline).

5. **Variable-length save = regenerate + tail-shift + header fix-up.** A new
   `write_effect_script.py` / `EffectScriptSaver` synthesizes the canonical
   section, splices it in, shifts the entire tail by `delta = new − old`, and
   adds `delta` to the eight downstream header pointers (0x0C–0x24), **skipping
   any that are zero** (e.g. an absent `time_scale_ptr`). It plugs into the
   existing `studio_save` saver chain after the flags saver.

6. **Surface as a third `effect_settings` tenant.** A "Script Pattern" section
   on the Effect ⚙ surface (beside Timeline #271 and Flags #272), showing the
   mode plus a Convert action (or read-only label), edited as a staged,
   undoable channel that re-flows the score live and commits at
   `studio_save` — consistent with ADR-0092.

## Consequences

- The round-trip guard must validate the **intermediate** swapped file
  (re-parse every section, assert `detect() == target`, assert header pointers
  land on section starts), because a there-and-back byte-identity check alone
  cannot — shifting the tail down then back up restores the bytes regardless of
  correctness.
- Only E001/E019 (3-phase) and E015 (CODE) source BINs exist; there is **no
  clean 1-phase DATA source BIN**. A 1-phase→3-phase→1-phase byte round-trip
  must therefore be tested on a **synthesized** fixture (swap E001→1-phase to
  mint it, then swap back).
- The section's trailing pad (62→64 for 3-phase) must be reproduced exactly;
  the round-trip guard on E001/E019 pins it.
