# Desi Cabo

A Cabo card game for mobile, built in Godot 4.7.

Each player holds three face-down cards, sees them once at the start, and plays from memory.
Lowest total when the deck runs out wins.

Modes: **Local** (one device passed around), **Online** (one device hosts over Wi-Fi),
**Bots**. 2–4 players in all three.

## Requirements

Godot 4.7 or newer. No other dependencies.

## Running on Desktop

1. Open Godot, click **Import**, select `project.godot`.
2. Press **F5**.

Entry scene: `Scenes/UI/main_menu.tscn`. Resolution: 1080×1920.

## Building and Running on iOS

Requires macOS, Xcode, and an Apple ID. Targets iOS 14+, iPhone only.

1. **Editor → Manage Export Templates** — download the templates.
2. **Project → Export → iOS**. Set **Bundle Identifier** (currently `com.example.desicabo`)
   and **App Store Team ID** (currently `0000000000`). Export fails with *"App Store Team ID
   not specified"* if the team ID is left empty.
3. **Export Project**. *Export Project Only* is enabled, so the output is an Xcode project.
4. Open the `.xcodeproj`, select a device, Run.

Notes:

- Free Apple ID builds expire after 7 days, this is not a major issue you will just have to reinstall the game again from Xcode onto your phone to refresh it.

## Rules

Deal three face-down cards per player, with one timed look before play starts.

On your turn, draw the top card of the deck, then either:

- swap it into a slot — the replaced card goes face up on the discard pile
- discard it
- take the top discard into a slot instead

Values are A = 1 to K = 13. Four cards trigger an effect when drawn; the drawn card is still
placed or discarded afterwards.

There are a few **Wild Cards** with certain effects:

| Card | Effect |
|---|---|
| Q | Look at your own hand |
| K | Look at an opponent's hand |
| J | Shuffle an opponent's hand — same cards, positions lost |
| 7 | Swap one of your cards for one of theirs, sight unseen (skippable) |

When the deck runs out, the game is over and all hands are revealed. Lowest total wins.

## Architecture

All three modes run the same loop in `Scenes/Managers/game_manager.tscn` /
`Scripts/Managers/game_manager.gd`.

**Networking** — the host runs the loop and holds the deck. Moves are sent as *steps*: data
messages carrying ranks, slot numbers and player numbers only, never node references. Each
device animates them itself, queued one at a time. `step()` sends to everyone,
`private_step()` sends the truth to named players and blanks to the rest, `personal_step()`
asks each device what it may see. Clients send intent only; the host validates it against the
current turn. `Scripts/Net/net_manager.gd` uses ENet on port 8654 and UDP broadcast on 8655.

**Bots** — `Scripts/AI/card_belief.gd` tracks each slot as known, grouped (shuffled hand:
values known, positions not), or unknown. Unknown slots are valued at the average of unseen
cards. Discards generate hints i.e. a card swapped in is probably lower than the card thrown, and
the chosen slot was probably the worst in that hand. These hints are stored at 75% weight, cleared when the
slot changes, wiped by a shuffle, and overridden by anything the bot actually saw. Memories
are dropped whole rather than decayed. The bots decide to take the lower of the drawn card and
the discard top if it beats the worst slot, otherwise discard; the required margin scales with
uncertainty.

Difficulty (Settings) scales forget rate, decision margin, and how often the bot plays off-rule.
The forget rate is scaled geometrically.

## Layout

| Path | Contents |
|---|---|
| `Scenes/` | Main menu, game board, card and hand scenes |
| `Scripts/Managers/game_manager.gd` | Dealing, turns, powers, scoring, step system |
| `Scripts/Boards/player_hand.gd` | One player's hand and its layout |
| `Scripts/Cards/` | Faces, flips, drag, hover, deck |
| `Scripts/Net/net_manager.gd` | Hosting, joining, discovery |
| `Scripts/AI/` | `card_belief.gd`, `card_bot.gd`, `bot_table.gd` |
| `Scripts/UI/` | Menu, settings, lobby, in-game menu |
| `Assets/` | Card art, fonts, sounds, shaders |
