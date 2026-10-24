## GameSettings — global autoload for the saved gameplay choices, kept apart
## from AudioSettings so each owns its own section of the settings file.
extends Node

const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "game"
## Longest name shown at the table. Short enough for "<name> wins!" to fit on
## one line of the final scores.
const MAX_NAME_LENGTH := 12

## How hard the bots are, 0..1. One number moves three things at once: a harder
## bot forgets its cards more slowly, needs a smaller edge before it acts, and
## stops throwing the odd move away. See [CardBot].
var bot_difficulty: float = 0.5
## The name the other players see online. Empty shows as "Player N".
var player_name: String = ""


func _ready() -> void:
	load_settings()


func set_bot_difficulty(value: float) -> void:
	bot_difficulty = clampf(value, 0.0, 1.0)


func set_player_name(value: String) -> void:
	player_name = clean_name(value)


## A name as the table shows it: printable characters only, trimmed, and cut to
## MAX_NAME_LENGTH. Online, names arrive from other players' devices, so the
## host runs every one through this rather than trusting it.
static func clean_name(raw_name: String) -> String:
	var printable := ""
	for character in raw_name:
		var code := character.unicode_at(0)
		if code >= 32 and code != 127:
			printable += character
	return printable.strip_edges().left(MAX_NAME_LENGTH).strip_edges()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return

	bot_difficulty = clampf(config.get_value(CONFIG_SECTION, "bot_difficulty", bot_difficulty), 0.0, 1.0)
	player_name = clean_name(str(config.get_value(CONFIG_SECTION, "player_name", player_name)))


## Called when the settings panel closes, rather than on every slider step.
func save_settings() -> void:
	var config := ConfigFile.new()
	# The audio section lives in the same file, so it is read back in first
	# rather than being written over.
	config.load(CONFIG_PATH)
	config.set_value(CONFIG_SECTION, "bot_difficulty", bot_difficulty)
	config.set_value(CONFIG_SECTION, "player_name", player_name)
	config.save(CONFIG_PATH)
