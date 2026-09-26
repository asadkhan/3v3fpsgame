class_name MatchTracker
extends Node
## Turns what happens in a match into the numbers and moments players care
## about: damage, assists, headshot kills, first bloods, objective plays, and
## the callouts - FIRST BLOOD, DOUBLE KILL, TRIPLE KILL, ACE, CLUTCH.
##
## [b]Host-authoritative[/b], like every other number in the match. The host
## listens to the gameplay events it alone raises (damage, deaths, plants and
## defuses), updates each [PlayerState], and sends changed players' stats to
## everyone a few times a second. Callouts are sent as they happen and raised
## on every machine as [signal EventBus.player_callout].
##
## Lives in the match scene as [code]Tracker[/code].

const GROUP := &"match_tracker"

## Callout kinds, raised through [signal EventBus.player_callout].
const FIRST_BLOOD := &"first_blood"
const DOUBLE_KILL := &"double_kill"
const TRIPLE_KILL := &"triple_kill"
const ACE := &"ace"
const CLUTCH := &"clutch"

## Seconds between stat broadcasts while something has changed.
const SEND_INTERVAL := 0.25

# --- Host-only round state ------------------------------------------------------

## victim peer -> {attacker peer: true} for the victim's current life.
var _damagers: Dictionary = {}
## peer -> kills this round.
var _round_kills: Dictionary = {}
var _first_blood_done: bool = false
## side -> the peer who became that side's last player alive against two or
## more opponents this round.
var _clutch_candidate: Dictionary = {}

var _dirty: Dictionary = {}
var _send_left: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(_on_player_died)
	EventBus.core_planted.connect(_on_core_planted)
	EventBus.core_defused.connect(_on_core_defused)
	GameManager.state_changed.connect(_on_phase_changed)


func _process(delta: float) -> void:
	if not _is_authority() or _dirty.is_empty():
		return
	_send_left -= delta
	if _send_left > 0.0:
		return
	_send_left = SEND_INTERVAL
	_flush()


## Sends every changed player's stats now.
func _flush() -> void:
	for peer_id in _dirty:
		var player := NetworkManager.get_player_for(peer_id)
		if player != null and NetworkManager.is_online:
			_net_stats.rpc(peer_id, player.state.stats_to_dict())
	_dirty.clear()


# --- Host: gameplay events ----------------------------------------------------------

func _on_player_damaged(victim_id: int, attacker_id: int, amount: float) -> void:
	if not _is_authority() or attacker_id == EventBus.INVALID_PEER or attacker_id == victim_id:
		return
	var attacker := NetworkManager.get_player_for(attacker_id)
	var victim := NetworkManager.get_player_for(victim_id)
	if attacker == null or victim == null or attacker.state.team == victim.state.team:
		return
	attacker.state.damage_dealt += int(round(amount))
	if not _damagers.has(victim_id):
		_damagers[victim_id] = {}
	_damagers[victim_id][attacker_id] = true
	_dirty[attacker_id] = true


func _on_player_died(victim_id: int, killer_id: int, headshot: bool) -> void:
	if not _is_authority():
		return
	var victim := NetworkManager.get_player_for(victim_id)
	var killer := NetworkManager.get_player_for(killer_id) if killer_id != EventBus.INVALID_PEER else null
	var in_round := GameManager.is_in(GamePhase.Phase.ROUND_ACTIVE)
	_dirty[victim_id] = true

	if killer != null and victim != null and killer.state.team != victim.state.team:
		_dirty[killer_id] = true
		if headshot:
			killer.state.headshot_kills += 1
		# Assists: everyone else on the killer's side who damaged this life.
		for damager_id in _damagers.get(victim_id, {}):
			if damager_id == killer_id:
				continue
			var helper := NetworkManager.get_player_for(damager_id)
			if helper != null and helper.state.team == killer.state.team:
				helper.state.assists += 1
				_dirty[damager_id] = true

		if in_round:
			if not _first_blood_done:
				_first_blood_done = true
				killer.state.first_bloods += 1
				_callout(killer_id, FIRST_BLOOD)
			var count: int = _round_kills.get(killer_id, 0) + 1
			_round_kills[killer_id] = count
			if count == _enemy_count(killer.state.team) and count >= 2:
				killer.state.aces += 1
				_callout(killer_id, ACE)
			elif count == 2:
				_callout(killer_id, DOUBLE_KILL)
			elif count == 3:
				_callout(killer_id, TRIPLE_KILL)
	_damagers.erase(victim_id)

	if in_round:
		_check_clutch_candidates()


