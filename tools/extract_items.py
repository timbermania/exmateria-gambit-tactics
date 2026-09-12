#!/usr/bin/env python3
"""
Extract FFT item data from game ISO extract.

Parses SCUS_942.21 to create items.json with all equipment data for the Godot project.

Binary structure (from OldItems section):
- 0x000-0xBFF: Common item data (256 items × 12 bytes)
- 0xC00-0xFFF: Weapon data (128 weapons × 8 bytes)
- 0x1000-0x101F: Shield data (16 shields × 2 bytes)
- 0x1020-0x109F: Armor data (64 armors × 2 bytes)
- 0x10A0-0x10DF: Accessory data (32 accessories × 2 bytes)
- 0x10E0+: Chemist item data (14 items × 3 bytes)

Item ranges:
- 0x00-0x7F: Weapons (knives, swords, katanas, axes, rods, staffs, etc.)
- 0x80-0x8F: Shields
- 0x90-0xCF: Armor (helms, body armor, clothes, robes)
- 0xD0-0xEF: Accessories (shoes, gauntlets, rings, armlets, mantles)
- 0xF0-0xFD: Chemist items (consumables)

Data source: the FFT PSX extract, resolved host-agnostically via _repo_paths
(CLI/env/<repo>/project-assets/fft-extract). Offsets from FFTPatcher PsxIso.cs.
"""

import json
from pathlib import Path

# Input path — resolves to <repo>/project-assets/fft-extract via shared helper.
from _repo_paths import scus as _scus
SCUS_FILE = _scus()

# Bit-packed FFT data decodes at the parser boundary (see ADR-0013).
from _fft_decode import (
    ELEMENTS,
    STATUS_NAMES_BY_BYTE,
    decode_set_msb,
    decode_set_msb_bytes,
    decode_flags_msb,
    extract_inflict_status_sets,
)

# Offsets from FFTPatcher PsxIso.cs
ITEMS_OFFSET = 0x536B8
ITEMS_SIZE = 0x110A  # 4362 bytes
ITEM_ATTR_OFFSET = 0x54AC4
ITEM_ATTR_SIZE = 0x7D0  # 2000 bytes

# Output path
# ADR-0251 dec. 2 — items.json and item_attributes.json moved into the almanac
# addon with `ItemDatabase`, which is the one database that carries TWO payloads.
OUTPUT_DIR = Path(__file__).parent.parent / "addons/exmateria_almanac/items"

# Item type enum values
ITEM_SUBTYPES = [
    "Nothing", "Knife", "NinjaBlade", "Sword", "KnightsSword", "Katana",
    "Axe", "Rod", "Staff", "Flail", "Gun", "Crossbow", "Bow", "Instrument",
    "Book", "Polearm", "Pole", "Bag", "Cloth", "Shield", "Helmet", "Hat",
    "HairAdornment", "Armor", "Clothing", "Robe", "Shoes", "Armguard",
    "Ring", "Armlet", "Cloak", "Perfume", "Throwing", "Bomb", "ChemistItem",
    "FellSword", "LipRouge"
]

# `ELEMENTS` now imported from `_fft_decode` (see ADR-0013).

