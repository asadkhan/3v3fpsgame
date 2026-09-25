extends Node
## The central game state machine. Registered as the [code]GameManager[/code]
## autoload.
##
## It answers one question for the rest of the game - "what phase are we in?"
## - and owns the objects that phase needs: the current [GameState] and the
## [MatchState]. That is the whole job. It deliberately does not know about
## weapons, player movement, rendering or UI.
##
## [b]Why a state machine at all:[/b] a tactical shooter has phases that must
## happen in a fixed order and must never overlap - you cannot reload during
## the round-end screen, and combat cannot begin mid-buy-phase. Expressing that
## as a table of allowed transitions ([constant ALLOWED_TRANSITIONS]) means the
## rules are written down in one readable place instead of being spread across
## whichever systems happened to call into it.
##
## [b]Reading the phase:[/b]
## [codeblock]
## if GameManager.is_in(GamePhase.Phase.ROUND_ACTIVE):
##     spawn_the_players()
## [/codeblock]
##
## [b]Reacting to the phase:[/b]
## [codeblock]
## GameManager.state_changed.connect(_on_phase_changed)
## [/codeblock]
##
## [b]Asking for a change:[/b] go through [method change_state], or from inside
## a state use [method GameState.request_state]. Transitions that are not in
## the table are refused with a warning, so a bug shows up immediately instead
## of quietly putting the game in a broken phase.

## Emitted after a phase change has fully completed, so the phase is already
## updated and the previous state has already run its exit.
signal state_changed(previous_phase: int, current_phase: int)

## The phase currently running. Always a valid [enum GamePhase.Phase].
var current_phase: int = GamePhase.Phase.MAIN_MENU

## The state object for [member current_phase]. Never null after startup.
var current_state: GameState = null

## The tunable rules for the match, loaded from
## [code]res://data/match_rules.tres[/code]. See [MatchRules] for why these are
## data rather than constants.
##
## Declared before [member match_state] on purpose: GDScript runs member
## initialisers top to bottom, and the match is built from these rules.
var match_rules: MatchRules = MatchRules.load_default()

## Score, round number and match winner. There is exactly one match at a time,
## which is why this is owned here rather than being an autoload of its own.
var match_state: MatchState = MatchState.new(match_rules)

## Phase -> the script that implements it. This is where a new phase gets
## registered; see [GameState] for the full checklist.
const STATE_SCRIPTS := {
	GamePhase.Phase.MAIN_MENU: preload("res://scripts/game/states/main_menu_state.gd"),
	GamePhase.Phase.LOBBY: preload("res://scripts/game/states/lobby_state.gd"),
	GamePhase.Phase.WARMUP: preload("res://scripts/game/states/warmup_state.gd"),
	GamePhase.Phase.BUY: preload("res://scripts/game/states/buy_state.gd"),
	GamePhase.Phase.ROUND_ACTIVE: preload("res://scripts/game/states/round_active_state.gd"),
	GamePhase.Phase.ROUND_END: preload("res://scripts/game/states/round_end_state.gd"),
	GamePhase.Phase.MATCH_END: preload("res://scripts/game/states/match_end_state.gd"),
}

## Which phase may follow which. Anything not listed here is refused.
## This table is the single source of truth for the flow of a match.
const ALLOWED_TRANSITIONS := {
	# From the title screen there is only one way out.
	GamePhase.Phase.MAIN_MENU: [GamePhase.Phase.LOBBY],

	# The host can start, or everyone can bail out to the menu. Jumping
	# straight to MATCH_END lets a host end a lobby that never got going.
	GamePhase.Phase.LOBBY: [
		GamePhase.Phase.WARMUP,
		GamePhase.Phase.MATCH_END,
		GamePhase.Phase.MAIN_MENU,
	],

	GamePhase.Phase.WARMUP: [
		GamePhase.Phase.BUY,
		GamePhase.Phase.MATCH_END,
	],

	# BUY / PREPARATION always becomes live combat. Ending early is for admin
	# (someone left, a host gave up), not for a normal round.
	GamePhase.Phase.BUY: [
		GamePhase.Phase.ROUND_ACTIVE,
		GamePhase.Phase.MATCH_END,
	],

	GamePhase.Phase.ROUND_ACTIVE: [
		GamePhase.Phase.ROUND_END,
		GamePhase.Phase.MATCH_END,
	],

	# The normal loop: back to BUY for the next round, or out to the
	# match result.
	GamePhase.Phase.ROUND_END: [
		GamePhase.Phase.BUY,
		GamePhase.Phase.MATCH_END,
	],

	# A rematch, or out to the title screen.
	GamePhase.Phase.MATCH_END: [
		GamePhase.Phase.LOBBY,
		GamePhase.Phase.MAIN_MENU,
	],
}


