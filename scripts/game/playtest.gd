class_name Playtest
extends Node3D
## The screen shown while there is no real match to get into: the grey box with
## the players in it.
##
## [b]This is a development harness, not a final level and not a final match.[/b]
## Chapter 7 replaces the environment and Chapter 8 replaces the presentation.
## Everything that actually has to survive both - the [Player] scene, the
## [NetworkManager] autoload, the weapon and its damage contract - lives outside
## this file and is untouched by either.
##
## ## Why it handles both offline and online
##
## There are two ways to arrive at this scene, and they end in the same place:
##
## - [b]Offline.[/b] Nobody pressed Host or Join. One local player is
##   instantiated directly, on the spot, with no network involved. This is what
##   the single-player playtest has always been, and Chapter 3's whole test
##   suite runs through it.
## - [b]Online.[/b] Somebody pressed Host or Join. The [MultiplayerSpawner] owns
##   every body from then on, on every machine, and this node's only job is to
##   decide [b]where[/b] a body appears and ask the host to spawn it.
##
## Keeping both in one scene rather than adding a separate "network match" scene
## means there is one place where a player is created, so there is one place to
## be wrong. A second scene would be a second spawner, a second camera handoff,
## and a second copy of the rule that a body is configured on every machine and
## not just the one that owns it.
##
## ## The rule that is easy to get wrong
##
## A spawned player's [method Player.configure_for_network] is called on
## [b]every[/b] machine, with the same arguments, not only on the one that owns
## it. That is what makes the authority flags agree across the session. A
## client that skipped configuration would have a body whose synchronisers
## pointed at nobody, and the failure would be "replication silently does
## nothing" rather than anything that points at the cause.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## The competitive map every networked match is played on.
const MATCH_MAP := preload("res://scenes/maps/meridian.tscn")

## The offline practice range: targets, a turret and the movement test pieces.
## Offline play is for practice, so it gets the range rather than an empty map.
const PRACTICE_RANGE := preload("res://scenes/game/placeholder_environment.tscn")

## Where spawned bodies are parented, relative to the spawner.
##
## A named constant rather than a literal in the scene file, because the path
## has to agree with the node that actually exists and the scene file is not
## somewhere a reader would think to look for that. See
## [method _configure_spawner] for the check that keeps the two in step.
const SPAWN_PATH := NodePath("../Players")

## Which marker a side spawns at. Two sides, two markers, authored by the
## environment in Chapter 1 precisely so this file would not have to change when
## networking arrived.
##
## Since the objective arrived these are really the [b]attacker[/b] and
## [b]defender[/b] spawns: whichever side is attacking this half spawns at
## AlphaSpawn. The names are kept so the practice range keeps working.
const ALPHA_SPAWN := "AlphaSpawn"
const BRAVO_SPAWN := "BravoSpawn"

## Used only if a marker is missing, so a renamed node in the environment
## degrades into a slightly odd spawn rather than a null reference crash in the
## middle of [method _ready].
const FALLBACK_SPAWN := Vector3(0.0, 0.0, 20.0)

## Fallback yaw when no marker can supply a facing. Chosen so an offline
## playtest still looks down the range rather than at a wall - the Chapter 2
## default, kept so the offline view has not changed under anyone.
const FALLBACK_YAW := 0.0

## How far a spawned body looks for a free spot before giving up and standing
## inside a teammate.
##
## Spawn points are shared, not per-peer, so two players connecting in the same
## frame would otherwise land in exactly the same capsule. Nudging forward in
## small steps is enough to separate them for a development lobby and is far
## less machinery than a real spawn-occupancy protocol, which is Chapter 5's
## problem once there is a round to spawn into.
const SPAWN_NUDGE_STEP := 1.5
const MAX_SPAWN_NUDGES := 8

## The player this machine drives, exposed so the debug overlay and the dev
## network UI can read it without searching the tree. Null briefly after a
## disconnect, until either an offline body is put back or a new one arrives.
var player: Player = null

@onready var _spawner: MultiplayerSpawner = $PlayerSpawner


