class_name Player
extends CharacterBody3D
## The first-person player. One scene, instantiated once per player - a local
## player in the playtest now, up to six copies in a 3v3 match later.
##
## [b]Where the seams are, on purpose.[/b]
##
## - [b]All movement is inside this node.[/b] Nothing asks GameManager to move
##   anyone, and there is no "the player" singleton. Every other player in the
##   match will be another instance of this same scene.
## - [b]Input is optional, not assumed.[/b] [member input_enabled] is the single
##   switch between "this player listens to the keyboard" and "this player's
##   transform is set by the network". A remote player is the same scene with
##   input off, so Chapter 4 adds replication without a second controller.
## - [b]Identity is data, not node state.[/b] [member state] is a Chapter 1
##   [PlayerState], so health and team already have somewhere to live without
##   this script growing fields for them.
##
## [b]Node layout and why:[/b]
## [codeblock]
## Player (CharacterBody3D)   - yaw only, never pitched
##  |- Collision              - capsule, resized for crouch
##  |- Head (Node3D)          - pitch pivot, sits at eye height
##      |- Camera3D           - the only thing that should ever be "current"
## [/codeblock]
## Yaw lives on the body and pitch on the head so that movement is always
## computed from a level heading. If the body were pitched, walking downhill
## would steer you into the ground.

# --- Signals ------------------------------------------------------------

## Health changed, or the player died. [param alive] is false on the frame
## health reaches zero. The HUD reads this; Chapter 5's scoreboard will too.
signal health_changed(health: int, alive: bool)

## A shot this player fired has been resolved by whoever is authoritative for
## it. [param victim] is the [Player] that was hit, or null for scenery, and
## [param at] / [param normal] describe where the round stopped. [param is_local]
## is false when this arrived over the network, which is how the shooter - and
## its weapon feedback - tell its own confirmed hit apart from a verdict about
## somebody else's.
signal shot_resolved(at: Vector3, normal: Vector3, victim: Player, zone: int, killed: bool, is_local: bool, surface: int)

## This machine's own player fired: the ray it fired along, spread included.
## For presentation (the tracer) - it is emitted before anything is resolved.
signal shot_fired(origin: Vector3, direction: Vector3)

## A shot landed on this player. Fired on every machine, including the victim's
## own, so a HUD hit indicator is one connection rather than a special case for
## "am I the one who got shot".
signal took_hit(from: Node, amount: float, zone: int)

## The player was eliminated. [param source] is whatever did it, which may be
## null - falling out of the world should still produce a death.
signal died(source: Node)

## Emitted when a weapon is equipped or removed. The HUD re-reads ammo on this
## rather than polling.
signal weapon_changed(weapon: Weapon)

## A reload started or finished. [param duration] is the full reload time when
## one started and zero when one finished. Separate from the weapon's own signal
## so the HUD does not have to hold a reference to the weapon to know.
signal reloading_changed(reloading: bool, duration: float)

## The trigger was pulled on an empty magazine.
signal dry_fired

# --- Body dimensions ---------------------------------------------------
# Metres. The capsule's origin is at the player's feet, so a shape of height h
# sits with its centre at y = h / 2.

## Collision height while standing. Also the default value for the scene.
@export var stand_height: float = 1.8

## Collision height while crouched. Must stay above 2x [member body_radius] or
## Godot will not accept it as a capsule.
@export var crouch_height: float = 1.1

@export var body_radius: float = 0.35

# --- Speeds ------------------------------------------------------------
# Deliberately not copied from any existing game. These are tuned to feel
# deliberate rather than floaty: enough acceleration to stop instantly on a
# dime, not so much that the player skates.

@export_group("Speeds")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.6

@export_group("Acceleration")
## How fast horizontal speed is gained on the ground, in m/s^2.
@export var ground_acceleration: float = 55.0

## How fast horizontal speed is lost on the ground with no input. Higher than
## [member ground_acceleration] so releasing a key stops the player crisply
## instead of sliding.
@export var ground_deceleration: float = 70.0

## Air control, as a fraction of [member ground_acceleration]. Low on purpose:
## a tactical shooter should reward committing to a jump rather than let the
## player steer freely in mid-air.
@export_range(0.0, 1.0) var air_control: float = 0.22

## Horizontal speed lost per second while airborne with no input. Also low, so
## a jump keeps its momentum.
@export var air_deceleration: float = 2.0

@export_group("Vertical")
## Downward acceleration. Higher than Earth's 9.8 so jumps feel snappy and
## falls resolve quickly.
@export var gravity: float = 18.0

## Upward speed applied by a jump. With the default gravity this clears about
## 0.84 m, which is enough to get onto a waist-high crate and not much else.
@export var jump_velocity: float = 5.5

## Downward speed cap, so a long fall does not turn into tunnelling.
@export var terminal_fall_speed: float = 40.0

## Grace period after walking off a ledge during which a jump still works.
## Without it, walking down a slope can drop the floor for a frame and eat the
## jump. Set to 0 to disable.
@export var coyote_time: float = 0.12

## How far the body may snap downwards to stay in contact with a slope is
## [member CharacterBody3D.floor_snap_length], set on the node in
## [code]player.tscn[/code]. It is deliberately not declared here: a script
## variable of that name shadows the engine's own property, so the number
## would appear in the Inspector looking configurable while the real value
## stayed at the engine default and the controller quietly failed to follow
## slopes down.

## Tallest ledge the player walks up without jumping, in metres. Uses a real
## overlap test rather than a raycast, so it cannot lift the player into a
## ceiling.
@export var step_height: float = 0.4

## Clearance required around the lifted position before a step is taken.
## Without it the lifted capsule can pass a ledge corner by a millimetre and
## then snag on it, which reads as the player stuttering against the stair.
const STEP_CLEARANCE := 0.02

# --- Camera ------------------------------------------------------------

@export_group("Camera")
## Multiplier turning the 0..1 setting in GameConfig into radians per pixel of
## mouse movement. A raw sensitivity number is meaningless without it, so the
## two are kept apart: the player owns this, the player-facing option does not.
@export var sensitivity_scale: float = 0.003

## How far up or down the head can look, in degrees. Just under 90 so the view
## can reach straight up and down without ever passing through the poles and
## flipping, which is the classic way an FPS camera breaks.
@export var pitch_limit_degrees: float = 89.0

## Eye height above the feet while standing, and while crouched. The camera
## interpolates between them rather than snapping, so crouching does not jolt.
@export var stand_eye_height: float = 1.62
@export var crouch_eye_height: float = 0.95

## How quickly the body and camera move between the two stances, in units per
## second. Shared by the collision shape and the camera so they can never
## disagree about how far through the transition the player is.
@export var stance_change_speed: float = 9.0

## Whether this player reads the keyboard. See the class docs: this is the
## switch Chapter 4 flips for remote players.
@export var input_enabled: bool = true

## Whether gameplay starts with the mouse captured.
@export var capture_mouse_on_ready: bool = true

## Coarse states the controller can be in. Enough for the HUD, the debug
## overlay and later combat logic to reason about, without a state machine
## that Chapter 3 would have to unpick.
enum MovementState {
	NORMAL,
	SPRINTING,
	CROUCHING,
	AIRBORNE,
	DEAD,
}

## Identity, health and team. Owned by this node rather than being global,
## because there is one per player. Chapter 3 reads health from here.
var state: PlayerState = PlayerState.new()

# --- Network identity (Chapter 4) ----------------------------------------

## Which peer drives this body. Defaults to [constant NetworkManager.SERVER_PEER_ID]
## so a player instantiated in the editor, or in a Chapter 3 harness, is
## immediately valid as a single-player body and does not have to be told it is
## the only one in the world.
@export var peer_id: int = NetworkManager.SERVER_PEER_ID

## Set by [method configure_for_network] when this body belongs to a different
## peer. A remote body does not run physics, does not read input, and has no
## camera - it is a transform receiver with a health readout.
var is_network_remote: bool = false

## Host-side bookkeeping for shot validation. See [method _resolve_incoming_shot].
var _last_validated_shot_ms: int = -100000

## Host-side count of rejected shots, exposed for the dev overlay so a
## misbehaving client is visible rather than mysterious.
var _rejected_shots: int = 0


## How many shots this body's authority has refused, and why the most recent
## one was refused.
##
## Public because a silently dropped shot is the hardest kind of networking bug
## to diagnose: from the shooter's side the trigger worked, the flash played,
## and nothing happened. A counter the dev overlay can display turns "something
## is wrong with combat" into "peer 4 has had nine rejected shots", which points
## straight at the cause.
func rejected_shot_count() -> int:
	return _rejected_shots

# --- Replicated state ----------------------------------------------------

## Health as the network sees it.
##
## [b]This is a mirror of [member PlayerState.health], not a replacement for
## it.[/b] The value lives on this node so it can cross the wire, and the job
## of putting it back into [member state] on a receiving machine belongs to the
## host's state RPC ([method _net_state_receive] and its helper [method
## _sync_state_from_network]). Keeping both is deliberate rather than
## duplicated: `state` is the game object's truth and is what the HUD, the
## scoreboard and the Chapter 5 round loop read, while these three exist only
## to cross the wire.
var net_health: int = PlayerState.MAX_HEALTH
var net_alive: bool = true
var net_team: int = Team.Side.NONE

## Whether the host has ever sent this body's state.
##
## The three fields above all have defaults, and two of them -
## [constant PlayerState.MAX_HEALTH] and [code]true[/code] - are exactly what
## the host would send for an untouched player. So their defaults cannot be
## read as an answer. [member net_team] can: [constant Team.Side.NONE] is a
## value the host never sends, because every player is given a side before it is
## spawned. This flag turns that into an explicit "the host has spoken" rather
## than leaving it implicit in a magic constant - see
## [method _sync_state_from_network] for what goes wrong without it.
var _net_state_received: bool = false

## Set when the host changes any of the mirrored fields, so a client can tell a
## replicated change from its own local damage. Without this, a client that took
## damage optimistically would fight the host's copy on every arrival.
var _is_net_state_authoritative: bool = true

# --- Interpolation (remote bodies only) -----------------------------------

## Where a remote body was last told to be, and where it is allowed to be
## drawn while it catches up.
##
## The obvious implementation - let the synchroniser write
## [member Node3D.global_position] and draw it - produces visible 20 Hz
## stepping, because a body jumps a third of a metre every 50 ms and then sits
## still. Snapping the draw position toward the replicated one at a bounded rate
## trades a few milliseconds of latency for motion that reads as continuous,
## which is the whole reason to bother.
var _render_position: Vector3 = Vector3.ZERO
var _render_rotation_y: float = 0.0
var _render_initialised: bool = false

## Metres per second a remote body is allowed to close the gap to its
## authoritative position. Generous enough to catch up from a teleport within a
## couple of frames, tight enough that a desync does not visibly slide across
## the map.
const REMOTE_CATCHUP_SPEED := 28.0

## How many seconds of position history to interpolate through. Two snapshots
## is the minimum that lets a body move *between* updates rather than towards
## them.
const REMOTE_SNAPSHOT_HISTORY := 3

## A snapshot further than this from the previous one is a teleport (a respawn,
## a spawn nudge), not movement. It is snapped to rather than interpolated, or a
## respawned player would visibly glide across the whole map.
const TELEPORT_SNAP_DISTANCE := 4.0

## The replicated transform. The owning machine writes these every physics
## frame; on every other machine the synchroniser writes them and the setters
## turn each arrival into an interpolation snapshot.
var net_position: Vector3 = Vector3.ZERO:
	set(value):
		net_position = value
		if is_network_remote:
			record_net_snapshot(value)

var net_yaw: float = 0.0

