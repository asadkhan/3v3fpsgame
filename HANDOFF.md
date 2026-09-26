# HANDOFF — SIGNALFALL (3v3 tactical FPS)

Persistent project memory between AI coding agents. **Read this first, then
`README.md`** (the README documents architecture and conventions per chapter).
Verify claims against the code — this file describes intent as of its last update.

_Last updated: 2026-09-26 — real weapon models (Quaternius Ultimate Gun Pack, CC0) with accessories, auto sight alignment, scope overlay, third-person guns._

## Theme (keep everything consistent with this)

**SIGNALFALL** - a near-future signal war at a sun-bleached desert relay
station. Attackers carry a **Signal Core** to overload the relay; defenders
hold it. The **Echo Field** is signal recon. The map is **Meridian**.
- **Palette:** warm sandstone world; **amber** (`UITheme.ACCENT`) = signal,
  objective, highlights; **cyan** (`UITheme.TECH`) = tech (crosshair, shields,
  Echo Field, barriers, spawn trim); team blue/red only for sides.
- **Type:** Bahnschrift (`UITheme.font()`, system-font fallbacks), also on world signs.
- **Naming:** weapons are birds of prey - Wren (pistol), Swift (SMG, id
  `jackal`), Harrier (burst rifle, id `halberd`), Kestrel (rifle). Internal ids
  kept to avoid churn. Title/tagline: `UITheme.GAME_TITLE` / `GAME_TAGLINE`.
- **Map dressing:** `BlockMap._add_relay_mast / _add_pylon / _add_light_strip /
  _outline_roof` (masts with blinking beacons, site pylons, roof trim).
- The project name is now "Signalfall", so saves live in
  `%APPDATA%/Godot/app_userdata/Signalfall/`.

---

## Current state

- **Engine:** Godot 4.7.2-stable, Forward+, Jolt Physics, ENet high-level multiplayer.
- **What it is:** an original 3v3 tactical FPS (Valorant-like direction).
- **Playable today (LAN):** the full competitive loop on **Meridian** - lobby →
  BUY (20 s, spawn barriers, B = buy menu) → ROUND_ACTIVE (100 s): attackers
  carry the **Signal Core** and plant it on A or B (hold E, 4 s); defenders
  defuse (hold E, 7 s) → detonation after 40 s. Win by elimination, plant +
  detonation, defuse, or (defenders) timeout. Credits for wins/losses (loss
  streak bonus), kills and plants. Four weapons (Wren sidearm free; Jackal,
  Halberd, Kestrel buyable), slots 1/2, primary lost on death. Sides swap after
  `rounds_to_win - 1` rounds with credits and guns reset. First to 5.
  Shields: Light (+25, 400) / Heavy (+50, 1000), absorb damage before health,
  kept while alive, lost on death, cleared at half. Dead players spectate a
  living teammate after a 2 s death cam (click cycles).
  ADS (right mouse, hold or toggle in Esc menu): light zoom, tighter spread,
  less recoil, slower movement; per-weapon values in the weapon `.tres` files.
- **Feel:** weapon sway/bob/sprint pose/landing + camera bob (toggle), tracers,
  muzzle flash sprite, bullet holes, impact debris, and a full synthesized
  soundscape (3D gunshots/footsteps, hit/headshot/kill sounds, core beeps,
  round stings). Walking fast/sprinting is audible; crouching or aiming is silent.
- **Retention:** host-tracked match stats (damage, assists, HS kills, first
  bloods, plants/defuses, aces, clutches, ACS), callouts (FIRST BLOOD, DOUBLE /
  TRIPLE KILL, ACE, CLUTCH), result screen with MVP and XP, and a saved local
  profile (level, title, career stats) on the main menu; levels show in lobby
  and scoreboard.
- **Next:** the user's models/animations, then UI art polish and balancing.

## Chapters

| Ch | Topic | Status |
|----|-------|--------|
| 1-4 | Foundation, controller, combat, multiplayer | ✅ Done |
| 5 | Tactical round system | ✅ Objective, win conditions, economy, buy, shields, side swap, spectating. (Possible later: overtime, weapon drops) |
| 6 | Unique mechanics | 🟡 Echo Field works (also detects plant/defuse activity); no echo display yet |
| 7 | Map | 🟡 Meridian built and playable; needs human playtest tuning; blockout art |
| 8 | UI / HUD / menus | ✅ Core done incl. buy menu, objective prompts, credits, slots. Missing: full settings screen, minimap |
| 9 | Art / audio / polish | ⬜ NEXT - models, effects, sound, animations |
| 10 | Testing / optimization / ship | ⬜ |

