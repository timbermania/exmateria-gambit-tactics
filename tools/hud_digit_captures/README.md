# HUD digit captures (dynamic analysis — the composition oracle)

Full 1 MB PSX VRAM dumps (gzipped) from the fork PCSX-Redux at battle savestates.
FFT composes the cur/max digit glyphs at RUNTIME into a scratch VRAM page (tpage
0x07) and palette-maps them through CLUT 0x7cbc.

**These are now the test ORACLE, not a build input.** The shipping font is
extracted statically from `EVENT/FRAME.BIN` by `tools/parse_frame_font.py`
(ISO-reproducible) into `FRAMEFONT.tga`; the old byte-capture path
(`build_hud_digits.py` + `HUDDIGITS.tga`) has been retired. These captures back
`tools/test_parse_frame_font.py`:

- the FRAME `0` palette-signature faithfulness check (`{1,2,3,4}` + idx-4 outline,
  distinct from the RANGETILE damage font's `{1,2,3,5}`), and
- the composition-metric check: a uniform fixed advance for repeated digits and
  the cur→max baseline stagger (`MAX_BASELINE_DY`).

NOTE: the scratch page composes at a TIGHTER intermediate pitch than the display.
The on-screen advances (`ADVANCE_BIG`/`ADVANCE_SMALL`) are read off the live PSX
framebuffer (`project-assets/fft-rom/hud-capture/sstate1_left_panel.png`) and
dialed headful — see `docs/hud-number-font.md`.

Each state isolates clean (last-digit / space-flanked) instances:

  sstate1 -> 0 1 2 5 6 7 9 /    sstate3 -> 4
  sstate5 -> 3  (HP "403", last cur digit)
  sstate6 -> 8  (HP "528", last cur digit)