# Item names (extracted from FFTPatcher Items.xml)
ITEM_NAMES = {
    0: "<Nothing>",
    1: "Dagger",
    2: "Mythril Knife",
    3: "Blind Knife",
    4: "Mage Masher",
    5: "Platina Dagger",
    6: "Main Gauche",
    7: "Orichalcum",
    8: "Assassin Dagger",
    9: "Air Knife",
    10: "Zorlin Shape",
    11: "Hidden Knife",
    12: "Ninja Knife",
    13: "Short Edge",
    14: "Ninja Edge",
    15: "Spell Edge",
    16: "Sasuke Knife",
    17: "Iga Knife",
    18: "Koga Knife",
    19: "Broad Sword",
    20: "Long Sword",
    21: "Iron Sword",
    22: "Mythril Sword",
    23: "Blood Sword",
    24: "Coral Sword",
    25: "Ancient Sword",
    26: "Sleep Sword",
    27: "Platinum Sword",
    28: "Diamond Sword",
    29: "Ice Brand",
    30: "Rune Blade",
    31: "Nagrarock",
    32: "Materia Blade",
    33: "Defender",
    34: "Save the Queen",
    35: "Excalibur",
    36: "Ragnarok",
    37: "Chaos Blade",
    38: "Asura Knife",
    39: "Koutetsu Knife",
    40: "Bizen Boat",
    41: "Murasame",
    42: "Heaven's Cloud",
    43: "Kiyomori",
    44: "Muramasa",
    45: "Kikuichimoji",
    46: "Masamune",
    47: "Chirijiraden",
    48: "Battle Axe",
    49: "Giant Axe",
    50: "Slasher",
    51: "Rod",
    52: "Thunder Rod",
    53: "Flame Rod",
    54: "Ice Rod",
    55: "Poison Rod",
    56: "Wizard Rod",
    57: "Dragon Rod",
    58: "Faith Rod",
    59: "Oak Staff",
    60: "White Staff",
    61: "Healing Staff",
    62: "Rainbow Staff",
    63: "Wizard Staff",
    64: "Gold Staff",
    65: "Mace of Zeus",
    66: "Sage Staff",
    67: "Flail",
    68: "Flame Whip",
    69: "Morning Star",
    70: "Scorpion Tail",
    71: "Romanda Gun",
    72: "Mythril Gun",
    73: "Stone Gun",
    74: "Blaze Gun",
    75: "Glacier Gun",
    76: "Blast Gun",
    77: "Bow Gun",
    78: "Night Killer",
    79: "Cross Bow",
    80: "Poison Bow",
    81: "Hunting Bow",
    82: "Gastrafitis",
    83: "Long Bow",
    84: "Silver Bow",
    85: "Ice Bow",
    86: "Lightning Bow",
    87: "Windslash Bow",
    88: "Mythril Bow",
    89: "Ultimus Bow",
    90: "Yoichi Bow",
    91: "Perseus Bow",
    92: "Ramia Harp",
    93: "Bloody Strings",
    94: "Fairy Harp",
    95: "Battle Dict",
    96: "Monster Dict",
    97: "Papyrus Plate",
    98: "Madlemgen",
    99: "Javelin",
    100: "Spear",
    101: "Mythril Spear",
    102: "Partisan",
    103: "Oberisk",
    104: "Holy Lance",
    105: "Dragon Whisker",
    106: "Javelin",
    107: "Cypress Rod",
    108: "Battle Bamboo",
    109: "Musk Rod",
    110: "Iron Fan",
    111: "Gokuu Rod",
    112: "Ivory Rod",
    113: "Octagon Rod",
    114: "Whale Whisker",
    115: "C Bag",
    116: "FS Bag",
    117: "P Bag",
    118: "H Bag",
    119: "Persia",
    120: "Cashmere",
    121: "Ryozan Silk",
    122: "Shuriken",
    123: "Magic Shuriken",
    124: "Yagyu Darkness",
    125: "Fire Ball",
    126: "Water Ball",
    127: "Lightning Ball",
    128: "Escutcheon",
    129: "Buckler",
    130: "Bronze Shield",
    131: "Round Shield",
    132: "Mythril Shield",
    133: "Gold Shield",
    134: "Ice Shield",
    135: "Flame Shield",
    136: "Aegis Shield",
    137: "Diamond Shield",
    138: "Platina Shield",
    139: "Crystal Shield",
    140: "Genji Shield",
    141: "Kaiser Plate",
    142: "Venetian Shield",
    143: "Escutcheon",
    144: "Leather Helmet",
    145: "Bronze Helmet",
    146: "Iron Helmet",
    147: "Barbuta",
    148: "Mythril Helmet",
    149: "Gold Helmet",
    150: "Cross Helmet",
    151: "Diamond Helmet",
    152: "Platina Helmet",
    153: "Circlet",
    154: "Crystal Helmet",
    155: "Genji Helmet",
    156: "Grand Helmet",
    157: "Leather Hat",
    158: "Feather Hat",
    159: "Red Hood",
    160: "Headgear",
    161: "Triangle Hat",
    162: "Green Beret",
    163: "Twist Headband",
    164: "Holy Miter",
    165: "Black Hood",
    166: "Golden Hairpin",
    167: "Flash Hat",
    168: "Thief Hat",
    169: "Cachusha",
    170: "Barette",
    171: "Ribbon",
    172: "Leather Armor",
    173: "Linen Cuirass",
    174: "Bronze Armor",
    175: "Chain Mail",
    176: "Mythril Armor",
    177: "Plate Mail",
    178: "Gold Armor",
    179: "Diamond Armor",
    180: "Platina Armor",
    181: "Carabini Mail",
    182: "Crystal Mail",
    183: "Genji Armor",
    184: "Reflect Mail",
    185: "Maximillian",
    186: "Clothes",
    187: "Leather Outfit",
    188: "Leather Vest",
    189: "Chain Vest",
    190: "Mythril Vest",
    191: "Adaman Vest",
    192: "Wizard Outfit",
    193: "Brigandine",
    194: "Judo Outfit",
    195: "Power Sleeve",
    196: "Earth Clothes",
    197: "Secret Clothes",
    198: "Black Costume",
    199: "Rubber Costume",
    200: "Linen Robe",
    201: "Silk Robe",
    202: "Wizard Robe",
    203: "Chameleon Robe",
    204: "White Robe",
    205: "Black Robe",
    206: "Light Robe",
    207: "Robe of Lords",
    208: "Battle Boots",
    209: "Spike Shoes",
    210: "Germinas Boots",
    211: "Rubber Shoes",
    212: "Feather Boots",
    213: "Sprint Shoes",
    214: "Red Shoes",
    215: "Power Wrist",
    216: "Genji Gauntlet",
    217: "Magic Gauntlet",
    218: "Bracer",
    219: "Reflect Ring",
    220: "Defense Ring",
    221: "Magic Ring",
    222: "Cursed Ring",
    223: "Angel Ring",
    224: "Diamond Armlet",
    225: "Jade Armlet",
    226: "108 Gems",
    227: "N-Kai Armlet",
    228: "Defense Armlet",
    229: "Small Mantle",
    230: "Leather Mantle",
    231: "Wizard Mantle",
    232: "Elf Mantle",
    233: "Dracula Mantle",
    234: "Feather Mantle",
    235: "Vanish Mantle",
    236: "Chantage",
    237: "Cherche",
    238: "Setiemson",
    239: "Salty Rage",
    240: "Potion",
    241: "Hi-Potion",
    242: "X-Potion",
    243: "Ether",
    244: "Hi-Ether",
    245: "Elixir",
    246: "Antidote",
    247: "Eye Drop",
    248: "Echo Grass",
    249: "Maiden's Kiss",
    250: "Soft",
    251: "Holy Water",
    252: "Remedy",
    253: "Phoenix Down",
    254: "<Nothing>",
    255: "<Nothing>",
}

