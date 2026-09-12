#!/usr/bin/env python3
"""What did this rewrite LOSE? The gate that makes deleting ADR prose safe.

"Never delete prose" was a crude safety rule, but it was the safety rule. Taking
it away leaves a gap: the failure mode of a rewrite is silently dropping the one
sentence that named a real constraint. `check_adr_anchors.py` does not help — it
checks that ANCHORS resolve, not that CONTENT survived.

So: extract every checkable token from both versions and diff the sets. A token
present in the old file and absent from the new one must be accounted for as

  folded    — still stated, in different words (you say so; this tool cannot)
  dead      — the thing no longer exists in the tree. PROVEN here by grep,
              never asserted.
  migrated  — it now lives in the register, an issue, or audit-notes/

This is permissive, not prohibitive. It does not stop you deleting; it makes you
say why. Its free side-effect is the finding class you actually want: a token in
the ADR that is NOT in the tree is a stale claim.

  tools/adr_claim_diff.py docs/adr/0052-*.md            # HEAD vs working tree
  tools/adr_claim_diff.py --old <rev> docs/adr/0052-*.md
  tools/adr_claim_diff.py --old-file a.md docs/adr/0052-*.md

Run from the package root.  Exit 0 = nothing dropped, or every drop is dead.
"""
import argparse
import os
import pathlib
import re
import subprocess
import sys

# A "checkable token" is something the tree could contradict. Prose is not.
BACKTICK = re.compile(r"`([^`\n]{2,120})`")
PATHLIKE = re.compile(r"(?:res://|user://)?(?:[\w.-]+/){1,}[\w.-]+\.[A-Za-z0-9]{1,12}")
SYMBOL = re.compile(r"\b(?:[A-Z][a-z0-9]+){2,}\b|\b[a-z_][a-z0-9_]{3,}\(\)")
COUNT = re.compile(r"\b\d{1,6}\b")

# Words that look like symbols but are English, and numbers that are never claims.
STOPWORDS = {"ADR", "TODO", "NOTE", "GDScript", "PSX", "README", "CONTEXT"}
SCAN_ROOTS = ("src", "addons", "assets", "tests", "tools", "docs", "config")
SCAN_EXT = {".gd", ".py", ".sh", ".md", ".json", ".gdshader", ".gdshaderinc",
            ".tscn", ".cfg", ".tsv", ".yaml", ".yml"}


# A backticked span is only a CLAIM if it names a thing — an identifier, a path,
# a call, a literal. This corpus also backticks headings and half-sentences, and
# letting those through buries the real drops in noise (measured: 101 "tokens"
# on one file, of which the great majority were prose).
CLAIMLIKE = re.compile(r"^[\w./:@+-]{3,}$|^[\w.]+\([^)]*\)$|^0x[0-9A-Fa-f]+$")
LINEREF = re.compile(r"^:?\d+(?:[-:]\d+)*$")


def is_claim(t):
    if t.startswith("#") or t.startswith("//"):
        return False
    if LINEREF.match(t):          # a bare `:135-139` is a citation, re-grepped separately
        return False
    return bool(CLAIMLIKE.match(t))


def tokens(text):
    """Tokens a rewrite could silently drop. Counts are kept separately: a number
    changing is usually a CORRECTION, not a loss, so they are reported apart."""
    hard, counts = set(), set()
    for m in BACKTICK.finditer(text):
        t = m.group(1).strip()
        if is_claim(t):
            hard.add(t)
    for m in PATHLIKE.finditer(text):
        if is_claim(m.group(0)):
            hard.add(m.group(0))
    for m in SYMBOL.finditer(text):
        t = m.group(0)
        if t not in STOPWORDS:
            hard.add(t)
    for m in COUNT.finditer(text):
        counts.add(m.group(0))
    return hard, counts


def read_git(rev, path):
    r = subprocess.run(["git", "show", f"{rev}:./{path}"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f"ERROR: git show {rev}:./{path} failed — note that git pathspecs are "
              f"CWD-RELATIVE; run from the package root and pass a path relative to it.",
              file=sys.stderr)
        sys.exit(2)
    return r.stdout


_TREE = None


def tree_text():
    """Every scannable file's text, once. Used to PROVE `dead`."""
    global _TREE
    if _TREE is None:
        buf = []
        for root in SCAN_ROOTS:
            for dirpath, dirnames, filenames in os.walk(root):
                dirnames[:] = [d for d in dirnames
                               if d not in (".git", "__pycache__", ".godot")]
                for f in filenames:
                    if os.path.splitext(f)[1] in SCAN_EXT:
                        try:
                            buf.append(open(os.path.join(dirpath, f), encoding="utf-8",
                                            errors="replace").read())
                        except OSError:
                            pass
        _TREE = "\n".join(buf)
    return _TREE


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="the ADR, relative to godot-learning/")
    ap.add_argument("--old", default="HEAD", help="git rev holding the old version")
    ap.add_argument("--old-file", help="read the old version from a file instead")
    a = ap.parse_args()

    new_path = pathlib.Path(a.path)
    if not new_path.exists():
        print(f"ERROR: {new_path} not found", file=sys.stderr)
        return 2
    old = (pathlib.Path(a.old_file).read_text(encoding="utf-8")
           if a.old_file else read_git(a.old, a.path))
    new = new_path.read_text(encoding="utf-8")

    old_hard, old_counts = tokens(old)
    new_hard, new_counts = tokens(new)
    dropped = sorted(old_hard - new_hard)
    dropped_counts = sorted(old_counts - new_counts, key=lambda x: (len(x), x))

    if not dropped and not dropped_counts:
        print(f"adr_claim_diff: OK — {new_path.name} dropped no checkable token.")
        return 0

    # `dead` is PROVEN, never asserted: the token must be absent from the tree,
    # with this ADR itself excluded so it cannot vouch for its own claim.
    self_text = new + old
    corpus = tree_text().replace(self_text, "")
    dead, live = [], []
    for t in dropped:
        (dead if t not in corpus else live).append(t)

    print(f"adr_claim_diff: {new_path.name} dropped {len(dropped)} token(s) "
          f"({len(dead)} dead, {len(live)} still live in the tree)\n")
    if dead:
        print(f"DEAD — absent from the tree, so deleting them is a stale-claim FINDING ({len(dead)}):")
        for t in dead:
            print(f"    {t}")
        print()
    if live:
        print(f"LIVE — these exist in the tree. Account for each as folded / migrated "
              f"in the commit message, or restore it ({len(live)}):")
        for t in live:
            print(f"    {t}")
        print()
    if dropped_counts:
        print(f"NUMBERS no longer stated ({len(dropped_counts)}) — usually a correction, "
              "not a loss; confirm each:")
        print("    " + ", ".join(dropped_counts))
        print()

    return 1 if live else 0


if __name__ == "__main__":
    sys.exit(main())
