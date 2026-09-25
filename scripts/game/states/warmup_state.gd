extends GameState
## [b]WARMUP[/b] - the one-off countdown before the very first round, so
## players have a moment to load in and get their bearings.
##
## This only ever runs once per match. Every round after the first goes
## [b]ROUND_END[/b] -> [b]BUY[/b] directly.
##
## Because it is a timed state it exposes [signal countdown_updated] rather
## than making the UI poll it. That is the pattern every timed phase here
## uses: the state owns the clock, the UI just listens. The clock itself is
## inherited from [GameState] - this file only decides what happens when it
## reaches zero.

## Emitted every frame with the seconds left, for the HUD countdown.
signal countdown_updated(remaining: float)


func enter(_previous: GameState) -> void:
	_start_countdown(get_rules().warmup_seconds)
	countdown_updated.emit(_remaining)


func update(delta: float) -> void:
	countdown_updated.emit(_tick_countdown(delta))
	if _remaining <= 0.0:
		request_state(GamePhase.Phase.BUY)
