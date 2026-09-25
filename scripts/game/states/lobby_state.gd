extends GameState
## [b]LOBBY[/b] - players are connected and waiting for the host to begin.
##
## Entering a lobby always starts a fresh match, so the score is reset here
## rather than at the end of the previous one. That way a player who backs out
## of a lobby mid-match does not leave a half-scored match behind, and a
## rematch from [b]MATCH_END[/b] starts clean without either side having to
## remember to reset anything.

func enter(_previous: GameState) -> void:
	# On a client the numbers arrive from the host with the phase itself.
	if is_authority():
		get_match().reset()


## How many peers are connected. Thin wrapper for now; the real roster is
## Chapter 4's job, and that roster will be the source of truth.
func get_player_count() -> int:
	return NetworkManager.get_player_count()


## Whether this client is allowed to start the match. Only the host can.
func can_start_match() -> bool:
	return NetworkManager.is_host


## The host calls this once everyone is ready.
func start_warmup() -> bool:
	return request_state(GamePhase.Phase.WARMUP)


## Abandons the lobby and returns to the title screen.
func leave_lobby() -> bool:
	return request_state(GamePhase.Phase.MAIN_MENU)
