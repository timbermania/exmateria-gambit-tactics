# Where the source that left the walk went is declared once

`WALK_ROOTS` answers *"which source does this refactor own"*. A system that
extracts into a **published package** leaves it, and **five instruments go blind
at that boundary** — each needing the same fact, *"where did system X actually
go"*, and three of them had already begun hardcoding the answer in prose.
`tools/_walk_roots.EXTRACTED` is that fact, declared once, beside the exclusion
that creates the need for it.

Status: accepted (2026-08-22). Completes the correction to
[ADR-0151](0151-an-addon-reaches-no-system-and-a-declarative-panel-is-not-built.md)
dec. 2. Extends [ADR-0149](0149-the-ten-goals-are-scored-per-extraction-and-three-of-them-are-not.md)
dec. 2 and [ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md).
Consumed by extraction #2.

Code at `92ad5f3ed`, classifier at `92ad5f3ed`.

## Context

ADR-0148's defect — *a scan root that does not follow the refactor's output goes
green because it no longer looks* — was fixed **for relocations inside
`godot-learning/`**. It was never fixed for a relocation that leaves the package,
and `Audio` is the first system to make that move.

Counted, the blindness is **five instruments**, not the one ADR-0145 dec. 5
recorded or the three extraction #2 enumerated:

| instrument | what it stops seeing |
|---|---|
| `check_baseline.py --delta` | the system's lines and reaches |
| `closure.py` / `residue.py` | its unclaimed files |
| `score_goals.py` | its goal scorecard |
| `check_addon_portability.py` | **whether it still obeys ADR-0151's rule** |
| `check_debug_panel_tunables.py` | **whether its panels route through `TuneField`** |

The last two are the ones ADR-0151 and ADR-0153 dec. 4 lean on hardest, which is
what turns this from an accounting gap into a live one: **ADR-0151's rule reverts
to a convention at the moment a system ships as its own package.**

Three of the five had already started answering it privately — the literal
`../exmateria-sound/addons/exmateria_sound` appears in `score_goals.py`,
`check_addon_portability.py` and `check_baseline.py`'s prose. Answering it three
times is how three answers drift apart.

## Decision

**1. One list: `tools/_walk_roots.EXTRACTED`.** `(system, path relative to
`PROJECT_DIR`, why this path)`, one row per system that has left the walk, with
`("Audio", "../exmateria-sound/addons/exmateria_sound", …)` as its first. It
lives in `_walk_roots.py` because that file already exists to answer *"which
source does this refactor own"* and already documents **why** the canonical
package is excluded; the destination belongs beside the reason for the exclusion,
not in a fourth file.

**2. It is DECLARED, not derived, and the obvious derivation is a trap that
passes where you test it.** The host carries
`godot-learning/addons/exmateria_sound`, which looks like a free mechanical
answer. Measured in both worktrees:

| | canonical (`fft-monorepo-game`) | secondary |
|---|---|---|
| `addons/exmateria_sound` | **real rsync'd directory** | **symlink** to the package |
| written by | `tools/sync_exmateria_sound.sh` | `tools/link_worktree_godot_assets.sh` |
| ignored at | `godot-learning/.gitignore:3` | `.git/info/exclude` |

So a symlink-based derivation **works in the canonical worktree and fails in a
secondary one**, and whoever writes the clever version tests it where it passes.
A worktree-dependent defect is strictly worse than a uniformly broken one: the
uniformly broken one is found immediately. Either way the derived list is
gitignored in every checkout, so a fresh clone derives **nothing** and every
consumer reports clean — the defect this table exists to close, reintroduced by
the elegant version of the fix.

*(Corrected 2026-08-22: this decision first said the host copy is "a per-worktree
symlink". That is true of the worktree it was written in and false of the
canonical one. Extraction #2 measured both. The correction strengthens the
argument rather than weakening it, which is why it is worth the paragraph.)*

