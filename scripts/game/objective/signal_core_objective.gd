class_name SignalCoreObjective
extends Node3D
## The Signal Core: the attackers' objective.
##
## Each round one attacker starts carrying the core. The carrier plants it by
## holding [code]interact[/code] (E) while standing on a site; a defender stops
## it by holding [code]interact[/code] beside the planted core. If the carrier
## dies the core drops where they fell, and any attacker who walks over it picks
## it up. The round clock and the win conditions live in
## [code]round_active_state.gd[/code]; this node only reports what happened
## through [EventBus] (core_planted / core_defused / core_detonated).
##
## [b]Authority.[/b] The host decides everything: who carries, whether a plant
## or defuse is valid, and progress. Each client only reports whether its
## player is holding the key, and draws the host's snapshot. Planting and
## defusing are interrupted by letting go, moving out of range, or dying, and
## start again from zero.
##
## Lives in the match scene as the node [code]Objective[/code]; the HUD finds
## it through the group [constant GROUP].

const GROUP := &"objective"

enum CoreState {
	INACTIVE,   ## No core this round (e.g. nobody on the attacking side).
	CARRIED,
	DROPPED,
	PLANTED,
	DEFUSED,
	DETONATED,
}

## How close an attacker must walk to a dropped core to pick it up.
const PICKUP_RADIUS := 1.6

## How close a defender must be to the planted core to defuse it.
const DEFUSE_RADIUS := 2.2

## Progress snapshots per second while someone is planting or defusing.
const PROGRESS_SEND_RATE := 10.0

# --- Replicated state (host truth, mirrored on clients) ----------------------

var core_state: int = CoreState.INACTIVE
var carrier_peer: int = 0
var core_position: Vector3 = Vector3.ZERO
var planted_site: String = ""
var plant_progress: float = 0.0
var defuse_progress: float = 0.0
## Peer currently planting / defusing, or 0.
var planter_peer: int = 0
var defuser_peer: int = 0

# --- Host-only ----------------------------------------------------------------

## peer id -> whether that player is holding the interact key.
var _holding: Dictionary = {}
var _send_left: float = 0.0

# --- Local ----------------------------------------------------------------------

var _local_holding_sent: bool = false
var _visual: Node3D
var _visual_light: OmniLight3D
var _visual_label: Label3D
var _pulse: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	_build_visual()
	GameManager.state_changed.connect(_on_phase_changed)
	EventBus.core_detonated.connect(_on_core_detonated_request)
	# Sounds, on every machine, where the core is.
	EventBus.core_planted.connect(func(_id: int, _site: String) -> void:
		Audio.play_at(&"core_planted", core_position, 2.0, 0.0, 70.0)
		_beep_left = 0.4)
	EventBus.core_defused.connect(func(_id: int) -> void:
		Audio.play_at(&"core_defused", core_position, 2.0, 0.0, 70.0))
	EventBus.core_detonated.connect(func() -> void:
		Audio.play_at(&"core_detonate", core_position, 8.0, 0.0, 200.0)
		Audio.play(&"core_detonate", -8.0, 0.0))
	NetworkManager.roster_updated.connect(_on_roster_updated)


# --- Queries (HUD) ---------------------------------------------------------------

func is_planted() -> bool:
	return core_state == CoreState.PLANTED


## Whether [param player] could start planting right now (on a site, carrying).
func can_plant(player: Player) -> bool:
	return player != null and player.state.is_alive \
		and core_state == CoreState.CARRIED and carrier_peer == player.peer_id \
		and GameManager.is_in(GamePhase.Phase.ROUND_ACTIVE) \
		and site_at(player.global_position) != ""


## Whether [param player] could start defusing right now.
func can_defuse(player: Player) -> bool:
	return player != null and player.state.is_alive \
		and core_state == CoreState.PLANTED \
		and player.state.team == GameManager.match_state.defending_side() \
		and player.global_position.distance_to(core_position) <= DEFUSE_RADIUS \
		and GameManager.is_in(GamePhase.Phase.ROUND_ACTIVE)


