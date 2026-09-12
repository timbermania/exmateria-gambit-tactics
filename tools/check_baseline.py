#!/usr/bin/env python3
"""Guard `docs/BASELINE.tsv` — the frozen opening reading of the refactor series.

ADR-0145 (prologue pass 5) publishes one reading against a stated code commit
AND a stated classifier revision, and freezes it. Every later reading is scored
against this file, so the two failures that matter are a **silent edit** and a
**silent schema drift**, and this guard exists for exactly those two.

    python3 tools/check_baseline.py            # guard — structure, freeze, arithmetic
    python3 tools/check_baseline.py --delta    # baseline -> HEAD, per system (~90 s)

The guard itself does not measure anything and takes under a second. `--delta`
re-runs `touch_matrix.py`, whose walk costs about 80 seconds; that is loop pass
9's reading, run deliberately, not something a guard loop should pay for.

WHAT IT CHECKS

  1. FREEZE. `# data_sha256` covers every non-`#` line. Change a number without
     changing the checksum and this goes red. Changing both is a deliberate act
     and ADR-0131 dec. 6 says what it costs — five silent baseline moves in five
     sessions is the failure that ADR exists to prevent.

  2. SCHEMA. The `system` rows must be exactly `classify_blueprint.SYSTEMS` and
     the `other` rows exactly its `OTHER` — no more, no fewer. Adding, removing
     or renaming a bucket therefore cannot land without a decision about what
     happens to the baseline it invalidates.

  3. ARITHMETIC. Shader counts cannot exceed file counts; `sum(reaches_out)`
     must equal `sum(reaches_in)`, because every cross-system reach is one edge
     read from both ends.

  4. UNITS. Only `system` rows carry reaches. `other` buckets are not systems
     (ADR-0131 dec. 2) and `extracted` rows are read from another package where
     this walk does not run, so both carry `.` — never `0`, which would read as
     a measured zero.

WHAT IT DOES NOT CHECK — and cannot. It does not re-measure. The tree moves
every day and the baseline does not; a guard that re-ran the instruments and
compared would be red permanently and would be deleted within a week. `--delta`
is that comparison, run on demand, reported and never asserted.

THE `extracted` ROW IS A READING NOW (ADR-0153 dec. 1). It used to be a static
number — `exmateria_sound 152 / 15,961`, written once and never re-measured —
and a static row cannot report a move. Extraction #2 relocates ~1,530 lines into
that package, and against a static row `--delta` would print `Audio -1,530` with
NO COUNTERPART: precisely the *"a system extracted by deletion"* reading
ADR-0131 dec. 7 was written to prevent. So `--delta` takes a second walk, over
`_walk_roots.EXTRACTED`, and prints it beside the systems with its own
total and a Δ against the frozen row.

That walk is NOT a walk root. `WALK_ROOTS` is unchanged, dec. 1 rejects all three
ways of widening it, and this reading is the alternative to them rather than a
step toward them. It does not join the freeze check and it does not join the
schema check — `BASELINE.tsv` does not move.

AND THE SUBTRACTION IS PRINTED, NOT ASSERTED. dec. 1 says *reported, never
asserted*; dec. 9 asserts `Audio -N` = `extracted +N`. Both are right about
different things: the equality holds ACROSS THE MOVE COMMIT and not across an
arbitrary baseline->HEAD interval, so a hard assertion would be false in general
and deleted within a week. The `CONSERVATION` line prints the two Δs and their
sum so the discrepancy is one glance rather than mental arithmetic, and a human
reads it at the move.
"""
import sys, pathlib, hashlib, io, contextlib, json, collections, subprocess

TSV = pathlib.Path("docs/BASELINE.tsv")
KIND_REACHLESS = ("other", "extracted")
bad = []


