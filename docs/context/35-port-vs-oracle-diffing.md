# Port-vs-oracle diffing

Vocabulary for the locality-diff instrument that pins port rendering
against the pcsx-redux oracle framebuffer (§15.26 Round 44). See
`tests/tools/oracle_diff.py` and `research/working_documents/FORMATION_SCREEN.md`.

**Oracle framebuffer**:
A 256×240 ROM-derived screenshot of the real game at a settled state
(e.g. `fb4.png`, the equip-picker). Ground truth for geometry. Local-only,
never committed; regenerate from a pcsx-redux savestate.
_Avoid_: "reference image" (too generic — this is specifically the PSX
framebuffer at display resolution).

**Subject**:
The unit + equipment shown on a screen. The oracle's subject (Ramza Lv99)
and the port capture's subject (a synthetic Squire) differ, so **content**
(portrait, name, level, HP/MP, stat values) diverges independently of
rendering geometry. The diff neutralizes the subject by masking, not by
matching it.

**Image diff pair**:
A named region-of-interest comparison — `{name, rect(s), notes}` — that
whitelists a locality: outside its rects, both oracle and port are set to
**black**, so only that region contributes to the diff. Bounded, re-runnable
after a fix (a regression check). The reusable unit of the instrument.
_Avoid_: "beat" — `FormationTransitionEngine` owns that term for a UI-transition
step (see [[Beat]]); different domain.

**Global orienting pass**:
The one whole-screen diff that *blacklists* known content (portrait/name/etc.
→ black) to spot where disconnects live, before drilling in with image diff
pairs. Blacklisting is used ONLY here — it can never prove all content is
masked, so it never replaces a whitelisted image diff pair.

**Channel overlay** / **magnitude heatmap**:
The two diff artifacts. Overlay = oracle→red, port→green, agreement→gray
(fringes reveal the *direction* of misalignment); heatmap = abs-diff
magnitude through a hot colormap. Both rendered at 4× NEAREST.
