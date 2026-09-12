extends RefCounted
## Write-side channel archetype for the shared, effect-global TIER-2 SoundContainers
## (#289 / ADR-0085 / ADR-0073). A timeline sound_id resolves THROUGH a container
## (container_idx = sound_id - 2) before reaching a FEDS pair; this encoder writes the
## container's raw resolver inputs so an author can change that selection logic. Given a
## raw-byte edit it mutates the storage field on the live container entry and declares
## what the edit invalidates. Channels supply encoders, not mutation logic; the single
## choke point is EffectEditSession.apply_edit.
##
## Storage model mirrors SoundChannel: `EffectData.sound_containers` is a RAW `Dictionary`
## parsed straight from sound_containers.json ({ "containers": [ {mode, id_a, id_b, id_c,
## index}, ... ] }), not a typed object, so the encoder mutates the entry dict directly
## (`entry["mode"] = new_raw`). Dictionaries are reference types, so every reader of this
## SAME doc — the resolver (playback), the ghost projector, the container views — sees the
## mutation live.
##
## Address is ONE-dimensional: just the container `index`. A SoundContainer is shared and
## effect-global (ADR-0073), so it has no phase / channel / event coordinate — unlike the
## sound TIMELINE (three) or palette (two). Editable fields per container: `mode` and the
## three FEDS-pair ids `id_a`/`id_b`/`id_c`, all u8.
##
## `invalidates_sim = false`: a container selects which SFX fires; it has NO framebuffer
## impact, so the studio preview repaints nothing. But it DOES change what every referencing
## trigger resolves to, so it declares `invalidates_containers` — the page's signal to
## recompute the container views and re-project the dependent ghost tails (the sole visual
## tell of "this makes a sound"). The AUDIO re-fires on the next playthrough (as with the
## sound TIMELINE edits — the resolver reads the shared doc).
##
## No class_name (ADR-0004); load()ed by path.

const _EDITABLE_FIELDS := ["mode", "id_a", "id_b", "id_c"]


## Write one raw value for the container named by `field_ref`, and return the snapshot the
## choke point records for undo. `field_ref` = {channel:"sound_container", index, field}.
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	var entry = _resolve_container(data, field_ref)
	if entry == null:
		push_error("SoundContainerChannel: no container for %s" % str(field_ref))
		return {}
	var field: String = field_ref.get("field", "")
	if not _EDITABLE_FIELDS.has(field):
		push_error("SoundContainerChannel: unknown container field '%s'" % field)
		return {}
	var before: int = int(entry.get(field, 0))
	entry[field] = int(new_raw)
	return {
		"before_raw": before,
		"after_raw": int(new_raw),
		"invalidates_sim": false,
		"invalidates_containers": true,
		"faithful": _byte_verdict(field, int(new_raw)),
	}


## Non-destructive Faithful advisory: a container field only lowers to E###.BIN if it fits
## its unsigned byte range (each container field is a u8).
static func _byte_verdict(field: String, raw: int) -> Dictionary:
	if raw < 0 or raw > 255:
		return {
			"ok": false,
			"reason": "%s = %d is outside the 0–255 byte encoding (Free-only)" % [field, raw],
		}
	return {"ok": true, "reason": ""}


## Resolve the addressed container entry by walking the raw doc:
## `data.sound_containers["containers"][index]`. null for a missing doc / out-of-range index.
static func _resolve_container(data, field_ref: Dictionary):
	if data == null or not (data.sound_containers is Dictionary):
		return null
	var containers = data.sound_containers.get("containers", null)
	if not (containers is Array):
		return null
	var index: int = int(field_ref.get("index", -1))
	if index < 0 or index >= containers.size() or not (containers[index] is Dictionary):
		return null
	return containers[index]
