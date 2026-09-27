class_name Playtest
extends Node3D
## the screen before there's a real match: the grey box with players in it.
##
## handles both offline and online spawning from one scene so there's only
## one place a player gets created.
##
## rule to not screw up: configure_for_network runs on every machine for a
## spawned player, not just the owner. skip it and that client's body just
## silently never replicates.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## the competitive map for networked matches.
const MATCH_MAP := preload("res://scenes/maps/meridian.tscn")

## offline practice range: targets, turret, movement test stuff.
const PRACTICE_RANGE := preload("res://scenes/game/placeholder_environment.tscn")

## where spawned bodies get parented, relative to the spawner.
## has to match the actual node name in the scene file - see _configure_spawner
## for the check that keeps them in sync.
const SPAWN_PATH := NodePath("../Players")

## which marker a side spawns at. these are really attacker/defender spawns
## once the objective is in play: whoever's attacking this half uses AlphaSpawn.
## kept the old names so the practice range still works.
const ALPHA_SPAWN := "AlphaSpawn"
const BRAVO_SPAWN := "BravoSpawn"

## fallback if a marker is missing, so a renamed node degrades gracefully
## instead of crashing on null.
const FALLBACK_SPAWN := Vector3(0.0, 0.0, 20.0)

## fallback yaw so offline playtest still looks down the range.
const FALLBACK_YAW := 0.0

## how far a spawned body looks for a free spot before giving up and standing
## inside a teammate. spawn points are shared, so two players joining the same
## frame would otherwise overlap.
const SPAWN_NUDGE_STEP := 1.5
const MAX_SPAWN_NUDGES := 8

## the player this machine drives. exposed for the debug overlay/dev network
## ui. null briefly after a disconnect until a body is back.
var player: Player = null

@onready var _spawner: MultiplayerSpawner = $PlayerSpawner


func _ready() -> void:
	add_to_group(&"match_scene")
	_use_environment(MATCH_MAP if NetworkManager.is_online else PRACTICE_RANGE)
	_configure_spawner()

	# spawner is only driven by the host, but every machine needs to hear
	# "peer X registered" to know a body is coming.
	NetworkManager.peer_registered.connect(_on_peer_registered)
	NetworkManager.peer_unregistered.connect(_on_peer_unregistered)
	NetworkManager.roster_updated.connect(_on_roster_updated)
	# hosting/joining from the dev panel happens while this scene is already
	# up, so the offline body needs to be swapped out here too.
	NetworkManager.hosting_started.connect(_on_hosting_started)
	NetworkManager.join_succeeded.connect(_on_join_succeeded)
	GameManager.state_changed.connect(_on_phase_changed)

	# online, bodies come from MultiplayerSpawner on every peer - nothing gets
	# instantiated locally, not even the host's own body.
	if NetworkManager.is_online:
		if NetworkManager.is_host:
			# host is a peer like any other, already registered but not spawned.
			var side := NetworkManager.players.team_of(NetworkManager.local_peer_id)
			_on_peer_registered(NetworkManager.local_peer_id, side,
				NetworkManager.players.display_name_of(NetworkManager.local_peer_id))
		else:
			# scene (and its spawner) exists now, so ask the host to spawn us.
			NetworkManager.request_spawn.rpc_id(NetworkManager.SERVER_PEER_ID,
				NetworkManager.local_display_name(), Profile.level)
		return

	_spawn_offline_player()


## points the spawner at our factory function and wires up the result signal.
func _configure_spawner() -> void:
	if _spawner == null:
		push_warning("Playtest: no PlayerSpawner child; networked play is disabled.")
		return

	_spawner.spawn_function = _spawn_networked_player
	_spawner.spawned.connect(_on_player_spawned)

	# set in code too and checked here: a bad spawn_path just fails silently
	# deep in Godot's spawn logic otherwise, with no hint which path was wrong.
	_spawner.spawn_path = SPAWN_PATH
	if _spawner.get_node_or_null(SPAWN_PATH) == null:
		push_error("Playtest: PlayerSpawner's spawn_path '%s' does not resolve to a node. \
Networked spawning is disabled." % SPAWN_PATH)
		return

	# unlimited - the roster enforces the player cap, not the spawner.
	_spawner.spawn_limit = 0


## swaps in [param scene] as the level under the "Environment" node name.
## needs AlphaSpawn/BravoSpawn markers. no-op if already loaded.
func _use_environment(scene: PackedScene) -> void:
	var current := get_node_or_null(^"Environment")
	if current != null:
		if current.scene_file_path == scene.resource_path:
			return
		# out of the tree now so the replacement can take the name right away.
		remove_child(current)
		current.queue_free()
	var level := scene.instantiate()
	level.name = "Environment"
	add_child(level)
	move_child(level, 0)
	_step_aside_from_overview_camera()


## drops the grey box's elevated debug camera once the player camera exists,
## so the frame is never drawn with two cameras both "current".
func _step_aside_from_overview_camera() -> void:
	# removed outright, not just disabled - a disabled camera can still get
	# picked as "next current" and steal the view.
	var overview := find_child("OverviewCamera", true, false) as Camera3D
	if overview != null:
		overview.get_parent().remove_child(overview)
		overview.queue_free()


