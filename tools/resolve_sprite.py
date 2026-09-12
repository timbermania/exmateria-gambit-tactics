#!/usr/bin/env python3
"""ENTD `sprite_set` (+ `job`, gender) -> flat-store `SPR` sprite-file index.

The authority is `research/key_documents/SPRITE_SET_RESOLUTION.md` ("The rule");
this is a byte-for-byte mirror of `src/data/JobDatabase.gd::get_sprite_id` +
`SPRITE_NAMES`, kept in `tools/` so the static EVTCHR-attribution derivation can
key a unit's identity on its *resolved SPR* (the sprites list) rather than its
`special_name`.

    sprite_set < 0x80                 -> SPR = sprite_set          (NAMED story unit)
    0x80 Generic Male  / 0x81 Female  -> SPR = 0x60 + (job-0x4A)*2 (+1 female)
    0x82 Monster                      -> SPR = 0x86 + floor((job-0x5E)/3)

`sprite_set` and `job` are independent ENTD fields; for the ~200 named slots the
sprite comes straight from `sprite_set` and `job` is ignored. Only the three
markers (`0x80`/`0x81`/`0x82`) re-couple the sprite to `job`. Values >= 0x80 that
are NOT a defined marker are undefined in the ENTD sprite-set namespace -- we pass
them through as a raw index (they never occur in the shipped ENTD).
"""

from __future__ import annotations

GENERIC_MALE = 0x80
GENERIC_FEMALE = 0x81
MONSTER = 0x82

GENERIC_HUMAN_JOB_BASE = 0x4A   # Squire; jobs 0x4A..0x5D are generic humans
GENERIC_HUMAN_SPR_BASE = 0x60   # Male Squire
MONSTER_JOB_BASE = 0x5E         # Chocobo
MONSTER_SPR_BASE = 0x86         # Chocobo; each 3-job family shares one sheet


def generic_human_sprite(job: int, female: bool = False) -> int:
    """`SPR = 0x60 + (job-0x4A)*2 (+1 female)` for generic-human jobs 0x4A..0x5D."""
    return GENERIC_HUMAN_SPR_BASE + (job - GENERIC_HUMAN_JOB_BASE) * 2 + (1 if female else 0)


def monster_sprite(job: int) -> int:
    """`SPR = 0x86 + floor((job-0x5E)/3)` -- each 3-job monster family, one sheet."""
    return MONSTER_SPR_BASE + (job - MONSTER_JOB_BASE) // 3


def resolve_sprite(sprite_set: int, job: int = 0, female: bool = False) -> int:
    """The flat-store SPR a unit renders with (SPRITE_SET_RESOLUTION.md "The rule").

    `sprite_set` < 0x80 is a direct SPR index (job irrelevant); the three markers
    derive the SPR from `job`. `female` only matters for `0x80`/`0x81`
    (generic-human M/F variant); it is inert for named and monster resolution.
    """
    if sprite_set < 0x80:
        return sprite_set                       # NAMED: the byte IS the sprite index
    if sprite_set == GENERIC_MALE:
        return generic_human_sprite(job, female=False)
    if sprite_set == GENERIC_FEMALE:
        return generic_human_sprite(job, female=True)
    if sprite_set == MONSTER:
        return monster_sprite(job)
    return sprite_set                           # undefined high value -> raw passthrough
