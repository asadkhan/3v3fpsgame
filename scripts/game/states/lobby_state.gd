extends GameState
## LOBBY - players are connected, waiting for the host to start.
##
## resets the score on entry rather than at the end of the previous match,
## so backing out mid-match doesn't leave a half-scored match behind, and a
## rematch from MATCH_END starts clean automatically.

func enter(_previous: GameState) -> void:
	# on a client the numbers arrive from the host with the phase itself.
	if is_authority():
		get_match().reset()


## how many peers are connected.
func get_player_count() -> int:
	return NetworkManager.get_player_count()


## whether this client can start the match. only the host can.
func can_start_match() -> bool:
	return NetworkManager.is_host


## host calls this once everyone is ready.
func start_warmup() -> bool:
	return request_state(GamePhase.Phase.WARMUP)


## abandons the lobby and returns to the title screen.
func leave_lobby() -> bool:
	return request_state(GamePhase.Phase.MAIN_MENU)
