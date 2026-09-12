#!/usr/bin/env python3
"""An `ADR-NNNN <anchor>` citation must resolve to a place that exists.

A quarter of this repo's ADR citations do not name an ADR — they name a place
INSIDE one: `ADR-0085 Amendment 19b`, `ADR-0137 dec. 3`, `ADR-0068 Addendum R1`.
Nothing checked them, so an ADR could be folded, renumbered or rewritten and
every one of those citations would go stale in silence. This is the instrument
that makes an ADR rewrite safe: it fails when a citation addresses a section
its ADR no longer has.

Anchors are written as headings OR as bold run-in paragraphs (`**3. ...**`,
`**Amendment 1 (...)**`) — this repo uses both, so both count.

Two failure kinds:
  UNRESOLVED ADR    — `ADR-NNNN` names no file
  UNRESOLVED ANCHOR — the file exists but offers no such amendment / decision

Run from the package root.  Exit 0 = clean.
"""
import collections, os, pathlib, re, sys

SCAN = ("src", "addons", "assets", "tests", "tools", "docs")
SKIP = {"tools/check_adr_anchors.py", "tools/check_adr_classification.py"}
EXT = {".gd", ".py", ".sh", ".md", ".json", ".gdshader", ".tscn", ".cfg", ".tsv"}

ID = r"[0-9]*[a-z]?[0-9]*"
AMD = re.compile(r"^(?:#{2,4}\s*|\*\*)(?:Amendment|Addendum)\s*(" + ID + r")", re.I)
AMD_DATED = re.compile(r"^(?:#{2,4}\s*|\*\*)(?:Amendment|Addendum)\s*\(\s*(\d{4}-\d{2}-\d{2})([a-z]?)", re.I)
NUM = re.compile(r"^(?:#{2,5}\s*|\*\*|\s{0,3})(\d+)\s*[.)·]")
DEC = re.compile(r"^(?:#{2,5}\s*|\*\*)(?:Decision|Dec\.)\s*(\d+)", re.I)
ORD = {"first": "1", "second": "2", "third": "3", "fourth": "4",
       "fifth": "5", "sixth": "6", "seventh": "7"}
SUBID = re.compile(r"^(?:#{2,5}\s*|\*\*|\s{0,3}[-*]?\s*)([A-Z]\d+)[.):\s]")
ORD_AMD = re.compile(r"^(?:#{2,4}\s*|\*\*)(" + "|".join(ORD) + r")\s+amendment", re.I)
REPO_ROOT = re.compile(r"(?:repo-root|repo root|root)\s+$", re.I)


