extends Node
## Owns the multiplayer peer and all connection state. Registered as the
## [code]NetworkManager[/code] autoload.
##
## Everything netcode-related goes through here, and nothing else in the game
## touches [ENetMultiplayerPeer] directly. Two reasons: the rest of the game
## can then ask simple questions ("am I the host?", "who is connected?")
## without caring about ENet, and there is exactly one place to look when
## connections misbehave.
##
## ## Authority
##
## Chapter 4 put the authority rules here, in one place, because scattering
## them across the player and the match scene is how two peers end up both
## thinking they own a body:
##
## - **A client owns its own movement.** Its [Player] runs the full Chapter 2
##   physics locally and replicates its transform. The host does not simulate
##   remote players and does not need to - it receives their snapshots and
##   applies them.
## - **The host owns health, team, death and respawns.** They cross the wire as
##   host-sent RPCs with a sender check ([method Player._net_state_receive],
##   [method Player._net_respawn_at]), so no amount of client enthusiasm can
##   write them.
## - **The host owns the match flow.** [GameManager] replicates the phase, score
##   and countdown to clients; a client never advances a phase itself.
## - **The host resolves every shot.** A client sends an aim ray; the host
##   re-derives the ray from its own copy of the world and decides what was hit.
##   The client is told what happened so it can draw it.
##
## The one asymmetry worth naming: the host's own player is both authoritative
## for its transform [b]and[/b] a remote body to nobody, so it takes the same
## validating path by calling it directly - Godot refuses an RPC addressed to
## the local peer.

# --- Signals ------------------------------------------------------------

## This machine started a server.
signal hosting_started(port: int)

## We are now connected to a server as a client.
signal join_succeeded

## Joining failed. [param reason] is safe to show in the UI.
signal join_failed(reason: String)

## A peer connected. [param peer_id] is 0 for the host itself on a client.
signal peer_connected(peer_id: int)

## A peer disconnected.
signal peer_disconnected(peer_id: int)

## We lost the server we were connected to.
signal server_disconnected

## The roster changed: somebody joined, left, or changed health. The dev UI
## listens to this rather than polling.
signal roster_updated

## Host only. A peer has been given a side and should now be spawned.
## [param player_name] is what the scoreboard will show.
signal peer_registered(peer_id: int, team_side: int, player_name: String)

## Host only. A peer is gone and their body should be removed from every
## machine. Raised before the node is freed so listeners can still look it up.
signal peer_unregistered(peer_id: int)

## A client has finished loading its match scene and is ready to be given a
## body. Host only, and raised by [method request_spawn].
signal spawn_requested(peer_id: int)

# --- Session configuration ----------------------------------------------

## Default port for a local or LAN match.
const DEFAULT_PORT := 27015

## Loopback, for testing two instances on one machine.
const DEFAULT_ADDRESS := "127.0.0.1"

## Hard ceiling on a session, whatever the rules ask for. A mistyped
## [code]match_rules.tres[/code] should not be able to open a server for a
## thousand players. This is a transport safety limit, not a game rule - the
## actual cap comes from [method get_max_players].
const ABSOLUTE_MAX_PLAYERS := 16

## Godot's first peer id is always the server. It is not a magic number in the
## way a hard-coded port is: this is the identity ENet itself hands the host,
## and every "the host is authoritative" check in the project reads it from
## here rather than repeating the literal.
const SERVER_PEER_ID := 1

var _peer: ENetMultiplayerPeer = null
var _is_online: bool = false
var _is_host: bool = false

## Who is in the session. Owned, not an autoload - this object dies with the
## manager, which is correct, because the roster is a property of the session
## and not of the application.
var players := PlayerRegistry.new()


func _ready() -> void:
	# Connection teardown must still run if the tree is paused mid-round.
	process_mode = Node.PROCESS_MODE_ALWAYS

	players.capacity = get_max_players()

	# Connected once, here, rather than on every join: `multiplayer` outlives
	# any individual peer, so these fire correctly across reconnects.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# One place that pushes the roster out, rather than a broadcast call at each
	# of the five places that can change it. A missed call site here is the kind
	# of bug that only shows up under a specific sequence - a client whose team
	# never arrives, with no error anywhere - and the cost of avoiding it is
	# one connection.
	roster_updated.connect(_on_roster_changed)


# --- State --------------------------------------------------------------

## Whether we are connected to a session at all.
var is_online: bool:
	get: return _is_online

## Whether this machine is the server. Clients must never run authoritative
## game logic, so this gates most decisions in Chapters 4 and 5.
var is_host: bool:
	get: return _is_host

