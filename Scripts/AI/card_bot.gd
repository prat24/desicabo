## CardBot — one seat played by the computer. Its whole strategy is one idea:
## every slot is worth whatever it expects to be in there, so take a card when
## it beats the worst slot and leave it otherwise. That single rule covers
## replacing a known King, covering an unknown slot with a low card, and passing
## on a card that helps nobody.
##
## Difficulty is not a smarter rule — it is a better memory. A bot that reasons
## correctly and misremembers reads as a person; one that reasons badly reads as
## broken. See [CardBelief] for the memory itself.
class_name CardBot
extends RefCounted

## What a turn costs the bot's memory, from the difficulty slider.
const FORGET_RATE_EASY := 0.30
const FORGET_RATE_HARD := 0.02
## How much better a card has to be before the bot will act on it. An unsure bot
## wants a bigger edge, which is what makes it pass up coin flips.
const CAUTION_EASY := 2.5
const CAUTION_HARD := 0.4
## How often it simply plays something else. Nothing models a distracted player
## as honestly as being distracted.
const BLUNDER_EASY := 0.20
const BLUNDER_HARD := 0.0
## A seven only swaps when the trade is worth more than this.
const SEVEN_MARGIN := 2.0

var seat: int
var belief: CardBelief
var forget_rate: float
var caution: float
var blunder_chance: float


## `difficulty` runs 0 (forgetful, timid, careless) to 1 (sharp).
func _init(bot_seat: int, players: int, slots: int, difficulty: float) -> void:
	seat = bot_seat
	belief = CardBelief.new(players, slots)

	var skill := clampf(difficulty, 0.0, 1.0)
	# Geometric, not linear: a memory survives at (1 - rate) per turn, so what
	# the player feels is the rate's ratio rather than its difference. Walking
	# it down linearly leaves the whole bottom half of the slider forgetting
	# almost everything and only the last stretch feeling sharp.
	forget_rate = FORGET_RATE_EASY * pow(FORGET_RATE_HARD / FORGET_RATE_EASY, skill)
	caution = lerpf(CAUTION_EASY, CAUTION_HARD, skill)
	blunder_chance = lerpf(BLUNDER_EASY, BLUNDER_HARD, skill)


# ── Decisions ─────────────────────────────────────────────────────────────────

## What to do with the card just drawn. Returns {"move": GameManager.Move,
## "slot": int}. `discard_rank` is 0 when the pile is empty or not takeable.
func choose_move(drawn_rank: int, discard_rank: int) -> Dictionary:
	var worst_slot := worst_own_slot()
	var worst_value := belief.expected_value(seat, worst_slot)

	if randf() < blunder_chance:
		return random_move(worst_slot)

	# Whichever of the two on offer is lower; the pile only counts when the
	# game is actually letting it be taken.
	var take_from_pile := discard_rank > 0 and discard_rank < drawn_rank
	var intake: int = discard_rank if take_from_pile else drawn_rank

	# The margin is the bot's nerve: it grows with how little it trusts the slot
	# it is about to throw away, so a jumbled hand makes it think twice.
	var margin: float = caution * belief.uncertainty(seat, worst_slot)
	if float(intake) < worst_value - margin:
		return {
			"move": GameManager.Move.TAKE_DISCARD if take_from_pile else GameManager.Move.SWAP_DRAWN,
			"slot": worst_slot,
		}

	return {"move": GameManager.Move.DISCARD_DRAWN, "slot": -1}


## Which opponent a King, Jack or Seven should be aimed at.
func choose_power_target(power: String, opponents: Array) -> int:
	if opponents.is_empty():
		return 0
	if randf() < blunder_chance:
		return opponents.pick_random()

	var best: int = opponents[0]
	for player: int in opponents:
		match power:
			# Look at the hand you know least about — the others teach you nothing.
			"K":
				if belief.unknown_slot_count(player) > belief.unknown_slot_count(best):
					best = player
			# Shuffle whoever is winning; it costs them their whole hand.
			"J":
				if belief.hand_total(player) < belief.hand_total(best):
					best = player
			# Swap with whoever is holding the lowest card you can see.
			_:
				if best_target_value(player) < best_target_value(best):
					best = player
	return best


## Which two cards a Seven should trade, or an empty result to skip. Gives away
## the worst card it holds for the best one it can see.
func choose_seven_swap(target_player: int) -> Dictionary:
	var own_slot := worst_own_slot()
	var target_slot := best_slot_of(target_player)
	var gain: float = belief.expected_value(seat, own_slot) - belief.expected_value(target_player, target_slot)

	if gain < SEVEN_MARGIN or randf() < blunder_chance:
		return {}
	return {"own_slot": own_slot, "target_slot": target_slot}


# ── What it saw ───────────────────────────────────────────────────────────────

func on_turn_passed() -> void:
	belief.decay(forget_rate)


# ── Private ───────────────────────────────────────────────────────────────────

## The slot it would most like to be rid of.
func worst_own_slot() -> int:
	return highest_slot(seat)


func highest_slot(player: int) -> int:
	var best := 0
	for slot in range(1, belief.slots_per_hand):
		if belief.expected_value(player, slot) > belief.expected_value(player, best):
			best = slot
	return best


func best_slot_of(player: int) -> int:
	var best := 0
	for slot in range(1, belief.slots_per_hand):
		if belief.expected_value(player, slot) < belief.expected_value(player, best):
			best = slot
	return best


func best_target_value(player: int) -> float:
	return belief.expected_value(player, best_slot_of(player))


func random_move(worst_slot: int) -> Dictionary:
	if randf() < 0.5:
		return {"move": GameManager.Move.DISCARD_DRAWN, "slot": -1}
	return {"move": GameManager.Move.SWAP_DRAWN, "slot": randi() % belief.slots_per_hand}
