#!/usr/bin/env python3
"""Extract ability and skill set data from game ISO extract.

Data source: the FFT PSX extract, resolved host-agnostically via _repo_paths
(CLI/env/<repo>/project-assets/fft-extract). Offsets from FFTPatcher PsxIso.cs.

Outputs:
- assets/abilities/abilities.json - All ability definitions
- assets/abilities/skill_sets.json - Skill sets mapping jobs to learnable abilities
"""

import json
import struct
from pathlib import Path

# Input path — resolves to <repo>/project-assets/fft-extract via shared helper.
from _repo_paths import scus as _scus
SCUS_FILE = _scus()

# Offsets from FFTPatcher PsxIso.cs
ABILITIES_OFFSET = 0x4F3F0
ABILITIES_SIZE = 9414
SKILLSETS_OFFSET = 0x55294
SKILLSETS_SIZE = 0x1130  # 4400 bytes

OUTPUT_DIR = Path(__file__).parent.parent / "assets/abilities"

# Ability names (extracted from FFTPatcher Abilities.xml)
ABILITY_NAMES = {
    0: "<Nothing>",
    1: "Cure",
    2: "Cure 2",
    3: "Cure 3",
    4: "Cure 4",
    5: "Raise",
    6: "Raise 2",
    7: "Reraise",
    8: "Regen",
    9: "Protect",
    10: "Protect 2",
    11: "Shell",
    12: "Shell 2",
    13: "Wall",
    14: "Esuna",
    15: "Holy",
    16: "Fire",
    17: "Fire 2",
    18: "Fire 3",
    19: "Fire 4",
    20: "Bolt",
    21: "Bolt 2",
    22: "Bolt 3",
    23: "Bolt 4",
    24: "Ice",
    25: "Ice 2",
    26: "Ice 3",
    27: "Ice 4",
    28: "Poison",
    29: "Frog",
    30: "Death",
    31: "Flare",
    32: "Haste",
    33: "Haste 2",
    34: "Slow",
    35: "Slow 2",
    36: "Stop",
    37: "Don't Move",
    38: "Float",
    39: "Reflect",
    40: "(Summon Demon)",
    41: "Quick",
    42: "Demi",
    43: "Demi 2",
    44: "Meteor",
    45: "",
    46: "Blind",
    47: "Spell Absorb",
    48: "Life Drain",
    49: "Pray Faith",
    50: "Doubt Faith",
    51: "Zombie",
    52: "Silence Song",
    53: "Blind Rage",
    54: "Foxbird",
    55: "Confusion Song",
    56: "Dispel Magic",
    57: "Paralyze",
    58: "Sleep",
    59: "Petrify",
    60: "Moogle",
    61: "Shiva",
    62: "Ramuh",
    63: "Ifrit",
    64: "Titan",
    65: "Golem",
    66: "Carbunkle",
    67: "Bahamut",
    68: "Odin",
    69: "Leviathan",
    70: "Salamander",
    71: "Silf",
    72: "Fairy",
    73: "Lich",
    74: "Cyclops",
    75: "Zodiac",
    76: "Asura",
    77: "Koutetsu",
    78: "Bizen Boat",
    79: "Murasame",
    80: "Heaven's Cloud",
    81: "Kiyomori",
    82: "Muramasa",
    83: "Kikuichimoji",
    84: "Masamune",
    85: "Chirijiraden",
    86: "Angel Song",
    87: "Life Song",
    88: "Cheer Song",
    89: "Battle Song",
    90: "Magic Song",
    91: "Nameless Song",
    92: "Last Song",
    93: "Witch Hunt",
    94: "Wiznaibus",
    95: "Slow Dance",
    96: "Polka Polka",
    97: "Disillusion",
    98: "Nameless Dance",
    99: "Last Dance",
    100: "Spin Fist",
    101: "Repeating Fist",
    102: "Wave Fist",
    103: "Earth Slash",
    104: "Secret Fist",
    105: "Stigma Magic",
    106: "Chakra",
    107: "Revive",
    108: "Gil Taking",
    109: "Steal Heart",
    110: "Steal Helmet",
    111: "Steal Armor",
    112: "Steal Shield",
    113: "Steal Weapon",
    114: "Steal Accessory",
    115: "Steal Exp",
    116: "Invitation",
    117: "Persuade",
    118: "Praise",
    119: "Threaten",
    120: "Preach",
    121: "Solution",
    122: "Death Sentence",
    123: "Negotiate",
    124: "Insult",
    125: "Mimic Daravon",
    126: "Pitfall",
    127: "Water Ball",
    128: "Hell Ivy",
    129: "Carve Model",
    130: "Local Quake",
    131: "Kamaitachi",
    132: "Demon Fire",
    133: "Quicksand",
    134: "Sand Storm",
    135: "Blizzard",
    136: "Gusty Wind",
    137: "Lava Ball",
    138: "Head Break",
    139: "Armor Break",
    140: "Shield Break",
    141: "Weapon Break",
    142: "Magic Break",
    143: "Speed Break",
    144: "Power Break",
    145: "Mind Break",
    146: "Accumulate",
    147: "Dash",
    148: "Throw Stone",
    149: "Heal",
    150: "Yell",
    151: "Cheer Up",
    152: "Wish",
    153: "Scream",
    154: "Ultima",
    155: "Stasis Sword",
    156: "Split Punch",
    157: "Crush Punch",
    158: "Lightning Stab",
    159: "Holy Explosion",
    160: "Shellbust Stab",
    161: "Blastar Punch",
    162: "Hellcry Punch",
    163: "Icewolf Bite",
    164: "Dark Sword",
    165: "Night Sword",
    166: "Dark Holy",
    167: "Deathspell 2",
    168: "Galaxy Stop",
    169: "Heaven Thunder",
    170: "Asura",
    171: "Diamond Sword",
    172: "Hydragon Pit",
    173: "Space Storage",
    174: "Sky Demon",
    175: "Heaven Bolt Back",
    176: "Asura Back",
    177: "Diamond Sword Back",
    178: "Hydragon Pit Back",
    179: "Space Storage Back",
    180: "Sky Demon Back",
    181: "Seal",
    182: "Shadow Stitch",
    183: "Stop Bracelet",
    184: "(Summon Angel)",
    185: "Shock",
    186: "Difference",
    187: "Seal",
    188: "Chicken Race",
    189: "Hold Tight",
    190: "Darkness",
    191: "Lose Voice",
    192: "Loss",
    193: "Spell",
    194: "Nightmare",
    195: "Death Cold",
    196: "Magic Ruin",
    197: "Speed Ruin",
    198: "Power Ruin",
    199: "Mind Ruin",
    200: "Blood Suck",
    201: "Allure",
    202: "Bio",
    203: "Bio",
    204: "Bio",
    205: "Bio 2",
    206: "Bio 2",
    207: "Bio 2",
    208: "Bio 2",
    209: "Bio 3",
    210: "Bio 3",
    211: "Bio 3",
    212: "Magic Barrier",
    213: "Leg Aim",
    214: "Arm Aim",
    215: "Seal Evil",
    216: "Melt",
    217: "Tornado",
    218: "Quake",
    219: "(Teleport 3: Send)",
    220: "(Teleport 3: Arrive)",
    221: "Toad 2",
    222: "Gravi 2",
    223: "Flare 2",
    224: "Blind 2",
    225: "Small Bomb",
    226: "Small Bomb",
    227: "Confuse 2",
    228: "Sleep 2",
    229: "Ultima",
    230: "All-ultima",
    231: "Mute",
    232: "Despair 2",
    233: "Return 2",
    234: "Blind",
    235: "Aspel",
    236: "Drain",
    237: "Faith",
    238: "Innocent",
    239: "Zombie",
    240: "Silence",
    241: "Berserk",
    242: "Chicken",
    243: "Confuse",
    244: "Despair",
    245: "Don't Act",
    246: "Sleep",
    247: "Break",
    248: "Ice Bracelet",
    249: "Fire Bracelet",
    250: "Thunder Bracelet",
    251: "Dragon Tame",
    252: "Dragon Care",
    253: "Dragon Power Up",
    254: "Dragon Level Up",
    255: "Holy Bracelet",
    256: "Shock!",
    257: "Braver",
    258: "Cross-slash",
    259: "Blade Beam",
    260: "Climhazzard",
    261: "Meteorain",
    262: "Finish Touch",
    263: "Omnislash",
    264: "Cherry Blossom",
    265: "Choco Attack",
    266: "Choco Ball",
    267: "Choco Meteor",
    268: "Choco Esuna",
    269: "Choco Cure",
    270: "Tackle",
    271: "Goblin Punch",
    272: "Turn Punch",
    273: "Eye Gouge",
    274: "Mutilate",
    275: "Bite",
    276: "Small Bomb",
    277: "Self Destruct",
    278: "Flame Attack",
    279: "Spark",
    280: "Scratch",
    281: "Cat Kick",
    282: "Blaster",
    283: "Poison Nail",
    284: "Blood Suck",
    285: "Tentacle",
    286: "Black Ink",
    287: "Odd Soundwave",
    288: "Mind Blast",
    289: "Level Blast",
    290: "Knife Hand",
    291: "Thunder Soul",
    292: "Aqua Soul",
    293: "Ice Soul",
    294: "Wind Soul",
    295: "Throw Spirit",
    296: "Zombie Touch",
    297: "Sleep Touch",
    298: "Drain Touch",
    299: "Grease Touch",
    300: "Wing Attack",
    301: "Look of Devil",
    302: "Look of Fright",
    303: "Circle",
    304: "Death Sentence",
    305: "Scratch Up",
    306: "Beak",
    307: "Shine Lover",
    308: "Feather Bomb",
    309: "Beaking",
    310: "Straight Dash",
    311: "Nose Bracelet",
    312: "Oink",
    313: "Pooh-",
    314: "Please Eat",
    315: "Leaf Dance",
    316: "Protect Spirit",
    317: "Clam Spirit",
    318: "Spirit of Life",
    319: "Magic Spirit",
    320: "Shake Off",
    321: "Wave Around",
    322: "Mimic Titan",
    323: "Gather Power",
    324: "Blow Fire",
    325: "Tentacle",
    326: "Lick",
    327: "Goo",
    328: "Bad Bracelet",
    329: "Moldball Virus",
    330: "Stab Up",
    331: "Sudden Cry",
    332: "Hurricane",
    333: "Ulmaguest",
    334: "Giga Flare",
    335: "Dash",
    336: "Tail Swing",
    337: "Ice Bracelet",
    338: "Fire Bracelet",
    339: "Thunder Bracelet",
    340: "Triple Attack",
    341: "Triple Bracelet",
    342: "Triple Thunder",
    343: "Triple Flame",
    344: "Dark Whisper",
    345: "Snake Carrier",
    346: "Poison Frog",
    347: "Midgar Swarm",
    348: "Lifebreak",
    349: "Nanoflare",
    350: "Grand Cross",
    351: "Destroy",
    352: "Compress",
    353: "Dispose",
    354: "Crush",
    355: "Energy",
    356: "Parasite",
    357: "",
    358: "",
    359: "",
    360: "",
    361: "",
    362: "",
    363: "",
    364: "",
    365: "",
    366: "",
    367: "Frog Attack",
    368: "Potion",
    369: "Hi-Potion",
    370: "X-Potion",
    371: "Ether",
    372: "Hi-Ether",
    373: "Elixir",
    374: "Antidote",
    375: "Eye Drop",
    376: "Echo Grass",
    377: "Maiden's Kiss",
    378: "Soft",
    379: "Holy Water",
    380: "Remedy",
    381: "Phoenix Down",
    382: "Shuriken",
    383: "Knife",
    384: "Sword",
    385: "Hammer",
    386: "Katana",
    387: "Ninja Sword",
    388: "Axe",
    389: "Spear",
    390: "Stick",
    391: "Knight Sword",
    392: "Dictionary",
    393: "Ball",
    394: "Level Jump2",
    395: "Level Jump3",
    396: "Level Jump4",
    397: "Level Jump5",
    398: "Level Jump8",
    399: "Vertical Jump2",
    400: "Vertical Jump3",
    401: "Vertical Jump4",
    402: "Vertical Jump5",
    403: "Vertical Jump6",
    404: "Vertical Jump7",
    405: "Vertical Jump8",
    406: "Charge+1",
    407: "Charge+2",
    408: "Charge+3",
    409: "Charge+4",
    410: "Charge+5",
    411: "Charge+7",
    412: "Charge+10",
    413: "Charge+20",
    414: "CT",
    415: "Level",
    416: "Exp",
    417: "Height",
    418: "Prime Number",
    419: "5",
    420: "4",
    421: "3",
    422: "A Save",
    423: "MA Save",
    424: "Speed Save",
    425: "Sunken State",
    426: "Caution",
    427: "Dragon Spirit",
    428: "Regenerator",
    429: "Brave Up",
    430: "Face Up",
    431: "HP Restore",
    432: "MP Restore",
    433: "Critical Quick",
    434: "Meatbone Slash",
    435: "Counter Magic",
    436: "Counter Tackle",
    437: "Counter Flood",
    438: "Absorb Used MP",
    439: "Gilgame Heart",
    440: "Reflect",
    441: "Auto Potion",
    442: "Counter",
    443: "",
    444: "Distribute",
    445: "MP Switch",
    446: "Damage Split",
    447: "Weapon Guard",
    448: "Finger Guard",
    449: "Abandon",
    450: "Catch",
    451: "Blade Grasp",
    452: "Arrow Guard",
    453: "Hamedo",
    454: "Equip Armor",
    455: "Equip Shield",
    456: "Equip Sword",
    457: "Equip Knife",
    458: "Equip Crossbow",
    459: "Equip Spear",
    460: "Equip Axe",
    461: "Equip Gun",
    462: "Half of MP",
    463: "Gained Jp UP",
    464: "Gained Exp UP",
    465: "Attack UP",
    466: "Defense UP",
    467: "Magic AttackUP",
    468: "Magic DefendUP",
    469: "Concentrate",
    470: "Train",
    471: "Secret Hunt",
    472: "Martial Arts",
    473: "Monster Talk",
    474: "Throw Item",
    475: "Maintenance",
    476: "Two Hands",
    477: "Two Swords",
    478: "Monster Skill",
    479: "Defend",
    480: "Equip Change",
    481: "",
    482: "Short Charge",
    483: "Non-charge",
    484: "",
    485: "",
    486: "Move+1",
    487: "Move+2",
    488: "Move+3",
    489: "Jump+1",
    490: "Jump+2",
    491: "Jump+3",
    492: "Ignore Height",
    493: "Move-HP Up",
    494: "Move-MP Up",
    495: "Move-Get Exp",
    496: "Move-Get Jp",
    497: "(Cannot enter water)",
    498: "Teleport",
    499: "Teleport 2",
    500: "Any Weather",
    501: "Any Ground",
    502: "Move in Water (Walk*)",
    503: "Walk on Water (Move*)",
    504: "Move on Lava",
    505: "Move Underwater",
    506: "Float",
    507: "Fly",
    508: "Silent Walk",
    509: "Move-Find Item",
    510: "",
    511: "",
    512: "",
}