## The owner's view pitch in radians (recoil included), replicated for
## spectators. See [SpectatorCamera].
var net_pitch: float = 0.0

## The owner's stance, 0 crouched .. 1 standing, replicated so every machine
## sizes this body's hitbox and eye height the same way.
var net_stance: float = 1.0

## Recent authoritative positions with the times they arrived.
var _snapshot_times: PackedFloat32Array = PackedFloat32Array()
var _snapshot_positions: PackedVector3Array = PackedVector3Array()

## Seconds between transform snapshots.
##
## Named for the unit it is in, because [member
## MultiplayerSynchronizer.replication_interval] is a duration and not a rate,
## and a constant called `..._HZ` holding `0.05` invites the reader to divide it
## - producing a twenty-second interval and a replication system that appears to
## work on a body standing still.
const TRANSFORM_REPLICATION_SECONDS := 0.05

## How far a client's claimed eye position may be from where the host believes
## that player is, in metres, before the shot is refused.
##
## Sized for the worst honest case rather than the average one. The host's copy
## of a remote body is a snapshot behind, and a player at a sprint covers
## several metres in 50 ms, so a tight bound would reject legitimate shots
## during exactly the movement a player is most likely to be shooting during.
## Two metres is comfortably more than interpolation lag and comfortably less
## than "somewhere else entirely".
const MAX_SHOT_ORIGIN_ERROR := 2.0

## Slack allowed on the host's fire-rate check, in milliseconds. The client
## enforces the real interval against its own clock and the host enforces the
## same interval against a different one, so without a little tolerance a
## legitimate shot gets refused roughly whenever the two clocks disagree.
const SHOT_CLOCK_TOLERANCE_MS := 15

## How many shots may arrive back to back before the fire-rate check bites.
const SHOT_BURST_ALLOWANCE := 2.0
var _shot_budget: float = SHOT_BURST_ALLOWANCE

# --- Combat (Chapter 3) -------------------------------------------------

## The equipped weapon, or null when this player has nothing in their hands.
## The player owns the weapon in the sense that it is a child of this node and
## travels with it; it owns none of the weapon's behaviour. See [Weapon].
@onready var weapon: Weapon = $Head/WeaponMount/Weapon

## The headshot band, as a fraction of the player's current height measured up
## from the feet. The top fifth of the capsule is a headshot.
##
## [b]A height band rather than a second collider, on purpose.[/b] A separate
## head collider would have to be moved every time the crouch height changed,
## and any frame where the two disagreed would leave the player with a hole in
## the head or a head that was floating. Deriving the band from
## [method get_current_height] - the same number the capsule is resized from -
## means it cannot fall out of step with the crouch, and it costs no extra
## collision shape, which keeps the Chapter 2 step-up and crouch-under-a-ceiling
## behaviour exactly as it was.
@export_range(0.05, 0.5, 0.01) var head_hit_fraction: float = 0.18

## How fast the camera returns to where the player was actually aiming after
## recoil, in degrees per second. The weapon decides [b]how much[/b] kick a shot
## has; this decides [b]how fast[/b] it goes away, because that is a property of
## the player's own view rather than of any one weapon.
@export var recoil_recovery_degrees: float = 55.0

## The furthest the camera can be pushed off the player's true aim by recoil
## alone, in degrees. A cap rather than an unbounded accumulator, so a long burst
## cannot walk the view somewhere the player cannot pull it back from.
@export var max_recoil_pitch_degrees: float = 6.0
@export var max_recoil_yaw_degrees: float = 3.0

## How long the camera takes to fall to the floor after death, in seconds.
@export var death_camera_fall_seconds: float = 1.1

## How far above the floor the camera comes to rest, in metres.
@export var death_camera_height: float = 0.35

## The player's true aim pitch, in radians, as the mouse last left it.
##
## [b]Separated from the head's rotation on purpose.[/b] Recoil is an [b]offset
## applied on top of[/b] this value, never an addition to it, which is what keeps
## the player's own aim from being destroyed: recovery always returns the view to
## exactly the pitch the player chose, so a twenty-round burst leaves the
## crosshair on the pixel it started on. Folding recoil into the head's rotation
## instead would make the view drift permanently upward and the player would have
## to fight it back down - the "recoil you cannot control" the chapter rules out.
var _look_pitch: float = 0.0

## Current recoil offset, in degrees, applied on top of [member _look_pitch].
var _recoil_pitch: float = 0.0
var _recoil_yaw: float = 0.0

## How far through the death camera fall the player is, 0 to 1.
var _death_tilt: float = 0.0

## Where the head was at the moment of death, so the fall starts from wherever
## the player actually was - standing, or already part way down from a crouch -
## rather than from an assumed standing height.
var _death_eye_start: float = 0.0

## Set by [method die] so [method _update_stance] stops fighting it and the
## camera cannot spring back up.
var _is_dying: bool = false

## Where the weapon mount sits when it is not recoiling, captured from the
## scene. Recoil is an offset from here rather than an accumulated addition, so
## twenty rounds of automatic fire cannot walk the gun slowly into the player's
## face.
var _viewmodel_rest: Vector3 = Vector3.ZERO
var _viewmodel_kick: float = 0.0

## How fast the viewmodel returns to rest after a shot, in kicks per second. A
## constant rather than a per-weapon number because it is a property of the
## player's hands, not of any particular gun.
const VIEWMODEL_KICK_RECOVERY := 12.0

@onready var _collision: CollisionShape3D = $Collision
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _weapon_mount: Node3D = $Head/WeaponMount
@onready var _hit_marker: HitMarker = $HitMarkerLayer/HitMarker
## Plain var rather than @onready: it is needed in [method _enter_tree], which
## runs before @onready initialisers.
var _transform_sync: MultiplayerSynchronizer = null
@onready var _echo_field: EchoField = $EchoField

## Optional translucent capsule used only to make the collider visible while
## developing, and permanently visible for a body this machine is not driving.
## Hidden by default, and parented to the collision shape so it can never drift
## away from the thing it is showing.
@onready var _body_mesh: MeshInstance3D = $Collision/BodyMesh

## 0.0 = fully crouched, 1.0 = fully standing. The single source of truth for
## "how crouched am I", read by the camera, the collider and the state getter.
var _stance: float = 1.0

## Seconds left of the coyote window.
var _coyote_left: float = 0.0

var _sprint_held: bool = false
var _crouch_held: bool = false

## Horizontal speed the player is *trying* to travel at, kept separately from
## [member CharacterBody3D.velocity] and never written by the physics engine.
##
## This split is not cosmetic. [method CharacterBody3D.move_and_slide] overwrites
## [code]velocity[/code] with the velocity the body actually ended up with, which
## is zero along any axis it collided on. Seeding acceleration from that means a
## player pressed against a step or a wall starts every frame from standstill,
## so they can never build enough speed to climb back out - and, worse, the
## step-up test gets handed a near-zero distance and decides nothing is in the
## way. Keeping the player's intent here means the two stay independent: intent
## is what the player asked for, velocity is what the world permitted.
var _move_velocity: Vector3 = Vector3.ZERO

## Set when a jump is refused because the player is not grounded, so the
## refusal can be reported rather than silently ignored.
var _last_jump_was_refused: bool = false

## Identity handed in by the match scene's spawn function [b]before[/b] this node
## entered the tree.
##
## Exists because [MultiplayerSpawner] adds the node first and only then raises
## [signal MultiplayerSpawner.spawned], so by the time the match scene gets to
## tell a body who it belongs to, [method _ready] has already run - and already
## captured the mouse, made its camera current and handed it a local identity.
## On the host, that window is long enough for somebody else's player to steal
## the pointer, and the damage is done before any configuration code runs.
##
## The spawn function can write these because it holds the instance before
## anything parents it, so [method _ready] has an answer instead of a guess. The
## alternative - deciding after the fact - has no way to un-capture a mouse.
var pending_peer_id: int = 0
var pending_team: int = Team.Side.NONE
var pending_display_name: String = ""


## Authority and the replication config are set here, before [method _ready].
##
## Godot requires a [MultiplayerSynchronizer]'s authority to be final by the
## time the spawner's `_enter_tree` pass is over; changing it in `_ready` leaves
## the synchroniser without a network id on the receiving peer ("unable to
## process the pending spawn since it has no network ID") and its first packets
## are dropped. The spawn function writes [member pending_peer_id] before the
## node enters the tree, so the answer is already known here.
func _enter_tree() -> void:
	if _transform_sync == null:
		_transform_sync = $TransformSync
	_configure_replication()
	if pending_peer_id > 0:
		set_multiplayer_authority(pending_peer_id)


func _ready() -> void:
	add_to_group(&"players")

	_apply_stance()

	# Replication was configured in [method _enter_tree], before anything could
	# fire a synchroniser at us: a MultiplayerSynchronizer with a null config is
	# inert, and one whose config changes after its spawn has started loses it.

	# Mouse look belongs to whichever camera this player owns, so a second
	# player in the match does not fight the first one for the pointer.
	_camera.fov = GameConfig.field_of_view
	GameConfig.setting_changed.connect(_on_setting_changed)

	if _weapon_mount != null:
		_viewmodel_rest = _weapon_mount.position

	_equip_weapon()

	# The head's rotation is derived, so it is written once here rather than
	# waiting for the first physics frame with a stale zero.
	_apply_view()

	# A spawned body already knows who it is. Applying that now, inside _ready,
	# is the only point at which "is this mine or somebody else's" can be
	# answered before the node starts doing local-player things like capturing
	# the mouse or claiming the camera.
	if pending_peer_id > 0:
		configure_for_network(pending_peer_id, pending_team, pending_display_name)
		return

	_apply_authority_state()


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "video/field_of_view":
		_camera.fov = float(value)


## Turns the identity fields into everything that follows from them: which
## camera is live, whether the body mesh is visible, whether this machine reads
## input, and whether the mouse is ours.
##
## Deliberately [b]idempotent and callable from both [method _ready] and
## [method configure_for_network]. It is called twice for a spawned body, once
## per entry point, and has to produce the same answer both times - otherwise the
## second call silently undoes the first, which is the kind of bug that only
## shows up as a camera that flickers between owners on join.
func _apply_authority_state() -> void:
	# The camera is not `current` in the scene file, on purpose. A camera that
	# enters the tree as current steals the view from whoever had it, and
	# switching it off again with `current = false` makes Godot hand the view to
	# the "next" camera it finds - in the grey box, the elevated overview
	# camera. That is exactly what happened to the host every time a client
	# joined: the view jumped above the map and stayed there. So only the body
	# this machine drives ever claims the view, and a remote one releases it
	# without passing it on.
	if is_network_remote:
		if _camera.current:
			_camera.clear_current(false)
	else:
		_camera.make_current()

	# A remote body carries a viewmodel and a hit marker that nobody can see.
	# Hiding them is not just tidiness: six visible Kestrels floating in front
	# of five other players is the single most obvious sign that replication
	# is only half working.
	if is_network_remote:
		_apply_remote_appearance()
		return

	if _body_mesh != null:
		_body_mesh.visible = false

	if capture_mouse_on_ready and input_enabled:
		capture_mouse(true)


