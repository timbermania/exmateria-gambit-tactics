"""Single home for FFT-specific magic numbers.

The patcher core (`patcher.py`, `iso9660.py`, `iso_sectors.py`) is generic
ISO9660 / Mode-2-Form-1 plumbing. FFT-specific layout — where the music
LBA table lives in SCUS_942.21, how many slots there are, the engine's
SMD load-size cap — belongs here so future asset handlers can import the
same values instead of re-deriving them.
"""

from __future__ import annotations

# Byte offset of the music slot table inside SCUS_942.21. Each entry is
# 8 bytes: <u32 lba, u32 size_bytes_padded_to_2048>. There are 100 slots.
MUSIC_TABLE_OFFSET = 0x37880

# Number of music slots in the FFT engine.
N_MUSIC_SLOTS = 100

# Hard cap on SMD load size enforced by the FFT engine. Binary-searched
# 2026-05-03 via the patcher: a 10-sector / 20480-byte custom SMD plays
# (matches MUSIC_99's vanilla padded allocation), a 13-sector / 26624-byte
# custom SMD silences the data screen. Mirrors the C++ side
# (FFTSmdGameCompileBudget::engine_max_bytes). Hand-built or third-party
# SMDs above this fail to play, so reject them at the patcher boundary
# rather than emit silent ISOs.
ENGINE_MAX_SMD_BYTES = 20480

# Path inside the FFT ISO to the SCUS that holds the music table.
SCUS_PATH = "/SCUS_942.21;1"

# --- Map (GNS) table -------------------------------------------------

# Path to BATTLE.BIN, which owns the GNS LBA table the game reads
# (FUN_800F3638 indexes it with the map id and raw-reads the GNS — no
# ISO9660 filename lookup).
BATTLE_BIN_PATH = "/BATTLE.BIN;1"

# The ISO9660 directory that holds every MAP resource file (record name
# `MAP` — directories on this disc carry no `;1` version suffix; the files
# inside do). The GNS record's LBA identifies the resource's directory
# record here.
MAP_DIR_PATH = "/MAP"

# Byte offset of the GNS LBA table inside BATTLE.BIN's user data: 126
# little-endian u32 absolute disc LBAs, one per map id 0–125. The game's
# zero-entry bail-out is why maps 120–124 hold 0. See
# research/working_documents/MAP_RESOURCE_TO_DISC_DELIVERY.md (#361, [V]).
BATTLE_BIN_GNS_TABLE_OFFSET = 0x8EC74

# One table entry per map id 0..125.
N_MAP_IDS = 126

# The game's GNS read window is the hard-coded immediate 4096 at 0x800F369C —
# two sectors, fixed, never derived from the file's size. A GNS can never
# exceed this.
GNS_MAX_BYTES = 4096

# One GNS record is 20 bytes: tag, 0x00, arrangement, time/weather, type hi
# (0x01), type lo, marker 0x3333, u32 LE LBA, u32 LE length (2048-multiple),
# sentinel 55 66 77 88 (file order).
GNS_RECORD_BYTES = 20
GNS_RECORD_SENTINEL = bytes.fromhex("55667788")
GNS_RECORD_MARKER = b"\x33\x33"  # u16 0x3333 at record offset 6
GNS_VALID_TAGS = frozenset((0x22, 0x30, 0x70))
GNS_TYPE_PADDED = 49  # PADDED terminator: echoes the last real record verbatim

# A GNS file is a contiguous prefix of 20-byte records followed by an
# opaque tail (every GNS on this disc is ≡ 8 mod 20 bytes and the tail
# holds non-zero data). The record count is invariant for a patched GNS
# and the tail is carried verbatim.