## Our own network id, or 0 when offline.
var local_peer_id: int:
	get: return _peer.get_unique_id() if _peer != null else 0

## Peers the transport reports, [b]excluding[/b] this machine.
##
## Godot's [method MultiplayerAPI.get_peers] never includes the local peer, so
## on the host this is "every client" and on a client it is "the host and every
## other client". Kept as a raw transport query, deliberately: it answers a
## transport question. For "how many players are in the match", use
## [method get_player_count], which does include this machine and does not
## change shape depending on whether you are the one hosting.
func get_connected_peers() -> PackedInt32Array:
	if not _is_online:
		return PackedInt32Array()
	return multiplayer.get_peers()


## Session size implied by the match rules: two teams of
## [member MatchRules.players_per_team]. "3v3" is therefore stated once, in
## [code]data/match_rules.tres[/code], rather than as a 6 here and a 3 there.
## Clamped so a bad rules file cannot produce an absurd session.
func get_max_players() -> int:
	return clampi(GameManager.match_rules.get_team_size(), 2, ABSOLUTE_MAX_PLAYERS)


## Total players in the match, [b]including[/b] this machine.
##
## Read from the roster rather than from the transport, for two reasons that
## both bite in a real session. The transport does not count the host, so a
## one-player session reads as zero. And the roster is the thing the team
## assignment and the six-player cap are actually enforced against, so a count
## taken from anywhere else could disagree with whether a new peer was accepted.
func get_player_count() -> int:
	return players.size()


## Whether the session has room for another player.
func has_open_slot() -> bool:
	return players.has_open_slot()


# --- Roster ---------------------------------------------------------------

## Adds a peer to the roster and assigns them a side. Host-only.
##
## Returns the assigned [enum Team.Side], or [constant Team.Side.NONE] if the
## session is full. The capacity refusal itself is
## [method PlayerRegistry.register]'s - this is the host check, the log line,
## and the roster notification around it.
func register_peer(peer_id: int, player_name: String = "") -> int:
	if not _is_host:
		push_warning("NetworkManager: only the host may assign peers. Ignoring register_peer(%d)." % peer_id)
		return Team.Side.NONE

	var side := players.register(peer_id, player_name)
	if side == Team.Side.NONE:
		return side

	print("[Network] peer %d joined as %s (%s), %s" % [
		peer_id, players.display_name_of(peer_id), Team.side_name(side),
		players.count_line()])
	roster_updated.emit()
	return side


## Removes a peer from the roster. Host-only, except that a client calling it
## for itself is allowed - that is the "I am leaving" path, and it only ever
## removes local state.
func unregister_peer(peer_id: int) -> void:
	if not _is_host and peer_id != local_peer_id:
		return
	if players.unregister(peer_id):
		roster_updated.emit()


## The [Player] node for a peer, or null if it is not spawned here.
##
## Looked up through the scene tree rather than kept in a parallel dictionary,
## because a node reference that outlives the node is a crash waiting for a
## disconnect, and the tree already knows the answer correctly at all times.
func get_player_for(peer_id: int) -> Player:
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.peer_id == peer_id:
			return player
	return null


## Every [Player] in this scene, for iteration that does not care who owns what.
func get_players() -> Array[Player]:
	var found: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null:
			found.append(player)
	return found


## The one player this machine drives, or null when we are a spectator with no
## body of our own.
##
## Also the offline answer. With no session there is no peer id to match on -
## [member local_peer_id] is 0 - but there is still exactly one player, and
## every piece of tooling that wants "the player I am looking through" wants it
## in single-player too. Scoping this to sessions would have meant the debug
## overlay, the harness and the UI each reimplementing the offline case.
func get_local_player() -> Player:
	if not _is_online:
		return _only_player()
	return get_player_for(local_peer_id)


## The single body in the scene, if there is exactly one. Null when there are
## none, and null when there are several, because "pick one of these" is a guess
## and a guess that happens to be wrong is worse than an honest null.
func _only_player() -> Player:
	var found: Player = null
	for node in get_tree().get_nodes_in_group(&"players"):
		var candidate := node as Player
		if candidate == null:
			continue
		if found != null:
			return null
		found = candidate
	return found


# --- Session control ----------------------------------------------------

