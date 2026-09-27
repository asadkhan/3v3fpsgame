class_name Player
extends CharacterBody3D
## the first-person player. one scene, one instance per player.
##
## all movement lives in this node - no singleton, no other node moves you.
## input_enabled is the switch between "reads the keyboard" and "network sets
## the transform", so a remote player is just this scene with input off.
## identity/health/team live in state (a PlayerState) instead of loose fields.
##
## node layout: Player (yaw only) -> Head (pitch pivot, eye height) -> Camera3D.
## yaw on the body, pitch on the head, so movement is always computed from a
## level heading - a pitched body would steer you into the ground on a downhill.

# --- Signals ------------------------------------------------------------

## health changed, or player died. alive is false the frame health hits zero.
signal health_changed(health: int, alive: bool)

## a shot this player fired got resolved. victim is null for scenery. is_local
## is false when this came from the network (someone else confirming our hit).
signal shot_resolved(at: Vector3, normal: Vector3, victim: Player, zone: int, killed: bool, is_local: bool, surface: int)

## this player fired: the ray and direction, before it's resolved. used for the tracer.
signal shot_fired(origin: Vector3, direction: Vector3)

## this player got hit. fires on every machine (including the victim) so a hud
## hit indicator can just listen to it.
signal took_hit(from: Node, amount: float, zone: int)

## this player died. source is whatever killed them, may be null (falling out
## of the world).
signal died(source: Node)

## fired when the equipped weapon changes. hud re-reads ammo off this instead
## of polling.
signal weapon_changed(weapon: Weapon)

## reload started or finished. duration is the reload time when starting, 0
## when done.
signal reloading_changed(reloading: bool, duration: float)

## trigger pulled on an empty mag.
signal dry_fired

# --- Body dimensions ---------------------------------------------------
# metres. capsule origin is at the feet, so centre sits at y = h/2.

## collision height while standing.
@export var stand_height: float = 1.8

## collision height while crouched. must stay above 2x body_radius or godot
## rejects the capsule shape.
@export var crouch_height: float = 1.1

@export var body_radius: float = 0.35

# --- Speeds ------------------------------------------------------------
# tuned to feel snappy, not floaty.

@export_group("Speeds")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.6

@export_group("Acceleration")
## how fast horizontal speed is gained on the ground, in m/s^2. higher = snappier start.
@export var ground_acceleration: float = 55.0

## how fast horizontal speed is lost with no input. higher than
## ground_acceleration so letting go stops you crisply instead of sliding.
@export var ground_deceleration: float = 70.0

## air control, as a fraction of ground_acceleration. kept low so jumps commit
## instead of letting you steer freely.
@export_range(0.0, 1.0) var air_control: float = 0.22

## horizontal speed lost per second while airborne with no input. low, so
## jumps keep momentum.
@export var air_deceleration: float = 2.0

@export_group("Vertical")
## downward acceleration. higher than real gravity so jumps feel snappy and
## falls resolve fast.
@export var gravity: float = 18.0

## upward speed from a jump. with default gravity clears about 0.84m - a
## waist-high crate, not much more.
@export var jump_velocity: float = 5.5

## downward speed cap, so a long fall can't tunnel through the floor.
@export var terminal_fall_speed: float = 40.0

## grace window after walking off a ledge where jump still works (coyote
## time). 0 disables it.
@export var coyote_time: float = 0.12

## floor_snap_length lives on the node in player.tscn, not here - a script var
## of that name would shadow the engine property and silently do nothing.

## tallest ledge walked up without jumping, in metres. uses an overlap test,
## not a raycast, so it can't lift you into a ceiling.
@export var step_height: float = 0.4

## clearance required around the lifted position before stepping up. without
## it the capsule can snag on a ledge corner and stutter.
const STEP_CLEARANCE := 0.02

# --- Camera ------------------------------------------------------------

@export_group("Camera")
## turns the 0..1 sensitivity setting into radians per pixel of mouse movement.
@export var sensitivity_scale: float = 0.003

## how far up/down the head can look, in degrees. kept just under 90 so it
## never flips at the poles.
@export var pitch_limit_degrees: float = 89.0

## eye height standing vs crouched. camera interpolates between them so
## crouching doesn't jolt.
@export var stand_eye_height: float = 1.62
@export var crouch_eye_height: float = 0.95

## how fast the body/camera move between stances, per second. shared by
## collider and camera so they stay in sync.
@export var stance_change_speed: float = 9.0

## whether this player reads the keyboard. off for remote players.
@export var input_enabled: bool = true

## whether gameplay starts with the mouse captured.
@export var capture_mouse_on_ready: bool = true

## coarse movement states for the hud/debug overlay to read.
enum MovementState {
	NORMAL,
	SPRINTING,
	CROUCHING,
	AIRBORNE,
	DEAD,
}

## identity, health and team - one per player, not global.
var state: PlayerState = PlayerState.new()

# --- Network identity ----------------------------------------------

## which peer drives this body. defaults to the server id so an editor-placed
## player works standalone with no setup.
@export var peer_id: int = NetworkManager.SERVER_PEER_ID

## set when this body belongs to another peer. a remote body skips
## physics/input and has no camera - just a transform + health readout.
var is_network_remote: bool = false

## host-side bookkeeping for shot validation.
var _last_validated_shot_ms: int = -100000

## host-side count of rejected shots, shown in the dev overlay to catch a
## misbehaving client.
var _rejected_shots: int = 0


## how many shots this player's authority has refused. public so a dropped
## shot shows up as a number instead of a mystery.
func rejected_shot_count() -> int:
	return _rejected_shots

# --- Replicated state ----------------------------------------------------

## health as the network sees it - a mirror of state.health that can cross the
## wire. state is still the source of truth.
var net_health: int = PlayerState.MAX_HEALTH
var net_alive: bool = true
var net_team: int = Team.Side.NONE

## whether the host has ever sent this body's state. net_team defaults to
## NONE, which the host never actually sends, so this flag tells a fresh
## default apart from a real "no team" answer.
var _net_state_received: bool = false

## set when the host changes the mirrored fields, so a client can tell a
## replicated update from its own local guess.
var _is_net_state_authoritative: bool = true

# --- Interpolation (remote bodies only) -----------------------------------

## where a remote body was last told to be, and where it's allowed to be drawn
## while catching up. smooths out the 20hz replication steps into continuous
## motion.
var _render_position: Vector3 = Vector3.ZERO
var _render_rotation_y: float = 0.0
var _render_initialised: bool = false

## how fast (m/s) a remote body closes the gap to its real position. fast
## enough to catch up from a teleport in a couple frames.
const REMOTE_CATCHUP_SPEED := 28.0

## seconds of position history kept to interpolate through. need at least 2
## snapshots to move between updates, not just toward them.
const REMOTE_SNAPSHOT_HISTORY := 3

## a snapshot farther than this from the last one counts as a teleport
## (respawn) rather than movement, and gets snapped to instead of interpolated.
const TELEPORT_SNAP_DISTANCE := 4.0

## replicated transform. the owner writes these every physics frame; elsewhere
## the synchroniser writes them and the setter turns each arrival into an
## interpolation snapshot.
var net_position: Vector3 = Vector3.ZERO:
	set(value):
		net_position = value
		if is_network_remote:
			record_net_snapshot(value)

var net_yaw: float = 0.0

## the owner's view pitch in radians (recoil included), replicated for spectators.
var net_pitch: float = 0.0

## the owner's stance, 0 crouched .. 1 standing, replicated so every machine
## sizes the hitbox/eye height the same.
var net_stance: float = 1.0

## recent authoritative positions with their arrival times.
var _snapshot_times: PackedFloat32Array = PackedFloat32Array()
var _snapshot_positions: PackedVector3Array = PackedVector3Array()

## seconds between transform snapshots. named for the unit (seconds) rather
## than _HZ, so nobody misreads it as a rate.
const TRANSFORM_REPLICATION_SECONDS := 0.05

## how far (metres) a client's claimed eye position may be from where the host
## thinks they are before a shot is refused. generous enough to cover
## interpolation lag during a sprint.
const MAX_SHOT_ORIGIN_ERROR := 2.0

## slack (ms) on the host's fire-rate check, since client and host clocks
## don't agree exactly.
const SHOT_CLOCK_TOLERANCE_MS := 15

