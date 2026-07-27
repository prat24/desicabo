## CardBelief — one player's picture of the table: the cards they have managed
## to keep track of. This is plain bookkeeping, not a learned model. Every entry
## comes from something that player actually saw — their opening peek, a King, a
## card landing face up on the pile — and is dropped when they lose it.
##
## Forgetting is all or nothing: each turn a memory either survives or goes
## entirely. A person who half-remembers a 2 still plays it as a 2; they do not
## start treating it as a 5. Fading every memory toward the average instead
## would have bots trading away good cards they were merely hazy about.
##
## Each slot is therefore in one of three states:
##
##   known    a rank this player can still name
##   grouped  a jumbled hand: they know WHICH cards they hold, just not where
##            any of them ended up
##   unknown  nothing but the prior — a card drawn at random from everything
##            this player has not seen
class_name CardBelief
extends RefCounted

const UNKNOWN_RANK := 0
const HIGHEST_RANK := 13
const COPIES_PER_RANK := 4

var player_count: int
var slots_per_hand: int

## [player - 1][slot] -> rank, or UNKNOWN_RANK for a slot this player cannot
## name.
var hands: Array = []
## Jumbled hands, keyed by player: {"members": Array[int], "ranks": Array[int],
## "unknown": int}. `members` are the slots still holding one of these cards,
## and members.size() == ranks.size() + unknown always holds.
var groups: Dictionary = {}
## Copies of each rank this player has not placed anywhere, indexed by rank.
## Anything unknown is a card drawn from here, so this is both the prior and
## the card counting.
var unseen: Array[int] = []


func _init(players: int, slots: int) -> void:
	player_count = players
	slots_per_hand = slots

	unseen.resize(HIGHEST_RANK + 1)
	for rank in range(1, HIGHEST_RANK + 1):
		unseen[rank] = COPIES_PER_RANK

	for player in range(player_count):
		var hand: Array = []
		hand.resize(slots)
		hand.fill(UNKNOWN_RANK)
		hands.append(hand)


# ── What the player thinks a card is worth ────────────────────────────────────

## The average rank of everything this player has not seen — what an unknown
## card is worth to them. Sharpens on its own as cards are revealed.
func prior_mean() -> float:
	var total := 0.0
	var count := 0
	for rank in range(1, HIGHEST_RANK + 1):
		total += float(rank * unseen[rank])
		count += unseen[rank]
	return total / float(count) if count > 0 else float(HIGHEST_RANK) * 0.5


## What this player expects the card in that slot to be worth.
func expected_value(player: int, slot: int) -> float:
	if group_holds(player, slot):
		return group_mean(player)

	var rank: int = hands[player - 1][slot]
	return prior_mean() if rank == UNKNOWN_RANK else float(rank)


## How unsure the player is about a slot, 0 (they can name it) to 1 (no idea).
## A jumbled hand sits in between: they know what is in there, so the more of
## it they have already placed the better their guess at the rest.
func uncertainty(player: int, slot: int) -> float:
	if group_holds(player, slot):
		return 1.0 - 1.0 / float(maxi(group_size(player), 1))
	return 0.0 if int(hands[player - 1][slot]) != UNKNOWN_RANK else 1.0


func hand_total(player: int) -> float:
	var total := 0.0
	for slot in range(slots_per_hand):
		total += expected_value(player, slot)
	return total


## Slots this player could not name if asked — what a King is worth against
## this hand.
func unknown_slot_count(player: int) -> int:
	var count := 0
	for slot in range(slots_per_hand):
		if uncertainty(player, slot) > 0.0:
			count += 1
	return count


# ── Learning ──────────────────────────────────────────────────────────────────

## This player saw a specific card. Remembering it also takes that copy out of
## the pool of things they might otherwise be holding.
func learn(player: int, slot: int, rank: int) -> void:
	leave_group(player, slot, rank)
	clear_slot(player, slot)
	if rank == UNKNOWN_RANK:
		return

	hands[player - 1][slot] = rank
	take_from_pool(rank)


## This player watched a card land somewhere they cannot read.
func forget(player: int, slot: int) -> void:
	leave_group(player, slot, UNKNOWN_RANK)
	clear_slot(player, slot)


## A card was turned face up in front of everyone, so it is no longer a card
## this player might be holding.
func note_revealed(rank: int) -> void:
	take_from_pool(rank)