## Architecture (quick map)

- Autoloads: `EventBus`, `GameConfig`, `NetworkManager`, `GameManager`.
- `scenes/core/main.tscn` — permanent router; swaps screens under `ScreenHost`
  per phase (`Main.SCREENS`). Every phase except MAIN_MENU routes to
  `playtest.tscn`, so bodies survive phase changes.
- `GameManager` — phase state machine. **Host-authoritative:** `is_authority()`
  is true offline or on the host. Host broadcasts `_receive_phase(phase, match
  dict, remaining)` on every change; late joiners get `send_snapshot_to(peer)`
  from `NetworkManager.request_spawn`. Clients may only request MAIN_MENU, or
  MAIN_MENU→LOBBY. States gate score/round mutations on `is_authority()`.
  Entering MAIN_MENU leaves any session.
- `Playtest` (`scripts/game/playtest.gd`) — the one place players are created
  (offline body, or `MultiplayerSpawner` spawn function). Sets spawn transform
  **before** tree entry. On entering BUY (authority only) respawns everyone at
  their side's marker via `Player.server_respawn_at`.
- `Player` — movement is client-owned; transform replicates through
  `net_position` / `net_yaw` (setters feed snapshot interpolation; >4 m jumps
  snap). Authority + replication config set in `_enter_tree`.
  Health/team/death/K-D are host-owned, pushed via `_net_state_receive`.
  Shots: client → `resolve_incoming_shot` RPC; host calls `_resolve_shot`
  directly (cannot RPC itself). Verdict broadcast via `_confirm_shot`.
  Respawn: host → `_net_respawn_at` RPC (call_local) → every machine resets,
  owner teleports itself.
- **Maps:** `scripts/maps/block_map.gd` (`BlockMap`) builds box geometry from
  data (world layer, matching colliders), spawn markers, BUY-only spawn barriers
  (group `spawn_barriers`) and site volumes (group `bomb_sites`, meta
  `site_name`). `scripts/maps/meridian.gd` is the layout (tables of footprints).
  `Playtest._use_environment()` loads Meridian online, the practice range offline,
  as the child named `Environment`.
- **Rounds:** `RoundActiveState` ends the round when one side is fully dead
  (only when both sides have players). `Player.die()` on the host credits the
  kill and broadcasts `_net_death_event` so `EventBus.player_died(victim, killer,
  headshot)` fires on every machine. `GameManager.return_to_menu()` = always-legal leave.
- **HUD:** `scenes/ui/hud.tscn` (in `playtest.tscn`), `scripts/ui/hud/*.gd`,
  palette/theme in `scripts/ui/ui_theme.gd` (`UITheme`). HUD only reads state.
  Inputs: Tab scoreboard, Enter start/rematch (host), Esc menu, F3 dev panels
  (hidden by default, `Main._dev_ui_shown`).
- **Names:** `GameConfig.display_name` (saved), sent in `request_spawn(name)`,
  sanitized by the host (`NetworkManager.sanitize_name`).
- **Objective:** `scripts/game/objective/signal_core_objective.gd` (node
  `Objective` in `playtest.tscn`, group `objective`). Host-authoritative:
  carrier assignment at BUY, drop/pickup, plant/defuse progress (ticked in
  `_process` on real time, same clock as the round timer - do not move it to
  `_physics_process`), replicated as a snapshot RPC. Clients only send "holding
  E". Raises `EventBus.core_planted/core_defused/core_detonated` on every
  machine. `RoundActiveState` owns the clock (switches to detonation timer on
  plant) and all win rules.
- **Economy:** `scripts/game/economy.gd` (pays rounds, half reset),
  `MatchRules` has all amounts, `PlayerState.credits` replicated in the state RPC.
- **Loadout:** `scripts/player/player_loadout.gd` (node `Loadout` under Player):
  primary + sidearm, per-weapon magazines, host-validated `request_buy`,
  slot switch broadcast so the host resolves shots with the held weapon.
  `WeaponCatalog` lists weapons by id. Firing is blocked while the mouse is free.
- **Sides:** `MatchState.attacking_side()` derives attack/defence from the round
  number (ALPHA attacks first half). Spawns are by role: attackers at
  `AlphaSpawn`, defenders at `BravoSpawn`.
- **Shields:** `PlayerState.shield` (soaked first in `PlayerState.apply_damage`),
  amounts/prices in `MatchRules`, bought via `PlayerLoadout.request_buy_shield`,
  replicated in the state RPC.
