extends SceneTree

## Capture of the GAMBIT SURFACE (#1007, ADR-0255) on the real formation host, engine fold
## ACTIVE — the acceptance instrument ADR-0244 requires. A UI3 window host left at the camera's
## own origin draws perfectly and is INVISIBLE (`UIWindowHost` writes only x and y, so z stays 0
## on the near plane), and no layout test can see that. Only a screenshot can.
##
## Boots FormationDetailTransition, opens a unit's detail settled, arms the four-row adjustment
## set, opens the action menu, walks to the level named by --level, screenshots and quits.
##
## Run (NOT headless):
##   godot --path . -s res://tools/capture_gambit_surface.gd -- --shot=/tmp/gambit.png --level=row
##   …--level=do      the "Do" list, hung under its own column
##   …--level=ability  the "Do" list drilled into its FIRST skillset — the second box under the
##                     same column, which is the one thing about that level a predicate cannot
##                     see (it must not land on top of the row it was opened from)
##   …--level=if      the "If" list — the LAST column, so the one whose box has to be clamped
##                    back inside the 256-px mask rather than running off it
##   …--level=to      the "To" list, hung under its own column — the ADR-0276 gate's own
##                    column, and the only level where a WITHHELD row is visible as an absence
##   …--level=menu    the action menu itself, to see the four-row home
##
## `--pick=<ability name>` lands that ability on slot 0 FIRST, through the same `_ability_choices`
## apply the pad drives, so the shot shows the aim the ability BROUGHT (ADR-0276 dec. 9) rather
## than the constructor's. Searched across every skillset the taker offers; a name it cannot find
## is reported and the shot is taken anyway, because a silently unpicked ability would photograph
## as a clean default.
##
## `--worst` (or `--worst-part=N`) OVERWRITES the visible rows with the widest string every
## column can hold, so the row's pixel budget is photographed AT ITS LIMIT rather than at
## whatever a fresh roster happens to author. This is the flag ADR-0283 dec. 4 was decided on:
## the chevron's clearance only fails when the column before it reaches its cap with a glyph
## that inks its full advance, which no seeded gambit does and no layout assertion can see.
## `--worst-part=N` aims the chevron (0=Do, 1=To, 2=Subject, 3=If); bare `--worst` is 2.
##
## It writes to the WIDGET (`set_row_entries`) and not to the gambits, on purpose: the question
## is whether the LAYOUT survives its own worst case, and reaching it through four real gambits
## would need a taker whose two skillsets happened to carry the longest names in the ROM.
##
## `--scroll=N` walks the OPEN list down N rows before the shot — the only way to photograph an
## entry past the fifth, since the window shows five at a time and scrolls.
##
## `--level=slot` is accepted as the old spelling of `row`: ADR-0268 dec. 1 removed the PART
## level, so "slot" and "row" now name the same thing.

## Loaded at RUNTIME, never `preload`ed. A `-s` SceneTree script compiles before the autoloads
## register, so a preload here compiles StartActionMenu too and its `Tune` reference is a
## compile error — which takes this whole file down with it.

var _boot: Node
var _host: Node
var _f := 0
var _did := false
var _quit := false
var _shot := "/tmp/gambit_surface.png"
var _level := "slot"
var _opened := false
var _scroll := 0
var _pick := ""
var _worst := false
## `--author=Do|To|Subject|If[;…]` seeds slots 0, 1, 2… through the surface's OWN applies, by
## NAME — one `|`-separated spec per slot, slots separated by `;`. Any field may be blank to
## leave that part alone. Unlike `--worst`, which writes strings straight
## onto the widget to photograph the pixel budget, this drives `choices_for(part)` — so the shot
## shows what the PRESSES produced, which is the only thing that can catch an apply that writes
## the row it was asked for and the wrong field behind it.
var _author := ""
## `--then=To:Them` applies ONE more choice to slot 0 after `--author` has finished, so a
## SEQUENCE of presses can be photographed and not just an end state. The order of two presses
## is the whole question wherever one of them re-derives a field the other wrote.
var _then := ""
## Which part the --worst shot aims the chevron at. `2` is SUBJECT, the new column — the one
## whose 10-px gap is what the fourth column is paid for, so it is the default.
var _worst_part := 2