# Item attribute names (extracted from FFTPatcher ItemAttributes.xml)
ITEM_ATTR_NAMES = {
    0x00: "",
    0x01: "Rune Blade",
    0x02: "Save the Queen",
    0x03: "Excalibur",
    0x04: "Ragnarok",
    0x05: "Chaos Blade",
    0x06: "Thunder Rod",
    0x07: "Flame Rod",
    0x08: "Ice Rod",
    0x09: "Wizard Rod",
    0x0A: "Wizard Staff",
    0x0B: "Mace of Zeus",
    0x0C: "C Bag",
    0x0D: "P Bag",
    0x0E: "H Bag",
    0x0F: "Ice Shield",
    0x10: "Flame Shield",
    0x11: "Aegis Shield",
    0x12: "Kaiser Plate",
    0x13: "Venetian Shield",
    0x14: "Grand Helmet",
    0x15: "Headgear",
    0x16: "Triangle Hat",
    0x17: "Green Beret",
    0x18: "Twist Headband",
    0x19: "Holy Miter",
    0x1A: "Golden Hairpin",
    0x1B: "Flash Hat",
    0x1C: "Thief Hat",
    0x1D: "Reflect Mail",
    0x1E: "Judo Outfit",
    0x1F: "Power Sleeve",
    0x20: "Earth Clothes",
    0x21: "Secret Clothes",
    0x22: "Black Costume",
    0x23: "Rubber Costume",
    0x24: "Wizard Robe",
    0x25: "Chameleon Robe",
    0x26: "White Robe",
    0x27: "Black Robe",
    0x28: "Light Robe",
    0x29: "Robe of Lords",
    0x2A: "Battle Boots",
    0x2B: "Spike Shoes",
    0x2C: "Germinas Boots",
    0x2D: "Rubber Shoes",
    0x2E: "Feather Boots",
    0x2F: "Sprint Shoes",
    0x30: "Red Shoes",
    0x31: "Power Wrist",
    0x32: "Genji Gauntlet",
    0x33: "Magic Gauntlet",
    0x34: "Bracer",
    0x35: "Reflect Ring",
    0x36: "Defense Ring",
    0x37: "Magic Ring",
    0x38: "Cursed Ring",
    0x39: "Angel Ring",
    0x3A: "Diamond Armlet",
    0x3B: "Jade Armlet",
    0x3C: "108 Gems",
    0x3D: "N-Kai Armlet",
    0x3E: "Defense Armlet",
    0x3F: "Wizard Mantle",
    0x40: "Vanish Mantle",
    0x41: "Chantage",
    0x42: "Cherche",
    0x43: "Setiemson",
    0x44: "Salty Rage",
    0x45: "Cachusha",
    0x46: "Barette",
    0x47: "Ribbon",
    0x48: "Stone Gun",
    0x49: "Faith Rod",
    0x4A: "",
    0x4B: "",
    0x4C: "",
    0x4D: "",
    0x4E: "",
    0x4F: "",
}


