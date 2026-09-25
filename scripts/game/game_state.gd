class_name GameState
extends RefCounted
## Base class for every phase of the game. One instance of a subclass exists
## for the active phase; [GameManager] creates it, ticks it, and throws it away.
##
## The point of this pattern is that [GameManager] never contains a chain of
## [code]if phase == ...[/code] branches. Each phase owns its own enter, tick
## and exit behaviour, so adding one is a new file rather than an edit to a
## switch statement that six other systems have to be read alongside.
##
## [b]Adding a phase:[/b]
## [codeblock]
## 1. Create a script in res://scripts/game/states/ extending this class.
## 2. Override enter() / update() / exit() with whatever the phase needs.
## 3. Add the phase to GamePhase.Phase.
## 4. Register the script and its transitions in GameManager.
## [/codeblock]
##
## [b]Note:[/b] states are plain objects, not nodes. They cannot own children,
## run their own [code]_process[/code], or create timers by themselves. Anything
## that needs to spawn something should ask [member game_manager], which is the
## one place allowed to touch the scene tree. Keeping states node-free is what
## lets the tick stay in one predictable place.

## The active [GameManager].
##
## Deliberately left untyped. Two obvious alternatives both fail: typing it as
## [GameManager] is a circular reference, because [GameManager] preloads every
## state script; typing it as [Node] makes the compiler reject reads such as
## [code]game_manager.match_state[/code], since [Node] has no such property.
## An untyped reference resolves at runtime, and [method get_match] hands back
## a properly typed result so nothing downstream has to care.
var game_manager

## Seconds left on this state's countdown, or 0 for states that are not timed.
##
## Every timed phase used to declare its own copy of this alongside its own
## copy of the decrement-and-check loop. That is four copies of the same five
## lines, and a bug fixed in one of them would have left the other three
## quietly wrong. The countdown lives here instead; subclasses call
## [method _start_countdown] and [method _tick_countdown].
##
## No [method exit] reset is needed. [GameManager] builds a fresh state object
## on every transition, so this always starts at zero for a new phase.
var _remaining: float = 0.0


func _init(manager = null) -> void:
	game_manager = manager


## Called once, when this state becomes the active phase.
## [param previous] is the state being left, or [code]null[/code] on the very
## first transition. Use it for teardown-order-sensitive logic; normal cleanup
## belongs in [method exit].
func enter(_previous: GameState) -> void:
	pass


## Called once, when this state stops being the active phase.
## [param next_state] is the state being entered, or [code]null[/code] if the
## game is shutting down. Always release timers and connections here.
func exit(_next_state: GameState) -> void:
	pass


## Called every frame by [GameManager] while this state is active, including
## while the tree is paused - that is what makes buy-phase and round-end
## countdowns keep running when gameplay is frozen.
func update(_delta: float) -> void:
	pass


## The match in progress. This is the single accessor states need for it, so
## the untyped [member game_manager] is reached through in exactly one place.
func get_match() -> MatchState:
	return game_manager.match_state as MatchState


## The rules for the match in progress - round length, buy window, rounds to
## win. Phases read their duration from here rather than hard-coding it, so
## retuning a match is an edit to [code]data/match_rules.tres[/code].
func get_rules() -> MatchRules:
	return game_manager.match_rules as MatchRules


# --- Countdown helpers ----------------------------------------------------
# Shared by every timed phase. A timed state is then three lines in
# [method enter] and three in [method update], with no bookkeeping of its own.

## Seconds left on this phase's countdown, or 0 for untimed phases. For the HUD.
func get_time_remaining() -> float:
	return _remaining


## Arms the countdown for [param seconds]. Call from [method enter].
func _start_countdown(seconds: float) -> void:
	_remaining = maxf(seconds, 0.0)


## Advances the countdown by [param delta] and returns the time left, which
## never goes below zero. Call from [method update], then compare
## [member _remaining] against zero to detect the frame the phase should end.
func _tick_countdown(delta: float) -> float:
	_remaining = maxf(_remaining - delta, 0.0)
	return _remaining


## Asks [GameManager] to move to [param phase]. Always go through this rather
## than calling [code]change_state[/code] yourself, so the transition table is
## enforced in one place. Returns false if the move was rejected.
func request_state(phase: int) -> bool:
	if game_manager == null:
		push_error("GameState.request_state() called before a GameManager was attached.")
		return false
	# A client's copy of a timed phase still counts down for display, but the
	# host decides when it ends. Returning quietly here is what stops every
	# client logging a refused transition on every frame after its timer hits 0.
	if not is_authority():
		return false
	return game_manager.change_state(phase)


## Whether this machine decides the match (offline, or the host). States gate
## any change to the score or round counter on this, because on a client those
## numbers arrive from the host instead.
func is_authority() -> bool:
	return game_manager != null and game_manager.is_authority()
