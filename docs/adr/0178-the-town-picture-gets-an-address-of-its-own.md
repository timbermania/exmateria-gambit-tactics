# The town picture gets an address of its own

The console keeps all 92 `WLDPIC.BIN` entries at **one** VRAM address and swaps
them in place per node. The port's `vram.bin` is a single static bake and cannot
hold a region that changes, so **each of the 19 node-reachable pictures gets an
address of its own**, and the primitive carries that slot's `tpage`/CLUT/uv
instead of the console's fixed pair. `vram.bin` stays immutable; the picture
still resolves through the same VRAM/CLUT sampler as every other primitive on
the screen.

Status: accepted (2026-08-23). Implements
`research/working_documents/WORLD_MAP_SCREEN.md` §35.1/§35.5/§35.6. Consumed by
`src/world_map/WorldMapTownPage.gd`; produced by `tools/parse_world_map.py`.
Guarded by `tests/WorldMapTownTest.gd` and by the extractor's own read-back.

↺ **Renumbered.** Filed as `ADR-0155`; renamed to `0178` on 2026-08-26 because `0155`
was already taken on `import-godot-game` by `0155-where-the-source-that-left-the-walk-went-is-declared-once.md`.
Commit messages up to `01f49f87d` cite the old number.

## Context

§35.1 read `WLDPIC.BIN` as 92 standard PSX TIMs. Every one of them declares the
same two destinations in its own header: the CLUT to VRAM **(0,484)** and the
image to VRAM **(512,256)**. §35.5 then showed the load is eager and the upload
lazy — the picture for the node you are standing on is fetched on arrival and
`LoadImage`d only when ○ opens the page. There is one picture page on the
console and it is rewritten per node.

`WorldMapAssets` loads a single 1024×512 `vram.bin` produced at extract time and
samples it by tpage/CLUT the way the console's GPU does. A region that holds
different content at different moments has no representation in that model.

Two further facts were measured before deciding, and both narrow the choice:

- **Nothing in the port reads the picture band.** The band `x 512..571,
  y 256..335` is entirely zero in `vram.bin`, as is the CLUT row at (0,484).
  The console also time-multiplexes (512,256) with the START menu's source and
  the round-16/17 frame source — but the port's START menu *synthesises* its box
  from `assets/ui/frame.tga` rather than sampling VRAM, precisely because §34.7–
  §34.11 found no console-accurate pixel reference for it. So the "re-establish
  whatever else uses that band on exit" cost of modelling the upload has an
  empty referent here.
- **There is room.** `WLDTEX.TM2` and `EVENT/FRAME.BIN` leave `x 0..767,
  y 0..255` completely untouched — twelve of the thirty-two 64×256-halfword
  tpage cells, every halfword zero.

## Decision

**1. One slot per picture, allocated at extract time.** `place_pictures` in
`tools/parse_world_map.py` decodes each node-reachable TIM and blits it into a
slot of its own inside the empty half of VRAM. The node record gains
`picture_slot` — `tpage`, `clut`, `uv`, and the VRAM addresses the blit used.

**2. The layout is forced, not chosen.** A picture is 120×80 texels at 8bpp =
60×80 halfwords. A uv is 8-bit, so a primitive can reach only 256×256 texels =
128×256 halfwords from its tpage origin — one page, holding 2 across × 3 down =
6. A tpage origin is a multiple of (64, 256) halfwords. 19 pictures therefore
need `ceil(19/6) = 4` pages at `x = 0, 128, 256, 384`, `y = 0`. The CLUTs are
256 entries each and a CLUT x must be a multiple of 16; one per row at `x = 512`
keeps them clear of both the picture pages and everything `WLDTEX`/`FRAME.BIN`
write.

**3. `vram.bin` stays immutable.** This is the reason to prefer slots over
modelling the upload. `WorldMapRenderer` caches baked textures keyed on
`(tpage, clut, uv, shift)` and has no invalidation path; a mutable VRAM buffer
would introduce a stale-bake bug class that does not exist today, and every
future reader of `WorldMapAssets` would have to know the buffer can move under
them. The alternative — a live `upload()` on page entry plus a cache flush — is
more faithful and buys nothing this port can currently observe.

**4. The divergence is the ADDRESS and nothing else.** The picture is still one
`0x64` textured rect at screen-centred (-64,-76) 120×80, still 8bpp at abr 0,
still resolved through `WorldMapAssets.texel` and `clut_levels`, still composited
in the console's 5-bit channels. Only `tpage` and `clut` differ from `0x0298` /
`0x7900` — and *where the picture sits* is the one thing the console varies
anyway.

**5. The extractor refuses rather than overwrites, and reads back through the
packet.** Every slot is checked empty before the blit, so a future extractor
change that lands on one fails loudly instead of painting over it. Then each
picture is re-read through its own `tpage` + texel uv and compared to the disc
bytes: the blit addresses VRAM in halfwords and the primitive addresses it in
texels, `picture_slot` computes the two apart, and this is the only check that
they agree. Seeded with the uv doubling removed, it reports
`picture 2 slot 1: texel (0,0) reads 209 ... but the disc says 2`.

## Consequences

- A 20th node-reachable picture is free (24 slots exist); a 25th needs a fifth
  page, and `place_pictures` raises rather than silently wrapping.
- `vram.bin` grows no larger — the slots were already there, holding zeros.
- If a later round wants the console's swap-in-place model (to reproduce §35.5's
  one-slot cache, say, or the CD read), the extractor changes and
  `WorldMapTownPage` keeps its shape: it already reads the tpage/CLUT from the
  node rather than naming a constant.
- The other 73 pictures are not extracted. ShiShi's `PSXImages.xml` names them —
  16 **Proposition Areas**, 45 **Proposition Items**, 11 **Symbols**, one
  **Go** — and none is reachable from a node record, so none belongs to this
  screen.

## Prior art

`vendor/FFTPatcher/ShishiSpriteEditor` declares all 92 WLDPIC entries with
hand-authored offsets (`palette at entry+20, 512 bytes; pixels at entry+544`,
stride 10240) and decodes them row-major, one byte per pixel. Those are the TIM
header offsets written out flat, and they agree with the headers in the file on
palette offset, image offset, width and height for **92 of 92** — an independent
confirmation of the parse.

Two things in ShiShi are **not** adopted, and the port is right in both:

- `Palette.BytesToColor` expands 5 bits as `(v & 0x1F) << 3`, so level 31 → 248.
  That is an editor round-trip convenience (`ColorToBytes` inverts it exactly).
  The console's expansion is `(v << 3) | (v >> 2)` → 255, which is
  `WorldMapAssets.expand5`.
- `Build16BitPalette` makes palette entry 0 transparent when it is black, and
  `BytesToColor` maps the STP bit to alpha 0. `WorldMapAssets.clut_levels`
  documents the measured rule instead: transparency is a property of the CLUT
  **value** (`0x0000`), not of the index. The index convention holds for every
  4bpp sprite on this screen and is false for both aperture ramps; §22.3 cost
  956 pixels to that.
