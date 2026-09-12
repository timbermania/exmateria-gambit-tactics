#!/usr/bin/env python3
"""A citation records WHERE. This checks WHAT — for the quotation-shaped subset.

KNOWING THE FAILURE MODE CONFERS NO IMMUNITY. On the day this was built, three
misquotations were committed by the two sessions documenting the problem — twice
by the author of ADR-0154, which is *about* this, and once by the session that
proposed this guard, into a paragraph it had just read. **The error is invisible
from the citing side by construction**: a citation records where, and a plausible
paraphrase of a real source is indistinguishable from a quotation of it at every
point after it is written. That, and not a defect rate, is the argument for
`ENFORCE` eventually being True.

    python3 tools/check_adr_quotes.py [--list]

`check_adr_classification.py` proves a relative ADR link RESOLVES. Nothing proved
that the target says the thing citing it, and on 2026-08-22 that cost two real
defects in one day:

  * *"analog, authored fresh"* is attributed to ADR-0112 in EIGHT sites across six
    documents -- ADR-0154 dec. 1 found four, #403 a fifth inside an instrument, and
    extraction #2's pass 9 three more. ADR-0112 does not contain the word `analog`
    (ADR-0154). The count read FOUR here for a day because dec. 1's repair table has
    one row per DOCUMENT and two documents state the rule twice; grep the PHRASE.
  * ADR-0150 attributed *"sequencing, mixing, banks"* to ADR-0117's row for
    `Audio`, twice. The row reads *"the sound driver"*; `sequencing` and `mixing`
    appear nowhere in ADR-0117.

Both are QUOTATION-SHAPED — `*"…"*` beside an `ADR-NNNN`, with the words simply
absent from the target — so both are mechanically catchable, which is what this
does. **It cannot catch a paraphrase**, and that limit is the point of the name:
support is checkable for the quoted subset and no further. A citation records
where, never what, and a plausible paraphrase of a real ADR is indistinguishable
from a quotation of it at every point after it is written.

WHY THIS CATCHES WHAT READING CANNOT — the argument a defect rate cannot make.
Two of the verified ten are different animals:

  * A DROPPED WORD. *"The closest system to finished"* quoted as *"the closest to
    finished"*. A careful reader with the source open catches this.
  * A FUSION. `BLUEPRINT.md` 434-435 reads *"**The closest system to finished** —
    `Effects`' **calibration** benchmark, and not the same thing as extracted."*
    The phantom — *"the calibrated example of a finished system"* — takes
    `calibration`, `finished` and `system` from **within two lines of each
    other** and recombines them. **Every content word in it is genuinely there**,
    so nothing reads as foreign and it survives eye-reading by someone who has
    the paragraph open. That is the class reading catches worst. A substring
    match does not care.

The same paragraph shows how *"FFT music and SFX banks"* got written: the content
shadow it paraphrases is real, sits two lines further on, and is in
**`BLUEPRINT.md` rather than ADR-0117** — *"one instrument bank (`WAVESET.WD`)
and four bank families — 100 SMD songs, 2 global `feds` banks, 401 per-effect
`feds` banks."* A real fact, a real source, the wrong document, and words nobody
wrote.

HOW A QUOTE IS MATCHED. The target is read whole and whitespace-collapsed first,
because these files are hard-wrapped and a quotation of two consecutive words
routinely spans a line break. Emphasis, backticks, link syntax, smart quotes, the
three dash characters and ALL punctuation are normalised away on both sides; the
comparison is case-insensitive. An ellipsis (`…` or `...`) splits the quote into
fragments that must appear IN ORDER, which is how an honest elided quotation is
written here. Punctuation-insensitivity was measured, not assumed: with it, 7 of
41 flags turned out to be a quoted clause closed with a period the source does
not have, and neither of the two known defects stops being caught.

WHICH TARGET. An `ADR-NNNN` on the same line, or one of three named documents —
`docs/BLUEPRINT.md`, `CONTEXT.md`, `../docs/agents/refactor-loop.md` — cited on
the same line. The document half was added after the ADR half missed a real
defect by construction: a span attributed to `BLUEPRINT.md` has no ADR number on
its line and so was never checked. Measured before shipping: 24 checked, 6
flagged, **four sampled, four real**.

Same line only, and that was measured too. Looking back two lines
checks twice as many quotes at the same hit rate, because the extra ones are
mostly quotations of `BLUEPRINT.md`, `CONTEXT.md` or a docstring that merely have
an ADR link nearby. Same-line keeps the association honest.

WHAT THE RUNS FOUND — 42 flags over 125 same-line quotations, and **ten sampled,
ten real** (six against ADR targets, four against document targets):

    ADR-0124 quotes ADR-0117   "the calibrated example of a finished system"
                               AND, in the same sentence, "FFT music and SFX
                               banks" — TWO fabricated quotations, both flagged
                               here, at :12 and :13. The first report of this run
                               named one, because its reader quoted line 12 and
                               truncated line 13 in the listing. Read every flag.
    ADR-0136 quotes BLUEPRINT  the SAME phrase — one phantom, two claimed
                               sources, present in neither. BLUEPRINT.md:434
                               reads "The closest system to finished".
    ADR-0127 quotes ADR-0122   "the effect channels"
    ADR-0147/0148/0149 + score_goals.py quote ADR-0146
                               "when two registers describe the same set, diff them"
    ADR-0144/0145 quote ADR-0112's TITLE, dropping a word
    ADR-0151 quotes ADR-0121's FILENAME as its title

None of those strings is in the ADR cited. The third is this guard's own finding
about the session that wrote it: the phrase is ADR-0147/0148's coinage and picked
up an ADR-0146 attribution purely by repetition — the same mechanism ADR-0154
found for *"analog, authored fresh"*, caught this time by a program.

**Not every flag is a defect**, which is why `ENFORCE` is False. A quote can be of
another document with an ADR link on the same line, and the guard cannot tell.
Flip `ENFORCE` when the list is empty or every survivor carries an explicit
`<!-- quote-exempt: … -->`; do not flip it on a percentage.

AND DO NOT DISMISS A LIST ON ITS RATE. This instrument was nearly discarded at
"36% cannot be a real defect rate"; six files opened said otherwise, six times
out of six. **A rate is a hypothesis about a population; opened files are
evidence.** Every flag here is a filename and a line number — read four before
concluding anything about the rest.
"""
import re, sys, pathlib, collections

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
ADR_DIR = PROJECT_DIR / "docs" / "adr"