## The name of the site containing [param point] ("A", "B"), or "".
func site_at(point: Vector3) -> String:
	for node in get_tree().get_nodes_in_group(BlockMap.SITE_GROUP):
		var area := node as Area3D
		if area == null:
			continue
		var shape := area.get_child(0) as CollisionShape3D
		var box := shape.shape as BoxShape3D if shape != null else null
		if box == null:
			continue
		var local := area.global_transform.affine_inverse() * point
		var half := box.size * 0.5
		if absf(local.x) <= half.x and absf(local.z) <= half.z and local.y >= -half.y - 0.5 and local.y <= half.y:
			return String(area.get_meta(&"site_name", "?"))
	return ""


# --- Per-frame ----------------------------------------------------------------

## Idle-frame rather than physics-frame, on purpose: the round and detonation
## clocks tick in [GameManager]'s idle frame on real time, and plant / defuse
## progress must run on the same clock. On a loaded host the physics step falls
## behind real time (Godot caps catch-up steps per frame), and a defuse measured
## in physics time then loses a race against a detonation measured in real time
## that it should have won.
func _process(delta: float) -> void:
	_send_local_input()
	if _is_authority():
		_server_tick(delta)
	_update_local_lock()
	_update_visual(delta)


## Tells the host whether this machine's player is holding the key. Only sends
## on change; the host remembers.
func _send_local_input() -> void:
	var local := NetworkManager.get_local_player()
	var holding := local != null and local.input_enabled \
		and Input.is_action_pressed(&"interact") \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if holding == _local_holding_sent:
		return
	_local_holding_sent = holding
	if local == null:
		return
	if _is_authority():
		_holding[local.peer_id] = holding
	else:
		_rpc_set_holding.rpc_id(NetworkManager.SERVER_PEER_ID, holding)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_holding(holding: bool) -> void:
	if not multiplayer.is_server():
		return
	_holding[multiplayer.get_remote_sender_id()] = holding


## Freezes the local player while their plant or defuse is in progress, or
## while they are holding the key somewhere a plant or defuse is possible - so
## the stop is instant rather than waiting for the host.
func _update_local_lock() -> void:
	var local := NetworkManager.get_local_player()
	if local == null:
		return
	var busy := _local_holding_sent and (can_plant(local) or can_defuse(local) \
		or planter_peer == local.peer_id or defuser_peer == local.peer_id)
	local.objective_lock = busy


func _server_tick(delta: float) -> void:
	var changed := false
	match core_state:
		CoreState.CARRIED:
			var carrier := NetworkManager.get_player_for(carrier_peer)
			if carrier == null or not carrier.state.is_alive or carrier.is_queued_for_deletion():
				_drop(carrier.global_position if carrier != null else core_position)
				return
			core_position = carrier.global_position
			changed = _tick_plant(carrier, delta)
		CoreState.DROPPED:
			for player in NetworkManager.get_players():
				if player.state.is_alive and player.state.team == GameManager.match_state.attacking_side() \
						and player.global_position.distance_to(core_position) <= PICKUP_RADIUS:
					carrier_peer = player.peer_id
					core_state = CoreState.CARRIED
					_broadcast()
					return
		CoreState.PLANTED:
			changed = _tick_defuse(delta)

	if changed:
		_send_left -= delta
		if _send_left <= 0.0:
			_send_left = 1.0 / PROGRESS_SEND_RATE
			_broadcast()


func _tick_plant(carrier: Player, delta: float) -> bool:
	if bool(_holding.get(carrier.peer_id, false)) and can_plant(carrier):
		planter_peer = carrier.peer_id
		plant_progress += delta / maxf(GameManager.match_rules.plant_seconds, 0.1)
		_report_to_echo_fields(carrier)
		if plant_progress >= 1.0:
			_plant(carrier)
		return true
	if planter_peer != 0 or plant_progress > 0.0:
		planter_peer = 0
		plant_progress = 0.0
		_broadcast()
	return false


