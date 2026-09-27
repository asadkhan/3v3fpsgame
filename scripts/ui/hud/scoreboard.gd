class_name HudScoreboard
extends PanelContainer
## held-tab scoreboard: both sides, each player's level, ACS (combat score
## per round), kills, deaths, assists, alive status. sorted by combat score,
## your row highlighted. only rebuilt while visible.

const COLUMNS := ["ACS", "K", "D", "A"]
const ROW_H := 34.0

var _body: VBoxContainer
var _header: Label
var _sub: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.pin(self, Vector2(0.5, 0.5), -400, -205, 400, -205)
	add_theme_stylebox_override(&"panel", UITheme.glass(Color(0.025, 0.03, 0.04, 0.9), 22))
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	_header = UITheme.heading("", 32, UITheme.TEXT)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	_sub = UITheme.caption("", UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_sub)
	column.add_child(UITheme.rule(UITheme.ACCENT, 60, 2))
	_body = VBoxContainer.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override(&"separation", 3)
	column.add_child(_body)


func update_view(local: Player) -> void:
	if not visible:
		return
	var rounds := maxi(GameManager.match_state.round_number, 1)
	var score := GameManager.match_state
	_header.text = "ALPHA  %d  -  %d  BRAVO" % [score.get_score(Team.Side.ALPHA), score.get_score(Team.Side.BRAVO)]
	_sub.text = "ROUND %d" % rounds
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

	for side in Team.ASSIGNABLE:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		_body.add_child(gap)
		_body.add_child(_team_header(side))
		var players := NetworkManager.get_players().filter(func(p: Player) -> bool: return p.state.team == side)
		players.sort_custom(func(a: Player, b: Player) -> bool:
			return a.state.combat_score() > b.state.combat_score())
		var index := 0
		for player: Player in players:
			var values := [str(player.state.combat_score_per_round(rounds)), str(player.state.kills),
				str(player.state.deaths), str(player.state.assists)]
			_body.add_child(_row(player, NetworkManager.level_of(player.peer_id), values, player == local, index))
			index += 1
		if players.is_empty():
			_body.add_child(UITheme.label("  no players", UITheme.SIZE_SMALL, UITheme.TEXT_DIM))


func _team_header(side: int) -> Control:
	var colour := UITheme.team_colour(side)
	var strip := PanelContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UITheme.glass(Color(colour, 0.16), 12, Color(0, 0, 0, 0))
	box.border_width_left = 4
	box.border_color = colour
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	strip.add_theme_stylebox_override(&"panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)
	var attacking := GameManager.match_state.attacking_side(maxi(GameManager.match_state.round_number, 1))
	var title := UITheme.heading("%s   %s" % [Team.side_name(side), "ATTACK" if attacking == side else "DEFEND"],
		UITheme.SIZE_BODY, colour)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	for column_name in COLUMNS:
		var cell := UITheme.caption(column_name, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		cell.custom_minimum_size = Vector2(64, 0)
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cell)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(64, 0)
	row.add_child(pad)
	return strip


func _row(player: Player, level: int, values: Array, is_you: bool, index: int) -> Control:
	var strip := PanelContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.custom_minimum_size = Vector2(0, ROW_H)
	var fill := Color(UITheme.ACCENT, 0.14) if is_you else Color(1, 1, 1, 0.045 if index % 2 == 0 else 0.02)
	var box := UITheme.glass(fill, 12, Color(0, 0, 0, 0))
	if is_you:
		box.border_width_left = 2
		box.border_color = UITheme.ACCENT
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	strip.add_theme_stylebox_override(&"panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	strip.add_child(row)
	var alive := player.state.is_alive
	var colour := UITheme.ACCENT if is_you else UITheme.TEXT
	if not alive:
		colour = Color(colour, 0.45)
	var lvl := UITheme.keycap(str(level), Color(UITheme.TEXT_DIM, 0.9))
	lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lvl)
	var name_label := UITheme.heading(player.state.display_name, UITheme.SIZE_BODY, colour)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	for value in values:
		var cell := UITheme.heading(String(value), UITheme.SIZE_BODY, colour, HORIZONTAL_ALIGNMENT_RIGHT)
		cell.custom_minimum_size = Vector2(54, 0)
		row.add_child(cell)
	var status := UITheme.caption("" if alive else "DEAD", UITheme.DANGER, HORIZONTAL_ALIGNMENT_RIGHT)
	status.custom_minimum_size = Vector2(54, 0)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status)
	return strip
