"""PSX CD-ROM Mode 2 Form 1 sector R/W with EDC + ECC regeneration.

Algorithm reference: pcsx-redux third_party/iec-60908b/edcecc.c (MIT, Pixel).
Spec: ECMA-130 / IEC-60908b. Yellow Book CRC for EDC, GF(2^8) Reed-Solomon
for P and Q ECC channels.

We chose the canonical algorithm over FFTPatcher's IsoPatch.cs port because
the FFTPatcher version produces ECC bytes that don't match the canonical
formula (it works in practice only because PSX hardware/emulators ignore
ECC mismatches on healthy reads).
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

# ---------------------------------------------------------------------------
# Mode 2 Form 1 sector layout
# ---------------------------------------------------------------------------

SECTOR_SIZE = 2352          # full raw sector
USER_DATA_SIZE = 2048       # payload per Mode 2 Form 1 sector
HEADER_OFFSET = 0x0C        # 4-byte address (MSF + mode)
SUBHEADER_OFFSET = 0x10     # 8-byte subheader
USER_DATA_OFFSET = 0x18     # 2048 bytes
EDC_OFFSET = 0x818          # 4 bytes
P_PARITY_OFFSET = 0x81C     # 172 bytes
Q_PARITY_OFFSET = 0x8C8     # 104 bytes — total ECC = 276 bytes

SYNC_PATTERN = bytes([0x00] + [0xFF] * 10 + [0x00])  # 12 bytes


# ---------------------------------------------------------------------------
# Lookup tables (computed at import)
# ---------------------------------------------------------------------------

def _build_yellow_book_crctable() -> list[int]:
    poly = 0xD8018001
    table = [0] * 256
    for i in range(256):
        edc = i
        for _ in range(8):
            edc = (edc >> 1) ^ (poly if (edc & 1) else 0)
        table[i] = edc & 0xFFFFFFFF
    return table


def _build_gf_tables() -> tuple[list[int], list[int], list[int], list[int]]:
    """Build GF(2^8) tables for primitive polynomial x^8+x^4+x^3+x^2+1 (=0x11D)."""
    exp_table = [0] * 512
    log_table = [0] * 256
    x = 1
    for i in range(255):
        exp_table[i] = x
        log_table[x] = i
        x <<= 1
        if x & 0x100:
            x ^= 0x11D
    # Duplicate so exp[a + b] is valid for a + b in [0, 510] without modulo.
    for i in range(255, 512):
        exp_table[i] = exp_table[i - 255]
    log_table[0] = 0   # log(0) is undefined but used as a sentinel by callers.

    def gf_mul(a: int, b: int) -> int:
        if a == 0 or b == 0:
            return 0
        return exp_table[(log_table[a] + log_table[b]) % 255]

    def gf_inv(a: int) -> int:
        # x * x^254 = x^255 = 1 in GF(2^8), so inv(x) = x^254
        return exp_table[(255 - log_table[a]) % 255]

    mul2_table = [gf_mul(i, 2) for i in range(256)]
    inv3 = gf_inv(3)
    div3_table = [gf_mul(i, inv3) for i in range(256)]
    return exp_table, log_table, mul2_table, div3_table


YELLOW_BOOK_CRC = _build_yellow_book_crctable()
GF_EXP, GF_LOG, GF_MUL2, GF_DIV3 = _build_gf_tables()


# ---------------------------------------------------------------------------
# EDC (CRC over subheader + user data)
# ---------------------------------------------------------------------------

def compute_edc(data: bytes) -> int:
    edc = 0
    for byte in data:
        edc = YELLOW_BOOK_CRC[(edc ^ byte) & 0xFF] ^ (edc >> 8)
    return edc & 0xFFFFFFFF


# ---------------------------------------------------------------------------
# ECC P (86 lines x 24 columns, stride 86)
# ---------------------------------------------------------------------------

def _compute_ecc_p(ecc_data: bytearray) -> None:
    """Compute P parity in-place over ecc_data[0..2063], write to [2064..2235]."""
    for i in range(86):
        ecc = 0
        for j in range(24):
            coeff = ecc_data[86 * j + i]
            ecc = GF_MUL2[(ecc & 0xFF) ^ coeff] | (
                ((ecc & 0xFF00) ^ ((coeff & 0xFF) << 8)) & 0xFFFF
            )
        ecc_high = (ecc >> 8) & 0xFF
        ecc_low = GF_DIV3[GF_MUL2[ecc & 0xFF] ^ ecc_high]
        ecc_high ^= ecc_low
        ecc_data[24 * 86 + i] = ecc_low & 0xFF
        ecc_data[25 * 86 + i] = ecc_high & 0xFF


# ---------------------------------------------------------------------------
# ECC Q (52 lines x 43 columns, modular straddle)
# ---------------------------------------------------------------------------

def _compute_ecc_q(ecc_data: bytearray) -> None:
    """Compute Q parity over ecc_data[0..2235] (incl. P), write to [2236..2339]."""
    for i in range(52):
        ecc = 0
        for j in range(43):
            l = ((44 * j + 43 * (i // 2)) % 1118) * 2 + (i & 1)
            coeff = ecc_data[l]
            ecc = GF_MUL2[(ecc & 0xFF) ^ coeff] | (
                ((ecc & 0xFF00) ^ ((coeff & 0xFF) << 8)) & 0xFFFF
            )
        ecc_high = (ecc >> 8) & 0xFF
        ecc_low = GF_DIV3[GF_MUL2[ecc & 0xFF] ^ ecc_high]
        ecc_high ^= ecc_low
        ecc_data[43 * 26 * 2 + i] = ecc_low & 0xFF
        ecc_data[44 * 26 * 2 + i] = ecc_high & 0xFF


# ---------------------------------------------------------------------------
# Sector regeneration
# ---------------------------------------------------------------------------

def regenerate_edc_ecc(sector: bytearray) -> None:
    """Update EDC + ECC P + ECC Q in place. Sector is the full 2352-byte sector."""
    if len(sector) != SECTOR_SIZE:
        raise ValueError(f"sector must be {SECTOR_SIZE} bytes, got {len(sector)}")
    if sector[0x0F] != 0x02:
        raise ValueError("not a Mode 2 sector")

    # EDC over subheader + user data (8 + 2048 = 2056 bytes)
    edc = compute_edc(bytes(sector[SUBHEADER_OFFSET:SUBHEADER_OFFSET + 8 + USER_DATA_SIZE]))
    sector[EDC_OFFSET + 0] = edc & 0xFF
    sector[EDC_OFFSET + 1] = (edc >> 8) & 0xFF
    sector[EDC_OFFSET + 2] = (edc >> 16) & 0xFF
    sector[EDC_OFFSET + 3] = (edc >> 24) & 0xFF

    # ECC source = bytes 0x0C..0x0C + 2340 (header + subheader + user + EDC + P).
    # Address bytes (header[0..3]) must be zeroed before computing ECC.
    saved_addr = bytes(sector[HEADER_OFFSET:HEADER_OFFSET + 4])
    sector[HEADER_OFFSET + 0] = 0
    sector[HEADER_OFFSET + 1] = 0
    sector[HEADER_OFFSET + 2] = 0
    sector[HEADER_OFFSET + 3] = 0

    # Build a working buffer; P is written at offset 2064, Q at 2236.
    ecc_buf = bytearray(sector[HEADER_OFFSET:HEADER_OFFSET + 2340])
    _compute_ecc_p(ecc_buf)   # writes [2064..2235]
    _compute_ecc_q(ecc_buf)   # writes [2236..2339]
    sector[HEADER_OFFSET:HEADER_OFFSET + 2340] = ecc_buf

    # Restore the address bytes.
    sector[HEADER_OFFSET + 0] = saved_addr[0]
    sector[HEADER_OFFSET + 1] = saved_addr[1]
    sector[HEADER_OFFSET + 2] = saved_addr[2]
    sector[HEADER_OFFSET + 3] = saved_addr[3]


# ---------------------------------------------------------------------------
# PSX disc handle
# ---------------------------------------------------------------------------

@dataclass
class PsxDisc:
    """Read/write user data into a PSX BIN (Mode 2 Form 1, 2352 bytes/sector)."""

    path: Path

    def __post_init__(self) -> None:
        if isinstance(self.path, str):
            self.path = Path(self.path)
        size = self.path.stat().st_size
        if size % SECTOR_SIZE != 0:
            raise ValueError(
                f"{self.path}: {size} bytes is not a multiple of {SECTOR_SIZE}"
            )
        self.total_sectors = size // SECTOR_SIZE

    def read_sector(self, lba: int) -> bytes:
        if lba < 0 or lba >= self.total_sectors:
            raise IndexError(f"LBA {lba} out of range [0, {self.total_sectors})")
        with self.path.open("rb") as f:
            f.seek(lba * SECTOR_SIZE)
            return f.read(SECTOR_SIZE)

    def read_user_data(self, lba: int, n_sectors: int = 1) -> bytes:
        out = bytearray()
        with self.path.open("rb") as f:
            for k in range(n_sectors):
                f.seek((lba + k) * SECTOR_SIZE + USER_DATA_OFFSET)
                out.extend(f.read(USER_DATA_SIZE))
        return bytes(out)

    def write_user_data(self, lba: int, payload: bytes) -> None:
        """Write payload (any size) into sectors starting at lba.

        Pads the final sector with zeros to USER_DATA_SIZE. Regenerates
        EDC + ECC P + ECC Q for every touched sector. Sector header (sync,
        MSF, mode, subheader) is preserved.
        """
        n_full, rem = divmod(len(payload), USER_DATA_SIZE)
        n_sectors = n_full + (1 if rem else 0)
        if n_sectors == 0:
            return

        with self.path.open("r+b") as f:
            for k in range(n_sectors):
                cur_lba = lba + k
                f.seek(cur_lba * SECTOR_SIZE)
                sector = bytearray(f.read(SECTOR_SIZE))
                if len(sector) != SECTOR_SIZE:
                    raise EOFError(
                        f"short read at LBA {cur_lba} ({len(sector)} bytes)"
                    )
                slice_start = k * USER_DATA_SIZE
                slice_end = min(slice_start + USER_DATA_SIZE, len(payload))
                chunk = payload[slice_start:slice_end]
                # Zero-pad the trailing sector if needed.
                user = bytearray(USER_DATA_SIZE)
                user[:len(chunk)] = chunk
                sector[USER_DATA_OFFSET:USER_DATA_OFFSET + USER_DATA_SIZE] = user
                regenerate_edc_ecc(sector)
                f.seek(cur_lba * SECTOR_SIZE)
                f.write(sector)

    def write_byte_range(self, lba: int, offset_in_payload: int, data: bytes) -> None:
        """Write `data` at byte offset within the sector at `lba`. Reads, modifies,
        writes back via write_user_data so EDC/ECC are regenerated."""
        if offset_in_payload + len(data) > USER_DATA_SIZE:
            raise ValueError(
                "byte range crosses sector boundary; split before calling"
            )
        existing = bytearray(self.read_user_data(lba, 1))
        existing[offset_in_payload:offset_in_payload + len(data)] = data
        self.write_user_data(lba, bytes(existing))
