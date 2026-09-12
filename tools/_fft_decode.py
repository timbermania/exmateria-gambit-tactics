"""Shared FFT bit-packed-data decoders for the extractors.

The one place the wiki labels for FFT element/status names and the
bit-order convention live. Every extractor that emits a committed JSON
artifact imports from here; runtime GDScript code never decodes bits
(see ADR-0013).

**FFT uses MSB-first bit packing within every byte.** Authority:
`FFTPatcher.PatcherLib.Utilities.Utilities.ByteFromBooleans(msb, six,
five, four, three, two, one, lsb)` — the first parameter goes to bit 7
(MSB), the last to bit 0 (LSB). So a name list `[Fire, Lightning, Ice,
Wind, Earth, Water, Holy, Dark]` is written "MSB-first" (Fire at
position 0 *is* bit 7), which matches FFTPatcher's `ElementFlags` enum
(`Fire = 0x80`, `Dark = 0x01`).

For multi-byte fields (`status_immunity`, `equipment_flags`) the bytes
themselves are little-endian within the binary record, but each byte's
flag layout is MSB-first per the rule above.

Three decoded shapes:

- **decode_set_msb(byte, names_msb_first)** — set membership packed
  MSB-first into one byte (names[0] = bit 7). Element affinity, etc.
- **decode_set_msb_bytes(byte_array, names_by_byte)** — set membership
  packed MSB-first across an array of bytes (`status_immunity` etc.,
  40 statuses × 5 bytes; skips `---` placeholders).
- **decode_flags_msb(byte, names_msb_first)** — independent boolean
  properties packed MSB-first into one byte. Used for `slot_flags`,
  `weapon_flags`.
- **decode_flags_msb_multi_byte(int_val, names_msb_first, num_bytes)** —
  same shape for a multi-byte little-endian int (`equipment_flags`,
  32 bits across 4 bytes; bit ordering is MSB-first per byte, and the
  bytes themselves are LE-stacked).

The MSB-first convention is FFT's, not a stylistic choice. CLAUDE.md's
"Wrong bit order when parsing binary flags" pitfall now lives here and
nowhere else; runtime code never sees a bit position.
"""

from __future__ import annotations


# ---- Element names (LSB-first, 8 bits = 1 byte) -----------------------------
# Bit 0 = Fire, bit 1 = Lightning, …, bit 7 = Dark.
# Source: FFTPatcher convention; same list already used inline by
# extract_items.py for `absorb_elements` / `cancel_elements` / etc.
ELEMENTS: list[str] = [
    "Fire", "Lightning", "Ice", "Wind", "Earth", "Water", "Holy", "Dark",
]


# ---- Status names (MSB-first, 5 bytes = 40 statuses) ------------------------
# FFT packs the 40-status table MSB-first: byte 0 bit 7 is the FIRST status
# ("Performing"), byte 0 bit 0 is the EIGHTH ("---" placeholder). So for a
# given byte, the name lookup is `names[7 - bit]`. The 5 bytes appear in
# `status_immunity`, `permanent_status`, `starting_status` per the job and
# item attribute records.
#
# `---` entries are placeholder slots in the ROM that have no semantic
# meaning; decoders skip them rather than emit them.
# Source of truth: FFTPatcher `Datatypes/Status/Statuses.cs:187` —
# each byte is `ByteFromBooleans(first, …, last)` so the FIRST name is
# bit 7 (MSB) and the LAST is bit 0 (LSB). Status offset N is at byte
# (N/8) bit (7-(N%8)), matching FFTPatcher's `PSXResources/StatusNames.xml`
# (offset 7 = Performing = byte 0 bit 0).
#
# Names are FFTPatcher's C# field identifiers verbatim — they are the
# authoritative slot names. Display strings (e.g. "Death Sentence" with
# a space, "Cursed" for `DarkEvilLooking`) are a downstream presentation
# concern and live alongside the data, not here.
STATUS_NAMES_BY_BYTE: list[list[str]] = [
    # byte 0 (statuses 0..7)
    ["NoEffect", "Crystal", "Dead", "Undead",
     "Charging", "Jump", "Defending", "Performing"],
    # byte 1 (statuses 8..15)
    ["Petrify", "Invite", "Darkness", "Confusion",
     "Silence", "BloodSuck", "DarkEvilLooking", "Treasure"],
    # byte 2 (statuses 16..23)
    ["Oil", "Float", "Reraise", "Transparent",
     "Berserk", "Chicken", "Frog", "Critical"],
    # byte 3 (statuses 24..31)
    ["Poison", "Regen", "Protect", "Shell",
     "Haste", "Slow", "Stop", "Wall"],
    # byte 4 (statuses 32..39)
    ["Faith", "Innocent", "Charm", "Sleep",
     "DontMove", "DontAct", "Reflect", "DeathSentence"],
]


