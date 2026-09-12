extends RefCounted
## The five ability slots, and the ability class each R/S/M slot's candidates must
## match — a FIXED VOCABULARY and its projection.
##
## Extracted from `AbilityLoadout` (#1059 phase 3) for the reason `items/EquipSlot.gd`
## carries in full: `abilities/AbilityCandidates.gd` reads both names and stays in this
## addon, and had `AbilityLoadout` left for the Character Catalogue, leaving them inline
## would have turned that read into a catalogue reach and inverted this addon's own
## declared dependency edge.
##
## 🔴 THAT MOVE IS NOW REJECTED (ADR-0300) AND THE EXTRACTION STILL STANDS. The
## anticipated-boundary half of the reason expired; the half below did not, and it is
## the one that was always load-bearing: a private another file reads is a published
## member nobody declared, which is true wherever either file lives.
##
## 🔴 `SLOT_TYPE` IS PUBLISHED HERE, AND IT WAS NOT PUBLISHED BEFORE. It lived as
## `AbilityLoadout._SLOT_TYPE` and `AbilityCandidates.gd:58,60` read it across a file
## boundary THROUGH THE LEADING UNDERSCORE. A private that another file reads is a
## published member nobody declared; relocating it under the same name would have
## carried that in and left the register describing a surface one member short.
##
## `table` in this addon's kind register.

const AbilityType = preload("res://addons/exmateria_almanac/abilities/AbilityType.gd")

enum Slot { PRIMARY, SECONDARY, REACTION, SUPPORT, MOVEMENT }

## The R/S/M slot → the ability class its candidates must match. The ROM gates
## candidates by hardcoded id-ranges (ABILITY_PICKER.md §3); those ranges match
## abilities.json `ability_type` exactly, so we classify asset-side.
const SLOT_TYPE := {
	Slot.REACTION: AbilityType.Type.REACTION,
	Slot.SUPPORT: AbilityType.Type.SUPPORT,
	Slot.MOVEMENT: AbilityType.Type.MOVEMENT,
}
