class_name PanelApplicability
extends RefCounted

## What a debug panel is a view ONTO, and whether those slugs reach anything here.
##
## The question this answers is "the Tiles panel is mounted — does turning its knobs do
## anything on THIS screen?", and the reason it exists is that every cheaper answer is
## wrong in a way that is invisible:
##
##   - **The panel is the wrong GRAIN.** A panel is a bag of rows and its rows can have
##     different owners with different liveness. `FormationScene` mounts
##     `DetailScreenDebugPanel` (`detail.*`, owner ephemeral) beside
##     `VitalsLayoutDebugPanel` (`vitals.*`, owner live) — two answers, one cell. So
##     applicability is a property of a SLUG and a panel's status is DERIVED from its rows.
##   - **The `setup()` signature is not evidence.** Four of the nine panels that take a
##     subject never read it — `CursorDebugPanel.setup(_rig: CursorRig)` ignores the rig,
##     `CameraFeelDebugPanel.setup(_camera)` ignores the camera — they migrated to pure
##     `Tune` views under ADR-0068 dec. 12 and kept the old parameter. Meanwhile
##     `TilesDebugPanel.setup()` takes NOTHING and is a view onto `tile.*`, owned by
##     `addons/exmateria_battlefield/overlay/TileOverlayConfig.gd`. A gate keyed on the
##     signature excludes the cursor panel for a parameter it never reads and waves the
##     battlefield one through. It fires on the wrong axis in both directions.
##
## So: walk the BUILT panel, collect the slugs its rows stamped
## (`TuneField.SLUG_META`), and ask `Tune.consumer_state` about each.
##
## 🔴 WHAT THIS CANNOT TELL YOU, and says so rather than guessing. `Tune.consumer_state`'s
## three states are UNDECLARED / DECLARED / CONSUMED, and only the outer two are claims —
## `DECLARED` means "nothing has been SEEN to consume this", which a build-time pull
## consumer produces just as readily as a genuinely dead knob. It is also process-scoped:
## once a battle has booted, its slugs stay declared everywhere for the rest of the session.
## Every label this module produces is therefore phrased as an observation, never a verdict:
## "no consumer seen", not "dead". Reporting a confident zero from an instrument that cannot
## distinguish absence from not-looking is the failure this whole page exists to surface.


## The slugs `panel` renders a row for, in tree order, deduplicated. Empty for a panel that
## builds no `TuneField` rows at all (an action-only panel like the effect viewer's
## transport, or one still on raw widgets) — which is why `summary_of` reports `total == 0`
## as its own state rather than folding it into "nothing is live".
static func slugs_of(panel: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	var stack: Array[Node] = [panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_meta(TuneField.SLUG_META):
			var slug := String(n.get_meta(TuneField.SLUG_META))
			if not seen.has(slug):
				seen[slug] = true
				out.append(slug)
		for c in n.get_children():
			stack.append(c)
	return out


## Per-state slug counts for `panel`: `{total, consumed, declared, undeclared, slugs}`.
## `slugs` maps each slug to its `Tune.Consumer` state so a caller can render the detail
## without walking twice.
static func summary_of(panel: Node) -> Dictionary:
	var slugs := slugs_of(panel)
	var by_slug := {}
	var consumed := 0
	var declared := 0
	var undeclared := 0
	for slug in slugs:
		var state := Tune.consumer_state(slug)
		by_slug[slug] = state
		match state:
			Tune.Consumer.CONSUMED: consumed += 1
			Tune.Consumer.DECLARED: declared += 1
			_: undeclared += 1
	return {
		"total": slugs.size(),
		"consumed": consumed,
		"declared": declared,
		"undeclared": undeclared,
		"slugs": by_slug,
	}


## A one-line, HONEST reading of `summary_of`'s counts — the string the catalogue page puts
## beside a panel's name. Deliberately never says "dead" or "inactive": see the module note.
static func summarise(summary: Dictionary) -> String:
	var total := int(summary.get("total", 0))
	if total == 0:
		return "no tunable rows"
	var consumed := int(summary.get("consumed", 0))
	var undeclared := int(summary.get("undeclared", 0))
	if undeclared == total:
		return "%d rows — owner not booted" % total
	var text := "%d/%d rows consumed" % [consumed, total]
	if undeclared > 0:
		text += ", %d not booted" % undeclared
	return text


## The per-slug label for a state, in the same observation-not-verdict register.
static func state_label(state: int) -> String:
	match state:
		Tune.Consumer.CONSUMED: return "consumed"
		Tune.Consumer.DECLARED: return "declared — no consumer seen"
		_: return "not booted"
