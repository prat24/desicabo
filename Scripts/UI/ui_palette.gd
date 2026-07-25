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
