class_name PlayerRegistry
extends RefCounted
## Who is in this session: a peer id, a name, a side, and whether they are
## alive. Host-authoritative, in memory, and gone when the session ends.
##
## [b]This is a plain object owned by [NetworkManager], not an autoload and not
## a node.[/b] It is deliberately not persisted and deliberately not replicated
## in its own right. The authoritative copy lives on the host; clients learn
## about peers through the spawn and despawn RPCs that [MultiplayerSpawner]
## already performs, so a second mechanism for "who is here" would be a second
## way to be wrong. The registry's job on a client is therefore to answer
## questions about the [b]local[/b] view, and on the host to be the truth.
##
## ## Why the team assignment lives here
##
## Balancing a lobby is the one piece of session setup that has to be decided in
## exactly one place, or two peers can end up on the same side of a 3v3. The
## host assigns; clients are told. There is no "pick your own team" path, and
## that is a scoping decision rather than an oversight - Chapter 8 puts a team
## select in front of the player once there is a lobby worth selecting in.
##
## ## Why it is not the scoreboard
##
## The registry knows who is connected. It does not know kills, does not decide
## a round winner, and has no idea a round exists. [MatchState] does those.
## Keeping them apart is what stops "is the match over" from acquiring a second
## opinion.

## One entry per connected peer.
##
## Keyed by peer id rather than held in an array, because every question this
## is asked - "whose player is this?", "is there room?", "what side is peer 7
## on?" - is a lookup, and an array would mean a linear scan to answer it.
var _entries: Dictionary = {}

## Cap on how many peers the registry will hold. Mirrors
## [method NetworkManager.get_max_players] so the two cannot disagree about
## what full means.
var capacity: int = 6


## Sets the session shape explicitly, e.g. [code]set_limits(3)[/code] for 3v3.
##
## Exists so the rule "3 per team" is written once as a number and the
## [code]capacity / 2[/code] in [method choose_side] is not the only place the
## reader has to spot it. An odd [param per_team] is rejected rather than
## rounded: a 3-per-side rule with a cap of 5 would let one side hold three and
## the other two, which is not a 3v3 and not obviously anything else.
func set_limits(per_team: int, teams: int = 2) -> void:
	if per_team < 1 or teams < 1:
		push_warning("PlayerRegistry: bad limits (%d x %d); keeping capacity %d" % [
			per_team, teams, capacity])
		return
	capacity = per_team * teams


## Adds or updates a peer. Returns the side that was assigned, or
## [constant Team.Side.NONE] if the session is full or the id is invalid.
##
## [b]The capacity check lives here, not in the caller.[/b] "How many players
## are allowed" and "how many players are here" are the same piece of knowledge,
## and a rule split across two files is a rule that eventually answers both
## questions differently. [method NetworkManager.register_peer] adds the host
## check and a log line; the refusal itself happens in exactly one place.
##
## Host-only by contract: [method NetworkManager] is the only caller, and only
## on the server. Calling this on a client would create a second, wrong roster.
func register(peer_id: int, player_name: String = "") -> int:
	if peer_id <= 0:
		push_warning("PlayerRegistry: refusing to register invalid peer id %d" % peer_id)
		return Team.Side.NONE

	# An existing peer is a re-registration, not a new arrival, and must not be
	# charged against the cap. Getting this wrong makes a reconnecting player
	# look like a seventh.
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


## Removes a peer entirely. Returns whether they were there to remove.
func unregister(peer_id: int) -> bool:
	return _entries.erase(peer_id)


## Empties the registry. Used when the host tears a session down, and when a
## client realises it has lost the server and has to stop believing in a roster
## that no longer exists.
func clear() -> void:
	_entries.clear()


## Replaces the entire contents with [param entries] from the host.
##
## Assigns teams from the incoming data rather than re-deriving them. A client
## has no way to reach the same answer the host did - it does not know the
## order peers arrived in, and re-running [method choose_side] against a
## partially-received roster would shuffle sides on every update.
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


## The stored record for a peer, or an empty dictionary. Returned by
## reference, so a caller can update a field and write it straight back with
## [method update] rather than needing a setter per attribute.
func get_entry(peer_id: int) -> Dictionary:
	return _entries.get(peer_id, {})


## Writes a record back, merging so a partial update cannot blank a field the
## caller did not mention.
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


## Records a health change reported by the host, so a client's registry view
## does not drift from the replicated [member Player.state].
func record_health(peer_id: int, health: int, is_alive: bool) -> void:
	update(peer_id, {"health": health, "is_alive": is_alive})


## Counts per side, for the UI and for the assignment rule below.
func count_for_side(side: int) -> int:
	var total := 0
	for entry in _entries.values():
		if int(entry.get("team", Team.Side.NONE)) == side:
			total += 1
	return total


## Picks the side that currently has fewer players, breaking a tie towards
## [constant Team.Side.ALPHA] so a fresh lobby is deterministic: 1, 2, 1, 2
## rather than an arbitrary ordering that depends on connection timing.
##
## A side that is already full is skipped even if it is the smaller one, so a
## rules file asking for 1v1 fills both sides before either doubles up. That
## check is what makes "3 per team" a hard shape rather than a tendency.
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


## A readable name for a peer that never chose one. "Player 3" rather than a
## uuid, because this is a development UI and a human is going to be staring
## at it trying to work out which window is which instance.
static func default_name_for(peer_id: int) -> String:
	return "Player %d" % peer_id


## "3 / 6" - connected against capacity.
func count_line() -> String:
	return "%d / %d" % [_entries.size(), capacity]


## One line per peer, for the dev overlay.
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


## Godot dictionaries preserve insertion order, so this is already "in the
## order they joined". Sorted explicitly anyway, because a roster that reorders
## itself between two reads makes the dev overlay look like it is flickering
## when it is only the hash order changing.
func _peer_ids_in_join_order() -> Array:
	var ids := _entries.keys()
	ids.sort()
	return ids
