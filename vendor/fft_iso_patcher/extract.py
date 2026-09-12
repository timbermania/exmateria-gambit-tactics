"""Extract a PSX FFT ISO into a directory tree.

Walks the ISO9660 hierarchy starting at the root, and writes each file's
user-data bytes to the corresponding path under ``out_dir``. The result
is a 1:1 mirror of the disc's filesystem — equivalent to what ``7z x``
or ``mkpsxiso -x`` would produce.

ISO9660 file names carry a ``;1`` version suffix; we strip it to match
what other tools expect (``BATTLE.BIN``, not ``BATTLE.BIN;1``).
"""

from __future__ import annotations

import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterator

from .asset_dirs import standard_iso_path
from .iso9660 import DirRecord, _list_dir, root_dir_record
from .iso_sectors import PsxDisc
from .iso_utils import bytes_to_sectors


@dataclass(frozen=True)
class ExtractedFile:
    iso_path: str        # e.g. "/SOUND/WAVESET.WD"
    out_path: Path       # absolute path on disk
    size_bytes: int


def _strip_version(name: str) -> str:
    """``"BATTLE.BIN;1"`` → ``"BATTLE.BIN"``. Leaves names without
    a version (directories, ``.`` and ``..``) untouched."""
    semi = name.rfind(";")
    return name[:semi] if semi >= 0 else name


def _walk(disc: PsxDisc, dir_rec: DirRecord, prefix: str) -> Iterator[tuple[str, DirRecord]]:
    """Yield ``(iso_path, record)`` for every file under ``dir_rec``,
    recursively. Skips ``.`` and ``..`` self-references."""
    for rec in _list_dir(disc, dir_rec.lba, dir_rec.size_bytes):
        # ISO9660 encodes "." and ".." as single bytes 0x00 / 0x01.
        if rec.name in ("\x00", "\x01"):
            continue
        clean = _strip_version(rec.name)
        path = f"{prefix}/{clean}" if prefix else f"/{clean}"
        if rec.is_dir:
            yield from _walk(disc, rec, path)
        else:
            yield path, rec


def extract(
    iso_path: Path,
    out_dir: Path,
    *,
    on_file: Callable[[ExtractedFile], None] | None = None,
    cache_iso: bool = True,
) -> list[ExtractedFile]:
    """Dump every regular file from ``iso_path`` into ``out_dir``.

    ``out_dir`` is created if missing. The disc's directory structure is
    mirrored under it. Existing files are overwritten.

    ``on_file`` is invoked once per extracted file (post-write). Useful
    for progress reporting from a CLI.

    ``cache_iso`` (default ``True``): also copy the source ISO to the
    standard exmateria ISO cache (``standard_iso_path()``) so other
    tools can default to it. Skipped if the source file already lives
    at that path.
    """
    disc = PsxDisc(iso_path)
    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[ExtractedFile] = []
    for iso_subpath, rec in _walk(disc, root_dir_record(disc), ""):
        # iso_subpath starts with "/"; strip and join under out_dir.
        rel = iso_subpath.lstrip("/")
        dest = out_dir / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        n_sectors = bytes_to_sectors(rec.size_bytes)
        # read_user_data returns a multiple of 2048; trim to the directory
        # record's declared size so we don't append sector padding.
        raw = disc.read_user_data(rec.lba, n_sectors) if n_sectors else b""
        dest.write_bytes(raw[: rec.size_bytes])
        entry = ExtractedFile(iso_path=iso_subpath, out_path=dest, size_bytes=rec.size_bytes)
        written.append(entry)
        if on_file is not None:
            on_file(entry)

    if cache_iso:
        cache_path = standard_iso_path()
        # Don't copy onto self.
        try:
            same = cache_path.resolve() == iso_path.resolve()
        except OSError:
            same = False
        if not same:
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(iso_path, cache_path)

    return written
