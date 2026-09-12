# A port half is not shipped until both directions of the value are on it

[#848](https://github.com/timbermania/fft-monorepo/issues/848) was the last row on
`tests/stranger/exmateria_sprite_rig/known_failures.tsv`, and its own analysis said what the fix
had to be:

> There is no such port for `PSXDisplay` today. Either **(a)** a `DisplayPort`-shaped `class_name`
> in `exmateria_platform` beside `TunePort` … or **(b)** the minimum conformant shape at the call
> site … (a) is the better answer if any other addon reaches `PSXDisplay`; (b) is right if this is
> the only site. **Measure that before choosing** — do not assume from this issue.

Measured. **Neither option was open, because option (a) had already shipped.**
`addons/exmateria_platform/display_port/DisplayPort.gd` has existed since
[#590](https://github.com/timbermania/fft-monorepo/issues/590) — a `RefCounted` beside `TunePort`,
published on the folder façade as `ExMateriaPlatform.DisplayPort`, soft-binding `^"PSXDisplay"` by
node path at call time. It is exactly the file the issue proposed writing.

What had not shipped was **its read half**. #590 moved `set_camera_angle` onto the port and left
the mirror that call writes reachable only as a *property* on the autoload:

```gdscript
static func set_camera_angle(psx_12bit: int) -> void:   # on the port
	…
var live_camera_angle: int = 0                          # on the autoload, and only there
```

A property on an autoload serves the host and cannot serve an addon, because an addon cannot name
the autoload. So `addons/exmateria_sprite_rig/render/CameraRelativeRenderer.gd` went on writing
`PSXDisplay.live_camera_angle` at two lines, did not parse in a project without the `[autoload]`
line, and took four more files down with it — including `exmateria_sprite_rig.gd`, the addon's one
published global name.

Status: accepted (2026-09-05). Builds
[ADR-0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md) dec. 2, which built the port
this completes, and closes
[ADR-0232](0232-goal-5-is-a-conjunction-and-neither-instrument-may-claim-the-word-alone.md) dec. 7,
which recorded `Sprite Rig` goal #5 `open` pending exactly this. Reads
[ADR-0229](0229-the-sprite-rig-reads-isolated-on-every-static-instrument-and-does-not-compile.md),
which built the rig that priced the debt.
Tickets: [#848](https://github.com/timbermania/fft-monorepo/issues/848) (paid here),
[#899](https://github.com/timbermania/fft-monorepo/issues/899) (filed here),
[#583](https://github.com/timbermania/fft-monorepo/issues/583) (unblocked, and no longer a
predecessor of anything on this line).

## Context

### The two options the issue offered were one shipped file and one guard violation

Option (b) — `get_tree().root.get_node_or_null(^"PSXDisplay")` written at the call site — reads
conformant because ADR-0202 dec. 7 rules that exact spelling conformant for `TunePort.gd:78`. It is
not conformant *here*, and the difference is not stylistic. `check_addon_portability.py` arm 2b
scores a host autoload named as a node-path STRING, and its free set is written out in its own
docstring:

> `main()` scores this arm on arm 5's free set: the kernel and the port are exempt, a SYSTEM is
> not.

with a second exemption for an addon reaching **its own** singleton, decided on the `res://` path
the `[autoload]` line carries. `exmateria_sprite_rig` is a system, and `PSXDisplay.gd` is shipped by
`exmateria_platform`. It is in neither exemption. ADR-0202 dec. 7's ruling covers `TunePort.gd`
because `TunePort` **is** the port; quoting it at a system's call site inverts it.

So the issue's "(b) is right if this is the only site" was answering the wrong question. The number
of call sites does not decide it; **which addon is doing the naming** decides it, and for a system
addon the port is the only shape that exists.

### The null-guard that could not fire, and the last copy of it

Both lines were spelled `PSXDisplay.live_camera_angle if PSXDisplay else 0`. A bare autoload
identifier is resolved at compile time: where the name is bound the ternary is dead weight, and
where it is not the file does not parse at all, so the fallback is unreachable by construction. The
author's intention to degrade gracefully was written into the source and the source could not run
it — ADR-0229 dec. 2 recorded this, and paying the row is what removes it rather than annotating it.

A census over the tree found exactly one other copy, `src/units/Unit.gd:975`, in the host, where the
name is bound and the guard is therefore merely dead. It is removed here too, in the same commit
that renames the key beside it. The idiom now appears nowhere.

### The claim that decided the shape, and the two claims that did not survive it

Three statements travelled with this ticket. One was true and load-bearing; two were false and had
been restated in three places each.

**TRUE — "no port is owed, it is an install step."** `PSXDisplay.gd` is at
`addons/exmateria_platform/display_port/PSXDisplay.gd`; `plugin.cfg` declares
`deps="exmateria_schema exmateria_platform"`; `tests/stranger/shared/rig.sh` stages every declared
dep with `cp -rL`. The script is present in the stranger project and only the `[autoload]` binding
is absent. Verified by reading the staging, not the docs.

**FALSE — "no such port exists today."** It does, and has since #590. This is the third consecutive
session on this line to find a false premise sitting in a doc nobody had run the instrument
against, and the shape is the same each time: a sentence that was true when written, about a tree
that then moved.

**FALSE — "#848 is ordered behind #583."** Asserted by ADR-0232's ticket line, by
`known_failures.tsv`'s header and by the handoff that opened this session, on the reasoning that
#583's rename of `PSXDisplay` to `DisplayCalibration` moves this row's own signature text.
`DisplayPort` absorbs the autoload's spelling at its own node path, *inside* `exmateria_platform` —
`DisplayPort.gd`'s docstring has said so since #590: *"after this port, that rename reaches the node
path on the line below and nothing in any addon."* Paying #848 first **deletes** the row, so there
is no signature for #583 to move. If there was ever an ordering it ran the other way.

### Goal #7 was the other half of that ordering claim, and it does not hold either

`docs/GOALS.tsv`'s `Sprite Rig`/#7 row said the addon's twelve rig-owned jargon lines were *"#583's
work and not a new ticket"*, because renaming the consumer ahead of the port would have this addon
spell a concept the port still spells `psx`. Measured: **the port does not spell it `psx`.**
`PSXDisplay.live_camera_angle`, `DisplayPort.live_camera_angle()` and `DisplayPort.set_camera_angle()`
are all prefix-free. The `psx` in those twelve lines was this addon's own local spelling
(`last_psx_camera_angle`, the `psx_camera_angle_changed` signal, the `psx_angle` view key,
`get_pose_octant`'s second parameter), echoing nothing. They are renamed here.

That leaves 22, and the row still reads `open` — which is the finding worth carrying forward,
because it is not what either ticket implied. `score_goals.py` has no partial credit and no
provider exemption:

```python
blocking = content if exempt else hits
if not blocking:
    return True, "0 content-jargon lines" + note
```

20 of the 22 name a `psx_*` symbol **another package publishes** (`psx_ot_depth`,
`psx_ot_computed_depth`, `psx_par_anchor`, `psx_unit_stretch`, `psx_color_apply`, `psx_color_stack`,
declared in `exmateria_schema` or `exmateria_platform`) and 2 are `PSX_FOLD_GAIN`, which the same
register books to goal #8. #583 as scoped clears **2 of the 22** — the two `psx_par` includes;
`unit.gdshader:78` and `unit_additive.gdshader:71` name `psx_unit_stretch` on the same line and
survive it. So #583 does not close goal #7 for this system either. #899 carries the provider-side
question.

## Decision

1. **A port half is not shipped until both directions of the value are on it.** `DisplayPort` gains
   `live_camera_angle()`, a fourth member, and the rule is general: a push-only port half reads as
   complete for exactly as long as nobody outside the host wants the value back. #590 shipped the
   push, `check_addon_portability` went green, and the read stayed on the autoload for three months
   because no instrument asks whether a port is *symmetric* — only whether an addon names something
   it should not.

2. **A SYSTEM addon reaching a foreign autoload has one conformant shape, and it is the port.** Not
   the bare identifier (arm 2, and it does not parse), not the node-path string (arm 2b, whose free
   set is the kernel, the port, and an addon's own singleton). ADR-0202 dec. 7's conformant ruling is
   scoped to the port and does not travel to the port's callers.

3. **The absent value is `0`, and it is a found value rather than a chosen identity.** `NO_STRETCH`
   is `1.0` because 1.0 is what "no stretch" means. There is no analogous identity for a camera yaw;
   `0` is used because it is the autoload's own boot value for the mirror *and* the fallback the one
   call site already spelled, so the port changed no behaviour on the day it landed. Absent
   calibration puts every unit on the baseline pose octant — defined and uniform, rather than a
   `null` reaching `AnimationStateController.get_pose_octant`.

4. **The rig's twelve rig-owned goal #7 lines are renamed here and not deferred to #583**, on the
   measurement above. Two of the four renamed names are contracts with the host — the
   `camera_angle_changed` signal and the `_view["camera_angle_12bit"]` key — and both halves move in
   this commit, with the rows added to the extraction #4 translation table (goal #2).

5. **`Sprite Rig` goal #5 is `met`, both halves, and this is the join ADR-0232 built doing its job.**
   The budget half was already 0 across four deliberately-disagreeing instruments; the install half
   is now an empty `known_failures.tsv` and a rig that reports `stands up in a project that did
   nothing for it` with no exception clause. Neither half may claim the word alone, and today both
   say it.

6. **Goal #7 is NOT closeable from inside this addon, and `GOALS.tsv` says so rather than implying a
   follow-up.** The remaining 22 lines belong to two provider addons and to goal #8. Filed as #899,
   which asks the one question that actually gates it: does ADR-0129 dec. 10's `psx_` retirement stay
   scoped to `par`, or does it generalise to the `.gdshaderinc` surface.

## Consequences

- `Sprite Rig` scores **6 met / 4 open**, up from 5/5. The four open are #6 and #10 (the authoring
  project — no verb in this repo creates a sprite template, and `SequenceViewer` holds no
  `ResourceSaver`), #7 (blocked on #899, a provider-side rename) and #8 (blocked on the epilogue's E1
  known-drops register, alongside `Render`, `Audio` and `Battlefield`). **None of the four is a
  Sprite Rig job**, which is the honest end-state for this extraction and is worth stating in place
  of a plan to close them.

- The fifth stranger rig's burn-down is empty, so `rig.sh` no longer runs `stranger_burn_down.gd`
  and `stranger_install.gd` is the arm that makes the claim. `known_failures.tsv` is kept, per its
  own header, because the record of which rows left and what paid them is the part a reader needs.

- **The cascade set moved on the LAST row, not proportionally.** #847 paid one of two rows and the
  install pass stayed at 72 files with four cascade files still down; #848 paid the second and it
  went to 73. `known_failures.tsv`'s header already predicted this in the other direction — *"a
  burn-down measured by ROW COUNT would have read that as half the debt paid"* — and it is now
  measured in both.

- `tests/TunePortTest.gd` gains the present and absent arms for the new verb. The absent arm seeds a
  non-zero angle before removing the port, without which `live_camera_angle() == 0` would be vacuous
  — the mirror reads 0 at boot, so the assertion would pass against a port that returned the stale
  value.

- `tests/CameraAnglePortTest.gd` — the liveness oracle for this whole value path, which no guard can
  replace — now also asserts the port's read half forwards, because the sprite rig reader it drives
  goes through `DisplayPort` rather than the autoload.

- **Three sessions, three false premises, all in the same shape.** ADR-0232 dec. 8 found
  `outbound_reaches()`'s docstring false; this ADR finds #848's *"no such port exists"* and its
  ordering false, and `GOALS.tsv` #7's *"it is #583's work"* false. Every one was a true sentence
  about a tree that later moved, restated forward without being re-run. The cheap defence is the one
  used here: before building what a doc describes, run the instrument the doc is describing.