## Sets this body's identity and decides who is authoritative for what.
##
## Called by the match scene on every machine, with the same arguments, as part
## of spawning. It is not called only on the authority: a client that skipped
## it would have a body with the wrong authority and would try to replicate a
## transform nobody is listening for.
func configure_for_network(p_peer_id: int, team_side: int, player_name: String = "") -> void:
	peer_id = p_peer_id
	state.setup(p_peer_id, player_name, team_side)

	# [b]Offline, nothing on this machine is anybody's remote body.[/b] There is
	# no multiplayer peer, so `get_unique_id()` is answering a question that
	# does not apply - and answering it "wrongly" would hand the single local
	# player a remote body, a dead camera and no input, which is a game that
	# renders a room nobody can move in.
	# Use NetworkManager.local_peer_id instead of multiplayer.get_unique_id()
	# because this may be called before the node is in the scene tree.
	is_network_remote = NetworkManager.is_online \
		and p_peer_id != NetworkManager.local_peer_id

	# The node's own authority follows the owning peer, which is what makes
	# `is_multiplayer_authority()` - used all over the RPC layer - answer the
	# right question.
	set_multiplayer_authority(p_peer_id)

	# Movement authority is the owning peer; health, team and death are always
	# the server's. Those two facts are not encoded the same way, because the
	# two mechanisms they use have different rules about who may speak:
	#
	# The transform is a [MultiplayerSynchronizer], and synchronisers replicate
	# cleanly from a client-owned node to the server - the client moves, the
	# server's copy follows. Reversing the direction does not. A synchroniser
	# whose authority is the server carries a client-owned body's state
	# nowhere: Godot only routes a synchroniser's packets for a node to the
	# peer that owns that node, so the owner receives the server's copy but
	# everyone else, including the body's own driver, never sees it. The probe
	# scene proved that point empirically (see Chapter 4's notes in the
	# README): the host's own body's health arrived on clients, a client's own
	# body's health never did.
	#
	# So state crosses the wire as a change-driven RPC instead - the host
	# broadcasts the trio in [method _publish_net_state], and receiving peers
	# apply it via [method _net_state_receive]. That keeps the exact same
	# authority (clients cannot write, only the host may), and it is lighter
	# than a periodic poll ever was, because a player whose health changes
	# twice a second sends two packets, not ten.
	_transform_sync.set_multiplayer_authority(p_peer_id)

	# Input is the local machine's business only. A remote body keeps
	# `input_enabled` true on the machine that owns it and false everywhere
	# else, which is exactly the distinction Chapter 2's seam was built for.
	input_enabled = not is_network_remote
	_apply_authority_state()

	# The mirror fields start at their defaults, and the defaults are not what
	# the host wants to send - most visibly `net_team`, which starts as NONE.
	# The state RPC sends whatever the host has in these fields, not whatever
	# the host has in [member state], so if it is not primed here the host's
	# first broadcast would tell every client that every player is on no side
	# at all. Priming costs one line and removes a visible wrong-then-right
	# flicker on every join.
	# Mirrors only - no broadcast. On the host this runs while the spawn
	# message for this body is still on its way, so an RPC now would reach
	# clients before the node exists there ("Node not found"). Clients seed
	# the same values from the roster just below, which is already up to date.
	_publish_net_state(false)

	# On a client, `_publish_net_state` is a no-op (host-only). If the roster
	# has already arrived (late join), the registry holds the authoritative
	# values for this peer; otherwise fall back to the local state that was
	# just set up. This ensures the first frame shows the host's truth.
	if NetworkManager.is_online and not multiplayer.is_server():
		var entry := NetworkManager.players.get_entry(peer_id)
		if not entry.is_empty():
			net_health = int(entry.get("health", PlayerState.MAX_HEALTH))
			net_alive = bool(entry.get("is_alive", true))
			net_team = int(entry.get("team", team_side))
		else:
			net_health = state.health
			net_alive = state.is_alive
			net_team = state.team
		_net_state_received = true


## Builds the transform replication config in code.
##
## In code rather than as a `.tscn` sub-resource so that the authority and the
## property list sit next to each other in one readable block. A hand-authored
## `SceneReplicationConfig` in a scene file is an opaque id reference, and the
## one thing that must be right here - that the list contains exactly the two
## transform properties and nothing that smells like authority - is exactly
## the thing that is invisible in that format.
##
## Health, team and death are deliberately [b]not[/b] replicated here. State
## crosses the wire as a change-driven RPC; see the notes beside
## [method configure_for_network] for why a synchroniser cannot carry a
## client-owned body's server-owned state to the client that drives it.
func _configure_replication() -> void:
	# Two facts about [method SceneReplicationConfig.add_property] that cost an
	# afternoon between them, both worth writing down because neither produces
	# a useful diagnostic:
	#
	# It takes a [NodePath], not a [StringName]. A StringName compiles, runs,
	# and fails inside C++ with "p_path == NodePath() is true" - a native error
	# with no script line attached and no GDScript warning to catch it first.
	#
	# The path needs a leading colon. Without one, the synchronizer walks it as
	# a chain of *node* names, so `global_position` becomes "find a child called
	# global_position" and the answer is "Node 'global_position' not found" -
	# once per property, per sync interval, forever, drowning the log. The colon
	# is Godot's own convention for "the last component is a property name", and
	# with it present the first component is empty, which means the root node
	# itself rather than a child of it.
	var transform_config := SceneReplicationConfig.new()
	# Only two properties. Position and yaw are the whole of what a remote peer
	# needs to draw a body; pitch stays local because it is a property of the
	# head, not the body, and because a remote player's head angle is not worth
	# bandwidth until Chapter 6 gives remote players something to animate.
	#
	# Replicated through [member net_position] / [member net_yaw] rather than
	# straight into `global_position`. Writing the transform directly meant the
	# synchroniser teleported remote bodies every 50 ms and the snapshot
	# interpolation below never received a single snapshot - it was dead code
	# and remote players visibly stepped at 20 Hz. The setters on these two
	# properties feed [method record_net_snapshot] instead. Both are world-space,
	# so they mean the same thing on every machine regardless of parenting.
	# [member net_pitch] rides along for spectators: a teammate watching
	# through your eyes needs to see where you are looking, not just facing.
	# [member net_stance] carries crouching: without it the host would cast a
	# crouched client's shots from standing eye height and keep a standing
	# hitbox for them.
	for property in [":net_position", ":net_yaw", ":net_pitch", ":net_stance"]:
		transform_config.add_property(NodePath(property))
	_transform_sync.replication_config = transform_config

	# 20 Hz for movement, well under the 60 Hz physics tick. The cost of this
	# choice is visible immediately if it is wrong: at full tick rate six
	# players send sixty position updates a second each for a transform that
	# changes smoothly, and the smoothing below hides the difference between
	# 20 Hz and 60 Hz completely.
	_transform_sync.replication_interval = TRANSFORM_REPLICATION_SECONDS


## Hides everything on this body that only makes sense from inside it, and
## shows everything that only makes sense from outside it.
##
## The pair is deliberate. A remote body must lose the camera, the viewmodel and
## the hit marker - none of them can be seen and all three cost something to
## process - and must gain the body mesh, which is hidden on a local player
## because you are standing inside it. Getting only one half right produces
## either invisible teammates or a gun floating in front of your face.
func _apply_remote_appearance() -> void:
	# Released without handing the view to another camera; see
	# [method _apply_authority_state].
	if _camera.current:
		_camera.clear_current(false)
	_set_weapon_visible(false)
	if _hit_marker != null:
		_hit_marker.visible = false
	if _body_mesh != null:
		_body_mesh.visible = true
	_apply_team_colour()

	# Nothing else needs to be done to stop a remote body being simulated: the
	# physics is skipped entirely in [method _physics_process], so nothing ever
	# calls [method CharacterBody3D.move_and_slide] on it and there is no
	# velocity for the server to integrate. It stays a solid collider on the
	# player layer, which is what it should be - a teammate you can stand
	# behind and a target you can be shot at.


## Tints the body mesh for whichever side this player is on.
##
## Not decoration. In a 3v3 the single most important thing a player needs from
## another player is "are they on my side", and an untinted grey capsule makes
## that a question the player has to answer by remembering a name. A colour per
## side is the cheapest possible answer and it is the reason the registry
## assigns a side at all.
func _apply_team_colour() -> void:
	if _body_mesh == null:
		return
	var colour: Color = TEAM_COLOURS.get(state.team, TEAM_COLOURS[Team.Side.NONE])
	var material := _body_mesh.get_active_material(0)
	if material is StandardMaterial3D:
		# Written in place, with no [method Resource.duplicate] first. The
		# material carries `resource_local_to_scene` in the scene file, so Godot
		# already gave every instance of this scene its own copy - duplicating
		# again would work and would hide the fact, which is the worse outcome:
		# remove the flag one day and six players silently repaint each other
		# again, with no error to point at.
		(material as StandardMaterial3D).albedo_color = colour


## One colour per side. Alpha is well below 1.0 so you can see somebody through
## a body you are standing in - in a shooter, being able to see the fight
## matters more than the body being solid-looking.
const TEAM_COLOURS := {
	Team.Side.NONE: Color(0.7, 0.7, 0.7, 0.18),
	Team.Side.ALPHA: Color(0.25, 0.65, 1.0, 0.22),
	Team.Side.BRAVO: Color(1.0, 0.35, 0.25, 0.22),
}


## Puts the starting weapon in this player's hands and wires up everything the
## weapon reports.
##
## [b]The signal wiring is here, in the player, not inside the weapon.[/b] The
## weapon never calls the player directly - it emits, and this node decides what
## that means. That is what lets a remote player in Chapter 4 hold the same
## weapon scene with a different set of listeners, or none.
func _equip_weapon() -> void:
	if weapon == null:
		return

	# The shared [WeaponData] instance is handed to the weapon by reference and
	# never written to, so six players in a match all firing the Kestrel cannot
	# change each other's spread. Which one is decided by the loadout.
	loadout.refill()

	weapon.fired.connect(_on_weapon_fired)
	weapon.recoil_requested.connect(_on_recoil_requested)
	weapon.hit_confirmed.connect(_on_hit_confirmed)
	weapon.reload_started.connect(_on_reload_started)
	weapon.reload_finished.connect(_on_reload_finished)
	weapon.dry_fired.connect(_on_dry_fired)

	weapon_changed.emit(weapon)

	# A player who dies mid-reload must not come back with a magazine that
	# silently refilled.
	if not state.is_alive:
		_set_weapon_visible(false)


## Hides or shows the weapon in the player's hands. On death the gun drops out
## of frame rather than vanishing instantly, because a player who can still see
## a magazine counting down while they are dead is being told a lie.
func _set_weapon_visible(visible_now: bool) -> void:
	if _weapon_mount == null:
		return
	_weapon_mount.visible = visible_now
	# The recoil offset is reset with it, or the next equip comes back with the
	# gun jammed half way back.
	_viewmodel_kick = 0.0
	_weapon_mount.position = _viewmodel_rest
	_weapon_mount.rotation = Vector3.ZERO


## Places the viewmodel: its rest position, moved towards the centre by aiming,
## plus the recovering recoil kick. Purely cosmetic, and driven from here rather
## than from the weapon because the mount is a node on the player.
func _update_viewmodel_kick(delta: float) -> void:
	if _weapon_mount == null or not _weapon_mount.visible:
		return

	_viewmodel_kick = maxf(_viewmodel_kick - delta * VIEWMODEL_KICK_RECOVERY, 0.0)
	var distance := 0.0
	if weapon != null and weapon.data != null:
		distance = weapon.data.viewmodel_kick
	# Positive z is back towards the camera, which is what "kicking" means.
	# Aimed, the kick is smaller - the steadier hold is part of what aiming buys.
	var kick := _viewmodel_kick * distance * aim.recoil_scale()
	_weapon_mount.position = _viewmodel_rest + aim.viewmodel_offset() + Vector3(0.0, 0.0, kick) 		+ view_feel.weapon_offset()
	_weapon_mount.rotation = view_feel.weapon_rotation()


