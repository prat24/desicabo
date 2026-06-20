## CardDeck — static helpers for creating and shuffling a standard 52-card deck.
extends RefCounted
class_name CardDeck

const SUITS = ["Clubs", "Diamonds", "Hearts", "Spades"]
const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

static func create_shuffled_deck() -> Array[Dictionary]:
	var deck := create_deck()
	deck.shuffle()
	return deck


static func create_deck() -> Array[Dictionary]:
	var deck: Array[Dictionary] = []

	for suit in SUITS:
		for rank in RANKS:
			deck.append({
				"rank": rank,
				"suit": suit,
				"texture": load(get_card_texture_path(suit, rank))
			})

	return deck


static func get_card_texture_path(suit: String, rank: String) -> String:
	return "res://Assets/Art/PNG/Cards/card%s%s.png" % [suit, rank]
