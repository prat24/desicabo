## BoardCard — a card displayed on the board (center draw slot or discard pile).
## Supports face-up/face-down state, a flip animation, and mouse hover signals.
extends Node2D
class_name BoardCard

signal hovered(card: Node2D)
signal hovered_off(card: Node2D)

@export var back_texture: Texture2D

var rank := ""
var suit := ""
var front_texture: Texture2D
var is_face_up := true
var can_drag := false

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	var parent_node := get_parent()
	if parent_node.has_method("connect_card_signals"):
		parent_node.connect_card_signals(self)


func _on_area_2d_mouse_entered() -> void:
	hovered.emit(self)


func _on_area_2d_mouse_exited() -> void:
	hovered_off.emit(self)


func setup_card(card_rank: String, card_suit: String, card_texture: Texture2D) -> void:
	rank = card_rank
	suit = card_suit
	front_texture = card_texture


func show_back() -> void:
	is_face_up = false
	sprite.texture = back_texture


func show_front() -> void:
	is_face_up = true
	sprite.texture = front_texture


func flip_to_front(enable_drag_after := true) -> void:
	can_drag = false
	show_back()
	animation_player.play("flip_to_front")
	await get_tree().create_timer(0.17).timeout
	show_front()
	await animation_player.animation_finished
	can_drag = enable_drag_after


func get_card_name() -> String:
	return suit + " " + rank
