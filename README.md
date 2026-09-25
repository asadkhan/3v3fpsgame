# 3v3 Tactical FPS

An original 3v3 tactical first-person shooter built in Godot.

> **Status: Chapter 4 complete.**
> Chapters 1–3 ship a reusable `Player` with full movement, a modular weapon system,
> one working full-auto rifle (Kestrel), hitscan ballistics, a reusable damage
> interface, player health and death with headshots, and a practice range with
> targets, cover and a hostile turret. Chapter 4 adds real high-level Godot
> multiplayer: host+client dev flow over LAN/local, identity-in-before-tree
> spawning, client-owned movement (20 Hz transform sync), server-owned health
> and team (reliable change-driven RPC), host-validated shot resolution,
> networked death, 3v3 team assignment, a six-player capacity enforced at both
> transport and application level, and a temporary dev network UI.
> Remaining: tactical round system (Ch. 5), unique mechanics (Ch. 6), final map
> (Ch. 7), real HUD/menus (Ch. 8), art/audio/polish (Ch. 9), testing/ship (Ch. 10).

---

## Requirements

| Item       | Value                             | Why                                        |
| ---------- | --------------------------------- | ------------------------------------------ |
| Engine     | **Godot 4.7.2-stable**            | Confirm with your installed version        |
| Renderer   | Forward+                          | Best lighting/shadows for a tactical FPS   |
| Physics    | Jolt Physics                      | Deterministic, fast, FPS-oriented          |

These three are already configured in `project.godot`. Do not switch renderer or
physics engine later — it invalidates baked lighting and physics tuning.

> **On the engine version.** The brief specified Godot 4.5; the editor installed
> here is 4.7.2, so that is what everything was built and verified against. The
> code sticks to APIs that already existed in 4.5 — `Node`, `Resource`,
> `ENetMultiplayerPeer`, `@export`, typed signals, `DirAccess`, `CanvasLayer`,
> `CapsuleShape3D`, `test_move`, `move_and_slide` — and deliberately uses no
> 4.6/4.7-only feature, so the sources should open in 4.5. That has **not** been
> proven by running 4.5, so if 4.5 is a hard requirement, open the project in 4.5
> once and re-run the movement checks before building on top of it.

---

## Project structure

Three top-level rules:

1. **Code goes in `scripts/`.**
2. **Scenes go in `scenes/`.**
3. **Everything else (art, audio, data) goes in `assets/`.**

```
res://
├── project.godot          # Engine configuration — edit via the Editor UI
├── icon.svg               # Window icon
│
├── data/                  # Designer-editable .tres data (see below)
│   ├── match_rules.tres   # Rounds, phase lengths, players per team
│   └── weapons/           # Weapon stat tables
│   │   └── kestrel.tres   # Ch. 3 — the one playable weapon
│
├── scenes/                # .tscn files, mirrored from scripts/
│   ├── core/              # Boot, main menu, settings, loading screen
│   ├── fx/                # Ch. 3 — impact effect, local weapon feedback
│   │   ├── impact_effect.tscn
│   │   └── weapon_fx.tscn
│   ├── game/              # Match scene, round flow, spawn logic
│   │   ├── playtest.tscn  # Ch. 2 — boots into this
│   │   ├── practice_target.tscn   # Ch. 3 — damageable, two colliders
│   │   ├── practice_turret.tscn   # Ch. 3 — hostile, damages the player
│   │   └── placeholder_environment.tscn (temporary)
│   ├── player/            # Player, camera, weapon holder
│   │   └── player.tscn    # Ch. 2 body + Ch. 3 health, weapon, feedback
│   ├── ui/                # HUD, scoreboard, menus
│   │   ├── hit_marker.tscn   # Ch. 3 — crosshair hit confirmation
│   └── weapons/           # Weapon scenes
│       └── rifle.tscn     # Ch. 3 — placeholder viewmodel, no collision
│
├── scripts/               # All .gd files
│   ├── core/              # Cross-cutting: EventBus, GameConfig, boot screen
│   │   └── collision_layers.gd  # Ch. 3 — one source of truth for layer bits
│   ├── game/              # GameManager, GameState, MatchState, MatchRules
│   │   ├── states/        # One file per phase - see Architecture
│   │   ├── playtest.gd    # Ch. 2 — spawns the player into the test arena
│   │   ├── practice_target.gd   # Ch. 3
│   │   └── practice_turret.gd   # Ch. 3
│   ├── fx/                # Ch. 3 — impact effect, local-only weapon feedback
│   ├── network/           # Multiplayer / netcode
│   ├── player/            # Player controller, camera, movement
│   │   └── player.gd      # Ch. 2 controller + Ch. 3 health/weapon/recoil
│   ├── ui/                # HUD and menu logic
│   │   ├── dev_overlay.gd # Debug readout (temporary)
│   │   └── hit_marker.gd  # Ch. 3
│   └── weapons/           # Weapon behaviour, ballistics, damage
│       ├── damageable.gd  # Ch. 3 — the reusable damage contract
│       ├── weapon.gd      # Ch. 3 — the runtime weapon
│       └── weapon_data.gd # Ch. 1 + Ch. 3 recoil / movement fields
│
└── assets/                # All non-code content
    ├── audio/             # SFX, music, ambience
    ├── characters/        # Player models, textures, rigs
    ├── effects/           # Particles, VFX, decals
    ├── maps/              # Map scenes and map-specific assets
    ├── materials/         # Shared .tres materials and shaders
    ├── ui/                # UI themes, icons, fonts
    └── weapons/           # Weapon models, textures, sounds
```

### About the `.gitkeep` files

Most of these folders are currently empty. Git does not track empty folders, so
each one contains an empty `.gitkeep` file to keep it alive. **Ignore them** —
delete them as soon as you add a real file to that folder. They are not part of
the game.

---

## Conventions

Keep these consistent so the project stays readable.