func _ready() -> void:
	add_to_group(&"match_scene")
	_use_environment(MATCH_MAP if NetworkManager.is_online else PRACTICE_RANGE)
	_configure_spawner()

	# The spawner is only asked to do anything by the host, but the signal
	# connection is made on every machine, because a client that never hears
	# "peer X registered" has no way to know a body is coming.
	NetworkManager.peer_registered.connect(_on_peer_registered)
	NetworkManager.peer_unregistered.connect(_on_peer_unregistered)
	NetworkManager.roster_updated.connect(_on_roster_updated)
	# Hosting or joining from the dev network panel happens while this scene is
	# already up, so the offline body has to make way for a networked one here
	# rather than only in _ready.
	NetworkManager.hosting_started.connect(_on_hosting_started)
	NetworkManager.join_succeeded.connect(_on_join_succeeded)
	GameManager.state_changed.connect(_on_phase_changed)

	# A body is spawned by the host through MultiplayerSpawner, which
	# instantiates it on every peer. Nothing is instantiated here directly when
	# the session is online - not even the host's own, because a body the host
	# made for itself alone would exist on one machine and not the other five.
	if NetworkManager.is_online:
		if NetworkManager.is_host:
			# The host is a peer like any other and joined before any client
			# could, so its own body is registered but not yet spawned.
			var side := NetworkManager.players.team_of(NetworkManager.local_peer_id)
			_on_peer_registered(NetworkManager.local_peer_id, side,
				NetworkManager.players.display_name_of(NetworkManager.local_peer_id))
		else:
			# This scene - and therefore the spawner that a spawned body would
			# arrive through - exists now, so the host may send one. Asking
			# here rather than having the host guess is what stops the spawn
			# message arriving before there is anywhere to put it.
			NetworkManager.request_spawn.rpc_id(NetworkManager.SERVER_PEER_ID,
				NetworkManager.local_display_name(), Profile.level)
		return

	_spawn_offline_player()


## Points the spawner at this script's factory and subscribes to the result.
##
## [code]spawn_function[/code] is assigned in code rather than in the scene file
## because it is a reference to a method on [b]this[/b] instance, and a scene
## cannot hold a callable to a sibling node without either an autoload or an
## awkward exported resource. The spawner is a plain child, so "this instance"
## is the only thing that can build the bodies and it is right here.
##
## The [signal MultiplayerSpawner.spawned] connection is what makes
## configuration happen on every machine. Without it a body would be added and
## left in its default single-player state - peer 1, no team, camera current -
## which is a body that thinks it is the host's player and tries to replicate
## authority it was never given.
func _configure_spawner() -> void:
	if _spawner == null:
		push_warning("Playtest: no PlayerSpawner child; networked play is disabled.")
		return

	_spawner.spawn_function = _spawn_networked_player
	_spawner.spawned.connect(_on_player_spawned)

	# Set in code as well as in the scene file, and checked.
	#
	# `spawn_path` is relative to the spawner, and a relative NodePath that
	# points at a node that is not there produces exactly one error -
	# "Cannot find spawn node" - from inside Godot's C++, once per spawn, with
	# no mention of the path that was wrong. Asserting it here turns a
	# replication mystery that shows up ten seconds later into a sentence that
	# says which path failed and where it was looked for.
	_spawner.spawn_path = SPAWN_PATH
	if _spawner.get_node_or_null(SPAWN_PATH) == null:
		push_error("Playtest: PlayerSpawner's spawn_path '%s' does not resolve to a node. \
Networked spawning is disabled." % SPAWN_PATH)
		return

	# Unlimited, because the roster - not the spawner - is what enforces the
	# six-player cap, and the roster is the thing that knows a side is full.
	# A spawner limit would be a second, independent answer to "is there room",
	# and two answers that disagree produce either a rejected spawn with no
	# explanation or a seventh player in a 3v3.
	_spawner.spawn_limit = 0


