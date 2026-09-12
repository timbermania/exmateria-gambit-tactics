#!/usr/bin/env bash
# Sync the ExMateria Sound addon and FFT music assets into this game.
#
# Windows Godot cannot follow WSL symlinks on /mnt/c, so the addon and the
# sound files the game loads must be real on-disk copies inside the game tree.
# This script is the pipeline that populates them from the exmateria-sound source of
# truth and the project-assets extract. Both targets are gitignored.
#
# Re-run whenever the addon or the FFT extract changes (e.g. after rebuilding
# the native libraries, or pulling exmateria-sound updates).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$GODOT_DIR/.." && pwd)"

# The SIBLING package when this is the monorepo; the vendored copy when it is the
# standalone bring-your-own-ISO repo, where ../exmateria-sound/ does not exist.
# tools/check_vendor_sync.py holds the two byte-identical whenever both are here,
# so which one resolves can never change what the game loads.
pick_src() {  # <sibling-relative-to-repo-root> <vendor-dir-name>
    if [[ -d "$REPO_ROOT/$1" ]]; then printf '%s' "$REPO_ROOT/$1"
    else printf '%s' "$GODOT_DIR/vendor/$2"; fi
}
ADDON_SRC="$(pick_src exmateria-sound/addons/exmateria_sound exmateria_sound)"
ADDON_DST="$GODOT_DIR/addons/exmateria_sound"
# The SPU is its own addon since #384. It is a hard dependency of the sound
# addon — Spu is a global class_name — so a sync that copies one and not the
# other leaves the game with parse errors in files it does not own.
SPU_SRC="$(pick_src exmateria-sound/addons/exmateria_spu exmateria_spu)"
SPU_DST="$GODOT_DIR/addons/exmateria_spu"
SOUND_SRC="$REPO_ROOT/project-assets/fft-extract/SOUND"
MUSIC_DST="$GODOT_DIR/assets/music"

if [[ ! -d "$ADDON_SRC" ]]; then
    echo "error: addon source not found: $ADDON_SRC" >&2
    echo "       (neither ../exmateria-sound/ nor godot-learning/vendor/ has it;" >&2
    echo "        in the monorepo, re-run tools/vendor_packages.py)" >&2
    exit 1
fi
if [[ ! -d "$SPU_SRC" ]]; then
    echo "error: SPU addon source not found: $SPU_SRC" >&2
    exit 1
fi
if [[ ! -d "$SOUND_SRC" ]]; then
    echo "error: SOUND extract not found: $SOUND_SRC" >&2
    echo "       (is project-assets populated? see SETUP.md)" >&2
    exit 1
fi

# -L dereferences symlinks into real files. exmateria-sound's source tree
# symlinks bin/lib*.so to its top-level bin/ (resolves there, not here),
# and per this script's whole point the destination must be real on-disk
# copies anyway.
#
# rsync is NOT in Git for Windows, and it is the only thing in this script that
# is not, so a Windows clone died here rather than anywhere interesting. The one
# thing we ask of it is "make DST an exact copy of SRC, symlinks resolved",
# which wipe-then-`cp -RL` does everywhere. rsync stays the fast path.
mirror_dir() {  # <src-dir> <dst-dir>
    if command -v rsync >/dev/null 2>&1; then
        rsync -aL --delete "$1/" "$2/"
    else
        rm -rf "${2:?mirror_dir needs a destination}"
        mkdir -p "$2"
        cp -RL "$1/." "$2/"
    fi
}

echo "[sync] addon  $ADDON_SRC -> $ADDON_DST"
mkdir -p "$ADDON_DST"
mirror_dir "$ADDON_SRC" "$ADDON_DST"

echo "[sync] spu    $SPU_SRC -> $SPU_DST"
mkdir -p "$SPU_DST"
mirror_dir "$SPU_SRC" "$SPU_DST"

# Any platform's library counts. Globbing `linux.*.so` told every Windows user
# with a perfectly good .dll that their audio was broken, and named a build
# command that would not have helped them.
if ! ls "$SPU_DST"/bin/libexmateria_spu.*.so  >/dev/null 2>&1 \
&& ! ls "$SPU_DST"/bin/libexmateria_spu.*.dll >/dev/null 2>&1; then
    echo "[sync] WARNING: no libexmateria_spu in addons/exmateria_spu/bin/ for any" >&2
    echo "       platform — build it first, from the exmateria-sound project:" >&2
    echo "         scons platform=linux target=template_debug" >&2
    echo "       (Windows x86_64 DLLs are prebuilt and committed; see the README's" >&2
    echo "        platform-support section.)" >&2
fi

echo "[sync] music  $SOUND_SRC -> $MUSIC_DST"
mkdir -p "$MUSIC_DST"
cp -f "$SOUND_SRC/WAVESET.WD" "$MUSIC_DST/"
cp -f "$SOUND_SRC"/MUSIC_*.SMD "$MUSIC_DST/"

smd_count=$(ls "$MUSIC_DST"/MUSIC_*.SMD 2>/dev/null | wc -l)
echo "[sync] done: both addons synced, WAVESET.WD + $smd_count SMD files copied"