## Applies the aim to everything outside the weapon's own numbers: the camera's
## zoom and the weapon's fire interval. Movement, spread, recoil and mouse
## sensitivity read [member aim] where they are computed.
func _apply_aim() -> void:
	_camera.fov = GameConfig.field_of_view * view_feel.fov_scale() / aim.zoom()
	if weapon != null:
		weapon.fire_interval_scale = aim.fire_interval_scale()


## How far into aiming down sights this player is, 0 to 1. For the HUD.
func get_aim_amount() -> float:
	return aim.amount


# --- Weapon signal handlers ---------------------------------------------
# All of these are one-liners. That is the payoff of the weapon emitting
# instead of calling: the player decides what a shot means for a player, and
# nothing in the weapon knows this class exists.

func _on_weapon_fired() -> void:
	# The aim ray starts at the camera, not the muzzle, so the crosshair tells
	# the truth about where the round goes.
	var origin := get_eye_position()
	# The weapon's spread cone is applied here, on the shooting machine, so the
	# host validates and casts exactly the ray the shooter's crosshair produced.
	# Before this call existed `spread_degrees` was authored on every weapon and
	# read by nothing, so every gun was perfectly accurate.
	var direction := weapon.apply_spread(get_look_direction(), aim.spread_scale())
	shot_fired.emit(origin, direction)

	# Offline, this player is the whole authority and the raycast runs right
	# here. Online, the host is the authority for what a shot hit, so the ray
	# is offered to it instead and the answer comes back. The local weapon has
	# already debited the round and flashed the muzzle by this point, so the
	# player still gets instant feedback for their own action; what they do not
	# get is the right to decide it hit something.
	if NetworkManager.is_online:
		request_shot_from_network(origin, direction)
		return

	weapon.hitscan(origin, direction)
	_report_shooting_to_echo_fields()


## Asks the host to resolve this shot. [b]The client-to-host combat
## interface.[/b]
##
## Public, and named, because it is the seam rather than a private detail: it is
## what a trigger press calls, and it is what a replay viewer, a turret, or a
## Chapter 6 ability that fires on somebody's behalf would call. Every one of
## those wants the same thing - describe an aim, let the authority decide - and
## none of them wants a local shortcut.
##
## The call is [b]not[/b] an RPC annotation on the call site: the host's own
## player takes the identical path, with the identical validation, as a client's
## does. Having a separate "trusted" local shortcut would mean the host is
## playing by different rules from everyone else, and the only way to find out
## that the validating rules were wrong would be to notice the host behaving
## differently.
func request_shot_from_network(origin: Vector3, direction: Vector3) -> void:
	# The host cannot RPC itself - Godot refuses a `call_remote` RPC addressed
	# to the local peer ("RPC on yourself is not allowed"), which is what left
	# the host unable to hit anything online. It calls the same validating
	# function directly instead, naming itself as the sender, so it still
	# plays by exactly the rules a client does.
	if multiplayer.is_server():
		_resolve_shot(multiplayer.get_unique_id(), origin, direction)
		return
	resolve_incoming_shot.rpc_id(NetworkManager.SERVER_PEER_ID, origin, direction)


