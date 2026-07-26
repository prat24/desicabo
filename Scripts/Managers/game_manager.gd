## GameManager — runs the full game loop: dealing, turns, drag-and-drop,
## special card powers, scoring, and animations.
##
## The same loop runs a hotseat game on one phone and a networked game on
## several. Online, the host owns the game: it holds the deck, decides what
## every move does, and sends each device the same sequence of "steps" to
## animate — with only the cards that device's player is allowed to see. The
## board itself is identical everywhere (Player 2 turns their phone upside
## down, Player 3 turns theirs sideways), so a step is just player numbers,
## slot numbers, and card ranks. See step(), private_step() and personal_step().
extends Node2D

const CARD_COLLISION_MASK = 1
## Cards resting on the board — the deck and discard piles — are drawn smaller
## than the ones in a hand, which leaves the hands room to fan out without
## piling up. Must stay in step with the DeckSprite/DiscardPileSprite scale in
## the scene (they are bare sprites, so their scale is this times the card
## sprite's 2). A card only travels between this size and a hand's size, never
## jumping: see board_card_rest_scale().
const NORMAL_CARD_SCALE = Vector2(1.05, 1.05)
## How much a hovered board card swells past whatever size it is resting at.
const HOVER_SCALE_MULTIPLIER = 1.05
const SNAP_TIME = 0.18
const DEAL_FLY_TIME = 0.28
const DEAL_STAGGER_TIME = 0.07
const DISCARD_FLY_TIME = 0.34
const SWAP_FLY_TIME = 0.4
## Horizontal offset of the deck and discard slots from the screen center. Far
## enough out that the hand-sized drawn card fits between the two piles.
const BOARD_SLOT_OFFSET_X = 375.0

# ── Hand sizing — a fan of three cards has to fit the screen's short edge, so
# the cards shrink a step for every player who joins the same table. Spacing
# always steps down with the card size, keeping one fan shape at every count:
# same arc, same overlap, never a row of spread-out cards. ────────────────────
const HAND_CARD_SCALE_2P = Vector2(1.4, 1.4)
const HAND_CARD_SCALE_3P = Vector2(1.25, 1.25)
const HAND_CARD_SCALE_4P = Vector2(1.03, 1.03)
const HAND_SPACING_2P = 290.0
const HAND_SPACING_3P = 259.0
const HAND_SPACING_4P = 213.0
const HAND_ARC_HEIGHT = 55.0
const HAND_MAX_ROTATION_DEGREES = 10.0
## How far a hand's center sits from the screen edge it hugs.
const HAND_EDGE_OFFSET_2P = 240.0
const HAND_EDGE_OFFSET_3P = 235.0
## Four hands is tight, so the bottom and top ones tuck further past their edge.
const HAND_EDGE_OFFSET_4P = 150.0
## The two hands sharing the right edge hug it tightly: together with the side
## split below, that keeps their fans clear of the bottom and top hands entirely,
## so each one is free to use its own half of the screen's full height.
const HAND_RIGHT_EDGE_OFFSET_4P = 160.0
## Players 1 and 2 sit at the left corners in a four-player game, so their whole
## hands tilt — which also swings each fan's far end clear of the right-side hand
## nearest it (Player 4 below, Player 3 above).
const HAND_TILT_4P = 12.0
## Where both tilted fans are centered horizontally (the viewport is always 1080
## wide; only its height varies by device). Far enough in from the corner that the
## corner-most card of each fan clears the side edge, and no further: the fan's
## other end has to stop short of the two hands sharing the right edge.
const HAND_CORNER_CENTER_X_4P = 375.0
## How far from the screen's middle each right-side hand sits, as a fraction of
## the height. A quarter would center each in its own half; slightly less than
## that closes the gap between the two of them.
const HAND_RIGHT_SPLIT_4P = 0.21
## Special-power dim overlay z-index; the selectable hand is raised above it.
const OVERLAY_Z_INDEX = 150
const RAISED_HAND_Z_INDEX = 200
# ── Turn-spotlight layers: dark overlay, active hand above it, board cards on
# top (the drawn card is always the topmost thing on screen). ────────────────
const TURN_FOCUS_OVERLAY_Z = 100
const FOCUSED_HAND_Z = 110
const FOCUSED_DISCARD_Z = 230
const FLYING_CARD_Z = 240
const FOCUSED_DRAW_CARD_Z = 250
## How far the drawn card steps away from screen center in 3-player mode so
## it never covers the tappable discard pile.
const DRAW_CARD_TURN_OFFSET = 160.0
## Online, the note telling a waiting player whose turn it is. It sits this far
## from the middle of the board, in the gap before that player's own hand.
const TURN_WAIT_LABEL_HEIGHT = 80.0
const TURN_WAIT_LABEL_BAND = 300.0
## How often the active player's device sends the card it is dragging to the
## others — often enough to look live, rarely enough to be nothing on a LAN.
const NET_DRAG_INTERVAL = 0.05
const MAIN_MENU_SCENE = "res://Scenes/UI/main_menu.tscn"

const UI_THEME = preload("res://Assets/Themes/clean_ui.tres")

@export_range(0.0, 15.0, 0.1) var pre_game_reveal_time: float = 4.0
@export_range(0.1, 0.8, 0.01) var initial_deal_fly_time: float = DEAL_FLY_TIME
@export_range(0.0, 0.3, 0.01) var initial_deal_stagger: float = DEAL_STAGGER_TIME
@export_range(0.0, 1.0, 0.01) var pre_game_dim_alpha: float = 0.35
@export_range(0.05, 1.5, 0.01) var player_card_flip_time: float = 0.24
## Reveals flip cards up much faster than they flip back down.
@export_range(0.05, 0.5, 0.01) var quick_flip_up_time: float = 0.12
@export_range(0.5, 10.0, 0.1) var reveal_prompt_time: float = 5.0
## Quick "Player X's turn" flash at the start of every turn.
@export_range(0.2, 5.0, 0.1) var turn_prompt_time: float = 1.5

enum TurnState {
	DEALING,
	WAITING_FOR_DROP,
	ANIMATING,
	SPECIAL_7,
	CHOOSING_PLAYER,
	GAME_OVER
}

## What a player's drop meant. The active player's device works this out and
## the host is the one that carries it out, so it has to survive the wire.
enum Move {
	SWAP_DRAWN,     ## Drawn card into one of my slots.
	DISCARD_DRAWN,  ## Drawn card straight onto the pile.
	RETURN_DRAWN,   ## Dropped nowhere — put it back and think again.
	TAKE_DISCARD,   ## Pile's top card into one of my slots.
	RETURN_DISCARD, ## Picked the pile up and put it back.
}

var turn_state: TurnState = TurnState.DEALING
var deck: Array[Dictionary] = []
var player_count: int = 2
var current_player: int = 1  ## Whose turn it is (1..player_count).

var screen_size: Vector2
var center_draw_position: Vector2 = Vector2.ZERO
var discard_pile_position: Vector2 = Vector2.ZERO

var dragged_card: BoardCard
var hovered_player_card: PlayerCard
## Card picking (7 power, player choice) acts on release, not press: on a
## phone, holding a finger on a card is how the player hovers it.
var pointer := TapGesture.new()
var pointer_press_state: TurnState = TurnState.DEALING

var intro_dim_overlay: ColorRect
var special_overlay: ColorRect
var game_over_overlay: ColorRect
var turn_focus_overlay: ColorRect
var is_returning_to_menu := false

# ── Online play (all inert in a hotseat game) ─────────────────────────────────
## Set from Net at load. False puts every path below back on its local
## behaviour, so the hotseat game is unchanged.
var online := false
## Which player this device is, 1..player_count. 0 in a hotseat game, where the
## one screen belongs to whoever's turn it is.
var my_seat := 0
## Steps arrive faster than they animate, so they wait their turn here instead
## of playing on top of each other.
var net_step_queue: Array = []
var net_step_running := false
## Peers whose board is up and ready to be dealt to (host side).
var ready_peers: Array[int] = []
## Client side: the host has heard us, so we can stop announcing ourselves.
var handshake_done := false
## The card that was drawn this turn, as the host knows it — its own screen
## keeps that card face down on everyone else's turn, so the node cannot be
## asked what it is.
var current_draw: Dictionary = {}
## The active player's 7-power picks: [own slot, opponent slot] once chosen.
var seven_choice: Array[int] = []
var seven_skipped := false
## True only while the host is waiting for those picks.
var awaiting_seven := false
## Throttles the drag position the active player streams to the other devices.
var net_drag_timer := 0.0
## Standing "Player N's turn…" note shown to the players who are not up.
var turn_wait_label: Label

# ── Seven-power selection state ───────────────────────────────────────────────
var selected_source_card: PlayerCard = null
var hovered_special_card: PlayerCard = null
var seven_selecting_opponent: bool = false
var seven_skip_button: Button
## The opponent hand a K/J/7 power acts on this turn.
var seven_target_hand: PlayerHand
## Player picked during CHOOSING_PLAYER (0 while undecided).
var chosen_target_player: int = 0

var sfx_place: AudioStreamPlayer
var sfx_slide: AudioStreamPlayer