func _initialize() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--shot="):
			_shot = a.substr("--shot=".length())
		elif a.begins_with("--level="):
			_level = a.substr("--level=".length())
		elif a.begins_with("--scroll="):
			_scroll = int(a.substr("--scroll=".length()))
		elif a.begins_with("--pick="):
			_pick = a.substr("--pick=".length())
		elif a.begins_with("--author="):
			_author = a.substr("--author=".length())
		elif a.begins_with("--then="):
			_then = a.substr("--then=".length())
		elif a == "--worst":
			_worst = true
		elif a.begins_with("--worst-part="):
			_worst = true
			_worst_part = int(a.substr("--worst-part=".length()))
	# FormationDev, not FormationDetailTransition: the MUTATING harness (ADR-0181) is the one
	# that seeds a real owned roster, and a bare coordinator selects nobody — which reads here
	# as "the Gambit state built nothing" rather than as a missing fixture.
	_boot = load("res://assets/scenes/FormationDev.tscn").instantiate()
	root.add_child(_boot)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[gambit-cap] booting FormationDetailTransition, level=%s -> %s" % [_level, _shot])


func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _on_post_draw() -> void:
	_f += 1
	if _f == 40 and not _opened:
		_opened = true
		_host = _boot.get_node_or_null("FormationDetailTransition")
		if _host == null:
			print("[gambit-cap] the dev boot mounted no coordinator")
			_quit = true
			return
		_open()
	if _f >= 110 and not _did:
		_did = true
		root.get_texture().get_image().save_png(_shot)
		print("[gambit-cap] ===== CAPTURED f=%d -> %s =====" % [_f, _shot])
		_quit = true


