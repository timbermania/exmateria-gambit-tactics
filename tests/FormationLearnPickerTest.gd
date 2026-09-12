extends Node3D
# test-kind: logic
# seeded-break: UnitProgression.learn_ability_from_job learns but never spends (job_jp[job_id] = available_jp instead of available_jp - jp_cost); 'the commit should spend exactly the JP cost (leaving 5)' + 'the cancel must not change the progression' RED; the full-catalogue picker (80 rows, headers/columns/scroll), the two-panel lockstep open, the four-tab partition + per-tab cursor, the unaffordable buzz, the Learned flip, the list-stays-open, and the close-walk asserts stay green; GREEN unbroken on the reverted tree

## The "Learn" flow of the formation ability sub-screen (LEARN_PICKER.md) — a headful
## integration guard, the sibling of FormationAbilityPickerTest's "Set" flow. From the
## settled Ability sub-screen, choosing "Learn" (row 2) opens the JOB PICKER over the full job
## CATALOGUE — the ADR-0197 full-catalog scaffold now applies to the Learn picker too, so the
## list is populated to its max (80 jobs, generic + special + monster) instead of the ~13 the
## seed unlocks. The unit's GATED unlocked set must remain a strict SUBSET of it, which is what
## slice 1 asserts; the commit slices then drive the real ui_down path to a job BY ID, since
## catalogue row indices are name-sorted and no longer track the generic id order:
##   (1) the picker opens over the ROM's OWN panel rect Rect2(29,30,203,193) with the full job
##       CATALOGUE (JobCandidates.build_catalog — every job carrying a learnable, 80 rows,
##       name-sorted with the job index as tie-break) as a >11-row scrolling list; the press
##       hides the list-menu AND every DetailScene panel while the vitals band fades out with
##       the aperture; the five column headers are baked frame.tga word cells (Job / Lv. /
##       Total / Next / Jp) under CLUT 0x7CBC; and each row is the job name plus its four
##       number columns (LEARN_PICKER.md round 10 — the spec, superseding §12);
##   (2) ○ on a job opens **Learn phase 1**, the ABILITY LIST ([LearnAbilityMenu], ROM
##       `FUN_8011F5F0`) — it does NOT commit. Until 2026-08-20 this press was a stub that
##       auto-resolved the job's first unlearned ability and charged it; slices 2–5 are the
##       real screen, and `research/working_documents/LEARN_ABILITY_LIST.md` is their spec;
##   (3) the list's TWO panels open in LOCKSTEP off one stage counter (§3.4), each scaling
##       `floor(w·p) × floor(h·p)` — integer floor, both axes (LEARN_PICKER.md §21);
##   (4) the four ability-TYPE tabs partition by the ROM's own id ranges (§8), LEFT/RIGHT
##       step them keeping a per-tab cursor (§9), non-ACTION rows draw the dash squiggle
##       instead of Mp/Speed digits (§14.3), and the enabled/disabled ramps are the two
##       mechanisms of §7 resolved onto one measured colour triple;
##   (5) ○ is three-way (§9): unaffordable buzzes, already-learned does nothing, otherwise it
##       spends the JP and the row flips to `Learned` — with the list STAYING OPEN, because
##       the ROM rebuilds its candidate list rather than exiting;
##   (6) × on the list returns to the JOB PICKER (§13.5 — not out of the screen), which
##       replays its own aperture on the row the player left; × again closes back to the
##       ability list-menu with no change.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const JobCandidates = ExMateriaAlmanac.JobCandidates
const JobDatabase = ExMateriaAlmanac.JobDatabase
const JobLevelsDatabase = ExMateriaAlmanac.JobLevelsDatabase


const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const BoxOpenAnimator = preload("res://src/ui3/detail/BoxOpenAnimator.gd")

var _failed := false

## The EXACT set of generic jobs the seed below unlocks — derived independently from the
## `prerequisites` table in addons/exmateria_almanac/jobs/job_levels.json against the seed
## {4a:2, 4b:2, 4c:2, 4d:2, 4e:3, 4f:2, 50:2, 51:2, 53:3}: 4a/4b have none; 4c/4d need Squire
## Lv2; 4e needs Squire+Knight Lv2; 4f/50 need Chemist Lv2; 51 needs Chemist+Monk Lv2; 52 needs
## Chemist+Monk+Priest Lv2; 53 needs Squire+Archer Lv2; 55 needs Chemist+Thief Lv2; 56 needs
## Squire+Knight Lv2 + Wizard Lv3; 57 needs Squire+Archer Lv2 + Geomancer Lv3. Every other job
## needs a level the seed lacks (54 wants Oracle Lv2; 58/59/5a/5b/5c/5d want Lv3+/Lv4+ in jobs
## the seed leaves at Lv2 or 0). Order = ascending generic id (0x4a..0x5d).
##
## THIRTEEN entries. This is no longer what the picker LISTS (the catalogue is) — it is
## retained as the SUBSET ORACLE: every job the gate would have shown must still be reachable
## in the catalogue. That keeps the gated derivation above under test and proves the scaffold
## only ever ADDS rows. The ROM's own case is 18 candidates against those ~11 rows.
const EXPECTED_UNLOCKED := ["4a", "4b", "4c", "4d", "4e", "4f", "50", "51", "52", "53",
	"55", "56", "57"]


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


