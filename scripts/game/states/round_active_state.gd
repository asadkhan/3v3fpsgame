extends GameState
## [b]ROUND_ACTIVE[/b] - live combat.
##
## Owns the round clock and is the single place a round is allowed to end.
## A round ends when:
## - [b]a side is eliminated[/b] - every player on it is dead (or gone) while the
##   other side still has someone standing. The survivors win.
## - [b]both sides are wiped out together[/b] - nobody wins.
## - [b]time runs out[/b] - nobody wins. (Once an objective exists, the timeout
##   will instead go to the defending side.)
##
## Elimination is only checked when both sides actually have players, so the
## offline practice range - one player, no opponents - never ends a round on
## its own.
##
## Note that [method end_round] does not award the win. It records who won and
## hands over to [b]ROUND_END[/b], which resolves the round in one place.
## That means the score, the [signal EventBus.round_ended] event and the
## next-phase decision all happen together and cannot drift apart.

## Emitted every frame with the seconds left in the round.
signal round_time_updated(remaining: float)

var _ended: bool = false


func enter(_previous: GameState) -> void:
	_start_countdown(get_rules().round_seconds)
	EventBus.player_died.connect(_on_player_died)
	NetworkManager.roster_updated.connect(_queue_elimination_check)


func exit(_next_state: GameState) -> void:
	if EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.disconnect(_on_player_died)
	if NetworkManager.roster_updated.is_connected(_queue_elimination_check):
		NetworkManager.roster_updated.disconnect(_queue_elimination_check)


func update(delta: float) -> void:
	round_time_updated.emit(_tick_countdown(delta))
	if _remaining <= 0.0:
		# Time ran out. Passing NONE means "no team won this round", which is
		# different from a draw between two teams and must not be scored.
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


func _on_player_died(_victim_id: int, _killer_id: int, _headshot: bool) -> void:
	_queue_elimination_check()


## Deferred to the end of the frame: a death is raised from inside a shot's
## resolution, and a disconnect from inside the transport callback. Neither is a
## good place to swap the whole game phase, and a body that is leaving is only
## gone from the tree once the frame finishes.
func _queue_elimination_check() -> void:
	if is_authority():
		_check_elimination.call_deferred()


func _check_elimination() -> void:
	if _ended or not is_authority():
		return

	var present := {Team.Side.ALPHA: 0, Team.Side.BRAVO: 0}
	var alive := {Team.Side.ALPHA: 0, Team.Side.BRAVO: 0}
	for player in NetworkManager.get_players():
		if player.is_queued_for_deletion() or not present.has(player.state.team):
			continue
		present[player.state.team] += 1
		if player.state.is_alive:
			alive[player.state.team] += 1

	# One side has nobody at all: a practice session or a lobby still filling.
	if present[Team.Side.ALPHA] == 0 or present[Team.Side.BRAVO] == 0:
		return

	var alpha_out: bool = alive[Team.Side.ALPHA] == 0
	var bravo_out: bool = alive[Team.Side.BRAVO] == 0
	if alpha_out and bravo_out:
		end_round(Team.Side.NONE)
	elif alpha_out:
		end_round(Team.Side.BRAVO)
	elif bravo_out:
		end_round(Team.Side.ALPHA)