## how many shots can arrive back-to-back before the fire-rate check kicks in.
const SHOT_BURST_ALLOWANCE := 2.0
var _shot_budget: float = SHOT_BURST_ALLOWANCE

# --- Combat -------------------------------------------------

## the equipped weapon, or null if empty-handed. child of this node, travels with it.
@onready var weapon: Weapon = $Head/WeaponMount/Weapon

## headshot band as a fraction of current height, measured up from the feet -
## top 18% counts as a headshot. a band instead of a separate collider so it
## always tracks crouch height automatically.
@export_range(0.05, 0.5, 0.01) var head_hit_fraction: float = 0.18

## how fast the camera returns to true aim after recoil, degrees/sec. the
## weapon decides how much kick; this decides how fast it fades.
@export var recoil_recovery_degrees: float = 55.0

## the furthest recoil alone can push the camera off true aim, in degrees.
## caps a long burst from walking the view somewhere you can't pull back from.
@export var max_recoil_pitch_degrees: float = 12.0
@export var max_recoil_yaw_degrees: float = 5.0

## seconds after a shot before the camera starts settling back (~1.6 fire
## intervals), so a spray climbs instead of fighting its own recovery.
const RECOIL_RECOVERY_DELAY := 0.12

## how long the camera takes to fall to the floor after death, in seconds.
@export var death_camera_fall_seconds: float = 1.1

## how far above the floor the death camera rests, in metres.
@export var death_camera_height: float = 0.35

## the player's true aim pitch, in radians. recoil is applied on top of this,
## never added into it, so recovery always returns to exactly where you were
## aiming.
var _look_pitch: float = 0.0

## current recoil offset in degrees, applied on top of _look_pitch.
var _recoil_pitch: float = 0.0
var _recoil_yaw: float = 0.0
var _since_recoil: float = 99.0
## per-shot camera shake: a decaying random roll and nudge, in degrees.
var _shake: float = 0.0
var _shake_roll: float = 0.0
var _shake_pitch: float = 0.0
## gun rearing up in the hands, 1 right after a shot, decays to 0.
var _viewmodel_rear: float = 0.0

## how far through the death camera fall, 0 to 1.
var _death_tilt: float = 0.0

## eye height at the moment of death, so the fall starts from wherever the
## player actually was (standing or mid-crouch).
var _death_eye_start: float = 0.0

## set by die() so _update_stance stops fighting it and the camera can't
## spring back up.
var _is_dying: bool = false

## weapon mount's rest position, captured from the scene. recoil offsets from
## here instead of accumulating, so a long burst can't walk the gun into the
## player's face.
var _viewmodel_rest: Vector3 = Vector3.ZERO
var _viewmodel_kick: float = 0.0

## how fast the viewmodel returns to rest after a shot, in kicks/sec.
const VIEWMODEL_KICK_RECOVERY := 12.0

@onready var _collision: CollisionShape3D = $Collision
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _weapon_mount: Node3D = $Head/WeaponMount
@onready var _hit_marker: HitMarker = $HitMarkerLayer/HitMarker
## plain var, not @onready - needed in _enter_tree, which runs before onready inits.
var _transform_sync: MultiplayerSynchronizer = null
@onready var _echo_field: EchoField = $EchoField

## translucent capsule shown only for dev visibility, and always visible on a
## body this machine doesn't drive. parented to the collider so it can't drift.
@onready var _body_mesh: MeshInstance3D = $Collision/BodyMesh

## 0 = fully crouched, 1 = fully standing. single source of truth, read by
## camera/collider/state.
var _stance: float = 1.0

## seconds left in the coyote window.
var _coyote_left: float = 0.0

var _sprint_held: bool = false
var _crouch_held: bool = false

## horizontal speed the player wants, kept separate from velocity (which
## move_and_slide overwrites on collision). keeps intent and actual outcome
## independent so hitting a wall doesn't zero out momentum for the step-up check.
var _move_velocity: Vector3 = Vector3.ZERO

## set when a jump is refused (not grounded), so the refusal can be reported
## instead of silently swallowed.
var _last_jump_was_refused: bool = false

## identity handed in by the match scene's spawn function before this node
## enters the tree - needed because _ready runs (and grabs the mouse/camera)
## before the spawner tells us who we are otherwise.
var pending_peer_id: int = 0
var pending_team: int = Team.Side.NONE
var pending_display_name: String = ""


## authority and replication config are set here, before _ready - godot needs
## a synchroniser's authority final by the end of the spawn pass, or its first
## packets get dropped.
func _enter_tree() -> void:
	if _transform_sync == null:
		_transform_sync = $TransformSync
	_configure_replication()
	if pending_peer_id > 0:
		set_multiplayer_authority(pending_peer_id)


func _ready() -> void:
	add_to_group(&"players")

	_apply_stance()

	# replication config was already set up in _enter_tree, before any
	# synchroniser could fire at us.

	# each player owns its own mouse look via its own camera.
	_camera.fov = GameConfig.field_of_view
	GameConfig.setting_changed.connect(_on_setting_changed)

	if _weapon_mount != null:
		_viewmodel_rest = _weapon_mount.position

	_equip_weapon()
	weapon_changed.connect(func(_w: Weapon) -> void: _refresh_third_person_weapon())

	# write the head rotation once now instead of waiting for a stale first frame.
	_apply_view()

	# apply identity now, before we do local-player things like grabbing the
	# mouse or camera.
	if pending_peer_id > 0:
		configure_for_network(pending_peer_id, pending_team, pending_display_name)
		return

	_apply_authority_state()


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "video/field_of_view":
		_camera.fov = float(value)


## turns identity into everything downstream: which camera is live, whether
## the body mesh shows, whether input is read, whether the mouse is ours.
## idempotent - called from both _ready and configure_for_network.
func _apply_authority_state() -> void:
	# camera isn't `current` in the scene file - claiming it on enter would
	# steal the view from whoever had it. only the body this machine drives
	# claims it; a remote one releases without handing it off.
	if is_network_remote:
		if _camera.current:
			_camera.clear_current(false)
	else:
		_camera.make_current()

	# hide the viewmodel/hit marker on a remote body - nobody should see them.
	if is_network_remote:
		_apply_remote_appearance()
		return

	if _body_mesh != null:
		_body_mesh.visible = false

	if capture_mouse_on_ready and input_enabled:
		capture_mouse(true)


## sets this body's identity and decides who is authoritative for what. called
## on every machine with the same args, not just the authority.
func configure_for_network(p_peer_id: int, team_side: int, player_name: String = "") -> void:
	peer_id = p_peer_id
	state.setup(p_peer_id, player_name, team_side)

	# offline there's no multiplayer peer, so skip the remote check entirely -
	# nothing here is anyone's remote body.
	# use NetworkManager.local_peer_id instead of multiplayer.get_unique_id()
	# since this may run before the node's in the tree.
	is_network_remote = NetworkManager.is_online \
		and p_peer_id != NetworkManager.local_peer_id

	# authority follows the owning peer, so is_multiplayer_authority() answers
	# correctly everywhere else.
	set_multiplayer_authority(p_peer_id)

	# movement authority is the owning peer; health/team/death are always the
	# server's. transform replicates fine from a client-owned node via
	# MultiplayerSynchronizer, but a server-authority synchroniser can't carry
	# state back to the client that owns the body - godot only routes a node's
	# sync packets to its owner. so state instead crosses as a change-driven
	# rpc: the host broadcasts in _publish_net_state, clients apply it in
	# _net_state_receive.
	_transform_sync.set_multiplayer_authority(p_peer_id)

	# input is local-only: true on the owning machine, false everywhere else.
	input_enabled = not is_network_remote
	_apply_authority_state()

	# prime the mirror fields now - their defaults (esp. net_team = NONE)
	# aren't what the host actually wants to send, and this avoids a
	# wrong-then-right flicker on join.
	# mirrors only, no broadcast yet - an rpc now could reach clients before
	# the node exists there.
	_publish_net_state(false)

	# on a client, seed from the roster if it already has this peer (late
	# join), else fall back to local state.
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


