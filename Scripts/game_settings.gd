## GameSettings — global autoload for the saved gameplay choices, kept apart
## from AudioSettings so each owns its own section of the settings file.
extends Node

const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "game"

## How hard the bots are, 0..1. One number moves three things at once: a harder
## bot forgets its cards more slowly, needs a smaller edge before it acts, and
## stops throwing the odd move away. See [CardBot].
var bot_difficulty: float = 0.5


func _ready() -> void:
	load_settings()


func set_bot_difficulty(value: float) -> void:
	bot_difficulty = clampf(value, 0.0, 1.0)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return

	bot_difficulty = clampf(config.get_value(CONFIG_SECTION, "bot_difficulty", bot_difficulty), 0.0, 1.0)


## Called when the settings panel closes, rather than on every slider step.
func save_settings() -> void:
	var config := ConfigFile.new()
	# The audio section lives in the same file, so it is read back in first
	# rather than being written over.
	config.load(CONFIG_PATH)
	config.set_value(CONFIG_SECTION, "bot_difficulty", bot_difficulty)
	config.save(CONFIG_PATH)
