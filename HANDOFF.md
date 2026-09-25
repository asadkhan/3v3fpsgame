# HANDOFF — 3v3 Tactical FPS

Persistent project memory between AI coding agents. **Read this first, then
`README.md`** (the README documents architecture and conventions per chapter).
Verify claims against the code — this file describes intent as of its last update.

_Last updated: 2026-09-26 — Chapter 4 stabilization pass._

---

## Current state

- **Engine:** Godot 4.7.2-stable, Forward+, Jolt Physics, ENet high-level multiplayer.
- **What it is:** an original 3v3 tactical FPS. Grey-box dev build: main menu
  (Host / Join / Offline), one arena (`placeholder_environment`), one weapon
  (Kestrel), practice range, dev overlay + dev network panel.
- **Playable today:** offline or LAN host+client; move, shoot, die; the phase
  loop WARMUP → BUY → ROUND_ACTIVE → ROUND_END → BUY… runs on timers and is
  replicated to clients. **No round win condition exists yet**, so rounds only
  end on the timer with no winner and a match never ends by itself.

## Chapters

| Ch | Topic | Status |
|----|-------|--------|
| 1 | Foundation & architecture | ✅ Done |
| 2 | Player controller | ✅ Done |
| 3 | Weapons & combat | ✅ Done |
| 4 | 3v3 multiplayer | ✅ Done after the 2026-09-26 stabilization pass (below) |
| 5 | Tactical round system | 🟡 Started: phase flow, BUY respawn, phase sync. Missing win conditions, objective, economy |
| 6 | Unique mechanics | 🟡 Echo Field started early: deploy/detect works offline + online; **no echo display/UI, echoes not sent to the owning team** |
| 7 | Map | ⬜ |
| 8 | UI / HUD / menus | ⬜ |
| 9 | Art / audio / polish | ⬜ (no audio at all yet) |
| 10 | Testing / optimization / ship | ⬜ |

**Next planned work:** Chapter 5 — round win conditions (team elimination +
timeout), then the objective (buy_state docs mention a "Signal Core"; its design
is **not defined anywhere — ask the user** before building it), then economy/buy.

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

## Known issues / unfinished

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
On the host, use the dev overlay buttons: LOBBY → WARMUP starts the round loop.
Controls: WASD, Shift sprint, Ctrl/C crouch, Space jump, LMB fire, R reload,
F Echo Field, Esc release mouse.
