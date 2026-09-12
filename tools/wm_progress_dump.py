#!/usr/bin/env python3
"""Dump a savestate's WORLD.BIN game-variable store as a GDScript literal.

    python3 tools/wm_progress_dump.py <sstate> [--captures <dir>]

WHAT THE STORE IS (WORLD_MAP_SCREEN.md sec 27, `travel.py`'s header)
  684 bytes at *(0x80153280), three regions that tile it exactly:

      idx <  128 : a whole u32 at  base + 4*idx                       words   0..127
      idx <  864 : one BIT     at  base + 512 + 4*((idx-128)>>5)      words 128..150
                   bit idx & 31
      idx < 1024 : one NIBBLE  at  base + 604 + 4*((idx-864)>>3)      words 151..170
                   shift 4*(idx & 7)

  Node i is known when bit 512+i is set; route r is drawn when bit 556+r is set; the
  story counter is var 110; gil is var 0x2C, the date is 0x2E / 0x2F.

WHY A LITERAL AND NOT AN ASSET FILE
  Same reason `parse_world_map.py` bakes `BG_GRID`: the value is savestate-sourced, has
  no disc source, and is byte-identical across every capture the repo holds for the
  parts that are not progression.  Baking it with the recipe next to it keeps the branch
  self-contained; regenerate rather than hand-edit.

  Only 32 of the 171 words are non-zero, so the literal is a sparse (index, value) list.
  It carries the UNKNOWN words too -- variables this RE has not named are still
  Campaign's progression, and dropping them would make the store lossy the first time
  something else reads one.
"""
import os, sys, struct

DEFAULT_CAPTURES = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', '..', '..',
    'fft-monorepo', 'research', 'working_documents', 'world_map_captures')
WORDS = 171
NODE_FLAG_BASE, ROUTE_FLAG_BASE = 512, 556
STORY, GIL, MONTH, DAY = 110, 0x2C, 0x2E, 0x2F


def var_slot(idx):
    if idx < 128:
        return 4 * idx, -1
    if idx < 864:
        return 512 + 4 * ((idx - 128) >> 5), idx & 31
    return 604 + 4 * ((idx - 864) >> 3), 4 * (idx & 7)


def read(blob, idx):
    off, sh = var_slot(idx)
    w = struct.unpack_from('<I', blob, off)[0]
    return w if sh < 0 else (w >> sh) & (1 if idx < 864 else 0xF)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    caps = argv[argv.index('--captures') + 1] if '--captures' in argv \
        else os.environ.get('WM_CAPTURES', DEFAULT_CAPTURES)
    if not os.path.isdir(caps):
        print('no capture tooling at %s -- pass --captures <dir>' % caps)
        return 2
    sys.path.insert(0, caps)
    import sstate_mine as sm                                  # noqa: E402
    import travel as T                                        # noqa: E402

    ram = sm.load(argv[1])['ram']
    base = sm.u32(ram, T.VAR_BASE_PTR) & 0x7FFFFF
    blob = ram[base:base + WORDS * 4]

    pairs = [(i, struct.unpack_from('<I', blob, 4 * i)[0]) for i in range(WORDS)]
    pairs = [(i, v) for i, v in pairs if v]
    known = [i for i in range(43) if read(blob, NODE_FLAG_BASE + i)]
    drawn = [r for r in range(48) if read(blob, ROUTE_FLAG_BASE + r)]

    print('# %s' % os.path.basename(argv[1]))
    print('#   nodes known  %s' % known)
    print('#   routes drawn %s' % drawn)
    print('#   story %d  gil %d  date %d/%d'
          % (read(blob, STORY), read(blob, GIL), read(blob, MONTH), read(blob, DAY)))
    print('const CAPTURE := [')
    for n in range(0, len(pairs), 4):
        print('\t' + ' '.join('[%d, 0x%08X],' % (i, v) for i, v in pairs[n:n + 4]))
    print(']')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