# ---- Equipment-flag names (LSB-first, 32 bits = 4 bytes) -------------------
# A job's `equipment_flags` is a 32-bit word: bit 0 = "Unused", bit 1 = "Knife",
# …, bit 31 = "Perfume". Source: FFTPatcher's `Datatypes/Job/Equipment.cs`
# `psxNames` (PSX context) — the in-order byte unpack matches the LSB-first
# `ByteFromBooleans` convention this codebase uses elsewhere. The "Unused"
# slot is the FFTPatcher-named bit 0; we keep its name so the dict is a
# 1:1 round-trip with the underlying ROM word.
EQUIPMENT_FLAG_NAMES: list[str] = [
    "Unused",  "Knife",   "NinjaBlade", "Sword",         # byte 0
    "KnightsSword", "Katana", "Axe",     "Rod",
    "Staff",   "Flail",   "Gun",     "Crossbow",         # byte 1
    "Bow",     "Instrument", "Book", "Polearm",
    "Pole",    "Bag",     "Cloth",   "Shield",           # byte 2
    "Helmet",  "Hat",     "HairAdornment", "Armor",
    "Clothing","Robe",    "Shoes",   "Armguard",         # byte 3
    "Ring",    "Armlet",  "Cloak",   "Perfume",
]


# ---- Bit-loop primitives ----------------------------------------------------

def decode_set_msb(byte_val: int, names: list[str]) -> list[str]:
    """Set-form decode for one FFT-style byte (MSB-first).

    `names[0]` is the bit-7 name (MSB), `names[7]` is the bit-0 name (LSB).
    Returns the names whose bits are set, in name-list (MSB-first) order.
    Used for element affinity (`Fire = 0x80` … `Dark = 0x01`).
    """
    return [name for i, name in enumerate(names) if byte_val & (1 << (7 - i))]


def decode_set_msb_bytes(
    byte_array: list[int] | bytes,
    names_by_byte: list[list[str]],
) -> list[str]:
    """Set-form decode for an MSB-first multi-byte field.

    For each byte, bit 7 maps to names[0] and bit 0 maps to names[7].
    Returns names in (byte, position) order — every set bit emits a name
    (FFTPatcher names every slot; e.g. byte 0 bit 7 is `NoEffect`,
    a real ROM slot, not a placeholder to elide).

    Used for `status_immunity` / `permanent_status` / `starting_status`
    (40 statuses across 5 bytes per `STATUS_NAMES_BY_BYTE`).
    """
    out: list[str] = []
    for byte_idx in range(min(len(byte_array), len(names_by_byte))):
        byte_val = int(byte_array[byte_idx])
        names = names_by_byte[byte_idx]
        for bit in range(8):
            if byte_val & (1 << bit):
                idx = 7 - bit  # FFT MSB-first
                if idx < len(names):
                    out.append(names[idx])
    return out


def decode_flags_msb(byte_val: int, names: list[str]) -> dict[str, bool]:
    """Named-bool decode for one FFT-style byte (MSB-first).

    `names[0]` is the bit-7 name (MSB), `names[7]` is the bit-0 name (LSB).
    Returns a dict keyed by every name (False for absent bits).
    Used for `slot_flags`, `weapon_flags`.
    """
    return {name: bool(byte_val & (1 << (7 - i))) for i, name in enumerate(names)}


def decode_flags_msb_multi_byte(
    int_val: int,
    names: list[str],
    num_bytes: int,
) -> dict[str, bool]:
    """Named-bool decode for a multi-byte little-endian int (MSB-first per byte).

    The int is split into `num_bytes` LE bytes; each byte's flag layout is
    MSB-first per `decode_flags_msb`. `names` carries `8 * num_bytes`
    entries (`names[0..7]` belong to byte 0, `names[8..15]` to byte 1, …),
    each block in MSB-first order. Used for `equipment_flags` (32 bits =
    4 bytes; FFTPatcher `Job/Equipment.cs` `psxNames`).
    """
    assert len(names) == 8 * num_bytes, "names length must equal 8 * num_bytes"
    out: dict[str, bool] = {}
    for byte_idx in range(num_bytes):
        byte_val = (int_val >> (byte_idx * 8)) & 0xFF
        for i in range(8):
            name = names[byte_idx * 8 + i]
            out[name] = bool(byte_val & (1 << (7 - i)))
    return out


