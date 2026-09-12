#!/usr/bin/env python3
"""Render docs/adr/CLASSIFICATION.tsv as docs/adr/INDEX.md. Run from the package root.

The TSV is the source of truth (prologue pass 1). This script only formats it —
edit the TSV, re-run this, never hand-edit INDEX.md. `render()` returns the whole
file as a string and writes nothing; only `__main__` touches `docs/adr/`.

One column is NOT from the TSV: `cited_by` is MEASURED here, every run. It used to
be recorded by hand and 78 of 187 rows had drifted from a recount — 66 of them
undercounting, 38 recording a flat 0 for an ADR that is cited. A hand-kept citation
count is a data-entry job nobody does, and a wrong one is worse than none: it reads
as permission to delete. The column left the TSV on 2026-08-28.
"""
import csv, collections, os, pathlib, re

SYSTEMS = ["Battlefield", "Battle", "Character Catalogue", "Sprite Rig", "Effects",
           "UI", "Audio", "Cutscene", "Campaign", "Render", "Debug"]
OTHER = ["platform", "host"]
BUCKETS = ["engine", "seam", "content", "method"]

import sys as _sys, pathlib as _pathlib
_sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parent))
import _walk_roots  # noqa: E402

CITE_SCOPE = ("src", "assets", "addons")
CITE_EXT = {".gd", ".py", ".gdshader", ".tscn", ".cfg", ".json"}

# ⟨m⟩ is what the one MEASURED cell — `cited_by` — renders as under
# `render(measured=False)`. Everything else in this table is read from
# `CLASSIFICATION.tsv`, and the split matters because the two halves go stale for
# different reasons: the TSV half drifts when somebody edits the TSV and forgets to
# re-run this, and `cited_by` drifts when ANY commit anywhere adds or drops an
# `ADR-NNNN` mention under src/assets/addons — a comment in a shell script did it
# twice in one day (#1163), and ADR-0214's amendment records an earlier round of the
# same abort from a different cause. `check_adr_classification.py` renders BOTH ways
# and reds only on the first.
MASK = "⟨m⟩"


def cited_by():
    """{ADR number -> count of files under CITE_SCOPE carrying an ADR-NNNN mention}."""
    seen = collections.defaultdict(set)
    # Follows symlinks — see gen_adr_audit.scan's comment. The vendored audio
    # addons are a directory in one worktree and a link in the next, and a
    # link-blind walk makes this generator's committed output checkout-dependent.
    for root in CITE_SCOPE:
        for q in _walk_roots.walk_files(root):
            if any(part in (".git", "__pycache__") for part in q.parts):
                continue
            if q.suffix not in CITE_EXT:
                continue
            path = q.as_posix()
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    body = fh.read()
            except OSError:
                continue
            for num in set(re.findall(r"ADR-(\d{4})", body)):
                seen[num].add(path)
    return {n: len(v) for n, v in seen.items()}


def render(measured: bool = True) -> str:
    """The whole of INDEX.md as a string. `measured=False` renders every
    tree-measured cell as MASK and skips the walk that would fill it."""
    with open("docs/adr/CLASSIFICATION.tsv", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    CITED = cited_by() if measured else {}
    titles = {}
    for r in rows:
        p = pathlib.Path("docs/adr") / r["file"]
        t = p.read_text(encoding="utf-8")
        if t.startswith("---\n"):
            t = t.split("\n---\n", 1)[1]
        titles[r["file"]] = next(l[2:].strip() for l in t.splitlines() if l.startswith("# "))

    dup = {n for n, c in collections.Counter(r["num"] for r in rows).items() if c > 1}
    out = []
    w = out.append
    w("# ADR classification — the cold pass\n")
    w("**Generated. Do not hand-edit** — edit `CLASSIFICATION.tsv` and run")
    w("`uv run python tools/gen_adr_index.py`. Guarded by `tools/check_adr_classification.py`.\n")
    w("Prologue **pass 1** of the refactor loop (`docs/agents/refactor-loop.md`): every ADR gets a")
    w("**bucket**, an **owning system**, the ADRs it **constrains**, and a **status**. No ADR prose was")
    w("touched — rewriting happens per chunk in the loop, where the context to do it well exists.\n")
    w("**Buckets** — `engine` survives any rename and travels with its system into the addon ·")
    w("`seam` is a PSX compromise that defines where a conversion boundary goes · `content` is")
    w("FFT-specific and stays with the content pack · `method` is how the work is conducted, stays")
    w("in the host, and can be *closed* rather than superseded when the refactor ends.\n")
    w("**Span** — an ADR reaching two systems is answered three ways: `split` (the only defect),")
    w("`interface` (a seam already written down — the most valuable documents here), or `platform`")
    w("(promoted above every system).\n")
    w("`cited_by` counts files under `src/`, `assets/` and `addons/` carrying an `ADR-NNNN`")
    w("mention. It is **measured on every run**, not recorded — see this script's docstring for")
    w("what the hand-kept column was worth. `docs/` and `tests/` are deliberately outside the")
    w("scope: this number answers *what code is standing on this decision*.\n")

    w("## Totals\n")
    w("| | " + " | ".join(f"`{b}`" for b in BUCKETS) + " | **all** |")
    w("|---|" + "---|" * (len(BUCKETS) + 1))
    grid = collections.Counter((r["system"], r["bucket"]) for r in rows)
    for s in SYSTEMS + OTHER:
        tot = sum(grid[(s, b)] for b in BUCKETS)
        if not tot:
            continue
        w(f"| {s} | " + " | ".join(str(grid[(s, b)] or "·") for b in BUCKETS) + f" | **{tot}** |")
    w("| **all** | " + " | ".join(f"**{sum(1 for r in rows if r['bucket']==b)}**" for b in BUCKETS)
      + f" | **{len(rows)}** |")
    w("")

    for s in SYSTEMS + OTHER:
        sub = [r for r in rows if r["system"] == s]
        if not sub:
            continue
        w(f"## {s} — {len(sub)}\n")
        w("| ADR | bucket | span | status | cited_by | constrains |")
        w("|---|---|---|---|---|---|")
        for r in sorted(sub, key=lambda r: r["file"]):
            mark = " ⚠" if r["num"] in dup else ""
            link = f"[{r['num']}]({r['file']}){mark} {titles[r['file']]}"
            con = ", ".join(f"`{x}`" for x in r["constrains"].split(",") if x) or "—"
            if len(con) > 90:
                con = con[:88] + "…"
            st = r["status"] if r["status"] != "accepted" else "·"
            w(f"| {link} | `{r['bucket']}` | {r['span'] if r['span']!='-' else '·'} | {st} | {CITED.get(r['num'], 0) if measured else MASK} | {con} |")
            if r["note"]:
                w(f"| | | | | | {r['note']} |")
        w("")

    return "\n".join(out) + "\n"


if __name__ == "__main__":
    _t = render()
    pathlib.Path("docs/adr/INDEX.md").write_text(_t, encoding="utf-8")
    print(f"wrote docs/adr/INDEX.md — {_t.count(chr(10))} lines")
