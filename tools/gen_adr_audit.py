#!/usr/bin/env python3
"""Render docs/adr/AUDIT.md — the conformance register. Run from the package root.

INDEX.md answers *what the decisions are*. This answers *what the code did about
them*, which is a different question and the one a consolidation pass needs: an
ADR can be complete, half-landed, contradicted by the code, or simply finished
and closeable — and an ADR can itself be the thing that is wrong.

Everything measurable is measured here, every run:

  lines / amd / dec   the shape of the document — where the 44k lines actually are
  code / test / doc   files that mention `ADR-NNNN`, by where they live. `code`
                      is what is standing on the decision; `doc` is mostly other
                      ADRs citing it.
  guard               a `tools/check_*.py` that names the number — the difference
                      between a decision and an enforced one
  body                the ADR's own status marker when it disagrees with the TSV

The one column that cannot be measured is the verdict, so it is hand-kept in
`docs/adr/AUDIT.tsv` and joined here. That register is keyed `(adr, dec)`: a `*`
dec carries the ADR-level verdict, a numeric dec carries one decision's own
conformance, and `proposed_guard` is the queue of named-but-unbuilt arms that
`enforce-adr-conformance` consumes. An ADR with no row reads `unaudited`, which
is the honest default — not `complete`.

Audit prose does not live in the register. It lives in `docs/adr/audit-notes/NNNN.md`,
which is working input for that ADR's de-amendment rewrite and is deleted when the
rewrite consumes it.

`render()` returns the whole file as a string and writes nothing; only `__main__`
touches `docs/adr/`. `render(measured=False)` renders the same lines with every
tree-measured cell blanked — see MASK below.
"""
import collections, csv, os, pathlib, re, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _walk_roots  # noqa: E402

VERDICTS = {"unaudited", "complete", "half-landed", "violated", "closeable", "superseded"}

CODE = ("src", "assets", "addons")
TEST = ("tests",)
DOC = ("docs",)
TOOL = ("tools",)
EXT = {".gd", ".py", ".sh", ".md", ".json", ".gdshader", ".tscn", ".cfg", ".tsv"}
# The register is not a citation of what it registers — and counting itself makes
# this generator's own output an input, which never reaches a fixed point.
REGISTER = {"docs/adr/INDEX.md", "docs/adr/AUDIT.md",
            "docs/adr/AUDIT.tsv", "docs/adr/CLASSIFICATION.tsv"}
adr_dir = pathlib.Path("docs/adr")

# ⟨m⟩ marks a cell this generator MEASURES from OUTSIDE `docs/adr/` rather than
# reading it from `CLASSIFICATION.tsv` / `AUDIT.tsv`. `code`, `test`, `doc`, `tool`
# and `guard` are the five; `lines`, `amd` and `dec` are deliberately NOT, because
# they are measured from the ADR's own body and an author editing an ADR is already
# in `docs/adr/`.
#
# The split exists because the two halves go stale for different reasons and only
# one of them is the author's fault: the TSV half drifts when somebody edits a TSV
# and forgets to re-run this, and the measured half drifts when ANY commit anywhere
# adds or drops an `ADR-NNNN` mention (#1163 — a comment in a shell script did it
# twice in one day). `check_adr_classification.py` renders BOTH ways and reds only
# on the first. See that file for the classification.
MASK = "⟨m⟩"


def scan(roots):
    """Files under `roots` citing an ADR.

    🔴 THE WALK MUST FOLLOW SYMLINKS — `_walk_roots.walk_files`, not a bare
    `os.walk`. `addons/exmateria_sound` and `addons/exmateria_spu` are a REAL
    rsync'd directory in the canonical worktree and SYMLINKS in every worktree
    `tools/link_worktree_godot_assets.sh` builds, and `os.walk`'s default
    `followlinks=False` walks straight past a link. So this generator read a
    DIFFERENT universe per checkout and its committed output oscillated: three
    `code` counts (0085 37↔35, 0136 1↔0) flipped on nothing but the install
    method, and `check_adr_classification.py` then reported STALE AUDIT.md and
    ABORTED the suite preflight in whichever worktree ran second. The remedy is
    `_walk_roots.walk_files`'s, written for exactly this (see its docstring:
    8 vs 164 addon `.gd` on the same commit).

    WHAT THIS DOES NOT FIX, stated so the next reader does not over-trust it. The
    two addons are gitignored, so a checkout that has not installed them at all
    still counts less — following a link cannot conjure a directory that is not
    there. What it buys is agreement between the two SUPPORTED installs, rsync
    and symlink, which is the pair that was actually oscillating. A tree with no
    audio addon is already a parse-error cascade for the game (root `CLAUDE.md`),
    so it is not a state this register has to be correct in.
    """
    seen = collections.defaultdict(set)
    for root in roots:
        for q in _walk_roots.walk_files(root):
            path = q.as_posix()
            f = q.name
            if any(part in (".git", "__pycache__") for part in q.parts):
                continue
            if q.suffix not in EXT or path in REGISTER:
                continue
            # An ADR citing itself is not a citation.
            self_num = f[:4] if path.startswith("docs/adr/") and re.match(r"\d{4}-", f) else None
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    body = fh.read()
            except OSError:
                continue
            for num in set(re.findall(r"ADR-(\d{4})", body)):
                if num != self_num:
                    seen[num].add(path)
    return seen