def load():
    text = TSV.read_text(encoding="utf-8")
    meta, data = {}, []
    for ln in text.splitlines():
        if ln.startswith("#"):
            parts = ln.lstrip("#").strip().split("\t")
            if len(parts) >= 2:
                meta.setdefault(parts[0].strip(), parts[1].strip())
            continue
        data.append(ln)
    return meta, data


def cbmod():
    """classify_blueprint ends in sys.exit(); importing it raises SystemExit."""
    ns = {"__name__": "cbmod"}
    with contextlib.redirect_stdout(io.StringIO()):
        try:
            exec(TSV.parent.parent.joinpath("tools/classify_blueprint.py").read_text(), ns)
        except SystemExit:
            pass
    return ns


meta, data = load()
if not data:
    print("BASELINE.tsv has no data rows")
    sys.exit(1)

# --- 1. freeze ------------------------------------------------------------
for k in ("code_commit", "classifier_rev", "taken_on", "data_sha256"):
    if k not in meta:
        bad.append(f"missing `# {k}` — a reading without both revisions is unquotable (ADR-0131 dec. 6)")
got = hashlib.sha256(("\n".join(data) + "\n").encode()).hexdigest()
if meta.get("data_sha256") and got != meta["data_sha256"]:
    bad.append(f"FROZEN data changed: sha256 is {got}, header says {meta['data_sha256']}\n"
               f"      The baseline moved. That needs an ADR (ADR-0131 dec. 6), not an edit.")

# --- 2. schema ------------------------------------------------------------
head, rows = data[0].split("\t"), [r.split("\t") for r in data[1:] if r.strip()]
EXPECT = ["bucket", "kind", "files", "lines", "shader_files", "shader_lines",
          "reaches_out", "reaches_in"]
if head != EXPECT:
    bad.append(f"header is {head}, expected {EXPECT}")
    print("\n".join(bad))
    sys.exit(1)

ns = cbmod()
by_kind = collections.defaultdict(list)
for r in rows:
    if len(r) != len(EXPECT):
        bad.append(f"row has {len(r)} fields, expected {len(EXPECT)}: {r}")
        continue
    by_kind[r[1]].append(r[0])

for kind, expected in (("system", ns["SYSTEMS"]), ("other", ns["OTHER"])):
    have, want = sorted(by_kind.get(kind, [])), sorted(expected)
    if have != want:
        miss, extra = set(want) - set(have), set(have) - set(want)
        bad.append(f"`{kind}` rows do not match classify_blueprint: "
                   + (f"missing {sorted(miss)} " if miss else "")
                   + (f"unexpected {sorted(extra)}" if extra else "")
                   + "\n      A bucket changed under a frozen baseline. Decide what that does to the series.")

# --- 3/4. arithmetic and units -------------------------------------------
tot_out = tot_in = 0
for r in rows:
    if len(r) != len(EXPECT):
        continue
    b, kind = r[0], r[1]
    try:
        f, l, sf, sl = (int(x) for x in r[2:6])
    except ValueError:
        bad.append(f"{b}: non-integer count in {r[2:6]}")
        continue
    if sf > f:
        bad.append(f"{b}: {sf} shader files of {f} files")
    if sl > l:
        bad.append(f"{b}: {sl} shader lines of {l} lines")
    if kind in KIND_REACHLESS:
        if r[6] != "." or r[7] != ".":
            bad.append(f"{b}: kind `{kind}` carries reaches {r[6]}/{r[7]}; must be `.`, "
                       f"which is 'not measured' — `0` would read as 'measured, and clean'")
    elif kind == "system":
        try:
            tot_out += int(r[6]); tot_in += int(r[7])
        except ValueError:
            bad.append(f"{b}: non-integer reach count {r[6]}/{r[7]}")
    else:
        bad.append(f"{b}: unknown kind `{kind}` (system|other|extracted)")
if tot_out != tot_in:
    bad.append(f"reaches_out sums to {tot_out} but reaches_in to {tot_in}; "
               f"every cross-system reach is one edge read from both ends")

