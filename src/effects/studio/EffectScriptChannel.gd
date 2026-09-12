extends RefCounted
## Write-side encoder for the effect SCRIPT PATTERN (#273, ADR-0094). A "swap"
## regenerates the ROOT `script_ops` to the target canonical pattern, preserving the
## prologue (texture page + every load_callback). Structural: the score re-flows (the
## phase-1/phase-2 sections hide on 1-phase, reappear on 3-phase) and the byte-exact
## whole-section rewrite — regenerate + tail-shift + header fix-up — happens at save
## (EffectScriptSaver → tools/write_effect_script.py). Undo is snapshot-based: the
## session stashes the pre-swap `script_ops` array and restores it wholesale.
##
## A swap is offered ONLY for a swappable script (DATA-format AND strictly canonical);
## Custom / CODE-format / non-canonical scripts refuse it (empty result). A swap to the
## already-current pattern is a `no_edit` (records nothing). No `class_name` (ADR-0004).

const EffectScriptPattern = preload("res://src/effects/studio/EffectScriptPattern.gd")

# choice index -> pattern (matches EffectSettingsProjector's ["3-phase", "1-phase"] choices).
const _INDEX_TO_PATTERN := {0: EffectScriptPattern.P_3PHASE, 1: EffectScriptPattern.P_1PHASE}


## Swap the script pattern to the target `new_raw` choice index. Returns
## `{before_pattern, after_pattern, invalidates_sim, invalidates_layout}` on a real swap,
## `{no_edit: true}` when already the target, or `{}` when refused (not swappable / bad
## index). The caller stashes a structural snapshot for undo BEFORE dispatch.
static func apply_raw(data, _field_ref: Dictionary, new_raw) -> Dictionary:
	if data == null or not (data.script_ops is Array) or data.script_ops.is_empty():
		return {}
	var target: String = _INDEX_TO_PATTERN.get(int(new_raw), "")
	if target == "":
		return {}
	# Only a swappable (DATA + strictly-canonical) script may swap.
	var cls: Dictionary = EffectScriptPattern.classify(
		data.script_ops, not bool(data.script_code_format))
	if not bool(cls.get("swappable", false)):
		return {}
	var before: String = String(cls.get("mode", ""))
	if before == target:
		return {"no_edit": true}
	var pro: Dictionary = EffectScriptPattern.extract_prologue(data.script_ops)
	# Replace (never mutate in place) so the pre-swap array the session stashed stays intact.
	data.script_ops = EffectScriptPattern.regenerate_root_ops(
		target, int(pro["texture_page"]), pro["callbacks"])
	return {
		"before_pattern": before,
		"after_pattern": target,
		# STRUCTURAL: the field set reshapes (the choice cell re-seeds to the new mode) AND the
		# score re-flows (phase sections hide/show) — the page takes the full re-project path,
		# like the screen Blend/Gradient Kind flip. invalidates_sim re-pumps the runtime (the
		# new opcodes execute: 1-phase drops phase-1/phase-2).
		"structural": true,
		"invalidates_sim": true,
		"invalidates_layout": true,
	}


## The live pattern of `data`'s script (for seeding the projector's choice / read-only cell).
static func read_pattern(data) -> String:
	if data == null or not (data.script_ops is Array):
		return EffectScriptPattern.P_CUSTOM
	return EffectScriptPattern.detect(data.script_ops)
