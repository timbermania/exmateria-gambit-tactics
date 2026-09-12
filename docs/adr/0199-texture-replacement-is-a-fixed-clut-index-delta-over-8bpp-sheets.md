# Texture replacement is a fixed-CLUT index delta over 8bpp sheets

## Status

accepted

## Context

#280 asks the Effect Studio to let an author **replace an effect's texture** —
the largest single gap in the file at 33,796 B (`texture_ptr` → EOF, the last
section). #280's settled format is an RGBA `.tga` matching
`godot-learning/tools/extract_effect_texture.lua` byte for byte, so artists can
paint in any tool that opens TGA-with-alpha; the studio quantizes back to
indexed + BGR555 on import. v1 forbids resize.

A pre-build corpus audit (`texture_roundtrip_gate.py` and passes 2–4, over all
401 non-empty effects) measured whether that round trip is actually invertible.
It is not, for two independent reasons, and both change the design.

**1. A colour does not identify an index.** 265 of 401 effects hold the same
BGR555 word at two or more palette indices — 8bpp effects average **88
duplicate entries out of 256**. An RGBA image carries colours, not indices, so
`decode → re-encode` picks *a* legal index rather than *the* original one. The
dominant pattern is a large filler region drawn with a high index whose colour
equals palette[0]: E216 remaps 29,538 of 32,768 pixels (90%) from index 201 to
index 0. Naive round-tripping is byte-exact for only **230/401 (57%)** — and
crucially, all 401 are **colour**-exact, i.e. they render identically. Byte
divergence here is ambiguity, not corruption.

**2. A 4bpp sheet is not one image.** Each frame selects a 16-colour
sub-palette via `flags_byte0 & 0x0F`. Across the corpus:

| depth | effects | using >1 sub-palette | sub-palette sets seen |
|---|---|---|---|
| 8bpp | 339 | **1** (E040) | `(0,)` ×338 |
| 4bpp | 60  | **58** | `(0,1,2)`, `(0..4)`, `(0..6)`, … |

DISPLAYING such a sheet correctly is **not** the problem: each frame carries its
own CLUT, so a preview can decode every frame's UV region through that frame's
own sub-palette and composite the sheet truthfully. The blocker is the
**inverse** — going from a painted RGBA image back to 4-bit indices, where a
texel's index is shared by every frame that samples it.

Measured over all 60 4bpp sheets (`texture_gate5.py`), by walking every frame's
UV rect:

| | result |
|---|---|
| sheets with texels read through **conflicting** sub-palettes | **30 of 60** |
| conflicting texels | 40,287 (10.3% of all covered texels) |
| sheets whose frames cover every texel | **0 of 60** |
| texels referenced by any frame at all | **39.4%** |

A conflicting texel has two readers expecting different palettes, so no single
index satisfies both — whatever the artist painted, one of the two frames
renders the wrong colour. And because no sheet is fully covered, ~60% of a 4bpp
sheet has no sub-palette attribution in *either* direction: nothing defines what
colour those texels are, so they can be neither exported truthfully nor
inverted.

(A future 4bpp ticket therefore has a narrower opening than "paint the sheet":
region-based authoring over the covered texels of the 30 conflict-free sheets.
The preview is not what needs building — the attribution model is.)

Two further measurements constrain the writer. The pixel plane fills
`texture_ptr + 0x404 → EOF` **exactly** for 401/401 (zero tail slack), so the
splice geometry is unambiguous. And the colour budget is near-saturated — 8bpp
sheets average **161.7** distinct colours against a hard cap of 256, several
using all 256 — so re-deriving a palette from an arbitrary painted image would
have to evict colours the sheet is still using.

## Decision

1. **The CLUT is fixed; only the pixel plane is authored.** Import never
   rewrites palette bytes. Incoming RGBA is matched *into* the existing palette.
   This follows from the colour budget: there is no headroom to re-derive a
   palette without evicting live colours, and 16 of the 8bpp effects share a
   second palette whose entries no pixel in this sheet references.

2. **Quantization is an index delta against the original plane, not a blind
   re-quantize.** For each texel: if the imported colour still equals the colour
   of the texel's **original index**, keep that index; otherwise pick the
   nearest CLUT entry. Re-importing an unmodified export is therefore byte-exact
   for **401/401**, and a save diff contains only genuinely repainted pixels.
   Blind nearest-colour matching was rejected: it rewrites 43% of the corpus's
   pixel bytes on a no-op re-import, making every diff look like a full repaint.

3. **v1 covers 8bpp single-sub-palette sheets only — 338 effects.** 4bpp sheets
   and E040 (the one mixed-depth 8bpp effect, sub-palettes 0/4/5) are **refused
   with a stated reason**, not silently mis-imported. Faithful 4bpp authoring
   needs a per-frame-region export and is its own ticket.

4. **The write is a section splice, not a field patch.** `@register("texture")`
   in `effect_writer_registry.py` replaces `[texture_ptr + 0x404, EOF)` wholesale
   and **refuses a length mismatch**, mirroring `serialize_sound_def`. Palette
   bytes `[texture_ptr, texture_ptr + 0x400)` and the 4-byte VRAM header at
   `+0x400` are never written by this serializer.