## The network entry point of a shot: a client asking the host to resolve it.
##
## Runs on the server, or it does nothing at all.
@rpc("any_peer", "call_remote", "reliable")
func resolve_incoming_shot(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_resolve_shot(multiplayer.get_remote_sender_id(), origin, direction)


## The authoritative end of a shot, on the host. [param sender] is the peer that
## asked - read from the transport for a client, and the host's own id for the
## host's player.
func _resolve_shot(sender: int, origin: Vector3, direction: Vector3) -> void:
	# A client may only speak for its own body. Without this, any peer could
	# fire on any other peer's behalf - including making somebody else's player
	# shoot, which would then be validated against a ray origin the attacker
	# chose rather than one they were standing at.
	if sender != peer_id:
		_rejected_shots += 1
		push_warning("[Combat] peer %d tried to fire player %d's weapon; refused." % [
			sender, peer_id])
		return

	# A dead player's queued shots are not honoured.
	if not state.is_alive or weapon == null or weapon.data == null:
		_rejected_shots += 1
		return

	# A zero-length direction would make `hitscan` normalise a null vector and
	# either throw or produce a NaN that poisons every later calculation on the
	# body. Cheap to refuse, so it is refused before anything else looks at it.
	if direction.length_squared() < 0.000001:
		_rejected_shots += 1
		return

	# Rate limit against the weapon's own fire interval, with a small allowance
	# for the fact that the two machines are not sharing a clock.
	#
	# This is not a substitute for the weapon's fire-rate enforcement - the
	# client already enforces that, and it is the client that owns the magazine.
	# It is here so the host is not a free damage button for a modified client
	# that removed the check locally.
	#
	# A token bucket rather than a minimum gap between arrivals: packets bunch
	# up (a frame that ran two physics steps, ordinary network jitter), so two
	# honest shots can arrive a few milliseconds apart. The bucket refills at
	# the weapon's fire rate and holds at most [constant SHOT_BURST_ALLOWANCE]
	# shots, so bunching is fine but a sustained rate above the weapon's is not.
	var now := Time.get_ticks_msec()
	var interval_ms := 60.0
	if weapon != null and weapon.data != null:
		interval_ms = maxf(weapon.data.fire_interval * 1000.0 - SHOT_CLOCK_TOLERANCE_MS, 20.0)
	_shot_budget = minf(SHOT_BURST_ALLOWANCE, _shot_budget + float(now - _last_validated_shot_ms) / interval_ms)
	_last_validated_shot_ms = now
	if _shot_budget < 1.0:
		_rejected_shots += 1
		return
	_shot_budget -= 1.0

	# The origin is checked and then discarded. This is the important one: a
	# client that could choose its own ray origin could fire from inside a wall
	# it is not standing in, or from across the map with a direction that only
	# makes sense from somewhere else entirely. The shot is cast from where the
	# host believes this player is, so the only thing the client gets to
	# influence is where they are aiming - which is the part that is genuinely
	# theirs to decide.
	var authoritative_origin := get_eye_position()
	if authoritative_origin.distance_to(origin) > MAX_SHOT_ORIGIN_ERROR:
		_rejected_shots += 1
		return

	# The weapon's own hitscan, run by the host, against the host's world. The
	# damage path from here is identical to Chapter 3's: `hitscan` calls
	# `Damageable.deal_damage` on whatever it found, and the host's copy of
	# every player's `apply_damage` is the one that counts.
	direction = direction.normalized()
	var result := weapon.hitscan(authoritative_origin, direction)
	_report_shooting_to_echo_fields()

	var collider: Object = result.get("collider")
	var victim := Damageable.find_target(collider)
	var victim_player := victim as Player
	# A miss has no position in the result; the impact belongs at the end of
	# the ray, which is also where the host's own weapon drew it.
	var hit_point: Vector3 = result.get("position", weapon.get_last_shot_end())
	var hit_normal: Vector3 = result.get("normal", -direction)
	var zone := Damageable.resolve_zone(victim, hit_point, collider)
	# "Hit" means damage was actually dealt. Shooting a corpse or scenery is
	# not a hit, and must not flash the shooter's hit marker.
	var hit := weapon.last_damage_dealt > 0.0
	var killed := hit and victim != null and victim.has_method(&"is_dead") and bool(victim.call(&"is_dead"))

	# The host ran the raycast here, so its own weapon has already drawn the
	# impact: this is a local result.
	var surface := weapon.last_surface
	shot_resolved.emit(hit_point, hit_normal, victim_player, zone, killed, true, surface)

	# Tell the other machines what happened, so they can draw the impact and
	# the shooter's hit marker. `call_remote` means the host does not receive
	# its own message and draw every effect twice.
	_confirm_shot.rpc(
		hit_point,
		hit_normal,
		zone,
		victim_player.peer_id if victim_player != null else 0,
		hit,
		killed,
		peer_id,
		surface)


## Applies another machine's authoritative verdict about a shot.
##
## [param victim_peer_id] is 0 for scenery, which is also the peer id of "nobody"
## - the two are not being confused here because a peer id of 0 is not a thing
## ENet hands out.
##
## [b]`any_peer` with a sender check, not `authority`.[/b] This node's
## multiplayer authority is the peer that [b]owns[/b] the body, because that is
## what `is_multiplayer_authority()` has to mean elsewhere on it. The peer that
## [b]decides[/b] shots is the host, and for a client's body those are two
## different peers. An `authority` annotation would mean "only the body's owner
## may say this happened", so the host could never send a verdict about
## somebody else's shot - and the failure is silent, because the message is
## simply dropped. A receiver-side `is_server()` check would have the same
## problem in another mirror image: the host never receives its own broadcast
## (that is [code]call_remote[/code]), so the only running copies of this
## function are on clients, and a check that reads "carry on only if you are
## the server" would tell every one of them to stop. Which peer sent the
## message is the question that is actually answerable at this point in the
## code, and it is the check that preserves the authority.
##
## [b]Reliable.[/b] The hit marker and the impact effect are the only
## user-visible result of pulling the trigger on a connection that is not
## losing packets, and a dropped verdict reads as "my gun does not work".
@rpc("any_peer", "call_remote", "reliable")
func _confirm_shot(point: Vector3, normal: Vector3, zone: int, victim_peer_id: int, hit: bool, killed: bool, shooter_peer_id: int, surface: int) -> void:
	# Only the host's word counts. Checked here rather than trusted from the
	# annotation for the reason above.
	if multiplayer.get_remote_sender_id() != NetworkManager.SERVER_PEER_ID:
		return
	var victim: Player = null
	if victim_peer_id != 0:
		victim = NetworkManager.get_player_for(victim_peer_id)

	# The hit marker is the shooter's business. On every other machine this is
	# somebody else's confirmed hit and drawing a crosshair flash for it would
	# be a lie about who is shooting.
	var is_mine := shooter_peer_id == multiplayer.get_unique_id()
	if is_mine and hit and _hit_marker != null:
		_hit_marker.flash(zone, killed)
		_play_hit_feedback(zone, killed)
	# Always a network result here: this machine did not run the raycast (the
	# host never receives its own `call_remote` broadcast), so nothing has been
	# drawn yet - including for this machine's own shots, which previously
	# produced no impact at all on a client.
	shot_resolved.emit(point, normal, victim, zone, killed, false, surface)


func _on_recoil_requested(_pitch_degrees: float, _yaw_degrees: float) -> void:
	var steady := aim.recoil_scale()
	add_recoil(_pitch_degrees * steady, _yaw_degrees * steady)
	_apply_view()
	_viewmodel_kick = 1.0


func _on_hit_confirmed(killed: bool, zone: int, _health_left: int) -> void:
	# Raised wherever the hitscan ran - which, for a client's shot, is the
	# host's copy of that client. Only the shooter's own machine gets feedback.
	if is_network_remote:
		return
	if _hit_marker != null:
		_hit_marker.flash(zone, killed)
	_play_hit_feedback(zone, killed)


## The sound half of a hit marker: a tick for a body shot, a bright ding for a
## headshot, a chime for a kill.
func _play_hit_feedback(zone: int, killed: bool) -> void:
	if killed:
		Audio.play(&"kill", -2.0, 0.0)
	elif zone == Damageable.HitZone.HEAD:
		Audio.play(&"hit_head", -3.0, 0.02)
	else:
		Audio.play(&"hit_body", -6.0, 0.05)


func _on_reload_started(duration: float) -> void:
	reloading_changed.emit(true, duration)
	if not is_network_remote:
		Audio.play(&"reload_out", -6.0)


func _on_reload_finished() -> void:
	reloading_changed.emit(false, 0.0)
	if not is_network_remote and weapon != null and weapon.is_full():
		Audio.play(&"reload_in", -5.0)


func _on_dry_fired() -> void:
	if not is_network_remote:
		Audio.play(&"dry_fire", -6.0)
	# Nothing visual yet - Chapter 8's job. The signal exists so there is
	# somewhere obvious to put the click, and so a test can prove an empty
	# weapon is distinguishable from a working one.
	dry_fired.emit()


## Primary + sidearm, switching and buying. See [PlayerLoadout].
@onready var loadout: PlayerLoadout = $Loadout

## Aiming down sights. See [PlayerAim].
@onready var aim: PlayerAim = $Aim

## Weapon sway, bob, sprint pose and landing - cosmetic. See [PlayerViewFeel].
@onready var view_feel: PlayerViewFeel = $ViewFeel

## Set by the objective while this player is planting or defusing: movement,
## jumping and firing stop, looking around does not.
var objective_lock: bool = false


# --- Public API --------------------------------------------------------
# Chapter 3+ and the network layer talk to the player through these, not by
# reaching into its internals.

# --- Footsteps --------------------------------------------------------------

## Metres between footsteps.
const STEP_STRIDE := 2.3

## Below this speed a player is silent. Walking at full speed or sprinting is
## heard; crouching and moving while aimed are not - the tactical trade of
## moving slowly to move quietly.
const STEP_MIN_SPEED := 4.2

var _step_distance: float = 0.0
var _step_last_position: Vector3 = Vector3.INF
var _step_airborne_speed: float = 0.0
var _step_was_grounded: bool = true


## Plays footsteps for every body, measured from how it actually moved - so it
## works the same for a remote body driven by snapshots. Your own are quiet and
## flat; everyone else's are positioned, so you can hear where they are.
func _update_footsteps(delta: float) -> void:
	var here := global_position
	if _step_last_position == Vector3.INF or delta <= 0.0:
		_step_last_position = here
		return
	var moved := Vector2(here.x - _step_last_position.x, here.z - _step_last_position.z).length()
	var vertical_speed := (here.y - _step_last_position.y) / delta
	_step_last_position = here
	var speed := moved / delta

	var grounded := is_on_floor() if not is_network_remote else absf(vertical_speed) < 1.5
	if not is_network_remote:
		# Landing thump, local only.
		if not grounded:
			_step_airborne_speed = maxf(_step_airborne_speed, -velocity.y)
		elif not _step_was_grounded and _step_airborne_speed > 4.0:
			Audio.play(&"land", -6.0)
			_step_airborne_speed = 0.0
		elif grounded:
			_step_airborne_speed = 0.0
	_step_was_grounded = grounded

	# A teleport or respawn is not a run.
	if not state.is_alive or not grounded or speed < STEP_MIN_SPEED or speed > 20.0:
		return
	_step_distance += moved
	if _step_distance < STEP_STRIDE:
		return
	_step_distance = 0.0
	if is_network_remote:
		Audio.play_at(&"step", here, -1.0, 0.12, 32.0)
	else:
		Audio.play(&"step", -14.0, 0.12)


## Gives the screen back to this player's own camera - after spectating, for
## instance. Does nothing for a body this machine does not drive.
func make_view_current() -> void:
	if not is_network_remote:
		_camera.make_current()


## Where a spectator watching this player should put the camera: at the eyes,
## facing where this player faces and looks. Uses the replicated values, so it
## is correct for remote bodies, and the live ones for the local body.
func get_spectator_view() -> Transform3D:
	var yaw := net_yaw if is_network_remote else rotation.y
	var pitch := net_pitch if is_network_remote else _head.rotation.x
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	return Transform3D(basis, _head.global_position)


## Current coarse state, derived rather than stored. Deriving it means it can
## never disagree with what the body is actually doing.
func get_movement_state() -> MovementState:
	if not state.is_alive:
		return MovementState.DEAD
	if not is_on_floor():
		return MovementState.AIRBORNE
	if _stance < 0.5:
		return MovementState.CROUCHING
	if _sprint_held and not _sprint_blocked() and _is_moving():
		return MovementState.SPRINTING
	return MovementState.NORMAL


## Human-readable name for [method get_movement_state], for the debug overlay.
static func state_name(movement_state: MovementState) -> String:
	return MovementState.keys()[movement_state]


## Current collision height, interpolated between crouch and stand.
func get_current_height() -> float:
	return lerpf(crouch_height, stand_height, _stance)


## Eye height, for anything that needs to know where this player is looking
## from - a weapon muzzle in Chapter 3, a spawn point in Chapter 4.
func get_eye_position() -> Vector3:
	return _head.global_position


## Forward direction including pitch, which is where a shot should go.
func get_look_direction() -> Vector3:
	return -_camera.global_transform.basis.z


func is_sprinting() -> bool:
	return get_movement_state() == MovementState.SPRINTING


func is_crouching() -> bool:
	return get_movement_state() == MovementState.CROUCHING


# --- Health and damage (Chapter 3) --------------------------------------

## Takes damage and returns how much health was actually removed, or 0.0 if
## nothing happened.
##
## [b]This is the whole of the player's damage surface.[/b] A weapon calls it
## through [method Damageable.deal_damage]; the Chapter 3 turret calls it
## through the same static; Chapter 4's replicated shots call it on the host
## after validation. Nothing else has a way in, and nothing else needs to -
## which is precisely what stops a client from deciding its own health.
## The zone of the most recent damaging hit, so a death can report whether it
## was a headshot.
var _last_hit_zone: int = Damageable.HitZone.BODY


func apply_damage(amount: float, _source: Node = null, _zone: Damageable.HitZone = Damageable.HitZone.BODY) -> float:
	if not state.is_alive or amount <= 0.0:
		return 0.0

	var removed := state.apply_damage(amount)
	if removed > 0.0:
		_last_hit_zone = _zone
		took_hit.emit(_source, removed, _zone)
		var attacker := _source as Player
		EventBus.player_damaged.emit(peer_id,
			attacker.peer_id if attacker != null else EventBus.INVALID_PEER, removed)
		health_changed.emit(state.health, state.is_alive)
		# Published before the death check, so a lethal hit still sends the
		# final health value. `_publish_net_state` is a no-op off the host, so
		# a client calling apply_damage locally changes only its own screen.
		_publish_net_state()
	if not state.is_alive:
		die(_source)
	return removed


## Reports which part of the player was hit, from where on the capsule the
## round landed. See [member head_hit_fraction] for why this is a band and not
## a second collider.
##
## [param collider] is ignored. A player has exactly one collider, so there is
## nothing to disambiguate - which is the whole reason the player's zones are
## derived and the practice target's are not.
func resolve_hit_zone(point: Vector3, _collider: Object = null) -> Damageable.HitZone:
	# Measured from the feet, and against the current height, so a crouched
	# player's head band is 0.2 m off the floor rather than 0.32 m. Using an
	# absolute height here would make the head unreachable while crouched.
	var up_the_body := (point.y - global_position.y) / maxf(get_current_height(), 0.001)
	return Damageable.HitZone.HEAD if up_the_body >= 1.0 - head_hit_fraction \
		else Damageable.HitZone.BODY


func get_health() -> int:
	return state.health


func get_max_health() -> int:
	return PlayerState.MAX_HEALTH


func is_dead() -> bool:
	return not state.is_alive


## Moves a remote body smoothly toward where the network says it is.
##
## Three snapshots are kept and the body is drawn at the position the network
## had one snapshot-interval ago, which is the standard trick for turning a
## series of discrete updates into continuous motion: you deliberately show
## slightly stale data, and spend the latency smoothing the gap between
## updates. One snapshot of history is not enough to interpolate *between*
## arrivals, and without history at all the body visibly steps.
##
## The fallback matters more than the happy path. A body that has received no
## snapshot yet - or has just spawned and is waiting for the first one - would
## otherwise be drawn at the world origin, which in this map is the middle of
## the practice range, so a late joiner appears as a player standing in the
## targets before their first packet lands.
func _advance_remote_interpolation(delta: float) -> void:
	var now := _net_time_now()

	if _snapshot_positions.is_empty():
		# Waiting for the first snapshot. Hold the spawn point rather than
		# defaulting to the origin.
		if not _render_initialised:
			_render_position = global_position
			_render_rotation_y = rotation.y
			_render_initialised = true
		return

	# Discard snapshots that are older than the window we are interpolating
	# across. The array is tiny and this runs once per physics tick per remote
	# body, so a linear pass is cheaper than maintaining a ring buffer and far
	# easier to read.
	while _snapshot_times.size() >= 2 \
			and now - _snapshot_times[0] > TRANSFORM_REPLICATION_SECONDS * REMOTE_SNAPSHOT_HISTORY:
		_snapshot_times.remove_at(0)
		_snapshot_positions.remove_at(0)

	var target_position := _snapshot_positions[_snapshot_positions.size() - 1]
	var target_yaw := net_yaw

	# Interpolate between the two most recent snapshots when we are between
	# their arrival times, rather than always chasing the newest one. Chasing
	# the newest one alone is just smoothing, and it introduces a consistent
	# half-interval of lag on top of the network's own.
	if _snapshot_times.size() >= 2:
		var previous_time := _snapshot_times[_snapshot_times.size() - 2]
		var previous_position := _snapshot_positions[_snapshot_positions.size() - 2]
		var newest_time := _snapshot_times[_snapshot_times.size() - 1]
		var span := newest_time - previous_time
		if span > 0.0001:
			var t := clampf((now - previous_time) / span, 0.0, 1.0)
			# Smoothstep rather than linear, so a body does not change direction
			# with a visible corner at every snapshot boundary.
			var eased := t * t * (3.0 - 2.0 * t)
			target_position = previous_position.lerp(target_position, eased)

	# Bounded catch-up, so a body dropped in by a respawn crosses the map
	# quickly instead of gliding there over several seconds.
	var to_target := target_position - _render_position
	var step := REMOTE_CATCHUP_SPEED * delta
	_render_position += to_target if to_target.length() <= step else to_target.normalized() * step

	_render_rotation_y = lerp_angle(_render_rotation_y, target_yaw, minf(1.0, delta * 12.0))
	global_position = _render_position
	rotation.y = _render_rotation_y
	# The head follows the replicated pitch too, so anything placed relative to
	# it - the muzzle a tracer starts from, a spectator's view - points where
	# this player is actually looking.
	_head.rotation.x = lerp_angle(_head.rotation.x, net_pitch, minf(1.0, delta * 12.0))
	_render_initialised = true


## Discards interpolation history and puts a remote body exactly at
## [param point]. Used for teleports, where gliding from the old spot would be a
## lie about where the player is.
func _snap_remote_to(point: Vector3) -> void:
	_snapshot_positions.clear()
	_snapshot_times.clear()
	_snapshot_positions.append(point)
	_snapshot_times.append(_net_clock)
	_render_position = point
	_render_initialised = true
	global_position = point


## Seconds since this body started, used to timestamp snapshots.
##
## Every snapshot is stamped on arrival and every comparison is made against
## this same local clock, so the two always agree by construction. Stamping
## with a wall clock on the sender and comparing against a wall clock on the
## receiver would be the obvious mistake here, and it is invisible until two
## machines' clocks happen to be far enough apart to make the interpolation
## extrapolate backwards.
var _net_clock: float = 0.0


func _net_time_now() -> float:
	return _net_clock


## Records an authoritative transform for a remote body to interpolate towards.
func record_net_snapshot(position: Vector3) -> void:
	if not _snapshot_positions.is_empty() \
			and _snapshot_positions[_snapshot_positions.size() - 1].distance_to(position) > TELEPORT_SNAP_DISTANCE:
		_snap_remote_to(position)
		return
	_snapshot_positions.append(position)
	_snapshot_times.append(_net_clock)
	while _snapshot_positions.size() > REMOTE_SNAPSHOT_HISTORY:
		_snapshot_positions.remove_at(0)
		_snapshot_times.remove_at(0)


## Copies replicated health, team and death into [member state] when they
## change, and runs the local presentation for a death this machine did not
## cause.
##
## Pushed, not polled: [method _net_state_receive] hands this the host's trio
## exactly when the host changes something, so it runs once per change and
## there is nothing to poll. The helper keeps its own guard rails - the team
## clobber gate below, the death presentation guard - so that a spurious or
## re-sent value is harmless rather than rely on the caller to be careful.
func _sync_state_from_network() -> void:
	# [b]Wait for the host to actually speak before believing any of it.[/b]
	#
	# The mirror fields are initialised to safe-looking defaults - full health,
	# alive, no side - and "no side" is a value the host never sends, because
	# every player is assigned one before they are spawned. So a body that has
	# not been told its team yet is distinguishable from a body that was told it
	# has no team, and the distinction has to be respected.
	#
	# Without this, the first physics frame after a remote body spawns reads
	# `net_team` as [constant Team.Side.NONE], decides the authoritative answer
	# is "unassigned", and overwrites the side the spawn data already put there.
	# The result is a body that is correctly on BRAVO in the roster and
	# correctly grey and unassigned on the machine that draws it, with no error
	# anywhere - and it gets worse rather than better, because the host's copy
	# of every client is remote, so every one of them clobbers itself.
	if not _net_state_received:
		if net_team == Team.Side.NONE:
			return
		_net_state_received = true

	if net_team != state.team:
		state.assign_team(net_team)
		# A team can only change before a round starts, but a client does not
		# know that and must not be relying on a rule it cannot see. Repainting
		# on the replicated value means a late team assignment is reflected
		# wherever the host decided it.
		_apply_team_colour()

	if net_health == state.health and net_alive == state.is_alive:
		# Shield or scoreboard change only; still worth telling the HUD.
		health_changed.emit(state.health, state.is_alive)
		return

	state.health = net_health
	state.is_alive = net_alive

	# Alive again after a death this machine drew: stand the corpse back up.
	# Normally [method _net_respawn_at] has already done it, and then this is
	# a no-op; it is here so a missed or reordered respawn cannot leave a
	# living player stuck on the corpse layer with the camera on the floor.
	if net_alive and _is_dying:
		_reset_life_presentation()

	if not net_alive:
		# A death this machine did not cause. [method die] is deliberately not
		# called: it credits the scoreboard, and the host is the only machine
		# allowed to do that, or every client would count the same kill. The
		# presentation - corpse layer, camera fall, weapon lowered - is local
		# and has to happen anyway, so it is factored out below.
		_begin_death_presentation(null)
		return

	health_changed.emit(state.health, true)


## Everything [method die] does that is presentation rather than authority.
##
## Split out because those are two different jobs with two different owners.
## The host runs this and also credits the death; a client runs this and
## credits nothing. Folding them back together would mean a client incrementing
## a death count it was never entitled to, once per peer that died.
func _begin_death_presentation(source: Node) -> void:
	if _is_dying:
		return

	_is_dying = true
	aim.reset()
	_death_tilt = 0.0
	_death_eye_start = _head.position.y
	_apply_view()

	velocity = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	_sprint_held = false
	_crouch_held = false

	collision_layer = CollisionLayers.CORPSE
	_set_weapon_visible(false)
	# The body mesh is hidden on a living local player because you are standing
	# inside it. A corpse has no inside, and a corpse nobody can see is a death
	# that only happened to the victim - so the mesh comes on here, already
	# tinted with whatever side this player was on.
	if _body_mesh != null:
		_body_mesh.visible = true
		_apply_team_colour()
	if weapon != null:
		weapon.cancel_reload()

	# TEMPORARY (offline test arena only): auto-respawn after a short delay so
	# the playtest does not leave you staring at a corpse forever. Online, the
	# round loop owns respawns (see [method server_respawn_at]). Counted down in
	# [method _physics_process] rather than awaited: an `await` on a timer
	# resumes on a freed player if the scene changes during those seconds.
	if not NetworkManager.is_online:
		_offline_respawn_left = OFFLINE_RESPAWN_SECONDS


## TEMPORARY: seconds before an offline corpse gets up again. See
## [method _begin_death_presentation].
const OFFLINE_RESPAWN_SECONDS := 3.0
var _offline_respawn_left: float = 0.0


func _tick_offline_respawn(delta: float) -> void:
	if _offline_respawn_left <= 0.0:
		return
	if NetworkManager.is_online or not _is_dying:
		_offline_respawn_left = 0.0
		return
	_offline_respawn_left -= delta
	if _offline_respawn_left <= 0.0:
		respawn()


## Host only. Brings this player back to life at [param point] on every
## machine.
##
## An RPC rather than a local call because the owning client is authoritative
## for its own transform: a host that just teleported its copy of a client's
## body would be overwritten by the next snapshot from that client, and the
## client itself would still be lying on the floor. So every machine runs the
## same reset, and the owner moves itself.
func server_respawn_at(point: Vector3, facing_yaw: float) -> void:
	if not NetworkManager.is_online:
		respawn()
		teleport_to(point, facing_yaw)
		return
	if not multiplayer.is_server():
		return
	_net_respawn_at.rpc(point, facing_yaw)


@rpc("any_peer", "call_local", "reliable")
func _net_respawn_at(point: Vector3, facing_yaw: float) -> void:
	# Only the host may raise anyone. `any_peer` with a sender check for the
	# same reason as [method _confirm_shot]: this body's authority is its owner.
	# (A `call_local` call on the host reports a sender id of 0.)
	var sender := multiplayer.get_remote_sender_id()
	if sender != NetworkManager.SERVER_PEER_ID and not (sender == 0 and multiplayer.is_server()):
		return
	respawn()
	teleport_to(point, facing_yaw)


## Puts the player back on their feet with a full magazine. Used by the test
## harness, and by the round loop through [method server_respawn_at].
func respawn() -> void:
	state.respawn()
	_reset_life_presentation()
	_publish_net_state()
	health_changed.emit(state.health, true)


## Everything [method respawn] does that is presentation rather than authority -
## the mirror image of [method _begin_death_presentation]. Split out so a client
## told by the host that a player is alive again can stand the corpse back up
## without pretending to be the authority for its health.
func _reset_life_presentation() -> void:
	_is_dying = false
	aim.reset()
	_offline_respawn_left = 0.0
	_death_tilt = 0.0
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0

	# Back on the player layer before the body is standing up again, or the
	# corpse stays intangible and shots pass through it while it is rising.
	collision_layer = CollisionLayers.PLAYER
	collision_mask = CollisionLayers.PLAYER_BODY_MASK

	_stance = 1.0
	_apply_stance()
	_apply_view()

	# The corpse mesh goes back off for a local player, who is once again
	# standing inside it. A remote body keeps its own visible on.
	if _body_mesh != null and not is_network_remote:
		_body_mesh.visible = false

	# The weapon only comes back into view on the machine that looks through
	# it; a remote body never shows a viewmodel.
	_set_weapon_visible(not is_network_remote)
	objective_lock = false
	if weapon != null:
		loadout.refill()


## Enters the dead state: control off, movement stopped, camera on the way to
## the floor, weapon lowered, and the body moved to the corpse layer.
##
## [b]The body stays in the scene.[/b] Removing it would be easier and is the
## wrong call - the chapter's own note about not spawning a duplicate Player
## applies to the corpse too, and Chapter 5 needs an eliminated player to remain
## a thing that is present in the world rather than a hole where someone was.
##
## [b]The corpse layer, not the player layer.[/b] A dead player has to stay
## solid - it blocks movement, it can be shot for effect - but it must stop
## being a valid combatant, or a corpse would be an aim target and would keep
## absorbing headshots. Those are different questions, so it is a different
## layer. See [constant CollisionLayers.CORPSE].
func die(source: Node = null) -> void:
	# Guarded on [member _is_dying], NOT on [member PlayerState.is_alive].
	#
	# The obvious guard - "if not is_alive, return" - is wrong here, and silently
	# so. The usual route into this function is [method apply_damage], and
	# [method PlayerState.apply_damage] sets [code]is_alive = false[/code] the
	# moment health reaches zero, before this is ever called. So the guard would
	# always be true on entry and the entire death sequence - corpse layer, camera
	# fall, weapon lowered, scoreboard credit - would never run. The body would
	# report itself dead and carry on standing up. This is the same trap
	# [method PlayerState.record_death] already had to be given its own guard for;
	# reaching zero health and being *counted* are separate concerns and need
	# separate flags.
	if _is_dying:
		return

	# Entered by routing through the state first: apply_damage above may have
	# already dropped health to zero, and this is the one place that is allowed
	# to notice.
	state.is_alive = false
	var newly_recorded := state.record_death()
	died.emit(source)

	# Scoreboard credit. Only the authority for health ever reaches this - a
	# client learns about deaths through [method _sync_state_from_network],
	# which deliberately never calls die() - so a kill is counted exactly once.
	if newly_recorded:
		var killer := source as Player
		var killer_id := EventBus.INVALID_PEER
		if killer != null and killer != self:
			# Named in the kill feed either way; credited only for an enemy.
			killer_id = killer.peer_id
			if killer.state.team != state.team:
				killer.state.record_kill()
				Economy.add_credits(killer.state, GameManager.match_rules.kill_credits)
				killer._publish_net_state()
		# The bought weapon is lost with the life.
		loadout.server_on_death()
		var headshot := _last_hit_zone == Damageable.HitZone.HEAD
		EventBus.player_died.emit(peer_id, killer_id, headshot)
		if NetworkManager.is_online:
			_net_death_event.rpc(killer_id, headshot)

	_begin_death_presentation(source)

	# Only the machine that is authoritative for this body's health writes the
	# mirrored fields. A client that wrote them here would be sending its own
	# idea of its health to every other peer, and whichever arrived last would
	# win - which is the entire failure mode the split authority exists to
	# prevent.
	_publish_net_state()

	health_changed.emit(state.health, false)


## Host to clients: "this player was killed by that one". Lets every machine
## raise [signal EventBus.player_died] for the kill feed. Health and the corpse
## are handled separately by the state RPC.
@rpc("any_peer", "call_remote", "reliable")
func _net_death_event(killer_id: int, headshot: bool) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.SERVER_PEER_ID:
		return
	EventBus.player_died.emit(peer_id, killer_id, headshot)


## Copies [member state] into the mirror fields and broadcasts them.
##
## Host-only by contract. Called on every health change, and nothing else, so
## there is one place where "the game decided this player is at 40" becomes
## "the network is told this player is at 40".
func _publish_net_state(broadcast: bool = true) -> void:
	if not multiplayer.is_server():
		return
	net_health = state.health
	net_alive = state.is_alive
	net_team = state.team
	if not NetworkManager.is_online or not broadcast:
		return
	NetworkManager.players.record_health(peer_id, state.health, state.is_alive)
	_net_state_receive.rpc(net_health, net_alive, net_team, state.kills, state.deaths, state.credits, state.shield)


## Applies the host's authoritative word about a body's health, team and death.
##
## This is the receiving half of [method _publish_net_state]. It is a
## change-driven push rather than a synchroniser poll, because - as the notes
## beside [method configure_for_network] record - a [MultiplayerSynchronizer]
## with server authority cannot carry a client-owned body's state back to the
## client that owns it.
##
## [b]`any_peer` with a sender check, not `authority`.[/b] This node's
## multiplayer authority is the peer that [b]owns[/b] the body, because that is
## what `is_multiplayer_authority()` has to mean elsewhere on it - for input,
## for the transform synchroniser, for the shot handshake. The peer that
## [b]decides[/b] the body's health is the host, and for a client's body those
## are two different peers. An `authority` annotation would mean "only the
## body's owner may write its health", which hands the client exactly the
## authority this chapter exists to take away. Sender identity is the
## verifiable thing, and it is verified.
@rpc("any_peer", "call_remote", "reliable")
func _net_state_receive(health_value: int, alive: bool, side: int, kills: int, deaths: int, credits: int, shield: int) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.SERVER_PEER_ID:
		return

	# Scoreboard numbers and credits are the host's; a client only mirrors them.
	state.kills = kills
	state.deaths = deaths
	state.credits = credits
	state.shield = shield

	net_health = health_value
	net_alive = alive
	net_team = side
	_sync_state_from_network()


## Adds a recoil kick to the view. Degrees, positive lifts the camera.
##
## Called by the weapon, which knows how much kick the weapon has. The
## [member max_recoil_pitch_degrees] cap lives here because it is a limit on how
## far the [b]player's view[/b] may be displaced, not a property of any gun.
func add_recoil(pitch_degrees: float, yaw_degrees: float) -> void:
	if state.is_alive:
		_recoil_pitch = minf(_recoil_pitch + pitch_degrees, max_recoil_pitch_degrees)
		_recoil_yaw = clampf(_recoil_yaw + yaw_degrees, -max_recoil_yaw_degrees, max_recoil_yaw_degrees)


## How far the view is currently displaced by recoil, in degrees. Zero when the
## view is where the player is actually aiming.
func get_recoil_offset() -> Vector2:
	return Vector2(_recoil_pitch, _recoil_yaw)


## The pitch the player is actually aiming at, in radians, ignoring recoil. The
## test harness checks that a burst leaves this unchanged.
func get_look_pitch() -> float:
	return _look_pitch


## Turns keyboard and mouse control on or off. Chapter 4 calls this with
## false for every player it is not authoritative for.
func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		capture_mouse(false)


## Shows or hides the mouse. While visible the player stops looking around, so
## this doubles as the pause-for-development affordance the brief asks for.
func capture_mouse(captured: bool) -> void:
	if not input_enabled:
		captured = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Drops the player at a point, clearing momentum. Chapter 4's spawn path
## calls this rather than setting position directly, so a respawn never
## inherits the velocity of the death.
func teleport_to(point: Vector3, facing_yaw: float = 0.0) -> void:
	velocity = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	rotation.y = facing_yaw
	_look_pitch = 0.0
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	_apply_view()
	global_position = point
	# Cleared deliberately. The floor flag still reads true for one frame after
	# the move, and _apply_vertical_motion would spend that frame refilling the
	# coyote window - which would hand a player dropped into mid-air a free jump.
	_coyote_left = 0.0
	if is_network_remote:
		# A remote body is drawn from snapshots; moving it here without
		# resetting them would have the interpolation drag it straight back.
		net_yaw = facing_yaw
		_snap_remote_to(point)
		return
	move_and_slide()
	_write_net_transform()


# --- Input -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return

	if event.is_action_pressed(&"toggle_mouse_capture"):
		capture_mouse(not is_mouse_captured())
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"weapon_primary"):
		loadout.switch_to(PlayerLoadout.SLOT_PRIMARY)
		return
	if event.is_action_pressed(&"weapon_sidearm"):
		loadout.switch_to(PlayerLoadout.SLOT_SIDEARM)
		return

	# Echo Field deployment (Chapter 6)
	if event.is_action_pressed(&"echo_field") and state.is_alive:
		_try_deploy_echo_field()
		get_viewport().set_input_as_handled()
		return

	# Looking around only makes sense with the mouse captured. Checking here
	# rather than trusting the mouse mode means an alt-tab back into the
	# window does not immediately start spinning the camera.
	#
	# Allowed while dead, unlike movement and firing. Being killed should not
	# take the camera away at the moment the player is trying to see what got
	# them - and the pitch is clamped the same way as always, so nothing about
	# the dead state can drive the view somewhere it should not.
	if event is InputEventMouseMotion and is_mouse_captured():
		_look(event as InputEventMouseMotion)


