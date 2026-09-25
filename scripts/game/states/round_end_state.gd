extends GameState
## [b]ROUND_END[/b] - the pause after a round, while the result is shown.
##
## This is the one place a round gets resolved. Crediting the score, telling
## the rest of the game the round is over, and deciding whether the match
## continues all happen together here, so they cannot get out of step with
## each other.

## Emitted every frame with the seconds left before the next phase.
signal resolution_updated(remaining: float)


func enter(_previous: GameState) -> void:
	_start_countdown(get_rules().round_end_seconds)

	var match_data := get_match()
	var winner := match_data.last_round_winner

	# A round with no winner is not scored, and does not stop the match.
	if winner != Team.Side.NONE and is_authority():
		match_data.add_round_win(winner)

	EventBus.round_ended.emit(winner)
	resolution_updated.emit(_remaining)


func update(delta: float) -> void:
	resolution_updated.emit(_tick_countdown(delta))
	if _remaining <= 0.0:
		_advance()


## Either the match is won, or we go round again. Reading
## [member MatchState.winning_team] rather than tracking a flag here means a
## win is detected the same way everywhere.
func _advance() -> void:
	var match_data := get_match()
	if match_data.is_match_over():
		request_state(GamePhase.Phase.MATCH_END)
	else:
		request_state(GamePhase.Phase.BUY)