## Starts a server and waits for players to connect.
## [param max_players] of 0 means "use the session size from the match rules".
## Returns [constant OK] on success, or an [enum Error] to pass to
## [method @GlobalScope.error_string].
func host_game(port: int = DEFAULT_PORT, max_players: int = 0) -> Error:
	leave_game()

	var cap := mini(max_players if max_players > 0 else get_max_players(), ABSOLUTE_MAX_PLAYERS)

	# ENet's second argument counts *clients*, not participants: the host is not
	# in it, because the host is the thing being connected to. Passing the
	# session size straight through therefore allows one more player than the
	# rules allow, and the excess is caught by the registry refusing to
	# register - which works, but leaves a peer connected to a visibly full
	# session with no way to tell them why. One less here means ENet turns the
	# seventh player away at the handshake, which is the only place that can be
	# turned away cleanly.
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, cap - 1)
	if error != OK:
		push_error("NetworkManager: could not host on port %d (%s)" % [port, error_string(error)])
		return error

	multiplayer.multiplayer_peer = peer
	_peer = peer
	_is_online = true
	_is_host = true
	players.capacity = cap
	players.clear()

	# The host is a peer like any other and has to be in the roster, or it would
	# be the one participant with no body and no side. Registering it here
	# rather than waiting for a connection event is deliberate: ENet never
	# raises `peer_connected` for the server about itself.
	register_peer(SERVER_PEER_ID, local_display_name())
	players.update(SERVER_PEER_ID, {"level": Profile.level})

	print("[Network] Hosting on port %d for up to %d players" % [port, cap])
	hosting_started.emit(port)
	return OK


## Connects to a server. Use [signal join_succeeded] or [signal join_failed]
## to find out how it went - this returns before the attempt completes.
func join_game(address: String = DEFAULT_ADDRESS, port: int = DEFAULT_PORT) -> Error:
	leave_game()

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		var reason := "Could not reach %s:%d (%s)" % [address, port, error_string(error)]
		push_error("NetworkManager: " + reason)
		join_failed.emit(reason)
		return error

	multiplayer.multiplayer_peer = peer
	_peer = peer
	_is_online = true
	_is_host = false

	print("[Network] Joining %s:%d" % [address, port])
	return OK


## Disconnects and returns to a fully offline state. Safe to call when
## already offline, and safe to call mid-round.
func leave_game() -> void:
	# Every peer has to be told their body is going away before the peer is
	# closed, or a client is left holding bodies it can no longer reconcile.
	# Doing this on the way out as well as on the way in is what makes a host
	# quit - the single most common thing to happen in a dev session - leave
	# every client in a clean, playable, offline state instead of a frozen one.
	for peer_id in players.peer_ids():
		peer_unregistered.emit(peer_id)
	players.clear()

	if _peer == null:
		_is_online = false
		_is_host = false
		roster_updated.emit()
		return

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer.close()
	_peer = null
	_is_online = false
	_is_host = false
	roster_updated.emit()
	print("[Network] Left the session")


# --- Peer callbacks -----------------------------------------------------

func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)

	if not _is_host:
		return

	if not players.has_open_slot():
		push_warning("NetworkManager: peer %d connected to a full session and was not registered" % id)
		roster_updated.emit()
		return

	# Register immediately so the roster is authoritative, but defer the
	# spawn until the client confirms its match scene is ready via
	# [method request_spawn]. The host's own peer (id 1) has no client to
	# handshake with, so we register and notify immediately.
	var side := register_peer(id)
	if id == SERVER_PEER_ID:
		peer_registered.emit(id, side, players.display_name_of(id))


## Client to host: "my match scene is up, please give me a body."
##
## [b]This handshake exists because there is otherwise a race, and the race
## loses a player.[/b] The host learns a peer exists from ENet's handshake and
## could spawn its body immediately - but a spawned body is a
## [MultiplayerSpawner] message, and a client that has not yet added its own
## spawner has nowhere to put it. The message is dropped, the client believes it
## is in a match, and the roster says six players while the client can see one.
## Nothing errors; the session is just quietly short a person.
##
## So the client says when it is ready instead, and the host spawns then. The
## host's own player needs no handshake: it is spawned by its own match scene
## the moment that scene exists, which is the same condition.
@rpc("any_peer", "call_remote", "reliable")
func request_spawn(player_name: String = "", player_level: int = 1) -> void:
	if not multiplayer.is_server():
		return

	# Only a peer the host has already registered may ask. Without this, a
	# client that connected to a full session and was refused could still ask
	# for a body, and the host would spawn one for a peer that is in nobody's
	# roster - a player with no side, no cap count and no way to be cleaned up.
	var sender := multiplayer.get_remote_sender_id()
	if not players.has_peer(sender):
		push_warning("NetworkManager: spawn requested by unregistered peer %d; refused." % sender)
		return

	# The client's chosen name, cleaned. Arrives here rather than at connect
	# time because ENet's handshake carries no payload.
	var clean := sanitize_name(player_name)
	var changes := {"level": clampi(player_level, 1, 999)}
	if not clean.is_empty():
		changes["display_name"] = clean
	players.update(sender, changes)
	roster_updated.emit()

	# Phase first, so the client is in the host's phase - with the host's score
	# and countdown - before its body arrives.
	GameManager.send_snapshot_to(sender)
	peer_registered.emit(sender, players.team_of(sender), players.display_name_of(sender))
	spawn_requested.emit(sender)


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)
	# On any machine, not just the host's: a client also needs to stop
	# believing a body for this peer exists, because the spawner despawn arrives
	# as a separate message and there is a frame where both are half-true.
	peer_unregistered.emit(id)
	if _is_host:
		players.unregister(id)
		roster_updated.emit()