func _look(motion: InputEventMouseMotion) -> void:
	var sensitivity: float = GameConfig.mouse_sensitivity * sensitivity_scale
	# An unconfigured sensitivity must not make the camera unusable.
	if sensitivity <= 0.0:
		sensitivity = sensitivity_scale
	# Scaled down with the zoom, so a mouse movement covers the same part of
	# the screen aimed as at the hip.
	sensitivity /= aim.zoom()

	view_feel.add_look(motion.relative)
	var delta := motion.relative * sensitivity

	# Yaw on the body so movement follows where the player is facing.
	rotate_y(-delta.x)

	# Pitch on the head, clamped every frame. Clamping the absolute angle
	# rather than the increment is what makes it impossible to flip: past the
	# limit the value stops, it does not wrap.
	#
	# The invert setting flips this frame's delta, never the accumulated angle.
	# Negating the total instead would send a view already tilted 30 degrees to
	# -30 on the first inverted mouse movement, rather than mirroring it.
	var pitch_delta := -delta.y
	if GameConfig.invert_mouse_y:
		pitch_delta = -pitch_delta

	var limit := deg_to_rad(pitch_limit_degrees)
	_look_pitch = clampf(_look_pitch + pitch_delta, -limit, limit)
	_apply_view()


## Writes the head's actual rotation from the player's true aim, the current
## recoil offset, and the death fall.
##
## Every camera angle in this game comes out of this one function. The head's
## [member Node3D.rotation] is [b]output, never input[/b] - nothing else writes
## to it - which is what guarantees that recoil cannot permanently redirect the
## view and that the death fall cannot be undone by a crouch command.
func _apply_view() -> void:
	var pitch := _look_pitch

	if _is_dying:
		pitch = lerpf(pitch, deg_to_rad(78.0), _death_tilt)

	# Recoil subtracts: a positive kick lifts the camera, and a positive x
	# rotation looks down in Godot's right-handed Y-up basis.
	_head.rotation.x = clampf(pitch - deg_to_rad(_recoil_pitch), -deg_to_rad(100.0), deg_to_rad(100.0))
	_head.rotation.z = lerpf(_head.rotation.z, deg_to_rad(_recoil_yaw) * 0.6, 0.5)
	_head.rotation.y = deg_to_rad(_recoil_yaw) * 0.4


