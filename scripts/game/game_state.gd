class_name GameState
extends RefCounted
## base class for every phase of the game. one instance of a subclass exists
## for the active phase; GameManager creates it, ticks it, and throws it away.
##
## keeps GameManager from turning into a pile of "if phase == ..." branches -
## each phase owns its own enter/tick/exit, so adding one is a new file.
##
## adding a phase:
## [codeblock]
## 1. Create a script in res://scripts/game/states/ extending this class.
## 2. Override enter() / update() / exit() with whatever the phase needs.
## 3. Add the phase to GamePhase.Phase.
## 4. Register the script and its transitions in GameManager.
## [/codeblock]
##
## states are plain objects, not nodes - no children, no own _process, no
## timers. anything that needs the scene tree goes through game_manager.

## the active GameManager.
##
## left untyped on purpose: typing it GameManager is a circular reference
## (GameManager preloads every state script), typing it Node breaks reads
## like game_manager.match_state. get_match() hands back a typed result
## so nothing downstream has to care.
var game_manager

## seconds left on this state's countdown, or 0 if untimed.
## lives here instead of duplicated in every timed phase; subclasses just
## call _start_countdown() / _tick_countdown().
var _remaining: float = 0.0

## wall-clock moment (Time.get_ticks_msec) the countdown hits zero. counting
## against the real clock instead of summing deltas keeps a 20s buy phase
## actually 20 seconds even through a stutter or a clamped frame.
var _deadline_ms: int = 0


func _init(manager = null) -> void:
	game_manager = manager


## called once when this state becomes active. previous is null on the very
## first transition. use for teardown-order-sensitive stuff; normal cleanup
## goes in exit().
func enter(_previous: GameState) -> void:
	pass


## called once when this state stops being active. next_state is null if
## the game is shutting down. always release timers/connections here.
func exit(_next_state: GameState) -> void:
	pass


## called every frame while this state is active, even while the tree is
## paused - that's what keeps buy-phase/round-end countdowns running when
## gameplay is frozen.
func update(_delta: float) -> void:
	pass


## the match in progress.
func get_match() -> MatchState:
	return game_manager.match_state as MatchState


## rules for the match in progress - round length, buy window, rounds to win.
func get_rules() -> MatchRules:
	return game_manager.match_rules as MatchRules


# --- Countdown helpers ----------------------------------------------------
# shared by every timed phase so each one is just a couple lines in enter()
# and update(), no bookkeeping of its own.

## seconds left on this phase's countdown, or 0 if untimed. for the HUD.
func get_time_remaining() -> float:
	return _remaining


## arms the countdown for `seconds`. call from enter().
func _start_countdown(seconds: float) -> void:
	_remaining = maxf(seconds, 0.0)
	_deadline_ms = Time.get_ticks_msec() + int(_remaining * 1000.0)


## updates the countdown from the real clock, returns time left (never below
## zero). call from update(), then check _remaining against zero.
func _tick_countdown(_delta: float) -> float:
	_remaining = maxf(float(_deadline_ms - Time.get_ticks_msec()) / 1000.0, 0.0)
	return _remaining


## asks GameManager to move to `phase`. always go through this instead of
## calling change_state directly. returns false if refused.
func request_state(phase: int) -> bool:
	if game_manager == null:
		push_error("GameState.request_state() called before a GameManager was attached.")
		return false
	# a client's copy of a timed phase still counts down for display, but the
	# host decides when it actually ends - stay quiet here so clients don't spam
	# refused-transition logs once their timer hits 0.
	if not is_authority():
		return false
	return game_manager.change_state(phase)


## whether this machine decides the match (offline, or host). states gate
## score/round changes on this since a client gets those from the host.
func is_authority() -> bool:
	return game_manager != null and game_manager.is_authority()
