## BotTable — the computer players at one table, and the single place that
## decides what each of them is allowed to have seen. The game calls these
## methods with the truth; every bot is then told only the part of it that a
## player in that seat could actually have watched happen, which is the same
## rule the networked game applies to the other phones.
class_name BotTable
extends RefCounted

var bots: Dictionary = {}


## Every seat except `human_seat` is played by the computer.
func _init(player_count: int, human_seat: int, slots_per_hand: int, difficulty: float) -> void:
	for seat in range(1, player_count + 1):
		if seat != human_seat:
			bots[seat] = CardBot.new(seat, player_count, slots_per_hand, difficulty)


func has_bot(seat: int) -> bool:
	return bots.has(seat)


func bot(seat: int) -> CardBot:
	return bots[seat]


# ── What the table saw ────────────────────────────────────────────────────────

## The opening peek: every player looks at their own hand and nobody else's.
func observe_opening_peek(ranks_by_player: Dictionary) -> void:
	for seat: int in bots:
		if not ranks_by_player.has(seat):
			continue
		var ranks: Array = ranks_by_player[seat]
		for slot in range(ranks.size()):
			bots[seat].belief.learn(seat, slot, int(ranks[slot]))


## A card came off the deck. The player whose turn it is always sees it; the
## rest only when it is a power card, which the whole table is shown.
func observe_draw(active_player: int, rank: int, public: bool) -> void:
	for seat: int in bots:
		if public or seat == active_player:
			bots[seat].belief.note_revealed(rank)


## A card landed face up on the pile, where everyone can read it.
func observe_discard(rank: int) -> void:
	for seat: int in bots:
		bots[seat].belief.note_revealed(rank)


## A card went into a slot. Everyone watched which slot changed; whether they
## know what went in depends on where it came from — the pile is face up, the
## drawn card is not.
func observe_slot_filled(player: int, slot: int, rank: int, public: bool) -> void:
	for seat: int in bots:
		if public or seat == player:
			bots[seat].belief.learn(player, slot, rank)
		else:
			bots[seat].belief.forget(player, slot)


## Somebody swapped a card into a slot and threw one away, where the whole table
## could see it. Everyone gets to reason about what that says — about the card
## that went in, and about the rest of that hand.
func observe_replacement(player: int, slot: int, discarded_rank: int) -> void:
	for seat: int in bots:
		bots[seat].belief.note_replacement(player, slot, discarded_rank)


## A King: only the player who drew it gets to look.
func observe_peek(viewer: int, target: int, ranks: Array) -> void:
	if not bots.has(viewer):
		return
	for slot in range(ranks.size()):
		bots[viewer].belief.learn(target, slot, int(ranks[slot]))


## A Jack. Everyone watching loses track of where that hand's cards went — the
## player holding it included, which is the whole point of the card.
func observe_jumble(player: int) -> void:
	for seat: int in bots:
		bots[seat].belief.jumble(player)


## A Seven: the two cards trade places face down. Anyone who knew what was in
## one of those slots now knows where it went, so the beliefs simply swap.
func observe_seven_swap(first_player: int, first_slot: int, second_player: int, second_slot: int) -> void:
	for seat: int in bots:
		bots[seat].belief.swap_slots(first_player, first_slot, second_player, second_slot)


## A turn went by, so every memory at the table gets a little hazier.
func observe_turn_passed() -> void:
	for seat: int in bots:
		bots[seat].on_turn_passed()