# ---- Inflict-status set table (SCUS_942.21 InflictStatusList) --------------
# Each ability's `inflict_status` byte (secondary-data offset 0x0B) is an index
# (0..127) into this table. Each 6-byte entry is one mode flag byte + 5 status
# bytes (Status1..Status5 = STATUS_NAMES_BY_BYTE[0..4]).
#
# Authority: hacktics_disassembly.txt label `InflictStatusList:` at RAM
# 0x80063FC4 (SCUS file offset 0x547C4). Table ends at 0x80064²C4
# (`ItemAttributes` label) = 0x300 bytes = 128 entries.
#
# Mode byte is MSB-first per ADR-0013:
#   bit 7 (0x80) = "all"       — apply every listed status
#   bit 6 (0x40) = "random"    — pick ONE listed status
#   bit 5 (0x20) = "separate"  — roll each listed status independently
#   bit 4 (0x10) = "cancel"    — REMOVE listed statuses from target
# Lower 4 bits unused (always 0 in vanilla).
#
# Status names match STATUS_NAMES_BY_BYTE (FFTPatcher C# identifiers verbatim);
# the runtime translation to Godot StatusRegistry names lives in the consumer.

INFLICT_STATUS_TABLE_RAM = 0x80063FC4
INFLICT_STATUS_TABLE_SCUS_OFFSET = 0x547C4   # RAM - 0x80010000 + 0x800 header
INFLICT_STATUS_TABLE_STRIDE = 6
INFLICT_STATUS_TABLE_ENTRIES = 128

INFLICT_MODE_NAMES_MSB: list[str] = [
    "all", "random", "separate", "cancel",
    "_unused_b3", "_unused_b2", "_unused_b1", "_unused_b0",
]


def decode_inflict_mode(mode_byte: int) -> str | None:
    """Return the one mode set in `mode_byte`, or None if the byte is zero.

    Vanilla FFT entries set exactly one of {all, random, separate, cancel}.
    If multiple bits are set we return the highest-priority name (all > random
    > separate > cancel) and let the caller decide what to do; a parser using
    this directly should verify popcount==1 and warn otherwise.
    """
    if mode_byte == 0:
        return None
    for i, name in enumerate(INFLICT_MODE_NAMES_MSB[:4]):
        if mode_byte & (1 << (7 - i)):
            return name
    return None


def extract_inflict_status_sets(
    scus_bytes: bytes,
) -> dict[int, dict]:
    """Decode the 128-entry InflictStatusList from a SCUS_942.21 byte string.

    Returns `{set_id: {mode, statuses, raw_mode_byte, raw_status_bytes}}`
    keyed by set_id 0..127. The `statuses` field is a name-array using the
    FFTPatcher C# identifiers from `STATUS_NAMES_BY_BYTE`. The `mode` field
    is one of `{"all", "random", "separate", "cancel", None}` (None for the
    all-zero entries that are reserved/unused).

    Raw bytes are preserved for the debug artifact (`raw_mode_byte` hex string,
    `raw_status_bytes` space-separated hex). Consumers that emit committed
    artifacts (per ADR-0013) should drop the raw_* fields and keep only
    semantic mode + statuses.
    """
    out: dict[int, dict] = {}
    base = INFLICT_STATUS_TABLE_SCUS_OFFSET
    stride = INFLICT_STATUS_TABLE_STRIDE
    for set_id in range(INFLICT_STATUS_TABLE_ENTRIES):
        off = base + set_id * stride
        entry = scus_bytes[off:off + stride]
        if len(entry) != stride:
            raise ValueError(
                f"SCUS too short to extract inflict set {set_id} at 0x{off:X}"
            )
        mode_byte = entry[0]
        status_bytes = list(entry[1:6])
        statuses = decode_set_msb_bytes(status_bytes, STATUS_NAMES_BY_BYTE)
        out[set_id] = {
            "mode": decode_inflict_mode(mode_byte),
            "statuses": statuses,
            "raw_mode_byte": f"0x{mode_byte:02X}",
            "raw_status_bytes": " ".join(f"{b:02X}" for b in status_bytes),
        }
    return out