if bad:
    print("BASELINE.tsv — %d problem(s):\n" % len(bad))
    for b in bad:
        print("  *", b)
    sys.exit(1)

print(f"BASELINE.tsv OK — {len(rows)} rows, frozen at {meta['code_commit']} "
      f"(classifier {meta['classifier_rev']}), {tot_out} cross-system reaches balanced both ways.")

# --- --delta --------------------------------------------------------------
if "--delta" not in sys.argv:
    sys.exit(0)

base = {r[0]: r for r in rows}
F = collections.Counter(); L = collections.Counter()
for q in ns["walk"]():
    b = ns["classify"](str(q).replace("\\", "/"))
    F[b] += 1
    L[b] += len(q.read_text(encoding="utf-8", errors="replace").splitlines())

subprocess.run([sys.executable, "tools/touch_matrix.py"], stdout=subprocess.DEVNULL, check=True)
cache = json.load(open("tools/.touch_cache.json"))
OUT = collections.Counter(); IN = collections.Counter()
for k, v in cache.items():
    a, b = k.split("||")
    if a in ns["SYSTEMS"] and b in ns["SYSTEMS"]:
        n = sum(len(x[3]) for x in v)
        OUT[a] += n; IN[b] += n

head_sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
print(f"\nDELTA  baseline {meta['code_commit']} -> HEAD {head_sha}   (+ is growth, not progress)")
print(f"{'bucket':<22}{'lines':>10}{'Δ':>9}{'out':>7}{'Δ':>7}{'in':>7}{'Δ':>7}")
for b in ns["SYSTEMS"]:
    r = base.get(b)
    if not r:
        continue
    print(f"{b:<22}{L[b]:>10}{L[b]-int(r[3]):>+9}{OUT[b]:>7}{OUT[b]-int(r[6]):>+7}{IN[b]:>7}{IN[b]-int(r[7]):>+7}")
tl = sum(L[b] for b in ns["SYSTEMS"]); bl = sum(int(base[b][3]) for b in ns["SYSTEMS"] if b in base)
print(f"{'TOTAL (systems)':<22}{tl:>10}{tl-bl:>+9}{sum(OUT.values()):>7}"
      f"{sum(OUT.values())-tot_out:>+7}{sum(IN.values()):>7}{sum(IN.values())-tot_in:>+7}")
# --- the extracted packages, RE-MEASURED (ADR-0153 dec. 1) ----------------
# A second walk, deliberately not a walk root. Same suffix and line rules as
# classify_blueprint's walk, so the two readings are comparable; run over
# `_walk_roots.EXTRACTED`, the one declaration every blind instrument shares.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _walk_roots

SRC_SUF, SH_SUF = ns["SOURCE_SUFFIXES"], ns["SHADER_SUFFIXES"]


def measure(root):
    f = l = sf = sl = 0
    for q in sorted(root.rglob("*")):
        if q.is_file() and q.suffix in SRC_SUF:
            n = len(q.read_text(encoding="utf-8", errors="replace").splitlines())
            f += 1; l += n
            if q.suffix in SH_SUF:
                sf += 1; sl += n
    return f, l, sf, sl


# TWO KEYS, AND THEY ARE NOT THE SAME KEY. `BASELINE.tsv` keys its `extracted`
# row by the PACKAGE directory (`exmateria_sound`); `_walk_roots.EXTRACTED` names
# the SYSTEM that went there (`Audio`). Matching on the package name is what makes
# the frozen row findable; carrying the system name is what lets the conservation
# line below pair a system's Δ with its package's Δ without guessing. Before the
# table had a `system` field there was no way to know which system had left, and
# the guess that filled the gap picked the wrong one — see the note there.
frozen_ext = {r[0]: r for r in rows if r[1] == "extracted"}
# GROUPED BY PACKAGE, NOT BY ROW, and the grouping is the whole point. Two systems
# may be declared into ONE package — nothing forbids it and extraction #3 may do
# it — and a per-row loop measures that package twice: `ext_dl` doubles while the
# TOTAL line, keyed by package, does not. The two disagree by exactly the amount
# nobody would look at. Found by the second-system arm of the collision harness,
# which was aimed at the residue caveat and hit this instead.
by_pkg = {}
for e in _walk_roots.extracted_roots():
    by_pkg.setdefault(e.path, []).append(e.system)
