## UiPalette — shared colors of the game's beige-on-dark interface, so the
## menu, the settings panel, and the in-game overlays stay in sync.
class_name UiPalette
extends RefCounted

## Warm beige used for panels, buttons, and accent text.
const ACCENT := Color(0.94, 0.9, 0.82)
## Pressed state of an accent-colored surface.
const ACCENT_PRESSED := Color(0.85, 0.8, 0.7)
## Near-black ink for text sitting on an accent surface.
const INK := Color(0.08, 0.07, 0.05)
## The plain near-black behind everything: the title screen before its swirl
## fades in (main_menu.tscn), the boot splash, and the whole game with Simple
## Cards on, which has no swirl at all.
const BACKDROP := Color(0.043, 0.068, 0.09)
## Corner buttons sit on top of whatever is already on screen — a fanned hand,
## a crowded four-player table — so they are barely-there dark glass.
const GLASS := Color(0.0, 0.0, 0.0, 0.3)
const GLASS_PRESSED := Color(0.0, 0.0, 0.0, 0.5)