## When a side is down to one player facing two or more, that player is in a
## clutch. Remembered until the round ends; it counts if their side wins.
func _check_clutch_candidates() -> void:
	var alive := {Team.Side.ALPHA: [], Team.Side.BRAVO: []}
	for player in NetworkManager.get_players():
		if player.state.is_alive and alive.has(player.state.team):
			alive[player.state.team].append(player)
	for side in alive:
		var mine: Array = alive[side]
		var theirs: Array = alive[Team.opposing_side(side)]
		if mine.size() == 1 and theirs.size() >= 2 and not _clutch_candidate.has(side):
			_clutch_candidate[side] = (mine[0] as Player).peer_id


func _on_core_planted(planter_id: int, _site: String) -> void:
	var planter := NetworkManager.get_player_for(planter_id) if _is_authority() else null
	if planter != null:
		planter.state.plants += 1
		_dirty[planter_id] = true


func _on_core_defused(defuser_id: int) -> void:
	var defuser := NetworkManager.get_player_for(defuser_id) if _is_authority() else null
	if defuser != null:
		defuser.state.defuses += 1
		_dirty[defuser_id] = true


func _on_phase_changed(_previous: int, current: int) -> void:
	if not _is_authority():
		return
	match current:
		GamePhase.Phase.BUY:
			_damagers.clear()
			_round_kills.clear()
			_first_blood_done = false
			_clutch_candidate.clear()
		GamePhase.Phase.ROUND_END:
			var winner := GameManager.match_state.last_round_winner
			if _clutch_candidate.has(winner):
				var peer_id: int = _clutch_candidate[winner]
				var hero := NetworkManager.get_player_for(peer_id)
				if hero != null:
					hero.state.clutches += 1
					_dirty[peer_id] = true
					_callout(peer_id, CLUTCH)
			# Everyone's final numbers for the round, straight away.
			for player in NetworkManager.get_players():
				_dirty[player.peer_id] = true
			_flush()
		GamePhase.Phase.MATCH_END:
			for player in NetworkManager.get_players():
				_dirty[player.peer_id] = true
			_flush()


func _enemy_count(side: int) -> int:
	var count := 0
	for player in NetworkManager.get_players():
		if player.state.team == Team.opposing_side(side):
			count += 1
	return count


# --- Replication --------------------------------------------------------------------

func _callout(peer_id: int, kind: StringName) -> void:
	EventBus.player_callout.emit(peer_id, kind)
	if NetworkManager.is_online:
		_net_callout.rpc(peer_id, kind)


@rpc("authority", "call_remote", "reliable")
func _net_callout(peer_id: int, kind: StringName) -> void:
	EventBus.player_callout.emit(peer_id, kind)


@rpc("authority", "call_remote", "reliable")
func _net_stats(peer_id: int, stats: Dictionary) -> void:
	var player := NetworkManager.get_player_for(peer_id)
	if player != null:
		player.state.apply_stats_dict(stats)


func _is_authority() -> bool:
	return not NetworkManager.is_online or multiplayer.is_server()


## Human-readable callout text.
static func callout_text(kind: StringName) -> String:
	match kind:
		FIRST_BLOOD: return "FIRST BLOOD"
		DOUBLE_KILL: return "DOUBLE KILL"
		TRIPLE_KILL: return "TRIPLE KILL"
		ACE: return "ACE"
		CLUTCH: return "CLUTCH"
	return String(kind).to_upper()
