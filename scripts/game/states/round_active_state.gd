extends GameState
## [b]ROUND_ACTIVE[/b] - live combat.
##
## Owns the round clock and is the single place a round is allowed to end.
## The rules, with the attacking side trying to plant the Signal Core:
##
## [b]Before a plant[/b]
## - Defenders all dead -> attackers win.
## - Attackers all dead -> defenders win.
## - Time runs out -> defenders win.
##
## [b]After a plant[/b] - the clock becomes the core's detonation timer
## ([member MatchRules.detonation_seconds]).
## - Defenders all dead -> attackers win (nobody is left to defuse).
## - Attackers all dead -> nothing yet; the defenders still have to defuse.
## - Core defused -> defenders win.
## - Core detonates -> attackers win.
##
## Elimination is only checked when both sides actually have players, so the
## offline practice range - one player, no opponents - never ends a round on
## its own, and its timeout scores nobody.
##
## Note that [method end_round] does not award the win. It records who won and
## hands over to [b]ROUND_END[/b], which resolves the round in one place.

## Emitted every frame with the seconds left in the round.
signal round_time_updated(remaining: float)

var _ended: bool = false
var _planted: bool = false


func enter(_previous: GameState) -> void:
	_start_countdown(get_rules().round_seconds)
	# A client joining mid-round learns the core is planted before it enters
	# this phase; pick that up from the objective rather than missing it.
	var objective := game_manager.get_tree().get_first_node_in_group(SignalCoreObjective.GROUP) as SignalCoreObjective
	if objective != null and objective.is_planted():
		_planted = true
	EventBus.player_died.connect(_on_player_died)
	EventBus.core_planted.connect(_on_core_planted)
	EventBus.core_defused.connect(_on_core_defused)
	NetworkManager.roster_updated.connect(_queue_elimination_check)


func exit(_next_state: GameState) -> void:
	for connection in [
		[EventBus.player_died, _on_player_died],
		[EventBus.core_planted, _on_core_planted],
		[EventBus.core_defused, _on_core_defused],
		[NetworkManager.roster_updated, _queue_elimination_check],
	]:
		var sig: Signal = connection[0]
		if sig.is_connected(connection[1]):
			sig.disconnect(connection[1])


## Whether the core is down this round. The HUD reads it to relabel the clock.
func is_core_planted() -> bool:
	return _planted


func update(delta: float) -> void:
	round_time_updated.emit(_tick_countdown(delta))
	if _remaining > 0.0 or not is_authority() or _ended:
		return
	if _planted:
		EventBus.core_detonated.emit()
		end_round(get_match().attacking_side())
	elif _both_sides_present():
		end_round(get_match().defending_side())
	else:
		end_round(Team.Side.NONE)


## Ends the current round and moves to [b]ROUND_END[/b].
## [param winner] is a [enum Team.Side]; pass [constant Team.Side.NONE] when
## nobody won. Returns false if the transition was rejected.
func end_round(winner: int) -> bool:
	if not is_authority() or _ended:
		return false
	_ended = true
	get_match().last_round_winner = winner
	return request_state(GamePhase.Phase.ROUND_END)


func _on_core_planted(_planter_id: int, _site: String) -> void:
	# Runs on every machine, so every copy of the clock switches over together.
	_planted = true
	_start_countdown(get_rules().detonation_seconds)
	_queue_elimination_check()


func _on_core_defused(_defuser_id: int) -> void:
	end_round(get_match().defending_side())


func _on_player_died(_victim_id: int, _killer_id: int, _headshot: bool) -> void:
	_queue_elimination_check()


## Deferred to the end of the frame: a death is raised from inside a shot's
## resolution, and a disconnect from inside the transport callback. Neither is a
## good place to swap the whole game phase, and a body that is leaving is only
## gone from the tree once the frame finishes.
func _queue_elimination_check() -> void:
	if is_authority():
		_check_elimination.call_deferred()


func _both_sides_present() -> bool:
	var counts := _count_sides()
	return counts[0][Team.Side.ALPHA] > 0 and counts[0][Team.Side.BRAVO] > 0


## [present per side, alive per side]
func _count_sides() -> Array:
	var present := {Team.Side.ALPHA: 0, Team.Side.BRAVO: 0}
	var alive := {Team.Side.ALPHA: 0, Team.Side.BRAVO: 0}
	for player in NetworkManager.get_players():
		if player.is_queued_for_deletion() or not present.has(player.state.team):
			continue
		present[player.state.team] += 1
		if player.state.is_alive:
			alive[player.state.team] += 1
	return [present, alive]


func _check_elimination() -> void:
	if _ended or not is_authority():
		return
	var counts := _count_sides()
	var present: Dictionary = counts[0]
	var alive: Dictionary = counts[1]
	# One side has nobody at all: a practice session or a lobby still filling.
	if present[Team.Side.ALPHA] == 0 or present[Team.Side.BRAVO] == 0:
		return

	var attackers := get_match().attacking_side()
	var defenders := get_match().defending_side()
	var attackers_out: bool = alive[attackers] == 0
	var defenders_out: bool = alive[defenders] == 0

	if defenders_out and (_planted or not attackers_out):
		end_round(attackers)
	elif defenders_out:
		# Everyone died together before a plant: the attack failed.
		end_round(defenders)
	elif attackers_out and not _planted:
		end_round(defenders)
