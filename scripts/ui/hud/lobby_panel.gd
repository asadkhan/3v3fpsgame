class_name HudLobbyPanel
extends PanelContainer
## Shown in the LOBBY phase: the map, both rosters, and - for the host - the
## button that starts the match. Offline it explains the practice range.

var _title: Label
var _alpha_list: VBoxContainer
var _bravo_list: VBoxContainer
var _status: Label
var _start: Button
var _teams: HBoxContainer
var _refresh_left: float = 0.0


func _ready() -> void:
	# Zero height: the container grows to fit its content instead of padding it.
	UITheme.pin(self, Vector2(0.0, 0.5), 24, -160, 380, -160)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	add_child(column)
	_title = UITheme.label("LOBBY  -  MERIDIAN", UITheme.SIZE_LARGE, UITheme.ACCENT)
	column.add_child(_title)

	_teams = HBoxContainer.new()
	_teams.add_theme_constant_override(&"separation", 24)
	column.add_child(_teams)
	_alpha_list = _team_column(_teams, Team.Side.ALPHA, "ALPHA  (attack)")
	_bravo_list = _team_column(_teams, Team.Side.BRAVO, "BRAVO  (defend)")

	_status = UITheme.label("", UITheme.SIZE_SMALL, UITheme.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(320, 0)
	column.add_child(_status)

	_start = Button.new()
	_start.text = "START MATCH  (Enter)"
	_start.focus_mode = Control.FOCUS_NONE
	_start.pressed.connect(start_match)
	column.add_child(_start)


func _team_column(parent: Control, side: int, heading: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	column.add_child(UITheme.label(heading, UITheme.SIZE_SMALL, UITheme.team_colour(side)))
	var list := VBoxContainer.new()
	column.add_child(list)
	return list


## Host only. Starts the warmup, which leads into round one.
func start_match() -> void:
	if GameManager.is_in(GamePhase.Phase.LOBBY) and NetworkManager.is_online and NetworkManager.is_host:
		GameManager.change_state(GamePhase.Phase.WARMUP)


func update_view(delta: float) -> void:
	visible = GameManager.is_in(GamePhase.Phase.LOBBY)
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.25

	if not NetworkManager.is_online:
		_title.text = "PRACTICE RANGE"
		_teams.visible = false
		_status.text = "Offline practice: targets, a turret and movement tests. " \
			+ "Host or join from the main menu to play a match."
		_start.visible = false
		return

	_title.text = "LOBBY  -  MERIDIAN"
	_teams.visible = true
	var alpha: Array[String] = []
	var bravo: Array[String] = []
	for peer_id in NetworkManager.players.peer_ids():
		var entry := NetworkManager.players.get_entry(peer_id)
		var line := String(entry.get("display_name", "?"))
		if peer_id == NetworkManager.local_peer_id:
			line += "  (you)"
		if peer_id == NetworkManager.SERVER_PEER_ID:
			line += "  [host]"
		if int(entry.get("team", Team.Side.NONE)) == Team.Side.BRAVO:
			bravo.append(line)
		else:
			alpha.append(line)
	_fill(_alpha_list, alpha)
	_fill(_bravo_list, bravo)

	var count := NetworkManager.get_player_count()
	var cap := NetworkManager.get_max_players()
	_start.visible = NetworkManager.is_host
	if NetworkManager.is_host:
		_status.text = "%d / %d players. Start when everyone is in. Esc frees the mouse." % [count, cap]
		if alpha.is_empty() or bravo.is_empty():
			_status.text += "\nOne side is empty - rounds only end on the timer."
	else:
		_status.text = "%d / %d players. Waiting for the host to start the match..." % [count, cap]


func _fill(list: VBoxContainer, names: Array) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for n in names:
		list.add_child(UITheme.label(n, UITheme.SIZE_BODY, UITheme.TEXT))
	if names.is_empty():
		list.add_child(UITheme.label("-", UITheme.SIZE_BODY, UITheme.TEXT_DIM))
