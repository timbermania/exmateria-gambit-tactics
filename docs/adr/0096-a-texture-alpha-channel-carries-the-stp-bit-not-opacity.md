# A texture's alpha channel carries the STP bit, not opacity

## Status

accepted

## Context

Effect textures are PSX indexed images with a BGR555 CLUT. Each 16-bit palette
word is `STP:1 | B:5 | G:5 | R:5` — bit 15 is the **STP** (Semi-Transparency
Processing) flag, which tells the GPU to run that texel through the primitive's
blend mode rather than drawing it flat. STP is a property of a **palette entry**,
not of a pixel.

RGBA image formats have no STP bit, so every tool that moves an effect texture
in or out of an artist-facing format has had to pick a carrier for it. Two tools
already did, independently and identically:

- `effect-editor/utils/bmp.lua` — `palette_rgb_to_bgr555_from_alpha` sets
  `0x8000` when `alpha < 255`, and its exporters emit `alpha = 128` for STP=1
  and `alpha = 255` for STP=0.
- `godot-learning/tools/extract_effect_texture.lua` — `bgr555_to_rgba` returns
  `a = stp and 128 or 255`.

The convention was never written down, and #280 (texture replacement) makes it
load-bearing: an artist repaints an exported RGBA TGA and the studio has to
decide what the alpha they painted means.

A corpus measurement over the 401 non-empty effects sharpened the question. The
all-zero palette word `0x0000` — the PSX's fully **transparent** black — is
palette entry 0 in **359 of 401** effects. Both tools decode it to
`RGB(0,0,0)` with `alpha = 255`, i.e. **opaque black**, while the *opaque* black
`0x8000` decodes to `alpha = 128`. Read naively as opacity, the mapping is
inverted and wrong. Read as "alpha is where the STP bit rides," it is exactly
right and losslessly invertible.

## Decision

1. **Alpha is the STP bit's carrier, not an opacity channel.** The mapping of
   record, in both directions, is:

   | BGR555 | exported alpha | imported alpha | meaning |
   |---|---|---|---|
   | STP = 0 | `255` | `= 255` | flat texel, no blending |
   | STP = 1 | `128` | `< 255` | texel runs through the blend mode |

   Export emits exactly `128`/`255`. Import accepts the whole `< 255` range as
   STP=1 so an artist's antialiasing or a tool's alpha resample cannot silently
   flip a texel to flat.

2. **Transparency is a palette *colour*, not an alpha value.** A fully
   transparent texel is the palette word `0x0000`, which is carried as opaque
   black `RGBA(0,0,0,255)` — the same as any other black entry. There is no
   alpha value that means "erased," and `alpha = 0` means STP=1, not
   transparent. Tools must not present the alpha channel to an artist as
   an eraser.

3. **The RGB→BGR555 conversion is the exact 5-bit truncation** `channel / 8`,
   inverse to the `field * 8` used on export. Both directions are lossless for
   any colour that came out of a real palette; a colour that did not is the
   importer's quantization problem (ADR-0097), not this convention's.

## Consequences

- Corpus-verified lossless: re-encoding every decoded palette word reproduces
  the original 16-bit value for **401/401** effects (0 lossy words).
- An artist who erases to full transparency in Photoshop does **not** get a
  transparent texel; under a fixed CLUT (ADR-0097) they get the nearest STP=1
  entry. Erasing to the sheet's transparent background is done by painting the
  background's own colour — pure black on the 359 effects whose entry 0 is
  `0x0000`. Any artist-facing surface must say so.
- The convention is now the shared contract between the Lua editor and the Godot
  studio; a change to either tool's alpha handling is a change to this ADR.
- **Two RGB expansions coexist in the repo and must not be mixed.** The RGBA
  round-trip path truncates (`field * 8`, range 0-248); `parse_effect.
  extract_palette`, which writes each effect's `texture_palette.json`, expands by
  bit replication (`(v << 3) | (v >> 2)`, full range 0-255). The same palette
  word therefore renders as 192 in a TGA and 198 in the JSON. Only the
  truncating form is invertible, so it is the one this ADR fixes for the
  round trip; anything comparing a TGA texel against `texture_palette.json` must
  compare in **5-bit space** (`>> 3`) rather than 8-bit, or every texel reads as
  off-palette.
- `research/key_documents/TEXTURE_AND_PALETTE_FORMAT.md`'s "`0x0000` = Black
  (fully transparent by default)" is correct about the format but does not say
  how the tools carry it; it is corrected to cite this ADR.
