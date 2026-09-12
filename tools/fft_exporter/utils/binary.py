"""Binary reading utilities for parsing FFT data files."""

import struct


def read_uint8(data: bytes, offset: int) -> int:
    """Read unsigned 8-bit integer."""
    return data[offset]


def read_int16_le(data: bytes, offset: int) -> int:
    """Read signed 16-bit little-endian integer."""
    return struct.unpack_from('<h', data, offset)[0]


def read_uint16_le(data: bytes, offset: int) -> int:
    """Read unsigned 16-bit little-endian integer."""
    return struct.unpack_from('<H', data, offset)[0]


def read_int32_le(data: bytes, offset: int) -> int:
    """Read signed 32-bit little-endian integer."""
    return struct.unpack_from('<i', data, offset)[0]


def read_uint32_le(data: bytes, offset: int) -> int:
    """Read unsigned 32-bit little-endian integer."""
    return struct.unpack_from('<I', data, offset)[0]


def get_bits(byte_val: int, start: int, count: int) -> int:
    """Extract bits from a byte value.

    Args:
        byte_val: The byte value to extract from
        start: Starting bit position (0 = LSB)
        count: Number of bits to extract

    Returns:
        The extracted bits as an integer
    """
    mask = (1 << count) - 1
    return (byte_val >> start) & mask


def get_bit(byte_val: int, bit: int) -> bool:
    """Extract a single bit from a byte value.

    Args:
        byte_val: The byte value to extract from
        bit: Bit position (0 = LSB)

    Returns:
        True if bit is set, False otherwise
    """
    return bool((byte_val >> bit) & 1)
