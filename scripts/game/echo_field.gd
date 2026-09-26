class_name EchoField
extends Node3D
## The Echo Field - a tactical reconnaissance mechanic (Chapter 6).
##
## When deployed, creates a temporary field that detects and records
## relevant activity (movement, shooting, objective interaction) within
## its radius. The field then produces short-lived "echo" indicators
## showing approximate location and type of activity.
##
## Server-authoritative: all detection logic runs on the host (or locally when
## offline). One field per player, instanced as a child of the [Player] scene.
##
## [b]Two things about its placement that are easy to get wrong.[/b]
## - It is [member Node3D.top_level], so once dropped it stays where it was put
##   instead of following the player that carries it around.
## - Its multiplayer authority is inherited from the player, i.e. the owning
##   client. So the host's state broadcast cannot be an `authority` RPC - it is
##   `any_peer` with an explicit check that the host sent it, the same pattern
##   [method Player._confirm_shot] uses.
##
## [b]Not done yet (Chapter 6 work):[/b] echoes are detected and stored, but no
## UI draws them and they are not sent to the owning team's clients.

## Emitted when an echo event is recorded (for UI/haptic feedback). Server only.
signal echo_detected(event_type: int, position: Vector3, timestamp: float)

## Emitted when the field expires naturally.
signal field_expired

## Emitted when the field is deployed.
signal field_deployed(position: Vector3, owner_peer_id: int)

## Group every field joins, so shots can be reported to fields in range.
const GROUP := &"echo_fields"

## Activity type constants
const ECHO_MOVEMENT = 0
const ECHO_SHOOTING = 1
const ECHO_OBJECTIVE = 2
const ECHO_ABILITY = 3

## How long the field stays active, in seconds.
@export_range(2.0, 30.0) var duration: float = 8.0

## Detection radius, in metres.
@export_range(3.0, 20.0) var detection_radius: float = 10.0

## Cooldown between deployments, in seconds.
@export_range(5.0, 60.0) var cooldown: float = 25.0

## How long each echo marker remains visible, in seconds.
@export_range(0.5, 5.0) var echo_lifetime: float = 2.0

## Team that owns this field (for filtering).
var owning_team: int = Team.Side.NONE

## Peer ID of the player who deployed this field.
var owner_peer_id: int = 0

## Whether the field is currently active.
var is_active: bool = false

## Remaining time on the field.
var time_remaining: float = 0.0

## Cooldown timer.
var _cooldown_remaining: float = 0.0

## Detected echo events waiting to be displayed.
var _pending_echoes: Array[Dictionary] = []

## Visual representation.
var _field_mesh: MeshInstance3D = null
var _detection_area: Area3D = null
var _pulse_phase: float = 0.0


func _ready() -> void:
	name = "EchoField"
	# Detached from the carrying player's transform; see the class notes.
	top_level = true
	add_to_group(GROUP)
	_build_field()


func _build_field() -> void:
	# Visual field boundary
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "FieldMesh"

	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = detection_radius
	cylinder_mesh.bottom_radius = detection_radius
	cylinder_mesh.height = 0.2
	mesh_instance.mesh = cylinder_mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8, 1.0, 0.3)
	# Alpha blending and emission have to be switched on explicitly; the pulse
	# below animates both and did nothing while they were off.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(0.2, 0.8, 1.0)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 1
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(0.0, 0.1, 0.0)
	add_child(mesh_instance)
	_field_mesh = mesh_instance

	# Detection area
	_detection_area = Area3D.new()
	_detection_area.name = "DetectionArea"
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = CollisionLayers.PLAYER
	_detection_area.monitoring = false
	_detection_area.monitorable = false

	var area_collision := CollisionShape3D.new()
	var area_shape := CylinderShape3D.new()
	area_shape.radius = detection_radius
	area_shape.height = 3.0
	area_collision.shape = area_shape
	area_collision.position = Vector3(0.0, 1.5, 0.0)
	_detection_area.add_child(area_collision)
	add_child(_detection_area)

	_field_mesh.visible = false

	_detection_area.body_entered.connect(_on_body_entered)

	_pulse_phase = 0.0


func _process(delta: float) -> void:
	if not is_active:
		if _cooldown_remaining > 0.0:
			_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
		return

	time_remaining = maxf(time_remaining - delta, 0.0)

	# Pulse animation
	_pulse_phase += delta * 3.0
	if _field_mesh != null:
		var pulse := sin(_pulse_phase) * 0.2 + 0.8
		var mat := _field_mesh.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(0.2, 0.8, 1.0, pulse * 0.3)
			mat.emission_energy_multiplier = pulse * 2.0

	# Fade out stored echoes
	var i := _pending_echoes.size() - 1
	while i >= 0:
		_pending_echoes[i]["lifetime"] = float(_pending_echoes[i]["lifetime"]) - delta
		if float(_pending_echoes[i]["lifetime"]) <= 0.0:
			_pending_echoes.remove_at(i)
		i -= 1

	# Expiry is decided by the authority, which tells everyone else.
	if time_remaining <= 0.0 and _is_authority():
		_deactivate()


