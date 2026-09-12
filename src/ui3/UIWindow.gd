@tool
class_name UIWindow
extends UIComponent

## Base for any combat-UI **window** — a panel dialed into a fixed screen
## position that the host ([UIWindowHost]) places. Owns the one piece of
## state every window shares: its `screen_pos`. Modal windows extend the
## [UIModalWindow] subtype for lifecycle on top of this. The single source of
## truth for a window's position is the .tscn that authors `screen_pos`; the
## default below is a deliberately-neutral sentinel (dead centre) so a window
## that forgot to author one is obvious on screen rather than silently
## inheriting some other type's value. See CONTEXT.md "Combat UI windows".

## Normalized screen position (0,0 = top-left, 1,1 = bottom-right). Authored
## per node in the scene; the host converts it to a world position each layout.
@export var screen_pos: Vector2 = Vector2(0.5, 0.5):
	set(value):
		if screen_pos == value:
			return
		screen_pos = value
