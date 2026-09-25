extends GameState
## [b]ROUND_ACTIVE[/b] - live combat.
##
## There is no combat system yet, so this state does the two things that are
## genuinely its job and no one else's: it owns the round clock, and it is the
## single place a round is allowed to end.
##
## Note that [method end_round] does not award the win. It records who won and
## hands over to [b]ROUND_END[/b], which resolves the round in one place.
## That means the score, the [signal EventBus.round_ended] event and the
## next-phase decision all happen together and cannot drift apart.

## Emitted every frame with the seconds left in the round.
signal round_time_updated(remaining: float)


func enter(_previous: GameState) -> void:
	_start_countdown(get_rules().round_seconds)


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
	if not is_authority():
		return false
	get_match().last_round_winner = winner
	return request_state(GamePhase.Phase.ROUND_END)


func exit(_next_state: GameState) -> void:
	pass
