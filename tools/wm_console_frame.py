#!/usr/bin/env python3
"""Dump the CONSOLE's own settled world-map framebuffer out of a savestate, 1:1.

    python3 tools/wm_console_frame.py <sstate> <out.png> [--captures <dir>]

WHY THIS EXISTS -- the oracle cannot judge every pixel.
  `wldgen.py render` is the packet oracle: its primitive list is the console's, 60/60
  and 12/12.  But it PAINTS that list with `render_scene.py`'s rasteriser, and that
  rasteriser does not apply the per-packet `rgb` modulation at all -- `blend()` takes
  `pal[idx]` straight.  On the world map the modulated primitives are the map pins,
  whose whole point is that they pulse (sec 21.3, sec 30.6), so a Godot renderer that
  modulates CORRECTLY reads as ~128 wrong pixels against the oracle's picture.  For
  those pixels the reference has to be the console framebuffer itself, which is sitting
  in the savestate next to everything else.

  Use it as the second opinion, not the first: the ORACLE is right about geometry, uv,
  tpage and CLUT (it is packet-exact and the picture is not), and the CONSOLE is right
  about colour.  Where they disagree, the disagreement is itself the finding.

  The console frame is also 3.2% away from the oracle's own render (sec 22) -- the
  ribbon, mostly -- so neither is a clean gate on its own.

DEPENDENCY: the savestate reader lives with the RE, on the `research/battle-end-flow`
branch, at `research/working_documents/world_map_captures/`.  That is a different
worktree from this one; pass `--captures` or set `WM_CAPTURES` if the default guess is
wrong.  Nothing is written there.
"""
import os, sys

W, H = 256, 240
DEFAULT_CAPTURES = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', '..', '..',
    'fft-monorepo', 'research', 'working_documents', 'world_map_captures')


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    sstate, out = argv[1], argv[2]
    caps = argv[argv.index('--captures') + 1] if '--captures' in argv \
        else os.environ.get('WM_CAPTURES', DEFAULT_CAPTURES)
    if not os.path.isdir(caps):
        print('no capture tooling at %s -- pass --captures <dir>' % caps)
        return 2
    sys.path.insert(0, caps)
    import sstate_mine as M                                   # noqa: E402

    st = M.load(sstate)
    ox, oy = M.display_origin(st['control'])
    buf = bytearray(W * H * 3)
    for y in range(H):
        for x in range(W):
            r, g, b = M.rgb555(M.hw(st['vram'], ox + x, oy + y))
            o = (y * W + x) * 3
            buf[o], buf[o + 1], buf[o + 2] = r, g, b
    M.write_png(out, W, H, bytes(buf))
    print('wrote %s (%dx%d) from display buffer (%d,%d)' % (out, W, H, ox, oy))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
