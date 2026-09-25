# HANDOFF — 3v3 Tactical FPS

Persistent project memory between AI coding agents. **Read this first, then
`README.md`** (the README documents architecture and conventions per chapter).
Verify claims against the code — this file describes intent as of its last update.

_Last updated: 2026-09-26 — Chapter 7 (map) + Chapter 8 core (HUD/menus) + round win conditions._

---

## Current state

- **Engine:** Godot 4.7.2-stable, Forward+, Jolt Physics, ENet high-level multiplayer.
- **What it is:** an original 3v3 tactical FPS (Valorant-like direction).
- **Playable today:** a complete match loop over LAN on the map **Meridian**:
  styled main menu (name, Host / Join / Practice) → lobby (host presses
  START / Enter) → WARMUP → BUY (spawn barriers up) → ROUND_ACTIVE → a side is
  eliminated → ROUND_END → … first to 5 → MATCH_END (VICTORY / DEFEAT, host
  REMATCH / anyone LEAVE). Full HUD. Offline = practice range with targets/turret.
- **Still missing for the Valorant loop:** objective (plant/defuse), economy +
  buy menu, more weapons, attack/defence side swap, audio, real art/animations.

## Chapters

| Ch | Topic | Status |
|----|-------|--------|
| 1 | Foundation & architecture | ✅ Done |
| 2 | Player controller | ✅ Done |
| 3 | Weapons & combat | ✅ Done |
| 4 | 3v3 multiplayer | ✅ Done (stabilization pass 2026-09-26) |
| 5 | Tactical round system | 🟡 Phase flow, host-authoritative sync, BUY respawn, **elimination win condition** done. Missing: objective, economy/buy, side swap, timeout-to-defenders |
| 6 | Unique mechanics | 🟡 Echo Field deploys/detects offline + online; no echo display, echoes not sent to owning team |
| 7 | Map | 🟡 **Meridian** built (3 lanes, 2 sites with site volumes, raised positions, spawn barriers, callouts). Needs playtesting/tuning; blockout-level art |
| 8 | UI / HUD / menus | 🟡 Core done: HUD (top bar, health/ammo/ability, crosshair, kill feed, announcer, scoreboard, damage vignette), lobby, match-end, Esc menu w/ sensitivity + FOV, themed main menu. Missing: buy menu, full settings screen, minimap |
| 9 | Art / audio / polish | ⬜ (no audio at all yet) |
| 10 | Testing / optimization / ship | ⬜ |

**Next planned work (recommended order):** objective ("Signal Core" plant/defuse
using the `bomb_sites` Area3Ds already on Meridian — confirm design with the
user) → economy + buy menu (needs Jackal/Halberd runtime support) → attack/defence
side swap at half → audio pass → map tuning from playtests.

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

## Known issues / unfinished

- Two instances on one PC share `user://settings.cfg`, so they default to the same saved name — type different names in the menu.
- Timeout rounds are a draw (no score) until an objective defines attackers/defenders.
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
F Echo Field, Esc release mouse.