- **Spectating:** `scripts/game/spectator_camera.gd` (node `Spectator` in
  `playtest.tscn`). Local only; follows `Player.get_spectator_view()` using the
  replicated `net_position` / `net_yaw` / `net_pitch`. Teammates only.
- **ADS:** `scripts/player/player_aim.gd` (node `Aim` under Player) blends
  0..1 and exposes multipliers; `Player` applies them to FOV, sensitivity,
  spread, recoil, speed, fire interval and viewmodel position. Local only (no
  replication needed). `WeaponData.ads_*` fields; `ads_viewmodel_offset` is the
  per-model sight alignment to tune when real weapon models arrive.
- **Fire rate:** weapon cooldown carries sub-frame leftover time (capped at
  one frame), so fire intervals are exact rather than rounded up to frames.
- **View feel:** `scripts/player/player_view_feel.gd` (node `ViewFeel`) - cosmetic
  offsets of the viewmodel mount and camera local transform only.
- **Shot FX:** `scripts/fx/` - `tracer.gd`, `muzzle_flash_mesh.gd`, `bullet_hole.gd`,
  `impact_effect.gd`; `WeaponFx` decides who draws what (see its comments).
  `Weapon.Surface` (none/world/entity) travels through hitscan -> `_confirm_shot`
  -> `shot_resolved`.
- **Audio:** `scripts/core/audio.gd` autoload `Audio` synthesizes every sound at
  startup; `play(name)` flat, `play_at(name, pos)` 3D. Swap in recorded sounds
  by loading them into `_library` under the same names.