## builds the transform replication config in code, so authority and the
## property list live together and are easy to audit.
##
## health, team and death are deliberately not replicated here - state
## crosses the wire as a change-driven rpc instead; see configure_for_network.
func _configure_replication() -> void:
	# add_property wants a NodePath, not a StringName (a StringName fails deep
	# inside c++ with no useful error). the path also needs a leading colon or
	# the synchronizer treats it as a chain of child node names instead of a
	# property.
	var transform_config := SceneReplicationConfig.new()
	# position + yaw is enough to draw a remote body.
	#
	# replicated through net_position/net_yaw rather than straight into
	# global_position, so the setters can feed record_net_snapshot for
	# interpolation. net_pitch rides along for spectators, net_stance so the
	# host casts shots from the right eye height/hitbox for a crouched client.
	for property in [":net_position", ":net_yaw", ":net_pitch", ":net_stance"]:
		transform_config.add_property(NodePath(property))
	_transform_sync.replication_config = transform_config

	# 20hz for movement, well under the 60hz physics tick - smoothing below
	# hides the gap.
	_transform_sync.replication_interval = TRANSFORM_REPLICATION_SECONDS


## hides everything that only makes sense from inside this body (camera,
## viewmodel, hit marker) and shows what only makes sense from outside (body
## mesh).
func _apply_remote_appearance() -> void:
	# released without handing the view to another camera.
	if _camera.current:
		_camera.clear_current(false)
	_set_weapon_visible(false)
	if _hit_marker != null:
		_hit_marker.visible = false
	if _body_mesh != null:
		_body_mesh.visible = true
	_apply_team_colour()
	_refresh_third_person_weapon()
	_refresh_model()

	# physics is skipped entirely for remote bodies in _physics_process - it
	# just stays a solid collider on the player layer.


## tints the body mesh by team, so you can tell allies from enemies at a glance.
func _apply_team_colour() -> void:
	if _model != null:
		_refresh_model()
	if _body_mesh == null:
		return
	var colour: Color = TEAM_COLOURS.get(state.team, TEAM_COLOURS[Team.Side.NONE])
	var material := _body_mesh.get_active_material(0)
	if material is StandardMaterial3D:
		# written in place - the material is resource_local_to_scene in the
		# scene file, so each instance already has its own copy.
		(material as StandardMaterial3D).albedo_color = colour


## one colour per side. alpha is low so you can see through a body you're
## standing in.
const TEAM_COLOURS := {
	Team.Side.NONE: Color(0.7, 0.7, 0.7, 0.18),
	Team.Side.ALPHA: Color(0.25, 0.65, 1.0, 0.22),
	Team.Side.BRAVO: Color(1.0, 0.35, 0.25, 0.22),
}


## equips the starting weapon and wires up its signals.
func _equip_weapon() -> void:
	if weapon == null:
		return

	# WeaponData is shared by reference and never mutated, so players sharing
	# a gun type can't affect each other's spread.
	loadout.refill()

	weapon.fired.connect(_on_weapon_fired)
	weapon.recoil_requested.connect(_on_recoil_requested)
	weapon.hit_confirmed.connect(_on_hit_confirmed)
	weapon.reload_started.connect(_on_reload_started)
	weapon.reload_finished.connect(_on_reload_finished)
	weapon.dry_fired.connect(_on_dry_fired)

	weapon_changed.emit(weapon)

	# don't come back from a mid-reload death with a silently refilled mag.
	if not state.is_alive:
		_set_weapon_visible(false)


## shows/hides the weapon in hand. on death it drops out of frame instead of
## vanishing instantly.
func _set_weapon_visible(visible_now: bool) -> void:
	if _weapon_mount == null:
		return
	_weapon_mount.visible = visible_now
	# reset recoil too, or the next equip comes back jammed half-recoiled.
	_viewmodel_kick = 0.0
	_weapon_mount.position = _viewmodel_rest
	_weapon_mount.rotation = Vector3.ZERO


## places the viewmodel: rest position + aim offset + recovering recoil kick.
## purely cosmetic.
func _update_viewmodel_kick(delta: float) -> void:
	if _weapon_mount == null or not _weapon_mount.visible:
		return

	_viewmodel_kick = maxf(_viewmodel_kick - delta * VIEWMODEL_KICK_RECOVERY, 0.0)
	_viewmodel_rear = maxf(_viewmodel_rear - delta * 7.0, 0.0)
	var distance := 0.0
	var rear_degrees := 0.0
	if weapon != null and weapon.data != null:
		distance = weapon.data.viewmodel_kick
		rear_degrees = weapon.data.viewmodel_kick_degrees
	# +z is back toward the camera (the kick). smaller while aimed - steadier
	# hold is part of what aiming buys.
	var steady := aim.recoil_scale()
	var kick := _viewmodel_kick * distance * steady
	# muzzle rears up and settles on an eased curve: sharp, then slow.
	var rear := deg_to_rad(rear_degrees) * _viewmodel_rear * _viewmodel_rear * steady
	_weapon_mount.position = _viewmodel_rest + aim.viewmodel_offset() + Vector3(0.0, rear * 0.03, kick) \
		+ view_feel.weapon_offset()
	_weapon_mount.rotation = view_feel.weapon_rotation() + Vector3(rear, 0.0, -rear * 0.25)


## applies aim to things outside the weapon's own numbers: camera zoom, fire interval.
func _apply_aim() -> void:
	_camera.fov = GameConfig.field_of_view * view_feel.fov_scale() / aim.zoom()
	if weapon != null:
		weapon.fire_interval_scale = aim.fire_interval_scale()
		weapon.set_model_hidden(aim.is_scoped())


## looking through a magnified scope right now, for the hud.
func is_scoped() -> bool:
	return not is_network_remote and aim.is_scoped()


## how far into ads, 0 to 1, for the hud.
func get_aim_amount() -> float:
	return aim.amount


# --- Weapon signal handlers ---------------------------------------------
# one-liners: the weapon emits, the player decides what it means.

func _on_weapon_fired() -> void:
	# ray starts at the camera, not the muzzle, so the crosshair tells the truth.
	var origin := get_eye_position()
	# spread is applied here on the shooter's machine, so the host validates
	# the exact ray the crosshair produced.
	var direction := weapon.apply_spread(get_look_direction(), aim.spread_scale() * get_movement_inaccuracy())
	direction = weapon.apply_spray(direction, aim.recoil_scale())
	shot_fired.emit(origin, direction)

	# offline, this machine is the authority and just runs the raycast.
	# online, the host decides what got hit - the shooter still gets instant
	# muzzle/ammo feedback locally, just not the final say.
	if NetworkManager.is_online:
		request_shot_from_network(origin, direction, weapon.melee_heavy)
		return

	weapon.hitscan(origin, direction)
	_report_shooting_to_echo_fields()


## asks the host to resolve this shot - the client-to-host combat interface.
## public because triggers, replays, and anything firing on someone's behalf
## should all go through here rather than a local shortcut.
func request_shot_from_network(origin: Vector3, direction: Vector3, heavy: bool = false) -> void:
	# godot refuses an rpc addressed to yourself, so the host calls the
	# validating function directly, naming itself as sender - same rules as a client.
	if multiplayer.is_server():
		_resolve_shot(multiplayer.get_unique_id(), origin, direction, heavy)
		return
	resolve_incoming_shot.rpc_id(NetworkManager.SERVER_PEER_ID, origin, direction, heavy)


## network entry point for a shot: a client asking the host to resolve it. server-only.
@rpc("any_peer", "call_remote", "reliable")
func resolve_incoming_shot(origin: Vector3, direction: Vector3, heavy: bool = false) -> void:
	if not multiplayer.is_server():
		return
	_resolve_shot(multiplayer.get_remote_sender_id(), origin, direction, heavy)


