extends Node
## owns the multiplayer peer and all connection state. registered as the
## NetworkManager autoload.
##
## everything netcode-related goes through here - nothing else touches
## ENetMultiplayerPeer directly, so the rest of the game can just ask
## "am i the host?" / "who's connected?" without caring about ENet.
##
## ## Authority
##
## authority rules live here in one place so two peers can't both end up
## thinking they own a body:
##
## - a client owns its own movement. its Player runs physics locally and
##   replicates its transform. the host never simulates remote players,
##   just receives their snapshots and applies them.
## - the host owns health, team, death and respawns, sent as host-only RPCs
##   with a sender check, so a client can't just write these itself.
## - the host owns match flow. GameManager replicates phase/score/countdown
##   to clients; a client never advances a phase on its own.
## - the host resolves every shot. a client sends an aim ray, the host
##   re-derives it and decides what got hit, then tells the client.
##
## one asymmetry worth remembering: the host's own player is authoritative
## for its own transform but also would be a remote body to nobody, so it
## takes the same validating path by calling it directly - Godot refuses
## an RPC addressed to the local peer.

# --- Signals ------------------------------------------------------------

## this machine started a server.
signal hosting_started(port: int)

## we're now connected to a server as a client.
signal join_succeeded

## joining failed. reason is safe to show in the UI.
signal join_failed(reason: String)

## a peer connected. peer_id is 0 for the host itself on a client.
signal peer_connected(peer_id: int)

## a peer disconnected.
signal peer_disconnected(peer_id: int)

## we lost the server we were connected to.
signal server_disconnected

## roster changed: somebody joined, left, or changed health. dev UI listens
## to this instead of polling.
signal roster_updated

## host only. a peer has been given a side and should now be spawned.
## player_name is what the scoreboard will show.
signal peer_registered(peer_id: int, team_side: int, player_name: String)

## host only. a peer is gone and their body should be removed everywhere.
## raised before the node is freed so listeners can still look it up.
signal peer_unregistered(peer_id: int)

## a client finished loading its match scene and is ready for a body.
## host only, raised by request_spawn().
signal spawn_requested(peer_id: int)

# --- Session configuration ----------------------------------------------

## default port for a local or LAN match.
const DEFAULT_PORT := 27015

## loopback, for testing two instances on one machine.
const DEFAULT_ADDRESS := "127.0.0.1"

## hard ceiling on a session no matter what the rules ask for, so a bad
## match_rules.tres can't open a server for a thousand players. transport
## safety limit, not a game rule - the real cap is get_max_players().
const ABSOLUTE_MAX_PLAYERS := 16

## Godot's first peer id is always the server - this is the id ENet itself
## hands the host, so every "is the host" check reads it from here.
const SERVER_PEER_ID := 1

var _peer: ENetMultiplayerPeer = null
var _is_online: bool = false
var _is_host: bool = false

## who's in the session. owned, not an autoload - dies with the manager,
## since the roster belongs to the session, not the app.
var players := PlayerRegistry.new()


func _ready() -> void:
	# connection teardown must still run if the tree is paused mid-round.
	process_mode = Node.PROCESS_MODE_ALWAYS

	players.capacity = get_max_players()

	# connected once here rather than on every join: `multiplayer` outlives
	# any individual peer, so these keep firing correctly across reconnects.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# one place that pushes the roster out instead of a broadcast call at
	# every spot that can change it.
	roster_updated.connect(_on_roster_changed)


# --- State --------------------------------------------------------------

## whether we're connected to a session at all.
var is_online: bool:
	get: return _is_online

## whether this machine is the server. clients must never run authoritative
## game logic, so this gates most of those decisions.
var is_host: bool:
	get: return _is_host

## our own network id, or 0 when offline.
var local_peer_id: int:
	get: return _peer.get_unique_id() if _peer != null else 0

## peers the transport reports, excluding this machine.
##
## MultiplayerAPI.get_peers() never includes the local peer, so on the host
## this is "every client", on a client it's "host + every other client".
## for "how many players are in the match" use get_player_count() instead,
## which does include this machine.
func get_connected_peers() -> PackedInt32Array:
	if not _is_online:
		return PackedInt32Array()
	return multiplayer.get_peers()


## session size implied by the match rules: two teams of players_per_team.
## "3v3" is stated once in data/match_rules.tres, not as a 6 here and a 3
## there. clamped so a bad rules file can't produce an absurd session.
func get_max_players() -> int:
	return clampi(GameManager.match_rules.get_team_size(), 2, ABSOLUTE_MAX_PLAYERS)


