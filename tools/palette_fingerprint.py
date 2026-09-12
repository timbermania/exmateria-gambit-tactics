#!/usr/bin/env python3
"""Palette-fingerprint owner resolution for composite EVTCHR segments.

A cinematic segment sheet can pack several characters' art into one 256x200 page,
distinguished only by which 16-colour CLUT row a unit samples (the `{7F}` palette
byte). The ROM stored no "who" axis. But a segment's embedded CLUT rows are the
characters' *actual palettes*: matching a row against every flat-store SPR palette
(`assets/sprites/textures/<id>.palette.tga`) recovers the owner exactly.

The match is a symmetric nearest-colour set distance ignoring near-black (the
shared dark/transparent entries). On real data the true owner is a *distance-0*
match with a wide margin to the runner-up (seg48: row0->0x18, row1->0x05,
row2->0x24, row3->0x0C, all dist 0; runners-up >= 281). So the resolver only
accepts an EXACT match -- a non-owner never scores 0.
"""

from __future__ import annotations

from pathlib import Path

from event_asset_slicing import segment_clut_row

# A colour whose R+G+B is <= this is treated as near-black/transparent and left
# out of the fingerprint (every row shares those; they carry no identity).
NEAR_BLACK_SUM = 24
# Mean per-colour squared distance below this counts as an exact match. Real
# owners score 0.0; the closest non-owner observed is ~281 -- so the gap is huge.
EXACT_MAX_DIST = 1.0


def _non_black(colors: list) -> list:
    """Drop near-black / fully-transparent entries from a colour list."""
    return [c for c in colors
            if c[3] > 0 and (c[0] + c[1] + c[2]) > NEAR_BLACK_SUM]


def _sq(a: tuple, b: tuple) -> int:
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


def color_set_distance(a: list, b: list) -> float:
    """Symmetric nearest-colour distance between two colour sets (RGB; alpha
    ignored). Each colour's nearest counterpart in the other set is summed both
    ways and averaged. 0.0 iff every colour has an exact match on both sides."""
    a, b = _non_black(a), _non_black(b)
    if not a or not b:
        return float("inf")
    total = sum(min(_sq(x, y) for y in b) for x in a)
    total += sum(min(_sq(y, x) for x in a) for y in b)
    return total / (len(a) + len(b))


def nearest_sprite(row_colors: list, sprite_palettes: dict) -> int | None:
    """The flat-store SPR whose palette EXACTLY matches `row_colors`, or None.

    `sprite_palettes` is `{spr_id -> [(r,g,b,a), ...]}`. Returns the id of the
    best (lowest-distance) palette only when that distance is an exact match
    (< EXACT_MAX_DIST); a merely-close palette yields None (the owner is always
    a distance-0 match on real data)."""
    row = _non_black(row_colors)
    if not row:
        return None
    best_id = None
    best_dist = float("inf")
    for spr_id, pal in sprite_palettes.items():
        d = color_set_distance(row, pal)
        if d < best_dist or (d == best_dist and best_id is not None and spr_id < best_id):
            best_dist, best_id = d, spr_id
    return best_id if best_dist < EXACT_MAX_DIST else None


def load_sprite_palettes(textures_dir: Path) -> dict:
    """`{spr_id -> [(r,g,b,a), ...]}` for every flat-store `<id>.palette.tga`.

    A flat-store SPR palette carries its 16 colours on CLUT row 0."""
    from event_asset_slicing import read_tga_bgra
    out: dict = {}
    for path in textures_dir.glob("*.palette.tga"):
        name = path.name[:-len(".palette.tga")]
        if name.lower().startswith("segment"):
            continue
        try:
            spr_id = int(name, 16)
        except ValueError:
            continue
        w, _h, bgra = read_tga_bgra(path)
        row0 = [(bgra[(c) * 4 + 2], bgra[c * 4 + 1], bgra[c * 4], bgra[c * 4 + 3])
                for c in range(w)]
        out[spr_id] = row0
    return out


class SegmentOwnerResolver:
    """Resolve `(segment, palette_row) -> owning SPR` by CLUT fingerprint.

    Holds the flat-store SPR palettes and reads a segment's `.palette.tga` row on
    demand (cached). `owner_of` returns the exact-match SPR or None (no owner /
    ambiguous / segment palette absent)."""

    def __init__(self, evtchr_dir: Path, sprite_palettes: dict):
        self.evtchr_dir = Path(evtchr_dir)
        self.sprite_palettes = sprite_palettes
        self._row_cache: dict = {}

    def _row_colors(self, segment: int, row: int) -> list | None:
        key = (segment, row)
        if key not in self._row_cache:
            pal = self.evtchr_dir / f"segment_{segment:03d}.palette.tga"
            self._row_cache[key] = segment_clut_row(pal, row) if pal.exists() else None
        return self._row_cache[key]

    def owner_of(self, segment: int, row: int) -> int | None:
        """The SPR whose palette exactly matches segment `segment` CLUT `row`."""
        colors = self._row_colors(segment, row)
        if not colors:
            return None
        return nearest_sprite(colors, self.sprite_palettes)

    def row_for_sprite(self, segment: int, spr_id: int, rows: int = 16) -> int | None:
        """The segment CLUT row whose palette exactly matches SPR `spr_id`, or None.

        Used by the single-resident-segment tier to recover a non-`{7F}` unit's
        palette row from its already-known (ENTD-resolved) SPR: find the row on the
        resident sheet that IS that character's palette."""
        target = self.sprite_palettes.get(spr_id)
        if not target:
            return None
        for row in range(rows):
            colors = self._row_colors(segment, row)
            if colors and color_set_distance(colors, target) < EXACT_MAX_DIST:
                return row
        return None
