# Signalfall

3v3 tactical shooter made in Godot 4. Two teams, one bomb (the "signal core"), buy phase each round, first to win the set number of rounds takes the match. Inspired by Valorant / CS.

## Features

- 3v3 online multiplayer (host + join over LAN / IP, ENet)
- rounds with a buy phase, economy, plant and defuse
- weapons: Kestrel (rifle), Harrier (scoped rifle), Swift (smg), Wren (pistol), knife
- learnable spray patterns, first shot accuracy, movement inaccuracy, aim down sights
- frag and smoke grenades
- animated player models, first person arms with draw / reload / inspect animations
- impact effects, shell casings, tracers, recorded gunshot sounds
- Meridian map with a battlefield look (smoke, fires, dust)
- graphics presets (low / medium / high / ultra)
- original menu music, red dot sight on the Kestrel

## Running it

1. Install Godot 4.7 (standard version, not .NET).
2. Open `project.godot` in Godot and press play (F5).

To play online, one player picks **Host** and the others **Join** with the host's IP address. The host presses Enter in the lobby to start.

## Controls

| Key | Action |
|---|---|
| W A S D | move |
| Space | jump |
| Shift | sprint |
| Ctrl / C | crouch |
| Left mouse | shoot |
| Right mouse | aim down sights |
| R | reload |
| Y | inspect weapon |
| 1 / 2 / 3 | rifle / pistol / knife |
| G | throw frag |
| Q | throw smoke |
| E | plant / defuse |
| B | buy menu (buy phase only) |
| F | echo field ability |
| Tab | scoreboard |
| Enter | start match (host) |
| Esc | pause / release mouse |

## Project layout

- `scenes/` - main scene, maps, player, weapons, ui
- `scripts/core/` - autoloads (audio, config, events, graphics settings)
- `scripts/game/` - match flow, round states, economy, objective
- `scripts/network/` - hosting, joining, player list
- `scripts/player/` - movement, shooting, loadout, player model
- `scripts/weapons/` - weapons, recoil, grenades, viewmodel animation
- `scripts/ui/` - menus and HUD
- `data/` - weapon stats (`data/weapons/*.tres`) and match rules (`data/match_rules.tres`)
- `assets/` - models, textures, sounds, shaders

Weapon damage, recoil and fire rate are all in the `.tres` files in `data/weapons/`, round timers and money are in `data/match_rules.tres`.

## Changing sounds and music

Gun sounds are plain `.wav` files in `assets/audio/weapons/`. Replace a file with your own (same name) and Godot picks it up next time you open the project:

| File | Used by |
|---|---|
| `shot_rifle.wav` | Kestrel |
| `shot_burst.wav` | Harrier |
| `shot_smg.wav` | Swift |
| `shot_pistol.wav` | Wren |

You can also put your own files in `assets/audio/weapons_custom/` with the same names. Anything there is used instead of the stock sound.

Each one also has a `_far.wav` version (e.g. `shot_rifle_far.wav`) that plays when the shot is more than 12 m away. If you delete a `_far` file the normal one is used instead. Which weapon uses which sound is decided in `_shot_sound()` in `scripts/fx/weapon_fx.gd`.

The menu music is `assets/audio/music/menu_theme.wav`. To use your own track, replace that file and turn on looping in the Import tab (Loop Mode: Forward). Music volume per game phase is `MUSIC_BY_PHASE` in `scripts/core/audio.gd`; players can change it in the pause menu.

## Credits

See [CREDITS.md](CREDITS.md) for the third party models, textures and sounds.
