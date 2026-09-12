#!/usr/bin/env python3
"""Guard: every key-location slug `<ns>.loc.<name>` is DEFINED in exactly one owner
class — the class its namespace names (ADR-0088 Amendment 2 §2).

Why this exists: a key location is a SHARED position many elements can ride via
`UI3Element.at(slug)`; scrubbing it moves every rider. For that to stay legible its
literal (and oracle citations) must live in ONE place — its owner. If the literal
drifts to another class, or a namespace ends up split across two classes, "which class
owns this position" becomes ambiguous, and the deferred Amendment 3 §7 "add a location"
materialise-injection (which resolves the owner FROM the namespace) has nowhere sound to
inject. This mechanizes the colocation convention so it cannot rot.

Static scan, not runtime: a definition is a source fact. The slug STRING LITERAL appears
only in its owner's `const`/bind block; consumers reference that const (`at(LOC_EQUIP)`),
never re-literal the slug. So grouping the quoted literals across `src/` by namespace
must yield exactly one owner file per namespace. Prose mentions (`foo.loc.*`,
`<ns>.loc.`) and the bare `".loc."` marker are not full quoted slugs and do not match.

Usage (run from the package root):
    uv run python tools/check_location_ownership.py            # print the mapping, exit 0
    uv run python tools/check_location_ownership.py --check    # exit 1 on any ambiguity

The `resolve()` / `scan_owners()` functions are the reusable namespace→owner resolver
the UI3 page and the future §7 injection tool consume.
"""
from __future__ import annotations

import pathlib
import re
import sys

# A quoted key-location slug literal: "<ns>.loc.<name>", ns a dotted lower snake token,
# name a lower snake token. The leading/trailing quotes exclude prose and the ".loc."
# marker (which has no `[a-z]` before `.loc.` inside the quotes).
_SLUG_RE = re.compile(r'"([a-z][a-z0-9_.]*)\.loc\.([a-z0-9_]+)"')


def _strip_comment(line: str) -> str:
    """Drop a GDScript `#`/`##` line comment, honoring quotes so a `#` inside a string
    is kept. Definitions are CODE; an example slug quoted in a doc comment is not an
    owner and must not be scanned."""
    quote = None
    for i, ch in enumerate(line):
        if quote is not None:
            if ch == quote and (i == 0 or line[i - 1] != "\\"):
                quote = None
        elif ch in ("\"", "'"):
            quote = ch
        elif ch == "#":
            return line[:i]
    return line


def scan_owners(src_root: str) -> dict[str, dict[str, list[str]]]:
    """namespace -> {owner_file_path: sorted[slugs]} for every `.gd` under src_root.

    A namespace with more than one owner_file key is a violation — the position's literal
    is scattered. owner_file_path is relative to src_root's parent (stable to display).
    """
    root = pathlib.Path(src_root)
    base = root.parent
    owners: dict[str, dict[str, set[str]]] = {}
    for path in sorted(root.rglob("*.gd")):
        text = path.read_text(encoding="utf-8", errors="replace")
        rel = str(path.relative_to(base))
        for line in text.splitlines():
            for ns, name in _SLUG_RE.findall(_strip_comment(line)):
                slug = f"{ns}.loc.{name}"
                owners.setdefault(ns, {}).setdefault(rel, set()).add(slug)
    return {ns: {f: sorted(s) for f, s in by_file.items()} for ns, by_file in owners.items()}


def resolve(src_root: str) -> dict[str, str]:
    """namespace -> the single owner file (relative path). Raises ValueError if a
    namespace is ambiguous — call check() first for a friendly report. This is the
    resolver the page + §7 injection reuse."""
    out: dict[str, str] = {}
    for ns, by_file in scan_owners(src_root).items():
        if len(by_file) != 1:
            raise ValueError(f"namespace '{ns}.loc.*' has {len(by_file)} owners: {sorted(by_file)}")
        out[ns] = next(iter(by_file))
    return out


def check(src_root: str) -> list[str]:
    """Return a list of human-readable violations ([] = clean): any namespace whose
    `.loc.*` literals are defined across more than one owner class."""
    violations: list[str] = []
    for ns, by_file in sorted(scan_owners(src_root).items()):
        if len(by_file) != 1:
            classes = ", ".join(pathlib.Path(f).stem for f in sorted(by_file))
            violations.append(
                f"location namespace '{ns}.loc.*' is defined in {len(by_file)} classes "
                f"({classes}) — a key position must live in ONE owner class "
                f"(ADR-0088 Amendment 2 §2). Files: {sorted(by_file)}"
            )
    return violations


def main(argv: list[str]) -> int:
    check_mode = "--check" in argv[1:]
    # NAMED LIMITATION (ADR-0148 dec. 3). This is the one source guard that does NOT
    # read `classify_blueprint.WALK_ROOTS`: `check()` takes a single root, reports
    # `owner_file_path` relative to that root's PARENT, and is called with a tmp dir by
    # tools/test_check_location_ownership.py — so multi-root support is a signature
    # change plus a display-path decision, not a one-line rescope. Verified at
    # extraction #1: neither addon declares a `<ns>.loc.<name>` slug, so nothing is
    # uncovered today. Fix it when an addon first declares one, or when the second
    # extraction makes the awkwardness worth paying for.
    src_root = "src"
    if not pathlib.Path(src_root).is_dir():
        print(f"ERROR: '{src_root}' not found — run from the package root", file=sys.stderr)
        return 2
    violations = check(src_root)
    if violations:
        print("FAIL: key-location ownership is ambiguous (ADR-0088 Amendment 2 §2):")
        for v in violations:
            print(f"  - {v}")
        return 1
    owners = resolve(src_root)
    total = sum(len(next(iter(v.values()))) for v in scan_owners(src_root).values())
    print(f"OK: {total} key location(s) across {len(owners)} namespace(s), one owner each:")
    for ns, owner_file in sorted(owners.items()):
        print(f"  {ns}.loc.* -> {pathlib.Path(owner_file).stem}  ({owner_file})")
    return 0 if not check_mode else (0 if not violations else 1)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
