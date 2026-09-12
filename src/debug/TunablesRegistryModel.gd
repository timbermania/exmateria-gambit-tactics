class_name TunablesRegistryModel
extends RefCounted
## Pure projection for the debug dashboard's REGISTRY page (ADR-0068 decision 9): the
## flat list of EVERY registered Tune slug with the metadata the masonry cards don't
## surface — code default, live value, range/step (or enum), inferred type, and dirty
## state. No UI here (guarded by TunablesRegistryModelTest); TunablesRegistryView
## renders these rows into a table and TuneField owns the editable control.

## One row per registered slug, sorted by slug (registered_slugs() is already sorted).
## Each row: { slug, namespace, default, value, hint, type, range, dirty }.
static func rows(tune) -> Array:
	var out: Array = []
	for slug: String in tune.registered_slugs():
		var default_value: Variant = tune.default_of(slug)
		var hint: Dictionary = tune.meta_of(slug)
		out.append({
			"slug": slug,
			"namespace": slug.get_slice(".", 0),
			"default": default_value,
			"value": tune.get_value(slug),  # coalesced live value (slug is from registered_slugs())
			"hint": hint,
			"type": type_label(default_value, hint),
			"range": range_label(hint),
			"dirty": tune.is_dirty(slug),
		})
	return out


## The control kind a slug resolves to, as a display string (mirrors TuneField's
## inference): an enum hint wins, else the default's type; unknown types show "?".
static func type_label(default_value: Variant, hint: Dictionary) -> String:
	if hint.has("enum"):
		return "enum"
	match typeof(default_value):
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "string"
		TYPE_COLOR: return "color"
		TYPE_VECTOR2: return "vector2"
		TYPE_VECTOR3: return "vector3"
		_: return "?"


## A compact human range/affordance string from the hint: "min..max /step" for a
## scalar, the option list for an enum, or "" when the hint carries nothing.
static func range_label(hint: Dictionary) -> String:
	if hint.has("enum"):
		return ", ".join(PackedStringArray(hint["enum"].keys()))
	var parts: Array = []
	if hint.has("min") or hint.has("max"):
		var lo: String = str(hint["min"]) if hint.has("min") else "*"
		var hi: String = str(hint["max"]) if hint.has("max") else "*"
		parts.append("%s..%s" % [lo, hi])
	if hint.has("step"):
		parts.append("/%s" % str(hint["step"]))
	return " ".join(PackedStringArray(parts))