func _tick_defuse(delta: float) -> bool:
	var defuser := NetworkManager.get_player_for(defuser_peer) if defuser_peer != 0 else null
	if defuser == null or not bool(_holding.get(defuser_peer, false)) or not can_defuse(defuser):
		defuser = null
		for player in NetworkManager.get_players():
			if bool(_holding.get(player.peer_id, false)) and can_defuse(player):
				defuser = player
				break
		if defuser == null or defuser.peer_id != defuser_peer:
			if defuser_peer != 0 or defuse_progress > 0.0:
				defuser_peer = 0
				defuse_progress = 0.0
				_broadcast()
			if defuser == null:
				return false
	defuser_peer = defuser.peer_id
	defuse_progress += delta / maxf(GameManager.match_rules.defuse_seconds, 0.1)
	_report_to_echo_fields(defuser)
	if defuse_progress >= 1.0:
		core_state = CoreState.DEFUSED
		defuse_progress = 1.0
		defuser_peer = 0
		_broadcast()
		EventBus.core_defused.emit(defuser.peer_id)
	return true


func _plant(carrier: Player) -> void:
	core_state = CoreState.PLANTED
	planted_site = site_at(carrier.global_position)
	core_position = _floor_below(carrier.global_position)
	carrier_peer = 0
	planter_peer = 0
	plant_progress = 1.0
	Economy.add_credits(carrier.state, GameManager.match_rules.plant_credits)
	carrier._publish_net_state()
	_broadcast()
	EventBus.core_planted.emit(carrier.peer_id, planted_site)


func _drop(at: Vector3) -> void:
	core_state = CoreState.DROPPED
	core_position = _floor_below(at)
	carrier_peer = 0
	planter_peer = 0
	plant_progress = 0.0
	_broadcast()


## Host only, at the start of every round: hand the core to an attacker.
func _server_reset_for_round() -> void:
	_holding.clear()
	planted_site = ""
	plant_progress = 0.0
	defuse_progress = 0.0
	planter_peer = 0
	defuser_peer = 0
	var attackers: Array[Player] = []
	for player in NetworkManager.get_players():
		if player.state.team == GameManager.match_state.attacking_side():
			attackers.append(player)
	if attackers.is_empty():
		core_state = CoreState.INACTIVE
		carrier_peer = 0
	else:
		var carrier: Player = attackers[randi() % attackers.size()]
		core_state = CoreState.CARRIED
		carrier_peer = carrier.peer_id
		core_position = carrier.global_position
	_broadcast()


func _on_phase_changed(_previous: int, current: int) -> void:
	if not _is_authority():
		return
	if current == GamePhase.Phase.BUY:
		_server_reset_for_round()
	elif current in [GamePhase.Phase.LOBBY, GamePhase.Phase.MATCH_END, GamePhase.Phase.WARMUP]:
		core_state = CoreState.INACTIVE
		carrier_peer = 0
		planter_peer = 0
		defuser_peer = 0
		_broadcast()


## Raised by the round when the planted core's clock runs out.
func _on_core_detonated_request() -> void:
	if _is_authority() and core_state == CoreState.PLANTED:
		core_state = CoreState.DETONATED
		_broadcast()


func _on_roster_updated() -> void:
	# A late joiner needs the current state.
	if NetworkManager.is_online and NetworkManager.is_host:
		_broadcast()


func _floor_below(point: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point + Vector3.DOWN * 4.0,
		CollisionLayers.WORLD)
	var hit := space.intersect_ray(query)
	return hit.position if not hit.is_empty() else point


func _report_to_echo_fields(player: Player) -> void:
	for node in get_tree().get_nodes_in_group(EchoField.GROUP):
		var field := node as EchoField
		if field != null and field.is_active \
				and field.global_position.distance_to(player.global_position) <= field.detection_radius:
			field.report_activity(EchoField.ECHO_OBJECTIVE, player.global_position, player.state.team)


# --- Replication ------------------------------------------------------------------

func _broadcast() -> void:
	if NetworkManager.is_online and NetworkManager.is_host:
		_net_snapshot.rpc(core_state, carrier_peer, core_position, planted_site,
			plant_progress, defuse_progress, planter_peer, defuser_peer)