# Local aliases keep the existing call sites short; the implementations
# live in `_fft_decode` per ADR-0013. Both decoders use FFT's MSB-first
# per-byte convention (FFTPatcher `ByteFromBooleans`: first param = bit 7),
# so the name lists at call sites are written *MSB-first* — `[Fire,
# Lightning, …, Dark]` means Fire at bit 7 (matching `ElementFlags.Fire =
# 0x80`), and `[striking, lunging, …, force_two_hands]` matches
# FFTPatcher's `ByteFromBooleans(Striking, …, Force2Hands)`.
def decode_elements(byte_val: int) -> list[str]:
    return decode_set_msb(byte_val, ELEMENTS)


def decode_flags(byte_val: int, flag_names: list[str]) -> dict[str, bool]:
    return decode_flags_msb(byte_val, flag_names)


def parse_common_item(data: bytes, offset: int) -> dict:
    """Parse 12 bytes of common item data."""
    return {
        "palette": data[0],
        "graphic": data[1],
        "enemy_level": data[2],
        "slot_flags": decode_flags(data[3], [
            "weapon", "shield", "head", "body", "accessory", "blank1", "rare", "blank2"
        ]),
        "second_table_id": data[4],
        "item_type": ITEM_SUBTYPES[data[5]] if data[5] < len(ITEM_SUBTYPES) else f"Unknown_{data[5]}",
        "item_type_id": data[5],
        "unknown1": data[6],
        "sia": data[7],  # Secondary Item Attribute index
        "price": int.from_bytes(data[8:10], "little"),
        "shop_availability": data[10],
        "unknown2": data[11],
    }


