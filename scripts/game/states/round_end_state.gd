extends GameState
## ROUND_END - the pause after a round, while the result is shown.
##
## the one place a round gets resolved: crediting the score, announcing the
## round is over, and deciding whether the match continues all happen here
## together so they can't get out of step.

## fires every frame with the seconds left before the next phase.
signal resolution_updated(remaining: float)


func enter(_previous: GameState) -> void:
	_start_countdown(get_rules().round_end_seconds)

	var match_data := get_match()
	var winner := match_data.last_round_winner

	# a round with no winner isn't scored and doesn't stop the match.
	if is_authority():
		if winner != Team.Side.NONE:
			match_data.add_round_win(winner)
		# paid before the streak advances, so a first loss earns the base amount.
		Economy.pay_round(winner)
		match_data.record_round_result(winner)

	EventBus.round_ended.emit(winner)
	resolution_updated.emit(_remaining)


func update(delta: float) -> void:
	resolution_updated.emit(_tick_countdown(delta))
	if _remaining <= 0.0:
		_advance()


## either the match is won, or we go another round.
func _advance() -> void:
	var match_data := get_match()
	if match_data.is_match_over():
		request_state(GamePhase.Phase.MATCH_END)
	else:
		request_state(GamePhase.Phase.BUY)
