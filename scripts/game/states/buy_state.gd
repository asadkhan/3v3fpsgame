extends GameState
## BUY - the prep/buy window at the start of every round.
##
## round one arrives from WARMUP, every later round from ROUND_END. both
## paths go through here, so this is where the round counter bumps and
## the rest of the game hears a round is being set up.
##
## doesn't spawn players - states are node-free and don't know where a
## map keeps its spawn markers. the match scene (Playtest) listens for
## this phase and respawns everyone at their side's spawn.

## emitted every frame with the seconds left in the buy window.
signal countdown_updated(remaining: float)


func enter(_previous: GameState) -> void:
	_start_countdown(get_rules().round_start_seconds)

	var match_data := get_match()
	# on a client the round number arrives from the host with the phase.
	if is_authority():
		match_data.start_round()
	EventBus.round_started.emit(match_data.round_number)
	countdown_updated.emit(_remaining)


func update(delta: float) -> void:
	countdown_updated.emit(_tick_countdown(delta))
	if _remaining <= 0.0:
		request_state(GamePhase.Phase.ROUND_ACTIVE)