# ---- Status-attribute table (SCUS_942.21, 40 entries x 0x10) ---------------
# One record per FFT status, in STATUS_NAMES_BY_BYTE order. The field this repo
# needs is byte +0x00: the status's DEFAULT DURATION in CT units, 0 meaning "no
# timer" — the status lasts until something cancels it.
#
# Authority, three sites, all in hacktics_disassembly.txt:
#
#   1. `Initialize_Status_Check_Data` (SCUS 0x80059854) loops `i = 0 .. 0x27`
#      adding 0x10 per iteration and reads flag bytes at 0x80065DE8 + 0x10*i and
#      +1 — which fixes the ENTRY COUNT (40) and the STRIDE (0x10).
#   2. `Status_CT_Set` (SCUS 0x8005DB70) computes `sll v1, status, 4` and then
#      `lbu param_1, 0x5DE7(at)` with at = 0x8006 — so the duration column is at
#      0x80065DE7 + 0x10*status, one byte BELOW the flag bytes above. That is
#      what fixes the record base: aligning records to ...DE8 instead shifts this
#      column one status off its owner and reads Sleep=24, DontMove=60,
#      DeathSentence=0xF2.
#   3. The same function stores it with `sb param_1, 0x5D(v1)` where
#      `v1 = unit + (status - 0x18)`, guarded by `sltiu (status - 0x18), 0x10` —
#      the per-unit countdown array is unit+0x5D..0x6C, SIXTEEN bytes, one per
#      status 24..39. A status outside that window has nowhere to count down,
#      which is why every CT outside it reads 0.
#
# Cross-check on the decoded values: Sleep 60, Stop 20, Haste 32, Poison 36,
# DontAct 24 and DeathSentence 3 are the durations FFT is documented to have.
# BATTLE.BIN 0x8018D910 is the decrementer (`unit[0x5D + i] -= 1` for i = 0..0xE,
# queueing the removal when it reaches 0); Death Sentence sits outside that loop
# because it counts the unit's TURNS, not clock ticks.
#
# ⚠️ Byte +0x0F reads as a distinct value in 0..39 for 39 of the 40 records and
# 0xF7 for the last (DeathSentence), so it is an order/priority column this
# decode does not fully explain. It is not the CT column and nothing here reads
# it.

STATUS_ATTR_TABLE_RAM = 0x80065DE7
STATUS_ATTR_TABLE_SCUS_OFFSET = 0x565E7   # RAM - 0x80010000 + 0x800 header
STATUS_ATTR_TABLE_STRIDE = 0x10
STATUS_ATTR_TABLE_ENTRIES = 40

# The window of status indices the ROM gives a countdown byte to (unit+0x5D+i).
STATUS_TIMER_FIRST_INDEX = 24
STATUS_TIMER_SLOTS = 16


def extract_status_attributes(scus_bytes: bytes) -> dict[int, dict]:
    """Decode the 40-entry status-attribute table from a SCUS_942.21 byte string.

    Returns `{status_index: {name, default_ct, timer_slot, raw}}` keyed by the
    status index the ROM itself uses (STATUS_NAMES_BY_BYTE order). `default_ct`
    is the duration in CT units (0 = no timer). `timer_slot` is the index into
    the ROM's per-unit countdown array (unit+0x5D + slot), or None for a status
    outside the 24..39 window — those cannot be timed at all.
    """
    names = [n for byte_names in STATUS_NAMES_BY_BYTE for n in byte_names]
    out: dict[int, dict] = {}
    base = STATUS_ATTR_TABLE_SCUS_OFFSET
    stride = STATUS_ATTR_TABLE_STRIDE
    for idx in range(STATUS_ATTR_TABLE_ENTRIES):
        off = base + idx * stride
        entry = scus_bytes[off:off + stride]
        if len(entry) != stride:
            raise ValueError(
                f"SCUS too short to extract status attributes {idx} at 0x{off:X}"
            )
        slot = idx - STATUS_TIMER_FIRST_INDEX
        out[idx] = {
            "name": names[idx],
            "default_ct": entry[0],
            "timer_slot": slot if 0 <= slot < STATUS_TIMER_SLOTS else None,
            "raw": " ".join(f"{b:02X}" for b in entry),
        }
    return out