ext_now, ext_dl, per_system, shared = {}, 0, {}, {}
print("\nEXTRACTED  re-measured over _walk_roots.EXTRACTED — the walk REPORTS these, it does not enter them")
print(f"{'system':<10}{'package':<22}{'files':>7}{'Δ':>7}{'lines':>10}{'Δ':>9}{'out':>7}{'in':>7}")
for root, systems in by_pkg.items():
    pkg = root.name
    # The column is 10 wide and `Audio+Render` is 12, which silently eats the
    # separator and welds the system onto the package name. A count plus a
    # continuation line keeps the table readable at any number of systems.
    label = systems[0] if len(systems) == 1 else f"{len(systems)} systems"
    f, l, sf, sl = measure(root)
    ext_now[pkg] = (f, l, sf, sl)
    fr = frozen_ext.get(pkg)
    if fr:
        df, dl = f - int(fr[2]), l - int(fr[3])
        ext_dl += dl
        # A package's Δ is attributable to ONE system or to none. With two, dec.
        # 9's per-system equality has no left-hand side — the package cannot say
        # which system's lines arrived — so it is refused below rather than
        # printed twice or split on a guess.
        if len(systems) == 1:
            per_system[systems[0]] = per_system.get(systems[0], 0) + dl
        else:
            shared[pkg] = (systems, dl)
        # `.` for reaches, never `0`: this walk does not measure reaches at all,
        # and a `0` would read as "measured, and clean" (check 4 above).
        print(f"{label:<10}{pkg:<22}{f:>7}{df:>+7}{l:>10}{dl:>+9}{'.':>7}{'.':>7}")
        if len(systems) > 1:
            print(f"{'':<10}  received: {', '.join(systems)}")
    else:
        print(f"{label:<10}{pkg:<22}{f:>7}{'  n/a':>7}{l:>10}{'      n/a':>9}{'.':>7}{'.':>7}")
        print(f"{'':<32}  no `extracted` row in the frozen baseline — Δ unavailable")
for pkg in frozen_ext:
    if pkg not in ext_now:
        print(f"{'':<10}{pkg:<22}  frozen row present but not in _walk_roots.EXTRACTED "
              f"— not re-measured")
if ext_now:
    tf = sum(v[0] for v in ext_now.values()); tll = sum(v[1] for v in ext_now.values())
    print(f"{'':<10}{'TOTAL (extracted)':<22}{tf:>7}{'':>7}{tll:>10}{ext_dl:>+9}{'.':>7}{'.':>7}")

