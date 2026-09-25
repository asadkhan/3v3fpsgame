class_name HudMatchEndPanel
extends PanelContainer
## The result screen: VICTORY or DEFEAT from this player's side, the final
## score, and what to do next - a rematch (host) or back to the menu (anyone).

var _result: Label
var _score: Label
var _hint: Label
var _rematch: Button


func _ready() -> void:
	UITheme.pin(self, Vector2(0.5, 0.5), -260, -130, 260, 130)
	visible = false

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 10)
	add_child(column)
	_result = UITheme.label("", UITheme.SIZE_HUGE, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_score = UITheme.label("", UITheme.SIZE_LARGE, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint = UITheme.label("", UITheme.SIZE_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_result)
	column.add_child(_score)
	column.add_child(_hint)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 12)
	column.add_child(buttons)
	_rematch = Button.new()
	_rematch.text = "REMATCH  (Enter)"
	_rematch.focus_mode = Control.FOCUS_NONE
	_rematch.pressed.connect(rematch)
	buttons.add_child(_rematch)
	var leave := Button.new()
	leave.text = "LEAVE"
	leave.focus_mode = Control.FOCUS_NONE
	leave.pressed.connect(GameManager.return_to_menu)
	buttons.add_child(leave)


## Host only: back to the lobby with the same players, score reset.
func rematch() -> void:
	if GameManager.is_in(GamePhase.Phase.MATCH_END) and GameManager.is_authority():
		GameManager.change_state(GamePhase.Phase.LOBBY)


func update_view(local_team: int) -> void:
	visible = GameManager.is_in(GamePhase.Phase.MATCH_END)
	if not visible:
		return
	var winner := GameManager.match_state.winning_team
	if winner == Team.Side.NONE:
		_result.text = "MATCH OVER"
		_result.add_theme_color_override(&"font_color", UITheme.TEXT)
	elif local_team == Team.Side.NONE:
		_result.text = "%s WINS" % Team.side_name(winner)
		_result.add_theme_color_override(&"font_color", UITheme.team_colour(winner))
	elif winner == local_team:
		_result.text = "VICTORY"
		_result.add_theme_color_override(&"font_color", UITheme.GOOD)
	else:
		_result.text = "DEFEAT"
		_result.add_theme_color_override(&"font_color", UITheme.DANGER)
	_score.text = GameManager.match_state.score_line()
	_rematch.visible = GameManager.is_authority()
	_hint.text = "" if GameManager.is_authority() else "Waiting for the host to start a rematch..."
