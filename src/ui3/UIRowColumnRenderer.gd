@tool
class_name UIRowColumnRenderer
extends RefCounted
## The painting primitive shared by every [row column schema] consumer
## (UIListModalWindow's pickers + UILearnPanel today). Callers resolve their
## per-knob sources locally — schema-dict shape varies by consumer because the
## lookup rules differ (host `@export`, row field, host Dict @export) — and
## hand the resolved values here. The painting is the same everywhere.
##
## Idempotent: subsequent calls with the same `child_name` reuse the existing
## UIText child of `parent`. The virtual-scroll factory in UIListModalWindow
## needs this (row nodes are recycled across visible indices); persistent-row
## consumers like UILearnPanel get it for free because their `parent` is
## fresh per row.


## Paint one column of a typed-row schema into `parent`. Returns the painted
## UIText for any further per-call customisation (none of today's callers
## need it; the return is the escape hatch).
##
## Parameters:
##   parent          — Node3D the column's UIText lives under.
##   child_name      — Node name to look up / create under `parent`.
##   value           — Pre-formatted display text (rows carry rendered strings).
##   host_ppu        — Host's `pixels_per_unit * assembly_scale` (or just
##                     `pixels_per_unit` when there's no assembly scale).
##   column_scale    — Per-column text scale; final text ppu = host_ppu × column_scale.
##   palette         — Resolved palette enum int.
##   space_width     — Per-call space-width override (pixels).
##   offset_x_px     — Virtual-pixel X offset; world position.x = offset_x_px × host_ppu.
##                     Pass NAN to mean "don't touch position.x" (preserves whatever
##                     the scene gave the node — UIListModalWindow's Name column).
##   hide_when_empty — If true and value is empty, hide the existing node and skip
##                     creation. Returns the existing node (or null) so callers can
##                     observe the hidden state if they care.
static func paint(
		parent: Node3D,
		child_name: StringName,
		value: String,
		host_ppu: float,
		column_scale: float,
		palette: int,
		space_width: float,
		offset_x_px: float,
		hide_when_empty: bool = false) -> UIText:
	var existing := parent.get_node_or_null(NodePath(child_name)) as UIText
	if hide_when_empty and value.is_empty():
		if existing:
			existing.visible = false
		return existing

	var node: UIText = existing
	if not node:
		node = UIText.new()
		node.name = child_name
		parent.add_child(node)

	if node.text != value:
		node.text = value
	node.pixels_per_unit = host_ppu * column_scale
	node.space_width = space_width
	node.set_palette(palette)
	if not is_nan(offset_x_px):
		node.position.x = offset_x_px * host_ppu
	node.visible = true
	return node
