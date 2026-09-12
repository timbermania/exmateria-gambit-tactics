"""GNS file parser for FFT map files."""

from pathlib import Path
from typing import List, Tuple

from ..models.map_resource import (
    MapResource,
    MapArrangementState,
    MapTime,
    MapWeather,
    ResourceType,
)
from ..utils.binary import read_uint16_le


# Valid header bytes for resource entries
VALID_HEADERS = {34, 48, 112}

# Resource type mapping (high byte must be 0x01)
RESOURCE_TYPE_MAP = {
    23: ResourceType.TEXTURE,
    46: ResourceType.INITIAL_MESH_DATA,
    47: ResourceType.OVERRIDE_MESH_DATA,
    48: ResourceType.ALTERNATE_STATE_MESH_DATA,
    49: ResourceType.PADDED,
    128: ResourceType.UNKNOWN_EXTRA_DATA_A,
    133: ResourceType.UNKNOWN_TWIN,
    134: ResourceType.UNKNOWN_TWIN,
    135: ResourceType.UNKNOWN_TWIN,
    136: ResourceType.UNKNOWN_TWIN,
}

# Weather code mapping
WEATHER_MAP = {
    0: MapWeather.NONE,
    1: MapWeather.NONE_ALT,
    2: MapWeather.LIGHT,
    3: MapWeather.NORMAL,
    4: MapWeather.HEAVY,
}

# Byte offsets within a 20-byte resource entry
HEADER_INDEX = 0
ARRANGEMENT_INDEX = 2
TIME_WEATHER_INDEX = 3
RESOURCE_TYPE_HIGH_INDEX = 4
RESOURCE_TYPE_LOW_INDEX = 5
FILE_SECTOR_INDEX = 8


def parse_resource_entry(raw_data: bytes) -> MapResource:
    """Parse a single 20-byte resource entry from GNS data.

    Args:
        raw_data: 20 bytes of raw resource entry data

    Returns:
        MapResource with parsed fields
    """
    if len(raw_data) < 20:
        return MapResource(
            resource_type=ResourceType.UNKNOWN_TRAILING_DATA,
            arrangement=MapArrangementState.PRIMARY,
            time=MapTime.DAY,
            weather=MapWeather.NONE,
            file_sector=0,
            raw_data=raw_data,
        )

    # Check header validity
    header = raw_data[HEADER_INDEX]
    if header not in VALID_HEADERS:
        return MapResource(
            resource_type=ResourceType.UNKNOWN_EXTRA_DATA_B,
            arrangement=MapArrangementState.PRIMARY,
            time=MapTime.DAY,
            weather=MapWeather.NONE,
            file_sector=0,
            raw_data=raw_data,
        )

    # Parse resource type
    type_high = raw_data[RESOURCE_TYPE_HIGH_INDEX]
    type_low = raw_data[RESOURCE_TYPE_LOW_INDEX]

    if type_high == 1 and type_low in RESOURCE_TYPE_MAP:
        resource_type = RESOURCE_TYPE_MAP[type_low]
    else:
        resource_type = ResourceType.BAD_FORMAT

    # Parse arrangement (0 = Primary, 1 = Secondary)
    arrangement_byte = raw_data[ARRANGEMENT_INDEX]
    arrangement = (
        MapArrangementState.SECONDARY
        if arrangement_byte == 1
        else MapArrangementState.PRIMARY
    )

    # Parse time and weather from byte 3
    # Bit 7: Day(0)/Night(1)
    # Bits 6-4: Weather code (0-4)
    time_weather_byte = raw_data[TIME_WEATHER_INDEX]
    is_day = ((time_weather_byte >> 7) & 1) == 0
    weather_code = (time_weather_byte >> 4) & 0x07

    time = MapTime.DAY if is_day else MapTime.NIGHT
    weather = WEATHER_MAP.get(weather_code, MapWeather.NONE)

    # Parse file sector (little-endian uint16 at offset 8)
    file_sector = read_uint16_le(raw_data, FILE_SECTOR_INDEX)

    return MapResource(
        resource_type=resource_type,
        arrangement=arrangement,
        time=time,
        weather=weather,
        file_sector=file_sector,
        raw_data=raw_data,
    )


def parse_gns_file(gns_path: Path) -> Tuple[List[MapResource], List[MapResource], List[MapResource]]:
    """Parse a GNS file and return all resources.

    Args:
        gns_path: Path to the .gns file

    Returns:
        Tuple of (all_resources, mesh_resources, texture_resources)
    """
    raw_data = gns_path.read_bytes()

    all_resources: List[MapResource] = []

    # Process all 20-byte entries
    index = 0
    while index < len(raw_data):
        # Calculate available bytes for this entry
        remaining = len(raw_data) - index
        entry_length = min(20, remaining)

        if entry_length < 20:
            # Not enough bytes for a full entry
            break

        entry_data = raw_data[index:index + entry_length]
        resource = parse_resource_entry(entry_data)

        # Only keep mesh and texture resources
        if resource.is_mesh or resource.is_texture:
            all_resources.append(resource)

        index += entry_length

    # Sort by file sector
    all_resources.sort(key=lambda r: r.file_sector)

    # Separate mesh and texture resources
    mesh_resources = [r for r in all_resources if r.is_mesh]
    texture_resources = [r for r in all_resources if r.is_texture]

    return all_resources, mesh_resources, texture_resources


def load_resource_files(
    map_root: Path,
    all_resources: List[MapResource],
) -> bool:
    """Load resource file data (.0, .1, .2, etc.) for all resources.

    Args:
        map_root: Path to map without extension (e.g., /path/to/MAP022)
        all_resources: List of MapResource objects to populate

    Returns:
        True if all resources were loaded successfully
    """
    # Get unique file sectors
    file_sectors = []
    for resource in all_resources:
        if resource.file_sector not in file_sectors:
            file_sectors.append(resource.file_sector)

    # Load numbered resource files
    resource_file_data: List[bytes] = []
    resource_x_files: List[int] = []

    x_file_index = 0
    while len(resource_file_data) < len(file_sectors):
        x_file_path = Path(f"{map_root}.{x_file_index}")

        if x_file_path.exists():
            resource_file_data.append(x_file_path.read_bytes())
            resource_x_files.append(x_file_index)

        x_file_index += 1

        if x_file_index > 200:
            # Safety limit
            break

    # Assign resource data to resources
    if len(resource_x_files) == len(all_resources):
        for i, resource in enumerate(all_resources):
            resource.x_file = resource_x_files[i]
            resource.resource_data = resource_file_data[i]
        return True

    return False


def load_map(gns_path: Path) -> Tuple[List[MapResource], List[MapResource], List[MapResource], str]:
    """Load a complete FFT map from a GNS file.

    Args:
        gns_path: Path to the .gns file

    Returns:
        Tuple of (all_resources, mesh_resources, texture_resources, map_name)

    Raises:
        ValueError: If resources could not be loaded
    """
    map_name = gns_path.stem
    map_folder = gns_path.parent
    map_root = map_folder / map_name

    all_resources, mesh_resources, texture_resources = parse_gns_file(gns_path)

    if not load_resource_files(map_root, all_resources):
        raise ValueError(f"Could not locate all resource files for {map_name}")

    return all_resources, mesh_resources, texture_resources, map_name
