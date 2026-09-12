"""Decode the {91} ShowMapTitle location-name images → PNG textures + manifest.

ShowMapTitle(X, Y, Speed) reveals a pre-battle location-name text strip (e.g.
"Military Academy's Auditorium") with a left→right wipe, holds, then erases it
with a SECOND left→right wipe. The opcode carries NO image index — the strip is
selected by the current map: the ATTACK.OUT worker reads event var 0x33 (= the
battle's map_id) and uploads strip (map_id - 1). See the map→slot table below.

The images live in EVENT/MAPTITLE.BIN, decoded deterministically from the ISO
extract (no live VRAM capture needed):

    EVENT/MAPTITLE.BIN   120 strips × 2560 B   256×20 4bpp indexed, low-nibble=left
                         115 inked (0..114 mostly), trailing blanks

Each strip is 256×20 (0xA00 = 2560 B) — the exact size the ATTACK.OUT worker
uploads to VRAM (rect (448,224,64,20) = 256×20 @ 4bpp). The top rows carry a thin
decorative rule; the location text sits below it. (An earlier 256×16/2048-stride
read was WRONG — it dropped the rule rows and mis-indexed; the stride is 2560,
byte-proven by a full 20-row VRAM match, op91 decode §5/§6.2.)

Unlike the CHAPTER cards ({7D}), MAPTITLE strips carry NO embedded CLUT. The
palette is a fixed 16-step grey ramp read from static ROM data in EVENT/ATTACK.OUT
(file 0x16FF0 = VA 0x801D5FF0, the pointer the worker uploads from); idx0 = 0x0000
(transparent background), idx15 = 0xFFFF (white). Same ramp for every title.

Format + reveal/erase + ROM provenance (every constant cited to an ATTACK.OUT
file offset): research/working_documents/scenario_1_captures/show_map_title_op91_decode.md.

Output:
    assets/scenarios/map_titles/title_<NNN>.png     one PNG per inked strip
    assets/scenarios/map_titles/map_titles.json     manifest keyed by strip index

Usage:
    uv run python tools/parse_map_titles.py
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

from _repo_paths import event_dir, assets_dir

# --- MAPTITLE.BIN layout (byte-proven, op91 decode §5) -----------------------
STRIP_SIZE = 2560            # 0xA00 bytes per strip (256×20 @ 4bpp) — the load stride
STRIP_COUNT = 120            # 307200 / 2560 = 120 strips total
TITLE_W, TITLE_H = 256, 20   # each strip = 256×20 4bpp indexed

# --- The external CLUT — sourced from the ROM (EVENT/ATTACK.OUT) --------------
# MAPTITLE strips carry no embedded CLUT; the ATTACK.OUT map-title worker uploads
# a fixed 16-entry grey ramp (idx0 = transparent bg, idx15 = white) from static
# overlay data at VA 0x801D5FF0 = ATTACK.OUT load base 0x801BF000 + file offset
# 0x16FF0 (op91 decode §5.2). We read it straight from the ROM file so the asset
# is ROM-derived, NOT baked from a savestate/VRAM capture. ATTACK_OUT_CLUT below
# is the expected byte-values, kept ONLY as a cross-check assertion.
ATTACK_OUT_CLUT_OFF = 0x16FF0
ATTACK_OUT_CLUT = [
    0x0000, 0x8842, 0x9084, 0x98C6, 0xA108, 0xA94A, 0xB18C, 0xB9CE,
    0xC210, 0xCE73, 0xD6B5, 0xDEF7, 0xE739, 0xEF7B, 0xF7BD, 0xFFFF,
]


def read_maptitle_clut(fft_extract: str | None) -> list[int]:
    """The 16-entry map-title CLUT, read from EVENT/ATTACK.OUT (ROM-derived).

    Returns the RGB555 words at ATTACK.OUT file offset 0x16FF0. Cross-checks
    against ATTACK_OUT_CLUT and raises if they disagree, so a wrong offset / a
    changed ROM is caught loudly rather than silently baking a bad palette.
    """
    ao = (event_dir(fft_extract) / "ATTACK.OUT").read_bytes()
    off = ATTACK_OUT_CLUT_OFF
    if off + 32 > len(ao):
        raise SystemExit(f"ATTACK.OUT too small for CLUT @0x{off:X}")
    clut = [ao[off + i * 2] | (ao[off + i * 2 + 1] << 8) for i in range(16)]
    if clut != ATTACK_OUT_CLUT:
        raise SystemExit(
            "ATTACK.OUT map-title CLUT @0x%X changed — got %s, expected %s "
            "(re-verify the offset before baking assets)"
            % (off, [hex(v) for v in clut], [hex(v) for v in ATTACK_OUT_CLUT]))
    return clut


# --- ROM-sourced render params (ALL from EVENT/ATTACK.OUT, op91 decode §II) ---
# The {91} worker (SUB_801c9ec0 @ file 0xAEC0) builds the on-screen quad + drives
# the reveal/hold/erase from immediate constants, cited here to their ATTACK.OUT
# file offset. There is NO file-resident geometry template (unlike {7D}'s ETC.OUT
# 0x1668) — the geometry is computed from these constants + the X/Y operands.
ROM = {
    # placement (builder SUB_801c992c) — primitive-space, before the battle
    # draw-env offset; X/Y opcode operands are ADDED to these bases.
    "prim_x_base": 128,     # 0xA9A0  addiu v0,t0,128   left_X = Xop + 128
    "prim_y_base": 96,      # 0xAA68  addiu v1,a2,96    top_Y  = Yop + 96
    "height": 20,           # 0xAA9C  quad height (= 256×20 strip)
    "grow_limit": 248,      # 0xADD8  slti s2,248       reveal grows 8→248 (== {7D})
    # animation (task body @ 0xAD68) — one step per BATTLE vsync, step = Speed.
    "reveal_start": 8,      # 0xAD98  initial extent
    "hold_frames": 110,     # 0xAE24  slti 110          HOLD length (cf {7D} 80)
    "erase_limit": 249,     # 0xAE88  slti 249          erase grows 8→249 (2nd L→R wipe)
    "grey": 128,            # 0xADC4  ori a2,0x80       interior grey level
    "edge": 32,             # 0xABD4  ori a0,0x20       soft L→R edge kernel (px)
    # upload (worker @ 0xAF38) — image + CLUT RECTs, static descriptor @0x16FC0.
    "upload_rect": [448, 224, 64, 20],   # file 0x16FC0
    "clut_rect": [448, 255, 16, 1],      # file 0x16FC8
    "vtex_top": 224, "vtex_bottom": 244, # 0xA978/0xA97C
    # id → slot: the worker reads event var 0x33 (= strip index); the strip is at
    # file (idx)*0xA00. The map_id→var0x33 assignment lives in scene setup (GAP).
}

# --- map/scenario → MAPTITLE strip index -------------------------------------
# RESOLVED (was op91 decode GAP-3.1): the mapping is arithmetic, NOT an opaque
# table. The {91} worker (attackout_map_title_worker_entry @ 0x801C9EC0, file off
# 0xAEC0) reads event var 0x33 — which holds the battle's map_id, set at scene
# setup — subtracts 1, and uploads MAPTITLE.BIN strip (map_id - 1). MAPTITLE.BIN
# is thus a flat array in map_id-1 order: strip i is the title for map_id i+1.
#   Disasm:  jal get_event_var(0x33) -> v0;  strip = v0 - 1  (0x801C9EE4..0xAF50).
#   Proven:  map 24  -> strip 23  "Military Academy's Auditorium" (byte-match, scn8)
#            map 104 -> strip 103 "Beoulve Residence"            (scn14, visual)
#            + every KNOWN_NAMES slot == map_names[slot+1].
# The full table is derived in main() from the inked strips (map_id = strip + 1).

# Human names, read off a decoded 256×20 montage (documentation only; the game
# keys by index). 0..29 visually confirmed; the tail is derivable from FFTacText.
KNOWN_NAMES: dict[int, str] = {
    0: "At main gate of Igros Castle",
    1: "Back gate of Lesalia Castle",
    2: "Hall of St. Murond Temple",
    3: "Office of Lesalia Castle",
    4: "Roof of Riovanes Castle",
    5: "At the gate of Riovanes Castle",
    6: "Inside of Riovanes Castle",
    7: "Riovanes Castle",
    8: "Citadel of Igros Castle",
    9: "Inside of Igros Castle",
    10: "Office of Igros Castle",
    11: "At the gate of Lionel Castle",
    12: "Inside of Lionel Castle",
    13: "Office of Lionel Castle",
    14: "At the gate of Limberry Castle",
    15: "Inside of Limberry Castle",
    16: "Underground cemetery of Limberry Castle",
    17: "Office of Limberry Castle",
    18: "At the gate of Limberry Castle",
    19: "Inside of Zeltennia Castle",
    20: "Zeltennia Castle",
    21: "Magic City Gariland",
    22: "Beoulve residence",
    23: "Military Academy's Auditorium",
    24: "Yardow Fort City",
    25: "Weapon storage of Yardow",
    26: "Goland Coal City",
    27: "Colliery underground First floor",
    28: "Colliery underground Second floor",
    29: "Colliery underground Third floor",
}


def _rgb555(v: int) -> tuple[int, int, int]:
    """PSX 16bpp RGB555 → 8-bit RGB (bit15 = STP/mask, ignored for color)."""
    return ((v & 31) << 3, ((v >> 5) & 31) << 3, ((v >> 10) & 31) << 3)


def decode_title(strip: bytes, clut: list[int]) -> Image.Image:
    """256×20 4bpp strip, low-nibble = left pixel, ROM grey-ramp CLUT.

    Index 0 (background) is emitted transparent so the additive reveal/erase only
    touches the visible rule/glyph pixels; the scene shows through the bg.
    """
    pal = [_rgb555(v) for v in clut]
    img = Image.new("RGBA", (TITLE_W, TITLE_H))
    pm = img.load()
    bpr = TITLE_W // 2
    for y in range(TITLE_H):
        for x in range(TITLE_W):
            byte = strip[y * bpr + (x >> 1)]
            nib = (byte & 0xF) if (x & 1) == 0 else (byte >> 4)
            r, g, b = pal[nib]
            pm[x, y] = (r, g, b, 0 if nib == 0 else 255)
    return img


def is_blank(strip: bytes) -> bool:
    """A strip with no inked pixels (trailing pad slots)."""
    return not any(strip)


def main() -> None:
    ap = argparse.ArgumentParser(description="Decode {91} ShowMapTitle textures")
    ap.add_argument("--fft-extract", help="FFT extract root override")
    ap.add_argument("--out", help="output dir (default assets/scenarios/map_titles)")
    args = ap.parse_args()

    ev = event_dir(args.fft_extract)
    out = Path(args.out) if args.out else assets_dir("scenarios/map_titles")
    out.mkdir(parents=True, exist_ok=True)

    data = (ev / "MAPTITLE.BIN").read_bytes()
    clut = read_maptitle_clut(args.fft_extract)  # ROM-derived (ATTACK.OUT)
    n_strips = len(data) // STRIP_SIZE
    if n_strips < STRIP_COUNT:
        raise SystemExit(
            f"MAPTITLE.BIN too small: {len(data)} B = {n_strips} strips "
            f"(expected {STRIP_COUNT})")

    titles: dict[str, dict] = {}
    for idx in range(n_strips):
        strip = data[idx * STRIP_SIZE:(idx + 1) * STRIP_SIZE]
        if is_blank(strip):
            continue
        fn = f"title_{idx:03d}.png"
        decode_title(strip, clut).save(out / fn)
        entry: dict = {"file": fn, "w": TITLE_W, "h": TITLE_H}
        if idx in KNOWN_NAMES:
            entry["name"] = KNOWN_NAMES[idx]
        titles[str(idx)] = entry

    manifest = {
        "clut": [f"0x{v:04X}" for v in clut],
        "clut_source": "EVENT/ATTACK.OUT @0x%X (VA 0x801D5FF0)" % ATTACK_OUT_CLUT_OFF,
        # ROM-sourced render params (every value cited to an ATTACK.OUT file
        # offset in ROM[] above) — the controller drives placement + reveal/hold/
        # erase from THESE, not from a savestate/framebuffer measurement.
        "render": ROM,
        "render_source": "EVENT/ATTACK.OUT worker SUB_801c9ec0 (file 0xAEC0)",
        # map_id -> strip: the worker computes strip = event_var(0x33) - 1, and
        # var 0x33 == the battle map_id (proven; see the map→slot note above).
        # So map_id i+1 selects inked strip i. Derived, not hand-seeded.
        # Only INKED strips are in `titles`, so a map whose strip is blank gets no
        # entry → slot_for_map returns -1 → Godot shows nothing AND does not arm the
        # {91} VM block. PSX runs strip=map_id-1 unconditionally and blocks ~591f even
        # on a blank strip, so the two diverge there — latent (the 115 inked strips
        # 0..114 are contiguous; only trailing 115..119 = map_ids 116..120 are blank,
        # and no known scene reaches {91} on those). Revisit if one ever does.
        "map_id_to_slot": {str(int(k) + 1): int(k) for k in titles},
        "map_id_to_slot_source": "ATTACK.OUT worker 0x801C9EE4: strip = var0x33(=map_id) - 1",
        "titles": titles,
    }
    (out / "map_titles.json").write_text(json.dumps(manifest, indent=2))
    print(f"Wrote {len(titles)} map titles + map_titles.json to {out}")


if __name__ == "__main__":
    main()