func _ready() -> void:
	# Phases such as the buy window and the round-end pause have to keep
	# ticking while gameplay itself is frozen, so this autoload opts out of
	# the pause tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enter_phase(GamePhase.Phase.MAIN_MENU, null)


func _process(delta: float) -> void:
	# Every state gets its tick from here, in one place, rather than each one
	# being a node with its own _process.
	if current_state != null:
		current_state.update(delta)


## Moves to [param phase] if the transition is allowed.
## Returns false if it was refused, which is the normal case for a transition
## that is not in [constant ALLOWED_TRANSITIONS].
func change_state(phase: int) -> bool:
	if phase == current_phase:
		return false

	# A client never drives the match. It may only leave for the title screen
	# or step from the title screen into a lobby it has just joined; every
	# other phase arrives from the host through [method _receive_phase].
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


## Whether [member current_phase] is [param phase].
func is_in(phase: int) -> bool:
	return current_phase == phase


## Whether a move from the current phase to [param phase] is permitted.
## Cheap and side-effect free, so UI can use it to grey out buttons.
func can_transition(phase: int) -> bool:
	if not is_authority() and not _client_may_request(phase):
		return false
	return phase in get_allowed_transitions(current_phase)


## Whether this machine decides the match flow: always offline, and only the
## host when a session is running. Timed states still tick on clients so their
## countdowns can be displayed, but only the authority acts when one expires.
func is_authority() -> bool:
	return not NetworkManager.is_online or NetworkManager.is_host


## The two local-navigation moves a client makes for itself.
func _client_may_request(phase: int) -> bool:
	if phase == GamePhase.Phase.MAIN_MENU:
		return true
	return current_phase == GamePhase.Phase.MAIN_MENU and phase == GamePhase.Phase.LOBBY


## Every phase reachable in one step from [param phase]. Used by the debug UI
## to build its buttons from the same table the machine enforces.
func get_allowed_transitions(phase: int) -> Array:
	return ALLOWED_TRANSITIONS.get(phase, [])


## A one-line summary of the current phase, for the debug UI and logs.
func describe_phase() -> String:
	return "%s (round %d, %s)" % [
		GamePhase.phase_name(current_phase),
		match_state.round_number,
		match_state.score_line(),
	]


## Leaves whatever is happening for the title screen. Always allowed, from any
## phase and on any machine - a player must never be trapped in a match - so it
## deliberately skips [constant ALLOWED_TRANSITIONS]. Entering MAIN_MENU ends
## any network session (see the main menu state).
func return_to_menu() -> void:
	if current_phase == GamePhase.Phase.MAIN_MENU:
		return
	_enter_phase(GamePhase.Phase.MAIN_MENU, current_state)


## Disconnects from any session and quits. Routed through here so that
## leaving the game always tears the network down, no matter who asked.
func quit_game() -> void:
	NetworkManager.leave_game()
	get_tree().quit()


## The actual work of a transition, kept private so it cannot be called
## without the transition table having been checked first.
func _enter_phase(phase: int, previous: GameState) -> void:
	var previous_phase := current_phase

	var script: Script = STATE_SCRIPTS[phase]
	var next_state: GameState = script.new(self)

	# Exit before enter, and hand each side the other, so a state can clean up
	# against the thing that is replacing it rather than guessing.
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

	# The host tells every client. Checked after the state has entered, because
	# entering MAIN_MENU leaves the session - there is nobody left to tell, and
	# the clients learn about it from the disconnect instead.
	if NetworkManager.is_online and NetworkManager.is_host:
		_receive_phase.rpc(current_phase, match_state.to_dict(), current_state._remaining)


# --- Replication ------------------------------------------------------------

## Host only. Brings one peer up to date - used when a client finishes loading
## its match scene, so a late joiner lands in the phase the match is actually in.
func send_snapshot_to(peer_id: int) -> void:
	if not (NetworkManager.is_online and NetworkManager.is_host):
		return
	_receive_phase.rpc_id(peer_id, current_phase, match_state.to_dict(), current_state._remaining)


## Applies the host's phase, score and countdown on a client.
##
## Bypasses [constant ALLOWED_TRANSITIONS] on purpose: the host already enforced
## the table, and a late joiner legitimately jumps from LOBBY straight into
## ROUND_ACTIVE. The match numbers are applied [b]before[/b] the state enters,
## so anything the enter hook emits carries the host's round number and score.
@rpc("authority", "call_remote", "reliable")
func _receive_phase(phase: int, match_data: Dictionary, remaining: float) -> void:
	if multiplayer.is_server():
		return
	match_state.apply_dict(match_data)
	if phase != current_phase:
		_enter_phase(phase, current_state)
	current_state._remaining = remaining