# ── Scene references ──────────────────────────────────────────────────────────
@onready var deck_sprite: Sprite2D = $DeckSprite
@onready var center_draw_card: BoardCard = $CenterDrawCard
@onready var discard_pile_sprite: Sprite2D = $DiscardPileSprite
@onready var discard_top_card: BoardCard = $DiscardTopCard
## Animation-only card for flights to the discard pile, so the pile's top card
## stays visible until the new card actually lands on it.
@onready var flying_card: BoardCard = $FlyingCard
@onready var player1_hand: PlayerHand = $PlayerHand
@onready var player2_hand: PlayerHand = $Player2Hand
@onready var player3_hand: PlayerHand = $Player3Hand
@onready var player4_hand: PlayerHand = $Player4Hand


func _ready() -> void:
	online = Net.is_online
	my_seat = Net.local_player if online else 0
	player_count = clampi(GameConfig.player_count, 2, 4)
	screen_size = get_viewport_rect().size
	layout_board_for_screen()
	center_draw_position = center_draw_card.global_position
	discard_pile_position = discard_pile_sprite.global_position
	center_draw_card.visible = false
	discard_top_card.visible = false
	flying_card.visible = false
	flying_card.get_node("Area2D").input_pickable = false
	flying_card.get_node("Area2D/CollisionShape2D").disabled = true
	set_discard_takeable(false)
	setup_board_card_shaders()
	center_draw_card.hovered.connect(on_board_card_hovered)
	center_draw_card.hovered_off.connect(on_board_card_hovered_off)
	discard_top_card.hovered.connect(on_board_card_hovered)
	discard_top_card.hovered_off.connect(on_board_card_hovered_off)
	setup_audio()
	fade_in_from_black()

	if online:
		Net.connection_lost.connect(on_connection_lost)
		if not is_host():
			# Everything a client shows arrives as a step from the host.
			await report_ready_to_host()
			return
		await wait_for_players()

	deck = CardDeck.create_shuffled_deck()
	await deal_initial_hands_animated()
	await run_pre_game_reveals()
	await start_turn()


# ── Online: who is in charge ──────────────────────────────────────────────────

## The host runs the game and tells the other devices what to show. A hotseat
## game has no network at all, so it is its own host.
func is_host() -> bool:
	return not online or multiplayer.is_server()


## Whether this device may act right now. The one screen of a hotseat game
## always belongs to the active player.
func is_my_turn() -> bool:
	return not online or current_player == my_seat


## The host may still be loading its own board, and an RPC that lands before
## its target node exists is dropped — so keep saying we are here until it
## answers.
func report_ready_to_host() -> void:
	while not handshake_done:
		rpc_id(1, "net_player_ready")
		await get_tree().create_timer(0.25).timeout


func wait_for_players() -> void:
	while ready_peers.size() < player_count - 1:
		await get_tree().process_frame


@rpc("any_peer", "call_remote", "reliable")
func net_player_ready() -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not ready_peers.has(sender):
		ready_peers.append(sender)
	rpc_id(sender, "net_ready_acknowledged")


@rpc("authority", "call_remote", "reliable")
func net_ready_acknowledged() -> void:
	handshake_done = true


# ── Online: steps ─────────────────────────────────────────────────────────────

## Run one visible move on every device: the host performs it locally and sends
## the same call out, so all the boards animate together. Only plain data goes
## over the wire — a card is a rank and a suit, and an empty rank means "this
## device is not allowed to know", which leaves the card face down.
func step(method: StringName, args: Array = []) -> void:
	if online and is_host():
		rpc("net_step", method, args)
	await callv(method, args)


## A step that puts a card somewhere face down. Everyone gets the same
## animation; only the players in `entitled` are told what the card is. The
## host always uses the real data, since its copy of the hands is the game.
func private_step(method: StringName, true_args: Array, hidden_args: Array, entitled: Array) -> void:
	if online and is_host():
		var others := Net.remote_seats()
		for peer_id: int in others:
			rpc_id(peer_id, "net_step", method, true_args if int(others[peer_id]) in entitled else hidden_args)
	await callv(method, true_args)


## A step that turns a card face up, where even the host must be kept in the
## dark on someone else's turn: `args_for` is asked, per player, what that
## player may see. Nothing here writes to the host's copy of a hand, so being
## shown nothing costs it nothing.
func personal_step(method: StringName, args_for: Callable) -> void:
	if online and is_host():
		var others := Net.remote_seats()
		for peer_id: int in others:
			rpc_id(peer_id, "net_step", method, args_for.call(int(others[peer_id])))
	await callv(method, args_for.call(my_seat))


@rpc("authority", "call_remote", "reliable")
func net_step(method: StringName, args: Array) -> void:
	# The host is the only caller, but nothing outside the step_ family is ever
	# a legitimate thing to be told to run.
	if not String(method).begins_with("step_"):
		return

	net_step_queue.append([method, args])
	if net_step_running:
		return

	# ENet delivers these in order; each one animates, so they play one after
	# another rather than all at once.
	net_step_running = true
	while not net_step_queue.is_empty():
		var next: Array = net_step_queue.pop_front()
		await callv(next[0], next[1])
	net_step_running = false


## A card in the form the animation code wants it. An empty rank is a card this
## device may not see: no texture, so it stays face down.
func make_card(rank: String, suit: String) -> Dictionary:
	if rank.is_empty():
		return {"rank": "", "suit": "", "texture": null}
	return {
		"rank": rank,
		"suit": suit,
		"texture": load(CardDeck.get_card_texture_path(suit, rank)),
	}


func hand_ranks(player: int) -> Array:
	var ranks: Array = []
	for card in get_hand(player).cards:
		ranks.append(card.rank)
	return ranks


func hand_suits(player: int) -> Array:
	var suits: Array = []
	for card in get_hand(player).cards:
		suits.append(card.suit)
	return suits


## Anchor the board to the real screen size: the scene is authored for
## 1080x1920, but stretch aspect "expand" makes the viewport taller on modern
## phones. Two players: middle row centered, Player 2 pinned to the top.
## Three or more: the board becomes a sideways column on the left, and the
## right edge belongs to Player 3 (and Player 4, who sits beside them).
func layout_board_for_screen() -> void:
	var center: Vector2 = screen_size * 0.5
	player2_hand.position = screen_size
	player3_hand.visible = player_count >= 3
	player4_hand.visible = player_count >= 4
	apply_hand_sizing()

	if player_count >= 3:
		for hand: PlayerHand in [player3_hand, player4_hand]:
			hand.position = Vector2(0.0, screen_size.y)
			hand.rotation_degrees = -90.0

		# Deck and discard sit close together in a sideways column on the
		# left; the drawn card goes to the screen center, oriented per turn.
		var column_x := 240.0
		for board_node: Node2D in [deck_sprite, discard_pile_sprite, discard_top_card, flying_card]:
			board_node.rotation_degrees = 90.0
		deck_sprite.position = Vector2(column_x, center.y - 180.0)
		center_draw_card.position = center
		discard_pile_sprite.position = Vector2(column_x, center.y + 180.0)
	else:
		deck_sprite.position = Vector2(center.x - BOARD_SLOT_OFFSET_X, center.y)
		center_draw_card.position = center
		discard_pile_sprite.position = Vector2(center.x + BOARD_SLOT_OFFSET_X, center.y)

	discard_top_card.position = discard_pile_sprite.position


## The size a card takes in the active player's hand. Everything that travels
## into or out of a hand tweens between this and NORMAL_CARD_SCALE, so a card
## never changes size in a single frame.
func hand_card_scale() -> Vector2:
	return get_active_hand().card_scale


## Where a board card sits when nothing is happening to it. The drawn card is
## already on its way to a hand, so it rests at hand size the moment it leaves
## the deck; the discard pile's top card rests at the pile's size and only grows
## once the player picks it up.
func board_card_rest_scale(card: BoardCard) -> Vector2:
	return hand_card_scale() if card == center_draw_card else NORMAL_CARD_SCALE


## Size and place every hand for the current player count. Each setter
## re-arranges the fan, so the cards pick the new layout up with no extra call.
func apply_hand_sizing() -> void:
	var hand_scale := HAND_CARD_SCALE_2P
	var spacing := HAND_SPACING_2P
	var edge_offset := HAND_EDGE_OFFSET_2P
	match player_count:
		3:
			hand_scale = HAND_CARD_SCALE_3P
			spacing = HAND_SPACING_3P
			edge_offset = HAND_EDGE_OFFSET_3P
		4:
			hand_scale = HAND_CARD_SCALE_4P
			spacing = HAND_SPACING_4P
			edge_offset = HAND_EDGE_OFFSET_4P

	for hand: PlayerHand in [player1_hand, player2_hand, player3_hand, player4_hand]:
		hand.card_scale = hand_scale
		hand.card_spacing = spacing
		hand.arc_height = HAND_ARC_HEIGHT
		hand.max_rotation_degrees = HAND_MAX_ROTATION_DEGREES
		hand.bottom_offset = edge_offset
		hand.top_offset = edge_offset
		hand.edge_shift = 0.0

	if player_count == 4:
		place_four_player_hands()


