#!/usr/bin/env python3
"""Root ADR-0001's standing guard: no disc-derived artifact is committed.

ADR-0001 used to say reproducibility was verified by "a one-time sweep, not a
standing guard". This is the guard. A one-time sweep is exactly how seven
artifacts reached this repo with no generator at all, and how
`projectile_models.json` sat on the ADR's own "must byte-reproduce" list with
nothing running its extractor.

The single table is `tools/data/generated_assets.tsv` — one row per tracked-or-
generated artifact under the asset roots, carrying its ADR-0001 provenance and,
for disc derivations, the generator that writes it. `.gitignore`'s managed block
is rendered from the same table, so the manifest and the ignore rules cannot
disagree without this guard saying so.

Three ways to lose the invariant, one check each:

  1. A tracked artifact with no row — somebody committed a new ROM derivation.
  2. A row whose ignore rule is gone — the quiet one: delete the rule and the
     next bootstrap re-commits the data, with no diff to the manifest to notice.
  3. A row that lies — an `iso-*` row naming a generator that is not there, a
     committed row claiming a generator, an unknown provenance, or a committed
     row that is not actually committed.

Judged against `git ls-files`, never `Path.exists()`. A fresh clone has none of
these files on disk until bootstrap runs; that is the normal state, not a
violation.

THE BLOCK LIVES IN THIS PACKAGE'S OWN `.gitignore`, package-relative. It used to
live in the MONOREPO ROOT `.gitignore`, prefixed `godot-learning/`, and this guard
read it as `PACKAGE.parent / ".gitignore"` — a path that escapes the standalone
`exmateria-gambit-tactics` clone the package ships as, where the package IS the
root. Measured there: a traceback with no `.gitignore` above the clone, and 56
false "absent from the managed block" violations with an unrelated one. The guard
could never be green in the repo it exists to protect.

Teaching the guard to look in two places was the smaller fix and the wrong one.
Git reads a `.gitignore` relative to its own directory, so ONE unprefixed copy in
the package is correct in both repos — and the subtree then carries a file that is
byte-identical on both sides instead of one that conflicts on every sync.

Usage:
    uv run python tools/check_generated_assets.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
MANIFEST = HERE / "data" / "generated_assets.tsv"
# The package's OWN .gitignore, never the monorepo root's — see the module
# docstring. Package-relative rules, so there is nothing to strip off them.
GITIGNORE = PACKAGE / ".gitignore"

# Matched as a line PREFIX, not equality: the marker names the manifest by its
# repo-relative path, which is `godot-learning/tools/…` in the monorepo and
# `tools/…` in the standalone clone. The guard must read both.
BEGIN = "# BEGIN generated-assets"
END = "# END generated-assets"

# Provenance classes, per root ADR-0001. The first two are disc derivations and
# must NOT be committed; the last three must be.
GENERATED = ("iso-data", "iso-code")
COMMITTED = ("runtime-capture", "fftpatcher", "hand-authored")


class Row(NamedTuple):
    path: str          # package-relative, e.g. "assets/scenarios/entd.json"
    provenance: str
    generator: str     # a tools/ filename, or "-" for the committed classes


def violations(rows, tracked, ignored, tools) -> list[str]:
    """Every way the manifest, git and the ignore rules can disagree.

    `rows` is the manifest; `tracked` the package-relative paths git tracks;
    `ignored` the paths the managed `.gitignore` block names; `tools` the
    filenames present in `tools/`. Injected rather than read here so the arms can
    be tested one at a time.
    """
    out: list[str] = []
    seen: dict[str, Row] = {}

    for r in rows:
        if r.path in seen:
            out.append(f"{r.path}: listed twice in the manifest")
            continue
        seen[r.path] = r

        if r.provenance in GENERATED:
            if r.generator == "-":
                out.append(f"{r.path}: provenance {r.provenance} but no generator named")
            elif r.generator not in tools:
                out.append(f"{r.path}: generator tools/{r.generator} does not exist")
            if r.path in tracked:
                out.append(
                    f"{r.path}: disc-derived ({r.provenance}) but TRACKED in git — "
                    f"ADR-0001 says it is rebuilt by tools/{r.generator}, not committed"
                )
            if r.path not in ignored:
                out.append(
                    f"{r.path}: disc-derived but absent from .gitignore's managed block — "
                    "re-render it, or the next bootstrap commits the data"
                )
        elif r.provenance in COMMITTED:
            if r.generator != "-":
                out.append(
                    f"{r.path}: provenance {r.provenance} cannot name a generator "
                    f"(got {r.generator}) — if a tool writes it, it is a disc derivation"
                )
            if r.path not in tracked:
                out.append(
                    f"{r.path}: provenance {r.provenance} but NOT tracked — "
                    "nothing can rebuild it, so it has to be committed"
                )
            if r.path in ignored:
                out.append(f"{r.path}: committed artifact named in the ignore block")
        else:
            out.append(
                f"{r.path}: unknown provenance {r.provenance!r} — "
                f"expected one of {', '.join(GENERATED + COMMITTED)}"
            )

    for path in sorted(tracked - set(seen)):
        out.append(
            f"{path}: tracked artifact with no manifest row — classify it in "
            "tools/data/generated_assets.tsv (see root ADR-0001)"
        )
    for path in sorted(set(ignored) - set(seen)):
        out.append(f"{path}: ignored by the managed block but has no manifest row")

    return out


def read_manifest(path: Path = MANIFEST) -> list[Row]:
    rows = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            raise SystemExit(f"{path}:{n}: expected 3 tab-separated fields, got {len(parts)}")
        rows.append(Row(*(p.strip() for p in parts)))
    return rows


def read_ignored(path: Path = GITIGNORE) -> set[str] | None:
    """The managed block's paths, package-relative. `None` when there is no block.

    A missing block is its own failure and is reported as one. Returning an empty
    set instead would re-derive it as one violation per disc-derived row — 56
    lines that all say the same thing and none of which names the actual cause.
    """
    if not path.is_file():
        return None
    # Sliced by LINE, not by `str.split(BEGIN)`: the marker line carries a
    # trailing "(rendered from …)" clause, and splitting mid-line leaves that
    # clause inside the block, where an unprefixed checkout reads it as a path.
    lines = path.read_text().splitlines()
    start = next((i for i, l in enumerate(lines) if l.strip().startswith(BEGIN)), None)
    if start is None:
        return None
    end = next((i for i, l in enumerate(lines[start + 1:], start + 1)
                if l.strip().startswith(END)), None)
    if end is None:
        return None
    return {
        line.strip()
        for line in lines[start + 1:end]
        if line.strip() and not line.lstrip().startswith("#")
    }


def read_tracked(roots) -> set[str]:
    out = subprocess.run(
        ["git", "ls-files", "-z", *roots],
        cwd=PACKAGE, capture_output=True, text=True, check=True,
    ).stdout
    return {p for p in out.split("\0") if p}


def main() -> int:
    rows = read_manifest()
    roots = sorted({r.path.split("/")[0] + "/" + r.path.split("/")[1] for r in rows})
    tracked = {
        p for p in read_tracked(roots)
        if p.endswith((".json", ".feds")) or p in {r.path for r in rows}
    }
    tools = {p.name for p in HERE.iterdir() if p.is_file()}
    ignored = read_ignored()
    if ignored is None:
        print(
            f"check_generated_assets: no '{BEGIN}' … '{END}' block in {GITIGNORE} "
            f"— nothing is ignoring the disc derivations, so the next bootstrap "
            f"commits them",
            file=sys.stderr,
        )
        return 1
    found = violations(rows, tracked, ignored, tools)
    if found:
        print(f"check_generated_assets: {len(found)} violation(s)\n", file=sys.stderr)
        for v in found:
            print(f"  {v}", file=sys.stderr)
        return 1
    print(f"check_generated_assets: {len(rows)} artifacts classified, none misfiled "
          f"({len(ignored)} ignore rules from {GITIGNORE.relative_to(PACKAGE)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