## the authoritative end of a shot, on the host. heavy is a knife stab vs
## slash - only melee reads it.
func _resolve_shot(sender: int, origin: Vector3, direction: Vector3, heavy: bool = false) -> void:
	# a client may only speak for its own body, or anyone could fire as anyone else.
	if sender != peer_id:
		_rejected_shots += 1
		push_warning("[Combat] peer %d tried to fire player %d's weapon; refused." % [
			sender, peer_id])
		return

	# a dead player's queued shots don't count.
	if not state.is_alive or weapon == null or weapon.data == null:
		_rejected_shots += 1
		return

	# reject a zero-length direction before hitscan normalizes it into a NaN.
	if direction.length_squared() < 0.000001:
		_rejected_shots += 1
		return

	# rate-limit against the weapon's own fire interval, with slack for clock
	# drift between machines. this isn't a substitute for the client's own
	# check - it just stops a modified client from becoming a free damage
	# button. token bucket instead of a min-gap, so normal packet bunching
	# doesn't get punished.
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

	# origin is checked then discarded - the shot is actually cast from where
	# the host thinks the player is, so a client can only influence where they
	# aim, not where from.
	var authoritative_origin := get_eye_position()
	if authoritative_origin.distance_to(origin) > MAX_SHOT_ORIGIN_ERROR:
		_rejected_shots += 1
		return

	# the weapon's hitscan, run by the host against the host's world.
	direction = direction.normalized()
	weapon.melee_heavy = heavy
	var result := weapon.hitscan(authoritative_origin, direction)
	_report_shooting_to_echo_fields()

	var collider: Object = result.get("collider")
	var victim := Damageable.find_target(collider)
	var victim_player := victim as Player
	# a miss has no position in the result - use the end of the ray instead.
	var hit_point: Vector3 = result.get("position", weapon.get_last_shot_end())
	var hit_normal: Vector3 = result.get("normal", -direction)
	var zone := Damageable.resolve_zone(victim, hit_point, collider)
	# "hit" means damage was actually dealt - shooting a corpse or scenery
	# doesn't flash the hit marker.
	var hit := weapon.last_damage_dealt > 0.0
	var killed := hit and victim != null and victim.has_method(&"is_dead") and bool(victim.call(&"is_dead"))

	# host ran the raycast, so this is a local result already drawn.
	var surface := weapon.last_surface
	shot_resolved.emit(hit_point, hit_normal, victim_player, zone, killed, true, surface)

	# tell other machines what happened so they can draw the impact/hit
	# marker. call_remote so the host doesn't double up on its own message.
	_confirm_shot.rpc(
		hit_point,
		hit_normal,
		zone,
		victim_player.peer_id if victim_player != null else 0,
		hit,
		killed,
		peer_id,
		surface)


## applies another machine's verdict about a shot. victim_peer_id 0 means
## scenery/nobody.
## any_peer with a sender check, not authority - this node's authority is its
## owner, but the host is who decides shots, and those are different peers for
## a client's body. reliable, since a dropped verdict reads as "my gun doesn't work".
@rpc("any_peer", "call_remote", "reliable")
func _confirm_shot(point: Vector3, normal: Vector3, zone: int, victim_peer_id: int, hit: bool, killed: bool, shooter_peer_id: int, surface: int) -> void:
	# only the host's word counts, checked explicitly.
	if multiplayer.get_remote_sender_id() != NetworkManager.SERVER_PEER_ID:
		return
	var victim: Player = null
	if victim_peer_id != 0:
		victim = NetworkManager.get_player_for(victim_peer_id)

	# hit marker is the shooter's business only - flashing it for someone
	# else's hit would be a lie.
	var is_mine := shooter_peer_id == multiplayer.get_unique_id()
	if is_mine and hit and _hit_marker != null:
		_hit_marker.flash(zone, killed)
		_play_hit_feedback(zone, killed)
	# always a network result here - this machine never ran the raycast itself.
	shot_resolved.emit(point, normal, victim, zone, killed, false, surface)
	# point the damage indicator at the shooter.
	if hit and victim != null and not victim.is_network_remote and not multiplayer.is_server():
		EventBus.local_hit_from.emit(global_position)


func _on_recoil_requested(_pitch_degrees: float, _yaw_degrees: float) -> void:
	var steady := aim.recoil_scale()
	add_recoil(_pitch_degrees * steady, _yaw_degrees * steady)
	_since_recoil = 0.0
	_viewmodel_rear = 1.0
	var shake := weapon.data.camera_shake * steady if weapon != null and weapon.data != null else 0.0
	_shake = 1.0
	_shake_roll = randf_range(-1.0, 1.0) * shake
	_shake_pitch = randf_range(0.3, 1.0) * shake
	_apply_view()
	_viewmodel_kick = 1.0


func _on_hit_confirmed(killed: bool, zone: int, _health_left: int) -> void:
	# only the shooter's own machine gets feedback from this.
	if is_network_remote:
		return
	if _hit_marker != null:
		_hit_marker.flash(zone, killed)
	_play_hit_feedback(zone, killed)


## sound for a hit marker: tick for body, ding for headshot, chime for a kill.
func _play_hit_feedback(zone: int, killed: bool) -> void:
	if killed:
		Audio.play(&"kill", -2.0, 0.0)
	elif zone == Damageable.HitZone.HEAD:
		Audio.play(&"hit_head", -3.0, 0.02)
	else:
		Audio.play(&"hit_body", -6.0, 0.05)


func _on_reload_started(duration: float) -> void:
	# sounds are cued by the reload animation.
	reloading_changed.emit(true, duration)


func _on_reload_finished() -> void:
	reloading_changed.emit(false, 0.0)


func _on_dry_fired() -> void:
	if not is_network_remote:
		Audio.play(&"dry_fire", -6.0)
	# no visual yet - signal exists so there's somewhere to hook it up later.
	dry_fired.emit()


## primary + sidearm, switching and buying. see PlayerLoadout.
@onready var loadout: PlayerLoadout = $Loadout

## aiming down sights. see PlayerAim.
@onready var aim: PlayerAim = $Aim

## weapon sway, bob, sprint pose, landing - cosmetic. see PlayerViewFeel.
@onready var view_feel: PlayerViewFeel = $ViewFeel

## set by the objective while planting/defusing: movement, jumping, firing
## stop; looking around doesn't.
var objective_lock: bool = false


# --- Public API --------------------------------------------------------
# other systems talk to the player through these, not by reaching into internals.

# --- Footsteps --------------------------------------------------------------

## metres between footsteps.
const STEP_STRIDE := 2.3

## below this speed, silent. crouching or aiming while moving is quiet - the
## tactical trade of slow but stealthy.
const STEP_MIN_SPEED := 4.2

var _step_distance: float = 0.0
var _step_last_position: Vector3 = Vector3.INF
var _step_airborne_speed: float = 0.0
var _step_was_grounded: bool = true


## plays footsteps from actual movement, so it works the same for remote
## bodies driven by snapshots. own footsteps are quiet/flat; others are
## positioned so you can hear where they are.
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
		# landing thump, local only.
		if not grounded:
			_step_airborne_speed = maxf(_step_airborne_speed, -velocity.y)
		elif not _step_was_grounded and _step_airborne_speed > 4.0:
			Audio.play(&"land", -6.0)
			_step_airborne_speed = 0.0
		elif grounded:
			_step_airborne_speed = 0.0
	_step_was_grounded = grounded

	# a teleport or respawn isn't a run.
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


# --- Player model -----------------------------------------------------------------

## the rigged soldier other players see. null on the body this machine plays
## (seen from inside).
var _model: PlayerModel = null
var _model_last_position := Vector3.ZERO
var _model_velocity := Vector3.ZERO
var _model_hidden: bool = false


## builds the soldier for a remote body, or swaps it on a team change, and
## retires the placeholder capsule.
func _refresh_model() -> void:
	if not is_network_remote or not is_inside_tree():
		return
	if _model == null:
		_model = PlayerModel.new()
		_model.name = "Model"
		add_child(_model)
		_model_last_position = global_position
	_model.build(state.team)
	if _body_mesh != null:
		_body_mesh.visible = false
	if not state.is_alive:
		_model.play_death()


## hides this body's soldier - a spectator looking through its eyes shouldn't
## see the inside of the helmet.
func set_model_hidden(hidden: bool) -> void:
	if hidden == _model_hidden:
		return
	_model_hidden = hidden
	if _model != null:
		_model.visible = not hidden
	if _third_person_weapon != null:
		_third_person_weapon.visible = state.is_alive and not hidden


## feeds the soldier what the network says this body is doing.
func _update_model(delta: float) -> void:
	if _model == null or delta <= 0.0:
		return
	var raw := (global_position - _model_last_position) / delta
	_model_last_position = global_position
	_model_velocity = _model_velocity.lerp(raw, minf(1.0, delta * 12.0))
	var local := global_basis.inverse() * _model_velocity
	var airborne := absf(_model_velocity.y) > 1.2
	_model.update(delta, Vector3(local.x, 0.0, local.z), 1.0 - _stance, airborne, _head.rotation.x,
		_third_person_weapon if state.is_alive else null, walk_speed)
	_update_name_tag()