def anchors_of(path):
    """(amendment ids, decision ids, any-numbered ids) an ADR offers.

    `dec. N` is checked STRICTLY against the Decision section — that is the
    claim a citation makes, and a decision deleted by a rewrite must fail.
    `§ N` is checked against any numbered item, because this corpus uses § for
    sub-items of amendments and audits too.

    FENCED BLOCKS ARE SKIPPED ENTIRELY — see the comment on the fence test below;
    a quoted GDScript `##` docstring is not a section heading and used to silently
    end the Decision section.
    """
    amd, dec, sec = set(), set(), set()
    in_decision = False
    fence = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        # 🔴 A FENCED BLOCK IS NOT PROSE, AND SKIPPING IT IS LOAD-BEARING RATHER THAN
        # TIDY. This corpus quotes GDScript, and a GDScript docstring line starts
        # `## `, which the section matcher below reads as a MARKDOWN HEADING — so one
        # quoted `## A Character = identity…` turned `in_decision` off and everything
        # after it stopped being offered. Measured when ADR-0243 could not cite
        # ADR-0241: that ADR offered decision 1 and NOTHING ELSE, so `dec. 2`
        # through `dec. 9` — the whole substance of a selection ADR — were
        # uncitable from any .py or .gd in the package while reading as green here,
        # because `docs/adr/` is excluded from the citation scan and only an outside
        # citation could ever have surfaced it.
        #
        # Measured tree-wide before it landed, so the blast radius is on the record:
        # exactly TWO files move. ADR-0241 GAINS decisions 2-9 (the defect). ADR-0137
        # LOSES `§ 12` from its any-numbered set, which came from `12.6  12.6  9.6…`,
        # a row of a numeric table inside a fence. Nothing outside `docs/adr/` addresses
        # that anchor, so the loss costs no citation.
        #
        # ADR-0137 is worth one more line, because it is the second half of the same
        # blind spot and this fix does NOT close it: its Decision section is prose
        # bullets, so it offers NO numbered decisions at all, and the five `dec. 12`
        # citations against it — plus decs. 4, 8, 10, 11 and 13 — are every one of them
        # written in another ADR. `docs/adr/` is excluded from the scan below, so those
        # are unchecked, not resolved. The exclusion is what hid the ADR-0241 defect too.
        f = re.match(r"^\s{0,3}(`{3,}|~{3,})", line)
        if f:
            # Only the SAME character closes a fence, so a ``` inside a ~~~ block
            # does not terminate it.
            if fence is None:
                fence = f.group(1)[0]
            elif f.group(1)[0] == fence:
                fence = None
            continue
        if fence:
            continue
        # ONLY a `##` changes section state — `### 1. ...` is an item INSIDE the
        # Decision section, not a new section (ADR-0172 writes its decisions that way).
        h = re.match(r"^##(?!#)\s*(.*)", line)
        if h:
            in_decision = bool(re.match(r"decisions?\b", h.group(1).strip(), re.I))
        m = AMD.match(line)
        if m:
            amd.add("*")
            if m.group(1):
                amd.add(m.group(1).lower())
        m = AMD_DATED.match(line)
        if m:
            amd.add("*"); amd.add(m.group(1)); amd.add(m.group(1) + m.group(2).lower())
            if m.group(2):
                amd.add(m.group(2).lower())
        m = ORD_AMD.match(line)
        if m:
            amd.add("*"); amd.add(ORD[m.group(1).lower()])
        m = SUBID.match(line)
        if m:
            amd.add(m.group(1).lower())
        m = NUM.match(line)
        if m:
            sec.add(m.group(1))
            if in_decision:
                dec.add(m.group(1))
        m = DEC.match(line)
        if m:
            sec.add(m.group(1)); dec.add(m.group(1))
    return amd, dec, sec


adr_dir = pathlib.Path("docs/adr")
by_num = collections.defaultdict(list)
for p in sorted(adr_dir.glob("[0-9][0-9][0-9][0-9]-*.md")):
    by_num[p.name[:4]].append(p)
OFFERS = {n: [anchors_of(p) for p in ps] for n, ps in by_num.items()}
HAS_AMD = {n: any("amendment" in p.read_text(encoding="utf-8", errors="replace").lower()
                  or "addendum" in p.read_text(encoding="utf-8", errors="replace").lower()
                  for p in ps) for n, ps in by_num.items()}

CITE = re.compile(
    r"ADR-(\d{4})(?:'s)?\s*"
    r"(?:(?P<amd>Amendment|Am\.|Addendum)[\s,(]*(?P<amdid>\d{4}-\d{2}-\d{2}[a-z]?|" + ID + r")"
    r"|(?P<dec>dec(?:ision)?s?\.?)\s*(?P<decid>\d+)"
    r"|§\s*(?P<sec>\d+))?", re.I)

fail = collections.Counter()
detail = collections.defaultdict(list)
n_cite = n_anchor = 0