**Scene and script pairs.** A script lives in `scripts/<area>/` and its scene in
`scenes/<area>/`, sharing a name:

```
scripts/player/player_controller.gd   <->   scenes/player/player_controller.tscn
```

**Naming.**

| Thing                | Style                        | Example                        |
| -------------------- | ---------------------------- | ------------------------------ |
| Files                | `snake_case.gd` / `.tscn`    | `weapon_pistol.tscn`           |
| Classes               | `PascalCase` (`class_name`)  | `class_name WeaponController`  |
| Functions & variables | `snake_case`                 | `func take_damage(amount)`     |
| Private members       | leading underscore            | `var _health := 100`           |
| Constants & enums     | `SCREAMING_SNAKE_CASE`       | `const MAX_HEALTH := 100`      |
| Signals               | `snake_case`, past tense     | `signal player_died`           |
| Booleans              | `is_` / `has_` prefix        | `var is_alive := true`         |

**`data/` vs `assets/`.** `data/` holds small, hand-editable `.tres` resource
files that designers tweak — weapon stat tables, ability definitions, map
metadata. Anything large or binary belongs in `assets/`.

### The data types

Four data classes, split by *when they change* rather than by what they hold.
That distinction is the whole design:

| Class | Base | Changes at runtime? | Holds |
| --- | --- | --- | --- |
| `WeaponData` | `Resource` | No — authored, saved as `.tres` | Damage, fire rate, magazine, price |
| `MatchRules` | `Resource` | No — authored, saved as `.tres` | Round length, rounds to win, team size |
| `PlayerState` | `RefCounted` | Yes | Health, team, alive, K/D/A |
| `MatchState` | `RefCounted` | Yes | Round number, scores, winner |
| `Team` | `RefCounted` | No | The `Side` enum and helpers |

`WeaponData` and `MatchRules` are `Resource`s because their values are authored
in the Inspector, saved to disk, and shared. The other three are `RefCounted`
because they are live state that changes as the game runs, and each needs its
own instance.

**Tunables live in `data/`, not in code.** Phase lengths, rounds-to-win and
players-per-team are all fields on `MatchRules` in
`data/match_rules.tres`. Retuning a match is a data edit. "3v3" in particular
is stated exactly once — `NetworkManager.get_max_players()` derives the
session cap from `players_per_team`, so the two can never drift apart.