# --- Offline --------------------------------------------------------------

## single-player path: one local body, no network involved. also what every
## automated test runs through.
func _spawn_offline_player() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	player.name = "LocalPlayer"

	# offline peer id is the server's id, not local_peer_id (which is 0 with
	# no session - peer 0 isn't a player).
	player.pending_peer_id = NetworkManager.SERVER_PEER_ID
	player.pending_team = Team.Side.ALPHA
	player.pending_display_name = NetworkManager.local_display_name()
	add_child(player)

	# added before teleport so _ready has already run (collider, replication,
	# camera, mouse capture) before we move it.
	player.teleport_to(_spawn_point(Team.Side.ALPHA), FALLBACK_YAW)


# --- Networked ------------------------------------------------------------

## host only. a peer got a side; spawn their body everywhere.
func _on_peer_registered(peer_id: int, team_side: int, player_name: String) -> void:
	if not NetworkManager.is_host or _spawner == null:
		return

	# already has a body? don't spawn a second one for the same peer.
	if NetworkManager.get_player_for(peer_id) != null:
		return

	var body := _spawner.spawn({
		"peer_id": peer_id,
		"team": team_side,
		"display_name": player_name,
		"spawn": _spawn_point(team_side),
		"yaw": _spawn_yaw(team_side),
	}) as Player

	# spawned signal only fires on the receiving peers, so the host has to
	# learn about its own body here.
	if body != null and peer_id == NetworkManager.local_peer_id:
		player = body
	if body != null:
		_prepare_joiner(body)


## host only. gives a late joiner this half's starting credits. if a round is
## in progress they join dead so they can't swing an elimination - they spawn
## normally next buy phase. published after a short delay so the client has
## the body before the state arrives.
func _prepare_joiner(body: Player) -> void:
	var phase := GameManager.current_phase
	if phase in [GamePhase.Phase.LOBBY, GamePhase.Phase.WARMUP, GamePhase.Phase.MATCH_END]:
		return
	body.state.credits = GameManager.match_rules.starting_credits
	if phase in [GamePhase.Phase.ROUND_ACTIVE, GamePhase.Phase.ROUND_END]:
		body.state.health = 0
		body.state.is_alive = false
		body._begin_death_presentation(null)
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(body):
			body._publish_net_state())


## runs on every machine via the spawner, with the same data the host passed
## to spawn(). the one place a networked Player gets built.
##
## get_spawn_data is only valid in here (and the spawned signal handler) -
## write everything the node needs before it enters the tree.
##
## note: configure_for_network is NOT called here. the node has to be added
## to the tree first (by MultiplayerSpawner) before set_multiplayer_authority
## works. pending_* fields get set here; Player._ready() calls
## configure_for_network once the node is in the tree.
func _spawn_networked_player(data: Variant) -> Player:
	var spawn_data := data as Dictionary
	var body := PLAYER_SCENE.instantiate() as Player

	# name matters for RPC addressing - every machine needs to agree on it,
	# so derive it from the peer id rather than anything generated.
	var peer_id := int(spawn_data.get("peer_id", NetworkManager.SERVER_PEER_ID))
	body.name = "Player%d" % peer_id

	# identity before the tree - by the time `spawned` fires, _ready has
	# already run and claimed camera/mouse if this were the local player.
	body.pending_peer_id = peer_id
	body.pending_team = int(spawn_data.get("team", Team.Side.NONE))
	body.pending_display_name = String(spawn_data.get("display_name", ""))

	# stash spawn position/yaw as metadata so _on_player_spawned can read it
	# back later - get_spawn_data() isn't valid in the spawned signal handler.
	# set before the tree because `spawned` never fires on the host that
	# called spawn(), so the host's own bodies would otherwise sit at origin.
	# Players node sits at the origin too, so local == world here.
	var spawn_pos: Vector3 = spawn_data.get("spawn", FALLBACK_SPAWN)
	var spawn_yaw := float(spawn_data.get("yaw", FALLBACK_YAW))
	body.position = spawn_pos
	body.rotation.y = spawn_yaw
	# seeds the replicated transform too, so nothing snaps from origin before
	# the owner's first physics frame.
	body.net_position = spawn_pos
	body.net_yaw = spawn_yaw

	return body


## runs on every machine except the host, once per body, after the spawner
## adds it. body is already configured/placed - just check if it's ours.
func _on_player_spawned(body: Node) -> void:
	var networked := body as Player
	if networked == null:
		return

	# matched on the body's own identity so this agrees with everything else.
	if networked.peer_id == NetworkManager.local_peer_id \
			and not networked.is_network_remote:
		player = networked


## a peer left. despawn their body if the spawner hasn't already.
func _on_peer_unregistered(peer_id: int) -> void:
	# on a client the host's spawner normally removes the body first; freeing
	# it again here would error on an already-freed node. when the whole
	# session is gone, _on_roster_updated clears everything anyway.
	if NetworkManager.is_online and not NetworkManager.is_host:
		return
	var body := NetworkManager.get_player_for(peer_id)
	if body == null:
		return
	if body == player:
		player = null
	body.queue_free()