func _on_connected_to_server() -> void:
	join_succeeded.emit()


func _on_connection_failed() -> void:
	# ENet leaves the peer half-open on failure, so clean up here rather than
	# leaving is_online true with nothing behind it.
	var reason := "The host did not respond."
	push_warning("NetworkManager: " + reason)
	leave_game()
	join_failed.emit(reason)


func _on_server_disconnected() -> void:
	# leave_game() raises peer_unregistered for every peer and empties the
	# roster, so the client's bodies come down before anyone tries to route to
	# a match that no longer exists. A host quitting mid-round is a completely
	# ordinary thing to do during development, and it must not leave a client
	# with three frozen teammates and a live mouse.
	leave_game()
	server_disconnected.emit()


## A player's profile level, for display: this machine's own from [Profile],
## everyone else's from the roster the host sends.
func level_of(peer_id: int) -> int:
	if not _is_online or peer_id == local_peer_id:
		return Profile.level
	return int(players.get_entry(peer_id).get("level", 1))


## Longest name the game will display.
const MAX_NAME_LENGTH := 16


## The name this machine plays under: the player's saved choice, or a generated
## one that is then saved so it stays the same between sessions.
func local_display_name() -> String:
	var chosen := sanitize_name(GameConfig.display_name)
	if chosen.is_empty():
		chosen = "Player%03d" % (randi() % 1000)
		GameConfig.display_name = chosen
	return chosen


## Trims, strips control characters and caps the length. Applied on the host to
## whatever a client sends, because a name is shown on every screen.
static func sanitize_name(raw: String) -> String:
	var out := ""
	for character in raw.strip_edges():
		if character.unicode_at(0) >= 32:
			out += character
	return out.substr(0, MAX_NAME_LENGTH).strip_edges()


## One line for the dev UI: role, peer id, and roster size.
func status_line() -> String:
	if not _is_online:
		return "Offline"
	var role := "Host" if _is_host else "Client"
	return "%s   peer %d   %s connected" % [role, local_peer_id, players.count_line()]


# --- Roster replication ---------------------------------------------------

## Host only. Pushes the whole roster to every client.
##
## A full snapshot rather than an increment, and that is the point. The
## alternative - "peer X joined", "peer Y left", "peer Z changed team" - is
## three messages, three orderings to get right, and a client that joins
## mid-session has missed all of them. A snapshot has no such state: whatever a
## client holds is the last complete truth the host sent, and applying it
## twice is harmless. Six players is about two hundred bytes, so there is
## nothing to save by being clever.
func _on_roster_changed() -> void:
	if not _is_host:
		return
	var entries: Array = []
	for peer_id in players.peer_ids():
		entries.append(players.get_entry(peer_id))
	if not entries.is_empty():
		_receive_roster.rpc(entries)


## Replaces this machine's roster with the host's, then primes every body
## that already exists so a late-joining client sees correct health/team
## before the next damage event arrives.
##
## Authority-only, and replaces rather than merges. A client that merged would
## keep entries the host has already dropped, so a peer who left would stay on
## the scoreboard forever - and on a client the whole roster comes from the
## host, so there is nothing local worth preserving.
@rpc("authority", "call_remote", "reliable")
func _receive_roster(entries: Array) -> void:
	if multiplayer.is_server():
		return
	players.replace_all(entries)

	# Bodies may already exist (spawner fired first) or may not yet (late join).
	# For any body that is present, seed its mirror fields so the first frame
	# of networked state is the host's truth, not the defaults.
	for entry in entries:
		var peer_id := int(entry.get("peer_id", 0))
		if peer_id <= 0:
			continue
		var body := NetworkManager.get_player_for(peer_id)
		if body != null:
			var health := int(entry.get("health", PlayerState.MAX_HEALTH))
			var alive := bool(entry.get("is_alive", true))
			var team := int(entry.get("team", Team.Side.NONE))
			body.net_health = health
			body.net_alive = alive
			body.net_team = team
			body._sync_state_from_network()