var _name_tag: Label3D = null


## floats a teammate's name over their head, visible through walls. enemies
## get none.
func _update_name_tag() -> void:
	var me := NetworkManager.get_local_player()
	var wanted := me != null and me != self and state.is_alive and not _model_hidden \
		and state.team != Team.Side.NONE and state.team == me.state.team
	if not wanted:
		if _name_tag != null:
			_name_tag.visible = false
		return
	if _name_tag == null:
		_name_tag = Label3D.new()
		_name_tag.name = "NameTag"
		_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_name_tag.no_depth_test = true
		_name_tag.fixed_size = true
		_name_tag.pixel_size = 0.0011
		_name_tag.font_size = 34
		_name_tag.outline_size = 8
		_name_tag.outline_modulate = Color(0, 0, 0, 0.85)
		_name_tag.font = UITheme.font()
		_name_tag.render_priority = 10
		_name_tag.outline_render_priority = 9
		_name_tag.position = Vector3(0.0, 1.98, 0.0)
		add_child(_name_tag)
	_name_tag.visible = true
	_name_tag.text = "%s\n\u25BC" % state.display_name.to_upper()
	_name_tag.modulate = UITheme.team_colour(state.team)


## where a remote player's shots appear to leave from: the held gun's muzzle.
func get_third_person_muzzle() -> Variant:
	if _third_person_weapon == null or not _third_person_weapon.visible:
		return null
	var muzzle := _third_person_weapon.find_child("Muzzle", true, false) as Node3D
	return muzzle.global_position if muzzle != null else null


# --- Third-person weapon ---------------------------------------------------------

## where the gun sits relative to a remote player's head - low and to the
## right, as if held at the shoulder.
const THIRD_PERSON_WEAPON_OFFSET := Vector3(0.24, -0.34, -0.12)

var _third_person_weapon: Node3D = null
var _third_person_scene: PackedScene = null


## puts the held weapon's model in a remote player's hands. the local player
## never sees their own (that's the viewmodel's job).
func _refresh_third_person_weapon() -> void:
	if not is_network_remote or not is_inside_tree():
		return
	var scene: PackedScene = weapon.data.viewmodel_scene if weapon != null and weapon.data != null else null
	if scene == _third_person_scene and _third_person_weapon != null:
		return
	_third_person_scene = scene
	if _third_person_weapon != null:
		# detach first so the replacement can reuse the same node name.
		_head.remove_child(_third_person_weapon)
		_third_person_weapon.queue_free()
		_third_person_weapon = null
	if scene == null:
		return
	_third_person_weapon = scene.instantiate() as Node3D
	_third_person_weapon.name = "ThirdPersonWeapon"
	_third_person_weapon.position = THIRD_PERSON_WEAPON_OFFSET
	_head.add_child(_third_person_weapon)
	_third_person_weapon.visible = state.is_alive


## gives the screen back to this player's own camera, e.g. after spectating.
## no-op for a body this machine doesn't drive.
func make_view_current() -> void:
	if not is_network_remote:
		_camera.make_current()


## where a spectator watching this player should put the camera: at the eyes,
## facing where they're looking.
func get_spectator_view() -> Transform3D:
	var yaw := net_yaw if is_network_remote else rotation.y
	var pitch := net_pitch if is_network_remote else _head.rotation.x
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	return Transform3D(basis, _head.global_position)


## current coarse state, derived rather than stored so it can never disagree
## with reality.
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


## human-readable name for get_movement_state, for the debug overlay.
static func state_name(movement_state: MovementState) -> String:
	return MovementState.keys()[movement_state]


## current collision height, interpolated between crouch and stand.
func get_current_height() -> float:
	return lerpf(crouch_height, stand_height, _stance)


## eye height, for anything that needs to know where this player looks from -
## a muzzle, a spawn check.
func get_eye_position() -> Vector3:
	return _head.global_position


## forward direction including pitch - where a shot should go.
func get_look_direction() -> Vector3:
	return -_camera.global_transform.basis.z


func is_sprinting() -> bool:
	return get_movement_state() == MovementState.SPRINTING


func is_crouching() -> bool:
	return get_movement_state() == MovementState.CROUCHING


# --- Health and damage --------------------------------------

## applies damage and returns how much health was actually removed, or 0 if
## nothing happened. the whole of the player's damage surface - weapons,
## turrets and replicated shots all go through this.
## zone of the most recent damaging hit, so a death can report whether it was
## a headshot.
var _last_hit_zone: int = Damageable.HitZone.BODY


func apply_damage(amount: float, _source: Node = null, _zone: Damageable.HitZone = Damageable.HitZone.BODY) -> float:
	if not state.is_alive or amount <= 0.0:
		return 0.0

	var removed := state.apply_damage(amount)
	if removed > 0.0:
		_last_hit_zone = _zone
		took_hit.emit(_source, removed, _zone)
		if not is_network_remote and _source is Node3D and is_instance_valid(_source):
			EventBus.local_hit_from.emit((_source as Node3D).global_position)
		var attacker := _source as Player
		EventBus.player_damaged.emit(peer_id,
			attacker.peer_id if attacker != null else EventBus.INVALID_PEER, removed)
		health_changed.emit(state.health, state.is_alive)
		# publish before the death check, so a lethal hit still sends the
		# final health value. no-op off the host.
		_publish_net_state()
	if not state.is_alive:
		die(_source)
	return removed


## which part of the player was hit, from where on the capsule it landed.
## collider is ignored - a player has one collider so there's nothing to
## disambiguate.
func resolve_hit_zone(point: Vector3, _collider: Object = null) -> Damageable.HitZone:
	# measured from the feet against current height, so a crouched player's
	# head band moves down with them.
	var up_the_body := (point.y - global_position.y) / maxf(get_current_height(), 0.001)
	return Damageable.HitZone.HEAD if up_the_body >= 1.0 - head_hit_fraction \
		else Damageable.HitZone.BODY


func get_health() -> int:
	return state.health


func get_max_health() -> int:
	return PlayerState.MAX_HEALTH


func is_dead() -> bool:
	return not state.is_alive


## moves a remote body smoothly toward where the network says it is - draws it
## one snapshot-interval behind so there's always something to interpolate
## toward instead of visibly stepping.
## falls back to holding the spawn point if no snapshot has arrived yet, so a
## late joiner doesn't appear at the world origin.
func _advance_remote_interpolation(delta: float) -> void:
	var now := _net_time_now()

	if _snapshot_positions.is_empty():
		# waiting for the first snapshot - hold the spawn point instead of the origin.
		if not _render_initialised:
			_render_position = global_position
			_render_rotation_y = rotation.y
			_render_initialised = true
		return

	# drop snapshots older than the interpolation window. array's tiny, so a
	# linear pass beats a ring buffer here.
	while _snapshot_times.size() >= 2 \
			and now - _snapshot_times[0] > TRANSFORM_REPLICATION_SECONDS * REMOTE_SNAPSHOT_HISTORY:
		_snapshot_times.remove_at(0)
		_snapshot_positions.remove_at(0)

	var target_position := _snapshot_positions[_snapshot_positions.size() - 1]
	var target_yaw := net_yaw

	# interpolate between the two most recent snapshots instead of just
	# chasing the newest, which would add extra lag.
	if _snapshot_times.size() >= 2:
		var previous_time := _snapshot_times[_snapshot_times.size() - 2]
		var previous_position := _snapshot_positions[_snapshot_positions.size() - 2]
		var newest_time := _snapshot_times[_snapshot_times.size() - 1]
		var span := newest_time - previous_time
		if span > 0.0001:
			var t := clampf((now - previous_time) / span, 0.0, 1.0)
			# smoothstep instead of linear, so direction changes don't look like corners.
			var eased := t * t * (3.0 - 2.0 * t)
			target_position = previous_position.lerp(target_position, eased)

	# bounded catch-up so a respawn snaps into place quickly instead of
	# gliding across the map.
	var to_target := target_position - _render_position
	var step := REMOTE_CATCHUP_SPEED * delta
	_render_position += to_target if to_target.length() <= step else to_target.normalized() * step

	_render_rotation_y = lerp_angle(_render_rotation_y, target_yaw, minf(1.0, delta * 12.0))
	global_position = _render_position
	rotation.y = _render_rotation_y
	# head follows replicated pitch too, so the muzzle/spectator view point
	# where they're actually looking.
	_head.rotation.x = lerp_angle(_head.rotation.x, net_pitch, minf(1.0, delta * 12.0))
	_render_initialised = true


