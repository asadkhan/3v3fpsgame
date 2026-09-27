extends GameState
## MATCH_END - a team has won the match.
##
## unlike the other phases this one has no timer and doesn't move on by
## itself. the result stays up until someone picks rematch or title screen -
## losing your rematch because a timer ran out would suck.

## fires once, when the match is actually won
signal match_concluded(winning_team: int)

var _announced: bool = false


func enter(_previous: GameState) -> void:
	_announced = false


func update(_delta: float) -> void:
	# announced on the first tick, not in enter(), so late connections (a peer
	# joining mid-transition, a screen not built yet) don't miss it or hear
	# it twice
	if _announced or game_manager == null:
		return

	var match_data := get_match()
	if not match_data.is_match_over():
		return

	_announced = true
	match_concluded.emit(match_data.winning_team)
	EventBus.match_ended.emit(match_data.winning_team)


## back to the lobby for a rematch. LOBBY resets the match, scoreboard starts clean.
func return_to_lobby() -> bool:
	return request_state(GamePhase.Phase.LOBBY)


## back to the title screen
func return_to_menu() -> bool:
	return request_state(GamePhase.Phase.MAIN_MENU)
