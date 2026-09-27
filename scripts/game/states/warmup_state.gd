extends GameState
## WARMUP - the one-off countdown before the very first round, so players get
## a moment to load in and get their bearings.
##
## only ever runs once per match. every round after goes ROUND_END -> BUY
## directly.
##
## exposes countdown_updated instead of making the UI poll - same pattern as
## every timed phase: the state owns the clock, UI just listens. clock itself
## comes from GameState; this file only decides what happens at zero.

## emitted every frame with the seconds left, for the HUD countdown
signal countdown_updated(remaining: float)


func enter(_previous: GameState) -> void:
	_start_countdown(get_rules().warmup_seconds)
	countdown_updated.emit(_remaining)


func update(delta: float) -> void:
	countdown_updated.emit(_tick_countdown(delta))
	if _remaining <= 0.0:
		request_state(GamePhase.Phase.BUY)
