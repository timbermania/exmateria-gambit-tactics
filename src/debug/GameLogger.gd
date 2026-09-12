extends Node

## Centralized logging system with categories and levels
##
## Accessed as GameLogger autoload singleton.
##
## Usage:
##   GameLogger.debug(GameLogger.Category.CAMERA, "Camera moved", {"unit": unit})
##   GameLogger.info(GameLogger.Category.ANIMATION, "Animation complete")
##   GameLogger.error(GameLogger.Category.MAP, "Failed to load map")

enum Level {
	DEBUG,   # Detailed step-by-step logs
	INFO,    # High-level events
	WARN,    # Warnings (not errors)
	ERROR    # Critical errors
}

enum Category {
	ANIMATION,  # Animation system
	EFFECT,     # Visual effect system
	CAMERA,     # Camera system
	MAP         # Procedural map loading
}

# Configuration: Which categories/levels to show
# Set to DEBUG to see all logs for that category
# Set to ERROR to see only critical errors
# Default: Only CAMERA enabled, all others quiet
var enabled_levels: Dictionary = {
	Category.ANIMATION: Level.ERROR,
	Category.EFFECT: Level.ERROR,
	Category.CAMERA: Level.DEBUG,
	Category.MAP: Level.ERROR
}

# Master toggle (controlled by DebugConfig for backwards compatibility)
var logging_enabled: bool = true

func _ready():
	# Sync with DebugConfig for backwards compatibility
	if DebugConfig:
		DebugConfig.debug_settings_changed.connect(_on_debug_settings_changed)
		_on_debug_settings_changed()

func _on_debug_settings_changed():
	"""Sync Logger levels with DebugConfig flags"""
	if DebugConfig.camera_debug_enabled:
		enabled_levels[Category.CAMERA] = Level.DEBUG
	else:
		enabled_levels[Category.CAMERA] = Level.ERROR

	if DebugConfig.map_debug_enabled:
		enabled_levels[Category.MAP] = Level.DEBUG
	else:
		enabled_levels[Category.MAP] = Level.ERROR

func log_message(category: Category, level: Level, message: String, context: Dictionary = {}):
	"""Main logging method with category, level, and context

	Args:
		category: Which system is logging (MOVEMENT, COMBAT, etc.)
		level: Log level (DEBUG, INFO, WARN, ERROR)
		message: The log message
		context: Optional context like {"unit": unit, "target": target}
	"""
	if not logging_enabled:
		return

	if not _should_log(category, level):
		return

	var prefix = _get_prefix(category, level, context)
	print(prefix + message)

func _should_log(category: Category, level: Level) -> bool:
	"""Check if log should be printed based on configuration"""
	if not enabled_levels.has(category):
		return false
	return level >= enabled_levels[category]

func _get_prefix(category: Category, level: Level, context: Dictionary) -> String:
	"""Build log prefix with category, level, and context"""
	var parts = []

	# Category (always shown)
	parts.append("[%s]" % Category.keys()[category])

	# Level (only if not INFO)
	if level != Level.INFO:
		parts.append("[%s]" % Level.keys()[level])

	# Context: unit name if present
	if context.has("unit") and context.unit:
		parts.append(context.unit.name)

	return " ".join(parts) + ": "

## Convenience Methods

func debug(category: Category, message: String, context: Dictionary = {}):
	"""Log at DEBUG level (most verbose)"""
	log_message(category, Level.DEBUG, message, context)

func info(category: Category, message: String, context: Dictionary = {}):
	"""Log at INFO level (high-level events)"""
	log_message(category, Level.INFO, message, context)

func error(category: Category, message: String, context: Dictionary = {}):
	"""Log at ERROR level (critical errors)"""
	log_message(category, Level.ERROR, message, context)

## Configuration API
