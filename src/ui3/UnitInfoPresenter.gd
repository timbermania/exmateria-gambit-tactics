class_name UnitInfoPresenter
extends RefCounted
## Field-inspect info-window presenter (#91).
##
## Pure mapping from a unit's UnitStats/snapshot *view* (a plain Dictionary) to
## the formatted rows the info window draws: identity (name/job/level), the
## HP/MP/CT bar rows (cur/max text + clamped fill fraction), Brave/Faith, and the
## active-status list. Kept pure (no nodes, no GPU) so the display logic is
## testable; the window node reads a fresh view each frame and never caches.
##
## Faithful to FFT's bottom info bar (spec §3 / §8): the bars are gradient quads
## whose fill is value/max; CT is always out of 100.

const CT_MAX := 100


static func build(view: Dictionary) -> Dictionary:
	return {
		"name": String(view.get("name", "")),
		"job": String(view.get("job", "")),
		"level": int(view.get("level", 1)),
		"exp": int(view.get("exp", 0)),
		"sprite_id": int(view.get("sprite_id", -1)),
		"template_folder": String(view.get("template_folder", "")),
		"hp": _bar(int(view.get("current_hp", 0)), int(view.get("max_hp", 0))),
		"mp": _bar(int(view.get("current_mp", 0)), int(view.get("max_mp", 0))),
		# CT: a battle unit has a 0..100 charge; an OUT-OF-BATTLE roster unit has no CT —
		# FFT draws it "---/---" with a FULL bar (oracle §14.4). `has_ct: false`
		# (FormationScene.vitals_view_from_character) selects that dash row; battle
		# views omit the flag and default to the numeric bar.
		"ct": (_bar(int(view.get("ct", 0)), CT_MAX) if bool(view.get("has_ct", true)) else _bar_dashes()),
		"brave": int(view.get("brave", 0)),
		"faith": int(view.get("faith", 0)),
		"statuses": _status_list(view.get("statuses", [])),
	}


static func _bar(cur: int, maximum: int) -> Dictionary:
	## A bar row: "cur/max" label + fill fraction clamped to [0,1]
	## (overheal / over-CT never overflows; max 0 never divides by zero).
	var frac := 0.0
	if maximum > 0:
		frac = clampf(float(cur) / float(maximum), 0.0, 1.0)
	return {"cur": cur, "max": maximum, "frac": frac, "text": "%d/%d" % [cur, maximum]}


static func _bar_dashes() -> Dictionary:
	## The out-of-battle CT row: no numeric value ("---/---") and a FULL bar. `dashes`
	## tells the window to render the dash pair; `frac` 1.0 fills the gauge (oracle §14.4).
	return {"cur": 0, "max": 0, "frac": 1.0, "dashes": true, "text": "---/---"}


static func _status_list(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for s in raw:
			out.append(String(s))
	return out
