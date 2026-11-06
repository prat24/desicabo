## CardArt — where every card picture comes from. The game has two looks: the
## watercolour deck, and Simple Cards from Settings (the original plain faces
## with a navy swirl back). The simple set copies the watercolour folders under
## Simple/, file for file and at the same 420x570 size, so picking a look only
## picks a folder: card sizes and layout never change with it.
##
## Every picture is kept once loaded. Loading a card face is slow — on a phone
## browser it is long enough to stall the frame it happens in — and Godot frees
## a texture the moment nothing shows it, so without this a card that left the
## table and came back (or a face a watching player had never seen, turned over
## on its way to the pile) was loaded again in the middle of its animation.
## The title screen loads the deck ahead of time with warm_up().
class_name CardArt
extends RefCounted

const ART_DIR := "res://Assets/Art/PNG/"
const SIMPLE_ART_DIR := "res://Assets/Art/PNG/Simple/"

## Loaded pictures by full path, for the look they were loaded in. Switching
## looks drops the other look's set rather than holding both.
static var _cache: Dictionary = {}
static var _cache_dir := ""


## A card picture by its path inside the art folder, such as
## "TitleCards/Local.png", in whichever look the player has picked.
static func texture(art_path: String) -> Texture2D:
	var art_dir := SIMPLE_ART_DIR if GameSettings.simple_cards else ART_DIR
	if art_dir != _cache_dir:
		_cache.clear()
		_cache_dir = art_dir

	var path := art_dir + art_path
	var picture: Texture2D = _cache.get(path)
	if picture == null:
		picture = load(path)
		_cache[path] = picture
	return picture


static func front(suit: String, rank: String) -> Texture2D:
	return texture(front_path(suit, rank))


static func back() -> Texture2D:
	return texture("Cards/cardBack_main.png")


static func discard_pile() -> Texture2D:
	return texture("Cards/discard_pile.png")


static func front_path(suit: String, rank: String) -> String:
	return "Cards/card%s%s.png" % [suit, rank]


## Every picture a game puts on the table: the 52 faces, the back and the
## discard pile's base.
static func table_art() -> PackedStringArray:
	var paths := PackedStringArray(["Cards/cardBack_main.png", "Cards/discard_pile.png"])
	for suit: String in CardDeck.SUITS:
		for rank: String in CardDeck.RANKS:
			paths.append(front_path(suit, rank))
	return paths


## Load the whole table's art, one picture a frame so nothing on screen
## stutters. Not awaited by the caller; a game that starts before it is done
## finds the rest already loaded or loads it with load_table_art().
static func warm_up(tree: SceneTree) -> void:
	for art_path in table_art():
		texture(art_path)
		await tree.process_frame


## Load whatever of the table's art warm_up() has not reached yet, all at once.
static func load_table_art() -> void:
	for art_path in table_art():
		texture(art_path)
