"""CLI entry: `python -m fft_iso_patcher` / `fft-iso-patcher`."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

from .asset_dirs import standard_assets_dir
from .assets.map import summary_line as _map_summary_line
from .constants import MUSIC_TABLE_OFFSET, N_MUSIC_SLOTS, SCUS_PATH
from .extract import ExtractedFile, extract
from .iso9660 import find_file
from .iso_sectors import PsxDisc
from .iso_utils import bytes_to_sectors
from .patcher import apply


def _cmd_apply(args: argparse.Namespace) -> int:
    manifest = apply(Path(args.recipe))
    print(f"Applied {len(manifest.placements)} patch(es).")
    if manifest.placements:
        for p in manifest.placements:
            if p.get("kind") == "map":
                # A raw resource list would be a wall of text (§5).
                print(f"  {_map_summary_line(p)}")
            else:
                print(f"  {p.get('kind')}: {p}")
    if args.recipe.endswith(".toml"):
        # Show output paths for clarity.
        print(f"Output ISO: {manifest.iso_out}")
    return 0


def _cmd_tui(args: argparse.Namespace) -> int:
    # Import lazily so `apply` / `inspect` don't pay the textual import cost.
    from .tui import PatcherApp

    PatcherApp().run()
    return 0


def _cmd_extract(args: argparse.Namespace) -> int:
    iso = Path(args.iso)
    out = Path(args.out) if args.out else standard_assets_dir()
    if out.exists() and any(out.iterdir()) and not args.force:
        print(
            f"Refusing to extract into non-empty {out} (use --force to overwrite).",
            file=sys.stderr,
        )
        return 2

    print(f"Extracting {iso}")
    print(f"        -> {out}")

    count = 0
    total_bytes = 0

    def progress(entry: ExtractedFile) -> None:
        nonlocal count, total_bytes
        count += 1
        total_bytes += entry.size_bytes
        if not args.quiet and (count % 50 == 0 or count == 1):
            print(f"  [{count:>5}] {entry.iso_path}")

    extracted = extract(iso, out, on_file=progress)
    print(f"Extracted {len(extracted)} files ({total_bytes / 1_000_000:.1f} MB) to {out}")
    print()
    print("exmateria-sound and the DAW plugin will pick this up automatically.")
    print(f"To override the location, set EXMATERIA_ASSETS_DIR={out}")
    return 0


def _cmd_inspect(args: argparse.Namespace) -> int:
    disc = PsxDisc(Path(args.iso))
    print(f"ISO: {disc.path}  ({disc.total_sectors} sectors, "
          f"{disc.total_sectors * 2352} bytes)")
    scus = find_file(disc, SCUS_PATH)
    print(f"SCUS_942.21;1: lba={scus.lba}  size={scus.size_bytes}")
    sectors = bytes_to_sectors(scus.size_bytes)
    user = disc.read_user_data(scus.lba, sectors)
    table = user[MUSIC_TABLE_OFFSET:MUSIC_TABLE_OFFSET + N_MUSIC_SLOTS * 8]
    print("Music table (LBA, size_bytes_padded):")
    for i in range(N_MUSIC_SLOTS):
        lba, size = struct.unpack_from("<II", table, i * 8)
        flag = " <-- MUSIC_41" if i == 41 else ""
        print(f"  MUSIC_{i:02d}: lba={lba:6d}  size={size:6d}{flag}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="fft-iso-patcher",
                                     description="Patch a PSX FFT ISO from a TOML recipe.")
    # No-args = launch the TUI. This is what most people want, and it makes
    # double-clicking the .exe on Windows do something useful (otherwise the
    # console flashes and closes when argparse complains about a missing
    # subcommand). Explicit `tui` subcommand still works.
    sub = parser.add_subparsers(dest="cmd")

    apply_p = sub.add_parser("apply", help="Apply a recipe to a PSX FFT ISO.")
    apply_p.add_argument("--recipe", required=True, help="Path to recipe.toml")
    apply_p.set_defaults(func=_cmd_apply)

    inspect_p = sub.add_parser("inspect", help="Print the music LBA table from an ISO.")
    inspect_p.add_argument("--iso", required=True, help="Path to PSX FFT ISO bin.")
    inspect_p.set_defaults(func=_cmd_inspect)

    extract_p = sub.add_parser(
        "extract",
        help="Dump the disc tree (BATTLE.BIN, SOUND/, EFFECT/, ...) so exmateria-sound and the DAW plugin can find it.",
    )
    extract_p.add_argument("iso", help="Path to PSX FFT ISO bin.")
    extract_p.add_argument(
        "--out",
        help="Destination directory (default: platform-standard exmateria assets dir).",
    )
    extract_p.add_argument("--force", action="store_true", help="Overwrite a non-empty destination.")
    extract_p.add_argument("--quiet", action="store_true", help="Suppress per-file progress.")
    extract_p.set_defaults(func=_cmd_extract)

    tui_p = sub.add_parser("tui", help="Launch the interactive TUI.")
    tui_p.set_defaults(func=_cmd_tui)

    args = parser.parse_args(argv)
    if args.cmd is None:
        # Fall through to the TUI as the default action.
        return _cmd_tui(args)
    return args.func(args)


def extract_main(argv: list[str] | None = None) -> int:
    """Entry point for the standalone ``exmateria-extract`` console script."""
    parser = argparse.ArgumentParser(
        prog="exmateria-extract",
        description=(
            "Extract the FFT PSX disc into the standard exmateria assets "
            "directory so exmateria-sound and the DAW plugin can find it."
        ),
    )
    parser.add_argument("iso", help="Path to PSX FFT ISO bin.")
    parser.add_argument(
        "--out",
        help="Destination directory (default: platform-standard exmateria assets dir).",
    )
    parser.add_argument("--force", action="store_true", help="Overwrite a non-empty destination.")
    parser.add_argument("--quiet", action="store_true", help="Suppress per-file progress.")
    args = parser.parse_args(argv)
    return _cmd_extract(args)


if __name__ == "__main__":
    sys.exit(main())