## discards interpolation history and puts a remote body exactly at point.
## used for teleports, where gliding would be a lie.
func _snap_remote_to(point: Vector3) -> void:
	_snapshot_positions.clear()
	_snapshot_times.clear()
	_snapshot_positions.append(point)
	_snapshot_times.append(_net_clock)
	_render_position = point
	_render_initialised = true
	global_position = point


## seconds since this body started, used to timestamp snapshots. both sides
## use this same local clock so comparisons never depend on the sender's wall
## clock.
var _net_clock: float = 0.0


func _net_time_now() -> float:
	return _net_clock


## records an authoritative transform for a remote body to interpolate toward.
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


## copies replicated health/team/death into state when they change, and runs
## the local death presentation for a death this machine didn't cause. pushed
## by _net_state_receive rather than polled, and self-guards so a stale or
## repeated value is harmless.
func _sync_state_from_network() -> void:
	# wait for the host to actually speak before trusting any of this -
	# net_team defaults to NONE, which the host never really sends, so an
	# untold body can be told apart from one genuinely assigned no team.
	# otherwise a remote body's first frame would clobber a real team
	# assignment back to unassigned.
	if not _net_state_received:
		if net_team == Team.Side.NONE:
			return
		_net_state_received = true

	if net_team != state.team:
		state.assign_team(net_team)
		# repaint on the replicated value so a late team assignment always
		# shows correctly.
		_apply_team_colour()

	if net_health == state.health and net_alive == state.is_alive:
		# shield/scoreboard change only, but still worth telling the hud.
		health_changed.emit(state.health, state.is_alive)
		return

	state.health = net_health
	state.is_alive = net_alive

	# alive again after a death this machine drew - stand the corpse back up.
	# usually a no-op since _net_respawn_at already did it; here as a safety net.
	if net_alive and _is_dying:
		_reset_life_presentation()

	if not net_alive:
		# a death this machine didn't cause. die() isn't called here since it
		# credits the scoreboard - only the host does that. just run the
		# local presentation.
		_begin_death_presentation(null)
		return

	health_changed.emit(state.health, true)


## everything die() does that's presentation, not authority. the host runs
## this and also credits the death; a client runs only this, crediting nothing.
func _begin_death_presentation(source: Node) -> void:
	if _is_dying:
		return

	_is_dying = true
	aim.reset()
	if _third_person_weapon != null:
		_third_person_weapon.visible = false
	_death_tilt = 0.0
	_death_eye_start = _head.position.y
	_apply_view()

	velocity = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	_sprint_held = false
	_crouch_held = false

	collision_layer = CollisionLayers.CORPSE
	_set_weapon_visible(false)
	# body mesh is hidden on a living local player (you're standing inside it)
	# but shows once dead, so the death is visible to others too. a remote
	# body falls as its soldier instead; the local player's own camera just
	# drops to the floor.
	if _model != null:
		_model.play_death()
	if _body_mesh != null:
		_body_mesh.visible = false
	if weapon != null:
		weapon.cancel_reload()

	# offline-only: auto-respawn after a short delay. online, the round loop
	# owns respawns. counted down each frame rather than awaited, so a scene
	# change can't resume this on a freed player.
	if not NetworkManager.is_online:
		_offline_respawn_left = OFFLINE_RESPAWN_SECONDS


## offline-only: seconds before a corpse gets up again.
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


## host only: brings this player back to life at point on every machine. an
## rpc rather than a local call, since the owning client is authoritative for
## its own transform and would otherwise fight the next snapshot.
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
	# only the host may raise anyone - same sender-check reasoning as
	# _confirm_shot. a call_local on the host reports sender id 0.
	var sender := multiplayer.get_remote_sender_id()
	if sender != NetworkManager.SERVER_PEER_ID and not (sender == 0 and multiplayer.is_server()):
		return
	respawn()
	teleport_to(point, facing_yaw)


## puts the player back on their feet with a full mag.
func respawn() -> void:
	state.respawn()
	_reset_life_presentation()
	_publish_net_state()
	health_changed.emit(state.health, true)


## everything respawn() does that's presentation, not authority - mirror of
## _begin_death_presentation. lets a client told "alive again" stand the
## corpse up without claiming authority over its own health.
func _reset_life_presentation() -> void:
	_is_dying = false
	aim.reset()
	if _third_person_weapon != null:
		_third_person_weapon.visible = not _model_hidden
	if _model != null:
		_model.revive()
	_offline_respawn_left = 0.0
	_death_tilt = 0.0
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0

	# back on the player layer before standing up, or the corpse stays
	# intangible mid-rise.
	collision_layer = CollisionLayers.PLAYER
	collision_mask = CollisionLayers.PLAYER_BODY_MASK

	_stance = 1.0
	_apply_stance()
	_apply_view()

	# corpse mesh goes off again for a local player (standing inside it); a
	# remote body keeps it visible.
	if _body_mesh != null and not is_network_remote:
		_body_mesh.visible = false

	# weapon only reappears on the machine looking through it - remote bodies
	# never show a viewmodel.
	_set_weapon_visible(not is_network_remote)
	objective_lock = false
	if weapon != null:
		loadout.refill()


## enters the dead state: control off, movement stopped, camera falling,
## weapon lowered, body moved to the corpse layer. the body stays in the
## scene - a dead player should still be present in the world, not deleted.
## corpse layer, not player layer, so it's still solid/shootable but not a
## live target.
func die(source: Node = null) -> void:
	# guarded on _is_dying, not state.is_alive - apply_damage already sets
	# is_alive false before calling this, so guarding on that would make this
	# a no-op every time and the death sequence would never run.
	if _is_dying:
		return

	# state.is_alive may already be false from apply_damage - this is where
	# it's actually acted on.
	state.is_alive = false
	var newly_recorded := state.record_death()
	died.emit(source)

	# scoreboard credit - only the health authority reaches this, so a kill
	# is counted exactly once.
	if newly_recorded:
		var killer := source as Player
		var killer_id := EventBus.INVALID_PEER
		if killer != null and killer != self:
			# named in the kill feed either way; credited only for an enemy.
			killer_id = killer.peer_id
			if killer.state.team != state.team:
				killer.state.record_kill()
				Economy.add_credits(killer.state, GameManager.match_rules.kill_credits)
				killer._publish_net_state()
		# the bought weapon is lost with the life.
		loadout.server_on_death()
		var headshot := _last_hit_zone == Damageable.HitZone.HEAD
		EventBus.player_died.emit(peer_id, killer_id, headshot)
		if NetworkManager.is_online:
			_net_death_event.rpc(killer_id, headshot)

	_begin_death_presentation(source)

	# only the health authority writes the mirrored fields - a client doing
	# this would race everyone else's copy.
	_publish_net_state()

	health_changed.emit(state.health, false)


## host to clients: this player was killed by that one. lets every machine
## raise player_died for the kill feed; health/corpse are handled by the
## state rpc separately.
@rpc("any_peer", "call_remote", "reliable")
func _net_death_event(killer_id: int, headshot: bool) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.SERVER_PEER_ID:
		return
	EventBus.player_died.emit(peer_id, killer_id, headshot)


## copies state into the mirror fields and broadcasts them. host-only, called
## on every health change.
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


## applies the host's authoritative word on a body's health, team and death -
## the receiving half of _publish_net_state. any_peer with a sender check, not
## authority, for the same reason as elsewhere: this node's authority is its
## owner, but the host is who decides health.
@rpc("any_peer", "call_remote", "reliable")
func _net_state_receive(health_value: int, alive: bool, side: int, kills: int, deaths: int, credits: int, shield: int) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.SERVER_PEER_ID:
		return

	# scoreboard numbers and credits are the host's; a client only mirrors them.
	state.kills = kills
	state.deaths = deaths
	state.credits = credits
	state.shield = shield

	net_health = health_value
	net_alive = alive
	net_team = side
	_sync_state_from_network()


