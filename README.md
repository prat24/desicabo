# Desi Cabo

A mobile card game built in Godot 4.7. It is a version of **Cabo**: everyone holds three
face-down cards, you get one look at them at the start, and from then on you play from memory.
Lowest total when the deck runs out wins.

Three ways to play, all from the same game code:

- **Local** — one phone passed around the table, 2 to 4 players
- **Online** — one phone hosts over Wi-Fi and the others join it, 2 to 4 players
- **Bots** — you against the computer, 2 to 4 players

No servers, no accounts, no analytics, no third-party libraries.

---

## Running it

You need [Godot 4.7](https://godotengine.org/download) or newer. Nothing else.

1. Open Godot, click **Import**, and select `project.godot` in this folder.
2. Press **F5** (or the ▶ button).

The game starts at `Scenes/UI/main_menu.tscn` and runs at 1080×1920.

### Testing online play on one computer

You do not need two devices. In the editor: **Debug → Customize Run Instances**, tick
*Enable Multiple Instances*, set it to **2**, then run. Two windows open.

In one window pick Online → 2 → **Host a Game**; in the other pick Online → 2 → **Join a
Game**. The host appears in the list — the search checks `127.0.0.1` as well as the network,
so two copies on one machine find each other.

---

## Building for iPhone

You need macOS, Xcode, and an Apple ID.

1. In Godot: **Editor → Manage Export Templates** and download the templates for your version.
2. **Project → Export**, select the **iOS** preset, and replace the two placeholders:
   **Bundle Identifier** (`com.example.desicabo` → something of your own) and **App Store
   Team ID** (`0000000000` → your team, found in your Apple Developer account). Export fails
   with *"App Store Team ID not specified"* if you leave that one empty.
3. Click **Export Project**. The preset has *Export Project Only* enabled, so you get an Xcode
   project rather than a finished build.
4. Open the generated `.xcodeproj`, select your device, and press Run.

Targets iOS 14+, iPhone only.

**Two things to know before you test on a device:**

- **Local network permission.** iOS gates local networking. The export preset already adds
  `NSLocalNetworkUsageDescription`, so both phones will prompt on first launch — accept it, or
  online play cannot connect.
- **Finding games may not work over Wi-Fi on device.** The search uses a UDP broadcast, and
  Apple requires their multicast entitlement for broadcast traffic. If no games are found, the
  host screen prints its own IP address and the join screen has a **Host address** box. Typing
  the address is a plain direct connection and needs no entitlement.

With a free Apple ID (a "personal team") builds stop launching after **7 days** and must be
reinstalled from Xcode. A paid Apple Developer Program membership removes that and is required
to ship.

---

## The rules

Each player gets **three face-down cards** and one timed look at them before play begins. After
that you are playing from memory.

On your turn you draw the top card of the deck, then choose one of:

- **swap it into one of your slots** — the card it replaces goes face up on the discard pile
- **throw it on the discard pile** and keep what you have
- **take the discard pile's top card instead** into one of your slots

Card values are **A = 1** up to **K = 13**. Four cards do something extra when you *draw* them,
and you still place or discard the card afterwards:

| Card | Effect |
|---|---|
| **Q** | Look at your own hand |
| **K** | Look at an opponent's hand |
| **J** | Shuffle an opponent's hand — they keep the cards, they lose track of where |
| **7** | Swap one of your cards for one of theirs, sight unseen (skippable) |

When the deck runs out, every hand is revealed. **Lowest total wins.**

---

## How the code is put together

The whole game lives in one scene, `Scenes/Managers/game_manager.tscn`, driven by
`Scripts/Managers/game_manager.gd`. The three modes are not three code paths — they are the
same loop with two questions answered differently.

### "Whose screen is this?"

Every mode sets `my_seat`:

| Mode | `my_seat` | What that means |
|---|---|---|
| Local hotseat | `0` | The screen belongs to whoever's turn it is; everything is shown |
| Online | your lobby seat | The screen belongs to you; other hands stay face down |
| Vs bots | `1` | Same as online — the bots are just seats you cannot see |

One check, `has_own_seat()`, decides whether a card may be turned face up. That is why the bot
game looks exactly like the online game: it is the same rule, not a copy of it.

What a player is allowed to see:

- Their own hand, at the opening peek and whenever a Q reveals it
- An opponent's hand only if *they* drew the K that revealed it
- The drawn card only on their own turn — **unless it is a power card**, which the whole table
  is shown, since it is about to act on somebody's hand
- Anything on the discard pile, which is face up by definition

### Online: the host owns the game

The host runs the entire game loop and holds the deck. Every visible move is sent to the other
devices as a **step** — a plain data message like *"player 2's slot 1 was replaced, the card
that came out was a 9"*. Steps carry only ranks, slot numbers and player numbers, never node
references, and each device animates them itself.

Three ways to send one, in `game_manager.gd`:

- `step()` — everyone gets the same thing (public events)
- `private_step()` — the named players get the truth, everyone else gets blanks
- `personal_step()` — each device is asked separately what it is allowed to see

Clients never decide anything. They send *intent* (`"swap into slot 2"`), the host checks it
came from the player whose turn it actually is, and the result comes back as steps. Steps queue
on arrival so they animate one at a time.

`Scripts/Net/net_manager.gd` handles the connection: ENet on port **8654**, plus a UDP
broadcast on **8655** so joining is a tap on a game that was found rather than typing an IP.

---

## How the bots work

The bots do not search ahead and are not trained. They keep track of cards the way a person
does, and act on one rule. Difficulty is not a smarter rule — it is a better memory.

### What a bot knows

`Scripts/AI/card_belief.gd` holds one table per bot. Every slot at the table — its own and its
opponents' — is in one of three states:

- **known** — a rank it can still name
- **grouped** — a jumbled hand: it knows *which* cards are in there, not *where*
- **unknown** — nothing but the prior

The prior is not a guess. The table tracks every card the bot has seen, so an unknown slot is
worth the average of the cards it has *not* seen. That is card counting, and it sharpens by
itself as the game goes on.

### Reading the table

Unknown does not mean nothing. When you swap a card in and throw a 5 away, two things follow —
and the bot uses both:

- the card that went in is probably **lower than 5**, because nobody trades a card for a worse one
- the slot you picked was probably your worst, so **the rest of your hand is probably ≤ 5 too**

Neither is certain — you might have been replacing a slot you had simply forgotten — so these
are stored as hints at 75% weight rather than as facts. An unknown slot normally reads ~6.9;
after watching you discard a 5 it reads ~4.0. Hints clear when the slot changes, travel with
the card through a 7-swap, are wiped by a jumble, and fade at the same rate as memories, so a
forgetful bot does not reason like a sharp one. A card the bot actually *saw* always wins over
a hint.

### Forgetting

Each turn, every memory either survives or is gone — all or nothing, never a blur. A person who
half-remembers a 2 still plays it as a 2; they do not start treating it as a 5. Fading memories
toward the average instead made bots trade away good cards they were merely hazy about.

**J is the interesting one.** When a hand is shuffled, the bot keeps the *values* and loses the
*positions* — it knows it holds a 3, a 7 and an 11 somewhere, so every slot is worth 7 to it and
replacing any of them is a gamble. As cards leave and land face up it narrows the list back
down, and once one slot is left it knows exactly what is in it again.

### The one decision rule

Every slot is worth whatever the bot expects to be in it. Then:

> Take the lower of {drawn card, discard top} if it beats the worst slot. Otherwise discard.

That single line covers replacing a known King, covering an unknown slot with a low card, and
passing on a card that helps nobody. The margin it demands scales with how unsure it is about
the slot it is about to throw away — so it hesitates on a jumbled hand and commits on a known
one.

Powers are just as short: **Q** look at yourself; **K** look at the hand you know least about;
**J** shuffle whoever is winning; **7** trade your worst card for the best one you can see, if
the gap is worth it.

### Difficulty

The slider in Settings moves three things at once: how fast memories fade, how big an edge the
bot needs before acting, and how often it simply plays something else. It reads as a word —
*Forgetful* through *Card Counter* — because what it moves is memory, not cleverness.

Measured over 15 full games at each setting against an opponent playing at random (lowest score
wins, 3 is the floor):

| Difficulty | Mean score | Own cards still known at the end |
|---|---|---|
| 0.0 | 8.5 | 1.0 of 3 |
| 0.5 | 6.8 | 1.3 of 3 |
| 1.0 | 3.7 | 1.7 of 3 |

The forgetting rate is scaled geometrically rather than linearly, because a memory survives at
`(1 - rate)` per turn — a linear slider leaves the bottom half feeling identical.

---

## Project layout

| Path | What is in it |
|---|---|
| `Scenes/` | The main menu, the game board, the card and hand scenes |
| `Scripts/Managers/game_manager.gd` | The game loop: dealing, turns, powers, scoring, and the online step system |
| `Scripts/Boards/player_hand.gd` | One player's fan of cards and how it is laid out |
| `Scripts/Cards/` | Card behaviour: faces, flips, drag, hover, and the deck |
| `Scripts/Net/net_manager.gd` | Hosting, joining, and finding games on the network |
| `Scripts/AI/` | The bots: `card_belief.gd` (memory), `card_bot.gd` (decisions), `bot_table.gd` (who saw what) |
| `Scripts/UI/` | Menu, settings, online lobby, in-game menu |
| `Assets/` | Card art, fonts, sounds, shaders |

The card shaders read a global `mouse_screen_pos` uniform for their hover tilt. Any scene
showing cards must update it every frame or the tilt animates toward a stale point.