# Skill set names (extracted from FFTPatcher SkillSets.xml)
SKILLSET_NAMES = {
    0x01: "Attack",
    0x02: "Defend",
    0x03: "Equip Change",
    0x05: "Basic Skill",
    0x06: "Item",
    0x07: "Battle Skill",
    0x08: "Charge",
    0x09: "Punch Art",
    0x0A: "White Magic",
    0x0B: "Black Magic",
    0x0C: "Time Magic",
    0x0D: "Summon Magic",
    0x0E: "Steal",
    0x0F: "Talk Skill",
    0x10: "Yin Yang Magic",
    0x11: "Elemental",
    0x12: "Jump",
    0x13: "Draw Out",
    0x14: "Throw",
    0x15: "Math Skill",
    0x16: "Sing",
    0x17: "Dance",
    0x18: "Mimic",
    0x19: "Guts",
    0x1A: "Guts",
    0x1B: "Guts",
    0x1C: "Guts",
    0x1D: "Holy Sword",
    0x1E: "Mighty Sword",
    0x1F: "Basic Skill",
    0x20: "Dark Sword",
    0x21: "Holy Sword",
    0x22: "Holy Sword",
    0x23: "Magic",
    0x24: "Holy Magic",
    0x25: "Snipe",
    0x26: "Snipe",
    0x27: "Dark Sword",
    0x28: "Holy Sword",
    0x29: "Limit",
    0x2A: "White-aid",
    0x2B: "Dragon",
    0x2C: "Breath",
    0x2D: "Truth",
    0x2E: "Un-truth",
    0x2F: "Starry Heaven",
    0x30: "Holy Sword",
    0x31: "Holy Magic",
    0x32: "Truth",
    0x33: "Battle Skill",
    0x34: "Jump",
    0x35: "Punch Skill",
    0x36: "Use Hand",
    0x37: "Use Hand",
    0x38: "Throw",
    0x39: "Throw",
    0x3A: "Holy Sword",
    0x3B: "Sword Spirit",
    0x3C: "Mighty Sword",
    0x3D: "All Magic",
    0x3E: "Sword Spirit",
    0x3F: "Blood Suck",
    0x40: "Mighty Sword",
    0x41: "All Magic",
    0x42: "Mighty Sword",
    0x43: "Mighty Sword",
    0x44: "Snipe",
    0x45: "Magic Sword",
    0x46: "Sword Skill",
    0x47: "All Magic",
    0x48: "All Magic",
    0x49: "Phantom",
    0x4A: "All Swordskill",
    0x4B: "Destroy Sword",
    0x4C: "Holy Magic",
    0x67: "Fear",
    0x68: "Warlock Summon",
    0x6B: "Fear",
    0x6C: "Ja Magic",
    0x6F: "Fear",
    0x70: "Dimension Magic",
    0x73: "Fear",
    0x74: "Impure",
    0x77: "Fear",
    0x78: "All Magic",
    0x7B: "Ultimate Magic",
    0x7C: "Chaos",
    0x7D: "Complete Magic",
    0x7E: "Saturation",
    0x9B: "Sword Skill",
    0x9C: "Charge",
    0x9D: "Black Magic",
    0x9E: "Time Magic",
    0x9F: "Yin Yang Magic",
    0xA0: "Summon Magic",
    0xA1: "Item",
    0xA2: "White Magic",
    0xA3: "Black Magic",
    0xA4: "Yin Yang Magic",
    0xAA: "Byblos",
    0xAB: "Work",
    0xAC: "Bio",
    0xAD: "Dark Cloud",
    0xAE: "Dark Magic",
    0xAF: "Night Magic",
    0xB0: "Chocobo",
    0xB1: "Black Chocobo",
    0xB2: "Red Chocobo",
    0xB3: "Goblin",
    0xB4: "Black Goblin",
    0xB5: "Gobbledeguck",
    0xB6: "Bomb",
    0xB7: "Grenade",
    0xB8: "Explosive",
    0xB9: "Red Panther",
    0xBA: "Cuar",
    0xBB: "Vampire",
    0xBC: "Pisco Demon",
    0xBD: "Squidlarkin",
    0xBE: "Mindflare",
    0xBF: "Skeleton",
    0xC0: "Bone Snatch",
    0xC1: "Living Bone",
    0xC2: "Ghoul",
    0xC3: "Ghost",
    0xC4: "Revenant",
    0xC5: "Flotiball",
    0xC6: "Ahriman",
    0xC7: "Plague",
    0xC8: "Juravis",
    0xC9: "Steel Hawk",
    0xCA: "Cockatoris",
    0xCB: "Uribo",
    0xCC: "Porky",
    0xCD: "Wildbow",
    0xCE: "Woodman",
    0xCF: "Trent",
    0xD0: "Taiju",
    0xD1: "Bull Demon",
    0xD2: "Minitaurus",
    0xD3: "Sacred",
    0xD4: "Morbol",
    0xD5: "Ochu",
    0xD6: "Great Morbol",
    0xD7: "Behemoth",
    0xD8: "King Behemoth",
    0xD9: "Dark Behemoth",
    0xDA: "Dragon",
    0xDB: "Blue Dragon",
    0xDC: "Red Dragon",
    0xDD: "Hyudra",
    0xDE: "Hydra",
    0xDF: "Tiamat",
}