## adds recoil kick to the view. degrees, positive = camera lifts.
## the pitch cap lives here since it limits the player's view, not any one gun.
## spread multiplier from moving: 1 standing still, up to 4 at a sprint, 5 in
## the air, eased by crouching. stop to shoot straight.
func get_movement_inaccuracy() -> float:
	if weapon != null and weapon.data != null and weapon.data.is_melee:
		return 1.0
	var speed := Vector2(_move_velocity.x, _move_velocity.z).length()
	var m := 1.0 + clampf((speed - 0.6) / maxf(walk_speed, 0.1), 0.0, 1.0) * 3.0
	if not is_on_floor():
		m = 5.0
	if _stance < 0.5:
		m = 1.0 + (m - 1.0) * 0.6
	return m


## a jolt to the view - e.g. a nearby blast.
func add_shake(amount: float) -> void:
	_shake = 1.0
	_shake_roll = randf_range(-1.0, 1.0) * amount
	_shake_pitch = randf_range(0.3, 1.0) * amount


func add_recoil(pitch_degrees: float, yaw_degrees: float) -> void:
	if state.is_alive:
		_recoil_pitch = minf(_recoil_pitch + pitch_degrees, max_recoil_pitch_degrees)
		_recoil_yaw = clampf(_recoil_yaw + yaw_degrees, -max_recoil_yaw_degrees, max_recoil_yaw_degrees)


## how far the view is currently displaced by recoil, in degrees. zero when
## aim matches true aim.
func get_recoil_offset() -> Vector2:
	return Vector2(_recoil_pitch, _recoil_yaw)


## the pitch the player's actually aiming at, in radians, ignoring recoil.
func get_look_pitch() -> float:
	return _look_pitch


## turns keyboard/mouse control on or off.
func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		capture_mouse(false)


## shows/hides the mouse. while visible, looking around stops - doubles as a pause.
func capture_mouse(captured: bool) -> void:
	if not input_enabled:
		captured = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## drops the player at a point, clearing momentum, so a respawn doesn't
## inherit the death's velocity.
func teleport_to(point: Vector3, facing_yaw: float = 0.0) -> void:
	velocity = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	rotation.y = facing_yaw
	_look_pitch = 0.0
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	_apply_view()
	global_position = point
	# cleared deliberately - the floor flag still reads true for one frame
	# after teleporting, which would otherwise refill coyote time and hand a
	# free jump.
	_coyote_left = 0.0
	if is_network_remote:
		# a remote body is drawn from snapshots - reset them too, or
		# interpolation drags it straight back.
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
	if event.is_action_pressed(&"weapon_knife"):
		loadout.switch_to(PlayerLoadout.SLOT_KNIFE)
		return
	if event.is_action_pressed(&"throw_frag") and _controls_active():
		loadout.throw_grenade(PlayerLoadout.FRAG)
		return
	if event.is_action_pressed(&"throw_smoke") and _controls_active():
		loadout.throw_grenade(PlayerLoadout.SMOKE)
		return
	if event.is_action_pressed(&"inspect") and state.is_alive and weapon != null:
		weapon.inspect()
		return

	# echo field deployment
	if event.is_action_pressed(&"echo_field") and state.is_alive:
		_try_deploy_echo_field()
		get_viewport().set_input_as_handled()
		return

	# looking around needs the mouse captured - checked here so alt-tabbing
	# back doesn't spin the camera.
	# allowed while dead too: you should still get to see what killed you.
	if event is InputEventMouseMotion and is_mouse_captured():
		_look(event as InputEventMouseMotion)


func _look(motion: InputEventMouseMotion) -> void:
	var sensitivity: float = GameConfig.mouse_sensitivity * sensitivity_scale
	# an unconfigured sensitivity shouldn't make the camera unusable.
	if sensitivity <= 0.0:
		sensitivity = sensitivity_scale
	# scaled with zoom, so a mouse move covers the same screen distance aimed or not.
	sensitivity /= aim.zoom()

	view_feel.add_look(motion.relative)
	var delta := motion.relative * sensitivity

	# yaw on the body so movement follows where the player is facing.
	rotate_y(-delta.x)

	# pitch on the head, clamped every frame on the absolute angle so it can't
	# flip past the limit.
	# invert flips this frame's delta, never the accumulated angle, so
	# toggling it mirrors from wherever you're looking instead of snapping to
	# the opposite angle.
	var pitch_delta := -delta.y
	if GameConfig.invert_mouse_y:
		pitch_delta = -pitch_delta

	var limit := deg_to_rad(pitch_limit_degrees)
	_look_pitch = clampf(_look_pitch + pitch_delta, -limit, limit)
	_apply_view()


## writes the head's actual rotation from true aim + recoil + death fall. the
## head's rotation is output only - nothing else writes it - so recoil can't
## permanently redirect the view.
func _apply_view() -> void:
	var pitch := _look_pitch

	if _is_dying:
		pitch = lerpf(pitch, deg_to_rad(78.0), _death_tilt)

	# recoil adds: positive x rotation turns -z toward +y, i.e. looks up.
	var shake := _shake * _shake * 0.5
	_head.rotation.x = clampf(pitch + deg_to_rad(_recoil_pitch + _shake_pitch * shake),
		-deg_to_rad(100.0), deg_to_rad(100.0))
	_head.rotation.z = lerpf(_head.rotation.z, deg_to_rad(_recoil_yaw * 0.15 + _shake_roll * shake), 0.5)
	# horizontal kick turns the whole view, so the pattern's sway is where the
	# crosshair goes.
	_head.rotation.y = -deg_to_rad(_recoil_yaw)


## recovers recoil, advances the death fall, and drives the weapon.
func _update_combat(delta: float) -> void:
	# recoil recovery runs even while dead, so respawning doesn't leave the
	# view stuck off-aim. settles at the weapon's own rate - a rifle takes
	# longer than an smg.
	_since_recoil += delta
	var recovery := recoil_recovery_degrees
	if weapon != null and weapon.data != null:
		recovery = weapon.data.recoil_recovery_degrees
	var hold := RECOIL_RECOVERY_DELAY
	if weapon != null and weapon.data != null:
		hold = maxf(hold, weapon.data.fire_interval * 1.6)
	if _since_recoil > hold:
		# eased: fast while far off, gentle at the end.
		var speed := recovery * (0.35 + 0.65 * clampf(_recoil_pitch / 4.0, 0.0, 1.0))
		if _recoil_pitch > 0.0:
			_recoil_pitch = maxf(_recoil_pitch - speed * delta, 0.0)
		if _recoil_yaw != 0.0:
			_recoil_yaw = move_toward(_recoil_yaw, 0.0, speed * delta)
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 9.0, 0.0)

	if _is_dying and _death_tilt < 1.0:
		_death_tilt = minf(_death_tilt + delta / maxf(death_camera_fall_seconds, 0.01), 1.0)
		# camera sinks to the floor on a 0-to-1 timer rather than a lerp toward
		# a moving target - a lerp is exponential and frame-rate dependent, so
		# it never quite finishes and lands somewhere different depending on
		# fps. the body capsule stays at standing height, so the corpse is
		# still a full obstacle and can still be shot.
		_head.position.y = lerpf(_death_eye_start, death_camera_height, ease(_death_tilt, 0.7))
		_apply_view()

	if weapon == null:
		return

	# trigger's read only here, so a remote player with input off just can't fire.
	# mouse must be captured too, or clicking a menu would also fire the gun.
	# no firing while sprinting - the gun's carried, not aimed.
	var can_trigger := _controls_active() and is_mouse_captured() and not is_sprinting()
	weapon.update_trigger(
		can_trigger and Input.is_action_pressed(&"fire"),
		can_trigger and Input.is_action_just_pressed(&"fire"),
		delta)

	if can_trigger and Input.is_action_just_pressed(&"reload"):
		weapon.try_reload()
	# a blade has no sights: right mouse is its heavy stab.
	if can_trigger and weapon.data != null and weapon.data.is_melee \
			and Input.is_action_just_pressed(&"aim"):
		weapon.try_heavy()