func _open() -> void:
	var form = _host._formation
	var sel = form.selected_character()
	var d = _host.open_detail(sel)
	d.set_open_frame(d._open_total_frames())    # settle the detail box-open under the menu
	var StartActionMenu = load("res://src/ui3/detail/StartActionMenu.gd")
	_host.action_rows = StartActionMenu.ROWS_ADJUST
	_host.open_action_menu()
	print("[gambit-cap] detail + adjustment menu open for %s" % (sel.display_name if sel else "?"))
	if _level == "menu":
		return
	var FDT = load("res://src/ui3/formation/FormationDetailTransition.gd")
	_host.enter(FDT.State.GAMBIT)
	var surface = _host.gambit_surface()
	if surface == null:
		print("[gambit-cap] NO SURFACE — the Gambit state built nothing")
		return
	# Walk without the pad: the capture is about PIXELS, and the input path is what
	# GambitSurfaceTest drives.
	var GS = load("res://src/ui3/detail/GambitSurface.gd")

	# --pick lands an ability on slot 0 before any list opens, through the real apply — so the
	# `To` column below shows what the PRESS produced and not what this script wrote.
	if not _pick.is_empty():
		# Reaches the private `_ability_choices` the same way the rest of this file reaches
		# `_part` / `_on_chosen` / `_choices`: a capture script is not a consumer of the class's
		# interface, it is a second driver of the pad, and going through the public list would
		# mean opening two levels of menu to photograph one row.
		var landed := false
		surface._slot = 0
		for row in surface.choices_for(GS.Part.DO):
			if not (row as Dictionary).has("drill"):
				continue
			for ab in surface._ability_choices(int(row["drill"])):
				if String((ab as Dictionary)["name"]) == _pick:
					((ab as Dictionary)["apply"] as Callable).call()
					landed = true
					break
			if landed:
				break
		if not landed:
			print("[gambit-cap] --pick='%s' matched NO ability in any of this taker's"
				% _pick + " skillsets — the shot below is of the UNPICKED slot")
		else:
			# REBUILD THE ROW LIST. The apply writes the gambit; the visible rows were built when
			# the Gambit state opened, one press earlier, and nothing here presses ✕ to come back
			# to them. Without this the ROW shot photographs an EMPTY slot while `row_entries()`
			# reports the pick — the two disagreeing is exactly the readout drift the row exists
			# to close, arriving in the instrument instead of the screen.
			surface._show_level(GS.Level.ROW)
			print("[gambit-cap] picked '%s' onto slot 0; row now reads %s"
				% [_pick, str(surface.row_entries()[0])])

	# --author lands each named choice through the part's OWN apply, in reading order, so a later
	# part sees what the earlier one wrote. That order matters and is not cosmetic: `Subject` is
	# `Their` = a COPY of the aim, so landing it before the aim would copy the aim the slot had
	# before the press.
	if not _author.is_empty():
		for slot_i in range(_author.split(";").size()):
			var fields: Array = String(_author.split(";")[slot_i]).split("|")
			var parts := [GS.Part.DO, GS.Part.TO, GS.Part.SUBJ, GS.Part.IF]
			surface._slot = slot_i
			for i in range(mini(fields.size(), parts.size())):
				var want := String(fields[i]).strip_edges()
				if want.is_empty():
					continue
				var part: int = parts[i]
				surface._part = part
				var landed := false
				for entry in surface.choices_for(part):
					var row: Dictionary = entry
					if String(row.get("name", "")) != want:
						continue
					if row.has("apply"):
						(row["apply"] as Callable).call()
						landed = true
					break
				# The ability names live one level down, behind a `drill` row, so a name the part's
				# own list does not offer is looked for in every skillset the taker has.
				if not landed and part == GS.Part.DO:
					for entry in surface.choices_for(GS.Part.DO):
						var row2: Dictionary = entry
						if not row2.has("drill"):
							continue
						for ab in surface._ability_choices(int(row2["drill"])):
							if String((ab as Dictionary)["name"]) == want:
								((ab as Dictionary)["apply"] as Callable).call()
								landed = true
								break
						if landed:
							break
				if not landed:
					print("[gambit-cap] --author: NOTHING named '%s' on the %s list — the shot below"
						% [want, GS.Part.keys()[part]]
						+ " is of a row that part never received")
			surface._show_level(GS.Level.ROW)
			print("[gambit-cap] authored slot %d -> %s"
				% [slot_i, str(surface.row_entries()[slot_i])])

	if not _then.is_empty():
		var bits: Array = _then.split(":")
		var part_names := {"Do": GS.Part.DO, "To": GS.Part.TO, "Subject": GS.Part.SUBJ,
			"If": GS.Part.IF}
		if bits.size() == 2 and part_names.has(String(bits[0])):
			var part2: int = part_names[String(bits[0])]
			surface._slot = 0
			surface._part = part2
			var hit := false
			for entry in surface.choices_for(part2):
				var row3: Dictionary = entry
				if String(row3.get("name", "")) == String(bits[1]) and row3.has("apply"):
					(row3["apply"] as Callable).call()
					hit = true
					break
			if not hit:
				print("[gambit-cap] --then: the %s list does not OFFER '%s' — which is itself a"
					% [String(bits[0]), String(bits[1])]
					+ " finding if the gate is what withheld it")
			surface._show_level(GS.Level.ROW)
			print("[gambit-cap] then %s -> slot 0 reads %s"
				% [_then, str(surface.row_entries()[0])])
		else:
			print("[gambit-cap] --then: cannot parse '%s' (want Part:Name)" % _then)

	if _level == "to":
		surface._part = GS.Part.TO
		surface._on_chosen(0)
	if _level == "do" or _level == "if" or _level == "ability":
		# Aim the part first, THEN press: the row is the readout and the editor at once, so a
		# choice list is opened by ○ on a part of a row and not by descending to a part level.
		surface._part = GS.Part.IF if _level == "if" else GS.Part.DO
		surface._on_chosen(0)                    # ○ on slot 0's focused part
	if _level == "ability":
		# ○ again, on the FIRST skillset row the Do list offers. Found by the `drill` key and
		# not by index, because the verbs above it are three today and the clear makes four —
		# an index would silently capture whichever row that arithmetic lands on.
		var drilled := false
		for i in range(surface._choices.size()):
			if (surface._choices[i] as Dictionary).has("drill"):
				surface._on_chosen(i)
				drilled = true
				break
		if not drilled:
			print("[gambit-cap] the Do list offered NO skillset row — nothing to drill into")
	# --worst overwrites the VISIBLE ROWS with the widest string every column can hold, so the
	# pixel budget is photographed at its limit rather than at whatever a fresh roster happens
	# to author. It writes to the widget and not to the gambits on purpose: the question is
	# "does the LAYOUT survive its own worst case", and reaching it through four real gambits
	# would need a taker whose two skillsets happen to carry the longest names in the ROM.
	if _worst and surface.menu() != null:
		surface.menu().set_row_entries([
			{"enable": "1", "do": "DragonPowerUp", "to": "Weakest Ally", "subj": "Their",
				"iff": "HP<25%", "extra": 0},
			{"enable": "2", "do": "Dimension Magic", "to": "Nearest Ally", "subj": "My",
				"iff": "MP<50%", "extra": 1},
			{"enable": "3", "do": "Warlock Summon", "to": "Nearest Foe", "subj": "Their",
				"iff": "HP>50%", "extra": 0},
			{"enable": "4", "do": "Attack", "to": "Nearest Foe", "subj": "", "iff": "", "extra": 0},
			{"text": "Attack / Nearest Foe / — / —", "inert": true},
		], int(_worst_part))

	for _i in range(_scroll):
		if surface.menu() != null:
			surface.menu().move_down()
	print("[gambit-cap] surface level=%d slot=%d part=%d rows=%s"
		% [surface.level(), surface.slot(), surface.part(),
			str(surface.menu().visible_row_names() if surface.menu() != null else [])])