# Ability types
ABILITY_TYPES = [
    "Blank", "Normal", "Item", "Throwing", "Jumping", "Charging",
    "Arithmetick", "Reaction", "Support", "Movement",
    "Unknown1", "Unknown2", "Unknown3", "Unknown4", "Unknown5", "Unknown6"
]


def parse_abilities(data: bytes) -> list:
    """Parse abilities from binary data."""
    abilities = []

    for i in range(512):
        # First part: 8 bytes at offset i*8
        offset = i * 8
        first = data[offset:offset + 8]

        jp_cost = struct.unpack_from("<H", first, 0)[0]
        learn_rate = first[2]
        flags = first[3]

        # Parse flags
        learn_with_jp = not (flags & 0x80)  # Inverted
        display_name = bool(flags & 0x40)
        learn_on_hit = bool(flags & 0x20)
        ability_type_val = flags & 0x0F
        ability_type = ABILITY_TYPES[ability_type_val] if ability_type_val < len(ABILITY_TYPES) else f"Unknown{ability_type_val}"

        # Determine category based on offset
        if i <= 0x16F:
            category = "normal"
        elif i <= 0x17D:
            category = "item"
        elif i <= 0x189:
            category = "throwing"
        elif i <= 0x195:
            category = "jumping"
        elif i <= 0x19D:
            category = "charging"
        elif i <= 0x1A5:
            category = "arithmetick"
        elif i >= 0x1A6 and i <= 0x1C5:
            # Reactions (422-453), Support (454-485), Movement (486-511 approx)
            if i <= 453:
                category = "reaction"
            elif i <= 485:
                category = "support"
            else:
                category = "movement"
        else:
            category = "other"

        name = ABILITY_NAMES.get(i, f"Ability_{i:03X}")

        abilities.append({
            "id": i,
            "name": name,
            "jp_cost": jp_cost,
            "learn_rate": learn_rate,
            "learn_with_jp": learn_with_jp,
            "learn_on_hit": learn_on_hit,
            "ability_type": ability_type,
            "category": category
        })

    return abilities