## Two cards traded places. Whatever this player thought was in one slot is now
## in the other — which is right for everybody: the player who set the swap up
## knows exactly what they handed over, and a bystander who knew neither card
## still knows nothing.
func swap_slots(first_player: int, first_slot: int, second_player: int, second_slot: int) -> void:
	# A jumbled hand cannot say which card left, so it gives up the position
	# rather than guessing.
	if group_holds(first_player, first_slot) or group_holds(second_player, second_slot):
		forget(first_player, first_slot)
		forget(second_player, second_slot)
		return

	var first: int = hands[first_player - 1][first_slot]
	hands[first_player - 1][first_slot] = hands[second_player - 1][second_slot]
	hands[second_player - 1][second_slot] = first


## Somebody shuffled this hand. Nothing is lost about WHAT is in there — only
## about where any of it went, which is exactly what happens to a person.
func jumble(player: int) -> void:
	var known_ranks: Array = []
	var unknown_count := 0

	for slot in range(slots_per_hand):
		if group_holds(player, slot):
			continue
		var rank: int = hands[player - 1][slot]
		if rank != UNKNOWN_RANK:
			known_ranks.append(rank)
		else:
			unknown_count += 1
		hands[player - 1][slot] = UNKNOWN_RANK

	# A hand that was already jumbled keeps whatever it had left.
	if groups.has(player):
		var existing: Dictionary = groups[player]
		known_ranks.append_array(existing["ranks"])
		unknown_count += int(existing["unknown"])

	groups[player] = {
		"members": range(slots_per_hand),
		"ranks": known_ranks,
		"unknown": unknown_count,
	}


## A turn went by. Each memory either survives it or is gone for good, and a
## card the player can no longer name goes back to being anybody's.
func decay(rate: float) -> void:
	if rate <= 0.0:
		return

	for player in range(1, player_count + 1):
		for slot in range(slots_per_hand):
			if int(hands[player - 1][slot]) != UNKNOWN_RANK and randf() < rate:
				clear_slot(player, slot)

		# A jumbled hand loses whole cards off the list of what is in there.
		if groups.has(player) and randf() < rate:
			var group: Dictionary = groups[player]
			var ranks: Array = group["ranks"]
			if not ranks.is_empty():
				return_to_pool(int(ranks.pop_back()))
				group["unknown"] = int(group["unknown"]) + 1


# ── Private ───────────────────────────────────────────────────────────────────

func group_holds(player: int, slot: int) -> bool:
	return groups.has(player) and (groups[player]["members"] as Array).has(slot)


func group_size(player: int) -> int:
	return (groups[player]["members"] as Array).size()


## Every slot of a jumbled hand is worth the same: the player cannot tell them
## apart, so the average of what is in there is all they have to go on.
func group_mean(player: int) -> float:
	var group: Dictionary = groups[player]
	var total := 0.0
	for rank: int in group["ranks"]:
		total += float(rank)
	total += float(group["unknown"]) * prior_mean()
	return total / float(maxi(group_size(player), 1))


## A card left a jumbled hand. Seeing what it was narrows down what is left —
## and once one slot remains, the player knows exactly what it is again.
func leave_group(player: int, slot: int, revealed_rank: int) -> void:
	if not group_holds(player, slot):
		return

	var group: Dictionary = groups[player]
	var members: Array = group["members"]
	var ranks: Array = group["ranks"]
	members.erase(slot)

	if revealed_rank != UNKNOWN_RANK and ranks.has(revealed_rank):
		ranks.erase(revealed_rank)
	elif int(group["unknown"]) > 0:
		group["unknown"] = int(group["unknown"]) - 1
	elif not ranks.is_empty():
		# It went somewhere unseen, so which of these left is anybody's guess.
		dissolve_group(player)
		return

	# Down to one slot, so whatever is left has nowhere else to be.
	if members.size() <= 1:
		dissolve_group(player)


## Give the last card back to its own slot when that is no longer ambiguous,
## and give up on the rest.
func dissolve_group(player: int) -> void:
	var group: Dictionary = groups[player]
	var members: Array = group["members"]
	var ranks: Array = group["ranks"]

	if members.size() == 1 and ranks.size() == 1:
		hands[player - 1][members[0]] = int(ranks[0])
	else:
		for rank: int in ranks:
			return_to_pool(rank)

	groups.erase(player)


func clear_slot(player: int, slot: int) -> void:
	var rank: int = hands[player - 1][slot]
	if rank != UNKNOWN_RANK:
		return_to_pool(rank)
	hands[player - 1][slot] = UNKNOWN_RANK


func take_from_pool(rank: int) -> void:
	if rank >= 1 and rank <= HIGHEST_RANK and unseen[rank] > 0:
		unseen[rank] -= 1


## A forgotten card is one this player might be holding again, so it goes back.
func return_to_pool(rank: int) -> void:
	if rank >= 1 and rank <= HIGHEST_RANK and unseen[rank] < COPIES_PER_RANK:
		unseen[rank] += 1