## host and client: lost the session, put a local body back so quitting the
## host is recoverable instead of leaving frozen remote bodies on screen.
func _on_roster_updated() -> void:
	if NetworkManager.is_online:
		# keep the pointer honest as peers come and go.
		player = NetworkManager.get_local_player()
		return

	_clear_all_players()
	_use_environment(PRACTICE_RANGE)
	_spawn_offline_player()


# --- Session changes while this scene is up --------------------------------

func _on_hosting_started(_port: int) -> void:
	_clear_all_players()
	_use_environment(MATCH_MAP)
	var side := NetworkManager.players.team_of(NetworkManager.local_peer_id)
	_on_peer_registered(NetworkManager.local_peer_id, side,
		NetworkManager.players.display_name_of(NetworkManager.local_peer_id))


func _on_join_succeeded() -> void:
	# offline body has no place in someone else's session. safe to call even
	# if _ready already asked - host ignores duplicate spawn requests.
	_clear_all_players()
	_use_environment(MATCH_MAP)
	NetworkManager.request_spawn.rpc_id(NetworkManager.SERVER_PEER_ID,
				NetworkManager.local_display_name(), Profile.level)


# --- Rounds ---------------------------------------------------------------

## every round starts with everyone alive, full hp, at their side's spawn.
## authority only. a rematch (MATCH_END -> LOBBY) resets the scoreboard too.
func _on_phase_changed(previous: int, current: int) -> void:
	if not GameManager.is_authority():
		return
	if current == GamePhase.Phase.BUY:
		# first round of each half: sides may have swapped, reset credits/streaks.
		if GameManager.match_state.is_first_round_of_half():
			GameManager.match_state.reset_loss_streaks()
			Economy.reset_for_half()
		_respawn_all_players()
	elif current == GamePhase.Phase.LOBBY and previous == GamePhase.Phase.MATCH_END:
		for body in NetworkManager.get_players():
			body.state.reset_score()
		_respawn_all_players()


func _respawn_all_players() -> void:
	# spots handed out by index rather than the join-time nudge, since at
	# round start everyone's still wherever the last round left them.
	var index_by_side := {}
	for body in NetworkManager.get_players():
		var side := body.state.team
		var index: int = index_by_side.get(side, 0)
		index_by_side[side] = index + 1
		body.server_respawn_at(_round_spawn_point(side, index), _spawn_yaw(side))


## the index'th spot for a side: marker, then alternating left/right in
## SPAWN_NUDGE_STEP increments.
func _round_spawn_point(side: int, index: int) -> Vector3:
	var offset := ceili(index / 2.0) * SPAWN_NUDGE_STEP * (1.0 if index % 2 == 1 else -1.0)
	return _marker_position(side) + Vector3(offset, 0.0, 0.0)


# --- Spawn points ---------------------------------------------------------

## where a side appears, nudged clear of anyone already standing there.
func _spawn_point(side: int) -> Vector3:
	var base := _marker_position(side)
	for attempt in MAX_SPAWN_NUDGES:
		if not _occupied(base):
			return base
		base += Vector3(0.0, 0.0, SPAWN_NUDGE_STEP)
	return base


## which way a side faces on spawn. read from the marker itself so a map can
## fix a wrong-facing spawn by moving the marker, not editing this file.
func _spawn_yaw(side: int) -> float:
	var marker := get_node_or_null("Environment/%s" % _marker_name(side)) as Marker3D
	if marker == null:
		return FALLBACK_YAW
	var yaw := marker.global_rotation.y
	return yaw if not is_zero_approx(yaw) else FALLBACK_YAW


func _marker_position(side: int) -> Vector3:
	var marker := get_node_or_null("Environment/%s" % _marker_name(side)) as Marker3D
	if marker == null:
		push_warning("Playtest: no '%s' marker under Environment." % _marker_name(side))
		return FALLBACK_SPAWN
	return marker.global_position


func _marker_name(side: int) -> String:
	return ALPHA_SPAWN if side == GameManager.match_state.attacking_side() else BRAVO_SPAWN


## is anything standing on this spot? flat 2d check on purpose - full 3d
## would treat a slightly-nudged body as a different spot and spread
## everyone along the back wall instead of clustering at spawn.
func _occupied(point: Vector3) -> bool:
	for body in NetworkManager.get_players():
		var flat_a := Vector2(body.global_position.x, body.global_position.z)
		var flat_b := Vector2(point.x, point.z)
		if flat_a.distance_to(flat_b) < SPAWN_NUDGE_STEP:
			return true
	return false


func _clear_all_players() -> void:
	for body in NetworkManager.get_players():
		# remove from the group now - queue_free leaves it until end of frame,
		# and a same-frame spawn would see a ghost standing on its spot.
		body.remove_from_group(&"players")
		body.queue_free()
	player = null
