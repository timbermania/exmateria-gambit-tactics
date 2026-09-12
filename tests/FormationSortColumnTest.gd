extends Node
# test-kind: logic
# seeded-break: sort_value_from_character's out-of-battle CT readout loses its `dashes: true` flag — 'ct readout missing dashes flag (would render 000/000)' RED; the CT label/cur/max arm and every hp/mp/lv_exp/brave_faith/header/CLUT/ring arm stays green; GREEN unbroken on the reverted tree

## FormationScene sort-column + header model test (#174) — pure GDScript, no GPU.
##
## Guards the two pure mappings the sort-column/chrome layer is built on:
##   * sort_value_from_character(): roster-Character -> the per-cell sort readout
##     (label + cur/max pair or a solo number) for each sort key. Roster units are
##     OUT of battle, so HP/MP read full (cur == max == effective) and CT reads 0 —
##     the same out-of-battle rule the vitals view uses.
##   * the sort-tab header model: the fixed label row and which tab is active for a
##     given sort key (HP is the default/active sort in t04.png).
## The on-screen glyph placement is byte-approximate and headful-tuned vs t04.png;
## only the data mapping is asserted here.

const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")
const Character = ExMateriaCatalogue.Character
func _ready() -> void:
	var failed := false

	var c: Character = Character.create_default("Ramza", "4a", false)
	var prog = c.progression
	var eff_hp: int = prog.get_effective_hp()
	var eff_mp: int = prog.get_effective_mp()

	# 1. HP sort key -> "Hp" label, full cur/max pair (out of battle).
	var hp: Dictionary = FormationScene.sort_value_from_character(c, "hp")
	if hp.get("label") != "Hp" or hp.get("kind") != "pair" \
			or int(hp.get("cur", -1)) != eff_hp or int(hp.get("max", -1)) != eff_hp:
		print("[FAIL] hp readout: %s (eff_hp=%d)" % [hp, eff_hp]); failed = true

	# 2. MP sort key -> "Mp" label, full cur/max pair.
	var mp: Dictionary = FormationScene.sort_value_from_character(c, "mp")
	if mp.get("label") != "Mp" or mp.get("kind") != "pair" \
			or int(mp.get("cur", -1)) != eff_mp or int(mp.get("max", -1)) != eff_mp:
		print("[FAIL] mp readout: %s (eff_mp=%d)" % [mp, eff_mp]); failed = true

	# 3. CT sort key -> empty pair (no battle CT out of formation), flagged for DASH
	# rendering: out of battle the oracle reads "Ct ---/---" (§12.3.5), so the readout
	# must carry `dashes = true` (the cur/max slots render dash glyphs, not "000/000").
	var ct: Dictionary = FormationScene.sort_value_from_character(c, "ct")
	if ct.get("label") != "Ct" or int(ct.get("cur", -1)) != 0 or int(ct.get("max", -1)) != 0:
		print("[FAIL] ct readout: %s" % ct); failed = true
	if not bool(ct.get("dashes", false)):
		print("[FAIL] ct readout missing dashes flag (would render 000/000): %s" % ct); failed = true

	# 4. Lv+Exp share ONE combined tab (§12.3.5, oracle) -> a "duo": two labelled
	# values ("Lv.99 Exp.05"), NOT two separate solo keys. There is no "lv"/"exp" key.
	var lvexp: Dictionary = FormationScene.sort_value_from_character(c, "lv_exp")
	if lvexp.get("kind") != "duo" \
			or (lvexp.get("left", {}) as Dictionary).get("label") != "Lv." \
			or str((lvexp.get("left", {}) as Dictionary).get("text")) != str(prog.level) \
			or (lvexp.get("right", {}) as Dictionary).get("label") != "Exp." \
			or str((lvexp.get("right", {}) as Dictionary).get("text")) != str(prog.experience):
		print("[FAIL] lv_exp readout: %s (lv=%d exp=%d)" % [lvexp, prog.level, prog.experience]); failed = true
	# The retired 6-key model's separate "lv"/"exp" keys must be GONE.
	if not FormationScene.sort_value_from_character(c, "lv").is_empty() \
			or not FormationScene.sort_value_from_character(c, "exp").is_empty():
		print("[FAIL] stale separate lv/exp keys still resolve"); failed = true

	# 5. Brave/Faith share one tab -> a "duo" too ("Br.70 Fa.70"), two labelled values.
	var bf: Dictionary = FormationScene.sort_value_from_character(c, "brave_faith")
	if bf.get("kind") != "duo" \
			or (bf.get("left", {}) as Dictionary).get("label") != "Br" \
			or int((bf.get("left", {}) as Dictionary).get("text", "-1").to_int()) != prog.brave \
			or (bf.get("right", {}) as Dictionary).get("label") != "Fa" \
			or int((bf.get("right", {}) as Dictionary).get("text", "-1").to_int()) != prog.faith:
		print("[FAIL] brave_faith readout: %s (br=%d fa=%d)" % [bf, prog.brave, prog.faith]); failed = true

	# 6. The sort-tab header model (§12.3.2): the six sort labels, in order, come
	# from the ROM-extracted RANGETILE metadata — one label per sort key. The
	# Brave/Faith tab carries a second cell (Br + Fa; the atlas has no combined
	# glyph). All named cells must be present in the atlas (guards Br/Fa vs drift).
	var atlas := RangeTileAtlas.new()
	if not atlas.has_header():
		print("[FAIL] atlas has no sort_header section (re-run parse_range_tiles)"); failed = true
	# The header draws SIX label glyphs (Hp Mp Ct Lv. Exp. Br+Fa) but they page as FIVE
	# keys (§12.3.5): Lv.+Exp. and Br.+Fa. each combine into one tab, so glyph-count and
	# key-count intentionally DIFFER. Guard both counts explicitly.
	var labels: Array = atlas.header_labels()
	if labels.size() != 6:
		print("[FAIL] header should draw 6 label glyphs, got %d" % labels.size()); failed = true
	if FormationScene.SORT_KEYS.size() != 5:
		print("[FAIL] should be 5 sort keys, got %d: %s" % [FormationScene.SORT_KEYS.size(), FormationScene.SORT_KEYS]); failed = true
	var label_names: Array = []
	for l in labels:
		label_names.append(str(l.get("name", "")))
		if not atlas.has_label(str(l.get("name", ""))):
			print("[FAIL] header label %s missing from atlas" % l.get("name")); failed = true
	if label_names != ["Hp", "Mp", "Ct", "Lv.", "Exp.", "Br"]:
		print("[FAIL] header label order %s" % [label_names]); failed = true
	var bf_l: Dictionary = labels[labels.size() - 1] if labels.size() > 0 else {}
	if str(bf_l.get("x2_name", "")) != "Fa" or not atlas.has_label("Fa"):
		print("[FAIL] brave_faith tab not Br+Fa: %s" % [bf_l]); failed = true
	# §12.3.3: each header label carries its OWN atlas cell [u,v,w,h] + live-prim x
	# (principled placement from the header prims, NOT the vitals WORD_LABELS). The
	# Brave/Faith tab additionally carries the "Fa" cell + a real period GLYPH cell —
	# so the "Br.Fa" dot is a textured atlas cell, never a hand-placed quad.
	for l in labels:
		var cell: Array = l.get("cell", [])
		if cell.size() != 4:
			print("[FAIL] header label %s has no 4-elem cell: %s" % [l.get("name"), cell]); failed = true
	var dot: Dictionary = bf_l.get("dot", {})
	if (dot.get("cell", []) as Array).size() != 4 or (bf_l.get("x2_cell", []) as Array).size() != 4:
		print("[FAIL] Br.Fa tab missing period-glyph cell / Fa cell: %s" % [bf_l]); failed = true
	# "Exp" must NOT be the vitals "Exp." cell (which includes a trailing period): the
	# header cell is the narrow 17px "Exp" (w17 clears the "p" bowl without pulling in
	# the period — §12.3.5). Guard the width so it can't regress wide (into the period).
	var exp_l: Dictionary = {}
	for l in labels:
		if str(l.get("name", "")) == "Exp.":
			exp_l = l
	if (exp_l.get("cell", []) as Array).size() == 4 and int(exp_l["cell"][2]) > 17:
		print("[FAIL] Exp header cell too wide (includes a period?): %s" % [exp_l.get("cell")]); failed = true
	if FormationScene.sort_tab_active_index("hp") != 0:
		print("[FAIL] hp not tab 0: %d" % FormationScene.sort_tab_active_index("hp")); failed = true
	if FormationScene.sort_tab_active_index("brave_faith") != 4:
		print("[FAIL] brave_faith not tab 4: %d" % FormationScene.sort_tab_active_index("brave_faith")); failed = true
	if FormationScene.sort_tab_active_index("bogus") != -1:
		print("[FAIL] unknown key not -1: %d" % FormationScene.sort_tab_active_index("bogus")); failed = true
	# The label-glyph indices each key highlights (§12.3.5): combined keys light TWO.
	var idx_expect := {"hp": [0], "mp": [1], "ct": [2], "lv_exp": [3, 4], "brave_faith": [5]}
	for k in idx_expect:
		if FormationScene.sort_tab_label_indices(k) != idx_expect[k]:
			print("[FAIL] sort_tab_label_indices(%s)=%s != %s" % [k, FormationScene.sort_tab_label_indices(k), idx_expect[k]]); failed = true

	# 8. Per-cell HP/MP/CT fill swatch (§12.3): the sort-value emitter draws a fixed-width
	# textured swatch keyed to the active sort column (0..2 = Hp/Mp/Ct). Lv/Exp/Br.Fa draw
	# no bar. Guards the ROM-derived stat mapping so a key can't silently gain/lose a swatch.
	var bar_expect := {"hp": 0, "mp": 1, "ct": 2, "lv_exp": -1, "brave_faith": -1, "bogus": -1}
	for k in bar_expect:
		if FormationScene.cell_sort_bar_stat(k) != bar_expect[k]:
			print("[FAIL] cell_sort_bar_stat(%s)=%d != %d" % [k, FormationScene.cell_sort_bar_stat(k), bar_expect[k]]); failed = true

	# 9. The fill swatch rides its OWN depth rung (RP_CELL_BAR): over the orb, UNDER the
	# sort digits (the top `cur` overlaps the swatch's upper edge in the oracle). This
	# ordering is what keeps the digits legible in front of the coloured band.
	if not (FormationScene.RP_ORB < FormationScene.RP_CELL_BAR
			and FormationScene.RP_CELL_BAR < FormationScene.RP_SORT_VALUE):
		print("[FAIL] RP_CELL_BAR rung out of order: orb=%d bar=%d value=%d" % [
			FormationScene.RP_ORB, FormationScene.RP_CELL_BAR, FormationScene.RP_SORT_VALUE]); failed = true

	# 7. The header CLUTs are the REAL VRAM palettes (ROM asset tail, §12.3.2) —
	# a genuine 2-tone emboss, NOT a single-ink punch-out. inactive_label: idx0
	# transparent, idx1 dark ink, idx4 = the bar's own tan (glyph fill blends in);
	# active_label: idx1 white (on a dark idx4 fill). This is what the first pass
	# faked and got rejected for.
	var inactive: Array = atlas.header_clut_colors("inactive_label")
	var active: Array = atlas.header_clut_colors("active_label")
	var button: Array = atlas.header_clut_colors("button")
	if inactive.size() != 16 or active.size() != 16 or button.size() != 16:
		print("[FAIL] header CLUTs not all 16-entry (%d/%d/%d)" % [inactive.size(), active.size(), button.size()]); failed = true
	# The L2/R2 PRESSED-button CLUT (§12.3.5, oracle 0x7e7c): the button flashes from
	# blue-grey (normal) to a WARM TAN when tapped — its body colour (idx4) reads r,g high
	# with b clearly lower, unlike the cool button CLUT. Guards the pressed flash's colour.
	var pressed: Array = atlas.header_clut_colors("button_pressed")
	if pressed.size() != 16:
		print("[FAIL] button_pressed CLUT not 16-entry: %d (re-run parse_range_tiles)" % pressed.size()); failed = true
	elif not (pressed[4].r > 0.5 and pressed[4].g > 0.5 and pressed[4].b < pressed[4].r - 0.08):
		print("[FAIL] button_pressed idx4 not warm tan: %s" % pressed[4]); failed = true
	if FormationScene.HEADER_BTN_PRESSED_DY <= 0.0:
		print("[FAIL] pressed button must nudge down (dy>0): %s" % FormationScene.HEADER_BTN_PRESSED_DY); failed = true
	else:
		if inactive[0].a > 0.01:
			print("[FAIL] inactive idx0 not transparent: a=%.2f" % inactive[0].a); failed = true
		if inactive[1].r > 0.3 or inactive[1].g > 0.3 or inactive[1].b > 0.3:
			print("[FAIL] inactive idx1 not dark ink: %s" % inactive[1]); failed = true
		if not (inactive[4].r > 0.5 and inactive[4].r >= inactive[4].g and inactive[4].g >= inactive[4].b):
			print("[FAIL] inactive idx4 not tan: %s" % inactive[4]); failed = true
		if not (active[1].r > 0.85 and active[1].g > 0.85 and active[1].b > 0.8):
			print("[FAIL] active idx1 not white: %s" % active[1]); failed = true
		# The active-tab "dark box" is NOT a separate primitive — it is the label
		# cell's OWN index-4 fill field re-coloured by the CLUT swap (§12.3.3, VRAM
		# oracle). inactive idx4 is the bar's tan (blends in → no visible box);
		# active idx4 is near-black (→ the dark box). Guard both so the swap-as-box
		# mechanism can't silently regress back to a hand-drawn quad.
		if not (inactive[4].r > 0.5):
			print("[FAIL] inactive idx4 (box field) not tan/blended: %s" % inactive[4]); failed = true
		if not (active[4].r < 0.2 and active[4].g < 0.2 and active[4].b < 0.2):
			print("[FAIL] active idx4 (box field) not dark — box-is-CLUT-swap broken: %s" % active[4]); failed = true

	# 10. L2/R2 paging state machine (§12.3.5): R2 (+1) walks Hp→Mp→Ct→Lv.Exp→Br.Fa and
	# WRAPS back to Hp; L2 (-1) is the exact inverse. The grid does NOT re-order — this only
	# advances which stat column shows — so the model is a pure ring over SORT_KEYS.
	var order := ["hp", "mp", "ct", "lv_exp", "brave_faith"]
	if FormationScene.SORT_KEYS != order:
		print("[FAIL] SORT_KEYS order %s != %s" % [FormationScene.SORT_KEYS, order]); failed = true
	# R2 forward through the whole ring + wrap.
	var k := "hp"
	for step in order.size():
		var want: String = order[(step + 1) % order.size()]
		k = FormationScene.next_sort_key(k, 1)
		if k != want:
			print("[FAIL] R2 step %d: got %s want %s" % [step, k, want]); failed = true
	if k != "hp":
		print("[FAIL] R2 did not wrap back to hp: %s" % k); failed = true
	# L2 backward is the inverse (Hp -L2-> Br.Fa wrap).
	if FormationScene.next_sort_key("hp", -1) != "brave_faith":
		print("[FAIL] L2 off hp did not wrap to brave_faith: %s" % FormationScene.next_sort_key("hp", -1)); failed = true
	if FormationScene.next_sort_key("mp", -1) != "hp":
		print("[FAIL] L2 off mp != hp: %s" % FormationScene.next_sort_key("mp", -1)); failed = true
	# next then prev round-trips for every key (ring invariant).
	for key in order:
		if FormationScene.next_sort_key(FormationScene.next_sort_key(key, 1), -1) != key:
			print("[FAIL] R2 then L2 not identity for %s" % key); failed = true
	# An unknown key falls back to the first (defensive; matches next_sort_key contract).
	if FormationScene.next_sort_key("bogus", 1) != "hp":
		print("[FAIL] unknown key next != hp: %s" % FormationScene.next_sort_key("bogus", 1)); failed = true

	if failed:
		print("[FAIL] FormationSortColumn test")
	else:
		print("[PASS] FormationSortColumn: per-cell readout + sort-tab header model")
	get_tree().quit()