# Flip once the tree is clean. Until then this REPORTS and exits 0 — the same
# contract check_debug_panel_tunables.py ran under while its tree was migrated.
ENFORCE = False

# `*"…"*` / `**"…"**` / `_"…"_` — this repo's convention for quoting another
# document. A bare "…" is not enough: ordinary prose uses quotes for scare-quoting
# and for naming things, and matching those produces noise, not findings.
QUOTE = re.compile(r'(?<![\w])(?:\*\*|\*|_)"(.+?)"(?:\*\*|\*|_)', re.S)
CITE = re.compile(r'ADR-(\d{4})|\]\((\d{4})-[\w-]+\.md')
# The three documents ADRs quote that are not ADRs. `refactor-loop.md` lives
# outside PROJECT_DIR — it is the monorepo's, not this package's — and is simply
# skipped when absent rather than being made a hard dependency.
DOCS = {"BLUEPRINT": "docs/BLUEPRINT.md",
        "CONTEXT.md": "CONTEXT.md",
        "refactor-loop": "../docs/agents/refactor-loop.md"}
DOCCITE = re.compile(r'BLUEPRINT|CONTEXT\.md|refactor-loop')
DASHES = dict.fromkeys(map(ord, "‐‑‒–—―"), "-")
QUOTES = {ord("‘"): "'", ord("’"): "'", ord("“"): '"', ord("”"): '"'}


def norm(text: str) -> str:
    """Collapse to a comparable form: no markup, no punctuation, no line breaks."""
    t = text.translate(DASHES).translate(QUOTES)
    t = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', t)   # [label](link) -> label
    t = re.sub(r'[*_`>#|]', '', t)
    t = re.sub(r'[^0-9a-zA-Z\s]', ' ', t)            # measured: kills 7 boundary flags
    return re.sub(r'\s+', ' ', t).strip().lower()


