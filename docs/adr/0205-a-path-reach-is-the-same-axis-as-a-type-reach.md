# A path reach is the same axis as a type reach, and the term both registers called "install" was never axis B

Two registers close to zero and neither answers the question. `check_addon_install` reads
**0 sites / 0 rows** — the addon installs into a bare fork+kernel+port project (ADR-0202).
`check_lattice_publish` reads **21 sites / 12 rows** and is nearly closed. Yet
`assets/scenes/GPUArena.tscn` still carries

    [ext_resource type="Script" path="res://addons/exmateria_battlefield/assembly/MapComposer.gd" ...]

and **139 host sites do the same thing**. Both registers are structurally blind to it, both say
so in their own output, and both call it *the install term*. That name is wrong, and the wrong
name is why the gap survived three ADRs unowned.

Status: accepted (2026-08-29). Loop **pass 12** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Opens the question
[ADR-0196](0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md)
dec. 8 raised and left unowned, and which
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 1 kept apart
without ruling on containment. Amends **ADR-0164 dec. 4** by adding criterion 4. Corrects a
scale claim in [ADR-0204](0204-the-mount-point-is-an-inherited-scene-because-the-addon-supplies-the-ui-to-a-hundred-and-seven.md).
Does **not** collapse `MapComposer` — see dec. 7.

## Context

### 🔴 The correction: host → addon is axis A, whatever the spelling

ADR-0202 dec. 1 named two axes and forbade reporting either as the other:

| axis | direction | question | register | state |
|---|---|---|---|---|
| **B** | addon → host | does the addon *install* into a bare project? | `check_addon_install` | **0 / 0, CLOSED** |
| **A** | host → addon | is the addon *isolated* from its host? | `check_lattice_publish` (criterion 1) | 21 / 12, open |

`check_lattice_publish`'s own ⚠️ says the `.tscn` path-instances are *"THE INSTALL TERM — 'the
addon does not parse where the declaring addon is absent'"*. ADR-0196 dec. 8 repeats it. Both
are wrong about the direction. A **host** file naming
`res://addons/exmateria_battlefield/assembly/MapComposer.gd` is the host reaching **into** the
addon. That is axis A. It is the same direction as `var c: MapComposer`, the same failure mode,
and the same criterion — only a different spelling.

The confusion had a cause worth writing down: *the addon does not parse where the declaring
addon is absent* is a true sentence about a **host** file with the **addon** removed, and it
sounds like an install claim because "install" is the word attached to absence. But axis B asks
what breaks when you remove the **host**. Nothing here does. Deleting the whole host tree leaves
every one of these 139 sites behind, in the host.

So the containment question — *does isolated subsume installable?* — is the wrong question and
answering it either way would have built the wrong register. The two axes stay disjoint exactly
as ADR-0202 dec. 1 has them. What was missing is that **axis A has two spellings and only one
was ever scored.**

### The population, measured

Every file outside `addons/exmateria_battlefield/` naming an
`res://addons/exmateria_battlefield/…` path, across `.tscn`, `.tres`, `.gd`, `.cfg`:

    TOTAL  139 sites over 132 files

    BY SHAPE                              BY DIRECTORY
      109  ext_resource type="Script"       122  tests/
       18  preload()                         12  assets/
        4  ext_resource type="PackedScene"    3  tools/
        4  bare string                        2  src/
        3  load()
        1  ext_resource type="Shader"

    BY TARGET
      115  assembly/MapComposer.gd            1  texturing/MapIlluminationDDA.gd
        8  cursor/TileCursor.tscn             1  camera/PlayerCamera.gd
        7  camera/PlayerCamera.tscn           1  cursor/TileCursor.gd
        1  cursor/cursor_clut_preview.gdshader 1 cursor/TileCursorBob.gd
        1  overlay/TileOverlayColor.gd        1  overlay/TileOverlayCompositor.gd
        1  debug/MapGridOverlay.gd            1  texturing/PaletteTextureGenerator.gd

Two numbers decide the design.

**`src/` holds 2 of 139.** The game source is already almost clean; the coupling is in test
scenes. A criterion scoped to `src/` the way ADR-0196 dec. 3 scoped criterion 1 would enforce
**2** sites and report 137 — it would read as nearly closed on the day it was built, while 122
test scenes hold the debt. See dec. 6.

