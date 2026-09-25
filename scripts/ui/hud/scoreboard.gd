class_name HudScoreboard
extends PanelContainer
## Held-Tab scoreboard: both sides, each player's kills, deaths and whether
## they are alive, with your own row marked. Rebuilt only while visible.

var _body: VBoxContainer
var _header: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.pin(self, Vector2(0.5, 0.5), -330, -200, 330, -200)
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_header = UITheme.label("", UITheme.SIZE_LARGE, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_header)
	_body = VBoxContainer.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body)


func update_view(local: Player) -> void:
	if not visible:
		return
	_header.text = "%s   -   ROUND %d" % [GameManager.match_state.score_line(),
		maxi(GameManager.match_state.round_number, 1)]
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

	for side in Team.ASSIGNABLE:
		var title := UITheme.label(Team.side_name(side), UITheme.SIZE_BODY, UITheme.team_colour(side))
		_body.add_child(title)
		_body.add_child(_row("PLAYER", "K", "D", "", UITheme.TEXT_DIM))
		var players := NetworkManager.get_players().filter(func(p: Player) -> bool: return p.state.team == side)
		players.sort_custom(func(a: Player, b: Player) -> bool: return a.state.kills > b.state.kills)
		for player: Player in players:
			var you := " (you)" if player == local else ""
			_body.add_child(_row(player.state.display_name + you, str(player.state.kills),
				str(player.state.deaths), "" if player.state.is_alive else "DEAD",
				UITheme.ACCENT if player == local else UITheme.TEXT))
		if players.is_empty():
			_body.add_child(_row("-", "", "", "", UITheme.TEXT_DIM))
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		_body.add_child(spacer)


func _row(player_name: String, kills: String, deaths: String, status: String, colour: Color) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UITheme.label(player_name, UITheme.SIZE_BODY, colour)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	for value in [kills, deaths]:
		var cell := UITheme.label(value, UITheme.SIZE_BODY, colour, HORIZONTAL_ALIGNMENT_RIGHT)
		cell.custom_minimum_size = Vector2(60, 0)
		row.add_child(cell)
	var status_label := UITheme.label(status, UITheme.SIZE_SMALL, UITheme.DANGER, HORIZONTAL_ALIGNMENT_RIGHT)
	status_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(status_label)
	return row