## Four hands, four corners of the screen. Players 3 and 4 share the right edge,
## so the other two clear out of the right entirely: Player 1 tilts into the
## bottom-left corner and Player 2 into the top-left one, each fan's far end
## swinging away from the right-side hand beside it. With nothing else reaching
## that far right, the two right-side hands have the screen's whole height to
## split between them — which is what keeps them apart on a short viewport as
## well as a tall one.
func place_four_player_hands() -> void:
	# The two corner fans are mirror images across the screen's middle: same
	# distance in from the left edge and from their own edge, opposite tilts.
	# Player 2 hangs upside down, so the mirrored tilt is a half-turn less than
	# Player 1's rather than more. Both fans are placed outright, which is why
	# neither needs the edge shift apply_hand_sizing() just cleared.
	place_hand_at(
		player1_hand,
		Vector2(HAND_CORNER_CENTER_X_4P, screen_size.y - HAND_EDGE_OFFSET_4P),
		HAND_TILT_4P
	)
	place_hand_at(
		player2_hand,
		Vector2(HAND_CORNER_CENTER_X_4P, HAND_EDGE_OFFSET_4P),
		180.0 - HAND_TILT_4P
	)

	for hand: PlayerHand in [player3_hand, player4_hand]:
		hand.bottom_offset = HAND_RIGHT_EDGE_OFFSET_4P
	player3_hand.edge_shift = screen_size.y * HAND_RIGHT_SPLIT_4P
	player4_hand.edge_shift = -screen_size.y * HAND_RIGHT_SPLIT_4P


## Put `hand`'s fan center on `center_global`, tilted. The node pivots about its
## own origin — a screen corner, far from the fan — so the position has to absorb
## the offset that rotating introduces. Card positions are local, so they follow
## along with no re-arrange.
func place_hand_at(hand: PlayerHand, center_global: Vector2, tilt_degrees: float) -> void:
	hand.rotation_degrees = tilt_degrees
	hand.position = center_global - hand.transform.basis_xform(hand.fan_center())


## Smooth arrival from the title screen: it fades to black before the scene
## change, so this scene starts black and fades in while the deal begins.
func fade_in_from_black() -> void:
	var fade := create_fullscreen_overlay(1.0, 500)
	var fade_tween := create_tween()
	fade_tween.tween_property(fade, "color:a", 0.0, 0.4)
	fade_tween.tween_callback(fade.queue_free)


func setup_board_card_shaders() -> void:
	CardShader.apply(deck_sprite, 12.0)
	CardShader.apply(discard_pile_sprite, 24.0)
	CardShader.set_inset(deck_sprite, 0.03)
	CardShader.set_inset(discard_pile_sprite, 0.03)


func setup_audio() -> void:
	sfx_place = CardSfx.create_place_player()
	sfx_slide = CardSfx.create_slide_player()
	add_child(sfx_place)
	add_child(sfx_slide)


## The two card cues. `slide` goes on the frame a card starts moving, `place`
## on the frame it lands — both are called next to the tween they belong to,
## never on a separate timer, so the audio cannot drift from the animation.
func play_place_sound() -> void:
	sfx_place.play()


func play_slide_sound() -> void:
	sfx_slide.play()


func deal_initial_hands_animated() -> void:
	await step("step_prepare_deal")

	var slots_per_hand: int = player1_hand.cards.size()
	for slot in range(slots_per_hand):
		for player in range(1, player_count + 1):
			if deck.is_empty():
				return

			var dealt: Dictionary = deck.pop_front()
			# Dealt face down, and nobody is told what it is — not even the
			# player getting it. The opening peek is what turns these up.
			await private_step(
				"step_deal_card",
				[player, slot, dealt["rank"], dealt["suit"]],
				[player, slot, "", ""],
				[]
			)


func step_prepare_deal() -> void:
	turn_state = TurnState.DEALING
	var deck_pos: Vector2 = deck_sprite.global_position
	for hand in get_all_hands():
		hand.arrange_cards()
		hand.stack_cards_at_deck(deck_pos, deck_sprite.rotation_degrees, deck_sprite.scale)


func step_deal_card(player: int, slot: int, rank: String, suit: String) -> void:
	await get_hand(player).animate_deal_card(
		slot,
		make_card(rank, suit),
		deck_sprite.global_position,
		initial_deal_fly_time,
		deck_sprite.scale,
		deck_sprite.rotation_degrees
	)
	play_place_sound()
	if initial_deal_stagger > 0.0:
		await get_tree().create_timer(initial_deal_stagger).timeout


## Every player peeks at their hand before Player 1's first turn; a prompt
## before each reveal warns the other player(s) to look away. Online there is
## nobody to look away — each player has their own screen — so all the peeks
## happen at once, each phone turning up its own player's hand.
func run_pre_game_reveals() -> void:
	if online:
		await step("step_prompt_everyone", ["Memorise your cards!", turn_prompt_time, 0.25])
		await personal_step("step_reveal_hand", func(seat: int) -> Array:
			return [seat, hand_ranks(seat), hand_suits(seat)]
		)
		return

	for player in range(1, player_count + 1):
		await show_reveal_prompt(player)
		await run_hand_reveal(get_hand(player))


## A prompt shown on every device at once, each one turned toward its own
## player rather than toward whoever is acting.
func step_prompt_everyone(prompt_text: String, hold_time: float, fade_time: float) -> void:
	await show_fullscreen_prompt(prompt_text, hold_time, fade_time, maxi(my_seat, 1))


## Turn `player`'s hand face up. Empty rank/suit arrays mean this device is not
## one of the eyes allowed on those cards: it watches the hand light up for
## exactly as long, with the faces never turning.
func step_reveal_hand(player: int, ranks: Array, suits: Array) -> void:
	var hand := get_hand(player)
	var show_faces := not ranks.is_empty()

	if show_faces:
		for i in range(mini(ranks.size(), hand.cards.size())):
			var revealed := make_card(ranks[i], suits[i])
			hand.cards[i].setup_card(revealed["rank"], revealed["suit"], revealed["texture"])

	await run_hand_reveal(hand, show_faces)


func show_reveal_prompt(player_number: int) -> void:
	if player_count == 2:
		# Face the player who must look away.
		var other_player := 3 - player_number
		await show_fullscreen_prompt(
			"Time for Player %d to see their cards!\nPlayer %d look away!" % [player_number, other_player],
			reveal_prompt_time,
			0.25,
			other_player
		)
	else:
		await show_look_away_prompt(
			"Time for Player %d to see their cards!\nEveryone else look away!" % player_number,
			reveal_prompt_time,
			0.25,
			get_other_players(player_number)
		)


func show_turn_prompt() -> void:
	if online:
		# Nobody hands the phone over, so the prompt says whether the turn is
		# yours; the players who are waiting then keep a standing note of whose
		# turn it is over the dimmed board (see update_turn_wait_label).
		var prompt_text := "Your turn!" if is_my_turn() else "Player %d's turn…" % current_player
		await show_fullscreen_prompt(prompt_text, turn_prompt_time, 0.15, maxi(my_seat, 1))
		return

	if player_count == 2:
		# Face the previous player, who must now look away.
		var other_player := 3 - current_player
		await show_fullscreen_prompt(
			"Player %d's turn now.\nPlayer %d, look away!" % [current_player, other_player],
			turn_prompt_time,
			0.15,
			other_player
		)
	else:
		await show_look_away_prompt(
			"Player %d's turn now.\nEveryone else, look away!" % current_player,
			turn_prompt_time,
			0.15,
			get_other_players(current_player)
		)


## Warn everyone in `audience` to look away, once per orientation rather than
## once per player: Players 3 and 4 read from the same edge, so one sideways
## showing addresses both. The total time is fixed and split per player, so a
## showing that covers two of them simply holds twice as long.
func show_look_away_prompt(prompt_text: String, total_time: float, fade_time: float, audience: Array[int]) -> void:
	if audience.is_empty():
		return

	var time_per_player: float = total_time / float(audience.size())
	var shown_rotations: Array[float] = []
	for player in audience:
		var facing: float = facing_rotation_degrees(player)
		if shown_rotations.has(facing):
			continue
		shown_rotations.append(facing)

		var sharing_this_side := 0
		for other in audience:
			if is_equal_approx(facing_rotation_degrees(other), facing):
				sharing_this_side += 1
		await show_fullscreen_prompt(prompt_text, time_per_player * sharing_this_side, fade_time, player)


## Every player number except `player`, in ascending order.
func get_other_players(player: int) -> Array[int]:
	var others: Array[int] = []
	for candidate in range(1, player_count + 1):
		if candidate != player:
			others.append(candidate)
	return others


## Near-black full-screen overlay with centered white text that fades in,
## holds, fades out, and cleans itself up. The text is rotated toward
## `facing_player` — the one who must act on it (Player 2 sits at the top of
## the screen, Player 3 views from the right edge).
func show_fullscreen_prompt(prompt_text: String, hold_time: float, fade_time: float = 0.25, facing_player: int = 1, text_color: Color = Color.WHITE) -> void:
	var overlay := create_fullscreen_overlay(0.9, 400)
	var label := make_overlay_label(prompt_text, 56)
	label.add_theme_color_override("font_color", text_color)
	label.position = Vector2.ZERO
	label.size = overlay.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.pivot_offset = label.size * 0.5
	label.rotation_degrees = facing_rotation_degrees(facing_player)
	overlay.add_child(label)

	overlay.modulate.a = 0.0
	var fade_in := create_tween()
	fade_in.tween_property(overlay, "modulate:a", 1.0, fade_time)
	await fade_in.finished

	await get_tree().create_timer(hold_time).timeout

	var fade_out := create_tween()
	fade_out.tween_property(overlay, "modulate:a", 0.0, fade_time)
	await fade_out.finished
	overlay.queue_free()


