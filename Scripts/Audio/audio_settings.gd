## AudioSettings — global autoload owning the Music and SFX mixer buses and
## the player's saved volume choices. Volumes are 0..1 sliders; 1.0 means the
## game's designed mix (0 dB on the bus), and 0 mutes the bus entirely.
extends Node

const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "audio"
## Below this a slider counts as off, since linear_to_db(0) is -inf.
const SILENCE_THRESHOLD := 0.001

## Sliders start at half, leaving headroom to turn things up.
var music_volume: float = 0.5
var sfx_volume: float = 0.5


func _ready() -> void:
	ensure_bus(AudioBuses.MUSIC)
	ensure_bus(AudioBuses.SFX)
	load_settings()
	apply_bus_volume(AudioBuses.MUSIC, music_volume)
	apply_bus_volume(AudioBuses.SFX, sfx_volume)


## Buses are created in code so the project needs no bus-layout resource.
func ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return

	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, AudioBuses.MASTER)


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	apply_bus_volume(AudioBuses.MUSIC, music_volume)


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	apply_bus_volume(AudioBuses.SFX, sfx_volume)


func apply_bus_volume(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return

	AudioServer.set_bus_mute(index, value <= SILENCE_THRESHOLD)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, SILENCE_THRESHOLD)))


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return

	music_volume = clampf(config.get_value(CONFIG_SECTION, "music_volume", music_volume), 0.0, 1.0)
	sfx_volume = clampf(config.get_value(CONFIG_SECTION, "sfx_volume", sfx_volume), 0.0, 1.0)


## Called when the settings panel closes, rather than on every slider step.
func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(CONFIG_SECTION, "music_volume", music_volume)
	config.set_value(CONFIG_SECTION, "sfx_volume", sfx_volume)
	config.save(CONFIG_PATH)