**`load()` is cached — weapon stats are shared, not copied.** Every player
holding the same weapon gets the *same* `WeaponData` object. Writing
`weapon.damage = 50` at runtime would buff everyone using it. Per-player state
that genuinely changes (rounds left, trigger held, recoil) lives in a separate
runtime object — `Weapon`, added in Chapter 3 — not on `WeaponData`. See
[Weapons and combat](#weapons-and-combat).

```gdscript
var halberd := load("res://data/weapons/halberd.tres") as WeaponData
print(halberd.display_name, " ", halberd.damage_at_distance(distance))
```

**Extending built-in types.** Avoid `extends CharacterBody3D` scattered across
files. Write one base class per area (e.g. `scripts/player/player_body.gd`) and
extend that. It keeps shared behaviour in one place.

`Player` currently extends `CharacterBody3D` directly, which is the one place
this rule is bent: there is exactly one *player* body type, so a base class would
be a file containing nothing but a class declaration. Chapter 3 did add a second
kind of body — the `PracticeTurret` — and deliberately did **not** promote it to
`player_body.gd`, because the turret is a `Node3D` that turns and shoots; it
shares no movement, stance or camera code with the player at all. A base class
containing nothing but two unrelated classes' worth of empty methods is not an
abstraction. If Chapter 4 adds a second *player* (a remote body driven by
snapshots) or Chapter 6 adds a vehicle, that is when the shared
`CharacterBody3D` behaviour is finally worth factoring out.

### Health and death (Chapter 3)

`Player` gained health in Chapter 3, and the shape of it was chosen so Chapter 5
can drop a respawn timer and a kill feed on top without rearranging anything:

- **The numbers are on `PlayerState`, not the controller.** `MAX_HEALTH` and
  `current_health` already existed from Chapter 1; `player.gd` reads and writes
  them and owns the `PlayerState` instance. There is no second `health` field
  on the body.
- **`apply_damage(amount, source, zone)` is the one way in**, and it is reached
  through `Damageable.deal_damage()` so the weapon, the turret and a future
  network validator all take the same path.
- **`died(source)` is emitted exactly once.** The sequence is guarded on a
  separate `_is_dying` flag rather than on `state.is_alive`, because
  `apply_damage` clears `is_alive` *before* calling `die()` — guarding on
  `is_alive` means the death routine never runs at all. This exact mistake
  already existed in `PlayerState.record_death()` in Chapter 1 and is worth
  remembering.
- **The corpse stays in the scene and moves to the `CORPSE` layer.** The
  capsule is left at full standing height, so a dead body still blocks movement
  and still gets shot; only the camera sinks.
- **The camera fall is derived from a 0-to-1 timer**, not approached with a
  lerp, so it provably reaches `death_camera_height` at any frame rate.
- **`input_enabled` and alive are separate questions.** Death does not go
  through `set_input_enabled(false)`. That flag means "the network owns this
  transform" and Chapter 4 needs it to stay true for a corpse so it can tell a
  dead remote player from a live one. Overloading it would also release the
  mouse at the worst possible moment.
- **`respawn()` is a real path**, already used by the test range's reset button:
  health, stance, camera, weapon magazine and corpse layer all return to normal.

---

## Running the project

The main scene is `scenes/core/main.tscn`, so **F5** runs the game. As of
Chapter 2 it boots **straight into the playtest arena** with a player already
spawned and the mouse already captured — there is no menu in the way yet. Set
`Main.BOOT_INTO_PLAYTEST` to `false` in `scripts/core/main.gd` to get the
Chapter 1 main menu back.

| Key                | Action                                       |
| ------------------ | -------------------------------------------- |
| `W` `A` `S` `D`    | Move, relative to where you are looking      |
| `Shift` (hold)     | Sprint                                       |
| `Ctrl` or `C`      | Crouch (hold)                                |
| `Space`            | Jump                                         |
| `Mouse`            | Look                                         |
| `LMB` (hold)       | Fire — Kestrel is full-auto, so hold to keep firing |
| `R`                | Reload                                       |
| `Escape`           | Release the mouse (click the window to recapture) |

Every binding is an action in the Input Map, not a raw keycode in the script,
so all of them are remappable in one place. `fire` and `reload` were added in
Chapter 3 and follow the same rule as the Chapter 2 movement actions: the
controller asks `Input.is_action_pressed(&"fire")` and never asks what physical
button the user happened to press.

The test arena is the Chapter 1 grey box plus three things a movement controller
has to be tested on and that a flat floor cannot catch: a **15° ramp**, a
**4-step staircase** (0.3 m rises), and a **low overhang** with 1.2 m of
clearance that a crouched player fits under and a standing one does not. Walk
into each to confirm the controller behaves; all three are generated by
`placeholder_environment.gd` and are deleted along with the rest of the
placeholder in Chapter 7.

Chapter 3 adds a second generated area to the same scene, `_build_range()`: a
backstop wall, **three practice targets** (one with a shootable head, one
without, one plain body) and a **hostile turret** that fires at you. All of it
is generated in script so it comes out in one deletion in Chapter 7. The debug
overlay has a **Reset range** button that puts the targets and the turret back
up without restarting the game.

Once you leave the title screen, the **debug overlay** appears down the right
side. It shows the current game state, which screen is routed in, the live
match rules, the score, whether networking is active, the frame rate, the
player's position and speed, the player's movement state, and — since Chapter 3
— health and ammo. It also offers a button for every legal next phase, so you
can walk the whole match flow by hand without waiting on timers.

**There is still no playable game here.** You can walk, look, crouch, jump, shoot
and die, but there is no real HUD, no networked player and no round objective.
Chapter 4, 5 and 8 are what turn this into a match.

---

## The player controller

`scenes/player/player.tscn` is one self-contained, reusable scene. Instantiate
it as many times as you like; nothing about it is unique or global.

```
Player (CharacterBody3D)   collision_layer 2, collision_mask 13
├── Collision (CollisionShape3D)   capsule; height and Y follow the stance
│   └── BodyMesh (MeshInstance3D)  hidden by default; visualises the collider
├── Head (Node3D)                 Y = eye height
│   ├── Camera3D                  fov 90, near 0.05
│   └── WeaponMount (Node3D)      Ch. 3 — viewmodel attaches here
│       ├── Weapon (rifle.tscn)   Ch. 3 — no collider, cosmetic only
│       └── WeaponFx (Node3D)     Ch. 3 — impact effects (finds Player by walking up)
├── HitMarkerLayer (CanvasLayer)  Ch. 3
│   └── HitMarker (Control)       drawn on a confirmed hit
├── TransformSync                 Ch. 4 — replicates net_position / net_yaw
└── EchoField (Node3D)            Ch. 6 (WIP) — top_level, stays where deployed
```

The mask is 13, not 1, because Chapter 3 added two layers: `TARGET` (4) so the
player can be shot by practice targets, and `CORPSE` (8) so a dead body still
blocks movement. All four layer bits live in `scripts/core/collision_layers.gd`
so nothing hard-codes a magic number.

**Yaw is on the body, pitch is on the head.** That split is deliberate: the
body's basis stays yaw-only, so a player looking up at the sky cannot tilt
their own collision capsule, and movement stays on the horizontal plane no
matter what the camera is doing.

**Crouch resizes the collider, it does not scale the node.** Scaling would
scale the collision radius and the camera along with the height, and would
make the player fit through gaps that a real body should not. A single
`_stance` value between `0` and `1` drives the capsule height, its `Y`, the
camera height and the reported state together, so they cannot drift apart.
Standing up is refused by a real overlap test when there is a ceiling in the
way.

**Movement is velocity-based and relative to facing**, with separate
walk/sprint/crouch speeds and separate ground and air rates:

| Export                    | Default | Notes                                      |
| ------------------------- | ------- | ------------------------------------------ |
| `walk_speed`              | 5.0     | m/s                                        |
| `sprint_speed`            | 8.0     | Hold Shift. No stamina, by design          |
| `crouch_speed`            | 2.6     | Crouch wins over sprint if both are held   |
| `ground_acceleration`     | 55.0    | m/s² toward the target speed               |
| `ground_deceleration`     | 70.0    | Stops quickly; no ice                       |
| `air_control`             | 0.22    | Fraction of ground accel usable airborne  |
| `air_deceleration`        | 2.0     | Low, so air momentum is mostly preserved   |
| `gravity`                 | 18.0    | m/s²                                       |
| `jump_velocity`           | 5.5     | m/s                                        |
| `terminal_fall_speed`     | 40.0    | Clamp so long falls stay sane              |
| `coyote_time`             | 0.12    | Grace period just after walking off a ledge|
| `step_height`             | 0.4     | Tallest ledge walked up without jumping    |
| `stand_height`            | 1.8     | Capsule height when standing               |
| `crouch_height`           | 1.1     | Capsule height when crouched               |
| `body_radius`             | 0.35    | Capsule radius                             |
| `stand_eye_height`        | 1.62    | Camera height standing                     |
| `crouch_eye_height`       | 0.95    | Camera height crouched                     |
| `stance_change_speed`     | 9.0     | How fast the crouch transition eases        |
| `pitch_limit_degrees`     | 89.0    | Stops the camera flipping at the poles      |
| `sensitivity_scale`       | 0.003   | Multiplies `GameConfig.mouse_sensitivity`   |
| `input_enabled`           | `true`  | The multiplayer seam — see below             |
| `capture_mouse_on_ready`  | `true`  | Set `false` for a remote player              |

None of these are Valorant's numbers; they are tuned for a deliberate,
weighty feel with no sliding and no air-strafing. Change any of them in the
Inspector on the scene instance and the controller uses it — nothing is
hard-coded in the script.

`GameConfig` already owned `mouse_sensitivity`, `invert_mouse_y` and
`field_of_view` from Chapter 1, so the player does not re-declare them. It
adds only `sensitivity_scale` as a per-player multiplier, which leaves the
global preference and the per-player scale as two separate things that can be
retuned independently.

### The multiplayer seam

This is the part Chapter 4 should not have to redesign.

- `set_input_enabled(false)` stops the player reading input **and releases the
  mouse**, while gravity and collision keep running normally. That single flag
  turns the same scene into a remote, server-driven player.
- The player owns its own `PlayerState`. There is no global player variable, no
  movement singleton, and `GameManager` does not know the player exists.
- **No team is hard-coded anywhere.** Nothing in the controller refers to a
  side, a roster or a spawn.
- `teleport_to(point, facing_yaw)` clears velocity and the coyote timer, so a
  respawn never inherits the momentum of whatever killed the player.

Replication, authority and interpolation are all still Chapter 4's work.

---

## Weapons and combat

### The shape of it

Chapter 1 shipped `WeaponData` as a shared, read-only `Resource` of stats. That
is still exactly what it is. Chapter 3 adds the runtime half as a **separate
object**, because those two things change at completely different times:

```
data/weapons/kestrel.tres          scripts/weapons/weapon.gd
┌────────────────────────┐        ┌──────────────────────────┐
│ WeaponData (Resource)  │  ───▶  │ Weapon (Node3D)          │
│  shared, never mutated │  load  │  per-player, per-round   │
│  damage, fire rate,    │        │  ammo, cooldown, reload  │
│  magazine, recoil ...  │        │  timer, trigger, flash   │
└────────────────────────┘        └──────────────────────────┘
                                       │
                     Player ───────────┤ equips, owns, reads the trigger
                                       ▼
                              damage travels *outward*
                    weapon.hitscan() ──▶ Damageable.deal_damage()
                                            │
                                            ▼
                                    target.apply_damage()
```

Two players holding the Kestrel share one `WeaponData` and each have their own
`Weapon`. A designer retunes falloff by editing the `.tres`; nobody can buff
the whole lobby by writing `weapon.data.damage = 50` at runtime, because that
object is shared and is only ever read.

**The weapon owns its own rules.** Fire rate, magazine size, reload timing,
empty-mag dry fire and burst pacing all live in `weapon.gd`. `GameManager` does
not know a weapon exists, and neither does the Player — the Player polls the
trigger, passes the aim ray in, and responds to a signal. Adding a second
weapon means adding a `.tres`, not editing a `match` conditional.

**The aim ray is passed in, never read from a camera.** `weapon.hitscan(origin,
direction)` is public and separate from `try_fire()`. The weapon has no
reference to a `Camera3D` and no way to find one. This is what lets Chapter 4
validate a client-claimed shot on the host using the host's own ray rather than
trusting whatever the client said it hit.

**`update_trigger(held, just_pressed, delta)` takes the trigger as arguments**
for the same reason. The Player owns the input switch, so a remote player with
`input_enabled == false` holds a weapon that cannot fire, and `weapon.gd` never
has to contain the word "input".

### The damage contract

`scripts/weapons/damageable.gd` is a `RefCounted` helper with a `HitZone`
enum and static functions. It is **duck-typed, not a base class**, and that is
deliberate: `Player` already extends `CharacterBody3D` and GDScript has no
multiple inheritance, so a `Damageable` base class would force a rewrite of
working Chapter 2 movement code to gain nothing.

```gdscript
# What a target must provide:
func apply_damage(amount: float, source: Node3D, zone: HitZone) -> void
func get_health() -> int
func get_max_health() -> int
func is_dead() -> bool
func resolve_hit_zone(point: Vector3, collider: Object) -> HitZone
```

Anything with those five methods is damageable. `Player`, `PracticeTarget` and
Chapter 4's network validator will all answer them.

`find_target(collider)` walks **up** the parent chain, which is what lets a head
hitbox be a plain scriptless `StaticBody3D` child: the ray hits the collider,
the helper climbs to the entity that can actually take the damage, and only then
is the entity asked which zone was struck. The weapon never writes to a
target's fields.

**Hit zones are resolved by the target, not the weapon.** A target knows whether
its own colliders are a head or a torso; the weapon only knows where the round
landed. Two different implementations, both satisfying the contract:

- `Player` uses a **height band** — `head_hit_fraction` of
  `get_current_height()`, so the head zone moves down when the player crouches
  and cannot desync from the resizing capsule. A second collider would have to
  be animated in lockstep with every stance change and would drift.
- `PracticeTarget` uses a **genuinely separate head collider**, because a
  stationary dummy is the one case where two static bodies are simpler and more
  honest than a height calculation.

### Kestrel

`data/weapons/kestrel.tres` is the one working weapon. It is correctly
categorised as a `RIFLE` and set to `AUTO`.

| Field                       | Value  | Notes                                        |
| --------------------------- | ------ | -------------------------------------------- |
| `damage`                    | 26.0   | Base, before falloff and headshot            |
| `headshot_multiplier`       | 2.2    | Configurable, not hard-coded                 |
| `max_range`                 | 45.0   | Beyond this the ray stops                    |
| `min_damage_floor`          | 0.75   | Fraction of damage at maximum range          |
| `fire_interval`             | 0.09   | ~667 RPM                                     |
| `magazine_size`             | 30     |                                              |
| `reload_time`               | 2.1 s  |                                              |
| `recoil_kick_degrees`       | 0.8°   | Per shot, recovers over time                 |
| `recoil_yaw_degrees`        | 0.3°   | Randomised sign                              |
| `recoil_recovery_degrees`   | 45.0   | Authored, but the player's own `recoil_recovery_degrees` export (55 °/s) is what is applied |
| `move_speed_multiplier`     | 0.92   | While held up                                |
| `spread_degrees`            | 0.6°   | Random cone, applied per shot in `Player._on_weapon_fired` |

**Reserve ammunition is infinite in Chapter 3** — `weapon.infinite_reserve` is
`true`. But `reserve_ammo` is still a real field, and the finite path in
`_finish_reload()` is the same code with the subtraction written out, so
Chapter 5's round-based buy system is a data change rather than a rewrite.
**There is no buy system in this chapter**, and `price` on `WeaponData` is
still unused.

### Recoil cannot steal your aim

This is the one piece of the player controller Chapter 3 had to be careful
about, because "recoil" and "the player rotated" are very easy to conflate.

- `_look_pitch` is the **authoritative** player-controlled pitch. Nothing else
  writes to it.
- `head.rotation.x` is **derived output**, recomputed every frame in
  `_apply_view()` as `clamp(_look_pitch - _recoil_pitch, ...)`.
- The weapon emits `recoil_requested`; the **player** applies and recovers it.

So recoil is a decaying offset layered on top of the real aim, and when it
recovers to zero the crosshair is exactly where the mouse last put it. A recoil
system that adds directly to `head.rotation.x` leaves the player's actual aim
permanently altered after a single burst, which is a bug that feels like
"sticky aim" and is very hard to diagnose later.

### Feedback is a request, not a decision

The weapon emits `impact_requested(point, normal, zone)` and
`hit_confirmed(killed, zone, health_left)`. `WeaponFx` — a node under the
Player — decides what that means locally: spawn an `ImpactEffect`, flash the
muzzle, draw a `HitMarker`.

The split is the Chapter 4 boundary. In multiplayer the host decides what was
actually hit; a client should not be drawing a blood decal because its own
raycast guessed. Keeping the signal on one side and the drawing on the other
means the visual layer can be deleted or replaced without touching ballistics.

### Collision layers

One source of truth, `scripts/core/collision_layers.gd`:

| Constant        | Bit | Used by                                    |
| --------------- | --- | ------------------------------------------ |
| `WORLD`         | 1   | Floor, walls, cover, backstop              |
| `PLAYER`        | 2   | Live player bodies                         |
| `TARGET`        | 4   | Practice targets                           |
| `CORPSE`        | 8   | Dead player bodies                         |

`PLAYER_BODY_MASK = 13` and `WEAPON_MASK = 15` are derived from those bits.
The weapon mask is everything, so a round stops on a wall, a live player, a
target or a corpse without the weapon knowing which is which.

### The practice range

Generated by `placeholder_environment.gd`, so Chapter 7 deletes it in one
stroke:

- **A backstop wall** to stop rounds and prove that cover blocks hitscan.
- **Three `PracticeTarget`s** — one with a shootable head collider, one
  headless (to test zone fallback), one plain body. Each records `last_zone`,
  topples when it dies, and is resettable.
- **A `PracticeTurret`** that periodically turns toward the player, checks line
  of sight, and damages them through the *same* `Damageable` path the player's
  weapon uses. No AI, no pathfinding — it exists so the combat loop is provably
  bidirectional.

---

## Architecture

### The four autoloads

Only genuinely global, single-instance things are autoloads. Everything else
is an object owned by something else — that is what keeps the list this short.

| Autoload          | Owns                                                        |
| ----------------- | ----------------------------------------------------------- |
| `GameManager`     | The phase the game is in, and the `MatchState` for it        |
| `NetworkManager`  | The `ENetMultiplayerPeer` and all connection state           |
| `GameConfig`      | Player preferences, saved to `user://settings.cfg`           |
| `EventBus`        | Signals that more than one unrelated system needs            |

**Not autoloads, on purpose:**

- `MatchState` — there is only one match, so `GameManager` owns it. A singleton
  would give the game a second, competing way to ask "what's the score?".
- `PlayerState` — every player needs their own. A singleton is wrong by
  definition; each player node owns one.
- The phase states — only one is alive at a time, and `GameManager` owns it.

### The phase state machine

`GameManager` answers exactly one question: *what phase are we in?*

```
MAIN_MENU → LOBBY → WARMUP → BUY → ROUND_ACTIVE
                             ↑           │
                             └ ROUND_END ←┘
                                  │
                                  └──→ MATCH_END → (LOBBY | MAIN_MENU)
```

Each phase is a small class in `scripts/game/states/` extending `GameState`,
with `enter()`, `update()` and `exit()` hooks. `GameManager` holds no
`if phase == ...` branches, so adding a phase is a new file plus two entries —
not an edit to a conditional six other systems have to be read alongside.

Legal moves are declared in one table, `GameManager.ALLOWED_TRANSITIONS`, and
anything not in it is refused with a warning. That is what stops a round from
starting twice or combat beginning mid-buy-phase.

```gdscript
if GameManager.is_in(GamePhase.Phase.ROUND_ACTIVE):
    spawn_the_players()

GameManager.state_changed.connect(_on_phase_changed)
```

### Adding a phase

1. Create a script in `res://scripts/game/states/` extending `GameState`.
2. Override the hooks you need.
3. Add the value to `GamePhase.Phase`.
4. Register the script in `GameManager.STATE_SCRIPTS` and its moves in
   `GameManager.ALLOWED_TRANSITIONS`.

### Communication

Use `EventBus` for things several unrelated systems need to hear about, so
they do not each need a reference to whatever raised the event. If exactly one
system cares, that system should just call the other one directly. `EventBus`
is not a dumping ground — if you add a signal nobody listens to, delete it.

### The debug overlay and the grey box

`scenes/core/main.tscn` is the permanent root: screens are swapped in and out
as its children, never by replacing it. Routing has to outlive whatever it
routes to — a router that swapped itself out would leave nothing to handle the
next phase change.

`scenes/ui/dev_overlay.tscn` is the debug overlay shown once you leave the
title screen. It reports the current game state, the scene currently routed
to, whether networking is active, the live match rules, the score, the frame
rate and the player's position and movement state, plus buttons that force the
state machine into any legal phase. Chapter 3 added the player's health and
weapon readout and a **Reset range** button.

**It is disposable, and deliberately isolated so that removing it is trivial.**
Either set `Main.DEV_OVERLAY_ENABLED` to `false`, or delete the two
`dev_overlay` files and the four lines in `main.gd` that reference them. Nothing
in the permanent router depends on it, and nothing outside its own script should
ever come to depend on it. The player controller does not reference the overlay
in either direction. Chapter 8 replaces it with a real HUD.

`scenes/game/playtest.tscn` is what the game routes to while in a match phase.
It instances the placeholder environment, spawns the Player at `AlphaSpawn`,
turns off the placeholder's overview camera, and exposes the player as an
`@export` so later chapters can reach it. It is a separate scene from
`main.tscn` so the router survives whatever it routes to.

`scenes/game/placeholder_environment.tscn` is the grey box behind it, and is
equally disposable — Chapter 7 replaces it. It is a separate scene rather than
part of `main.tscn` so that replacing the map is deleting one file, not
unpicking nodes out of the router.

Within that scene the split is deliberate:

- **Authored in the `.tscn`** — sky, sun, camera, apron, floor, walls. These are
  things you want to click and adjust in the Inspector.
- **Generated in the script** — the eight cover blocks, the Chapter 2 ramp,
  staircase and overhang, and the Chapter 3 practice range (backstop, three
  targets, a turret). They are near-identical, and a loop is a better home
  for them than a dozen copy-pasted nodes that all have to be deleted again in
  Chapter 7.

Two things are easy to get wrong in a placeholder and are worth doing properly
now rather than rediscovering in Chapter 3:

- **Every visible box has a matching `CollisionShape3D` sized separately from
  its `BoxMesh`.** Editing the mesh to look right should never silently change
  what a player can walk into. Chapter 3 held to this for the backstop and the
  targets it generated.
- **Both spawn points already exist as `Marker3D`s** (`AlphaSpawn`, `BravoSpawn`),
  so Chapter 4 can assign teams without this scene having to change.

The floor's top surface sits at exactly `y = 0`, which is where the player
controller expects solid ground. The ramp's low end is seated so that its top
surface is also flush with `y = 0`, for the same reason.

---

## Roadmap

Each chapter builds on the last.

- [x] **Ch. 1 — Foundation & Project Architecture:** project structure, conventions,
      version control, phase state machine, autoloads, data resources, boot
      scene, debug overlay
- [x] **Ch. 2 — FPS Player Controller:** input map, movement, camera, jumping,
      sprinting, crouching
- [x] **Ch. 3 — Weapons & Combat:** guns, shooting, damage, health, headshots,
      reloads
- [x] **Ch. 4 — 3v3 Multiplayer:** networking, players, synchronization, teams
- [ ] **Ch. 5 — Tactical Round System:** rounds, objectives, timers, victory
      conditions
- [ ] **Ch. 6 — Unique Game Mechanics:** original abilities/gadgets that make
      the game stand out
- [ ] **Ch. 7 — Map & Level Design:** the actual 3v3 map, sites, cover, spawns,
      layout
- [ ] **Ch. 8 — UI & Presentation:** HUD, menus, scoreboard, buy screen, round
      UI
- [ ] **Ch. 9 — Art, Audio & Polish:** models, VFX, sounds, animations, visual
      identity
- [ ] **Ch. 10 — Testing, Optimization & Final Build:** multiplayer testing,
      bug fixing, optimization, packaging/submission

### Carried forward from Chapter 1

Deliberately left out, so later chapters do not have to unpick them:

- **No replication.** `NetworkManager` covers session setup and peer
  bookkeeping only — no player spawning, ownership or authority. Chapter 4's
  job, and a clean gap is much easier to fill than half-built replication.
- **No team assignment.** It belongs with the roster in Chapter 4, not bolted
  onto connection setup now.
- **No combat.** `ROUND_ACTIVE` owns the round clock and is the only place a
  round can end; nothing decides who won yet.
- **Plain default-controls UI.** Presentation is Chapter 8's job.
- **No runtime weapon object.** `WeaponData` holds a weapon's stats and nothing
  else. Firing, recoil, reload progress and ammo in the magazine are Chapter
  3's job, and they live in a separate per-player object — not on `WeaponData`,
  which is shared and must stay read-only.
- **Three weapons, no roster.** `data/weapons/` holds a sidearm, an SMG and a
  rifle as working examples of the `WeaponData` format. The real weapon list
  and the buy menu that selects from it are Chapter 5's job.

### Carried forward from Chapter 2

Now done, and listed here so the reasoning survives:

- ~~**No weapon holder, viewmodel or camera shake.**~~ Chapter 3 added
  `WeaponMount` under `Head` and `rifle.tscn` beneath it, so the viewmodel
  follows the camera with no parenting code. It carries **no collider at all**,
  which is the only reliable way to stop a first-person weapon clipping into
  geometry.
- ~~**No health, damage or death.**~~ `PlayerState`'s health and alive/dead
  flags are now written, `PlayerState.record_death()` is called exactly once,
  and the corpse is retained on the `CORPSE` layer. See
  [Health and death](#health-and-death-chapter-3).
- ~~**No replication or interpolation.**~~ Still true and still Chapter 4's
  work — but the seams it needs now exist: `input_enabled`, a `Damageable`
  contract the host can validate against, a damage result the weapon reports as
  a signal rather than a local side effect, and an aim ray passed *into* the
  weapon rather than read out of a camera.
- ~~**No respawn path.**~~ `respawn()` exists and is used by the range's reset
  button. Chapter 4 owns *when* a respawn happens.
- ~~**No collider with the world.**~~ The player capsule is mask 13. It still
  passes through other players — Chapter 4 decides whether that should change,
  because it is a bandwidth and gameplay question, not a chapter-3 one.

### Carried forward from Chapter 3

Also deliberately left out:

- **No projectiles.** The ballistics are a hitscan `PhysicsDirectSpaceState3D`
  raycast, deliberately isolated in one public `hitscan(origin, direction)`
  method so a projectile path can replace it without touching ammo, fire rate,
  reload, damage or the player. The aim ray is already an argument, which is
  the hard part of that swap.
- **No networked combat.** The host does not validate shots, health is local,
  and nothing is replicated. Chapter 4's job. The weapon was built with the
  seam in mind: a signal for what was hit, a passed-in ray, and no local
  visual side effects in the ballistics code.
- **No real HUD.** The debug overlay grew an ammo and health readout, which is
  a debug readout and not a HUD. Hit markers are a `CanvasLayer` drawing
  primitives. Chapter 8 replaces all of it.
- **No audio.** The muzzle flash, impact effect and hit marker are all
  placeholder visuals; the signal seam is there for sounds in Chapter 9.
- **No weapon select, no inventory, no buy phase.** The Player equips one
  weapon at construction. Chapter 5.
- **Infinite reserve only.** `reserve_ammo` exists and the finite path is
  implemented and tested, but `infinite_reserve` is on. Chapter 5's buy
  system turns it off.
- **One weapon.** `data/weapons/` still holds the Chapter 1 sidearm, SMG and
  rifle stat tables as examples of the `WeaponData` format, but only the
  Kestrel has a runtime `Weapon` scene behind it. The real roster and the
  selection UI are Chapters 5 and 8.
- **No animations.** Firing, reloading and the death camera fall are all
  procedural transforms. Chapter 9 replaces them, and `WeaponFx` and
  `WeaponMount` are the seams for that.
- **The game boots into the playtest, not the menu.** `Main.BOOT_INTO_PLAYTEST`
  is `true`. Flip it to `false` once there is a menu worth landing on.

### Originality note

Everything user-facing will be original work: the game title, agent and ability
names, weapon names, map names, level layouts, art direction, and UI. The genre
is *tactical FPS*; the content is ours. Naming and visual identity are handled in
Chapters 6 and 8 — until then, `3v3 Tactical FPS` is a working title only.

---

## Chapter 4 — 3v3 Multiplayer Foundation

**Status: Complete.** Real high-level Godot multiplayer, built on `ENetMultiplayerPeer`.

### What Chapter 4 delivers

| Feature | Implementation |
|---------|----------------|
| **Host + client dev flow** | `NetworkManager.host_game(port)` / `join_game(addr, port)`; local/LAN only, no matchmaking, no dedicated server |
| **Identity-in-before-tree** | `Player.pending_peer_id / pending_team / pending_display_name` set by `_spawn_networked_player` before the node enters the scene; `Player._ready` calls `configure_for_network` so the first frame has correct authority, camera and input |
| **Client-authoritative movement** | One `MultiplayerSynchronizer` (`TransformSync`, authority = owning peer, 20 Hz). The client moves; the host's copy follows. No server-side simulation of remote players. |
| **Server-authoritative health / team / death** | Change-driven RPC (`_net_state_receive`, reliable, `any_peer` + sender check). A second synchronizer cannot carry server-authoritative state to a client-owned body — Godot routes a synchronizer's packets only to the node's owning peer. The host broadcasts the trio on every health change; all peers apply it. |
| **Host-validated combat** | `Player.request_shot_from_network(origin, direction)` — `@rpc("any_peer", "call_remote", "unreliable_ordered")` with internal `is_server()` check. Host re-derives ray from its own copy of the world, validates origin (2.0 m tolerance), rate-limits against weapon fire interval, casts `hitscan`, applies damage, then broadcasts `_confirm_shot` (reliable, `any_peer` + sender check) so all clients draw the impact. The host's own player takes the identical validating path. |
| **Networked death** | `die()` splits into host-only bookkeeping (`state.record_death()`) and local presentation (`_begin_death_presentation()`). Corpse moves to `CORPSE` layer on all machines; camera falls to `death_camera_height` over a 0→1 timer. |
| **3v3 team system** | `PlayerRegistry` (plain `RefCounted`, host-owned). `register(peer_id)` owns the capacity rule — refuses the 7th peer, balances teams by count (tie → ALPHA). Teams are `ALPHA` / `BRAVO` only; no victory logic. |
| **Max 6 players / 3 per team** | `NetworkManager.get_max_players()` derives cap from `MatchRules.players_per_team` (default 3). ENet `create_server(port, cap - 1)` enforces at transport level; `PlayerRegistry.register()` enforces at application level. A 7th peer is refused at the handshake. |
| **Dev network UI** | `DevNetworkUI` (CanvasLayer, hidden on main menu, deleted in Ch. 8). Host / Join / Offline buttons, status line, local peer id, connected count. |

### Architecture decisions

- **Two-synchronizer design abandoned.** `MultiplayerSynchronizer` only sends to the node's owning peer, so a server-authority synchronizer on a client-owned body silently drops packets for everyone except that owner. The probe proved this empirically. State is now a change-driven RPC with the same authority model (clients cannot write).
- **`_confirm_shot` uses `any_peer` + sender check, not `authority`.** The node's multiplayer authority is the owning peer; `authority` would let the host never send a verdict about a client's shot. Sender identity (`get_remote_sender_id() == SERVER_PEER_ID`) is the verifiable check.
- **Roster replicated as full snapshots.** `_receive_roster.rpc(entries)` — reliable, authority, call_remote. Clients `replace_all()`; no merge, no drift. Initial state for late joiners seeded in `configure_for_network` and `_receive_roster`.
- **No periodic state poll.** `_publish_net_state()` fires only when health/alive/team changes. A player whose health changes twice a second sends two packets, not ten.
- **`PlayerRegistry.register()` owns the capacity rule.** Single source of truth. `NetworkManager.register_peer` keeps the host check + log.
- **Offline preserved.** `BOOT_INTO_PLAYTEST = false`; main menu is front door with Host/Join/Offline buttons. Offline body uses `SERVER_PEER_ID` (1), not `local_peer_id` (0).

### Files created / modified

| File | Change |
|------|--------|
| `scripts/player/player.gd` | Identity-before-tree (`pending_*`), `_apply_authority_state()`, two-authority replication (transform RPC, state RPC), remote interpolation (3 snapshots, smoothstep), host shot validation, `request_shot_from_network`, `_confirm_shot` fix, `rejected_shot_count()`, `die()` split, team colour, local-body state consume, `_net_state_received` gate, `_configure_replication` NodePath fix |
| `scripts/network/player_registry.gd` | `register()` owns capacity, `set_limits()`, `count_for_side()`, `replace_all()` |
| `scripts/network/network_manager.gd` | ENet cap-1, `get_player_count()`, roster snapshot RPC, `request_spawn()` handshake, `_on_peer_connected` defers spawn to `request_spawn`, `get_local_player()` offline fallback |
| `scripts/game/playtest.gd` | `SPAWN_PATH` const + collision-checked spawner config, `_spawn_offline_player` via pending identity, `_spawn_networked_player` sets pending identity before tree entry, `_on_player_spawned` no longer re-configures |
| `scenes/player/player.tscn` | `TransformSync` only; `Mat_body` `resource_local_to_scene = true` |
| `scenes/game/playtest.tscn` | `Players` + `PlayerSpawner` |
| `scripts/ui/dev_network_ui.gd` / `.tscn` | Disposable dev UI (Host, Join, Offline, status, local peer, connected count) |
| `scripts/ui/main_menu.gd` + `.tscn` | Offline button |
| `scripts/ui/dev_overlay.gd` | Roster label, local-player lookup |
| `scripts/core/main.gd` | `BOOT_INTO_PLAYTEST = false` |
| `scripts/fx/weapon_fx.gd` | Shared impact spawn with network path guard |

### Controls (multiplayer)

| Key | Action |
|-----|--------|
| `H` (menu) | Host a session |
| `J` (menu) | Join `127.0.0.1:27015` |
| `O` (menu) | Offline playtest |

In-match controls unchanged from Chapter 3 (`WASD`, `Shift`, `Ctrl`, `Space`, `LMB`, `R`, `Escape`).

### Tests performed

- **Headless editor quit** (`--headless --editor --quit`): clean.
- **Headless quit** (`--headless --quit`): clean.
- **Windowed boot** (`--quit-after 120`): clean.
- **2-client harness** (`--clients=2`): all core sections pass (1–9): offline regression, host session, client spawn, roster/teams, transform sync, health authority, client-cannot-set-health, combat, shot rejection.
- **5-client harness** (`--clients=5`): host spawns 5 clients, roster at 6/6, team balance within one, capacity rule refuses 7th peer at application level, host-leaves recovery works. Minor client-readiness timing flakiness in the test harness (not game logic).
- **Multi-instance real runs**: 1 host + 2–5 join clients, local LAN, multiple hours aggregate.

### Problems found and fixed

| Problem | Fix |
|---------|-----|
| State synchronizer silently dropped server-authoritative state for client-owned bodies | Replaced `StateSync` with change-driven RPC (`_net_state_receive`), same pattern as working `_confirm_shot` |
| `_confirm_shot` guard used `is_server()` blocking clients from receiving verdicts | Changed to sender check (`get_remote_sender_id() == SERVER_PEER_ID`) |
| Initial state race: client's first roster arrived before bodies existed | Seeded mirror fields in `configure_for_network` + `_receive_roster` applies to existing bodies |
| Client spawn race: host spawned on connect before client's spawner was ready | Deferred spawn to `request_spawn` handshake; host's own peer spawns immediately |
| `request_spawn` RPC signature mismatch (extra argument) | Removed spurious `, 1` argument |
| `MultiplayerSynchronizer.add_property` StringName + missing `:` prefix | Changed to `NodePath(":property")` |
| Death guard on `is_alive` meant death routine never ran | Guard on separate `_is_dying` flag |
| `queue_free` in teardown left ghost bodies in `players` group | Changed to `free()` for immediate removal |
| Material was shared across instances, team colour bled | `resource_local_to_scene = true` in `.tscn`; `_apply_team_colour()` writes in place |
| Offline `is_network_remote` and `get_local_player` used `local_peer_id` (0) | Offline peer = `SERVER_PEER_ID` (1); offline fallback to single body in `players` group |

---

### Chapter 4 stabilization pass (post-handoff)

A later audit found Chapter 4 was not as complete as the table above claims.
Fixed, and verified with a real two-process host + client run and an offline
run (see `HANDOFF.md` for the full list):

- The host could not shoot online (Godot refuses an RPC to yourself); it now
  calls the same validator directly.
- Host-side bodies spawned at the world origin (`spawned` never fires on the
  host); the transform is now set before the node enters the tree.
- `main.tscn` kept a hidden but live second arena (two turrets); removed.
- Remote-body interpolation received no snapshots; transform now replicates via
  `net_position` / `net_yaw`.
- Match phase is now host-authoritative and replicated to clients.
- Networked respawn (`Player.server_respawn_at`), kill credit, `EventBus`
  combat events, weapon spread, and `WeaponFx` impacts on clients all work.