## total players in the match, including this machine.
##
## read from the roster, not the transport: the transport doesn't count the
## host (a one-player session would read as zero), and the roster is what
## team assignment and the player cap are actually enforced against.
func get_player_count() -> int:
	return players.size()


## whether the session has room for another player.
func has_open_slot() -> bool:
	return players.has_open_slot()


# --- Roster ---------------------------------------------------------------

## adds a peer to the roster and assigns them a side. host-only.
##
## returns the assigned Team.Side, or Team.Side.NONE if the session is full
## (PlayerRegistry.register handles the actual capacity check; this wraps
## the host check, logging and roster notification around it).
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


## removes a peer from the roster. host-only, except a client calling it for
## itself is fine - that's just the "I am leaving" path.
func unregister_peer(peer_id: int) -> void:
	if not _is_host and peer_id != local_peer_id:
		return
	if players.unregister(peer_id):
		roster_updated.emit()


## the Player node for a peer, or null if not spawned here.
##
## looked up through the scene tree instead of cached in a dictionary - a
## stale node reference is a crash waiting to happen on disconnect.
func get_player_for(peer_id: int) -> Player:
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.peer_id == peer_id:
			return player
	return null


## every Player in this scene, for iteration that doesn't care who owns what.
func get_players() -> Array[Player]:
	var found: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null:
			found.append(player)
	return found


## the one player this machine drives, or null if we're a spectator with no
## body of our own. also handles offline: no session means no peer id to
## match on, but there's still exactly one player to find.
func get_local_player() -> Player:
	if not _is_online:
		return _only_player()
	return get_player_for(local_peer_id)


## the single body in the scene, if there's exactly one. null if there are
## none or several - guessing which one is worse than an honest null.
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

## starts a server and waits for players to connect.
## max_players of 0 means "use the session size from the match rules".
## returns OK on success, or an Error for error_string().
func host_game(port: int = DEFAULT_PORT, max_players: int = 0) -> Error:
	leave_game()

	var cap := mini(max_players if max_players > 0 else get_max_players(), ABSOLUTE_MAX_PLAYERS)

	# ENet's second argument counts *clients*, not participants - the host
	# isn't one of them. passing the full cap through would let one extra
	# player connect before the registry refuses them; subtracting 1 makes
	# ENet reject the extra player at the handshake instead, which is cleaner.
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

	# the host has to be in the roster too, or it'd be the one participant
	# with no body and no side. registered here directly since ENet never
	# raises peer_connected for the server about itself.
	register_peer(SERVER_PEER_ID, local_display_name())
	players.update(SERVER_PEER_ID, {"level": Profile.level})

	print("[Network] Hosting on port %d for up to %d players" % [port, cap])
	hosting_started.emit(port)
	return OK


## connects to a server. use join_succeeded/join_failed to find out how it
## went - this returns before the attempt completes.
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


## disconnects and returns to a fully offline state. safe to call when
## already offline, and safe mid-round.
func leave_game() -> void:
	# every peer needs to be told their body is going away before the peer
	# closes, or clients are left holding bodies they can't reconcile.
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

	# register immediately so the roster is authoritative, but defer the
	# spawn until the client confirms its match scene is ready via
	# request_spawn(). the host's own peer (id 1) has no client to handshake
	# with, so register and notify immediately.
	var side := register_peer(id)
	if id == SERVER_PEER_ID:
		peer_registered.emit(id, side, players.display_name_of(id))


## client to host: "my match scene is up, please give me a body."
##
## this handshake exists to avoid a race: if the host spawned a body the
## instant ENet's handshake completes, a client that hasn't added its
## MultiplayerSpawner yet would silently drop the spawn message and end up
## a player short with nothing erroring. so the client says when it's ready
## instead, and the host spawns then.
@rpc("any_peer", "call_remote", "reliable")
func request_spawn(player_name: String = "", player_level: int = 1) -> void:
	if not multiplayer.is_server():
		return

	# only a peer the host already registered may ask, or a refused/full-session
	# client could still get a body spawned for it with no roster entry.
	var sender := multiplayer.get_remote_sender_id()
	if not players.has_peer(sender):
		push_warning("NetworkManager: spawn requested by unregistered peer %d; refused." % sender)
		return

	# the client's chosen name, cleaned. arrives here rather than at connect
	# time because ENet's handshake carries no payload.
	var clean := sanitize_name(player_name)
	var changes := {"level": clampi(player_level, 1, 999)}
	if not clean.is_empty():
		changes["display_name"] = _unique_name(clean, sender)
	players.update(sender, changes)
	roster_updated.emit()

	# phase first, so the client has the host's score/countdown before its
	# body arrives.
	GameManager.send_snapshot_to(sender)
	peer_registered.emit(sender, players.team_of(sender), players.display_name_of(sender))
	spawn_requested.emit(sender)