def parse_weapon(data: bytes, inflict_sets: dict[int, dict]) -> dict:
    """Parse 8 bytes of weapon-specific data."""
    inflict_entry = inflict_sets[data[7]]
    return {
        "range": data[0],
        "weapon_flags": decode_flags(data[1], [
            "striking", "lunging", "direct", "arc", "two_swords", "two_hands", "throwable", "force_two_hands"
        ]),
        "formula": data[2],
        "unknown": data[3],
        "weapon_power": data[4],
        "evade_percent": data[5],
        "elements": decode_elements(data[6]),
        # ADR-0013: decoded name array + mode enum; raw set_id index stays only
        # in tools/extracted/inflict_status_sets.json for traceability.
        "inflict_statuses": list(inflict_entry["statuses"]),
        "inflict_mode": inflict_entry["mode"],
    }


def parse_shield(data: bytes) -> dict:
    """Parse 2 bytes of shield-specific data."""
    return {
        "physical_block": data[0],
        "magic_block": data[1],
    }


def parse_armor(data: bytes) -> dict:
    """Parse 2 bytes of armor-specific data."""
    return {
        "hp_bonus": data[0],
        "mp_bonus": data[1],
    }


def parse_accessory(data: bytes) -> dict:
    """Parse 2 bytes of accessory-specific data (same as armor)."""
    return {
        "hp_bonus": data[0],
        "mp_bonus": data[1],
    }


def parse_chemist_item(data: bytes, inflict_sets: dict[int, dict]) -> dict:
    """Parse 3 bytes of chemist item data."""
    inflict_entry = inflict_sets[data[2]]
    return {
        "formula": data[0],
        "z_value": data[1],
        # ADR-0013 — same shape as parse_weapon.
        "inflict_statuses": list(inflict_entry["statuses"]),
        "inflict_mode": inflict_entry["mode"],
    }


def parse_item_attributes(data: bytes, attr_id: int) -> dict:
    """Parse 25 bytes of item attribute data."""
    return {
        "attr_id": attr_id,
        "pa_bonus": data[0],
        "ma_bonus": data[1],
        "speed_bonus": data[2],
        "move_bonus": data[3],
        "jump_bonus": data[4],
        "permanent_statuses": decode_set_msb_bytes(list(data[5:10]), STATUS_NAMES_BY_BYTE),
        "status_immunity": decode_set_msb_bytes(list(data[10:15]), STATUS_NAMES_BY_BYTE),
        "starting_statuses": decode_set_msb_bytes(list(data[15:20]), STATUS_NAMES_BY_BYTE),
        "absorb_elements": decode_elements(data[20]),
        "cancel_elements": decode_elements(data[21]),
        "half_elements": decode_elements(data[22]),
        "weak_elements": decode_elements(data[23]),
        "strengthen_elements": decode_elements(data[24]),
    }


