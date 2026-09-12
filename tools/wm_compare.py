#!/usr/bin/env python3
"""Compare the Godot world-map render against the oracle, as a HISTOGRAM.

    python3 tools/wm_compare.py <oracle.png> <godot.png> [--delta out.png] [--zoom N]

WHY A HISTOGRAM AND NOT A MEAN
  docs/WORLD_MAP_PORT_LIST.md sec 10: a mean absolute error of ~0.26 was consistent with
  two different stories about the residual -- "every blended pixel is off by one 8-bit
  level" and "a handful of pixels are off by a whole 5-bit level (delta 8)".  Only the
  histogram separated them, and the second reading was the wrong one.  So this prints the
  distribution of the per-pixel max-channel delta, never an average.

WHY THE UNBLENDED CORE IS REPORTED SEPARATELY
  It is the region no aperture pass touches (sec 13.3), so it is the only part of the
  frame where an exact match means "geometry, uv, tpage, CLUT and the 555->888 expansion
  are all correct".  A whole-frame percentage mixes that question with the blend question
  and answers neither.  The core is the load-bearing number; the whole-frame figure is
  dominated by the aperture and moves for reasons that have nothing to do with a bug.

THE ORACLE is `research/working_documents/world_map_captures/wldgen.py render` -- which
emits the console's own primitives, 60/60 and 12/12 packet for packet.  Never
render_scene.py, which replays.  Its PNG is 2x; this subsamples it back to 1:1.
"""
import sys, zlib, struct


def read_png(path):
    """Decode a non-interlaced 8-bit RGB/RGBA/grey PNG to (w, h, [ (r,g,b) ]) rows."""
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path + ': not a PNG'
    pos, idat, w = 8, bytearray(), None
    while pos < len(data):
        ln, typ = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        if typ == b'IHDR':
            w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and interlace == 0, 'only 8-bit non-interlaced'
            nch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
        elif typ == b'IDAT':
            idat += body
        elif typ == b'IEND':
            break
        pos += 12 + ln
    raw = zlib.decompress(bytes(idat))
    stride = w * nch
    out, prev, o = [], bytearray(stride), 0
    for _y in range(h):
        f = raw[o]; o += 1
        line = bytearray(raw[o:o + stride]); o += stride
        if f == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                c = prev[i - nch] if i >= nch else 0
                b = prev[i]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        elif f != 0:
            raise AssertionError('bad filter %d' % f)
        prev = line
        row = []
        for x in range(w):
            px = line[x * nch:x * nch + nch]
            row.append((px[0], px[0], px[0]) if nch <= 2 else (px[0], px[1], px[2]))
        out.append(row)
    return w, h, out


def write_png(path, w, h, rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for p in row:
            raw += bytes(p)
    def chunk(t, b):
        c = struct.pack('>I', len(b)) + t + b
        return c + struct.pack('>I', zlib.crc32(t + b) & 0xFFFFFFFF)
    open(path, 'wb').write(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(bytes(raw), 6)) + chunk(b'IEND', b''))


W, H = 256, 240
## Screen-centred -> framebuffer is + (128, 120), sec 4.
OX, OY = 128, 120
## sec 13.3 -- the band no aperture quad covers.  43 x 80 = 3440 pixels.
CORE = (OX + 37, OY - 40, OX + 80, OY + 40)


def subsample(w, h, rows):
    if (w, h) == (W, H):
        return rows
    assert w % W == 0 and h % H == 0, 'oracle is %dx%d, not a multiple of %dx%d' % (w, h, W, H)
    zx, zy = w // W, h // H
    return [[rows[y * zy][x * zx] for x in range(W)] for y in range(H)]


def report(name, want, got, box=None):
    x0, y0, x1, y1 = box or (0, 0, W, H)
    hist, worst = {}, (0, None)
    for y in range(y0, y1):
        for x in range(x0, x1):
            a, b = want[y][x], got[y][x]
            d = max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))
            hist[d] = hist.get(d, 0) + 1
            if d > worst[0]:
                worst = (d, (x, y, a, b))
    tot = (x1 - x0) * (y1 - y0)
    ex = hist.get(0, 0)
    one = hist.get(1, 0)
    more = tot - ex - one
    print('  %-22s %6d/%-6d = %6.2f%% exact   %6d off by 1 (%5.2f%%)   %5d off by more (%5.3f%%)'
          % (name, ex, tot, 100.0 * ex / tot, one, 100.0 * one / tot, more, 100.0 * more / tot))
    if more:
        tail = sorted(k for k in hist if k > 1)
        print('  %-22s delta tail: %s' % ('',
              '  '.join('%d:%d' % (k, hist[k]) for k in tail[:12])))
        d, w_ = worst
        print('  %-22s worst d=%d at fb(%d,%d) want=%s got=%s' % ('', d, w_[0], w_[1], w_[2], w_[3]))
    return ex, tot


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    ow, oh, orows = read_png(argv[1])
    gw, gh, grows = read_png(argv[2])
    want = subsample(ow, oh, orows)
    got = subsample(gw, gh, grows)
    print('oracle %s (%dx%d)  vs  godot %s (%dx%d)' % (argv[1], ow, oh, argv[2], gw, gh))
    report('UNBLENDED CORE', want, got, CORE)
    report('whole frame', want, got)
    if '--delta' in argv:
        out = argv[argv.index('--delta') + 1]
        rows = []
        for y in range(H):
            row = []
            for x in range(W):
                a, b = want[y][x], got[y][x]
                d = max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))
                # black = exact, blue = off by 1 (the arithmetic band), red = worse
                row.append((0, 0, 0) if d == 0 else
                           (0, 0, 96) if d == 1 else
                           (min(255, 64 + 24 * d), 0, 0))
            rows.append(row)
        write_png(out, W, H, rows)
        print('  delta map -> %s   (black exact, dim blue off-by-1, red off by more)' % out)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
