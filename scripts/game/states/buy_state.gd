extends GameState
## [b]BUY[/b] - the preparation / buy window at the start of every round.
##
## Round one is reached from [b]WARMUP[/b], and every later round from
## [b]ROUND_END[/b]. Both paths come through here, which is what makes this the
## right place to bump the round counter and tell the rest of the game a round
## is being set up.
##
## [b]What this state does not do: spawn players.[/b] States are node-free (see
## [GameState]) and have no business knowing where a map keeps its spawn
## markers. The match scene ([Playtest]) listens for this phase and respawns
## every body at its side's spawn - on the host, through the networked respawn
## path in [method Player.server_respawn_at]. The buy menu itself is Chapter 8.

## Emitted every frame with the seconds left in the buy window.
signal countdown_updated(remaining: float)


func enter(_previous: GameState) -> void:
	_start_countdown(get_rules().round_start_seconds)

	var match_data := get_match()
	# On a client the round number arrives from the host with the phase.
	if is_authority():
		match_data.start_round()
	EventBus.round_started.emit(match_data.round_number)
	countdown_updated.emit(_remaining)


func update(delta: float) -> void:
	countdown_updated.emit(_tick_countdown(delta))
	if _remaining <= 0.0:
		request_state(GamePhase.Phase.ROUND_ACTIVE)