## Recovers recoil, advances the death fall, and drives the weapon.
func _update_combat(delta: float) -> void:
	# Recoil recovery runs even while dead, so a player killed mid-burst does
	# not leave the view stuck off-aim when they respawn.
	if _recoil_pitch > 0.0:
		_recoil_pitch = maxf(_recoil_pitch - recoil_recovery_degrees * delta, 0.0)
	if _recoil_yaw != 0.0:
		_recoil_yaw = move_toward(_recoil_yaw, 0.0, recoil_recovery_degrees * delta)

	if _is_dying and _death_tilt < 1.0:
		_death_tilt = minf(_death_tilt + delta / maxf(death_camera_fall_seconds, 0.01), 1.0)
		# The camera sinks to the floor. The body's own capsule is left alone,
		# so the corpse is still a full-height obstacle and still gets shot.
		# Driven straight from the death timer, rather than approached with a
		# lerp toward a moving target.
		#
		# The lerp version is the obvious way to write a "sink to the floor",
		# and it has two problems. It is exponential, so it is still visibly
		# short of the target when the fall should be over - a body left with
		# its eyes at chest height a full second after dying, because each
		# frame only closed a fraction of whatever was left. And because it
		# reads the head's current height every frame, where the camera came
		# to rest depended on the frame rate. Deriving the height from a 0-to-1
		# timer means the camera is provably at [member death_camera_height]
		# when the timer reaches 1, at any frame rate.
		#
		# The body capsule is deliberately left at its standing height, so the
		# corpse is still a full-height obstacle and still gets shot.
		_head.position.y = lerpf(_death_eye_start, death_camera_height, ease(_death_tilt, 0.7))
		_apply_view()

	if weapon == null:
		return

	# The trigger is read here and nowhere else. The player owns the input
	# switch, so a remote player with input off holds a weapon that cannot fire
	# and the weapon itself never has to know the word "input".
	# The pointer must be captured too: with it free the player is clicking on
	# a menu (buy, Esc), and those clicks must not also fire the gun.
	var can_trigger := _controls_active() and is_mouse_captured()
	weapon.update_trigger(
		can_trigger and Input.is_action_pressed(&"fire"),
		can_trigger and Input.is_action_just_pressed(&"fire"),
		delta)

	if can_trigger and Input.is_action_just_pressed(&"reload"):
		weapon.try_reload()


# --- Movement ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tick_offline_respawn(delta)
	_read_input()
	aim.update(delta)
	_apply_aim()
	_update_combat(delta)
	_update_viewmodel_kick(delta)

	# A remote body is not simulated here. It did the moving on the machine that
	# owns it and the transform arrived over the network, so running the
	# Chapter 2 controller on it as well would mean two things writing
	# `global_position` sixty times a second - the controller's gravity and the
	# synchroniser's arrival - and the visible result is a body that jitters
	# where it stands and slowly sinks through the floor.
	#
	# The early return is placed after the combat update on purpose. Death
	# presentation still has to run on a remote body, because a client learns
	# that somebody died from a state RPC rather than from a local
	# apply_damage call, and skipping this would leave remote corpses standing
	# upright forever. (The RPC itself is applied where it arrives, in
	# [method _net_state_receive], which calls [method _begin_death_presentation]
	# through the ordinary state path - it does not need this loop to reach it.)
	if is_network_remote:
		_net_clock += delta
		_advance_remote_interpolation(delta)
		# Follow the owner's crouch, so the hitbox, head zone and the eye the
		# host fires this player's shots from all match what they are doing.
		if not _is_dying and not is_equal_approx(_stance, net_stance):
			_stance = move_toward(_stance, net_stance, stance_change_speed * delta)
			_apply_stance()
		_update_footsteps(delta)
		return

	# Health, team and death are the host's and the host alone. The RPC handling
	# in [method _net_state_receive] runs on [b]every body on every machine
	# except the host's[/b] - including this machine's own player.
	#
	# That last part is the one that is easy to miss, and it is the difference
	# between a working chapter and one that appears to work. A client's own
	# body is not a remote body, so the `is_network_remote` branch above never
	# reached it, so the client kept its own optimistic guess of its health
	# forever: the host thought it was at 60, the player was convinced it was at
	# 100, and taking damage appeared to do nothing at all. The whole point of
	# host authority is that the client is told the truth about itself, and
	# "itself" is precisely the body the other code path skips. (The one
	# machine that never receives the RPC is the host: [code]call_remote[/code]
	# does not echo to the caller, and the host does not need to be told what it
	# already decided.)
	#
	# Nothing is polled here. The RPC handler applies the host's trio itself.

	_apply_horizontal_motion(delta)
	_apply_vertical_motion(delta)
	_update_stance(delta)

	# A ledge is only stepped over while actually trying to move into it.
	# Stepping while stationary would lift the player onto whatever they are
	# standing next to.
	#
	# Fed from _move_velocity, not velocity: a player walking into a step has
	# velocity zeroed along that axis by the collision that has just happened,
	# and a zero-length sweep reports the ledge as absent.
	#
	# The vertical cancel matters as much as the horizontal input. The step is
	# tested against horizontal motion alone, so the frame has to resolve as
	# horizontal motion alone too; leaving the usual downward push in place
	# sinks the freshly lifted body straight back into the ledge and the player
	# stalls against the step forever.
	if is_on_floor() and _try_step_up(Vector3(_move_velocity.x, 0.0, _move_velocity.z) * delta):
		velocity.y = 0.0

	move_and_slide()

	_track_floor(delta)
	_write_net_transform()
	view_feel.update(delta, velocity, is_on_floor(), is_sprinting(), aim.amount)
	_update_footsteps(delta)
	_camera.position = view_feel.camera_offset()
	_camera.rotation.z = view_feel.camera_roll()


