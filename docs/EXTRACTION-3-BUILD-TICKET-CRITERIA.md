# Extraction #3 — the block `/to-tickets` emits onto every pass-6 build ticket

Written at loop **pass 5** by [#565](https://github.com/timbermania/fft-monorepo/issues/565),
recorded as [ADR-0168](adr/0168-the-manifest-is-the-only-register-that-can-say-the-right-files-moved.md).
Satisfied at pass 6, checked at pass 7.

`/to-tickets` emits an `## Acceptance criteria` section of `- [ ]` items per
ticket. **Paste the block below verbatim into every `Battlefield` build ticket**,
under that heading and after the ticket's own criteria. It is the same block on
every ticket by design: these are properties of *the extraction*, and a criterion
that appears on only some tickets is a criterion the ticket without it may break.

`refactor-loop.md`'s reason for writing it at pass 5 rather than pass 6 is the
part to keep in mind while resisting the urge to trim it:

> It cannot be detected after the fact: by pass 8 the evidence needed to tell the
> two cases apart is gone.

---

## The block

```markdown
## Acceptance criteria

<!-- extraction #3 standing criteria — ADR-0168, on EVERY Battlefield build ticket -->

- [ ] `uv run python tools/check_move_manifest.py` is green. Four arms: every
      manifest row is in exactly one of its two places; the classifier books no
      `Battlefield` file the manifest does not name; the addon's source-file set
      equals the manifest's `dst` set; and no registered vault note has lost its
      last anchor.
- [ ] Files were **moved, not retyped** — `git mv` or an equivalent that carries
      the file's bytes, so its `## Vault: [[…]]` comments travel for free
      (ADR-0110 dec. 1, ADR-0154 dec. 1). If any file was instead **authored
      fresh** as an analog, its rows in `docs/EXTRACTION-3-VAULT-EDGES.tsv` were
      re-anchored **by hand in the same commit**, and the ticket says which and
      why.
- [ ] **No anchor was invented.** Extraction #3's measured authoring debt is
      **zero** (15 notes / 31 edges, 0 gaps, 0 extras at `cd9d6c88f`), and 28 of
      the 46 rows carry no anchor because the vault cites nothing in them.
      Coverage is reported, never asserted (#310) — a manufactured anchor gives
      pass 8 an edge to find intact that never existed.
- [ ] If the move changed which files exist, `docs/EXTRACTION-3-MOVE-MANIFEST.tsv`
      was edited **in the same commit** — never in a follow-up. The `src` column
      is frozen at `cd9d6c88f` and is not the ticket's to edit; only `dst` moves.
- [ ] `uv run python tools/check_addon_portability.py` is green — nothing under
      the addon root names a symbol the classifier books to one of the eleven
      `cb.SYSTEMS`. A `platform` port (`Tune`) and the `schema` kernel are fine
      and are the point (ADR-0139 dec. 12, ADR-0140 dec. 9). ⚠️ "addon → addon"
      is **not** a permission: arm 1 keys on the destination **bucket**, so a
      reach into `addons/exmateria_render/` (which books `Render`) fails exactly
      as `src/render/` would.
- [ ] `uv run python tools/path_refs.py Battlefield --tsv` was **regenerated**,
      not read — `docs/EXTRACTION-3-PATH-REFERENCES.tsv` is a snapshot of a
      moving tree (ADR-0159 dec. 1). Any reference this ticket re-pointed is in
      the new output.
- [ ] The full suite ran, and `git status --porcelain` was read **before**
      committing. `git mv` stages the rename only: a scene can ship pointing at a
      script deleted in the same commit while the test still prints `[PASS]`.
- [ ] Verified **headful** on the 4.8 fork (`godot --version` ⇒
      `4.8.dev.custom_build`), never `--headless` and never stock
      `/usr/bin/godot`.
```

---

## What this block deliberately does not contain

- **A line count, a `--delta`, or any before/after total.** #561 dec. 3 measured
  that `check_baseline.py --delta` is structurally blind to an in-walk
  extraction — same bucket on both sides — and ADR-0167 dec. 6 found a third
  register hole in the same family (`assembler` is outside `cb.SYSTEMS`, so six
  new host wiring lines are invisible and `1044 → 1040` reads as −10 scored /
  +6 unscored, never −4 net). A build ticket that promises a number can satisfy
  it by moving the wrong file. **Set equality is the only checkable form of "the
  right files moved."**
- **The two registers pass 6 owes but does not yet have** — ADR-0164 dec. 4's
  duck-typed-door register (12 → 0) and ADR-0166 dec. 4's Tile-door register
  (8 → 0). Both must exist at pass 6; neither is built, and neither is this
  document's to specify. When they land, their guards join the first checkbox.
- **`.tscn` coverage by the walk.** `SOURCE_SUFFIXES` has no `.tscn`, so the two
  scene rows are matched by suffix rather than through the walk, and
  `path_refs.py:42`'s hardcoded `DEFAULT_SCENES` still loses both silently if a
  ticket moves them without editing it (#561 dec. 3). That edit is a build task,
  not a standing criterion.