def extract_items():
    """Extract all items from SCUS_942.21."""
    print("Loading item data from SCUS_942.21...")

    # Load binary data from SCUS file. We slurp the whole thing so we can
    # also decode the inflict-status set table (used by weapons + chemist
    # items per ADR-0013).
    with open(SCUS_FILE, "rb") as f:
        scus_data = f.read()
    items_data = scus_data[ITEMS_OFFSET:ITEMS_OFFSET + ITEMS_SIZE]
    attr_data = scus_data[ITEM_ATTR_OFFSET:ITEM_ATTR_OFFSET + ITEM_ATTR_SIZE]
    inflict_sets = extract_inflict_status_sets(scus_data)

    print(f"  Read {len(items_data)} bytes of item data")
    print(f"  Read {len(attr_data)} bytes of attribute data")

    # Parse item attributes (80 entries × 25 bytes = 2000 bytes)
    attributes = {}
    for i in range(80):
        offset = i * 25
        attr = parse_item_attributes(attr_data[offset:offset + 25], i)
        attr["name"] = ITEM_ATTR_NAMES.get(i, "")
        attributes[i] = attr

    # Parse items
    items = {}

    # Weapons (0x00-0x7F)
    for i in range(0x80):
        common_offset = i * 12
        weapon_offset = 0xC00 + i * 8

        item = parse_common_item(items_data[common_offset:common_offset + 12], i)
        item["id"] = i
        item["name"] = ITEM_NAMES.get(i, f"Weapon_{i}")
        item["category"] = "weapon"
        item["weapon"] = parse_weapon(items_data[weapon_offset:weapon_offset + 8], inflict_sets)

        # Link to attributes if SIA > 0
        if item["sia"] > 0 and item["sia"] < 80:
            item["attributes"] = attributes[item["sia"]]

        items[i] = item

    # Shields (0x80-0x8F)
    for i in range(0x80, 0x90):
        common_offset = i * 12
        shield_offset = 0x1000 + (i - 0x80) * 2

        item = parse_common_item(items_data[common_offset:common_offset + 12], i)
        item["id"] = i
        item["name"] = ITEM_NAMES.get(i, f"Shield_{i}")
        item["category"] = "shield"
        item["shield"] = parse_shield(items_data[shield_offset:shield_offset + 2])

        if item["sia"] > 0 and item["sia"] < 80:
            item["attributes"] = attributes[item["sia"]]

        items[i] = item

    # Armor (0x90-0xCF) - includes helms, body armor, clothes, robes
    for i in range(0x90, 0xD0):
        common_offset = i * 12
        armor_offset = 0x1020 + (i - 0x90) * 2

        item = parse_common_item(items_data[common_offset:common_offset + 12], i)
        item["id"] = i
        item["name"] = ITEM_NAMES.get(i, f"Armor_{i}")
        item["category"] = "armor"
        item["armor"] = parse_armor(items_data[armor_offset:armor_offset + 2])

        if item["sia"] > 0 and item["sia"] < 80:
            item["attributes"] = attributes[item["sia"]]

        items[i] = item

    # Accessories (0xD0-0xEF) - shoes, gauntlets, rings, armlets, mantles, perfumes
    for i in range(0xD0, 0xF0):
        common_offset = i * 12
        acc_offset = 0x10A0 + (i - 0xD0) * 2

        item = parse_common_item(items_data[common_offset:common_offset + 12], i)
        item["id"] = i
        item["name"] = ITEM_NAMES.get(i, f"Accessory_{i}")
        item["category"] = "accessory"
        item["accessory"] = parse_accessory(items_data[acc_offset:acc_offset + 2])

        if item["sia"] > 0 and item["sia"] < 80:
            item["attributes"] = attributes[item["sia"]]

        items[i] = item

    # Chemist items (0xF0-0xFD)
    for i in range(0xF0, 0xFE):
        common_offset = i * 12
        chem_offset = 0x10E0 + (i - 0xF0) * 3

        item = parse_common_item(items_data[common_offset:common_offset + 12], i)
        item["id"] = i
        item["name"] = ITEM_NAMES.get(i, f"ChemistItem_{i}")
        item["category"] = "consumable"
        item["chemist"] = parse_chemist_item(items_data[chem_offset:chem_offset + 3], inflict_sets)

        items[i] = item

    return items, attributes


def main():
    """Main entry point."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    items, attributes = extract_items()

    # Write items.json
    output_path = OUTPUT_DIR / "items.json"
    with open(output_path, "w") as f:
        json.dump(items, f, indent=2)
    print(f"Wrote {len(items)} items to {output_path}")

    # Write item_attributes.json
    attr_path = OUTPUT_DIR / "item_attributes.json"
    with open(attr_path, "w") as f:
        json.dump(attributes, f, indent=2)
    print(f"Wrote {len(attributes)} item attributes to {attr_path}")

    # Print summary
    categories = {}
    for item in items.values():
        cat = item["category"]
        categories[cat] = categories.get(cat, 0) + 1

    print("\nItem categories:")
    for cat, count in sorted(categories.items()):
        print(f"  {cat}: {count}")


if __name__ == "__main__":
    main()