func _action(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	# #1273 — the screen now STATES `input_refused` and the host names the buzz. This
	# test builds its own screen instead of going through `mount_over_map`, so it wires
	# it the same way `NavigatorMain` and `GPUArena` do, and the buzz asserts below keep
	# measuring the CUE rather than the signal.
	UIWiring.wire_formation_screen(host)
	for _i in 4:
		await get_tree().process_frame

	var form = host._formation
	_expect(form != null and form.selected_character() != null, "no formation/selection")
	if form == null or form.selected_character() == null:
		_finish()
		return
	var sel = form.selected_character()

	# Seed the unit: those job levels unlock EXACTLY EXPECTED_UNLOCKED (13 jobs — two more than
	# the picker's 11 visible rows, so the scroll window is still exercised), with zero JP and
	# no learned abilities, so the first commit press is a JP-fail.
	sel.progression.current_job_id = "4a"
	sel.progression.job_levels = {"4a": 2, "4b": 2, "4c": 2, "4d": 2, "4e": 3, "4f": 2,
		"50": 2, "51": 2, "53": 3}
	sel.progression.learned_abilities = {}
	sel.progression.job_jp = {}
	sel.progression.job_jp_total = {}

	# Open detail → action menu → choose "Ability" (row 1) → the Ability slide.
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	_expect(d != null, "○ did not open the detail overlay")
	host.open_action_menu()
	host.action_menu().move_down()          # row 0 (Item) -> row 1 (Ability)
	host.action_menu().confirm()            # "Ability" -> the Ability slide begins
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	var menu = host.action_menu()
	if menu == null or d == null:
		_finish()
		return
	_expect(d.ability_only, "did not settle into the ability sub-screen")

	# --- Slice 1: "Learn" (row 2) opens the job picker of the unit's unlocked jobs. ---
	menu.move_down()                        # row 0 (Set) -> row 1 (Remove)
	menu.move_down()                        # row 1 (Remove) -> row 2 (Learn)
	menu.confirm()
	var jp = host.job_picker()
	_expect(jp != null and is_instance_valid(jp), "Learn did not open the job picker")
	if jp == null:
		_finish()
		return
	var ids: Array = _picker_ids(jp)
	# The picker lists the CATALOGUE, in the catalogue's own order — the one wiring seam.
	_expect(ids == _catalog_ids(),
		"picker should list the full job catalogue in catalogue order, got %d ids" % ids.size())
	_expect(jp.row_count() == 80 and jp.row_count() > JobPickerMenu.VISIBLE_ROWS,
		"the 80-job catalogue should overflow the %d-row window, got %d" % [
			JobPickerMenu.VISIBLE_ROWS, jp.row_count()])
	# The scaffold only ADDS: every job the progression gate would have shown is still here.
	var missing: Array = []
	for gated in EXPECTED_UNLOCKED:
		if not ids.has(gated):
			missing.append(gated)
	_expect(missing.is_empty(),
		"the catalogue must be a superset of the gated unlocked set, missing %s" % [missing])
	# ...and it adds the rows that are the POINT of the scaffold: jobs no gate would unlock.
	# 03 is the Squire whose skillset carries Ultima (9999 JP) — the character-specific job
	# index the gated generic list can never reach, and the reason the KEY is the job index.
	_expect(ids.has("03"), "the catalogue must include the special Squire 03 (its skillset carries Ultima)")
	_expect(ids.has("9a"), "the catalogue must include the monster job 9a (Ultima Demon)")
	_expect(not sel.progression.get_unlocked_jobs().has("03"),
		"job 03 must NOT be gate-unlocked — otherwise it proves nothing about the catalogue")
	# Rows still resolve their jobs.json name, and the six colliding "Squire" indices all made
	# it through as distinct rows (the collision the index disambiguates).
	var squires: Array = []
	for e in jp.entries:
		if String(e.get("name", "")) == "Squire":
			squires.append(String(e.get("id", "")))
	_expect(squires == ["01", "02", "03", "04", "07", "4a"],
		"all six Squire indices should be distinct rows in index order, got %s" % [squires])
	_expect(String(_entry_of(jp, "4a").get("name", "")) == "Squire",
		"job 4a should still read 'Squire' (jobs.json name), got '%s'" % String(_entry_of(jp, "4a").get("name", "")))
	# GEOMETRY: the picker window IS the ROM panel rect — x29..231 / y30..222. The top is the
	# panel's CHROME top (§9.2's framebuffer row profile: y30/y31 are full-width chrome rows
	# INSIDE the cream header row y27..33), not §11's y35, which is only where the bevel/fill
	# begins. Round 10 #1 authored y35, so the headers rendered 100% ABOVE the frame instead of
	# straddling its top edge. Bottom unchanged: 30 + 193 = 223 ⇒ y222.
	_expect(jp.window() != null and jp.window().rect() == Rect2(29, 30, 203, 193),
		"the picker window should be the ROM panel Rect2(29,30,203,193), got %s" % [
			jp.window().rect() if jp.window() != null else "<no window>"])
	# ...and the reason that top is right: STRIPE's 9px fixed top margin then covers y30..38,
	# so the tiled body starts at y39 — exactly §9.2's "y39+ panel fill" — leaving 5px of top
	# margin above row 0's text at y44. This ties the rect literal to the framebuffer profile,
	# so a future re-dial of either the rect or the 9-slice margins has to answer for it.
	_expect(jp.window() != null
			and is_equal_approx(jp.window().rect().position.y + UIFrame.STRIPE_MARGINS.z, 39.0),
		"the STRIPE top margin should land the panel fill on y39 (§9.2), got %f" % [
			jp.window().rect().position.y + UIFrame.STRIPE_MARGINS.z if jp.window() != null else -1.0])
	# TRANSITION (round 10 #2): the press hides the list-menu AND every DetailScene panel —
	# unit cluster, stats band, lower Eqp/Ability panel, compare panel, pager — while the
	# `detail.vitals_band` stripe and the 3D formation behind it stay (the ROM's window 0,
	# §4). Restored on cancel (slice 4).
	_expect(not menu.visible, "the Learn press should hide the ability list-menu")
	_expect(not d.panels_visible(),
		"the Learn press should hide every DetailScene panel (cluster + stats + lower + pager)")
	# BAND FADE (round 10 #3): the vitals stripe fades with the aperture walk through
	# DetailScene.band_crossfade's OUT-ramp, and is gone by the settle frame. Frame 0 has
	# already been driven by _ready's play_open, so the band still stands full here.
	_expect(is_equal_approx(d.vitals_band_factor(), 1.0),
		"at aperture frame 0 the vitals band should still be full, got %f" % d.vitals_band_factor())
	for _f in BoxOpenAnimator.settle_frame(false):
		UI3Registry.transition_engine_step()
	_expect(jp.window().is_settled(), "the picker box-open should have settled")
	_expect(is_equal_approx(d.vitals_band_factor(), 0.0),
		"the settled aperture should have cleared the vitals band, got %f" % d.vitals_band_factor())
	_expect(jp.row_decoration_materials().is_empty(), "job picker rows must be text-only")
	_expect(jp.visible_row_names().size() >= 1, "picker did not render any job name")
	# ROW COLUMNS (round 10 #5): every row is the job name PLUS Lv. / Total / Next / Jp under
	# their headers. Expected values are derived HERE from the data tables + the seeded
	# progression, never read back from the host. `Total` is the new lifetime-JP field;
	# `Lv.`/`Next`/`Jp` keep deriving from the spendable pool, so no behaviour changed.
	_expect(jp.visible_row_columns() == _expected_columns(sel, 0),
		"row columns should read Lv./Total/Next/Jp, got %s want %s" % [
			jp.visible_row_columns(), _expected_columns(sel, 0)])
	# LEADING ZEROES + the `/` (round 16, LEARN_PICKER.md §3.1). The ROM's s13 digit loop
	# draws every unused leading position as a literal `0` glyph in the SAME CLUT for record
	# type 0x0D, so the settled screen reads `I │ /0175 │ 0200 │ 0005`. Assert the shape
	# rather than a seeded value: Lv. is exactly 1 char, the other three exactly 4.
	for row_cols in jp.visible_row_columns():
		_expect(String(row_cols[0]).length() == 1,
			"Lv. is the ROM's maxd=1 column, got %s" % [row_cols[0]])
		for ci in [1, 2, 3]:
			_expect(String(row_cols[ci]).length() == 4,
				"Total/Next/Jp are maxd=4 zero-padded, got %s" % [row_cols[ci]])
	# The `/` chrome between Lv. and Total is a real mounted glyph, so every row spends
	# 1 + 4 + 4 + 4 digit cells PLUS one slash = 14 HUD glyphs. Counting them is what fails
	# if either the separator or the padding is dropped.
	_expect(jp.row_number_materials().size() == jp.visible_row_names().size() * 14,
		"each row should mount 13 digits + the `/` separator = 14 HUD glyphs, got %d for %d rows" % [
			jp.row_number_materials().size(), jp.visible_row_names().size()])
	# HEADERS (round 10 #4): five BAKED frame.tga word cells — Job / Lv. / Total / Next / Jp —
	# drawn through the cream CLUT 0x7CBC, NOT the round-7 port's UIMenuText-composed "JOB".
	# The rects are round 9's, read straight off the sheet; the screen x's are §9.2's live
	# framebuffer bboxes.
	_expect(jp.header_materials().is_empty(),
		"the round-7 FONT-composed 'JOB' header must be gone (headers are frame.tga cells now)")
	_expect(jp.header_cell_materials().size() == 5,
		"all five header cells should mount, got %d" % jp.header_cell_materials().size())
	_expect(jp.header_cells() == [Rect2i(22, 32, 17, 8), Rect2i(49, 48, 14, 8),
			Rect2i(0, 152, 22, 8), Rect2i(24, 152, 21, 8), Rect2i(228, 64, 12, 10)],
		"the header cells should be round 9's frame.tga rects, got %s" % [jp.header_cells()])
	_expect(jp.header_screen_x() == [38.0, 119.0, 143.0, 174.0, 208.0],
		"the headers should sit at the ROM's screen x's, got %s" % [jp.header_screen_x()])
	# The headers now STRADDLE the window top (y26..35 against a rect top of y30), so they are
	# only half-covered by the rect and the box-open would scissor the rest — `aperture_pad`
	# top must still enclose them. Guard the MECHANISM, not the literal (mirrors
	# AbilityPickerMenuTest): the settled aperture encloses the header element's rect.
	_expect(Rect2(jp.window().aperture()).encloses(jp.header_element_rect()),
		"the settled aperture %s must enclose the header row %s (needs aperture_pad top)" % [
			Rect2(jp.window().aperture()), jp.header_element_rect()])
	# ROW NUMBER FONT (defect 3.2): the four number columns are the SMALL HUD DIGIT font
	# (FRAMEFONT — §9.2's "small 6-px-wide quads", the set the nameplate draws Brave/Faith
	# with), NOT the FONT.BIN body text the job NAME uses. Two different fonts in one row, so
	# assert both: the names go through the FONT shader, the numbers through the index→CLUT
	# text shader. Round 10 mounted every column through UIMenuText.mount().
	_expect(not jp.row_number_materials().is_empty(),
		"the four number columns should mount HUD digit glyphs")
	for m in jp.row_number_materials():
		_expect(String(m.shader.resource_path).ends_with("formation_text_opaque.gdshader"),
			"number-column glyphs should render through the HUD digit shader, got %s" % [
				m.shader.resource_path])
	for m in jp.row_text_materials():
		_expect(String(m.shader.resource_path).ends_with("formation_font_opaque.gdshader"),
			"job-name glyphs should stay FONT.BIN body text, got %s" % [m.shader.resource_path])
	# ROW NUMBER ALIGNMENT (defect 3.3): the columns are CENTRED on their header cell's centre,
	# not right-aligned on its right edge + 1. §9.2's job-row glyph run is screen x123..224 and
	# centring reproduces BOTH ends — a 1-digit Lv. on 125.5 starts at x123, a 4-digit Jp on
	# 213.5 ends at x224. Round 10 #5's right-alignment predicts x128..220, refuted at both
	# ends of the very run it cited. These two assertions ARE that derivation.
	_expect(is_equal_approx(jp.number_ink_x("1", JobPickerMenu.LV_CENTER_X), 123.0),
		"a 1-digit Lv. centred on 125.5 should start §9.2's run at x123, got %f" % [
			jp.number_ink_x("1", JobPickerMenu.LV_CENTER_X)])
	_expect(is_equal_approx(jp.number_ink_x("1234", JobPickerMenu.JP_CENTER_X)
			+ jp.number_ink_width("1234"), 224.0),
		"a 4-digit Jp centred on 213.5 should end §9.2's run at x224, got %f" % [
			jp.number_ink_x("1234", JobPickerMenu.JP_CENTER_X) + jp.number_ink_width("1234")])
	# ...and now that the columns are FIXED-WIDTH, the centring must reproduce the template's
	# own base-x bytes (`0x8018D1A4` @0x77/@0x81/@0xBF/@0xC9 = 0x7B/0x8F/0xAD/0xCB), which is a
	# stronger pin than the framebuffer run: it is what the ROM record literally says.
	# NEXT_CENTER_X was 184.0 and landed on 174 — one pixel right of the ROM — until round 16.
	var base_x := [
		[jp.number_ink_x("1", JobPickerMenu.LV_CENTER_X), 123.0, "Lv."],
		[jp.number_ink_x("0000", JobPickerMenu.TOTAL_CENTER_X), 143.0, "Total"],
		[jp.number_ink_x("0000", JobPickerMenu.NEXT_CENTER_X), 173.0, "Next"],
		[jp.number_ink_x("0000", JobPickerMenu.JP_CENTER_X), 203.0, "Jp"],
	]
	for b in base_x:
		_expect(is_equal_approx(float(b[0]), float(b[1])),
			"%s should start on the template's base-x %d, got %f" % [b[2], int(b[1]), b[0]])
	# The 11-row window scrolls: 12 downs from row 0 offset it to scroll 2 (rows 2..12 up), and
	# the first visible name is catalogue index 2's — resolved from the catalogue rather than
	# named as a literal, since the name-sorted order no longer tracks the generic id order.
	for _n in 12:
		host._input(_action("ui_down"))
	_expect(jp.scroll() == 2,
		"12 downs from row 0 should offset the %d-row window to scroll 2, got %d" % [
			JobPickerMenu.VISIBLE_ROWS, jp.scroll()])
	var want_top: String = String(JobDatabase.get_job(String(_catalog_ids()[2])).get("name", ""))
	_expect(String(jp.visible_row_names().front()) == want_top,
		"after scrolling, the first visible row should be catalogue index 2 ('%s'), got %s" % [
			want_top, str(jp.visible_row_names().front())])
	for _n in 12:
		host._input(_action("ui_up"))
	_expect(jp.scroll() == 0, "driving back to row 0 should reset the scroll, got %d" % jp.scroll())
	# The catalogue is deep enough that the LAST row is only reachable by scrolling — drive the
	# real ui_down path all the way down and back, which the 13-row gated list never exercised.
	for _n in jp.row_count() - 1:
		host._input(_action("ui_down"))
	_expect(jp.selected_row() == jp.row_count() - 1,
		"driving down %d times should reach the last catalogue row, got %d" % [
			jp.row_count() - 1, jp.selected_row()])
	_expect(jp.scroll() == jp.row_count() - JobPickerMenu.VISIBLE_ROWS,
		"the window should bottom out at scroll %d, got %d" % [
			jp.row_count() - JobPickerMenu.VISIBLE_ROWS, jp.scroll()])
	_expect(jp.visible_row_columns() == _expected_columns(sel, jp.scroll()),
		"the bottomed-out window's columns should track the catalogue, got %s want %s" % [
			jp.visible_row_columns(), _expected_columns(sel, jp.scroll())])
	# Park on the SEEDED job by ID (not by row index): the commit slices below spend JP that is
	# seeded on 4a, and the catalogue's name-sort puts 4a nowhere near row 0.
	_drive_to_id(host, jp, "4a")
	_expect(String(jp.entries[jp.selected_row()].get("id", "")) == "4a",
		"the cursor should be parked on job 4a, got %s" % String(jp.entries[jp.selected_row()].get("id", "")))

	# --- Slice 2: ○ on the job picker opens the ABILITY LIST, it does NOT commit. ---
	# This is the whole point of LEARN_ABILITY_LIST.md: the old port stub auto-resolved the
	# job's first unlearned ability and charged it here. The ROM instead sets `DAT_801C854C = 1`
	# and starts calling FUN_8011F5F0 (§1), so the picker stops being emitted and the ability
	# list opens over the same torn-down screen. No SFX, no progression write.
	var cues: Array = []
	SfxRouter.cue_requested.connect(func(n: String, b: String, s: int) -> void:
		cues.append([n, b, s]))
	host._input(_action("ui_accept"))
	var ll = host.learn_ability_list()
	_expect(ll != null and is_instance_valid(ll), "○ on a job should open the Learn ability list")
	if ll == null:
		_finish()
		return
	_expect(host.job_picker() == null or not is_instance_valid(host.job_picker()),
		"the job picker must be gone once the ability list stands in its place")
	_expect(sel.progression.learned_abilities.is_empty(),
		"opening the ability list must not learn anything (the old stub committed here)")
	_expect(sel.progression.job_jp.is_empty(), "opening the ability list must not touch the JP pool")
	_expect(cues.is_empty(), "opening the ability list must not buzz, got %s" % [cues])
	_expect(not menu.visible and not d.panels_visible(),
		"the ability list stands on the same torn-down screen the picker did")

	# --- Slice 3: TWO panels, opening in LOCKSTEP off ONE stage counter. ---
	# The template carries exactly one `s22` record (§3.4), and §13.2 measured both panels at
	# the same scale in the same frame, on BOTH axes. Two windows on one clock is the port's
	# reproduction, so the guard samples both apertures per driven frame and requires them to
	# agree — a second cadence, a stray `open()`, or one panel settling early all break here.
	_expect(ll.top_window() != null and ll.bottom_window() != null, "both panels should exist")
	_expect(ll.top_window().rect() == LearnAbilityMenu.TOP_PANEL
			and ll.bottom_window().rect() == LearnAbilityMenu.BOTTOM_PANEL,
		"the panels should be the measured rects, got %s / %s" % [
			ll.top_window().rect(), ll.bottom_window().rect()])
	var ap_guard := 0
	var ap_frames := 0
	while not ll.bottom_window().is_settled() and ap_guard < 240:
		var at: Rect2i = ll.top_window().aperture()
		var ab: Rect2i = ll.bottom_window().aperture()
		# Same width every frame: both panels are 203 wide and share one scale ladder.
		_expect(at.size.x == ab.size.x,
			"the two panels must scale in lockstep — frame %d has widths %d / %d" % [
				ap_frames, at.size.x, ab.size.x])
		# ...and the scale applies on the HEIGHT axis too, by integer FLOOR — LEARN_PICKER.md
		# §21's one port-facing rule (`196·0.6 = 117.6 -> 117`, never 118). The oracle is the
		# CURVE at this frame, not the observed width: deriving the percent back out of a
		# floored width loses it (203·60% = 121, and 121·100/203 reads 59), which is a mistake
		# worth leaving named here because it makes correct code look off-by-two.
		var pct := BoxOpenAnimator.progress_percent(ap_frames, false)
		for w in [ll.top_window(), ll.bottom_window()]:
			var full: Vector2i = ll.top_window().padded_rect().size if w == ll.top_window() \
				else ll.bottom_window().padded_rect().size
			var want := Vector2i((full.x * pct) / 100, (full.y * pct) / 100)
			_expect(w.aperture().size == want,
				"panel %s should scale to floor(%s x %d%%) = %s at frame %d, got %s" % [
					w.spec().get("id", "?"), full, pct, want, ap_frames, w.aperture().size])
		UI3Registry.transition_engine_step()
		ap_frames += 1
		ap_guard += 1
	_expect(ap_frames >= 3, "the two-panel open should span several driven frames, got %d" % ap_frames)
	_expect(ll.top_window().is_settled() and ll.bottom_window().is_settled(),
		"both panels must settle together — top=%s bottom=%s" % [
			ll.top_window().is_settled(), ll.bottom_window().is_settled()])
	# The column headers STRADDLE each panel's top edge (y28 over a y31 rect, y73 over y76), so
	# the box-open's `aperture_pad` has to enclose them or the reveal scissors them off.
	for w in [ll.top_window(), ll.bottom_window()]:
		_expect(Rect2(w.aperture()).encloses(Rect2(w.padded_rect())),
			"the settled aperture must be the whole padded box for %s" % [w.spec().get("id", "?")])

	# --- Slice 4: the four TABS, the rows, and the two dim mechanisms. ---
	# Nine baked frame.tga header cells across both frames (Job/Lv./Total/Next/Jp +
	# Ability/Mp/Speed/Jp) and four ALWAYS-DRAWN tab icons — the template gates each icon on a
	# palette pick, not on visibility (§3.3), so all four mount and only the CLUT differs.
	_expect(ll.header_cell_materials().size() == 9,
		"nine header cells should mount across the two frames, got %d" % ll.header_cell_materials().size())
	_expect(ll.tab_icon_materials().size() == 4,
		"all four tab icons always draw (palette pick, not a visibility gate), got %d" % [
			ll.tab_icon_materials().size()])
	# The tab PARTITION is the ROM's own ability-id ranges (§8). Derive the oracle from the
	# database, never from the menu.
	var by_tab: Array = [[], [], [], []]
	for a in AbilityDatabase.get_learnable_abilities_for_job("4a"):
		var t := LearnAbilityMenu.tab_for_id(int(a.id))
		if t >= 0:
			(by_tab[t] as Array).append(String(a.name))
	for t in 4:
		var want: Array = by_tab[t]
		var got: Array = []
		for idx in ll.tab_entry_indices(t):
			got.append(String((ll.entries[int(idx)] as Dictionary).get("name", "")))
		_expect(got == want, "tab %d should list %s, got %s" % [t, want, got])
	# Tab 0 is the ACTION tab and the one the settled ROM capture shows (§13.1): Accumulate /
	# Dash / Throw Stone / Heal, with `Learned` on the two the seed already has and the grey
	# ramp on the two the unit cannot afford.
	_expect(ll.tab() == 0, "the list should boot on tab 0, got %d" % ll.tab())
	_expect(ll.visible_row_names() == by_tab[0],
		"tab 0 should render the action abilities, got %s" % [ll.visible_row_names()])
	_expect(ll.visible_row_columns() == _expected_ability_columns(sel, "4a", 0),
		"tab 0 columns should read Mp/Speed/Jp, got %s want %s" % [
			ll.visible_row_columns(), _expected_ability_columns(sel, "4a", 0)])
	_expect(ll.visible_row_dim() == _expected_ability_dim(sel, "4a", 0),
		"tab 0's dim flags should be (not learned and not affordable), got %s want %s" % [
			ll.visible_row_dim(), _expected_ability_dim(sel, "4a", 0)])
	# Both dim mechanisms hang off that ONE flag (§7), and the port paints them through the
	# ONE colour ramp the savestate says they share. Assert the identity rather than the
	# literals, so a re-dial of either constant has to keep them equal.
	_expect(LearnAbilityMenu.DIM_INKS != LearnAbilityMenu.LIT_INKS,
		"the disabled ramp must actually differ from the enabled one")
	for i in 3:
		_expect(LearnAbilityMenu.CLUT_7FA4[i + 1] == LearnAbilityMenu.DIM_INKS[i],
			"CLUT 0x7FA4[%d] (the disabled NUMBER palette) must equal DIM_INKS[%d] — the two ROM mechanisms share one ramp" % [i + 1, i])
	# RIGHT steps the tab (`FUN_8012BA7C` bit 0x2000, §9) and wraps 3 -> 0.
	for t in [1, 2, 3, 0]:
		host._input(_action("ui_right"))
		_expect(ll.tab() == t, "RIGHT should step to tab %d, got %d" % [t, ll.tab()])
	host._input(_action("ui_left"))
	_expect(ll.tab() == 3, "LEFT from tab 0 should wrap to tab 3, got %d" % ll.tab())
	# Every non-ACTION row draws the dash squiggle across the Mp AND Speed columns instead of
	# digits — structural, not incidental: those records have no MP/Speed field at all (§14.3).
	for t in [1, 2, 3]:
		while ll.tab() != t:
			host._input(_action("ui_right"))
		for row_cols in ll.visible_row_columns():
			_expect(String(row_cols[0]) == "-" and String(row_cols[1]) == "-",
				"tab %d rows must draw the dash cell, not digits — got %s" % [t, row_cols])
		_expect(ll.row_cell_materials().size() >= ll.visible_row_names().size(),
			"tab %d should mount one dash cell per row, got %d for %d rows" % [
				t, ll.row_cell_materials().size(), ll.visible_row_names().size()])
	# PER-TAB CURSOR (§9/§13.3): the ROM saves the outgoing tab's 6-byte record and restores
	# the incoming one, which is why its build block memsets exactly FOUR of them.
	while ll.tab() != 2:
		host._input(_action("ui_right"))
	host._input(_action("ui_down"))
	host._input(_action("ui_down"))
	var tab2_row := ll.selected_row()
	_expect(tab2_row == 2, "two downs on tab 2 should sit on row 2, got %d" % tab2_row)
	host._input(_action("ui_right"))
	_expect(ll.selected_row() == 0, "tab 3's own cursor should still be row 0, got %d" % ll.selected_row())
	host._input(_action("ui_left"))
	_expect(ll.selected_row() == tab2_row,
		"stepping back should restore tab 2's saved cursor (row %d), got %d" % [tab2_row, ll.selected_row()])

	# --- Slice 5: ○ — refused vs committed, and the list STAYS OPEN either way. ---
	# §9's three-way. Park on tab 0 row 0 (Accumulate, 300 JP against the seed's 0).
	while ll.tab() != 0:
		host._input(_action("ui_right"))
	while ll.selected_row() != 0:
		host._input(_action("ui_up"))
	host._input(_action("ui_accept"))
	_expect(cues.size() == 1 and String(cues[0][1]) == "system" and String(cues[0][0]) == "system.invalid",
		"an unaffordable ○ should buzz exactly once as system-bank 'invalid', got %s" % [cues])
	_expect(sel.progression.learned_abilities.is_empty(), "a refused ○ must not learn anything")
	_expect(host.learn_ability_list() != null and is_instance_valid(host.learn_ability_list()),
		"a refused ○ must leave the ability list open")
	# Now afford it. EARN the JP (not a raw poke) so the lifetime total accrues and the
	# commit's spend can be seen to move `Jp` without moving `Total`.
	var pick = _first_unlearned(sel, "4a")
	_expect(pick != null, "the seeded Squire should have an unlearned learnable ability")
	if pick != null:
		var cost: int = int(pick.jp_cost)
		sel.progression.add_jp(cost + 5)
		# The list was built against the OLD pool; re-enter it the way the player would, by
		# backing out to the picker and choosing the job again.
		host._input(_action("ui_cancel"))
		var back = host.job_picker()
		_expect(back != null and is_instance_valid(back), "× should land back on the job picker")
		_expect(host.learn_ability_list() == null or not is_instance_valid(host.learn_ability_list()),
			"× should drop the ability list")
		# §13.5: the picker REBUILDS and replays its own aperture from stage 1 — and it comes
		# back on the row the player left, because the ROM restores its 6-byte record.
		_expect(String(back.entries[back.selected_row()].get("id", "")) == "4a",
			"the picker should return on the job the player left, got %s" % [
				String(back.entries[back.selected_row()].get("id", ""))])
		# The band is already cleared down here; re-running the open ramp would flash it back
		# to full and fade it out a second time.
		_expect(is_equal_approx(d.vitals_band_factor(), 0.0),
			"the ×-return must not re-ramp the vitals band, got %f" % d.vitals_band_factor())
		for _f in BoxOpenAnimator.settle_frame(false):
			UI3Registry.transition_engine_step()
		host._input(_action("ui_accept"))
		ll = host.learn_ability_list()
		_expect(ll != null and is_instance_valid(ll), "○ should reopen the ability list")
		for _f in BoxOpenAnimator.settle_frame(false):
			UI3Registry.transition_engine_step()
		while ll.selected_row() != 0:
			host._input(_action("ui_up"))
		var target_name := String((ll.entries[ll.selected_entry()] as Dictionary).get("name", ""))
		host._input(_action("ui_accept"))
		_expect(sel.progression.has_learned_ability(pick.id),
			"○ on an affordable row should learn ability %d, learned=%s" % [
				pick.id, sel.progression.learned_abilities])
		_expect(int(sel.progression.job_jp.get("4a", -1)) == 5,
			"the commit should spend exactly the JP cost (leaving 5), got %d" % [
				int(sel.progression.job_jp.get("4a", -1))])
		_expect(sel.progression.get_job_jp_total("4a") == cost + 5,
			"the lifetime JP total must NOT be decremented by the spend, got %d want %d" % [
				sel.progression.get_job_jp_total("4a"), cost + 5])
		_expect(cues.size() == 1, "a successful commit must not buzz, got %s" % [cues])
		# §9: "either way the candidate list is rebuilt" — the screen STAYS OPEN and the row
		# just committed flips to `Learned` under the glove. The old stub closed here.
		_expect(host.learn_ability_list() != null and is_instance_valid(host.learn_ability_list()),
			"the commit must leave the ability list open (the ROM rebuilds, it does not exit)")
		var committed_row: Array = ll.visible_row_columns()[ll.selected_row() - ll.scroll()]
		_expect(String(committed_row[2]) == "Learned",
			"the committed row should flip to the `Learned` cell, got %s (%s)" % [
				committed_row, target_name])
		_expect(not bool(ll.visible_row_dim()[ll.selected_row() - ll.scroll()]),
			"a learned row draws in the ENABLED ramp (bit 12 is set, bits 14-15 are not)")

	# --- Slice 6: × off the list, then × off the picker → the ability menu, unchanged. ---
	host._input(_action("ui_cancel"))
	var reopened = host.job_picker()
	_expect(reopened != null and is_instance_valid(reopened), "× should land back on the job picker")
	for _f in BoxOpenAnimator.settle_frame(false):
		UI3Registry.transition_engine_step()
	host._input(_action("ui_cancel"))
	_expect(host.job_picker() == null or not is_instance_valid(host.job_picker()),
		"△ should close the picker")
	# --- The CLOSE is a walk, and NOTHING rides it (user-directed 2026-08-19). ---
	# The box shuts 100% FIRST; then the screen comes back in ONE beat — vitals band, ability
	# list-menu and every DetailScene panel together, on the SAME driven frame the aperture
	# reaches shut. Assert the MECHANISM, not frame numbers: sample all three per frame, and
	# require every pre-settle frame to be fully torn down and the settle frame fully restored.
	_expect(is_instance_valid(reopened) and not reopened.is_queued_for_deletion(),
		"△ must PLAY the box-close, not free the picker outright")
	var band_walk: Array = [d.vitals_band_factor()]
	var menu_walk: Array = [menu.visible]
	var panel_walk: Array = [d.panels_visible()]
	var walk_guard := 0
	while reopened.window() != null and not reopened.window().is_settled() and walk_guard < 240:
		UI3Registry.transition_engine_step()
		band_walk.append(d.vitals_band_factor())
		menu_walk.append(menu.visible)
		panel_walk.append(d.panels_visible())
		walk_guard += 1
	_expect(band_walk.size() > 2,
		"the close should span several driven frames, got %d samples" % band_walk.size())
	var last := band_walk.size() - 1
	for i in last:
		_expect(float(band_walk[i]) < 0.01,
			"the vitals band must stay CLEARED until the box is shut — frame %d of %d is %f (walk %s)"
				% [i, last, float(band_walk[i]), band_walk])
		_expect(not bool(menu_walk[i]),
			"the ability list-menu must stay hidden until the box is shut — frame %d of %d is visible" % [i, last])
		_expect(not bool(panel_walk[i]),
			"the DetailScene panels must stay hidden until the box is shut — frame %d of %d are visible" % [i, last])
	_expect(is_equal_approx(float(band_walk[last]), 1.0),
		"the SHUT box should restore the vitals band on the settle frame, got %f" % float(band_walk[last]))
	_expect(bool(menu_walk[last]), "the SHUT box should restore the ability list-menu")
	_expect(bool(panel_walk[last]), "the SHUT box should restore every DetailScene panel")
	_expect(reopened.is_queued_for_deletion(),
		"the picker should be freed once its box has shut — not before")
	_expect(d.ability_only, "the cancel should leave the ability sub-screen in place")
	_expect(sel.progression.learned_abilities.size() == 1
		and int(sel.progression.job_jp.get("4a", -1)) == 5,
		"the cancel must not change the progression")

	_finish()


## The Lv./Total/Next/Jp column strings the picker SHOULD render for the visible window
## starting at `scroll` — derived from the CATALOGUE + the data tables + the live progression,
## never from the picker. Reads JobCandidates (the row set) rather than get_unlocked_jobs()
## since the seam moved; the per-unit numbers still come off the progression, unchanged —
## a catalogue job the unit has never held simply reads Lv.0 / 0 / <full next> / 0. Next = the JP still owed toward the next job level (round 10 #5: Lv./Next keep
## deriving from the spendable `job_jp`; only Total reads the new lifetime field).
func _expected_columns(sel, scroll: int) -> Array:
	var out: Array = []
	var listed: Array = _catalog_ids()
	for i in range(scroll, mini(listed.size(), scroll + JobPickerMenu.VISIBLE_ROWS)):
		var jid: String = String(listed[i])
		var lv: int = sel.progression.get_job_level(jid)
		var owed: int = maxi(0, JobLevelsDatabase.get_jp_for_level(lv + 1)
			- sel.progression.get_job_jp(jid))
		# Zero-padded to the ROM's `maxd` per column (LEARN_PICKER.md §3.1 / round 16):
		# Lv. is 1 digit, Total/Next/Jp are 4 with literal leading `0` glyphs.
		out.append([str(lv).pad_zeros(1),
			str(sel.progression.get_job_jp_total(jid)).pad_zeros(4),
			str(owed).pad_zeros(4),
			str(sel.progression.get_job_jp(jid)).pad_zeros(4)])
	return out


## The `[Mp, Speed, Jp]` strings the ABILITY LIST should paint for tab `t` of `job_id` —
## derived from the ability tables + the live progression, never read back from the menu.
## Mirrors the ROM's three row shapes (LEARN_ABILITY_LIST.md §5.2/§14.3): a non-ACTION
## ability draws the dash cell across both number columns, an already-learned one draws the
## `Learned` cell in place of the JP digits, and Speed is `ceil(100 / ct)`.
func _expected_ability_columns(sel, job_id: String, t: int) -> Array:
	var out: Array = []
	for a in AbilityDatabase.get_learnable_abilities_for_job(job_id):
		if LearnAbilityMenu.tab_for_id(int(a.id)) != t:
			continue
		var rec: Dictionary = AbilityDatabase.ABILITIES.get(a.id, {})
		var row: Array = []
		if LearnAbilityMenu.is_dash_row(int(a.id)):
			row.append("-")
			row.append("-")
		else:
			row.append(str(int(rec.get("mp_cost", 0))).pad_zeros(2))
			row.append(str(LearnAbilityMenu.speed_from_ct(int(rec.get("ct", 0)))).pad_zeros(2))
		row.append("Learned" if sel.progression.has_learned_ability(a.id)
			else str(int(a.jp_cost)).pad_zeros(4))
		out.append(row)
	return out


## Which of tab `t`'s rows should paint through the DISABLED ramp — the ROM candidate array's
## bits 14–15 (§8): set when the ability is neither already learned nor affordable out of the
## unit's JP in this job. A LEARNED row is drawn enabled (bit 12, not bits 14–15), which is
## why the settled capture shows `Dash`/`Throw Stone` dark and `Accumulate`/`Heal` grey.
func _expected_ability_dim(sel, job_id: String, t: int) -> Array:
	var jp: int = sel.progression.get_job_jp(job_id)
	var out: Array = []
	for a in AbilityDatabase.get_learnable_abilities_for_job(job_id):
		if LearnAbilityMenu.tab_for_id(int(a.id)) != t:
			continue
		out.append(not sel.progression.has_learned_ability(a.id) and jp < int(a.jp_cost))
	return out


## The catalogue's job ids in catalogue (render) order — the picker's row set since the
## seam moved off the progression gate. Derived from JobCandidates, the production source,
## so this oracle tracks the one seam rather than re-deriving the sort here.
func _catalog_ids() -> Array:
	var out: Array = []
	for row in JobCandidates.build_catalog():
		out.append(String(row["id"]))
	return out


func _picker_ids(jp) -> Array:
	var out: Array = []
	for e in jp.entries:
		out.append(String(e.get("id", "")))
	return out


func _entry_of(jp, job_id: String) -> Dictionary:
	for e in jp.entries:
		if String(e.get("id", "")) == job_id:
			return e
	return {}


## Park the picker cursor on `job_id` by driving the REAL ui_down/ui_up input path (never by
## poking the row), so the scroll window follows exactly as it would under the player's hand.
## Catalogue rows are name-sorted, so a job's index is not knowable as a literal.
func _drive_to_id(host, jp, job_id: String) -> void:
	var want := -1
	for i in jp.entries.size():
		if String(jp.entries[i].get("id", "")) == job_id:
			want = i
			break
	if want < 0:
		_expect(false, "job %s is not in the catalogue — cannot drive to it" % job_id)
		return
	var guard: int = jp.row_count() * 2 + 4
	while jp.selected_row() > want and guard > 0:
		host._input(_action("ui_up"))
		guard -= 1
	while jp.selected_row() < want and guard > 0:
		host._input(_action("ui_down"))
		guard -= 1
	_expect(jp.selected_row() == want,
		"driving to job %s should land row %d, got %d" % [job_id, want, jp.selected_row()])


## The first unlearned learnable ability for `job_id` per the port-side spec (the phase-1
## stub's commit rule) — read from the data tables, never from the host.
func _first_unlearned(sel, job_id: String):
	for a in AbilityDatabase.get_learnable_abilities_for_job(job_id):
		if not sel.progression.has_learned_ability(a.id):
			return a
	return null


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationLearnPickerTest")
	else:
		print("[PASS] FormationLearnPickerTest: Learn -> job picker -> ABILITY LIST -> commit/cancel")
	get_tree().quit()
