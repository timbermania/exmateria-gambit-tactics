#!/usr/bin/env python3
"""Clear Godot user data (saved rosters, settings, etc.)

Usage:
    uv run python tools/clear_user_data.py [--dry-run]

This clears saved data from:
- Windows: %APPDATA%/Godot/app_userdata/<project_name>/
- Linux: ~/.local/share/godot/app_userdata/<project_name>/
"""

import argparse
import os
import shutil
import sys
from pathlib import Path

# Project name as it appears in Godot's user data
# This comes from project.godot [application] config/name
PROJECT_NAME = "learning"


def get_user_data_paths() -> list[Path]:
    """Get possible Godot user data paths for this project."""
    paths = []

    # Windows path
    appdata = os.environ.get("APPDATA")
    if appdata:
        paths.append(Path(appdata) / "Godot" / "app_userdata" / PROJECT_NAME)

    # Also check Windows path from WSL
    # /mnt/c/Users/<user>/AppData/Roaming/Godot/app_userdata/<project>
    home = os.environ.get("HOME", "")
    if "/mnt/c/" in home or os.path.exists("/mnt/c/Users"):
        # Try to find Windows username
        import subprocess
        try:
            result = subprocess.run(
                ["cmd.exe", "/c", "echo", "%USERNAME%"],
                capture_output=True, text=True, timeout=5
            )
            win_user = result.stdout.strip()
            if win_user and win_user != "%USERNAME%":
                win_path = Path(f"/mnt/c/Users/{win_user}/AppData/Roaming/Godot/app_userdata/{PROJECT_NAME}")
                paths.append(win_path)
        except Exception:
            pass

    # Linux path
    xdg_data = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    paths.append(Path(xdg_data) / "godot" / "app_userdata" / PROJECT_NAME)

    return paths


def clear_user_data(dry_run: bool = False) -> None:
    """Clear all user data for the project."""
    paths = get_user_data_paths()

    found_any = False
    for path in paths:
        if path.exists():
            found_any = True
            print(f"Found: {path}")

            # List files that will be deleted
            for item in path.iterdir():
                print(f"  - {item.name}")

            if not dry_run:
                shutil.rmtree(path)
                print(f"  Deleted!")
            else:
                print(f"  (dry run - would delete)")

    if not found_any:
        print("No user data found at:")
        for path in paths:
            print(f"  - {path}")


def main():
    parser = argparse.ArgumentParser(description="Clear Godot user data")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be deleted without deleting")
    args = parser.parse_args()

    print(f"Clearing user data for project: {PROJECT_NAME}")
    print()

    clear_user_data(dry_run=args.dry_run)

    if args.dry_run:
        print()
        print("Run without --dry-run to actually delete.")


if __name__ == "__main__":
    main()