## Makes [param scene] the level under the node name [code]Environment[/code],
## replacing whatever was there. Spawn markers are looked up under that name, so
## any map works as long as it provides [code]AlphaSpawn[/code] and
## [code]BravoSpawn[/code]. A no-op when that level is already loaded.
func _use_environment(scene: PackedScene) -> void:
	var current := get_node_or_null(^"Environment")
	if current != null:
		if current.scene_file_path == scene.resource_path:
			return
		# Out of the tree now, so the replacement can take the name at once.
		remove_child(current)
		current.queue_free()
	var level := scene.instantiate()
	level.name = "Environment"
	add_child(level)
	move_child(level, 0)
	_step_aside_from_overview_camera()


## The grey box keeps the elevated camera it needed in Chapter 1, to prove the
## scene rendered at all. Godot would hand the screen to the player anyway on
## its own, but doing it here in the right order means the frame is never drawn
## with two cameras both claiming to be current.
func _step_aside_from_overview_camera() -> void:
	# Removed outright rather than just switched off. A disabled camera is still
	# a candidate whenever Godot looks for "the next camera" after another one
	# stops being current, and that is how the host's view used to end up
	# above the map when a player joined. The match always has a player camera,
	# so the overview camera has no job here.
	var overview := find_child("OverviewCamera", true, false) as Camera3D
	if overview != null:
		overview.get_parent().remove_child(overview)
		overview.queue_free()


# --- Offline --------------------------------------------------------------

## The Chapter 2 and Chapter 3 path, unchanged in behaviour: one local body,
## built here, driven here, no network in the loop at all.
##
## It is also the path every automated test takes, which is why it has to keep
## working with no session. If a change to the networked path ever breaks the
## single-player case, the test suite notices immediately.
func _spawn_offline_player() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	player.name = "LocalPlayer"

	# Identity before the tree, by the same route a spawned body takes. The
	# offline peer id is the server's rather than
	# [member NetworkManager.local_peer_id], which is 0 with no session: peer 0
	# is not a player, and a body that believes it is peer 0 is a body whose
	# synchronisers point at nobody.
	player.pending_peer_id = NetworkManager.SERVER_PEER_ID
	player.pending_team = Team.Side.ALPHA
	player.pending_display_name = NetworkManager.local_display_name()
	add_child(player)

	# Added before the teleport so the player's own _ready has run - it is what
	# applies the standing collider, configures replication, picks up the camera
	# and captures the mouse - before it is moved into place.
	player.teleport_to(_spawn_point(Team.Side.ALPHA), FALLBACK_YAW)


# --- Networked ------------------------------------------------------------

## Host only. A peer has been given a side; spawn their body everywhere.
##
## Called for the host's own peer as well as for every client, because the
## host is in the roster from the moment it starts hosting and ENet never raises
## a connection event for the server about itself.
func _on_peer_registered(peer_id: int, team_side: int, player_name: String) -> void:
	if not NetworkManager.is_host or _spawner == null:
		return

	# A re-registration for a peer that already has a body would leave two
	# bodies fighting over one identity. The roster is the authority on who
	# exists, so if it says the peer is registered and a body is present,
	# something has asked twice and the second request is the one to ignore.
	if NetworkManager.get_player_for(peer_id) != null:
		return

	var body := _spawner.spawn({
		"peer_id": peer_id,
		"team": team_side,
		"display_name": player_name,
		"spawn": _spawn_point(team_side),
		"yaw": _spawn_yaw(team_side),
	}) as Player

	# [signal MultiplayerSpawner.spawned] only fires on the receiving peers, so
	# the host learns about its own body here instead.
	if body != null and peer_id == NetworkManager.local_peer_id:
		player = body
	if body != null:
		_prepare_joiner(body)


## Host only. A player arriving in a match that is already going: give them
## this half's starting credits, and if a round is in progress, bring them in
## dead - joining mid-round must not be able to swing an elimination. They
## spawn normally at the next buy phase. Published after a short delay so the
## client has the body before the state arrives.
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


