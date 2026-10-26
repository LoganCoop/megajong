# Megajong

A 16-bit neo-noir mahjong-tile rummy game with DATA // SURGE scoring (data x surge), characters and power tiles. Play solo against bots, pass-and-play on one device, or online with friends. Made with Godot 4.7.

## Game modes

- **Solo vs Bots** - you plus three bots.
- **Local Pass & Play** - 2-4 humans share one screen; a hand-hiding screen appears before each turn. Empty seats are bots.
- **Host / Join Online** - the host picks a character and shares their IP (UDP port 7777, forward it for play over the internet). Up to 3 friends join; empty seats are bots. The host runs the rules and clients only see their own hand. If a player disconnects, a bot takes their seat. Press Esc or MENU to leave.

## How to play

- 4 players, 10 tiles each, 3 rounds. Best total score wins.
- Each turn: **draw** (click the wall, or the top of the discard pile), **lay melds**, then **discard 1 tile** to end your turn.
- Melds are 3-5 tiles:
  - **Set**: 3-4 of the same rank (all one suit = Pure, bonus surge).
  - **Run**: 3-5 of the same suit in order.
- Each meld scores **data x surge**. Every extra meld in the same turn adds +1 surge (combo).
- Empty your hand to **go out**: +150 and the round ends.
- **Characters** (pick one): Dragon (sets +2 surge), Crane (runs +2 surge), Magpie (+20 data per meld), Fox (starts with a WILD).
- **Power tiles** in the wall: **W** wild (stands in for any tile), **G** gold (+25 data when scored), **T** thief (steals 20 points from the leader when scored).
- Bots have personalities: Rusher (goes out fast), Collector (saves up chained melds), Schemer (hoards power tiles).

## Layout

- `scenes/` - `main.tscn` is the entry point (UI, menus and networking are in `main.gd`)
- `scripts/core/` - `table_game.gd` rules engine (UI-free, driven by action dictionaries), `bot.gd` AI, `characters.gd`
- `scripts/meld.gd` - meld validation and scoring tables; `scripts/tile_view.gd` - procedural pixel tiles
- `shaders/` - rainy Tokyo background and CRT post effect

## Style
16-bit neo-noir Japanese cyberpunk: rainy Tokyo night shader, neon-lacquer tiles, kanji signage. Fonts: Press Start 2P and DotGothic16 (OFL, see assets/fonts).
