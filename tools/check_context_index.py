#!/usr/bin/env python3
"""CONTEXT.md is generated from docs/context/, and a term is defined once.

The vocabulary used to be one 9,001-line file. Splitting it into clusters buys
nothing if the index drifts from the prose, or if two clusters both define the
same term — a term that resolves two ways is exactly the ambiguity the split
was meant to remove.

Three checks:
  STALE INDEX     — CONTEXT.md is not what the generator produces
  DUPLICATE TERM  — two cluster files define the same term
  ORPHAN CLUSTER  — a file in docs/context/ the index does not name
  BARE ANCHOR     — a `](#slug)` link, which the split turned into a file
  BROKEN LINK     — a relative link out of a cluster that does not land
  DEAD OUTBOUND   — a relative link in the generated CONTEXT.md that does not land
  DEAD FRAGMENT   — a `CONTEXT.md#slug` reference from ANYWHERE in the package;
                    the index has no per-term headings, so the fragment is dead
  DEAD INBOUND    — a link INTO the vocabulary, from outside it, that does not land

Run from the package root.  Exit 0 = clean.
"""
import collections, importlib.util, pathlib, sys

spec = importlib.util.spec_from_file_location("gen", "tools/gen_context_index.py")
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

fail = []
ctx = pathlib.Path("docs/context")

current = pathlib.Path("CONTEXT.md").read_text(encoding="utf-8")
if current != gen.render():
    fail.append("STALE INDEX — CONTEXT.md is not the generator's output; run "
                "`uv run python tools/gen_context_index.py` and commit the result")

owner = collections.defaultdict(list)
named = set()
for p, title, terms, _ in gen.clusters():
    named.add(p)
    for t in terms:
        owner[t.lower()].append(p.name)
for t, ps in sorted(owner.items()):
    if len(set(ps)) > 1:
        fail.append(f"DUPLICATE TERM — {t!r} is defined in {', '.join(sorted(set(ps)))}")

for p in sorted(ctx.glob("*.md")):
    if p not in named:
        fail.append(f"ORPHAN CLUSTER — {p} is not named by the index "
                    "(cluster files must be `NN-slug.md`)")

# Relative links out of a cluster must land. The split turned 841 intra-document
# `](#slug)` anchors into cross-file links; a bare `#anchor` no longer resolves to
# anything, because the cluster heading it named is now a FILE.
import re

for p in sorted(ctx.glob("*.md")):
    body = p.read_text(encoding="utf-8")
    for m in re.finditer(r"\]\(([^)\s]+)\)", body):
        tgt = m.group(1)
        if tgt.startswith(("http://", "https://", "mailto:")):
            continue
        if tgt == "#TBD":
            continue                      # deliberate placeholder, pre-dates the split
        if tgt.startswith("#"):
            fail.append(f"BARE ANCHOR — {p}: `{tgt}` names a heading that is now a file")
            continue
        if not (p.parent / tgt.split("#")[0]).exists():
            fail.append(f"BROKEN LINK — {p} -> {tgt}")

# --- OUTBOUND from the generated index. --------------------------------------
# CONTEXT.md is hoisted OUT of docs/context/ to the package root, so every
# relative link in it has been re-expressed by `gen.rehome()`. Nothing else here
# checks that the re-expression lands: the arm above reads the CLUSTERS, where
# `../adr/…` is correct, and the inbound arm below only follows links INTO the
# vocabulary. So 31 links pointing at a repo-root `adr/` that has never existed
# sat in this file with every check green (#1096, #1097).
n_outbound = 0
for m in re.finditer(r"\]\(([^)\s]+)\)", current):
    tgt = m.group(1)
    if tgt.startswith(("http://", "https://", "mailto:", "#")):
        continue
    n_outbound += 1
    if not pathlib.Path(tgt.split("#")[0]).exists():
        fail.append(f"DEAD OUTBOUND — CONTEXT.md -> {tgt}")

# --- INBOUND: links INTO the vocabulary, from the rest of the package. --------
# The split moved every cluster heading into its own file, which killed 114
# `CONTEXT.md#cluster-slug` references in one commit and reported nothing — the
# arms above only look at links leaving docs/context/. These two look the other
# way. A dead fragment is unconditional: CONTEXT.md is a generated INDEX whose
# only headings are its own two, so no `#term` fragment can ever resolve there.
SCAN = (".md", ".gd", ".py", ".sh", ".tscn", ".gdshader")
ctx_abs = ctx.resolve()
index_abs = pathlib.Path("CONTEXT.md").resolve()
n_inbound = 0
for p in sorted(pathlib.Path(".").rglob("*")):
    if p.suffix not in SCAN or ctx in p.parents or ".git" in p.parts:
        continue
    if p == pathlib.Path(__file__).relative_to(pathlib.Path.cwd()):
        continue  # this file SPELLS the bad forms it looks for, in prose
    try:
        body = p.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    # Same trap as the spelling-based match below: from docs/adr/ a cluster link
    # reads `../context/NN-…`. A fast-out keyed on "docs/context/" skipped 48 of
    # the 218 inbound links, silently.
    if "CONTEXT.md" not in body and "context/" not in body:
        continue
    for ln, line in enumerate(body.splitlines(), 1):
        for m in re.finditer(r"CONTEXT\.md#([A-Za-z0-9_-]+)", line):
            fail.append(f"DEAD FRAGMENT — {p}:{ln}: `CONTEXT.md#{m.group(1)}` "
                        "— name the cluster file under docs/context/ instead")
        for m in re.finditer(r"\]\(([^)\s]+)\)", line):
            tgt = m.group(1)
            if tgt.startswith(("http://", "https://", "mailto:")):
                continue
            # Decide by where the link LANDS, not by how it is spelled: from
            # docs/adr/ a cluster link reads `../context/NN-…`, which contains
            # neither "CONTEXT.md" nor "docs/context/".
            dest = (p.parent / tgt.split("#")[0]).resolve()
            if dest != index_abs and ctx_abs not in dest.parents:
                continue
            n_inbound += 1
            if not dest.exists():
                fail.append(f"DEAD INBOUND — {p}:{ln} -> {tgt}")

if fail:
    print(f"check_context_index: {len(fail)} problem(s)")
    for m in fail:
        print("  " + m)
    sys.exit(1)
print(f"check_context_index: OK — {len(named)} clusters, {len(owner)} terms, "
      f"index current, {n_outbound} outbound + {n_inbound} inbound links land")