## Runs on [b]every[/b] machine, by the spawner, with the same data the host
## passed to [method MultiplayerSpawner.spawn].
##
## This is the single place a networked [Player] is constructed, and it is why
## there is no second player scene and no second spawn path.
##
## [method MultiplayerSpawner.get_spawn_data] is valid in here and nowhere else
## except the [signal MultiplayerSpawner.spawned] handler - the spawner is
## mid-flight and has nothing to hand out otherwise. Everything that has to be
## known before the node enters the tree is written here, for that reason and no
## other.
##
## CRITICAL: We do NOT call configure_for_network here. The node must be added
## to the scene tree first (by the MultiplayerSpawner) before we can call
## set_multiplayer_authority on it. The pending_* fields are set here, and
## Player._ready() will call configure_for_network after the node enters the tree.
func _spawn_networked_player(data: Variant) -> Player:
	var spawn_data := data as Dictionary
	var body := PLAYER_SCENE.instantiate() as Player

	# The name is cosmetic on a single player and load-bearing on a network:
	# RPCs are addressed by node path, so every machine has to agree on it or a
	# client's `resolve_incoming_shot` call arrives at a node that does not
	# exist. Deriving it from the peer id rather than from a generated name is
	# what makes it deterministic.
	var peer_id := int(spawn_data.get("peer_id", NetworkManager.SERVER_PEER_ID))
	body.name = "Player%d" % peer_id

	# Identity, before the tree. See [member Player.pending_peer_id] for why
	# this cannot wait for the `spawned` signal: by then `_ready` has run, and
	# a remote body that spent its first frames thinking it was local has
	# already claimed the camera and taken the mouse.
	body.pending_peer_id = peer_id
	body.pending_team = int(spawn_data.get("team", Team.Side.NONE))
	body.pending_display_name = String(spawn_data.get("display_name", ""))

	# Store spawn position and yaw as metadata so _on_player_spawned can read
	# them back after the node enters the tree. MultiplayerSpawner.get_spawn_data()
	# is only valid during the spawn function, not in the spawned signal handler.
	# The transform is placed here, before the tree, and not in the `spawned`
	# handler: that signal only fires on the peers receiving the spawn, never on
	# the host that called spawn(), so every body the host created stayed at
	# the world origin on the host - including the host's own player. The parent
	# ([code]Players[/code]) sits at the origin, so local equals world here.
	var spawn_pos: Vector3 = spawn_data.get("spawn", FALLBACK_SPAWN)
	var spawn_yaw := float(spawn_data.get("yaw", FALLBACK_YAW))
	body.position = spawn_pos
	body.rotation.y = spawn_yaw
	# Seeds the replicated transform too, so any value the synchroniser sends
	# before the owner's first physics frame is the spawn point, not the origin.
	body.net_position = spawn_pos
	body.net_yaw = spawn_yaw

	return body


## Runs on every machine [b]except the host[/b], once per body, after the
## spawner has added it ([signal MultiplayerSpawner.spawned] is not raised on
## the peer that called spawn()).
##
## The body is already configured and placed by now - [method
## _spawn_networked_player] wrote its identity and transform before the tree.
## What is left is noticing whether it is the one this machine drives.
func _on_player_spawned(body: Node) -> void:
	var networked := body as Player
	if networked == null:
		return

	# Matched on the body's own identity rather than on the spawn data, so this
	# reads the same answer the rest of the node does. A body that disagrees with
	# its own peer id is exactly the kind of mismatch that makes a client look
	# like it is driving somebody else.
	if networked.peer_id == NetworkManager.local_peer_id \
			and not networked.is_network_remote:
		player = networked


## A peer is gone. Despawn the body if the spawner has not already.
##
## The spawner will normally have removed it before this arrives, in which case
## there is nothing to do and [method NetworkManager.get_player_for] correctly
## answers null. The fallback is for the case where the disconnect reached us
## first: freeing by hand then is correct, and freeing an already-freed node
## cannot happen because the lookup is what found it.
func _on_peer_unregistered(peer_id: int) -> void:
	# On a client in a live session the host's spawner removes the body, and a
	# body freed here first makes that despawn message arrive for a node that
	# no longer exists ("recv_nodes.has(net_id)" error). When the session itself
	# is gone, [method _on_roster_updated] clears every body anyway.
	if NetworkManager.is_online and not NetworkManager.is_host:
		return
	var body := NetworkManager.get_player_for(peer_id)
	if body == null:
		return
	if body == player:
		player = null
	body.queue_free()


