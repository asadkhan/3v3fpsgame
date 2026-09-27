class_name DevOverlay
extends CanvasLayer
## dev-only readout: current game state, the scene currently routed to, and
## whether networking is active - plus buttons that force the state machine
## into any legal phase.
##
## disposable, meant to be deleted before release. set Main.DEV_OVERLAY_ENABLED
## to false, or delete this scene/script and the lines in main.gd referencing them.
##
## a CanvasLayer rather than a Control so it draws over the 3d world without
## the router needing its own canvas.

## one line explaining what each phase is for, shown under the phase name.
const PHASE_NOTES := {
	GamePhase.Phase.MAIN_MENU: "Nobody connected, nothing loaded. This is the only phase you start in.",
	GamePhase.Phase.LOBBY: "A fresh match. Peers show up here; the host starts the warm-up.",
	GamePhase.Phase.WARMUP: "One-off countdown before the very first round. Only runs once per match.",
	GamePhase.Phase.BUY: "Freeze / buy window. The round counter ticks up here, not when combat starts.",
	GamePhase.Phase.ROUND_ACTIVE: "Live round.",
	GamePhase.Phase.ROUND_END: "Round resolved: score credited, then next round or the match result.",
	GamePhase.Phase.MATCH_END: "Match won. Stays here until someone picks a rematch or quits.",
}

## the node the router swaps real screens into. assigned by Main before
## this overlay is added, so it can report the live screen without syncing
## through signals.
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

## buttons built for the current phase, cleared each refresh.
var _transition_buttons: Array[Button] = []

## cached from the tree each refresh. looked up by group rather than
## asked from the playtest, so it keeps working wherever a player is spawned.
var _player: Player = null


func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)
	EventBus.player_joined.connect(_on_player_joined)
	EventBus.player_left.connect(_on_player_left)
	NetworkManager.roster_updated.connect(_refresh_network)

	# game's already in a phase by the time this loads, so render once here
	# instead of only reacting to future changes.
	refresh(GameManager.current_phase)


## player readout and fps change every frame; phase, rules and score don't -
## keeping them separate means the expensive part (rebuilding buttons)
## doesn't run 60 times a second.
func _process(_delta: float) -> void:
	_refresh_live()


func _refresh_live() -> void:
	_fps_label.text = "FPS %d   |   physics %d Hz   |   %d players" % [
		Engine.get_frames_per_second(),
		Engine.physics_ticks_per_second,
		get_tree().get_nodes_in_group(&"players").size(),
	]

	# the player this machine drives, not just the first one in the tree -
	# the group can hold up to six bodies.
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


## re-reads everything from the autoloads. split out from _on_state_changed
## so it can be called on its own, e.g. from a test.
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


## the scene currently routed to by Main, or a note that none is.
func _describe_current_scene() -> String:
	if screen_host == null:
		return "(overlay not wired to a screen host)"

	for child in screen_host.get_children():
		# an outgoing screen stays a child until the end of the frame it
		# was freed in - skip it so we don't report a dead scene as live.
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

	# roster, one line per peer. on a client this is the host's list, which
	# is the point - a client's own view would look like an empty session.
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

	# built from the same ALLOWED_TRANSITIONS table the machine enforces,
	# so the overlay can never offer a move that would be refused.
	for next_phase in GameManager.get_allowed_transitions(phase):
		# a client can't drive the match, so it's only offered moves it
		# can actually make (leaving for the menu).
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
