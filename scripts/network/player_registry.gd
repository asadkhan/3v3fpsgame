class_name PlayerRegistry
extends RefCounted
## who's in this session: peer id, name, side, alive or not. host-authoritative,
## in memory, gone when the session ends.
##
## a plain object owned by NetworkManager, not an autoload or a node. not
## persisted, not replicated on its own - host holds the truth, clients learn
## about peers through the spawn/despawn RPCs MultiplayerSpawner already
## does, so a client's registry is just its local view of that.
##
## team assignment lives here too, so balancing a lobby happens in exactly
## one place (host assigns, clients are told - no "pick your own team" yet).
##
## this is not the scoreboard: it knows who's connected, not kills or round
## wins - that's MatchState.

## one entry per connected peer.
##
## keyed by peer id instead of an array, since every question here ("whose
## player is this", "is there room", "what side is peer 7 on") is a lookup.
var _entries: Dictionary = {}

## cap on how many peers the registry holds. mirrors
## NetworkManager.get_max_players so the two can't disagree about full.
var capacity: int = 6


## sets the session shape, e.g. set_limits(3) for 3v3.
##
## an odd per_team is rejected rather than rounded - a 3-per-side rule with
## a cap of 5 would let one side hold three and the other two, which isn't
## a 3v3 or obviously anything else.
func set_limits(per_team: int, teams: int = 2) -> void:
	if per_team < 1 or teams < 1:
		push_warning("PlayerRegistry: bad limits (%d x %d); keeping capacity %d" % [
			per_team, teams, capacity])
		return
	capacity = per_team * teams


## adds or updates a peer. returns the assigned side, or Team.Side.NONE if
## the session is full or the id is invalid.
##
## capacity check lives here, not in the caller, so "how many are allowed"
## and "how many are here" stay one rule instead of two that can drift.
## NetworkManager.register_peer adds the host check and a log line on top.
##
## host-only by contract - calling this on a client would create a second,
## wrong roster.
func register(peer_id: int, player_name: String = "") -> int:
	if peer_id <= 0:
		push_warning("PlayerRegistry: refusing to register invalid peer id %d" % peer_id)
		return Team.Side.NONE

	# an existing peer is a re-registration, not a new arrival, and must not
	# be charged against the cap - otherwise a reconnect looks like a seventh.
	var entry: Dictionary = _entries.get(peer_id, {})
	if not entry.is_empty():
		entry["display_name"] = player_name if not player_name.is_empty() \
			else default_name_for(peer_id)
		return int(entry.get("team", Team.Side.NONE))

	if not has_open_slot():
		push_warning("PlayerRegistry: session full (%d/%d), refusing peer %d" % [
			_entries.size(), capacity, peer_id])
		return Team.Side.NONE

	entry = {
		"peer_id": peer_id,
		"team": choose_side(),
		"is_alive": true,
		"health": PlayerState.MAX_HEALTH,
		"display_name": player_name if not player_name.is_empty() else default_name_for(peer_id),
	}
	_entries[peer_id] = entry
	return int(entry["team"])


## removes a peer entirely. returns whether they were there to remove.
func unregister(peer_id: int) -> bool:
	return _entries.erase(peer_id)


## empties the registry. used when the host tears a session down, or a
## client loses the server and has to stop trusting a roster that's gone.
func clear() -> void:
	_entries.clear()


## replaces the entire contents with entries from the host.
##
## uses the incoming teams instead of re-deriving them - a client doesn't
## know the join order, so re-running choose_side against a partial roster
## would shuffle sides on every update.
func replace_all(entries: Array) -> void:
	_entries.clear()
	for raw in entries:
		var entry: Dictionary = raw
		var peer_id := int(entry.get("peer_id", 0))
		if peer_id <= 0:
			continue
		_entries[peer_id] = entry.duplicate()


func has_peer(peer_id: int) -> bool:
	return _entries.has(peer_id)


func size() -> int:
	return _entries.size()


func has_open_slot() -> bool:
	return _entries.size() < capacity


func peer_ids() -> Array:
	return _entries.keys()


## the stored record for a peer, or an empty dictionary.
func get_entry(peer_id: int) -> Dictionary:
	return _entries.get(peer_id, {})


## writes a record back, merging so a partial update can't blank a field
## the caller didn't mention.
func update(peer_id: int, changes: Dictionary) -> void:
	if not _entries.has(peer_id):
		return
	var entry: Dictionary = _entries[peer_id]
	for key in changes:
		entry[key] = changes[key]


func display_name_of(peer_id: int) -> String:
	var entry := get_entry(peer_id)
	return String(entry.get("display_name", default_name_for(peer_id)))


func team_of(peer_id: int) -> int:
	return int(get_entry(peer_id).get("team", Team.Side.NONE))


## records a health change reported by the host, so a client's view doesn't
## drift from the replicated Player.state.
func record_health(peer_id: int, health: int, is_alive: bool) -> void:
	update(peer_id, {"health": health, "is_alive": is_alive})


## counts per side, for the UI and the assignment rule below.
func count_for_side(side: int) -> int:
	var total := 0
	for entry in _entries.values():
		if int(entry.get("team", Team.Side.NONE)) == side:
			total += 1
	return total


## picks the side with fewer players, ties towards ALPHA so a fresh lobby
## fills deterministically: 1, 2, 1, 2 - not order-of-connection dependent.
##
## a full side is skipped even if smaller, so both sides fill before either
## doubles up - what makes "3 per team" a hard rule, not a tendency.
func choose_side() -> int:
	var best := Team.Side.ALPHA
	var best_count := count_for_side(Team.Side.ALPHA)
	for side in Team.ASSIGNABLE:
		if count_for_side(side) >= capacity / 2:
			continue
		var count := count_for_side(side)
		if count < best_count:
			best = side
			best_count = count
	return best


## readable fallback name for a peer that never chose one.
static func default_name_for(peer_id: int) -> String:
	return "Player %d" % peer_id


## "3 / 6" - connected against capacity.
func count_line() -> String:
	return "%d / %d" % [_entries.size(), capacity]


## one line per peer, for the dev overlay.
func summary_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for peer_id in _peer_ids_in_join_order():
		var entry := get_entry(peer_id)
		lines.append("  peer %d  %-12s  %-5s  %s" % [
			peer_id,
			String(entry.get("display_name", "?")),
			Team.side_name(int(entry.get("team", Team.Side.NONE))),
			"alive" if bool(entry.get("is_alive", true)) else "dead",
		])
	return lines


## dictionaries already preserve join order; sorted explicitly anyway so the
## dev overlay doesn't look like it's flickering between reads.
func _peer_ids_in_join_order() -> Array:
	var ids := _entries.keys()
	ids.sort()
	return ids