## Host and client alike: if we have lost the session, put a local body back.
##
## This is what makes quitting the host recoverable. A client that had three
## teammates and a live mouse is left with three remote bodies that will never
## move again and no way to make them go away; putting one local body back and
## clearing the roster is the whole of "recover", and it is better than a menu.
func _on_roster_updated() -> void:
	if NetworkManager.is_online:
		# Keep the pointer honest as peers come and go.
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
	# The offline body has no place in somebody else's session. The host
	# ignores a second request for a peer that already has a body, so this is
	# safe even when the scene's own _ready has already asked.
	_clear_all_players()
	_use_environment(MATCH_MAP)
	NetworkManager.request_spawn.rpc_id(NetworkManager.SERVER_PEER_ID,
				NetworkManager.local_display_name(), Profile.level)


# --- Rounds ---------------------------------------------------------------

## Every round starts with everyone alive, full, and at their side's spawn.
## Done by the authority only; on a session that goes through
## [method Player.server_respawn_at], which the owning machines carry out.
##
## A rematch (MATCH_END -> LOBBY) is a fresh match: everyone is stood back up
## and the scoreboard is cleared.
func _on_phase_changed(previous: int, current: int) -> void:
	if not GameManager.is_authority():
		return
	if current == GamePhase.Phase.BUY:
		# The first round of each half: sides have (possibly) swapped, so
		# everyone starts over with the starting credits and a pistol.
		if GameManager.match_state.is_first_round_of_half():
			GameManager.match_state.reset_loss_streaks()
			Economy.reset_for_half()
		_respawn_all_players()
	elif current == GamePhase.Phase.LOBBY and previous == GamePhase.Phase.MATCH_END:
		for body in NetworkManager.get_players():
			body.state.reset_score()
		_respawn_all_players()


func _respawn_all_players() -> void:
	# Spots are handed out per side by index, rather than with the join-time
	# occupancy nudge, because at the start of a round everyone is still
	# standing wherever the last round left them.
	var index_by_side := {}
	for body in NetworkManager.get_players():
		var side := body.state.team
		var index: int = index_by_side.get(side, 0)
		index_by_side[side] = index + 1
		body.server_respawn_at(_round_spawn_point(side, index), _spawn_yaw(side))


## The [param index]th spot for a side: the marker, then alternately to its
## right and left in [constant SPAWN_NUDGE_STEP] steps.
func _round_spawn_point(side: int, index: int) -> Vector3:
	var offset := ceili(index / 2.0) * SPAWN_NUDGE_STEP * (1.0 if index % 2 == 1 else -1.0)
	return _marker_position(side) + Vector3(offset, 0.0, 0.0)


# --- Spawn points ---------------------------------------------------------

## Where a side appears, nudged clear of anybody already standing there.
func _spawn_point(side: int) -> Vector3:
	var base := _marker_position(side)
	for attempt in MAX_SPAWN_NUDGES:
		if not _occupied(base):
			return base
		base += Vector3(0.0, 0.0, SPAWN_NUDGE_STEP)
	return base


## Which way a side faces when it appears.
##
## Derived from the marker itself rather than a constant, so a map that puts
## Bravo's spawn facing the wrong way is fixed by moving a marker instead of by
## editing this file. Falls back to the offline default when the marker is
## missing.
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


## Is anything standing on this spot?
##
## A cheap 2D test on purpose. Comparing full positions would mean a body that
## has been nudged a centimetre by a collision solver counts as a different
## spot, and six players would end up strung out along the back wall instead of
## clustered at the spawn.
func _occupied(point: Vector3) -> bool:
	for body in NetworkManager.get_players():
		var flat_a := Vector2(body.global_position.x, body.global_position.z)
		var flat_b := Vector2(point.x, point.z)
		if flat_a.distance_to(flat_b) < SPAWN_NUDGE_STEP:
			return true
	return false


func _clear_all_players() -> void:
	for body in NetworkManager.get_players():
		# Out of the group immediately: queue_free leaves the node - and its
		# membership of "players" - in place until the end of the frame, and a
		# spawn in that same frame would then see a ghost standing on its spot.
		body.remove_from_group(&"players")
		body.queue_free()
	player = null