- **Stats/progression:** `scripts/game/match_tracker.gd` (node `Tracker` in
  `playtest.tscn`, host-authoritative, replicates stats + callouts);
  `PlayerState` stats + `combat_score()`; `scripts/core/profile.gd` autoload
  `Profile` (user://profile.cfg); XP is paid by `HudMatchEndPanel` once per real
  online match. Levels travel in the roster via `request_spawn(name, level)`.
- RPC rule used throughout: host→client messages on client-owned nodes are
  `any_peer` + `get_remote_sender_id() == SERVER_PEER_ID`, never `authority`.

## Stabilization pass — 2026-09-26 (what changed)

Found in audit, fixed, and verified with a real two-process host+client run
over localhost plus an offline run (Godot 4.7.2 headless, zero errors):

1. Host could not shoot online ("RPC on yourself is not allowed") → direct call.
2. Host-side bodies (incl. host's own) spawned at world origin → transform set in spawn function.
3. `main.tscn` held a hidden-but-live duplicate arena (2 turrets, 6 targets, duplicate colliders) → placeholder now instanced only when a phase has no screen.
4. Remote interpolation never received snapshots → replicate `net_position`/`net_yaw`.
5. Phases ran independently on every machine → host-authoritative phase replication.
6. BUY state: wrong marker path, nonexistent `weapon.reset_ammo()`, self-RPC offline, wiped K/D each round → rewritten; respawn moved to `Playtest`.
7. Networked respawn impossible (client owns transform; clients kept corpse state) → `server_respawn_at` / `_net_respawn_at`; state sync also revives.
8. Kills never credited, `EventBus.player_died/player_damaged` never emitted → fixed in `die()` / `apply_damage()`; K/D replicated.
9. Weapon spread never applied → applied in `_on_weapon_fired`.
10. `WeaponFx` found Head instead of Player → walks up; clients now draw impacts for all shots (`shot_resolved.is_local` = "this machine ran the raycast").
11. Hit marker flashed on misses online → `hit` flag from `Weapon.last_damage_dealt`.
12. Practice turret fired on clients (health desync) → authority only.
13. Echo Field: followed the player, never deployable online, wrong RPC authority, not in group, typed-array crash, invisible material → fixed.
14. Offline auto-respawn used `await` on a timer (resume-after-free risk) → ticked timer (still marked TEMPORARY).
15. Synchroniser authority set in `_ready` ("no network ID" errors) → `_enter_tree`; initial state RPC no longer races the spawn.
16. Dev panel Host/Join from inside a match left the offline body → handled in `Playtest`.
17. Main menu kept a captured mouse after returning from a match → released.
18. Orphan `round_start_state.gd.uid` removed; README phase diagram, node tree and Kestrel table corrected.
19. **Host view jumped above the map when a player joined** (user-reported). `player.tscn`'s camera was `current = true`, so each new body stole the view and releasing it passed it to the arena's `OverviewCamera`. Camera is now non-current in the scene; only the local body calls `make_current()`, remote bodies `clear_current(false)`; `Playtest` frees the overview camera. Verified with host + 2 clients, windowed.
20. Clients freed departing players' bodies themselves, so the host's despawn then errored (`recv_nodes.has(net_id)`) → on a live client the spawner removes them.

## Weapon models

Source: Quaternius **Ultimate Gun Pack** (CC0), FBX, in
`assets/weapons/quaternius/` (+ `Accessories/`). Models point along +X in
large units; each weapon has a scene in `scenes/weapons/models/` that turns it
to -Z, scales it by 0.16 (a rifle is ~0.83 m) and mounts accessories:

| Weapon | Model | Accessories |
|---|---|---|
| Wren | Pistol_5 (root scaled 0.8) | - |
| Swift | SubmachineGun_3 | Flashlight |
| Harrier | AssaultRifle2_3 | Scope_3 (scope overlay, ADS zoom 1.8) |
| Kestrel | AssaultRifle2_1 | Grip, Flashlight |

Each scene has a `Muzzle` marker (tracers/flash start) and a `Sight` marker.
`WeaponData.viewmodel_scene` points at it; `Weapon._apply_model()` swaps it in
on equip; `PlayerAim.viewmodel_offset()` lines the Sight up with the eye at
`WeaponData.ads_sight_distance` automatically. `WeaponData.scope_overlay`
hides the model when fully aimed and shows `HudScopeOverlay`. Remote players
carry the same model (`Player._refresh_third_person_weapon`, under the head,
follows replicated pitch). To add a gun: make a model scene with Muzzle +
Sight markers, point a WeaponData at it, tune the root position for hip framing.

## Diagnostics pass (2026-09-26)

Two code reviews plus scripted 3-player matches (buy, shields, plant/defuse,
detonation, side swap, spectating, rematch, leave, host quit, late join).
Fixed: shared capsule resource (crouch shrank everyone's hitbox), crouch not
replicated (`net_stance`), over-strict host fire-rate check (now a token
bucket), spectator error on teammate disconnect, clients looping rounds after
the host quit (now back to menu with a reason), late joiners (starting credits,
dead if mid-round), late join during a plant, sidearm refill, echo fields
missing shots, team kills counted, stale stats after rematch, XP farmable via
skipping to MATCH_END / lost on quick rematch, MVP with zero score, buy menu vs
Esc, dev-panel keyboard focus, effects outliving the match, half-time reset
faking damage/purchase sounds, BBCode injection via names, settings written on
every slider tick. Final runs: zero errors on every machine.

## Known issues / unfinished

- Two instances on one PC share `user://settings.cfg`, so they default to the same saved name — type different names in the menu.
- Testing two windowed instances on one laptop overloads it: the background instance's game clock slows (Godot caps frame delta). Real matches on separate PCs are unaffected; for local tests prefer lower resolution.
- Halberd's "rpm" on the buy card uses its in-burst interval.
- The core has no explosion visual yet (sound exists).
- Profile/XP is local per machine (no account server); a player could edit their own file.
- Automated probes run inside the project write to the same `user://` as the real game; clear `user://profile.cfg` and the saved name after testing.
- Dead players look at the floor; there is no spectate-teammate camera yet.
- Kestrel viewmodel is a placeholder block model; no audio anywhere.

- No round win conditions, objective, economy, buy menu (Chapter 5).
- Echo Field: no visual echoes / UI; echoes stay on the host (Chapter 6).
- Practice targets only topple on the host when a client shoots them (grey-box only; removed in Ch. 7).
- A late joiner sees other players' K/D as 0 until their next change (roster carries health/team only).
- Players are not frozen during BUY.
- `player.gd` is ~2000 lines — split into components (movement / combat / net / abilities) before it grows further.
- Client-authoritative movement: fine for dev/LAN, a cheating risk for public play.
- No automated test suite in the repo. The probes used for verification were throwaway.

## How to test locally

Run two instances (Godot editor: Debug → Customize Run Instances → 2, or run the
exported exe twice). Instance 1: **Host**. Instance 2: **Join** (127.0.0.1).
In the lobby the host presses **START MATCH** (or Enter). Tab = scoreboard, Esc = menu, F3 = dev panels.
Controls: WASD, Shift sprint, Ctrl/C crouch, Space jump, LMB fire, R reload,
F Echo Field, E plant/defuse, B buy (buy phase), 1/2 weapons, Tab scoreboard, Esc menu, F3 dev panels.
