class_name DevOverlay
extends CanvasLayer
## Development-only readout: the current game state, the scene currently routed
## to, and whether networking is active - plus buttons that force the state
## machine into any legal phase.
##
## [b]This whole file is disposable and is meant to be deleted before release.
## It is deliberately isolated in its own scene and script so removing it does
## not touch the permanent router. To remove it from a build, either set
## [code]Main.DEV_OVERLAY_ENABLED[/code] to false, or delete
## [code]scenes/ui/dev_overlay.tscn[/code], [code]scripts/ui/dev_overlay.gd[/code]
## and the four lines in [code]main.gd[/code] that reference them. Nothing
## outside this script should ever come to depend on it.
##
## It is a [CanvasLayer] rather than a bare [Control] so it can be added
## straight to the router and still draw over the 3D world without the router
## having to own a canvas of its own.

## One line explaining what each phase is for, shown under the phase name.
const PHASE_NOTES := {
	GamePhase.Phase.MAIN_MENU: "Nobody connected, nothing loaded. This is the only phase you start in.",
	GamePhase.Phase.LOBBY: "A fresh match. Peers show up here; the host starts the warm-up. Chapter 2 shows the playable playtest in this phase.",
	GamePhase.Phase.WARMUP: "One-off countdown before the very first round. Only runs once per match.",
	GamePhase.Phase.BUY: "Freeze / buy window. The round counter ticks up here, not when combat starts.",
	GamePhase.Phase.ROUND_ACTIVE: "Live round. Weapons and damage arrive in Chapter 3.",
	GamePhase.Phase.ROUND_END: "Round resolved: score credited, then next round or the match result.",
	GamePhase.Phase.MATCH_END: "Match won. Stays here until someone picks a rematch or quits.",
}

## The node the router swaps real screens into. Assigned by [Main] before this
## overlay is added to the tree, so the overlay can report which screen is live
## without the two of them having to stay in sync through signals.
var screen_host: Node = null

@onready var _phase_label: Label = %PhaseLabel
@onready var _note_label: Label = %NoteLabel
@onready var _scene_label: Label = %SceneLabel
@onready var _net_label: Label = %NetLabel
@onready var _roster_label: Label = %RosterLabel
@onready var _rules_label: Label = %RulesLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _player_label: Label = %PlayerLabel
@onready var _fps_label: Label = %FpsLabel
@onready var _transition_box: HBoxContainer = %TransitionBox

## Buttons built for the current phase, so they can be cleared each refresh.
var _transition_buttons: Array[Button] = []

## Cached from the tree each refresh. Looked up by group rather than by asking
## the playtest for it, so the overlay keeps working for a player that some
## future scene spawned somewhere else entirely.
var _player: Player = null


func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)
	EventBus.player_joined.connect(_on_player_joined)
	EventBus.player_left.connect(_on_player_left)
	NetworkManager.roster_updated.connect(_refresh_network)

	# The game is already in a phase by the time this loads, so render once
	# here instead of only reacting to future changes.
	refresh(GameManager.current_phase)


## The player readout and the frame counter change every frame; the phase,
## rules and score do not. Keeping them on separate paths means the expensive
## half - rebuilding the transition buttons - is not run 60 times a second.
func _process(_delta: float) -> void:
	_refresh_live()


func _refresh_live() -> void:
	_fps_label.text = "FPS %d   |   physics %d Hz   |   %d players" % [
		Engine.get_frames_per_second(),
		Engine.physics_ticks_per_second,
		get_tree().get_nodes_in_group(&"players").size(),
	]

	# The player this machine drives, not merely the first one in the tree.
	#
	# Chapter 2 could use "first node in the players group" because there was
	# exactly one. Chapter 4 cannot: the group holds up to six bodies and the
	# one the overlay reports has to be the one this machine is looking through
	# the camera of, or the position and movement state on screen describe
	# somebody else entirely.
	_player = NetworkManager.get_local_player()
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"players") as Player
	if _player == null:
		_player_label.text = "No player in the scene."
		return

	var position := _player.global_position
	_player_label.text = "%s\nx %6.2f   y %6.2f   z %6.2f\n%s\n%s" % [
		Player.state_name(_player.get_movement_state()),
		position.x, position.y, position.z,
		_player.debug_line(),
		_player.debug_line_combat(),
	]


## Re-reads everything from the autoloads. Split from [method _on_state_changed]
## so it can be called on its own, which is what makes this class testable
## without driving the state machine.
func refresh(_phase: int = -1) -> void:
	_phase_label.text = GamePhase.phase_name(GameManager.current_phase)
	_note_label.text = PHASE_NOTES.get(GameManager.current_phase, "")
	_scene_label.text = _describe_current_scene()
	_refresh_network()
	_rules_label.text = "Rules: %s" % GameManager.match_rules.summary()
	_score_label.text = "Round %d   |   %s" % [
		GameManager.match_state.round_number,
		GameManager.match_state.score_line(),
	]
	_build_transition_buttons(GameManager.current_phase)


## The scene currently routed to by [Main], or a note that none is. This is the
## "which screen am I actually looking at" answer when a phase has several
## nodes and the phase name alone is not enough to tell them apart.
func _describe_current_scene() -> String:
	if screen_host == null:
		return "(overlay not wired to a screen host)"

	for child in screen_host.get_children():
		# An outgoing screen stays a child until the end of the frame it was
		# freed in. Reporting it here would make the overlay claim the old
		# scene is still live for one frame after every phase change.
		if child.is_queued_for_deletion():
			continue
		var path: String = child.scene_file_path
		if not path.is_empty():
			return path
		return "%s (%s)" % [child.name, child.get_class()]
	return "(none - this phase has no screen of its own)"


func _refresh_network() -> void:
	if not NetworkManager.is_online:
		_net_label.text = "Inactive - offline"
		return

	var role := "Host (server)" if NetworkManager.is_host else "Client"
	_net_label.text = "%s  |  %d / %d players  |  peer id %d" % [
		role,
		NetworkManager.get_player_count(),
		NetworkManager.get_max_players(),
		NetworkManager.local_peer_id,
	]

	# The roster, one line per peer. On a client this is the host's list, which
	# is the point: a client that reported only its own view would report one
	# player and look like a working session with nobody in it.
	_roster_label.text = "\n".join(NetworkManager.players.summary_lines())


func _on_state_changed(_previous: int, current: int) -> void:
	refresh(current)


func _on_player_joined(peer_id: int, player_name: String) -> void:
	print("[DevOverlay] %s (peer %d) joined" % [player_name, peer_id])
	_refresh_network()


func _on_player_left(peer_id: int) -> void:
	print("[DevOverlay] peer %d left" % peer_id)
	_refresh_network()


func _build_transition_buttons(phase: int) -> void:
	for button in _transition_buttons:
		button.queue_free()
	_transition_buttons.clear()

	# Built from the same ALLOWED_TRANSITIONS table the machine enforces, so
	# the overlay can never offer a move that would be refused. If a phase
	# looks stuck, the bug is in the table rather than here.
	for next_phase in GameManager.get_allowed_transitions(phase):
		# A client cannot drive the match, so it is only offered the moves it
		# may actually make (leaving for the menu).
		if not GameManager.can_transition(next_phase):
			continue
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.text = GamePhase.phase_name(next_phase)
		button.pressed.connect(_on_transition_pressed.bind(next_phase))
		_transition_box.add_child(button)
		_transition_buttons.append(button)


func _on_transition_pressed(phase: int) -> void:
	GameManager.change_state(phase)