## `show_faces` off runs the reveal on the same clock without turning anything
## over: the players who may not see this hand still watch it light up and go
## dark again, so every device stays on the same beat.
func run_hand_reveal(hand: PlayerHand, show_faces := true) -> void:
	create_intro_dim_overlay()
	dim_for_hand_reveal(hand, true)

	var card_count: int = hand.cards.size()
	if show_faces:
		for card in hand.cards:
			await card.animate_flip(true, quick_flip_up_time)
	else:
		await get_tree().create_timer(card_count * quick_flip_up_time).timeout

	var flip_time_total: float = card_count * (quick_flip_up_time + player_card_flip_time)
	var hold_time: float = maxf(0.0, pre_game_reveal_time - flip_time_total)

	if hold_time > 0.0:
		await get_tree().create_timer(hold_time).timeout

	if show_faces:
		for card in hand.cards:
			await card.animate_flip(false, player_card_flip_time)
	else:
		await get_tree().create_timer(card_count * player_card_flip_time).timeout

	dim_for_hand_reveal(hand, false)
	if intro_dim_overlay:
		intro_dim_overlay.queue_free()
		intro_dim_overlay = null


func create_intro_dim_overlay() -> void:
	if intro_dim_overlay:
		return
	intro_dim_overlay = create_fullscreen_overlay(pre_game_dim_alpha, 200)


func dim_for_hand_reveal(active_hand: PlayerHand, dimmed: bool) -> void:
	var target_modulate := Color(1.0, 1.0, 1.0, 1.0)
	if dimmed:
		target_modulate = Color(0.6, 0.6, 0.6, 1.0)

	deck_sprite.modulate = target_modulate
	center_draw_card.modulate = target_modulate
	discard_pile_sprite.modulate = target_modulate
	discard_top_card.modulate = target_modulate

	for hand in get_all_hands():
		if hand != active_hand:
			hand.modulate = target_modulate
	active_hand.z_index = 300 if dimmed else 0


