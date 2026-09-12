# The test instrument

**Test kind**:
What a test *needs in order to run*, and therefore what it costs. One of six,
declared in the file's own header as `# test-kind: <kind>[ lane-pinned]` and
enforced by `tools/check_test_charter.py` (clause 1). The six form a **ladder**,
cheapest last, and moving a test down it is the audit verdict **demote**:
`gpu` (needs a Vulkan device or the compute pipeline) →
`render` (needs the 4.8 fork's engine-fold compositor and a real frame) →
`logic` (needs a Godot boot but asserts nothing about pixels) →
`static-guard` (needs no Godot at all; a `tools/check_*.py` in the pre-flight).
Two rungs sit off that line rather than on it:
`stranger-rig` (addon-owned, run by `tests/stranger/<addon>/run.sh` against a
staged throwaway project, never by the runner's array) and
`perf` (exists to measure wall clock, and is therefore the one kind exempt from
[the charter](../TEST-CHARTER.md)'s clause 14).
The word is *kind*, never *tier* — **Platform tier** is already this package's
term for the addon-extraction axis and the two have nothing to do with each other.
_Avoid_: reading a kind as a quality grade (a `gpu` test is not a worse test, it
is a more expensive one); treating `static-guard` as "not a real test" — ~25 of
them run in the pre-flight and they are the cheapest coverage in the package.

**Lane-pinned**:
A modifier on any kind, not a kind of its own: this test runs in
`run_tests_parallel.py`'s `SEQUENTIAL_LANE` instead of the parallel pool, because
it was **measured** to be unstable under concurrent load. The lane's one standing
entry carries the shape the evidence must take — *20/20 PASS idle, 5 FAIL in 30
starts under an N=8 mixed load* — because a pin without a measurement is a real
bug refiled as flakiness. A `perf` test is lane-pinned automatically: a real-time
measurement taken under N=8 load is not a measurement.
_Avoid_: pinning a test to make a red go away; treating a re-run that passes as
evidence of flakiness (it is evidence of nothing — two runs' FAIL sets in this
package have had *zero* overlap).

**Seeded break**:
The specific change that makes a given test go red, recorded in the test as
`# seeded-break: <what to break>` (charter clause 10). It is the answer to *can
this test fail at all* — a question this package has had to ask by hand more than
once, and each time the answer was no: #421's guard could not fail because
`EditorImportPlugin.new()` is null outside an editor, and the scene passed
regardless. A seeded break is also the currency of a **delete**: a test may only
be removed once some *other* test is shown to red on the same seeded break, and
that other test is its **survivor**.
_Avoid_: recording a break that reds the test by making it *error* rather than
*fail* — a parse error reds everything and proves nothing about this test's
assertions.

**Audit verdict**:
The outcome of one iteration of `.claude/skills/test-audit-loop` against one test,
recorded in `docs/TEST-AUDIT-REGISTER.tsv`. Seven: **keep** (audited, nothing to
change), **speed** (cheaper, same kind), **demote** (moved down the kind ladder),
**merge** (folded into a twin that shares its setup), **delete** (removed, with a
named survivor), **flaky** (measured unstable, so lane-pinned), **red** (already
failing on trunk — recorded and left alone, because fixing the game is not this
loop's job). Distinct from a **test verdict**, which is what `tests/lib/verdict.sh`
scores a *run* as (PASS / FAIL / HUNG / TIMEOUT / CRASHED / NOT_A_TEST /
NO_VERDICT / THREW).
_Avoid_: using the word "verdict" unqualified in a test-audit context — the two
registers answer different questions and share the noun.

**Closure overlap (of two tests)**:
The Jaccard similarity of two tests' static closures at depth 3, computed by
`tools/seed_test_audit_register.py` over `closure.py`'s seven edges. It orders the
audit register, because the pairs that load the same files are the mechanically
derivable **merge** candidates — and merging is the only lever that reduces the
process count, which is the number that makes the suite expensive.
_Avoid_: reading a high overlap as a verdict. Two tests can load every file in
common and assert on different halves of it; overlap decides what the audit reads
first, never what it concludes.