def render(measured: bool = True) -> str:
    """The whole of AUDIT.md as a string. `measured=False` renders every cell
    measured from outside `docs/adr/` as MASK and skips the walks that fill them."""
    if measured:
        code, test, doc, tool = (scan(r) for r in (CODE, TEST, DOC, TOOL))
    else:
        code = test = doc = tool = collections.defaultdict(set)

    # These enforce corpus-wide hygiene and name numbers only in prose ABOUT the
    # corpus — counting them would credit every renumbered ADR with a guard it has not
    # got. check_adr_shape.py is the sharpest case: it names ADR-0085 in its docstring
    # as the EXAMPLE of the shape it forbids, and 0085 is on its BURN_DOWN, i.e. the
    # one set the rule does not yet enforce. Crediting it a guard is inverted twice.
    NOT_A_GUARD = {
        "check_adr_anchors.py",
        "check_adr_classification.py",
        "check_adr_shape.py",
    }
    guards = collections.defaultdict(set)
    for p in (sorted(pathlib.Path("tools").glob("check_*.py")) if measured else ()):
        if p.name in NOT_A_GUARD:
            continue
        body = p.read_text(encoding="utf-8", errors="replace")
        for num in set(re.findall(r"ADR-(\d{4})", body)):
            guards[num].add(p.name)

    with open("docs/adr/CLASSIFICATION.tsv", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))

    # AUDIT.tsv is keyed (adr, dec). A `*` dec is the ADR-level verdict; a numeric
    # dec is one decision's own conformance. Prose does NOT live here — the audit
    # working notes are per-ADR files under docs/adr/audit-notes/, which each ADR's
    # de-amendment rewrite consumes and then deletes.
    verdicts = {}
    dec_status = collections.defaultdict(dict)      # num -> {dec: status}
    arms = collections.defaultdict(list)            # num -> [proposed guard arm]
    tsv = adr_dir / "AUDIT.tsv"
    if tsv.exists():
        with open(tsv, encoding="utf-8") as fh:
            _audit_rows = list(csv.DictReader(fh, delimiter="\t"))
        for r in _audit_rows:
            if r["dec"] == "*":
                verdicts[r["adr"]] = r["status"]
            else:
                dec_status[r["adr"]][r["dec"]] = r["status"]
            if r.get("proposed_guard"):
                arms[r["adr"]].append(r["proposed_guard"])

    AMD = re.compile(r"^#{2,4}\s*(?:\w+\s+)?(?:Amendment|Addendum)\b", re.I)
    shape = {}
    for r in rows:
        body = (adr_dir / r["file"]).read_text(encoding="utf-8", errors="replace")
        lines = body.count("\n") + 1
        amd = sum(1 for l in body.splitlines() if AMD.match(l))
        in_dec, dec = False, set()
        for l in body.splitlines():
            h = re.match(r"^##(?!#)\s*(.*)", l)
            if h:
                in_dec = bool(re.match(r"decisions?\b", h.group(1).strip(), re.I))
            m = re.match(r"^(?:#{2,5}\s*|\*\*|\s{0,3})(\d+)\s*[.)·]", l)
            if m and in_dec:
                dec.add(m.group(1))
        marker = ""
        head = "\n".join(body.splitlines()[:40])
        # A STATUS BANNER, not the word: ADR-0068 supersedes its own decisions in
        # a sentence, and matching that credits the ADR itself with being retired.
        if re.search(r"^>?\s*(?:\*\*)?(?:Status:\s*)?(?:PARTLY\s+)?SUPERSEDED\b",
                     head, re.I | re.M):
            marker = "superseded"
        shape[r["num"]] = (lines, amd, len(dec), marker)

    out = []
    w = out.append
    w("# ADR conformance audit\n")
    w("**Generated. Do not hand-edit** — put verdicts in `AUDIT.tsv` and run")
    w("`uv run python tools/gen_adr_audit.py`. Guarded by `tools/check_adr_classification.py`.\n")
    w("`INDEX.md` says what the decisions are. This says what the code did about them.\n")
    w("**Duplicate prose is not the measure — superseded prose is.** An earlier pass measured")
    w("exact duplicate paragraphs at 0.01% and concluded there was nothing to fold. That premise")
    w("was wrong: two paragraphs stating opposite things about one decision are not duplicates by")
    w("any string measure, and only one of them is current. The corpus is **50,503 lines across")
    w("189 ADRs**, of which **65 carry an amendment and those 65 hold 24,417 lines** — ADR-0085 is")
    w("a 39-line decision under 2,947 lines of 27 successive positions, one of which reverses")
    w("decision 3. The fold buys the *now*: what should be true, why, and what was rejected.")
    w("`adr-states-the-now` is the pass that does it; `check_adr_shape.py` is the ratchet that")
    w("keeps it, capping an ADR at one dated update.\n")
    w("**Columns.** `lines` / `amd` / `dec` are the document's shape — a numbered Decision")
    w("section is what makes `ADR-NNNN dec. N` citations checkable, so `dec 0` on a cited ADR")
    w("is itself a finding. `code` / `test` / `doc` / `tool` count files mentioning the number,")
    w("by where they live; an ADR citing itself does not count. `guard` names a")
    w("`tools/check_*.py` that mentions the number — the difference between a decision and an")
    w("enforced one, and `arms` counts guards that are *proposed but unbuilt*. `body` shows")
    w("the ADR's own status marker when the TSV disagrees.\n")
    w("**Verdicts** — `complete` (the code does this and something holds it there) ·")
    w("`half-landed` (partly built, or built with no guard) · `violated` (the code contradicts")
    w("it) · `closeable` (done and no longer constraining — retire rather than delete) ·")
    w("`superseded` · `unaudited` (nobody has looked; the default, and it means nothing")
    w("stronger than that).\n")

    tally = collections.Counter(verdicts.get(r["num"], "unaudited") for r in rows)
    w("| verdict | ADRs |")
    w("|---|---:|")
    for v in ("complete", "half-landed", "violated", "closeable", "superseded", "unaudited"):
        w(f"| {v} | {tally[v]} |")
    w(f"| **all** | **{len(rows)}** |")
    w("")

    no_guard_cited = sum(1 for r in rows if not guards[r["num"]] and len(code[r["num"]]) >= 5)
    _named = sum(1 for r in rows if guards[r['num']]) if measured else MASK
    _five = no_guard_cited if measured else MASK
    w(f"{_named} of {len(rows)} ADRs are named by a "
      f"`tools/check_*.py`. {_five} are cited by five or more code files with no "
      "guard at all — that set is where a mechanized arm buys the most.\n")

    SYSTEMS = ["Battlefield", "Battle", "Character Catalogue", "Sprite Rig", "Effects",
               "UI", "Audio", "Cutscene", "Campaign", "Render", "Debug", "platform", "host"]
    for s in SYSTEMS:
        sub = [r for r in rows if r["system"] == s]
        if not sub:
            continue
        w(f"## {s} — {len(sub)}\n")
        w("| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |")
        w("|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|")
        for r in sorted(sub, key=lambda r: r["file"]):
            n = r["num"]
            lines, amd, dec, marker = shape[n]
            g = ", ".join(sorted(x[len("check_"):-len(".py")] for x in guards[n])) or "—"
            if len(g) > 46:
                g = g[:44] + "…"
            if not measured:
                g = MASK
            body = marker if marker and marker != r["status"] else "·"
            v = verdicts.get(n, "unaudited")
            w(f"| [{n}]({r['file']}) | `{r['bucket']}` | {lines} | {amd or '·'} | {dec or '·'} "
              f"| {(len(code[n]) or '·') if measured else MASK}"
              f" | {(len(test[n]) or '·') if measured else MASK}"
              f" | {(len(doc[n]) or '·') if measured else MASK} "
              f"| {(len(tool[n]) or '·') if measured else MASK} | {g} "
              f"| {len(arms[n]) or '·'} | {body} | {v} |")
            if n in verdicts:
                pending = collections.Counter(dec_status[n].values()).get("unreviewed", 0)
                bits = [f"[audit notes](audit-notes/{n}.md)"]
                if dec_status[n]:
                    bits.append(f"{len(dec_status[n])} decisions, {pending} not yet graded"
                                if pending else f"{len(dec_status[n])} decisions graded")
                if arms[n]:
                    joined = "; ".join(arms[n]).replace("|", "\\|")
                    bits.append(f"**{len(arms[n])} proposed arm(s)**: " + joined[:180])
                w(f"| | | | | | | | | | | | | {' · '.join(bits)} |")
        w("")

    return "\n".join(out) + "\n"


if __name__ == "__main__":
    _t = render()
    pathlib.Path("docs/adr/AUDIT.md").write_text(_t, encoding="utf-8")
    print(f"wrote docs/adr/AUDIT.md — {_t.count(chr(10))} lines")
