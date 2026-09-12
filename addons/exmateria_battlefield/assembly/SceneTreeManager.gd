extends RefCounted

## Manages tile nodes in the scene tree.
##
## Responsibilities:
## - Create and own tile_container Node3D
## - Add tiles to scene tree
## - Remove tiles from scene tree
## - Batch operations for doodad placement/removal
##
## Extracted from MapComposer to separate scene tree management
## from high-level doodad orchestration.

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const Tile = preload("res://addons/exmateria_battlefield/lattice/Tile.gd")


var _tile_container: Node3D
var _parent_node: Node3D  # Reference to MapComposer


## Initialize with parent node (MapComposer).
##
## Args:
##     parent: Node3D that will own the tile_container
func initialize(parent: Node3D) -> void:
	_parent_node = parent
	_tile_container = Node3D.new()
	_tile_container.name = "Tiles"
	_parent_node.add_child(_tile_container)


## Add tiles to scene tree.
##
## Args:
##     tiles: Array of Tile nodes to add
func add_tiles(tiles: Array[Tile]) -> void:
	if not is_instance_valid(_tile_container):
		return
	for tile in tiles:
		_tile_container.add_child(tile)


## Detach tiles from scene tree without deletion.
func detach_tiles(tiles: Array[Tile]) -> void:
	if not is_instance_valid(_tile_container):
		return
	for tile in tiles:
		if tile and tile.is_inside_tree():
			_tile_container.remove_child(tile)


## Clear all tiles from scene tree.
func clear_all() -> void:
	if not is_instance_valid(_tile_container):
		return
	for child in _tile_container.get_children():
		_tile_container.remove_child(child)
		child.queue_free()