**`MapComposer` is 115 of 139, 83%.** One target dominates, and it has had no equivalent of
ADR-0204's pass. See dec. 7.

### 🔴 Two counts in the prior ADRs are wrong, and one claim is a scale error

`check_lattice_publish`'s ⚠️ says *"107 and 109 `.tscn` files"* instance `PlayerCamera` and
`MapComposer`. Measured on this tree, after ADR-0204 landed: `PlayerCamera.tscn` has **7**
namers and `MapComposer.gd` has **115**. The 107 was true before ADR-0204 collapsed it to the
inherited-scene mount; the 109 was a `.tscn`-only count and undercounts the `.gd` `preload`
shape. The ⚠️ text is therefore stale in both directions at once and is deleted by this pass,
not corrected in place.

ADR-0204 dec. 3 says Class C "closes on the addon side only". That is correct and this pass
confirms it: **the install register reads 0 and stays 0** — the fan-out measured here is
entirely host→addon and touches axis B nowhere. The 115-site `MapComposer` fan-out is **not a
layering inversion**; it is the host consuming a published implementation file directly instead
of through a host-owned indirection, which is precisely what ADR-0204 built for the camera.

## Decisions

**1. Axis A has two spellings. A path reach is a criterion-1-axis site, and *isolated* does not
subsume *installable*.** The containment question ADR-0196 dec. 8 raised is dissolved rather
than answered: the reaches it pointed at were never on axis B. ADR-0202 dec. 1 stands unchanged
— the two axes are disjoint, must never be reported as each other, and both numbers appear in
every report. What changes is that axis A's number was incomplete.

**2. The path spelling is scored BESIDE criterion 1, in its own register, as criterion 4.**
ADR-0164 dec. 4 gains a fourth criterion: *no file outside the addon may name an
`res://addons/exmateria_battlefield/…` path, except at a declared mount.* It is not folded into
criterion 1. Criterion 1's subject is the **compiled symbol** surface and its instrument is a
`class_name` scan of `.gd`; this one's subject is the **resource path** surface across four file
types. ADR-0131 dec. 7's named failure — one number answering two questions — applies to
merging them, not to running them side by side. `tools/check_lattice_scene.py` is the register.

**3. The target is 0 UNDECLARED reaches, on ADR-0196 dec. 4's ENFORCED/REPORTED split.**

      ENFORCED   every path reach outside the addon that is not a declared mount. Arm 1,
                 burn-down by name, both directions. Target 0.
      REPORTED   `DECLARED_MOUNTS` both ways, and the namer count per declared target.
                 Prints, scores nothing.

An earlier draft of this decision proposed a target of *one namer per addon entry point*. That
was rejected: it bakes an arbitrary integer into a criterion, and it cannot say which one namer
is the legitimate one. The declared-mount list does both — it names the sanctioned indirection
file explicitly, and everything else is debt at target 0. The number is honestly zero.

Today there is exactly one declared mount, ADR-0204's:

    assets/scenes/CombatCamera.tscn  →  camera/PlayerCamera.tscn

so the burn-down opens at **138 sites / 138 rows**, and 1 site is declared.