## Copies this body's transform into the replicated properties. Only ever
## called on the machine that drives the body; see [member net_position].
func _write_net_transform() -> void:
	net_position = global_position
	net_yaw = rotation.y
	net_pitch = _head.rotation.x
	net_stance = _stance


func _read_input() -> void:
	if not _controls_active():
		_sprint_held = false
		_crouch_held = false
		return
	_sprint_held = Input.is_action_pressed(&"sprint")
	_crouch_held = Input.is_action_pressed(&"crouch")


## Whether this player's own input should move and fire them right now.
##
## [b]Two different questions, and conflating them is a trap for Chapter
## 4.[/b] [member input_enabled] means "the network owns this player's
## transform" - false for every player except the one this machine controls.
## Being alive means "this player has a body that responds to input". A remote
## corpse and a local corpse are both dead; only one of them is remote, and
## Chapter 4 needs to be able to say which.
func _controls_active() -> bool:
	return input_enabled and state.is_alive and not objective_lock


## Current movement input in world space, already rotated into the player's
## heading. [member _head] holds all the pitch, so the body basis is yaw-only
## and this cannot tilt the player off vertical.
func _wish_direction() -> Vector3:
	if not _controls_active():
		return Vector3.ZERO
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_backward")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var direction := transform.basis * Vector3(input.x, 0.0, input.y)
	direction.y = 0.0
	return direction.normalized()


func _is_moving() -> bool:
	return _wish_direction() != Vector3.ZERO


func _target_speed() -> float:
	# Crouch wins over sprint. A player holding both is crouched, because the
	# slower speed is the one that must not be bypassed.
	if _stance < 0.5:
		return crouch_speed
	if _sprint_held and not _sprint_blocked():
		return sprint_speed
	return walk_speed * _weapon_speed_multiplier() * aim.move_scale()


## The movement penalty of whatever is in the player's hands.
##
## Read from the weapon's [WeaponData] rather than hard-coded, so the Chapter 5
## buy system changing what you are carrying changes how you move with no
## change here at all. A missing weapon means no penalty, so a player with empty
## hands walks at the full Chapter 2 speed.
func _weapon_speed_multiplier() -> float:
	if weapon == null or weapon.data == null:
		return 1.0
	return weapon.data.move_speed_multiplier


## Whether the equipped weapon refuses to be sprinted with.
func _sprint_blocked() -> bool:
	return weapon != null and weapon.data != null and weapon.data.blocks_sprint


## Steers horizontal velocity toward the target speed. One place decides how
## fast the player speeds up and slows down, so acceleration and deceleration
## can never disagree.
func _apply_horizontal_motion(delta: float) -> void:
	# A dead body stops on the same frame it dies rather than coasting to a halt.
	#
	# The usual path would be a corpse decelerating over several frames at
	# 70 m/s^2, which from a sprint is most of a second of sliding along the
	# floor. That reads as a body still being pushed by something, and it lets a
	# corpse drift out of the cover it died behind. Hard stop instead.
	if not state.is_alive:
		_move_velocity = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var direction := _wish_direction()
	var target := direction * _target_speed()

	var rate: float
	if is_on_floor():
		rate = ground_acceleration if direction != Vector3.ZERO else ground_deceleration
	else:
		rate = ground_acceleration * air_control if direction != Vector3.ZERO else air_deceleration

	# Accelerated from [member _move_velocity], not from the engine's reported
	# velocity, so brushing a wall does not erase the player's momentum.
	_move_velocity = _move_velocity.move_toward(target, rate * delta)
	velocity.x = _move_velocity.x
	velocity.z = _move_velocity.z


func _apply_vertical_motion(delta: float) -> void:
	if is_on_floor():
		_coyote_left = coyote_time
		# A small constant downward push rather than exactly zero, so the
		# controller keeps testing for floor on slopes instead of drifting off
		# them. This is what floor_snap_length then holds the player to.
		velocity.y = -2.0
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -terminal_fall_speed)

	# Applies the jump itself, or does nothing. Refusals are recorded on
	# [member _last_jump_was_refused] rather than returned, because nothing
	# branches on them yet.
	_try_jump()


func _try_jump() -> void:
	_last_jump_was_refused = false
	if not _controls_active() or not Input.is_action_just_pressed(&"jump"):
		return
	# Grounded, or still inside the coyote window. Never both, so there is no
	# way to get a second jump out of one press.
	if not is_on_floor() and _coyote_left <= 0.0:
		_last_jump_was_refused = true
		return

	velocity.y = jump_velocity
	_coyote_left = 0.0


func _track_floor(delta: float) -> void:
	if is_on_floor():
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)


## Lifts the body over a ledge no taller than [member step_height].
##
## [param horizontal] is the distance this frame's movement is about to cover.
## Both tests below sweep the body that distance rather than testing a point,
## and that detail is the whole reason this works:
##
## - Asking "is anything in the way?" with a [constant] Vector3.ZERO
##   [method] sweep does not work. A zero-length sweep is degenerate, so it
##   reports clear no matter what is overhead, and the body gets lifted on open
##   ground. On a low ceiling that lift walks the player straight into the slab
##   and they stall short of it.
## - The lift is only considered when the movement is genuinely blocked, so
##   walking on the flat and following a shallow slope - both of which
##   [method move_and_slide] already handles - are left completely alone.
## - The raised test uses the same horizontal sweep, so it answers "could I
##   both be up there and still make this move?". A wall taller than
##   [member step_height] fails it and is left alone, which is what stops a
##   player climbing a wall they should have to jump.
## Returns whether a step was actually taken.
func _try_step_up(horizontal: Vector3) -> bool:
	if horizontal.length_squared() <= 0.0:
		return false

	# Free to move at the current height: there is nothing to step over. On open
	# ground and on shallow slopes this is always the answer, so the controller
	# is left entirely to move_and_slide.
	if not test_move(global_transform, horizontal):
		return false

	# Blocked, so there is a ledge. The only question left is whether it is a
	# step or a wall: the full capsule has to fit one step_height up, and this
	# frame's movement has to still be possible from there.
	#
	# The whole step_height is lifted in one go rather than a measured minimum.
	# A minimum search looks tempting - it would avoid overshooting a low tread -
	# but the thing it can actually ask is "is this one frame's move clear if
	# raised a little", and the answer stays yes for a few centimetres over
	# every ledge. The player then creeps up a stair in 0.05 m increments over
	# several frames instead of stepping. Lifting decisively puts the body
	# above the tread, and floor snapping settles the small remainder within a
	# frame or two, which reads as a step rather than a scramble.
	var raised := global_transform
	raised.origin.y += step_height

	# Third argument is the collision output, passed null because only the
	# yes/no answer is wanted; the margin is the fourth.
	if test_move(raised, horizontal, null, STEP_CLEARANCE):
		return false

	global_position.y += step_height
	return true


# --- Crouch ------------------------------------------------------------

## Moves the body between standing and crouched, and refuses to stand up if
## there is a ceiling in the way.
func _update_stance(delta: float) -> void:
	# Frozen while dead. A corpse should keep the collider height it died with;
	# letting it stand back up would make a body that was shot in the head rise
	# to full height afterwards, which is a lie about where the player is.
	if _is_dying:
		return

	if _crouch_held and _stance > 0.0:
		_stance = move_toward(_stance, 0.0, stance_change_speed * delta)
	elif not _crouch_held and _stance < 1.0:
		# Only grow back if the standing capsule fits. Checked every frame
		# while held down, so walking out from under a low passage resumes the
		# stand automatically without the player pressing anything.
		if _can_stand():
			_stance = move_toward(_stance, 1.0, stance_change_speed * delta)

	_apply_stance()


## Resizes the collision shape and moves the camera to match the stance. The
## shape's [member CollisionShape3D.position] is what keeps the player's feet
## planted: the capsule is anchored at the origin, so a shorter capsule has to
## drop by half the difference or the player sinks into the floor.
func _apply_stance() -> void:
	var height := get_current_height()
	var shape := _collision.shape as CapsuleShape3D
	shape.height = maxf(height, body_radius * 2.0 + 0.001)
	_collision.position.y = shape.height * 0.5

	# Skipped while dead. The camera's height belongs to the death fall at that
	# point, and _update_stance runs after _update_combat every frame - so
	# writing it here would put the player straight back on their feet and start
	# the whole fall over, every frame, forever.
	if not _is_dying:
		_head.position.y = lerpf(crouch_eye_height, stand_eye_height, _stance)

	# Keep the development capsule the same size as the collider, so it is
	# still an honest picture of the collision when someone enables it.
	var mesh := _body_mesh.mesh as CapsuleMesh
	if mesh != null:
		mesh.height = shape.height


## Whether a standing player would fit at the current position.
func _can_stand() -> bool:
	var shape := _collision.shape as CapsuleShape3D
	var saved_height := shape.height

	shape.height = maxf(stand_height, body_radius * 2.0 + 0.001)
	_collision.position.y = shape.height * 0.5
	var blocked := test_move(global_transform, Vector3.ZERO)

	shape.height = saved_height
	_apply_stance()
	return not blocked


# --- Debug support -----------------------------------------------------

## One-line summary for the debug overlay.
func debug_line() -> String:
	return "%s  h=%4.2f  v=%5.1f m/s  y=%5.2f  HP %3d  %s" % [
		state_name(get_movement_state()),
		get_current_height(),
		Vector2(velocity.x, velocity.z).length(),
		global_position.y,
		state.health,
		weapon.debug_line() if weapon != null else "unarmed",
	]


## Second line for the debug overlay: aim and recoil, which are the two numbers
## a Chapter 3 bug almost always turns out to be about.
func debug_line_combat() -> String:
	return "aim %+6.1f deg   recoil %+5.2f / %+5.2f   dead_tilt %.2f" % [
		rad_to_deg(_look_pitch),
		_recoil_pitch,
		_recoil_yaw,
		_death_tilt,
	]


# --- Echo Field (Chapter 6) -------------------------------------------------

## Attempts to deploy the Echo Field at the player's feet.
## Called from _unhandled_input when the echo_field action is pressed.
func _try_deploy_echo_field() -> void:
	if _echo_field == null:
		push_warning("Player: echo_field not assigned.")
		return
	
	if _echo_field.is_on_cooldown() or _echo_field.is_active:
		return
	
	# Deploy at player's position, slightly forward
	var deploy_pos := global_position + -_camera.global_transform.basis.z * 1.5
	deploy_pos.y = global_position.y
	
	_echo_field.request_deploy(deploy_pos)


## Reports shooting activity to nearby Echo Fields.
## Called wherever a shot is resolved authoritatively - offline in
## [method _on_weapon_fired], online on the host in [method _resolve_shot] -
## because detection is server-side and a client's own call would be ignored.
func _report_shooting_to_echo_fields() -> void:
	for node in get_tree().get_nodes_in_group(EchoField.GROUP):
		var field: EchoField = node as EchoField
		if field != null and field.is_active:
			var dist := global_position.distance_to(field.global_position)
			if dist <= field.detection_radius:
				field.report_activity(EchoField.ECHO_SHOOTING, global_position, state.team)
