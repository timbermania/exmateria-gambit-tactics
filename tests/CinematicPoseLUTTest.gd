extends Node
## CinematicPoseLUT fixture test (ADR-0053). Re-reads the 40 BATTLE.BIN
## halfwords at file offset 0x10dc (RAM 0x800680dc..0x8006812b) and asserts
## byte-equality with the baked PackedInt32Array constants in
## CinematicPoseLUT.gd. This is the transcription regression-proof: if
## the BATTLE.BIN bytes ever change, or the manual transcription drifts,
## this test fails.
##
## SKIP (not FAIL) if BATTLE.BIN isn't on this machine — project-assets/
## is local-only / gitignored per SETUP.md, and bots / fresh clones won't
## have it. The compile-time check that the constants parse is still a
## meaningful PASS in that environment.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const CinematicPoseLUT = ExMateriaSpriteRig.CinematicPoseLUT

const BATTLE_BIN_REL := "project-assets/fft-extract/BATTLE.BIN"
const LUT_FILE_OFFSET := 0x10dc  # RAM 0x800680dc - BATTLE.BIN base 0x80067000


func _ready() -> void:
	var failed := false

	# Pre-flight: the constants exist and have the documented shapes.
	failed = _expect(CinematicPoseLUT.SUB_A_FRAME_BASE.size() == 16, "SUB_A_FRAME_BASE has 16 entries (pose_octant 0..15)", failed)
	failed = _expect(CinematicPoseLUT.SUB_B_MIRROR.size() == 16, "SUB_B_MIRROR has 16 entries", failed)
	failed = _expect(CinematicPoseLUT.SUB_E_CARDINAL_OFFSET.size() == 4, "SUB_E_CARDINAL_OFFSET has 4 entries (cardinal_idx 0..3)", failed)
	failed = _expect(CinematicPoseLUT.SUB_F_CARDINAL_MIRROR.size() == 4, "SUB_F_CARDINAL_MIRROR has 4 entries", failed)

	# Read the 40 halfwords from BATTLE.BIN if available.
	var repo_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	# godot-learning/ is one level under the repo root.
	var battle_bin_path := repo_root.get_base_dir() + "/" + BATTLE_BIN_REL
	var f := FileAccess.open(battle_bin_path, FileAccess.READ)
	if f == null:
		print("[SKIP] CinematicPoseLUT byte-equality: BATTLE.BIN not found at %s (project-assets/ is local-only)" % battle_bin_path)
		if failed:
			print("[FAIL] CinematicPoseLUT: shape checks failed")
		else:
			print("[PASS] CinematicPoseLUT: shape OK (byte-equality skipped — no BATTLE.BIN)")
		get_tree().quit()
		return

	f.seek(LUT_FILE_OFFSET)
	var raw := f.get_buffer(80)  # 40 halfwords * 2 bytes
	f.close()
	failed = _expect(raw.size() == 80, "read 80 bytes from BATTLE.BIN @ 0x%x" % LUT_FILE_OFFSET, failed)

	var halfwords: Array[int] = []
	for i in range(40):
		halfwords.append(int(raw[i * 2]) | (int(raw[i * 2 + 1]) << 8))

	# Sub-table layout (see SPRITE_PIPELINE_INVESTIGATION.md "Two indexing-base
	# conventions"):
	#   F (cardinal mirror)         : idx 0..3   (sp base + 0x18)
	#   E (cardinal frame_offset)   : idx 4..7   (sp base + 0x20)
	#   B (pose-octant mirror)      : idx 8..23  (sp+0x10 base + 0x18)
	#   A (pose-octant frame_base)  : idx 24..39 (sp+0x10 base + 0x38)
	var rom_sub_f := halfwords.slice(0, 4)
	var rom_sub_e := halfwords.slice(4, 8)
	var rom_sub_b := halfwords.slice(8, 24)
	var rom_sub_a := halfwords.slice(24, 40)

	failed = _expect(_arrays_equal(rom_sub_a, CinematicPoseLUT.SUB_A_FRAME_BASE),
		"SUB_A_FRAME_BASE matches BATTLE.BIN bytes (ROM=%s, baked=%s)" % [rom_sub_a, CinematicPoseLUT.SUB_A_FRAME_BASE], failed)
	failed = _expect(_arrays_equal(rom_sub_b, CinematicPoseLUT.SUB_B_MIRROR),
		"SUB_B_MIRROR matches BATTLE.BIN bytes (ROM=%s, baked=%s)" % [rom_sub_b, CinematicPoseLUT.SUB_B_MIRROR], failed)
	failed = _expect(_arrays_equal(rom_sub_e, CinematicPoseLUT.SUB_E_CARDINAL_OFFSET),
		"SUB_E_CARDINAL_OFFSET matches BATTLE.BIN bytes (ROM=%s, baked=%s)" % [rom_sub_e, CinematicPoseLUT.SUB_E_CARDINAL_OFFSET], failed)
	failed = _expect(_arrays_equal(rom_sub_f, CinematicPoseLUT.SUB_F_CARDINAL_MIRROR),
		"SUB_F_CARDINAL_MIRROR matches BATTLE.BIN bytes (ROM=%s, baked=%s)" % [rom_sub_f, CinematicPoseLUT.SUB_F_CARDINAL_MIRROR], failed)

	if failed:
		print("[FAIL] CinematicPoseLUT: byte-equality check failed")
	else:
		print("[PASS] CinematicPoseLUT: 4 sub-tables match BATTLE.BIN @ 0x%x" % LUT_FILE_OFFSET)
	get_tree().quit()


func _arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


func _expect(cond: bool, label: String, failed_so_far: bool) -> bool:
	if not cond:
		print("[FAIL] %s" % label)
		return true
	return failed_so_far
