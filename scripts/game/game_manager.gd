extends Node
## the central game state machine. autoload: GameManager.
##
## answers "what phase are we in" and owns what that phase needs: the
## current GameState and the MatchState. doesn't know about weapons, movement,
## rendering or UI.
##
## phases have to happen in a fixed order and never overlap (no reloading
## during round-end, no combat mid-buy), so the allowed order lives in one
## table (ALLOWED_TRANSITIONS) instead of being scattered around.
##
## check the phase: GameManager.is_in(GamePhase.Phase.ROUND_ACTIVE)
## react to changes: GameManager.state_changed.connect(...)
## request a change: change_state(), or GameState.request_state() from inside
## a state. anything not in the transition table is refused with a warning.

## fires after a phase change fully completes - phase is updated and the
## previous state already ran its exit.
signal state_changed(previous_phase: int, current_phase: int)

## the phase currently running.
var current_phase: int = GamePhase.Phase.MAIN_MENU

## the state object for current_phase. never null after startup.
var current_state: GameState = null

## tunable match rules, loaded from res://data/match_rules.tres.
##
## declared before match_state on purpose: initialisers run top to bottom
## and the match is built from these rules.
var match_rules: MatchRules = MatchRules.load_default()

## score, round number and match winner. one match at a time, owned here.
var match_state: MatchState = MatchState.new(match_rules)

## phase -> the script that implements it. register new phases here.
const STATE_SCRIPTS := {
	GamePhase.Phase.MAIN_MENU: preload("res://scripts/game/states/main_menu_state.gd"),
	GamePhase.Phase.LOBBY: preload("res://scripts/game/states/lobby_state.gd"),
	GamePhase.Phase.WARMUP: preload("res://scripts/game/states/warmup_state.gd"),
	GamePhase.Phase.BUY: preload("res://scripts/game/states/buy_state.gd"),
	GamePhase.Phase.ROUND_ACTIVE: preload("res://scripts/game/states/round_active_state.gd"),
	GamePhase.Phase.ROUND_END: preload("res://scripts/game/states/round_end_state.gd"),
	GamePhase.Phase.MATCH_END: preload("res://scripts/game/states/match_end_state.gd"),
}

## which phase may follow which. anything not listed here is refused - the
## single source of truth for match flow.
const ALLOWED_TRANSITIONS := {
	# only one way out of the title screen.
	GamePhase.Phase.MAIN_MENU: [GamePhase.Phase.LOBBY],

	# host can start, or everyone can bail to the menu. jumping straight to
	# MATCH_END lets a host end a lobby that never got going.
	GamePhase.Phase.LOBBY: [
		GamePhase.Phase.WARMUP,
		GamePhase.Phase.MATCH_END,
		GamePhase.Phase.MAIN_MENU,
	],

	GamePhase.Phase.WARMUP: [
		GamePhase.Phase.BUY,
		GamePhase.Phase.MATCH_END,
	],

	# buy always becomes live combat. ending early is for admin (someone
	# left, host gave up), not a normal round.
	GamePhase.Phase.BUY: [
		GamePhase.Phase.ROUND_ACTIVE,
		GamePhase.Phase.MATCH_END,
	],

	GamePhase.Phase.ROUND_ACTIVE: [
		GamePhase.Phase.ROUND_END,
		GamePhase.Phase.MATCH_END,
	],

	# normal loop: back to buy for the next round, or out to the match result.
	GamePhase.Phase.ROUND_END: [
		GamePhase.Phase.BUY,
		GamePhase.Phase.MATCH_END,
	],

	# rematch, or out to the title screen.
	GamePhase.Phase.MATCH_END: [
		GamePhase.Phase.LOBBY,
		GamePhase.Phase.MAIN_MENU,
	],
}


func _ready() -> void:
	# buy window and round-end pause need to keep ticking while gameplay
	# itself is frozen, so this autoload opts out of the pause tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enter_phase(GamePhase.Phase.MAIN_MENU, null)


func _process(delta: float) -> void:
	# every state gets its tick from here instead of having its own _process.
	if current_state != null:
		current_state.update(delta)