**4. The `.gd` `preload`/`load`/bare-string-by-path shapes fold into the same register.**
`preload("res://addons/exmateria_battlefield/…")` is the identical coupling with a different
file extension around it — 25 of the 139. `check_lattice_publish` explicitly lists this shape as
a blind spot (*"names the file, not the `class_name`, and `strip_noncode` blanks the literal
before the scan sees it"*). Splitting it into a fifth register would put one question in two
places and let a site move between them unscored.

**5. Criterion 1's 21 sites are closed by this pass's sibling commits.** ADR-0196 dec. 8
deferred `TileCursor` (13) and `CursorController` (8) to *"the pass that closes criterion 1"*.
This is that pass. The shape is a `CursorController.new()` construction seam plus `TileCursor`
type annotations — an interface answer, not a re-spelling. Rows go STALE and are **deleted**;
the reach is never restored.

**6. `tests/` ENFORCES here, unlike criterion 1's arm 2.** ADR-0196 dec. 3 made `tests/` a
reporting arm because *"`classify()` returns `None` for every test file"* — the bucket
classifier cannot say which system a test belongs to, so a threshold would be guesswork. **That
reason does not transfer.** A path is not a bucket: `res://addons/exmateria_battlefield/…`
identifies the addon with no classifier involved, and the question "does this file name that
path" has the same answer in `tests/` as in `src/`. With `src/` at 2 of 139, a reporting-only
`tests/` arm would leave 88% of the population unscored and the register would read as nearly
closed on day one.

**7. This pass rules and builds the register. It does NOT collapse `MapComposer`.** All 115
rows open on the burn-down with an owner and a named pass, per ADR-0196 dec. 5. The precedent is
ADR-0204's — a host-owned indirection that keeps consumer-visible structure byte-identical — but
`MapComposer.gd` is a **script** reach, not a `PackedScene` instance, so the inherited-scene
mechanism does not transfer unexamined and pricing it is that pass's work. Building the register
first is ADR-0192 dec. 1 / ADR-0196 dec. 1's rule: after a move, a scanner blind to the old
spelling is indistinguishable from a correct one, and 83% of this population is about to move.

**8. ADR-0204 dec. 3 is confirmed, and the fan-out is recorded as a correction, not a defect
class.** Class C is **0** after ADR-0204. The 115 `MapComposer` sites are host→addon and were
never in Class C's population; nothing about them reopens axis B. Recorded here so the next
reader does not price them as a layering inversion.

## Consequences

- A fourth register joins the mandatory set. ADR-0202's rule becomes: run **five** —
  `check_addon_install`, `check_lattice_ports`, `check_lattice_doors`, `check_lattice_publish`,
  `check_lattice_scene` — and report axis A and axis B as separate numbers.
- `check_lattice_publish`'s ⚠️ block is deleted. The question it raised is now owned, its
  direction was wrong, and its two counts are stale; leaving a corrected version would preserve
  a pointer to a term that does not exist.
- 🔴 **The register carries 138 rows on the day it is built.** That is the point — a burn-down
  is a named list so a triaged site is distinguishable from one that merely matches (#424) —
  but it means the guard's literal is large and one pass will delete 115 rows at once.
- The declared-mount list is the only escape hatch and is a reviewed literal. It is REPORTED in
  both directions so a mount declared for a target nothing names shows up as dead.
- 🔴 **A symlinked directory is outside the walk, and it stays that way.** `Path.rglob` does
  not recurse into one (`recurse_symlinks=False`, Python 3.13), so `addons/exmateria_sound/`,
  `addons/exmateria_spu/`, `assets/maps/` and ~20 more trees are unscanned. Found by a seed
  test **written asserting the opposite**; the failure was the finding. Following them is
  rejected: `assets/maps` is absent from a bare worktree, so the ENFORCED count would differ
  between two checkouts of the same commit and a burn-down row would go STALE on a machine
  rather than on a fix. Instead `symlink_probe()` counts prefix-naming files inside each
  symlinked tree and REPORTS it, so the gap cannot go non-empty silently. Measured: **0 files
  across every symlinked tree**, so nothing is being excused today.
- 🔴 **Both seed tests must CONSTRUCT the site and the row** (ADR-0202 dec. 10). A control that
  borrows live debt expires the day the debt is paid; that has failed **six** times in this
  repo, most recently `test_check_addon_install.py`'s `"Not a pass"` assertion.

## Alternatives rejected

- **Fold the path shape into criterion 1.** Rejected: one number, two questions, two
  instruments, four file types — ADR-0131 dec. 7's own named failure.
- **Answer the containment question as posed (does isolated ⊇ installable).** Rejected as
  built on a false premise; see Context. Either answer builds the wrong register.
- **Target one namer per entry point.** Rejected in dec. 3: an arbitrary integer in a criterion,
  and it cannot identify which namer is legitimate.
- **Scope the enforcing arm to `src/`, mirroring ADR-0196 dec. 3.** Rejected in dec. 6: dec. 3's
  reason is about a bucket classifier and does not survive contact with a path. It would enforce
  2 of 139.
- **Collapse `MapComposer` in this pass.** Rejected in dec. 7: the register goes first, and a
  script reach is not the scene reach ADR-0204 solved.
- **Follow symlinks in the walk.** Rejected: it makes the enforced number a property of the
  checkout rather than the commit. Replaced by a reported probe — see Consequences.