def parse_skill_sets(data: bytes, ability_names: dict) -> list:
    """Parse skill sets from binary data.

    Each skill set is 25 bytes:
    - Bytes 0-1: Action flags (16 bits, 1 = ability ID > 0xFF)
    - Byte 2: TheRest flags (6 bits used)
    - Bytes 3-18: 16 Action ability IDs (low byte)
    - Bytes 19-24: 6 TheRest ability IDs (RSM abilities)
    """
    skill_sets = []

    num_sets = len(data) // 25  # 176 for PSX

    for i in range(num_sets):
        offset = i * 25
        ss_data = data[offset:offset + 25]

        # Parse action flags
        action_flags = struct.unpack_from("<H", ss_data, 0)[0]
        rest_flags = ss_data[2]

        # Parse action abilities (16 abilities)
        actions = []
        for j in range(16):
            ability_low = ss_data[3 + j]
            is_high = (action_flags >> (15 - j)) & 1
            ability_id = ability_low + (0x100 if is_high else 0)
            if ability_id > 0:  # Skip empty slots
                actions.append({
                    "id": ability_id,
                    "name": ability_names.get(ability_id, f"Ability_{ability_id:03X}")
                })

        # Parse RSM abilities (Reaction, Support, Movement - 6 abilities)
        rsm = []
        for j in range(6):
            ability_low = ss_data[19 + j]
            is_high = (rest_flags >> (7 - j)) & 1
            ability_id = ability_low + (0x100 if is_high else 0)
            if ability_id > 0:  # Skip empty slots
                rsm.append({
                    "id": ability_id,
                    "name": ability_names.get(ability_id, f"Ability_{ability_id:03X}")
                })

        name = SKILLSET_NAMES.get(i, f"SkillSet_{i:02X}")

        skill_sets.append({
            "id": i,
            "name": name,
            "actions": actions,
            "rsm": rsm  # Reaction/Support/Movement abilities
        })

    return skill_sets


