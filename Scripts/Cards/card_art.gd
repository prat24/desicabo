## CardArt — where every card picture comes from. The game has two looks: the
## watercolour deck, and Simple Cards from Settings (the original plain faces
## with a navy swirl back). The simple set copies the watercolour folders under
## Simple/, file for file and at the same 420x570 size, so picking a look only
## picks a folder: card sizes and layout never change with it.
class_name CardArt
extends RefCounted

const ART_DIR := "res://Assets/Art/PNG/"
const SIMPLE_ART_DIR := "res://Assets/Art/PNG/Simple/"


## A card picture by its path inside the art folder, such as
## "TitleCards/Local.png", in whichever look the player has picked.
static func texture(art_path: String) -> Texture2D:
	var art_dir := SIMPLE_ART_DIR if GameSettings.simple_cards else ART_DIR
	return load(art_dir + art_path)


static func front(suit: String, rank: String) -> Texture2D:
	return texture("Cards/card%s%s.png" % [suit, rank])


static func back() -> Texture2D:
	return texture("Cards/cardBack_main.png")


static func discard_pile() -> Texture2D:
	return texture("Cards/discard_pile.png")