func _process(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set("mouse_screen_pos", get_viewport().get_mouse_position())

	if turn_state == TurnState.SPECIAL_7:
		update_seven_hover()
		if hovered_special_card and hovered_special_card != selected_source_card:
			hovered_special_card.update_shader_tilt(get_global_mouse_position())
		return

	if turn_state == TurnState.CHOOSING_PLAYER:
		update_choose_hover()
		if hovered_special_card:
			hovered_special_card.update_shader_tilt(get_global_mouse_position())
		return

	if dragged_card == null:
		return

	var mouse_position: Vector2 = get_global_mouse_position()
	dragged_card.update_shader_tilt(mouse_position)

	if hovered_player_card:
		hovered_player_card.update_shader_tilt(mouse_position)

	var collision_shape: CollisionShape2D = dragged_card.get_node("Area2D/CollisionShape2D")
	var shape: RectangleShape2D = collision_shape.shape as RectangleShape2D
	if shape == null:
		return

	var half_size: Vector2 = shape.size * dragged_card.global_scale * 0.5
	dragged_card.global_position = Vector2(
		clamp(mouse_position.x, half_size.x, screen_size.x - half_size.x),
		clamp(mouse_position.y, half_size.y, screen_size.y - half_size.y)
	)
	update_player_card_drag_hover()
	broadcast_drag(_delta)


## Online, the other players watch the card being dragged around rather than
## seeing it teleport when it is let go. Sent as a fraction of the screen,
## since a taller phone is a taller board.
func broadcast_drag(delta: float) -> void:
	if not online or not is_my_turn():
		return

	net_drag_timer += delta
	if net_drag_timer < NET_DRAG_INTERVAL:
		return
	net_drag_timer = 0.0
	rpc("net_drag", dragged_card == discard_top_card, dragged_card.global_position / screen_size)


@rpc("any_peer", "call_remote", "unreliable")
func net_drag(is_discard_card: bool, normalized_position: Vector2) -> void:
	# These arrive out of order by design, so anything that lands after the
	# drop has been played out is stale and ignored.
	if not online or turn_state != TurnState.WAITING_FOR_DROP:
		return
	if Net.seat_of(multiplayer.get_remote_sender_id()) != current_player:
		return

	var card: BoardCard = discard_top_card if is_discard_card else center_draw_card
	card.global_position = normalized_position * screen_size
	card.scale = hand_card_scale()


func _input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	# Watching someone else's turn: nothing on this screen is touchable, apart
	# from the tap that leaves the final scores.
	if online and not is_my_turn() and turn_state != TurnState.GAME_OVER:
		return

	# Tracked on every press, even in the states that act on the press itself,
	# so the hover always knows whether it is following a finger or a mouse.
	var is_tap := track_pointer_tap(mouse_event)

	match turn_state:
		TurnState.GAME_OVER:
			# The overlay marks that final scores are on screen; any tap exits.
			if mouse_event.pressed and game_over_overlay:
				return_to_main_menu()
		TurnState.SPECIAL_7:
			if is_tap:
				await handle_seven_click()
		TurnState.CHOOSING_PLAYER:
			if is_tap:
				handle_choose_click()
		_:
			if mouse_event.pressed:
				var card := check_card_click()
				if card:
					start_card_drag(card)
			elif dragged_card:
				await end_card_drag()


## Feeds the press/release pair to the tap detector and reports, on release,
## whether it was a quick tap rather than a press-and-hold or a drag.
func track_pointer_tap(mouse_event: InputEventMouseButton) -> bool:
	var pointer_position := get_global_mouse_position()
	if mouse_event.pressed:
		pointer.press(mouse_event, pointer_position)
		pointer_press_state = turn_state
		return false

	# A tap belongs to the phase it started in: a finger already down when a
	# power begins must not pick a card the press itself could not have picked.
	return pointer.release(pointer_position) and pointer_press_state == turn_state


func start_card_drag(card: Node2D) -> void:
	if turn_state != TurnState.WAITING_FOR_DROP:
		return

	var board_card := card as BoardCard
	if board_card == null or not board_card.can_drag:
		return

	# A card being dragged is on its way to a hand, so it takes the hand's size
	# now rather than snapping to it on the drop.
	board_card.tween_hover_scale(hand_card_scale())
	CardShader.set_hover(board_card.sprite, 1.0)
	CardShader.set_inset(board_card.sprite, 0.0)
	dragged_card = board_card


func end_card_drag() -> void:
	var dropped_card := dragged_card
	var target_player_card := hovered_player_card

	clear_player_card_drag_hover()
	dragged_card = null

	var slot: int = get_active_hand().cards.find(target_player_card) if target_player_card else -1

	if dropped_card == discard_top_card:
		await submit_move(Move.TAKE_DISCARD if slot >= 0 else Move.RETURN_DISCARD, slot)
		return

	if slot >= 0:
		await submit_move(Move.SWAP_DRAWN, slot)
	elif is_card_over_discard_pile(center_draw_card):
		await submit_move(Move.DISCARD_DRAWN, -1)
	else:
		await submit_move(Move.RETURN_DRAWN, -1)


## The active player's device decides what a drop meant; the host is the one
## that carries it out, so a client sends it over and waits for the steps to
## come back.
func submit_move(move: Move, slot: int) -> void:
	if is_host():
		await perform_move(move, slot)
		return

	turn_state = TurnState.ANIMATING
	rpc_id(1, "net_request_move", int(move), slot)


@rpc("any_peer", "call_remote", "reliable")
func net_request_move(move: int, slot: int) -> void:
	if not is_host() or turn_state != TurnState.WAITING_FOR_DROP:
		return
	if not is_request_from_active_player() or move < 0 or move >= Move.size():
		return
	if slot >= get_active_hand().cards.size():
		return

	await perform_move(move as Move, slot)


## Only the player whose turn it is may move, whatever their device sends.
func is_request_from_active_player() -> bool:
	return Net.seat_of(multiplayer.get_remote_sender_id()) == current_player


func perform_move(move: Move, slot: int) -> void:
	match move:
		Move.SWAP_DRAWN:
			await swap_draw_card_into_slot(slot)
		Move.DISCARD_DRAWN:
			await discard_center_draw_card()
		Move.RETURN_DRAWN:
			await return_center_draw_card()
		Move.TAKE_DISCARD:
			await take_discard_into_slot(slot)
		Move.RETURN_DISCARD:
			await return_discard_card()


func on_board_card_hovered(card: BoardCard) -> void:
	if card.can_drag:
		highlight_card(card, true)


func on_board_card_hovered_off(card: BoardCard) -> void:
	if dragged_card == null:
		highlight_card(card, false)


func highlight_card(card: BoardCard, is_hovered: bool) -> void:
	var rest_scale := board_card_rest_scale(card)
	card.tween_hover_scale(rest_scale * HOVER_SCALE_MULTIPLIER if is_hovered else rest_scale)
	CardShader.set_hover(card.sprite, 1.0 if is_hovered else 0.0)
	if is_hovered:
		CardShader.set_inset(card.sprite, 0.0)
	else:
		CardShader.tween_inset(card, card.sprite, CardShader.RESTING_INSET, 0.12)


func check_card_click() -> Node2D:
	var space_state := get_world_2d().direct_space_state
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = CARD_COLLISION_MASK
	var result := space_state.intersect_point(parameters)
	if result.size() > 0:
		return get_top_card(result)
	return null


func get_top_card(cards: Array[Dictionary]) -> Node2D:
	var top_card: Node2D = cards[0]["collider"].get_parent()
	var highest_z_index := top_card.z_index

	for i in range(1, cards.size()):
		var current_card: Node2D = cards[i]["collider"].get_parent()
		if current_card.z_index > highest_z_index:
			top_card = current_card
			highest_z_index = current_card.z_index

	return top_card


func update_player_card_drag_hover() -> void:
	var best_player_card := get_best_overlapped_player_card()

	if hovered_player_card == best_player_card:
		return

	if hovered_player_card:
		hovered_player_card.set_drag_hovered(false)

	hovered_player_card = best_player_card

	if hovered_player_card:
		hovered_player_card.set_drag_hovered(true)


func clear_player_card_drag_hover() -> void:
	if hovered_player_card:
		hovered_player_card.set_drag_hovered(false)
		hovered_player_card = null


func get_best_overlapped_player_card() -> PlayerCard:
	if dragged_card == null:
		return null

	var dragged_card_rect := dragged_card.get_global_rect()
	var best_player_card: PlayerCard
	var best_overlap_area := 0.0

	for player_card in get_tree().get_nodes_in_group("player_cards"):
		# Hands that are not in play are hidden, not removed — an undealt card
		# has no face, and swapping onto one puts a null texture on the discard.
		if player_card is PlayerCard and player_card.player_id == current_player \
				and player_card.is_visible_in_tree():
			var overlap_area := get_overlap_area(dragged_card_rect, player_card.get_global_rect())
			if overlap_area > best_overlap_area:
				best_overlap_area = overlap_area
				best_player_card = player_card

	return best_player_card


func get_overlap_area(first_rect: Rect2, second_rect: Rect2) -> float:
	if not first_rect.intersects(second_rect):
		return 0.0

	var overlap_rect := first_rect.intersection(second_rect)
	return overlap_rect.size.x * overlap_rect.size.y


## The host's turn loop. Every line of it is a step, so the other devices play
## the same turn out card for card.
func start_turn() -> void:
	if deck.is_empty():
		await end_game()
		return

	await step("step_begin_turn", [current_player])
	await deal_center_draw_card()
	await check_special_card_effect()
	# Power effects (reveals, seven swap) restore full brightness when they
	# finish, so the spotlight has to be re-applied.
	await step("step_resume_turn")


func step_begin_turn(player: int) -> void:
	current_player = player
	turn_state = TurnState.DEALING
	await show_turn_prompt()
	apply_turn_focus()


## Hand the turn over to whoever is up. On the devices that are only watching,
## nothing becomes draggable — they are left with the animation and the note
## saying whose turn this is.
func step_resume_turn() -> void:
	apply_turn_focus()
	set_discard_takeable(is_my_turn())
	center_draw_card.can_drag = is_my_turn()
	turn_state = TurnState.WAITING_FOR_DROP


## Spotlight the active player for the whole turn: a dark overlay covers the
## board, and only their hand, the drawn card, and the discard top card sit
## above it. The overlay persists between turns; only the raised hand changes.
func apply_turn_focus() -> void:
	if turn_focus_overlay == null:
		turn_focus_overlay = create_fullscreen_overlay(0.5, TURN_FOCUS_OVERLAY_Z)

	for hand in get_all_hands():
		hand.z_index = FOCUSED_HAND_Z if hand == get_active_hand() else 0
	center_draw_card.z_index = FOCUSED_DRAW_CARD_Z
	discard_top_card.z_index = FOCUSED_DISCARD_Z
	update_turn_wait_label()


## Online, a player who is not up keeps a standing "Player N's turn…" note over
## the dimmed board, turned toward their own side of the table. They still
## watch every card move; they just cannot touch anything.
func update_turn_wait_label() -> void:
	if turn_wait_label:
		turn_wait_label.queue_free()
		turn_wait_label = null
	if not online or is_my_turn():
		return

	turn_wait_label = make_overlay_label("Player %d's turn…" % current_player, 52)
	turn_wait_label.z_index = TURN_FOCUS_OVERLAY_Z + 1
	turn_wait_label.size = Vector2(screen_size.x, TURN_WAIT_LABEL_HEIGHT)
	turn_wait_label.pivot_offset = turn_wait_label.size * 0.5
	turn_wait_label.rotation_degrees = facing_rotation_degrees(my_seat)
	turn_wait_label.position = turn_wait_label_position()
	add_child(turn_wait_label)


## The clear band between this player's own hand and the middle of the board,
## on their side of the screen — the one place a note can sit without covering
## either the drawn card or anybody's cards.
func turn_wait_label_position() -> Vector2:
	var middle: float = screen_size.y * 0.5
	if my_seat == 2:
		return Vector2(0.0, middle - TURN_WAIT_LABEL_BAND - TURN_WAIT_LABEL_HEIGHT)
	return Vector2(0.0, middle + TURN_WAIT_LABEL_BAND)


func clear_turn_focus() -> void:
	if turn_focus_overlay:
		turn_focus_overlay.queue_free()
		turn_focus_overlay = null
	if turn_wait_label:
		turn_wait_label.queue_free()
		turn_wait_label = null

	for hand in get_all_hands():
		hand.z_index = 0
	center_draw_card.z_index = 1
	discard_top_card.z_index = 5


## While waiting for a drop, the discard pile's top card may be taken into the
## hand instead of the drawn card. Disabling also clears any stale hover state,
## since a disabled Area2D never fires mouse_exited.
func set_discard_takeable(takeable: bool) -> void:
	var enabled := takeable and discard_top_card.visible
	discard_top_card.can_drag = enabled
	discard_top_card.get_node("Area2D").input_pickable = enabled
	discard_top_card.get_node("Area2D/CollisionShape2D").set_deferred("disabled", not enabled)

	if not enabled:
		discard_top_card.clear_hover()


## Queen: reveal the active player's own hand.
## King: reveal an opponent's hand.
## Jack: jumble an opponent's cards randomly.
## Seven: swap one of the active player's cards with an opponent's card.
## With three players, K/J/7 first let the active player pick the opponent.
func check_special_card_effect() -> void:
	match String(current_draw.get("rank", "")):
		"Q":
			await reveal_hand_to(current_player, current_player)

		"K":
			var reveal_player := await pick_power_target("Choose a player whose\ncards you wish to see")
			remove_special_overlay()
			await reveal_hand_to(reveal_player, current_player)

		"J":
			var jumble_player := await pick_power_target("Choose a player whose\ncards you wish to jumble")
			remove_special_overlay()
			await step("step_jumble_hand", [jumble_player, shuffled_order(get_hand(jumble_player).cards.size())])

		"7":
			var swap_player := await pick_power_target("Choose a player who\nyou wish to swap with")
			await run_seven_swap_power(swap_player)


## Turn `player`'s hand face up, but only on `viewer`'s screen — the K is the
## one player's look at somebody else's cards, and nobody else gets it. The
## other devices see the same hand light up with its faces still down.
func reveal_hand_to(player: int, viewer: int) -> void:
	await personal_step("step_reveal_hand", func(seat: int) -> Array:
		if not online or seat == viewer:
			return [player, hand_ranks(player), hand_suits(player)]
		return [player, [], []]
	)


func step_jumble_hand(player: int, order: Array) -> void:
	play_slide_sound()
	await get_hand(player).jumble_cards(order)
	play_place_sound()


## A shuffled slot order for the jumble, worked out once by the host so every
## device shuffles the same hand the same way. Guaranteed to move something.
func shuffled_order(count: int) -> Array:
	var order: Array = range(count)
	order.shuffle()

	var all_fixed := true
	for i in range(count):
		if order[i] != i:
			all_fixed = false
			break
	if all_fixed and count >= 2:
		order[0] = 1
		order[1] = 0

	return order


## Which player a K/J/7 power acts on: always the other one in a 2-player game;
## with three or four, the active player taps an opponent's cards to pick. That
## tapping is a hotseat path — an online game is two players for now.
func pick_power_target(choose_prompt_text: String) -> int:
	if player_count == 2:
		return current_player % player_count + 1
	return await choose_target_player(choose_prompt_text)


## Prompt the active player, then light up both opponent hands and wait for a
## tap on one of them. Leaves the dim overlay up for the power that follows.
func choose_target_player(choose_prompt_text: String) -> int:
	chosen_target_player = 0
	hovered_special_card = null

	await show_fullscreen_prompt(choose_prompt_text, turn_prompt_time, 0.15, current_player, UiPalette.ACCENT)

	# Same layering as the seven power: board cards dim under the overlay,
	# selectable hands are raised above it.
	center_draw_card.z_index = 1
	discard_top_card.z_index = 5
	create_special_overlay()
	for hand in get_all_hands():
		var selectable := hand != get_active_hand()
		set_hand_enabled(hand, selectable)
		hand.z_index = RAISED_HAND_Z_INDEX if selectable else 0

	turn_state = TurnState.CHOOSING_PLAYER
	while chosen_target_player == 0:
		await get_tree().process_frame
	turn_state = TurnState.DEALING

	if hovered_special_card:
		hovered_special_card.set_drag_hovered(false)
		hovered_special_card = null
	for hand in get_all_hands():
		set_hand_enabled(hand, true)
		hand.z_index = 0

	return chosen_target_player


## The card under `point` in any opponent hand (CHOOSING_PLAYER state).
func get_opponent_card_at(point: Vector2) -> PlayerCard:
	var best_card: PlayerCard = null
	var highest_z := -9999

	for hand in get_all_hands():
		if hand == get_active_hand():
			continue
		for card in hand.cards:
			if card.get_global_rect().has_point(point) and card.z_index > highest_z:
				highest_z = card.z_index
				best_card = card

	return best_card


func update_choose_hover() -> void:
	var new_hover := get_opponent_card_at(get_global_mouse_position()) if TapGesture.is_pointer_hovering() else null

	if hovered_special_card == new_hover:
		return

	pointer.hover_target_changed(new_hover != null)
	if hovered_special_card:
		hovered_special_card.set_drag_hovered(false)
	hovered_special_card = new_hover
	if hovered_special_card:
		hovered_special_card.set_drag_hovered(true)


func handle_choose_click() -> void:
	var clicked_card := get_opponent_card_at(get_global_mouse_position())
	if clicked_card:
		chosen_target_player = clicked_card.player_id


func deal_center_draw_card() -> void:
	current_draw = deck.pop_front()
	await personal_step("step_draw_card", func(seat: int) -> Array:
		if may_see_draw(seat):
			return [current_draw["rank"], current_draw["suit"]]
		return ["", ""]
	)


## Whether `seat` gets to see the card that was just drawn. The player whose
## turn it is always does; the rest only when it is a power card, since that
## one is about to act on somebody else's hand and the table should know.
func may_see_draw(seat: int) -> bool:
	return not online or seat == current_player or is_power_rank(current_draw["rank"])


func is_power_rank(rank: String) -> bool:
	return rank in ["7", "J", "Q", "K"]


func step_draw_card(rank: String, suit: String) -> void:
	var drawn := make_card(rank, suit)
	center_draw_card.setup_card(
		drawn["rank"],
		drawn["suit"],
		drawn["texture"]
	)
	center_draw_card.visible = true
	center_draw_card.z_index = FOCUSED_DRAW_CARD_Z
	center_draw_card.can_drag = false
	center_draw_card.global_position = deck_sprite.global_position
	center_draw_card.rotation_degrees = deck_sprite.rotation_degrees
	# The card's child sprite is pre-scaled, so divide that out to spawn at
	# exactly the deck pile's on-screen size.
	center_draw_card.scale = deck_sprite.scale / center_draw_card.sprite.scale.x

	# In 3-player mode the drawn card turns to face whoever's turn it is. Four
	# players keep the two upright hands' card upright — it lands beside the
	# board, where they both read it fine — but Players 3 and 4 draw to the
	# sideways column on their own edge, so their card turns with them.
	var target_rotation := 0.0
	if player_count == 3 or current_player >= 3:
		target_rotation = facing_rotation_degrees(current_player)

	play_slide_sound()
	var move_tween := create_tween().set_parallel(true)
	move_tween.tween_property(center_draw_card, "global_position", get_draw_card_rest_position(), initial_deal_fly_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Grows out of the pile to hand size — it is a card in play now, not one
	# sitting on the board.
	move_tween.tween_property(center_draw_card, "scale", hand_card_scale(), initial_deal_fly_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	move_tween.tween_property(center_draw_card, "rotation_degrees", target_rotation, initial_deal_fly_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await move_tween.finished

	# A card this device may not see stays face down: the players who are only
	# watching see it fly out and land, and that is all they learn.
	if drawn["texture"] != null:
		await center_draw_card.flip_to_front(is_my_turn())


## Where the drawn card rests this turn. Once the board is a sideways column,
## Players 1 and 2 get the card stepped to the side away from the discard pile,
## while the right-side players' sideways card parks right on top of the deck
## pile (which isn't interactive), nudged up a touch so its edge cannot cover
## the tappable discard pile below.
func get_draw_card_rest_position() -> Vector2:
	var rest := center_draw_position
	if player_count >= 3:
		if current_player >= 3:
			rest = deck_sprite.global_position + Vector2(0.0, -30.0)
		else:
			rest.x += DRAW_CARD_TURN_OFFSET
	return rest


func discard_center_draw_card() -> void:
	# The pile is face up, so throwing a card onto it tells the whole table
	# what it was, whether or not they were allowed to see it in play.
	await step("step_discard_drawn", [current_draw["rank"], current_draw["suit"]])
	advance_to_next_player()
	await start_turn()


func step_discard_drawn(rank: String, suit: String) -> void:
	turn_state = TurnState.ANIMATING
	center_draw_card.can_drag = false
	set_discard_takeable(false)
	turn_over_drawn_card(rank, suit)

	var move_tween := create_tween().set_parallel(true)
	move_tween.tween_property(center_draw_card, "global_position", discard_pile_position, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_property(center_draw_card, "rotation_degrees", discard_pile_sprite.rotation_degrees, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# Back down to the pile's size on the way out of play.
	move_tween.tween_property(center_draw_card, "scale", NORMAL_CARD_SCALE, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	place_card_on_discard(center_draw_card)
	play_place_sound()
	center_draw_card.visible = false


## On its way to the pile, a drawn card the watching players were never shown
## turns over as it goes — the same way a card swapped out of a hand does.
func turn_over_drawn_card(rank: String, suit: String) -> void:
	if not center_draw_card.rank.is_empty():
		return
	var revealed := make_card(rank, suit)
	center_draw_card.setup_card(revealed["rank"], revealed["suit"], revealed["texture"])
	center_draw_card.flip_to_front(false)


func swap_draw_card_into_slot(slot: int) -> void:
	var replaced: Dictionary = get_active_hand().cards[slot].to_card_data()
	# The drawn card goes in face down, so only its owner is told what landed
	# there. The card it pushed out lands face up on the pile for everyone.
	await private_step(
		"step_swap_drawn_into_slot",
		[current_player, slot, current_draw["rank"], current_draw["suit"], replaced["rank"], replaced["suit"]],
		[current_player, slot, "", "", replaced["rank"], replaced["suit"]],
		[current_player]
	)
	advance_to_next_player()
	await start_turn()


func step_swap_drawn_into_slot(
	player: int,
	slot: int,
	rank: String,
	suit: String,
	replaced_rank: String,
	replaced_suit: String
) -> void:
	turn_state = TurnState.ANIMATING
	center_draw_card.can_drag = false
	set_discard_takeable(false)

	var player_card: PlayerCard = get_hand(player).cards[slot]

	# Grow to the hand's card size on the way in, so the card the player let go
	# of is exactly the card that ends up in the slot.
	var move_tween := create_tween().set_parallel(true)
	move_tween.tween_property(center_draw_card, "global_position", player_card.global_position, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_property(center_draw_card, "scale", player_card.resting_scale, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	var incoming := make_card(rank, suit)
	player_card.setup_card(
		incoming["rank"],
		incoming["suit"],
		incoming["texture"]
	)
	player_card.set_drag_hovered(false)
	play_place_sound()
	center_draw_card.visible = false

	await animate_card_to_discard(
		make_card(replaced_rank, replaced_suit),
		player_card.global_position,
		player_card.resting_scale
	)


func return_center_draw_card() -> void:
	await step("step_return_drawn")


func step_return_drawn() -> void:
	turn_state = TurnState.ANIMATING
	center_draw_card.can_drag = false

	play_slide_sound()
	var move_tween := create_tween()
	move_tween.tween_property(center_draw_card, "global_position", get_draw_card_rest_position(), SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	center_draw_card.scale = hand_card_scale()
	center_draw_card.can_drag = is_my_turn()
	# Only keep the hover look if the pointer actually rests on the card — and
	# a finger that has lifted rests on nothing, wherever it left the pointer.
	var pointer_on_card := is_my_turn() and TapGesture.is_pointer_hovering() \
		and center_draw_card.get_global_rect().has_point(get_global_mouse_position())
	highlight_card(center_draw_card, pointer_on_card)
	turn_state = TurnState.WAITING_FOR_DROP


## Take the discard pile's top card into the hand instead of the drawn card:
## the drawn card goes onto the pile, then the replaced hand card lands on top.
## Everything here is public — the table watched the pile's top card go into
## that slot, and both of the other cards end up face up on the pile.
func take_discard_into_slot(slot: int) -> void:
	var player_card: PlayerCard = get_active_hand().cards[slot]
	var replaced := player_card.to_card_data()
	var taken := discard_top_card.to_card_data()

	await step("step_take_discard_into_slot", [
		current_player, slot,
		taken["rank"], taken["suit"],
		current_draw["rank"], current_draw["suit"],
		replaced["rank"], replaced["suit"],
	])
	advance_to_next_player()
	await start_turn()


func step_take_discard_into_slot(
	player: int,
	slot: int,
	taken_rank: String,
	taken_suit: String,
	drawn_rank: String,
	drawn_suit: String,
	replaced_rank: String,
	replaced_suit: String
) -> void:
	turn_state = TurnState.ANIMATING
	center_draw_card.can_drag = false
	set_discard_takeable(false)

	var player_card: PlayerCard = get_hand(player).cards[slot]
	var old_hand_data := make_card(replaced_rank, replaced_suit)
	var taken_data := make_card(taken_rank, taken_suit)

	var move_tween := create_tween().set_parallel(true)
	move_tween.tween_property(discard_top_card, "global_position", player_card.global_position, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_property(discard_top_card, "scale", player_card.resting_scale, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	player_card.setup_card(taken_data["rank"], taken_data["suit"], taken_data["texture"])
	player_card.set_drag_hovered(false)
	play_place_sound()
	discard_top_card.visible = false

	turn_over_drawn_card(drawn_rank, drawn_suit)
	play_slide_sound()
	var center_tween := create_tween().set_parallel(true)
	center_tween.tween_property(center_draw_card, "global_position", discard_pile_position, DISCARD_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	center_tween.tween_property(center_draw_card, "rotation_degrees", discard_pile_sprite.rotation_degrees, DISCARD_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	center_tween.tween_property(center_draw_card, "scale", NORMAL_CARD_SCALE, DISCARD_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await center_tween.finished
	place_card_on_discard(center_draw_card)
	play_place_sound()
	center_draw_card.visible = false

	await animate_card_to_discard(old_hand_data, player_card.global_position, player_card.resting_scale)


func return_discard_card() -> void:
	await step("step_return_discard")


func step_return_discard() -> void:
	turn_state = TurnState.ANIMATING

	play_slide_sound()
	var move_tween := create_tween().set_parallel(true)
	move_tween.tween_property(discard_top_card, "global_position", discard_pile_position, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# Shrinks back to the pile's size — picking it up had grown it to hand size.
	move_tween.tween_property(discard_top_card, "scale", NORMAL_CARD_SCALE, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	# Only keep the hover look if the pointer actually rests on the card — and
	# a finger that has lifted rests on nothing, wherever it left the pointer.
	var pointer_on_card := is_my_turn() and TapGesture.is_pointer_hovering() \
		and discard_top_card.get_global_rect().has_point(get_global_mouse_position())
	highlight_card(discard_top_card, pointer_on_card)
	turn_state = TurnState.WAITING_FOR_DROP


## `start_scale` is the size the card had where it left — a hand's card size for
## the usual case — so it shrinks to the board's size as it flies to the pile.
func animate_card_to_discard(card_data: Dictionary, start_position: Vector2, start_scale: Vector2) -> void:
	flying_card.visible = true
	flying_card.setup_card(
		card_data["rank"],
		card_data["suit"],
		card_data["texture"]
	)
	flying_card.global_position = start_position
	flying_card.scale = start_scale
	flying_card.z_index = FLYING_CARD_Z

	var move_tween := create_tween().set_parallel(true)
	move_tween.tween_property(flying_card, "global_position", discard_pile_position, DISCARD_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_property(flying_card, "scale", NORMAL_CARD_SCALE, DISCARD_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	flying_card.flip_to_front(false)

	await move_tween.finished
	place_card_on_discard(flying_card)
	flying_card.visible = false
	play_place_sound()


## Stamp `card`'s face onto the discard pile's top-card slot.
func place_card_on_discard(card: BoardCard) -> void:
	discard_top_card.visible = true
	discard_top_card.setup_card(card.rank, card.suit, card.front_texture)
	discard_top_card.show_front()
	discard_top_card.can_drag = false
	discard_top_card.global_position = discard_pile_position
	discard_top_card.scale = NORMAL_CARD_SCALE
	discard_top_card.z_index = 5


func is_card_over_discard_pile(card: Card) -> bool:
	return get_overlap_area(card.get_global_rect(), Card.sprite_global_rect(discard_pile_sprite)) > 0.0


func create_fullscreen_overlay(alpha: float, overlay_z_index: int) -> ColorRect:
	# Sized explicitly: anchor presets don't reliably fill the viewport for
	# Controls parented to a Node2D, which left overlays collapsed at (0,0).
	var overlay := ColorRect.new()
	overlay.position = Vector2.ZERO
	overlay.size = screen_size
	overlay.color = Color(0.0, 0.0, 0.0, alpha)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = overlay_z_index
	add_child(overlay)
	return overlay


func create_special_overlay() -> void:
	if special_overlay:
		return
	special_overlay = create_fullscreen_overlay(0.65, OVERLAY_Z_INDEX)


func remove_special_overlay() -> void:
	if special_overlay:
		special_overlay.queue_free()
		special_overlay = null


func set_hand_enabled(hand: PlayerHand, enabled: bool) -> void:
	for card in hand.cards:
		card.modulate = Color.WHITE if enabled else Color(0.35, 0.35, 0.35)


## The host's side of the 7: put every device into the picking state, wait for
## the active player's two cards (from this device or over the wire), then swap
## them everywhere. Nothing resumes until the cards have landed.
func run_seven_swap_power(target_player: int) -> void:
	seven_choice.clear()
	seven_skipped = false
	awaiting_seven = true

	await step("step_begin_seven", [target_player])

	while seven_choice.is_empty() and not seven_skipped:
		await get_tree().process_frame
	awaiting_seven = false

	if not seven_skipped:
		await step("step_seven_swap", [current_player, seven_choice[0], target_player, seven_choice[1]])
	await step("step_end_seven")


## Only the active player's device gets the skip button and the picking state;
## the others just watch their hands dim and wait.
func step_begin_seven(target_player: int) -> void:
	seven_target_hand = get_hand(target_player)
	selected_source_card = null
	hovered_special_card = null
	seven_selecting_opponent = false

	# Drop the board cards below the seven overlay so the drawn 7 dims and
	# cannot cover the skip button; the turn spotlight restores them after.
	center_draw_card.z_index = 1
	discard_top_card.z_index = 5

	create_special_overlay()
	set_seven_phase_hands(true)

	if is_my_turn():
		show_seven_skip_button()
		turn_state = TurnState.SPECIAL_7
	else:
		turn_state = TurnState.ANIMATING


func step_seven_swap(first_player: int, first_slot: int, second_player: int, second_slot: int) -> void:
	turn_state = TurnState.ANIMATING

	var first: PlayerCard = get_hand(first_player).cards[first_slot]
	var second: PlayerCard = get_hand(second_player).cards[second_slot]
	first.set_special_selected(false)
	second.set_drag_hovered(false)
	selected_source_card = null
	hovered_special_card = null

	await animate_swap_player_cards(first, second)


func step_end_seven() -> void:
	remove_seven_skip_button()
	remove_special_overlay()
	for hand in get_all_hands():
		set_hand_enabled(hand, true)
		hand.z_index = 0


func show_seven_skip_button() -> void:
	seven_skip_button = Button.new()
	seven_skip_button.text = "Skip (don't swap)"
	seven_skip_button.theme = UI_THEME
	seven_skip_button.add_theme_font_size_override("font_size", 48)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		seven_skip_button.add_theme_color_override(color_name, UiPalette.INK)

	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.ACCENT
	style.set_corner_radius_all(16)
	style.set_content_margin_all(28.0)
	seven_skip_button.add_theme_stylebox_override("normal", style)
	var pressed_style := style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = UiPalette.ACCENT_PRESSED
	seven_skip_button.add_theme_stylebox_override("pressed", pressed_style)
	seven_skip_button.add_theme_stylebox_override("hover", style)
	seven_skip_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	seven_skip_button.focus_mode = Control.FOCUS_NONE
	seven_skip_button.z_index = OVERLAY_Z_INDEX + 10
	seven_skip_button.size = Vector2(580.0, 130.0)
	seven_skip_button.position = (screen_size - seven_skip_button.size) * 0.5
	seven_skip_button.pivot_offset = seven_skip_button.size * 0.5
	seven_skip_button.rotation_degrees = facing_rotation_degrees(current_player)
	seven_skip_button.pressed.connect(on_seven_skip_pressed)
	add_child(seven_skip_button)

	# Quick pop-in.
	seven_skip_button.scale = Vector2(0.6, 0.6)
	seven_skip_button.modulate.a = 0.0
	var pop := create_tween().set_parallel(true)
	pop.tween_property(seven_skip_button, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(seven_skip_button, "modulate:a", 1.0, 0.18)


func remove_seven_skip_button() -> void:
	if seven_skip_button:
		seven_skip_button.queue_free()
		seven_skip_button = null


func on_seven_skip_pressed() -> void:
	if turn_state != TurnState.SPECIAL_7:
		return

	if selected_source_card:
		selected_source_card.set_special_selected(false)
		selected_source_card = null
	if hovered_special_card:
		hovered_special_card.set_drag_hovered(false)
		hovered_special_card = null

	turn_state = TurnState.ANIMATING
	if is_host():
		seven_skipped = true
	else:
		rpc_id(1, "net_request_seven_skip")


## Light up and raise the selectable hand, dim and lower the rest.
## Phase 1 (selecting_own = true): the active hand. Phase 2: the chosen
## target hand — any third player stays dark and excluded.
func set_seven_phase_hands(selecting_own: bool) -> void:
	var selectable_hand := get_active_hand() if selecting_own else seven_target_hand
	for hand in get_all_hands():
		var selectable := hand == selectable_hand
		set_hand_enabled(hand, selectable)
		hand.z_index = RAISED_HAND_Z_INDEX if selectable else 0


## The card under `point` in the currently selectable hand.
func get_seven_card_at(point: Vector2) -> PlayerCard:
	var hand := seven_target_hand if seven_selecting_opponent else get_active_hand()
	var best_card: PlayerCard = null
	var highest_z := -9999

	for card in hand.cards:
		if card.get_global_rect().has_point(point) and card.z_index > highest_z:
			highest_z = card.z_index
			best_card = card

	return best_card


## A lifted finger leaves the pointer parked on its last spot, so on touch the
## hover has to end with the press instead of following that ghost.
func update_seven_hover() -> void:
	var new_hover := get_seven_card_at(get_global_mouse_position()) if TapGesture.is_pointer_hovering() else null

	if hovered_special_card == new_hover:
		return

	# Resting on one card long enough picks it on release, so the clock only
	# runs while the hover stays put.
	pointer.hover_target_changed(new_hover != null)
	if hovered_special_card and hovered_special_card != selected_source_card:
		hovered_special_card.set_drag_hovered(false)

	hovered_special_card = new_hover

	if hovered_special_card and hovered_special_card != selected_source_card:
		hovered_special_card.set_drag_hovered(true)


func handle_seven_click() -> void:
	# Resolve the card at the tap position directly: on touch screens the
	# hover state tracked in _process lags one frame behind the finger.
	var clicked_card := get_seven_card_at(get_global_mouse_position())
	if clicked_card == null:
		return

	if not seven_selecting_opponent:
		selected_source_card = clicked_card
		selected_source_card.set_special_selected(true)
		seven_selecting_opponent = true
		hovered_special_card = null

		set_seven_phase_hands(false)
		# Keep the chosen card lit and above the dim overlay while picking a target.
		selected_source_card.modulate = Color.WHITE
		selected_source_card.z_index = RAISED_HAND_Z_INDEX
		return

	# Both cards are picked. The host is the one that performs the swap — on
	# every device at once — so this only reports the two slots and waits.
	var source_slot: int = get_active_hand().cards.find(selected_source_card)
	var target_slot: int = seven_target_hand.cards.find(clicked_card)
	turn_state = TurnState.ANIMATING

	if is_host():
		seven_choice = [source_slot, target_slot]
	else:
		rpc_id(1, "net_request_seven", source_slot, target_slot)


@rpc("any_peer", "call_remote", "reliable")
func net_request_seven(source_slot: int, target_slot: int) -> void:
	if not is_host() or not awaiting_seven or not is_request_from_active_player():
		return
	if source_slot < 0 or source_slot >= get_active_hand().cards.size():
		return
	if target_slot < 0 or target_slot >= seven_target_hand.cards.size():
		return

	seven_choice = [source_slot, target_slot]


@rpc("any_peer", "call_remote", "reliable")
func net_request_seven_skip() -> void:
	if not is_host() or not awaiting_seven or not is_request_from_active_player():
		return

	seven_skipped = true


## Fly two cards to each other's slots, then swap their data and snap back.
## Both cards are face-down, so the snap-back is invisible to the players.
func animate_swap_player_cards(first: PlayerCard, second: PlayerCard) -> void:
	var first_data := first.to_card_data()
	var second_data := second.to_card_data()

	var first_global := first.global_position
	var second_global := second.global_position

	# The lift from selecting these two is still tweening their position and
	# scale; leaving it running would fight the flight for its first frames.
	first.stop_state_tweens()
	second.stop_state_tweens()

	first.z_index = RAISED_HAND_Z_INDEX
	second.z_index = RAISED_HAND_Z_INDEX

	play_slide_sound()
	var swap_tween := create_tween().set_parallel(true)
	swap_tween.tween_property(first, "global_position", second_global, SWAP_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	swap_tween.tween_property(second, "global_position", first_global, SWAP_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await swap_tween.finished

	first.setup_card(second_data["rank"], second_data["suit"], second_data["texture"])
	second.setup_card(first_data["rank"], first_data["suit"], first_data["texture"])
	play_place_sound()

	# Every hand, not just the first two: the flight parks each card in the
	# other's slot at a raised z-index, and only its own hand's re-arrange puts
	# it back. Skipping Player 3's left their card sitting in the hand it flew
	# to, on top of that player's fan, while their own fan looked a card short.
	for hand in get_all_hands():
		hand.arrange_cards()


func get_all_hands() -> Array[PlayerHand]:
	var hands: Array[PlayerHand] = [player1_hand, player2_hand]
	if player_count >= 3:
		hands.append(player3_hand)
	if player_count >= 4:
		hands.append(player4_hand)
	return hands


func get_hand(player: int) -> PlayerHand:
	match player:
		1: return player1_hand
		2: return player2_hand
		3: return player3_hand
		_: return player4_hand


func get_active_hand() -> PlayerHand:
	return get_hand(current_player)


## Turn order cycles 1 → 2 → (3) → 1.
func advance_to_next_player() -> void:
	current_player = current_player % player_count + 1


## How much a screen-facing element must rotate to be upright for a player:
## Player 1 sits at the bottom, Player 2 at the top, and Players 3 and 4 both
## look in from the right edge — so they read the same rotation.
func facing_rotation_degrees(player: int) -> float:
	match player:
		2: return 180.0
		3, 4: return -90.0
		_: return 0.0


## The deck ran out. Every hand goes face up now, so this is the one step that
## hands the whole table's cards to every device — they each work the scores
## out from what they were told.
func end_game() -> void:
	var ranks: Array = []
	var suits: Array = []
	for player in range(1, player_count + 1):
		ranks.append(hand_ranks(player))
		suits.append(hand_suits(player))

	await step("step_end_game", [ranks, suits])


func step_end_game(ranks: Array, suits: Array) -> void:
	turn_state = TurnState.GAME_OVER
	clear_turn_focus()
	center_draw_card.visible = false

	for player in range(1, player_count + 1):
		var hand := get_hand(player)
		var player_ranks: Array = ranks[player - 1]
		var player_suits: Array = suits[player - 1]
		for i in range(mini(player_ranks.size(), hand.cards.size())):
			var final_card := make_card(player_ranks[i], player_suits[i])
			hand.cards[i].setup_card(final_card["rank"], final_card["suit"], final_card["texture"])

	await reveal_all_cards()
	show_game_over_overlay()


func reveal_all_cards() -> void:
	for hand in get_all_hands():
		for card in hand.cards:
			await card.animate_flip(true, player_card_flip_time)


## Cabo scoring: A=1, number cards face value, J=11, Q=12, K=13.
func get_card_value(card_rank: String) -> int:
	match card_rank:
		"A": return 1
		"J": return 11
		"Q": return 12
		"K": return 13
		_: return int(card_rank)


func get_hand_score(hand: PlayerHand) -> int:
	var total := 0
	for card in hand.cards:
		total += get_card_value(card.rank)
	return total


func show_game_over_overlay() -> void:
	var hands := get_all_hands()
	var scores: Array[int] = []
	for hand in hands:
		scores.append(get_hand_score(hand))

	# Lowest total wins; multiple players on the lowest score is a tie.
	var best_score: int = scores.min()
	var winner_player := 0
	var winner_count := 0
	for i in range(scores.size()):
		if scores[i] == best_score:
			winner_count += 1
			winner_player = i + 1

	var title := "It's a tie!" if winner_count > 1 else "Player %d wins!" % winner_player

	game_over_overlay = create_fullscreen_overlay(0.9, 400)

	# Winner, totals, and the exit hint are one column, so they stay together
	# under the headline. The whole block turns sideways and sits in the middle
	# of the screen, where every player can read it from their side of the phone.
	var block := VBoxContainer.new()
	block.alignment = BoxContainer.ALIGNMENT_CENTER
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_theme_constant_override("separation", 24)
	game_over_overlay.add_child(block)

	block.add_child(make_overlay_label(title, 72))
	for i in range(scores.size()):
		block.add_child(make_overlay_label("Player %d: %d points" % [i + 1, scores[i]], 40))
	block.add_child(make_overlay_label("Tap anywhere for the main menu", 30))

	# Turned a quarter turn, the block's own width runs down the screen's long
	# edge, so it is sized from that and centered on both axes. Godot grows a
	# Control that is set smaller than its contents, so the height is read back
	# rather than assumed.
	block.size = Vector2(screen_size.y, block.get_combined_minimum_size().y)
	var block_size := block.size
	block.pivot_offset = block_size * 0.5
	block.rotation_degrees = 90.0
	block.position = (screen_size - block_size) * 0.5


func make_overlay_label(label_text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = label_text
	label.theme = UI_THEME
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Someone dropped out (or quit to their own menu): the match cannot go on, so
## every device that is still here says so and heads back to the title screen.
func on_connection_lost(reason: String) -> void:
	if is_returning_to_menu:
		return

	turn_state = TurnState.ANIMATING
	clear_turn_focus()
	await show_fullscreen_prompt(reason, 1.6, 0.2, maxi(my_seat, 1))
	return_to_main_menu()


func return_to_main_menu() -> void:
	if is_returning_to_menu:
		return
	is_returning_to_menu = true
	Net.leave()

	# Fade to black, then swap scenes; the menu fades back in on its side.
	var fade := create_fullscreen_overlay(0.0, 500)
	var fade_tween := create_tween()
	fade_tween.tween_property(fade, "color:a", 1.0, 0.35)
	await fade_tween.finished
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