def main():
    print("Extracting ability data from SCUS_942.21...")

    # Load binary data from SCUS file
    with open(SCUS_FILE, "rb") as f:
        f.seek(ABILITIES_OFFSET)
        abilities_data = f.read(ABILITIES_SIZE)
        f.seek(SKILLSETS_OFFSET)
        skillsets_data = f.read(SKILLSETS_SIZE)

    print(f"  Read {len(abilities_data)} bytes of ability data")
    print(f"  Read {len(skillsets_data)} bytes of skill set data")

    # Parse abilities
    abilities = parse_abilities(abilities_data)
    print(f"  Parsed {len(abilities)} abilities")

    # Parse skill sets
    skill_sets = parse_skill_sets(skillsets_data, ABILITY_NAMES)
    print(f"  Parsed {len(skill_sets)} skill sets")

    # Create output directory
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Save abilities
    abilities_output = {
        "description": "FFT ability data extracted from SCUS_942.21",
        "source": SCUS_FILE.name,
        "abilities": {str(a["id"]): a for a in abilities}
    }
    with open(OUTPUT_DIR / "abilities.json", "w") as f:
        json.dump(abilities_output, f, indent=2)
    print(f"  Saved abilities to {OUTPUT_DIR / 'abilities.json'}")

    # Save skill sets
    skillsets_output = {
        "description": "FFT skill set data extracted from SCUS_942.21",
        "source": SCUS_FILE.name,
        "skill_sets": {str(ss["id"]): ss for ss in skill_sets}
    }
    with open(OUTPUT_DIR / "skill_sets.json", "w") as f:
        json.dump(skillsets_output, f, indent=2)
    print(f"  Saved skill sets to {OUTPUT_DIR / 'skill_sets.json'}")

    # Print summary of generic job skill sets
    print("\n=== Generic Job Skill Sets ===")
    # Skill set IDs for generic jobs (from Jobs.xml data)
    generic_skillsets = {
        "05": "Basic Skill (Squire)",
        "06": "Item (Chemist)",
        "07": "Battle Skill (Knight)",
        "08": "Charge (Archer)",
        "09": "Punch Art (Monk)",
        "0a": "White Magic",
        "0b": "Black Magic",
        "0c": "Time Magic",
        "0d": "Summon Magic",
        "0e": "Steal (Thief)",
        "0f": "Talk Skill (Orator)",
        "10": "Yin Yang Magic (Mystic)",
        "11": "Elemental (Geomancer)",
        "12": "Jump (Dragoon)",
        "13": "Draw Out (Samurai)",
        "14": "Throw (Ninja)",
        "15": "Math Skill (Arithmetician)",
        "16": "Sing (Bard)",
        "17": "Dance (Dancer)",
        "18": "Mimic (Mime)"
    }

    for ss_id_hex, desc in generic_skillsets.items():
        ss_id = int(ss_id_hex, 16)
        ss = skill_sets[ss_id] if ss_id < len(skill_sets) else None
        if ss:
            action_count = len(ss["actions"])
            rsm_count = len(ss["rsm"])
            print(f"  0x{ss_id:02X} {desc}: {action_count} actions, {rsm_count} RSM")


if __name__ == "__main__":
    main()
