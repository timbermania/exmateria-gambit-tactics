extends Node

## FormationScene RIGHT unit-info panel guard (#176, §14.6) — pure GDScript, no GPU.
##
## The panel itself (frame + orb bullet + zodiac + text) is assembled from shared UI
## primitives and verified headful against the oracle; here we lock the two things a
## silent edit could regress:
##   1. info_view_from_character() — the roster-Character -> panel view dict
##      (number / name / job / brave / faith / zodiac; OUR data, faithfulness rule).
##   2. The oracle-measured placement constants (§14.6 absolute 256x240 coords) and
##      the ADR-0077 depth-ladder order (frame behind < bullet < text, all in front
##      of the band).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase
const UnitProgression = ExMateriaAlmanac.UnitProgression


const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")
const Character = ExMateriaCatalogue.Character
func _ready() -> void:
	var failed := false

	# --- 1. view mapping -------------------------------------------------------
	var c: Character = Character.create_default("Ramza", "4a", false)
	var prog = c.progression
	prog.brave = 70
	prog.faith = 70
	prog.zodiac = UnitProgression.Zodiac.CAPRICORN   # oracle: Ramza shows Capricorn
	var view: Dictionary = FormationScene.info_view_from_character(c, 1)

	if int(view["number"]) != 1:
		print("[FAIL] number: %s (want 1 = roster slot)" % view["number"]); failed = true
	if view["name"] != "Ramza":
		print("[FAIL] name: %s" % view["name"]); failed = true
	var job: Dictionary = JobDatabase.get_job("4a")
	if view["job"] != job.get("name", "4a"):
		print("[FAIL] job name: %s (want %s)" % [view["job"], job.get("name", "4a")]); failed = true
	if int(view["brave"]) != 70 or int(view["faith"]) != 70:
		print("[FAIL] brave/faith: %s/%s" % [view["brave"], view["faith"]]); failed = true
	if int(view["zodiac"]) != UnitProgression.Zodiac.CAPRICORN:
		print("[FAIL] zodiac: %s (want CAPRICORN=%d)" %
			[view["zodiac"], UnitProgression.Zodiac.CAPRICORN]); failed = true

	# --- 2. depth-ladder order (ADR-0077) --------------------------------------
	# The panel's opaque pieces must occlude the folded band (RP_BACKGROUND) and
	# stack near->far: frame behind < bullet/zodiac < text in front.
	if not (FormationScene.RP_INFO_FRAME > FormationScene.RP_BACKGROUND
			and FormationScene.RP_INFO_FRAME < FormationScene.RP_INFO_BULLET
			and FormationScene.RP_INFO_BULLET < FormationScene.RP_INFO_TEXT):
		print("[FAIL] rung order frame<bullet<text over band: %d/%d/%d (bg %d)" % [
			FormationScene.RP_INFO_FRAME, FormationScene.RP_INFO_BULLET,
			FormationScene.RP_INFO_TEXT, FormationScene.RP_BACKGROUND]); failed = true

	# --- 3. oracle-measured placement (§14.6) ----------------------------------
	# A detached instance (never enters the tree, so _ready is not called) exposes
	# the @export placement defaults. These are the byte-measured oracle coords.
	var scene = FormationScene.new()
	var want := {
		"info_name_px": Vector2(158, 183),
		"info_job_px": Vector2(158, 199),
		"info_number_px": Vector2(147, 183),
		"info_brave_label_px": Vector2(162, 216),
		"info_brave_value_px": Vector2(188, 216),
		"info_faith_label_px": Vector2(205, 216),
		"info_faith_value_px": Vector2(227, 216),
	}
	for prop in want:
		var got: Vector2 = scene.get(prop)
		if got != want[prop]:
			print("[FAIL] %s = %s (want %s per §14.6)" % [prop, got, want[prop]]); failed = true
	# The tan frame must span the oracle rect (134,176)-(248,230): origin + size.
	if scene.info_origin_px != Vector2(134, 176):
		print("[FAIL] info_origin_px = %s (want (134,176))" % scene.info_origin_px); failed = true
	if scene.info_frame_size_px.x < 108 or scene.info_frame_size_px.y < 48:
		print("[FAIL] info_frame_size_px too small: %s" % scene.info_frame_size_px); failed = true
	scene.free()

	# The Brave/Faith labels are WHOLE-WORD baked textures on the RANGETILE sheet
	# (§14.6.1), NOT FONT.BIN — the atlas must carry both word cells.
	var atlas := RangeTileAtlas.new()
	for w in ["Brave", "Faith"]:
		if not atlas.has_label(w):
			print("[FAIL] RANGETILE atlas missing baked word label '%s'" % w); failed = true
		elif atlas.label_rect(w).size == Vector2.ZERO:
			print("[FAIL] RANGETILE label_rect('%s') is empty" % w); failed = true

	# --- 4. vitals view carries the portrait folder (#205 portrait fix) ---------
	# vitals_view_from_character MUST thread the resolved template_folder so the
	# portrait fronts the unit's OWN sheet; the key omission made every unit show
	# the fallback job (Squire) face. The key must exist (folder for uniques, ""
	# for generics — UIPortraitFrame.display_from_template falls back on "").
	var vview: Dictionary = FormationScene.vitals_view_from_character(c)
	if not vview.has("template_folder"):
		print("[FAIL] vitals view omits template_folder (portrait would fall back to job)"); failed = true

	# --- 5. hand-rolled glyph advance narrows SPACE (dialogue-box parity) --------
	# _mount_word_opaque advances by glyph_advance(): a space uses the ROM 4px
	# narrow advance (DialogueBox.SPACE_WIDTH_PX), NOT the full FONT.BIN cell width,
	# so names like "40 year old man" don't over-gap.
	var f := UIFont.new()   # fresh: char_width = 10 (the old, too-wide space advance)
	if FormationScene.glyph_advance(f, " ") != DialogueBox.SPACE_WIDTH_PX:
		print("[FAIL] glyph_advance(space) = %s (want %s)" %
			[FormationScene.glyph_advance(f, " "), DialogueBox.SPACE_WIDTH_PX]); failed = true
	if not (FormationScene.glyph_advance(f, " ") < FormationScene.glyph_advance(f, "A")):
		print("[FAIL] space advance (%s) not narrower than a glyph cell (%s)" %
			[FormationScene.glyph_advance(f, " "), FormationScene.glyph_advance(f, "A")]); failed = true

	if failed:
		print("[FAIL] FormationInfoPanelView test")
	else:
		print("[PASS] FormationInfoPanelView: view mapping + §14.6 placement + ADR-0077 order")
	get_tree().quit()