# --- Movement ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tick_offline_respawn(delta)
	_read_input()
	aim.update(delta)
	_apply_aim()
	_update_combat(delta)
	_update_viewmodel_kick(delta)

	# a remote body isn't simulated here - it already moved on the owning
	# machine and the transform arrived over the network. running the
	# controller too would double-write global_position and make it jitter/sink.
	# the early return comes after the combat update on purpose: death
	# presentation still needs to run on a remote body since a client learns
	# about deaths via rpc, not a local apply_damage call.
	if is_network_remote:
		_net_clock += delta
		_advance_remote_interpolation(delta)
		# follow the owner's crouch, so the hitbox, head zone and the eye the
		# host fires this player's shots from all match what they are doing.
		if not _is_dying and not is_equal_approx(_stance, net_stance):
			_stance = move_toward(_stance, net_stance, stance_change_speed * delta)
			_apply_stance()
		_update_footsteps(delta)
		_update_model(delta)
		return

	# health/team/death are the host's alone. _net_state_receive runs on every
	# body on every machine except the host - including this machine's own
	# player, which is the part that's easy to miss: a client's own body isn't
	# "remote", so without that rpc it would keep believing its own
	# optimistic (wrong) health forever.

	_apply_horizontal_motion(delta)
	_apply_vertical_motion(delta)
	_update_stance(delta)

	# only step over a ledge while actually trying to move into it, or it'd
	# lift the player onto anything they're standing next to. fed from
	# _move_velocity (intent), not velocity, since a collision zeroes velocity
	# on that axis and the step test would see no motion to test against. the
	# vertical cancel matters too - resolving the frame as horizontal-only
	# stops the freshly-lifted body sinking straight back into the ledge.
	if is_on_floor() and _try_step_up(Vector3(_move_velocity.x, 0.0, _move_velocity.z) * delta):
		velocity.y = 0.0

	move_and_slide()

	_track_floor(delta)
	_write_net_transform()
	view_feel.update(delta, velocity, is_on_floor(), is_sprinting(), aim.amount)
	_update_footsteps(delta)
	_camera.position = view_feel.camera_offset()
	_camera.rotation.z = view_feel.camera_roll()


## copies this body's transform into the replicated properties. only called
## on the machine driving the body.
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


## whether this player's own input should move/fire them right now.
## input_enabled means the network owns this body's transform; being alive
## means the body responds to input at all - a remote corpse and a local
## corpse are both dead, but only one is remote.
func _controls_active() -> bool:
	return input_enabled and state.is_alive and not objective_lock


## movement input in world space, rotated into the player's heading. head
## holds all the pitch, so the body basis stays yaw-only.
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
	# crouch wins over sprint - holding both stays crouched, since the slower
	# speed shouldn't be bypassable.
	if _stance < 0.5:
		return crouch_speed
	if _sprint_held and not _sprint_blocked():
		return sprint_speed
	return walk_speed * _weapon_speed_multiplier() * aim.move_scale()


## movement penalty from whatever's in hand, read from the weapon's data. no
## weapon = no penalty.
func _weapon_speed_multiplier() -> float:
	if weapon == null or weapon.data == null:
		return 1.0
	return weapon.data.move_speed_multiplier


## whether the equipped weapon refuses to be sprinted with.
func _sprint_blocked() -> bool:
	return weapon != null and weapon.data != null and weapon.data.blocks_sprint


## steers horizontal velocity toward the target speed - one place decides
## accel/decel so they can't disagree.
func _apply_horizontal_motion(delta: float) -> void:
	# a dead body stops instantly instead of coasting to a halt, or a corpse
	# could slide out of the cover it died behind.
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

	# accelerated from _move_velocity, not the engine's velocity, so brushing a
	# wall doesn't erase momentum.
	_move_velocity = _move_velocity.move_toward(target, rate * delta)
	velocity.x = _move_velocity.x
	velocity.z = _move_velocity.z


func _apply_vertical_motion(delta: float) -> void:
	if is_on_floor():
		_coyote_left = coyote_time
		# small constant downward push instead of zero, so floor_snap_length
		# can hold the player to slopes.
		velocity.y = -2.0
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -terminal_fall_speed)

	# applies the jump, or does nothing - refusals are recorded on
	# _last_jump_was_refused rather than returned.
	_try_jump()


func _try_jump() -> void:
	_last_jump_was_refused = false
	if not _controls_active() or not Input.is_action_just_pressed(&"jump"):
		return
	# grounded or still in the coyote window, never both - no double jump from
	# one press.
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


## lifts the body over a ledge no taller than step_height. both tests sweep
## the movement distance rather than checking a point - a zero-length sweep
## would report clear no matter what's overhead. the lift only happens when
## movement is actually blocked, so flat ground and slopes (already handled
## by move_and_slide) are left alone; the raised test uses the same sweep to
## make sure the body could really fit up there.
## returns whether a step was taken.
func _try_step_up(horizontal: Vector3) -> bool:
	if horizontal.length_squared() <= 0.0:
		return false

	# nothing blocking at the current height - nothing to step over.
	if not test_move(global_transform, horizontal):
		return false

	# blocked, so it's a ledge - check whether the full capsule fits one
	# step_height up and the move is still possible from there. lift the
	# whole step_height at once rather than searching for a minimum: a
	# minimum search reads as "clear" for tiny lifts too, so the player
	# creeps up in centimetre increments instead of stepping cleanly.
	var raised := global_transform
	raised.origin.y += step_height

	# third arg is the collision output (unused, so null); margin is the fourth.
	if test_move(raised, horizontal, null, STEP_CLEARANCE):
		return false

	global_position.y += step_height
	return true


# --- Crouch ------------------------------------------------------------

## moves the body between standing/crouched, and refuses to stand if there's
## a ceiling in the way.
func _update_stance(delta: float) -> void:
	# frozen while dead - a corpse keeps the height it died at.
	if _is_dying:
		return

	if _crouch_held and _stance > 0.0:
		_stance = move_toward(_stance, 0.0, stance_change_speed * delta)
	elif not _crouch_held and _stance < 1.0:
		# only stand back up if the standing capsule actually fits - rechecked
		# every frame so walking out from under a low ceiling auto-resumes standing.
		if _can_stand():
			_stance = move_toward(_stance, 1.0, stance_change_speed * delta)

	_apply_stance()


## resizes the collider and moves the camera to match stance. the capsule is
## anchored at the origin, so a shorter capsule has to drop by half the
## height difference or the feet sink into the floor.
func _apply_stance() -> void:
	var height := get_current_height()
	var shape := _collision.shape as CapsuleShape3D
	shape.height = maxf(height, body_radius * 2.0 + 0.001)
	_collision.position.y = shape.height * 0.5

	# skipped while dead - the death fall owns camera height at that point, or
	# this would reset the fall every frame.
	if not _is_dying:
		_head.position.y = lerpf(crouch_eye_height, stand_eye_height, _stance)

	# keep the dev capsule the same size as the real collider.
	var mesh := _body_mesh.mesh as CapsuleMesh
	if mesh != null:
		mesh.height = shape.height


## whether a standing player would fit at the current position.
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

## one-line summary for the debug overlay.
func debug_line() -> String:
	return "%s  h=%4.2f  v=%5.1f m/s  y=%5.2f  HP %3d  %s" % [
		state_name(get_movement_state()),
		get_current_height(),
		Vector2(velocity.x, velocity.z).length(),
		global_position.y,
		state.health,
		weapon.debug_line() if weapon != null else "unarmed",
	]


## second debug line: aim and recoil numbers.
func debug_line_combat() -> String:
	return "aim %+6.1f deg   recoil %+5.2f / %+5.2f   dead_tilt %.2f" % [
		rad_to_deg(_look_pitch),
		_recoil_pitch,
		_recoil_yaw,
		_death_tilt,
	]


# --- Echo Field -------------------------------------------------

## deploys the echo field at the player's feet.
func _try_deploy_echo_field() -> void:
	if _echo_field == null:
		push_warning("Player: echo_field not assigned.")
		return

	if _echo_field.is_on_cooldown() or _echo_field.is_active:
		return

	# deploy slightly forward of the player's position
	var deploy_pos := global_position + -_camera.global_transform.basis.z * 1.5
	deploy_pos.y = global_position.y

	_echo_field.request_deploy(deploy_pos)


## reports shooting to nearby echo fields. called wherever a shot resolves
## authoritatively (offline in _on_weapon_fired, online on the host in
## _resolve_shot), since detection is server-side.
func _report_shooting_to_echo_fields() -> void:
	for node in get_tree().get_nodes_in_group(EchoField.GROUP):
		var field: EchoField = node as EchoField
		if field != null and field.is_active:
			var dist := global_position.distance_to(field.global_position)
			if dist <= field.detection_radius:
				field.report_activity(EchoField.ECHO_SHOOTING, global_position, state.team)