5. **Undo is a snapshot, not a scalar.** A 33 KB plane has no meaningful
   before/after scalar, so the texture channel takes the `"feds"` branch of
   `EffectEditSession.undo()` — swap the whole blob — rather than the scalar
   before/after path every other channel uses.

6. **Both directions live in the studio.** Export writes the RGBA TGA
   (a Godot-side port of the Lua extractor's byte layout, so the loop does not
   depend on the Lua/PCSX tool); Import reads one back. Alpha is the STP bit
   throughout, per ADR-0096 — and because the CLUT is fixed, alpha is only ever
   a *matching* input, never a written bit.

## Consequences

- The build's green bar is **not** "byte-exact round trip" — that is unreachable
  through an RGBA intermediate. It is: (a) re-import of an unmodified export is
  byte-exact for every in-scope effect, and (b) re-import of any RGBA image is
  colour-exact under the fixed CLUT.
- An artist cannot introduce a new colour. The importer reports off-palette
  pixels and their colour error rather than failing, so a near-miss from a
  colour-managed editor is visible instead of silent.
- **Opacity is decided in two places, and only one of them is the palette.**
  A texel renders opaque when either the FRAME's semi-transparency enable
  (`semi_trans_on`, flags_byte1 bit 1) is clear — in which case every non-black
  texel of that sprite is opaque and no blend pass exists — or that bit is set
  and the texel's palette entry has STP=0. So:
    * **Whole-sprite opaque is already authorable** and needs nothing from this
      ADR: it is the frame's `semi_trans_on`, editable since #278.
    * **Mixed opaque-and-blended texels WITHIN one enabled sprite** is the only
      case that needs the palette, because STP is a property of a CLUT ENTRY.
      With the CLUT fixed, that works only where the palette already holds an
      STP=0 non-black entry — and measured over the 338 in-scope sheets, **328
      have zero such entries** (10 have any; 9 of those exactly one). The corpus
      agrees that this is how the ROM is built: 72.1% of texels transparent,
      27.9% STP, and an *opaque* class of just 254 texels across 4 effects.
  Only that second case needs a palette-side route (making CLUT entries
  editable), which this ADR excludes. It is a narrow follow-on, not a claim that
  opaque art is unauthorable.
- **338 of the 401** non-empty effects are authorable. The other 63: the 60 4bpp
  sheets (including the 2 that happen to use a single sub-palette — one rule, no
  special cases), E040 (frames disagree on depth), and E509/E510 (a texture no
  frame references, so no depth is established). The manifest carve reflects
  that real scope rather than claiming the whole 33,796 B gap.
- A corpus scan must fall back to an embedded-header search: three effects —
  E259/E338/E464 — open with `0x00054040` rather than a MIPS prologue, so
  `parse_effect.find_header_offset` returns 0 and reads a bogus header. Without
  the fallback a scan silently covers 398 of 401 while reporting success.
- A texture-shape change still cascades into every frame's UV fields, which is
  why v1 forbids resize; the v2 "defrag" ticket owns that, and is cheaper than
  it looks because this is the last section in the file.
- **The preview swap is a PUSH, not just a model write** (added 2026-08-18, after
  the first user report of "import does nothing"). `TextureChannel.replace` mints
  a NEW `ImageTexture` on `EffectData.texture`, and the surfaces that display the
  sheet each cached the *old object*: the particle renderer binds it into its pool
  slot's shader material (and the slot's `_effect_tex`) once at `initialize()`,
  and the frameset canvas rebinds only when the inspection target changes.
  `EffectInstance.refold()` re-runs the sim but never touches materials, so it
  cannot fix either. A texture swap therefore lowers as three steps —
  `refresh_texture()` (re-push the uniforms), `refold()` (re-run the sim that
  samples them), and a page re-render (rebind the canvas) — and the same three
  apply to the UNDO, which restores the previous texture object. Per-spawn
  callbacks rebind inside `_on_init`, so the refold already covers them.
- **Every refusal is reported on screen.** The scope gate, the .tga decoder, and
  the dimension check all reject with a reason, and those reasons reach the
  studio's transport-bar status strip rather than `push_warning`. A silent refusal
  is indistinguishable from a working import, which is how the missing push above
  survived roughly 120 green assertions: they all tested seams in isolation. The
  guard for the live path is `tests/EffectStudioTextureImportAcceptanceTest.gd`,
  which boots the real scene and asserts on both display surfaces.
- **The importer accepts both true-colour TGA framings, not just the one we write**
  (added 2026-08-18, after a user's re-save was refused). `encode` still emits image
  type 2, uncompressed, top-left origin — the byte-exact match for
  `tools/extract_effect_texture.lua`. `decode` additionally accepts type **10**
  (RLE true-colour), because compression is the DEFAULT in several editors' TGA
  export: a sheet the studio itself exported comes back compressed simply by being
  opened and saved. RLE is lossless, so refusing it rejects ordinary work rather
  than protecting anything. Two traits of a real editor save shape the decoder:
  packets do **not** respect scanline boundaries (measured: runs a full 128-texel
  row wide, unaligned to rows), so expansion fills a flat plane and the existing
  bottom-up flip runs after it; and the file may carry a 26-byte TGA 2.0 footer
  (`TRUEVISION-XFILE.`), so expansion stops at `width * height` rather than EOF.
  Bottom-left origin and RLE arrive together, since the editors that default to one
  default to the other.
