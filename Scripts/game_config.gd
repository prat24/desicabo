## GameConfig — cross-scene game setup chosen on the title screen.
class_name GameConfig
extends RefCounted

## Number of players for the next game (2 to 4).
static var player_count: int = 2
## Local game against the computer rather than round the same phone. The player
## takes seat 1 and every other seat is a bot.
static var vs_bots: bool = false