## moves to phase if the transition is allowed. returns false if refused
## (the normal case for anything not in ALLOWED_TRANSITIONS).
func change_state(phase: int) -> bool:
	if phase == current_phase:
		return false

	# a client never drives the match - it can only leave for the title
	# screen or step from there into a lobby it just joined. every other
	# phase arrives from the host via _receive_phase.
	if not is_authority() and not _client_may_request(phase):
		push_warning("GameManager: %s -> %s refused; the host owns the match flow." % [
			GamePhase.phase_name(current_phase), GamePhase.phase_name(phase),
		])
		return false

	if not phase in get_allowed_transitions(current_phase):
		push_warning("GameManager: %s -> %s is not an allowed transition." % [
			GamePhase.phase_name(current_phase), GamePhase.phase_name(phase),
		])
		return false

	_enter_phase(phase, current_state)
	return true


## whether current_phase is phase.
func is_in(phase: int) -> bool:
	return current_phase == phase


## whether current -> phase is permitted. cheap, side-effect free - for
## greying out buttons.
func can_transition(phase: int) -> bool:
	if not is_authority() and not _client_may_request(phase):
		return false
	return phase in get_allowed_transitions(current_phase)


## whether this machine decides match flow: always offline, host only when
## online. timed states still tick on clients for countdown display, but
## only the authority acts when one expires.
func is_authority() -> bool:
	return not NetworkManager.is_online or NetworkManager.is_host


## the two moves a client can make for itself.
func _client_may_request(phase: int) -> bool:
	if phase == GamePhase.Phase.MAIN_MENU:
		return true
	return current_phase == GamePhase.Phase.MAIN_MENU and phase == GamePhase.Phase.LOBBY


## every phase reachable in one step from phase. used by the debug UI to
## build buttons from the same table the machine enforces.
func get_allowed_transitions(phase: int) -> Array:
	return ALLOWED_TRANSITIONS.get(phase, [])


## one-line summary of the current phase, for the debug UI and logs.
func describe_phase() -> String:
	return "%s (round %d, %s)" % [
		GamePhase.phase_name(current_phase),
		match_state.round_number,
		match_state.score_line(),
	]


## leaves whatever is happening for the title screen. always allowed, from
## any phase, on any machine - a player must never get trapped in a match -
## so it skips ALLOWED_TRANSITIONS entirely. entering MAIN_MENU ends any
## network session (see the main menu state).
func return_to_menu() -> void:
	if current_phase == GamePhase.Phase.MAIN_MENU:
		return
	_enter_phase(GamePhase.Phase.MAIN_MENU, current_state)


## disconnects from any session and quits. routed through here so leaving
## always tears the network down, no matter who asked.
func quit_game() -> void:
	NetworkManager.leave_game()
	get_tree().quit()


## the actual work of a transition, kept private so it's never called
## without the table having been checked first.
func _enter_phase(phase: int, previous: GameState) -> void:
	var previous_phase := current_phase

	var script: Script = STATE_SCRIPTS[phase]
	var next_state: GameState = script.new(self)

	# exit before enter, each side gets the other, so a state can clean up
	# against what's replacing it instead of guessing.
	if current_state != null:
		current_state.exit(next_state)

	current_state = next_state
	current_phase = phase
	next_state.enter(previous)

	state_changed.emit(previous_phase, phase)
	print("[Game] %s -> %s  |  %s" % [
		GamePhase.phase_name(previous_phase),
		GamePhase.phase_name(phase),
		describe_phase(),
	])

	# host tells every client. checked after enter, because entering
	# MAIN_MENU leaves the session - clients learn about it from the
	# disconnect instead.
	if NetworkManager.is_online and NetworkManager.is_host:
		_receive_phase.rpc(current_phase, match_state.to_dict(), current_state._remaining)


# --- Replication ------------------------------------------------------------

## host only. brings one peer up to date - used when a client finishes
## loading its match scene, so a late joiner lands in the right phase.
func send_snapshot_to(peer_id: int) -> void:
	if not (NetworkManager.is_online and NetworkManager.is_host):
		return
	_receive_phase.rpc_id(peer_id, current_phase, match_state.to_dict(), current_state._remaining)


## applies the host's phase, score and countdown on a client.
##
## bypasses ALLOWED_TRANSITIONS on purpose: the host already enforced it,
## and a late joiner legitimately jumps from LOBBY straight to ROUND_ACTIVE.
## match numbers are applied before the state enters, so the enter hook's
## events carry the host's round number and score.
@rpc("authority", "call_remote", "reliable")
func _receive_phase(phase: int, match_data: Dictionary, remaining: float) -> void:
	if multiplayer.is_server():
		return
	match_state.apply_dict(match_data)
	if phase != current_phase:
		_enter_phase(phase, current_state)
	current_state._start_countdown(remaining)
