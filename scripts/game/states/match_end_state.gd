extends GameState
## [b]MATCH_END[/b] - a team has won the match.
##
## Unlike the other phases this one has no timer and does not move on by
## itself. The result stays up until a player chooses to go back to the lobby
## for a rematch or to the title screen, because losing your rematch because a
## timer ran out is a miserable way to end a match.

## Fires once, when the match is actually won.
signal match_concluded(winning_team: int)

var _announced: bool = false


func enter(_previous: GameState) -> void:
	_announced = false


func update(_delta: float) -> void:
	# Announced on the first tick rather than in enter() so that anything
	# which connects late - a peer joining mid-transition, a screen that has
	# not been built yet - cannot miss it or hear it twice.
	if _announced or game_manager == null:
		return

	var match_data := get_match()
	if not match_data.is_match_over():
		return

	_announced = true
	match_concluded.emit(match_data.winning_team)
	EventBus.match_ended.emit(match_data.winning_team)


## Back to the lobby for a rematch. [b]LOBBY[/b] resets the match, so the
## scoreboard starts clean.
func return_to_lobby() -> bool:
	return request_state(GamePhase.Phase.LOBBY)


## Back to the title screen.
func return_to_menu() -> bool:
	return request_state(GamePhase.Phase.MAIN_MENU)
