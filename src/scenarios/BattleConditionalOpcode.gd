# THIS FILE IS GENERATED -- DO NOT EDIT.
# Source of truth: assets/scenarios/battle_conditional_opcodes.json
# Regenerate: uv run python tools/gen_opcode_catalog.py
#
# Dispatch key for the BattleConditionals mini-ISA (ADR-0059). The member
# name is the Option-A slug of the catalog display name; the underlying
# int value IS the 2-byte opcode. Reference members by name
# (BattleConditionalOpcode.RUN_SCENARIO), never by a literal opcode. The
# ScenarioDirector reads each requirement's operands through the shared
# EventInstructionArgs reader (BattleConditionalSet.args).
class_name BattleConditionalOpcode
extends RefCounted

enum {
	VARIABLE_EQ = 0x0001,
	VARIABLE_GE = 0x0002,
	VARIABLE_LE = 0x0003,
	UNIT_PRESENT = 0x0004,
	HP_GE = 0x0005,
	HP_LE = 0x0006,
	HP_0X0007 = 0x0007,
	HP_0X0008 = 0x0008,
	MP_GE = 0x0009,
	MP_LE = 0x000A,
	ACTIVE_TURN = 0x000B,
	MAIN_CHARACTER_EQUIP = 0x000D,
	GIL_GE = 0x000E,
	GIL_LE = 0x000F,
	DATE_GE = 0x0010,
	DATE_LE = 0x0011,
	CASUALTIES_GE = 0x0012,
	CASUALTIES_LE = 0x0013,
	VICTORY = 0x0016,
	UNIT_LOCATION = 0x0018,
	RUN_SCENARIO = 0x0019,
	TEAM_UNIT_LOCATION = 0x0025,
}
