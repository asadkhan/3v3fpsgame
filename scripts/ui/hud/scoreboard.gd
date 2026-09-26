class_name HudScoreboard
extends PanelContainer
## Held-Tab scoreboard: both sides with each player's level, combat score per
## round (ACS), kills, deaths, assists and whether they are alive, sorted by
## combat score, with your own row marked. Rebuilt only while visible.

const COLUMNS := ["ACS", "K", "D", "A"]

var _body: VBoxContainer
var _header: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.pin(self, Vector2(0.5, 0.5), -380, -210, 380, -210)
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
	var rounds := maxi(GameManager.match_state.round_number, 1)
	_header.text = "%s   -   ROUND %d" % [GameManager.match_state.score_line(), rounds]
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

	for side in Team.ASSIGNABLE:
		var title := UITheme.label(Team.side_name(side), UITheme.SIZE_BODY, UITheme.team_colour(side))
		_body.add_child(title)
		_body.add_child(_row("PLAYER", COLUMNS, "", UITheme.TEXT_DIM))
		var players := NetworkManager.get_players().filter(func(p: Player) -> bool: return p.state.team == side)
		players.sort_custom(func(a: Player, b: Player) -> bool:
			return a.state.combat_score() > b.state.combat_score())
		for player: Player in players:
			var label := "[%d] %s%s" % [NetworkManager.level_of(player.peer_id), player.state.display_name,
				"  (you)" if player == local else ""]
			var values := [str(player.state.combat_score_per_round(rounds)), str(player.state.kills),
				str(player.state.deaths), str(player.state.assists)]
			_body.add_child(_row(label, values, "" if player.state.is_alive else "DEAD",
				UITheme.ACCENT if player == local else UITheme.TEXT))
		if players.is_empty():
			_body.add_child(_row("-", ["", "", "", ""], "", UITheme.TEXT_DIM))
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		_body.add_child(spacer)


func _row(player_name: String, values: Array, status: String, colour: Color) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UITheme.label(player_name, UITheme.SIZE_BODY, colour)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	for value in values:
		var cell := UITheme.label(String(value), UITheme.SIZE_BODY, colour, HORIZONTAL_ALIGNMENT_RIGHT)
		cell.custom_minimum_size = Vector2(62, 0)
		row.add_child(cell)
	var status_label := UITheme.label(status, UITheme.SIZE_SMALL, UITheme.DANGER, HORIZONTAL_ALIGNMENT_RIGHT)
	status_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(status_label)
	return row