## wanted, with a number appended if someone else already goes by it - two
## "Player867"s on one scoreboard is unreadable.
func _unique_name(wanted: String, peer_id: int) -> String:
	var taken := {}
	for other: int in players.peer_ids():
		if other != peer_id:
			taken[players.display_name_of(other).to_lower()] = true
	var out := wanted
	var n := 2
	while taken.has(out.to_lower()):
		out = "%s %d" % [wanted.substr(0, MAX_NAME_LENGTH - 2), n]
		n += 1
	return out


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)
	# on any machine, not just the host: a client also needs to stop
	# believing this peer's body exists, since the spawner despawn is a
	# separate message that can arrive a frame later.
	peer_unregistered.emit(id)
	if _is_host:
		players.unregister(id)
		roster_updated.emit()


func _on_connected_to_server() -> void:
	join_succeeded.emit()


func _on_connection_failed() -> void:
	# ENet leaves the peer half-open on failure, so clean up here instead of
	# leaving is_online true with nothing behind it.
	var reason := "The host did not respond."
	push_warning("NetworkManager: " + reason)
	leave_game()
	join_failed.emit(reason)


func _on_server_disconnected() -> void:
	# leave_game() clears the roster and despawns bodies before anyone tries
	# to route into a match that no longer exists.
	leave_game()
	last_disconnect_reason = "The host left the match."
	server_disconnected.emit()
	# no match without a host - back to the menu instead of playing empty
	# rounds with offline authority.
	GameManager.return_to_menu()


## a player's profile level, for display: this machine's own from Profile,
## everyone else's from the roster the host sends.
func level_of(peer_id: int) -> int:
	if not _is_online or peer_id == local_peer_id:
		return Profile.level
	return int(players.get_entry(peer_id).get("level", 1))


## why the last session ended, shown once on the main menu. cleared there.
var last_disconnect_reason: String = ""


## longest name the game will display.
const MAX_NAME_LENGTH := 16


## the name this machine plays under: the player's saved choice, or a
## generated one that then gets saved so it stays the same between sessions.
func local_display_name() -> String:
	var chosen := sanitize_name(GameConfig.display_name)
	if chosen.is_empty():
		chosen = "Player%03d" % (randi() % 1000)
		GameConfig.display_name = chosen
	return chosen


## trims, strips control characters and caps the length. applied on the host
## to whatever a client sends, since a name gets shown everywhere.
static func sanitize_name(raw: String) -> String:
	var out := ""
	for character in raw.strip_edges():
		if character.unicode_at(0) >= 32:
			out += character
	return out.substr(0, MAX_NAME_LENGTH).strip_edges()


## one line for the dev UI: role, peer id, and roster size.
func status_line() -> String:
	if not _is_online:
		return "Offline"
	var role := "Host" if _is_host else "Client"
	return "%s   peer %d   %s connected" % [role, local_peer_id, players.count_line()]


# --- Roster replication ---------------------------------------------------

## host only. pushes the whole roster to every client.
##
## a full snapshot rather than increments on purpose - "peer joined/left/
## changed team" messages need ordering and a late-joining client misses all
## of them. a snapshot has no such state: applying it twice is harmless, and
## six players is only a couple hundred bytes anyway.
func _on_roster_changed() -> void:
	if not _is_host:
		return
	var entries: Array = []
	for peer_id in players.peer_ids():
		entries.append(players.get_entry(peer_id))
	if not entries.is_empty():
		_receive_roster.rpc(entries)


## replaces this machine's roster with the host's, then primes every body
## that already exists so a late-joining client sees correct health/team
## before the next damage event arrives.
##
## authority-only, and replaces rather than merges - merging would keep
## entries the host already dropped, leaving departed peers stuck on the
## scoreboard forever.
@rpc("authority", "call_remote", "reliable")
func _receive_roster(entries: Array) -> void:
	if multiplayer.is_server():
		return
	players.replace_all(entries)

	# bodies may already exist (spawner fired first) or not yet (late join).
	# for any body present, seed its mirror fields so the first networked
	# frame is the host's truth, not the defaults.
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