for root in SCAN:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in {".git", "__pycache__", ".godot"}]
        for fn in filenames:
            p = pathlib.Path(dirpath) / fn
            if p.suffix not in EXT or str(p) in SKIP or p.parts[:2] == ("docs", "adr"):
                continue
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for ln, line in enumerate(text.splitlines(), 1):
                for m in CITE.finditer(line):
                    num = m.group(1)
                    # A citation the author has ALREADY marked as the other corpus's.
                    # Two ADR sets share one number space (root `docs/adr/` and this
                    # one), so `ADR-0003 dec. 4` written inside `exmateria-sound` is a
                    # correct citation this checker cannot resolve — it only holds
                    # godot-learning's corpus. `KNOWN` below pins four such lines by
                    # PATH, and its own comment says the convention is that the citing
                    # text "says `repo-root ADR-0003` explicitly". This makes that
                    # convention mechanical: say it, and the citation addresses the
                    # other corpus, from any file, without a pin that rots when the
                    # file moves. It is deliberately narrow — the prefix has to be
                    # immediately before the number, so it cannot silence a citation
                    # that merely mentions the root repo in the same sentence.
                    if REPO_ROOT.search(line, 0, m.start()):
                        continue
                    n_cite += 1
                    if num not in by_num:
                        fail["UNRESOLVED ADR"] += 1
                        detail["UNRESOLVED ADR"].append(f"{p}:{ln}: ADR-{num} names no file")
                        continue
                    if m.group("amd"):
                        val = (m.group("amdid") or "").lower()
                        # `amendment states that…` — a bare word is not an id
                        if not any(c.isdigit() for c in val):
                            val = "*"
                        kind = "amendment"
                    elif m.group("dec"):
                        kind, val = "decision", m.group("decid")
                    elif m.group("sec"):
                        kind, val = "§", m.group("sec")
                    else:
                        continue
                    n_anchor += 1
                    ok = False
                    for amd, decs, secs in OFFERS[num]:
                        if kind == "amendment":
                            ok |= val in amd or (val == "*" and HAS_AMD[num])
                        elif kind == "decision":
                            ok |= val in decs
                        else:
                            ok |= val in secs
                    if not ok:
                        fail["UNRESOLVED ANCHOR"] += 1
                        detail["UNRESOLVED ANCHOR"].append(
                            f"{p}:{ln}: ADR-{num} {kind} {val} — the ADR offers no such item")

# Citations that are RIGHT and cannot resolve here. Shrink, never grow.
#   ADR-0003 — names the REPO-ROOT ADR set, not godot-learning's; the citing
#     comments say "repo-root ADR-0003" explicitly.
#   ADR-0190 — a knowing forward reference; the README says "is not merged".
KNOWN = {
    # (path, ADR) pairs that are RIGHT and cannot resolve here. Keyed WITHOUT a
    # line number on purpose: a line-keyed pin rots the moment anything above it
    # moves. Shrink this, never grow it.
    #
    # ADR-0003 — names the REPO-ROOT ADR set, not godot-learning's. TWO of the
    #   four pins this list used to carry are gone: those files already spelled
    #   it "repo-root ADR-0003", which `REPO_ROOT` above now honours directly,
    #   so the pin was doing nothing. The two left are the ones that cite it
    #   BARE; say "repo-root" in them and they can go too.
    # ADR-0190 — a knowing forward reference; the README says "is not merged".
    ("tools/test_check_addon_portability.py", "0003"),
    ("tests/run_all_tests.sh", "0003"),
    ("addons/exmateria_battlefield/README.md", "0190"),
}
def pinned(msg):
    path, rest = msg.split(":", 1)
    m = re.search(r"ADR-(\d{4})", rest)
    return (path, m.group(1)) in KNOWN if m else False


for k, v in list(detail.items()):
    kept = [d for d in v if not pinned(d)]
    fail[k] -= len(v) - len(kept)
    if kept:
        detail[k] = kept
    else:
        del detail[k], fail[k]

print(f"check_adr_anchors: {n_cite} ADR citations, {n_anchor} anchored "
      f"({len(by_num)} numbers over {sum(len(v) for v in by_num.values())} files)")
if not fail:
    print("check_adr_anchors: OK — every anchored citation resolves")
    sys.exit(0)
for k in sorted(detail):
    print(f"\n{k}: {fail[k]}")
    for d in detail[k][:30]:
        print("  " + d)
    if len(detail[k]) > 30:
        print(f"  … and {len(detail[k]) - 30} more")
sys.exit(1)
