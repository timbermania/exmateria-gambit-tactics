extends RefCounted

## Unified BODY palette-row resolver for event-script / EVTCHR unit spawns.
##
## FFT colors a cinematic unit sprite along two independent axes; this resolves
## the CONTENT axis (which of the SPR's 16 sub-palette rows the BODY shader
## looks up). The full derivation, citations, and confidence table live in
## `research/working_documents/EVTCHR_CLUT_RESOLUTION.md` (§1 two-axis model,
## §3.1 this resolver). The one-line rule:
##
##   resolve_body_palette_row(slot, sprite_id):
##       if is_monster(job): return job.body_palette_row   # SCUS 0x2E (ADR-0022)
##       row = slot.palette                                # ENTD byte @0x17
##       if row in populated_body_rows(sprite_id): return row   # generics: Blue=0/Red=2
##       return 0                                          # named unique SPR -> clamp
##
## This collapses the four historical row-sources into ONE (see the doc's §3
## reconciliation matrix). Monsters keep the JOB row (correct — the ENTD byte is
## an enemy-squad team-recolor selector they ignore). Humans keep the ENTD byte
## ONLY when the SPR actually authored that row — generic sprites author rows
## 0-4 so Blue=0/Red=2 pass through, but a NAMED unique unit (Delita 0x05,
## Ovelia 0x0C, Ramza 0x01) authors only body row 0, so a stale byte of 2 points
## at an all-black row and must clamp to 0 (the "Delita in a black jumpsuit"
## trap). Cinematic mode (V14, SpriteLayerManager) consumes the resolved row
## unchanged — it only swaps the pixel atlas.
##
## `populated_body_rows` is a bake-time fact from `tools/bake_populated_rows.py`
## (scans the ISO-derived `NN.palette.tga`), so the clamp is deterministic and
## needs no runtime PSX read.
## Vault: [[EVTCHR CLUT Resolution]]

# ADR-0223 dec. 8 — this line USED to name `JsonAsset` where `src/data/`
# declared it, which is ARM7_BURN_DOWN #809 and goal #5 unmet on the TYPE
# axis. The file moved to the port; naming the port is what a portable addon
# is ALLOWED to do (ADR-0139 dec. 12, `plugin.cfg` `deps=`), and the spelling
# below is unchanged (ADR-0212 dec. 1).
const JsonAsset = ExMateriaPlatform.JsonAsset

## `ContentPort` is `addons/exmateria_sprite_rig`'s, published on the addon's one
## global name; this aliases it back so the call sites below stay a verb rather
## than a façade walk (ADR-0211 dec. 4, ADR-0217 dec. 9). The port replaces a
## direct name for a host content store: this file no longer compiles against one.
const ContentPort = ExMateriaSpriteRig.ContentPort

const _MANIFEST_PATH := "res://addons/exmateria_sprite_rig/resources/populated_rows.json"

# sprite-id (uppercase two-hex str) -> Array[int] of populated body rows 0-7.
static var _populated_rows: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	# JSON numbers parse as floats in Godot, and `int in [float, ...]` is false
	# (strict-type membership). Normalize each row list to ints once so the
	# resolver's `row in populated` check works.
	var data := JsonAsset.load_dict(_MANIFEST_PATH, "sprites")
	for key in data:
		var rows: Array = []
		for r in data[key]:
			rows.append(int(r))
		_populated_rows[key] = rows


static func job_body_palette_row(job_id_hex: String) -> int:
	"""The JOB (CONTENT) axis on its own: the sub-palette row a unit's color comes
	from when it is JOB-sourced rather than ENTD-team-sourced.

	This is the combat / roster-spawn case — there is no ENTD deployment record, so
	no `palette` team byte to clamp. Monsters carry their variant row here (Yellow
	Chocobo=0 / Black=1 / Red=2), `special` non-humanoid jobs carry a real row too
	(Holy Dragon 0x48=3), and every humanoid job carries 0 (their default palette
	is baked at SPR row 0). Raw jobs.json value, unclamped — the row is authored
	data (SCUS 0x2E, ADR-0022), not a stale byte, so there is nothing to clamp
	against. The two-axis `resolve_body_palette_row` monster branch delegates here
	so "monster color = the job's row" lives in exactly ONE place.
	"""
	return ContentPort.job_body_palette_row(job_id_hex)


static func populated_body_rows(sprite_id: int) -> Array:
	"""Which of BODY rows 0-7 sprite `sprite_id` authored real color in.

	Returns an empty array when the sprite is absent from the manifest — the
	caller treats that as "unknown, don't clamp" (conservative pass-through).
	"""
	_ensure_loaded()
	return _populated_rows.get("%02X" % sprite_id, [])


static func resolve_body_palette_row(slot: Dictionary, sprite_id: int) -> int:
	"""The unified CONTENT-axis rule. `slot` = an ENTD deployed-unit dict (uses
	`job` and `palette`); `sprite_id` = the RESOLVED SPR id (from
	`ScenarioPlayerScene._resolve_sprite_set`), needed to clamp the ENTD byte to
	rows the SPR actually authored. Pure function (args + database statics only).
	"""
	var job_hex := "%02x" % int(slot.get("job", 0))
	if ContentPort.job_is_monster(job_hex):
		# Monster: color is a JOB attribute (SCUS 0x2E), ENTD byte ignored.
		return job_body_palette_row(job_hex)
	# Human / named unit: the ENTD `palette` byte is the team-color row, but it
	# is only valid where the SPR authored that row.
	var row := int(slot.get("palette", 0))
	var populated := populated_body_rows(sprite_id)
	if populated.is_empty():
		# Unknown sprite (not in manifest) -> don't over-clamp; keep the byte.
		return row
	if row in populated:
		return row
	# Byte points at an unpopulated (all-black/sentinel) row -> clamp to 0.
	return 0
