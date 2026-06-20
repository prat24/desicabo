## MainMenu — title screen; pressing Play loads the game.
extends Control

const GAME_SCENE_PATH := "res://Scenes/Managers/game_manager.tscn"

@onready var play_button: Button = $Playbutton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
