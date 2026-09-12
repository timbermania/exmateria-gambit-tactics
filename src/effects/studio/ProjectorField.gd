extends RefCounted
## Shared field-atom builders for the per-archetype projectors (ADR-0071). A Section's
## `fields` are archetype-appropriate; this holds only the simplest atom — a `const`
## name/value row (display string, read-only) — that every projector reuses so the
## inspector renders them uniformly.


static func const_field(name: String, value: String, tooltip: String = "") -> Dictionary:
	var f := {"name": name, "shape": "const", "value": value}
	if tooltip != "":
		f["tooltip"] = tooltip
	return f
