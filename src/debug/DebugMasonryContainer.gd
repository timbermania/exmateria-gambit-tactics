@tool
class_name DebugMasonryContainer
extends Container
## Masonry layout (Pinterest / Tumblr packing). N uniform-width columns whose
## width is the widest visible cell (clamped into [min_column_width,
## max_column_width]) so a wide cell never spills sideways into its neighbour;
## the column count then follows from how many such columns fit. Each child is
## placed at the top of the SHORTEST column at the moment of placement, so a
## short cell does not leave dead space below it — the next cell drops in to
## fill the gap. Wraps responsively as the container resizes.
##
## Built for the DebugDashboard's cell-of-panels case; not parameterized
## for general reuse. Lives in src/debug/ to keep that signaling clear.

@export var min_column_width: int = 280:
	set(value):
		if min_column_width == value:
			return
		min_column_width = value
		queue_sort()

## Upper bound for the auto-widened column. Columns grow to fit the widest
## visible cell (so panels never spill sideways into the neighbour), but a
## single pathological panel is not allowed to inflate every column past this
## — it overflows on its own instead of collapsing the whole layout. Keep this
## comfortably above the widest real panel's natural width.
@export var max_column_width: int = 600:
	set(value):
		if max_column_width == value:
			return
		max_column_width = value
		queue_sort()

@export var h_separation: int = 12:
	set(value):
		if h_separation == value:
			return
		h_separation = value
		queue_sort()

@export var v_separation: int = 12:
	set(value):
		if v_separation == value:
			return
		v_separation = value
		queue_sort()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_arrange()


func _arrange() -> void:
	var available_width: float = size.x
	if available_width <= 0:
		return

	# Column width must be at least as wide as the widest cell wants to be —
	# otherwise fit_child_in_rect honours the cell's own minimum width and the
	# cell bursts out of its column, overlapping the next column (the panels
	# here carry non-wrapping content up to ~520px wide). So the effective
	# minimum column width is the widest visible cell, clamped into
	# [min_column_width, max_column_width].
	var widest_child: float = 0.0
	for child in get_children():
		if child is Control and child.visible:
			widest_child = max(widest_child, (child as Control).get_combined_minimum_size().x)
	var col_min: float = clampf(widest_child, float(min_column_width), float(max_column_width))

	# How many uniform columns fit. Each column takes col_min + a separation
	# gap on its right (except the rightmost which has no gap). Columns then
	# stretch to divide the leftover space evenly, so column_width >= col_min.
	var per_col_with_gap: float = col_min + float(h_separation)
	var n_cols: int = max(1, int((available_width + h_separation) / per_col_with_gap))
	var column_width: float = (available_width - float(n_cols - 1) * h_separation) / float(n_cols)

	# Running height of each column (the y at which the next cell in that
	# column would be placed).
	var column_heights: Array[float] = []
	column_heights.resize(n_cols)
	column_heights.fill(0.0)

	for child in get_children():
		if not (child is Control):
			continue
		var control: Control = child
		if not control.visible:
			continue

		# Pick the column with the smallest current height — that's where the
		# next cell drops. Ties break to the leftmost (the loop runs L→R and
		# only updates on strict <).
		var shortest_idx: int = 0
		for i in range(1, n_cols):
			if column_heights[i] < column_heights[shortest_idx]:
				shortest_idx = i

		# Constrain the child to column_width horizontally, let its own
		# get_combined_minimum_size compute its height at that width.
		var child_min: Vector2 = control.get_combined_minimum_size()
		var child_height: float = max(child_min.y, 0.0)
		var x: float = float(shortest_idx) * (column_width + float(h_separation))
		var y: float = column_heights[shortest_idx]
		fit_child_in_rect(control, Rect2(x, y, column_width, child_height))

		column_heights[shortest_idx] += child_height + float(v_separation)

	# Report our own minimum height so the parent ScrollContainer knows how
	# tall the content is.
	var max_height: float = 0.0
	for h in column_heights:
		max_height = max(max_height, h)
	custom_minimum_size = Vector2(custom_minimum_size.x, max_height)


func _get_minimum_size() -> Vector2:
	return Vector2(float(min_column_width), 0.0)