def target_of(line: str) -> str | None:
    """The target cited on the quote's OWN line: an ADR number, or a doc key.

    An ADR wins when both appear — an ADR citation is the more specific claim,
    and a doc name alongside it is usually saying where the ADR sits.
    """
    m = CITE.search(line)
    if m:
        return m.group(1) or m.group(2)
    d = DOCCITE.search(line)
    return d.group(0) if d else None


def main() -> int:
    bodies: dict[str, str] = {}
    for key, rel in DOCS.items():
        q = PROJECT_DIR / rel
        if q.exists():
            bodies[key] = norm(q.read_text(encoding="utf-8"))
    for p in sorted(ADR_DIR.glob("[0-9][0-9][0-9][0-9]-*.md")):
        # Six numbers are used twice in this tree (0073, 0091, 0095, 0096, 0097,
        # 0137), so a number resolves to more than one file and BOTH are haystack:
        # a quote is a defect only if it is in neither. check_adr_classification
        # already fails a duplicate that is actually cited; this must not
        # second-guess it with a coin flip.
        bodies[p.name[:4]] = bodies.get(p.name[:4], "") + " " + norm(p.read_text(encoding="utf-8"))

    citing = sorted(ADR_DIR.glob("[0-9][0-9][0-9][0-9]-*.md"))
    citing += [PROJECT_DIR / DOCS[k] for k in ("BLUEPRINT", "CONTEXT.md")
               if (PROJECT_DIR / DOCS[k]).exists()]
    print("subject: %d citing files (docs/adr/, %s); targets are those ADRs plus %s. "
          "Quotation-shaped spans only (`*\"…\"*` beside a citation on the SAME line). "
          "A paraphrase is NOT checkable here."
          % (len(citing), ", ".join(sorted(DOCS)),
             ", ".join(k for k in DOCS if k in bodies)))

    self_key = {DOCS[k]: k for k in DOCS}
    bad, checked = [], 0
    for p in citing:
        text = p.read_text(encoding="utf-8")
        lines = text.splitlines()
        own = p.name[:4] if p.parent.name == "adr" else self_key.get(
            p.relative_to(PROJECT_DIR).as_posix())
        for m in QUOTE.finditer(text):
            line_no = text[:m.start()].count("\n")
            num = target_of(lines[line_no])
            if num is None or num == own or num not in bodies:
                continue          # self-quote, or no resolvable target on the line
            quote = norm(m.group(1))
            if len(quote) < 12:
                continue          # too short to be evidence either way
            checked += 1
            hay, pos, ok = bodies[num], 0, True
            for frag in [f.strip() for f in re.split(r'…|\.\.\.', quote) if f.strip()]:
                at = hay.find(frag, pos)
                if at < 0:
                    ok = False
                    break
                pos = at + len(frag)
            if not ok:
                bad.append((p.name, line_no + 1, num, m.group(1).strip()))

    print("checked %d quotations against the source they name" % checked)
    if not bad:
        print("quotations OK — every quoted span appears in the source it cites.")
        return 0

    print("\n%d quoted span(s) NOT FOUND in the source they cite:\n" % len(bad))
    # ADR-0154 is flagged for correctly quoting the wrong quotation — its table
    # of the four "analog, authored fresh" sites reproduces each site's words
    # verbatim, and those words are not in ADR-0112. That is the finding, quoted.
    # Left flagged rather than exempted: an exemption here would be the first
    # entry on a list that ends with the guard exempting everything awkward.
    for f, ln, num, q in bad:
        short = q if len(q) < 110 else q[:107] + "..."
        where = ("ADR-" + num) if num.isdigit() else num
        print("  %s:%d cites %s\n      %r" % (f, ln, where, short))
    print("\nEither the quotation is wrong or the citation is. Both happened on "
          "2026-08-22.\nA citation records WHERE; this is the only check on WHAT.")
    return 1 if ENFORCE else 0


if __name__ == "__main__":
    sys.exit(main())