# --- conservation, PRINTED (ADR-0153 dec. 9, and dec. 1 on why not asserted) --
# NO GUESS ABOUT WHICH SYSTEM IS EXTRACTING. An earlier draft paired the
# `extracted` Δ with "the largest falling system" and, run at extraction #2's
# pass 6, that picked `Render -491` — extraction #1's within-walk relocation,
# which has nothing to do with the package. A heuristic that is right only at
# the commit you were thinking of is a heuristic that lies at every other one.
#
# The quantity that left the walk is the systems TOTAL Δ; the quantity that
# arrived is the extracted Δ; their sum is the net change in the whole measured
# universe, and for a pure relocation it is 0. That needs no guess and is true
# for every extraction.
#
# AND dec. 9's PER-SYSTEM form no longer needs one either. `_walk_roots.EXTRACTED`
# names the system that went to each package (ADR-0155 / #411), so the pairing is
# READ from the table instead of inferred. `--conserve <System>` survives as an
# OVERRIDE — for asking the question about a system the table does not name — and
# is no longer how the per-system line is obtained. #410 runs a bare `--delta`.
if ext_now:
    print(f"\nCONSERVATION   systems TOTAL Δ {tl - bl:+}   +   extracted Δ {ext_dl:+}"
          f"   =   {tl - bl + ext_dl:+}")
    deltas = {b: L[b] - int(base[b][3]) for b in ns["SYSTEMS"] if b in base}
    want = None
    for i, a in enumerate(sys.argv):
        if a == "--conserve" and i + 1 < len(sys.argv):
            want = sys.argv[i + 1]
    if want is not None:
        if want in deltas:
            print(f"               {want} Δ {deltas[want]:+}   +   extracted Δ {ext_dl:+}"
                  f"   =   {deltas[want] + ext_dl:+}      (--conserve {want}, OVERRIDE)")
        else:
            print(f"               --conserve {want!r} is not one of "
                  f"{', '.join(ns['SYSTEMS'])}")
    else:
        for s, dl in sorted(per_system.items()):
            if s in deltas:
                print(f"               {s} Δ {deltas[s]:+}   +   its package Δ {dl:+}"
                      f"   =   {deltas[s] + dl:+}      (paired by _walk_roots.EXTRACTED)")
            else:
                print(f"               {s} is named by _walk_roots.EXTRACTED but is not a "
                      f"blueprint system — no Δ to pair; package Δ {dl:+}")
        for pkg, (systems, dl) in sorted(shared.items()):
            print(f"               {pkg} received {' and '.join(systems)} — dec. 9's "
                  f"per-system form is UNDEFINED here: a package Δ of {dl:+} cannot say "
                  f"which system's lines arrived. Use `--conserve <System>` to ask about "
                  f"one, knowing the package half covers both.")
    print("  A pure relocation reads 0: every line that left arrived in the package.")
    print("  This is PRINTED, never asserted. The equality holds across the MOVE COMMIT, not")
    print("  across an arbitrary baseline->HEAD interval — every unrelated edit in between")
    print("  lands in it — so a guard on it would be false in general (dec. 1 vs dec. 9).")
    print("  AUTHORED lines are not part of this subtraction: the host adapter and the")
    print("  un-inherited panel's widget helpers are additions on each side, and folding")
    print("  them in would hide exactly the discrepancy this line exists to catch (dec. 9).")

# ADR-0148 dec. 1: ADR-0145 dec. 5's REACH half was a caveat in prose, and a caveat
# in prose is exactly what ADR-0145 dec. 1 found moves without code changing. It is a
# READING now. Reaches into `addons/exmateria_sound/` are counted NOWHERE — the walk
# excludes it because ADR-0131 dec. 8 reads that row from the canonical
# `exmateria-sound/` package, and walking the host's drifted copy (#326) would
# double-count it. Every extraction hands the series a reach fall it did not earn, so
# the size of the unearned part is printed rather than described. Reported, never
# asserted (ADR-0145 dec. 4).
import collections as _c
_ext = _c.Counter()
for _p in ns["walk"]():
    _n = sum(1 for _l in _p.read_text(errors="replace").splitlines()
             if "addons/exmateria_sound" in _l.split("#", 1)[0])
    if _n:
        _b = ns["classify"](_p.as_posix())
        _ext[_b if isinstance(_b, str) else "UNCLASSIFIED"] += _n
print(f"\nUNCOUNTED — lines reaching the extracted addons/exmateria_sound/: {sum(_ext.values())}"
      f"  ({', '.join(f'{k} {v}' for k, v in _ext.most_common())})")
print("The reach count is a FLOOR (ADR-0131 dec. 6) and it does not see these\n"
      "(ADR-0145 dec. 5 / ADR-0148 dec. 1). A fall is not automatically progress.")
