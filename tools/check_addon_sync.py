#!/usr/bin/env python3
"""The host's DEPLOYMENT COPY of an extracted package must equal the package.

    python3 tools/check_addon_sync.py [--list] [--stamp]

`godot-learning/addons/exmateria_sound/` is not source. It is a gitignored copy
(`godot-learning/.gitignore:3`) that `tools/sync_exmateria_sound.sh` rsyncs from
`exmateria-sound/addons/exmateria_sound/`, because Windows Godot cannot follow a
WSL symlink on `/mnt/c` and the game must load real files. #410's acceptance
criterion is that the two are byte-identical.

NOTHING WAS CHECKING THAT, AND THEY WERE NOT. Measured on the canonical worktree
at `156758e9f`: **67 `.gd` files differed**, every one of them missing the
`## Vault: [[…]]` anchor lines added by `36bed6c8f` — the sync was simply never
re-run after that commit. Zero files were present on one side and absent on the
other, so nothing about the tree looked wrong; the game just loaded an older
addon than the one the package holds, silently, including in every test run.

A COPY WITH NO GUARD IS A CACHE WITH NO INVALIDATION. The sync is a manual step
at the end of a checklist, which is the same shape as every other defect this
branch found: it is green while nobody runs it. This makes the drift loud, and
it is the arm that makes `sync_exmateria_sound.sh` worth having.

A SYMLINKED DESTINATION IS IN STEP BY CONSTRUCTION, and that is not a pass this
guard hides. `tools/link_worktree_godot_assets.sh:161` points the destination at
the package in a secondary worktree, so there is no copy to drift; the guard says
so by name rather than reporting a vacuous OK. (That symlink is also why
`closure.py` and friends must walk with `followlinks=True` — see
`_walk_roots.walk_files`.)

Exit 0 = clean. Pure stdlib; run from the package root.
"""
import dataclasses
import filecmp
import os
import pathlib
import sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_DIR / "tools"))
import _walk_roots  # noqa: E402

# rsync writes these from the package; they are large, binary, and identical by
# construction when the .gd files are. Compared anyway — `-L` dereferences the
# package's own bin/ symlinks, so a stale .so is exactly the kind of thing that
# produces `Identifier "ExMateriaPsxSpu" not declared` three hours later.
SKIP_NAMES = {".DS_Store"}


def walk_rel(root: pathlib.Path) -> set:
    out = set()
    for dirpath, _dirnames, filenames in os.walk(root, followlinks=True):
        for n in filenames:
            if n in SKIP_NAMES:
                continue
            out.add(os.path.relpath(os.path.join(dirpath, n), root))
    return out


# --- one comparison, two readers ---------------------------------------------
# The full report below and the one-line banner stamp (`--stamp`, read by
# `tools/harness_stamp.py` into every run log) are two RENDERINGS of this, never
# two comparisons. A stamp derived by re-reading this tool's prose would be the
# second opinion #451 spent a ticket collapsing.

@dataclasses.dataclass
class Status:
    system: str
    name: str
    state: str            # missing | symlink | identical | stale
    dst: pathlib.Path
    src: pathlib.Path = None
    link: str = ""
    files: int = 0
    differ: list = dataclasses.field(default_factory=list)
    only_src: list = dataclasses.field(default_factory=list)
    only_dst: list = dataclasses.field(default_factory=list)

    @property
    def clean(self) -> bool:
        return self.state in ("symlink", "identical")


def statuses() -> list:
    """One `Status` per extracted package declared in `_walk_roots.EXTRACTED`."""
    out = []
    for e in _walk_roots.extracted_roots():
        dst = PROJECT_DIR / "addons" / e.path.name
        if not dst.exists():
            out.append(Status(e.system, e.path.name, "missing", dst, e.path))
            continue
        if dst.is_symlink():
            out.append(Status(e.system, e.path.name, "symlink", dst, e.path,
                              link=os.readlink(dst)))
            continue
        src_files, dst_files = walk_rel(e.path), walk_rel(dst)
        only_src = sorted(src_files - dst_files)
        only_dst = sorted(dst_files - src_files)
        differ = sorted(f for f in src_files & dst_files
                        if not filecmp.cmp(e.path / f, dst / f, shallow=False))
        state = "identical" if not (only_src or only_dst or differ) else "stale"
        out.append(Status(e.system, e.path.name, state, dst, e.path,
                          files=len(src_files), differ=differ,
                          only_src=only_src, only_dst=only_dst))
    return out


def stamp() -> str:
    """The banner line — what a RUN can say about its own addon copy.

    A run log is the only place this fact can be recorded truthfully, because the
    copy can drift between the run and whenever somebody reads the register. See
    `tools/suite_register.py`: provenance is a property of the run.
    """
    st = statuses()
    if not st:
        return "no extracted package declared"
    parts = []
    for s in st:
        if s.state == "missing":
            parts.append(f"{s.name}=MISSING (no deployment copy)")
        elif s.state == "symlink":
            parts.append(f"{s.name}=symlinked (in step by construction)")
        elif s.state == "identical":
            parts.append(f"{s.name}=in-step ({s.files} files byte-identical)")
        else:
            parts.append(f"{s.name}=STALE ({len(s.differ)} differ, "
                         f"{len(s.only_src)} missing, {len(s.only_dst)} extra)")
    return "; ".join(parts)


def main() -> int:
    if "--stamp" in sys.argv:
        print(stamp())
        return 0
    rc = 0
    checked = []
    for s in statuses():
        e_path, dst = s.src, s.dst
        checked.append(f"{s.system} {s.name}")
        if s.state == "missing":
            print(f"MISSING DEPLOYMENT COPY — {s.system}: {dst} does not exist. "
                  f"Run tools/sync_exmateria_sound.sh.")
            rc = 1
            continue
        if s.state == "symlink":
            print(f"{s.system} ({s.name}): destination is a SYMLINK -> "
                  f"{s.link} — in step by construction, nothing to compare "
                  f"(a linked worktree; see tools/link_worktree_godot_assets.sh).")
            continue

        only_src, only_dst, differ = s.only_src, s.only_dst, s.differ
        if s.state == "identical":
            print(f"{s.system} ({s.name}): deployment copy is byte-identical "
                  f"({s.files} files).")
            continue

        rc = 1
        print(f"\nDEPLOYMENT COPY IS STALE — {s.system}\n"
              f"  package: {_rel(e_path)}\n"
              f"  host:    {_rel(dst)}\n"
              f"  {len(differ)} differ, {len(only_src)} missing from the host, "
              f"{len(only_dst)} the package does not have.\n")
        show = ("--list" in sys.argv)
        for label, group in (("differs", differ), ("host is missing", only_src),
                             ("host has extra", only_dst)):
            for f in (group if show else group[:8]):
                print(f"  {label:<16} {f}")
            if not show and len(group) > 8:
                print(f"  {'':<16} … and {len(group) - 8} more (--list)")
        print("\nFix: run tools/sync_exmateria_sound.sh from the package root. #410's AC is\n"
              "byte-identical; the game loads the HOST copy, so a stale one means every\n"
              "run — tests included — exercises an older package than the one you edited.")
    if not checked:
        print("no extracted package declared in _walk_roots.EXTRACTED — nothing to check")
    return rc


def _rel(q: pathlib.Path) -> str:
    try:
        return q.relative_to(PROJECT_DIR).as_posix()
    except ValueError:
        return os.path.relpath(q, PROJECT_DIR).replace("\\", "/")


if __name__ == "__main__":
    sys.exit(main())