@rpc("authority", "call_remote", "reliable")
func _net_snapshot(p_state: int, p_carrier: int, p_position: Vector3, p_site: String,
		p_plant: float, p_defuse: float, p_planter: int, p_defuser: int) -> void:
	if multiplayer.is_server():
		return
	var previous := core_state
	core_state = p_state
	carrier_peer = p_carrier
	core_position = p_position
	planted_site = p_site
	plant_progress = p_plant
	defuse_progress = p_defuse
	planter_peer = p_planter
	defuser_peer = p_defuser
	# Clients raise the same events the host raised, so the HUD and the round
	# state react identically everywhere.
	if previous != core_state:
		match core_state:
			CoreState.PLANTED:
				EventBus.core_planted.emit(0, planted_site)
			CoreState.DEFUSED:
				EventBus.core_defused.emit(0)
			CoreState.DETONATED:
				EventBus.core_detonated.emit()


func _is_authority() -> bool:
	return not NetworkManager.is_online or multiplayer.is_server()


# --- Visual ---------------------------------------------------------------------

## The core itself: a glowing double pyramid with a light and a floating label,
## drawn whenever it is lying on the ground or planted. Placeholder art until
## the art pass.
func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "CoreVisual"
	_visual.top_level = true
	add_child(_visual)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.75, 0.25)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.6, 0.15)
	material.emission_energy_multiplier = 2.5
	for flip in [1.0, -1.0]:
		var half := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.22
		cone.height = 0.3
		cone.radial_segments = 6
		half.mesh = cone
		half.material_override = material
		half.position = Vector3(0, 0.35 + 0.15 * flip, 0)
		half.rotation.x = 0.0 if flip > 0.0 else PI
		_visual.add_child(half)

	_visual_light = OmniLight3D.new()
	_visual_light.light_color = Color(1.0, 0.65, 0.25)
	_visual_light.omni_range = 4.0
	_visual_light.light_energy = 1.5
	_visual_light.position = Vector3(0, 0.5, 0)
	_visual.add_child(_visual_light)

	_visual_label = Label3D.new()
	_visual_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_visual_label.no_depth_test = true
	_visual_label.fixed_size = true
	_visual_label.pixel_size = 0.0015
	_visual_label.font_size = 28
	_visual_label.outline_size = 8
	_visual_label.position = Vector3(0, 1.1, 0)
	_visual_label.modulate = Color(1.0, 0.8, 0.35)
	_visual.add_child(_visual_label)
	_visual.visible = false


## Seconds to the planted core's next beep.
var _beep_left: float = 0.0


## The planted core beeps, faster and faster as its clock runs down - the
## sound every player in the match times their retake or their hold by.
func _tick_beep(delta: float) -> void:
	if not GameManager.is_in(GamePhase.Phase.ROUND_ACTIVE) or GameManager.current_state == null:
		return
	var remaining := GameManager.current_state.get_time_remaining()
	var total := maxf(GameManager.match_rules.detonation_seconds, 1.0)
	_beep_left -= delta
	if _beep_left > 0.0:
		return
	_beep_left = lerpf(0.12, 1.0, clampf(remaining / total, 0.0, 1.0))
	Audio.play_at(&"core_beep", core_position, 0.0, 0.0, 60.0)


func _update_visual(delta: float) -> void:
	var shown := core_state in [CoreState.DROPPED, CoreState.PLANTED, CoreState.DEFUSED]
	_visual.visible = shown
	if not shown:
		return
	_visual.global_position = core_position
	if core_state == CoreState.PLANTED:
		_tick_beep(delta)
	_pulse += delta * (7.0 if core_state == CoreState.PLANTED else 2.0)
	_visual.rotation.y += delta * 1.5
	var dim := core_state == CoreState.DEFUSED
	_visual_light.light_energy = 0.2 if dim else 1.2 + 0.8 * absf(sin(_pulse))
	match core_state:
		CoreState.DROPPED:
			_visual_label.text = "SIGNAL CORE"
		CoreState.PLANTED:
			_visual_label.text = "CORE PLANTED - %s" % planted_site
		CoreState.DEFUSED:
			_visual_label.text = "DEFUSED"