**2b. The record is an object, not a tuple, because the collision was real.**
Extraction #2 independently built an `extracted_roots()` in this same module,
returning `(name, path, present: bool)` against this one's `(system, path, why:
str)` — same module, same name, both 3-tuples. Whichever survived a merge would
unpack positionally into the other's consumers and bind a **string** to
`present`, which is always truthy, silently killing an "absent from this
checkout" branch. Git conflicts on neither half: the definitions sit in different
parts of the file and the call sites are in different files. An `Extracted`
object that cannot be unpacked turns that into a `TypeError` on the first line
that tries.

**3. A declared path that does not exist RAISES.** `extracted_roots()` refuses to
skip a missing row, because every consumer reads a short list as *"nothing more
to check"*. Direction-tested: with the path broken, all three consumers fail
loudly rather than reporting clean.

**4. `docs/BASELINE.tsv` already had the row class, and that is the ancestry.**
Row 29 is `exmateria_sound  extracted  152  15961`, and ADR-0131 dec. 8 says
`extracted` rows are read from the canonical package. **The baseline knew the fact
and could not carry the path** — it is frozen by checksum, and it names
`exmateria_sound` rather than `Audio`. This adds the path and the system, and the
`152` reproduces exactly against the declared root, which is the check that the
two registers describe the same thing.

**5. Three consumers wired now; two left deliberately.**

- `check_addon_portability.py` enforces over declared roots **automatically**, so
  ADR-0151's rule survives a system shipping as its own package. This is the
  decision's whole point.
- `score_goals.py` scores them automatically.
- `residue.py` writes a second header line **naming what it did not look at** —
  *"NOT looked at: … its residue is unmeasured, not zero"*. Saying what you
  scanned is half of it; a reader also needs the roots that exist, hold this
  refactor's output, and are absent on purpose.
- `check_baseline.py --delta` is extraction #2's (#402) and is untouched here; it
  should read this accessor rather than write a second list.
- `check_debug_panel_tunables.py` is **not** wired, and that is a real remaining
  hole rather than an oversight: its subject is *panels*, and whether a package's
  panels should be scanned by the host's panel guard is a question the extraction
  that moves them should answer, not this ADR.

**6. A system with NO rows in the register is REPORTED, never failed; a system
with SOME rows owes all ten.** `Audio`'s extraction has not reached pass 9, so
there is nothing for the scorecard to agree or disagree with, and ADR-0149
dec. 4's two-arm rule has no purchase. Failing on it would make trunk red for
work correctly in progress on a branch. The moment `Audio` has one row it owes
all ten — mechanical, and not gameable by writing nine.

## Considered alternatives

- **Widen `WALK_ROOTS` to include the canonical package.** Rejected, and it stays
  rejected: `tools/_walk_roots.py` carries the reproduction — it drags 15,961
  lines of another package into the frozen baseline and turns
  `check_no_env_vars.py` red immediately (ADR-0153 dec. 1, ADR-0131 dec. 8).
- **Derive it from the host's `addons/` symlink.** Rejected by dec. 2, on the
  measurement rather than the aesthetics.
- **A `docs/EXTRACTED.tsv` register with its own guard.** Rejected: a register
  needs a generator, a checker and a staleness story, and this is a declaration
  of ~10 rows changing once per extraction. `WALK_ROOTS` is a tuple in a source
  file for the same reason.
- **Leave each instrument its own `--root` flag.** Rejected: that is the state
  that produced three copies of one path, and a flag nobody remembers to pass is
  a check that does not run. The flags remain for a package not yet declared.
- **Wire `check_debug_panel_tunables.py` too, for symmetry.** Rejected by dec. 5
  — symmetry is not a reason, and the extraction that moves the panels is better
  placed to say whether the host's panel contract still binds them.

## Consequences

- **ADR-0151's rule is mechanized across the boundary.** The guard's subject now
  reads `addons/exmateria_render, ../exmateria-sound/addons/exmateria_sound`, and
  it is green over both. Direction-tested against the **real** canonical package:
  a probe there naming `BaseDebugPanel`, `TuneField` and `DebugConfig` reports
  three lines and exits 1.
- **`Audio` gets a scorecard before its extraction finishes**, reported and not
  enforced: **10 open**, with #5 already **met** (0 cross-system reach lines) and
  #7 at 210 content-jargon lines across 82 files. Extraction #2 inherits a
  measurement rather than a blank page.
- **Goal #4's reading is now precise instead of absolute.** It used to say a root
  outside the walk means *"every guard is green because it no longer looks"*.
  With this list that is two-thirds true, so it now names the split: the two
  instruments that follow the system out, and the other 29 that do not.
- **The blindness is smaller and its remainder is legible.** `--delta` and the
  panel guard are still blind, both by a decision recorded here, and pass 8 can
  state the limit rather than reporting a clean register.
- **This is the third instrument in two days whose subject and question had
  drifted apart**, after the stale SPIR-V cache and `RESIDUE.tsv`'s roots.
  `refactor-loop.md` already carries the rule; this is the first time the fix was
  a **shared fact** rather than a printed one.