# --- Deployment -----------------------------------------------------------

## Asks to deploy the field at [param position]. Called by the owning player on
## its own machine; routes to whoever is authoritative.
##
## The host (and offline play) validates immediately. A client sends the request
## to the host - previously it called the handler directly, which on a client
## returned at the server check and on the host looked up "remote sender 0",
## so the field could never be deployed online by anyone.
func request_deploy(position: Vector3) -> void:
	if _is_authority():
		_server_deploy(_owner_peer(), position)
		return
	_rpc_request_deploy.rpc_id(NetworkManager.SERVER_PEER_ID, position)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_deploy(position: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_server_deploy(multiplayer.get_remote_sender_id(), position)


## Validation and activation. Authority only.
func _server_deploy(sender: int, position: Vector3) -> void:
	var player := get_parent() as Player
	if player == null or not player.state.is_alive:
		return

	# A peer may only deploy their own field.
	if NetworkManager.is_online and sender != player.peer_id:
		push_warning("EchoField: peer %d tried to deploy player %d's field; refused." % [
			sender, player.peer_id])
		return

	if _cooldown_remaining > 0.0 or is_active:
		return

	# Must land on the floor, and not somewhere far from the player.
	if position.distance_to(player.global_position) > 4.0:
		return
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		position + Vector3(0, 2, 0), position - Vector3(0, 5, 0), CollisionLayers.WORLD)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return

	_activate(result.position, player.peer_id, player.state.team)


func _activate(position: Vector3, peer_id: int, team: int) -> void:
	_apply_active(true, position, peer_id, team, duration)
	field_deployed.emit(position, peer_id)
	if NetworkManager.is_online:
		_sync_field_state.rpc(true, position, peer_id, team, duration)


## Deactivates the field early or on expiration. Authority only.
func _deactivate() -> void:
	if not is_active:
		return
	_apply_active(false, global_position, 0, Team.Side.NONE, 0.0)
	field_expired.emit()
	if NetworkManager.is_online:
		_sync_field_state.rpc(false, global_position, 0, Team.Side.NONE, 0.0)


## Host to everyone. `any_peer` + sender check; see the class notes.
@rpc("any_peer", "call_remote", "reliable")
func _sync_field_state(active: bool, position: Vector3, peer_id: int, team: int, dur: float) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.SERVER_PEER_ID:
		return
	_apply_active(active, position, peer_id, team, dur)
	if not active:
		field_expired.emit()


func _apply_active(active: bool, position: Vector3, peer_id: int, team: int, dur: float) -> void:
	var was_active := is_active
	is_active = active
	if active:
		global_position = position
		if not was_active:
			Audio.play_at(&"echo_deploy", position, 0.0, 0.03, 45.0)
		owner_peer_id = peer_id
		owning_team = team
		time_remaining = dur
		_cooldown_remaining = cooldown
		_pending_echoes.clear()
	else:
		time_remaining = 0.0
	_field_mesh.visible = active
	# Detection only runs where it is decided.
	_detection_area.set_deferred(&"monitoring", active and _is_authority())


# --- Detection -------------------------------------------------------------

## Detects players entering the field.
func _on_body_entered(body: Node3D) -> void:
	if not is_active or not _is_authority():
		return

	var player := body as Player
	if player == null or not player.state.is_alive:
		return

	# Don't detect own team's activity
	if player.state.team == owning_team:
		return

	_record_echo(ECHO_MOVEMENT, player.global_position, player.state.team)


## Public method for external systems to report activity (e.g., shooting, a
## future objective). Authority only; ignored elsewhere.
func report_activity(activity_type: int, position: Vector3, source_team: int) -> void:
	if not is_active or not _is_authority():
		return
	if source_team == owning_team:
		return
	_record_echo(activity_type, position, source_team)


func _record_echo(activity_type: int, position: Vector3, source_team: int) -> void:
	var echo := {
		"type": activity_type,
		"position": position,
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"lifetime": echo_lifetime,
		"player_team": source_team,
	}
	_pending_echoes.append(echo)
	echo_detected.emit(activity_type, position, echo["timestamp"])


# --- Queries ---------------------------------------------------------------

## Returns all currently visible echoes for UI rendering.
func get_active_echoes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for echo in _pending_echoes:
		if float(echo["lifetime"]) > 0.0:
			result.append(echo.duplicate())
	return result


## Returns whether this field is on cooldown.
func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0.0


## Returns cooldown progress (0.0 to 1.0).
func get_cooldown_progress() -> float:
	if cooldown <= 0.0:
		return 1.0
	return 1.0 - (_cooldown_remaining / cooldown)


func _is_authority() -> bool:
	return not NetworkManager.is_online or multiplayer.is_server()


func _owner_peer() -> int:
	var player := get_parent() as Player
	return player.peer_id if player != null else NetworkManager.SERVER_PEER_ID
