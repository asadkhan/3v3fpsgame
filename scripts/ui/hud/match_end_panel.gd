class_name HudMatchEndPanel
extends PanelContainer
## The result screen: VICTORY or DEFEAT from this player's side, the final
## score, the match MVP, every player's numbers, and the XP this match earned
## towards the player's profile level - then a rematch (host) or back to the
## menu (anyone).
##
## XP is recorded once per match, a moment after MATCH_END so the host's final
## stats have arrived. Only real matches pay out: online, with both sides
## populated. The practice range never does.

var _result: Label
var _score: Label
var _mvp: Label
var _table: VBoxContainer
var _xp_total: Label
var _xp_lines: Label
var _level_label: Label
var _level_bar: ProgressBar
var _hint: Label
var _rematch: Button

var _recorded: bool = false
var _record_timer: float = -1.0
var _xp_anim: Tween


func _ready() -> void:
	UITheme.pin(self, Vector2(0.5, 0.5), -420, -300, 420, -300)
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	add_child(column)
	_result = UITheme.label("", UITheme.SIZE_HUGE, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_score = UITheme.label("", UITheme.SIZE_LARGE, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_mvp = UITheme.label("", UITheme.SIZE_BODY, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_result)
	column.add_child(_score)
	column.add_child(_mvp)

	_table = VBoxContainer.new()
	_table.add_theme_constant_override(&"separation", 2)
	column.add_child(_table)

	var xp_box := HBoxContainer.new()
	xp_box.add_theme_constant_override(&"separation", 24)
	column.add_child(xp_box)
	var xp_left := VBoxContainer.new()
	xp_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_box.add_child(xp_left)
	_xp_total = UITheme.label("", UITheme.SIZE_LARGE, UITheme.GOOD)
	_level_label = UITheme.label("", UITheme.SIZE_SMALL, UITheme.TEXT)
	_level_bar = ProgressBar.new()
	_level_bar.show_percentage = false
	_level_bar.custom_minimum_size = Vector2(0, 10)
	_level_bar.max_value = 1.0
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.GOOD
	_level_bar.add_theme_stylebox_override(&"background", back)
	_level_bar.add_theme_stylebox_override(&"fill", fill)
	xp_left.add_child(_xp_total)
	xp_left.add_child(_level_label)
	xp_left.add_child(_level_bar)
	_xp_lines = UITheme.label("", UITheme.SIZE_SMALL, UITheme.TEXT_DIM)
	_xp_lines.custom_minimum_size = Vector2(300, 0)
	xp_box.add_child(_xp_lines)

	_hint = UITheme.label("", UITheme.SIZE_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
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

	GameManager.state_changed.connect(_on_phase_changed)


## Host only: back to the lobby with the same players, score reset.
func rematch() -> void:
	if GameManager.is_in(GamePhase.Phase.MATCH_END) and GameManager.is_authority():
		GameManager.change_state(GamePhase.Phase.LOBBY)


func _on_phase_changed(_previous: int, current: int) -> void:
	if current == GamePhase.Phase.MATCH_END:
		_recorded = false
		_record_timer = 0.6
		_xp_total.text = ""
		_xp_lines.text = ""
		_level_label.text = ""
		_level_bar.value = 0.0


func update_view(local_team: int, delta: float = 0.0) -> void:
	visible = GameManager.is_in(GamePhase.Phase.MATCH_END)
	if not visible:
		return
	var match_state := GameManager.match_state
	var winner := match_state.winning_team
	if winner == Team.Side.NONE:
		_set_result("MATCH OVER", UITheme.TEXT)
	elif local_team == Team.Side.NONE:
		_set_result("%s WINS" % Team.side_name(winner), UITheme.team_colour(winner))
	elif winner == local_team:
		_set_result("VICTORY", UITheme.GOOD)
	else:
		_set_result("DEFEAT", UITheme.DANGER)
	_score.text = match_state.score_line()
	_rematch.visible = GameManager.is_authority()
	_hint.text = "" if GameManager.is_authority() else "Waiting for the host to start a rematch..."
	_rebuild_table()

	if not _recorded and _record_timer >= 0.0:
		_record_timer -= delta
		if _record_timer <= 0.0:
			_recorded = true
			_record_xp(local_team)


func _set_result(text: String, colour: Color) -> void:
	_result.text = text
	_result.add_theme_color_override(&"font_color", colour)


func _mvp_player() -> Player:
	var best: Player = null
	for player in NetworkManager.get_players():
		if best == null or player.state.combat_score() > best.state.combat_score() \
				or (player.state.combat_score() == best.state.combat_score() and player.state.kills > best.state.kills):
			best = player
	return best


var _table_left: float = 0.0


func _rebuild_table() -> void:
	# Cheap to rebuild, but no need to every frame.
	_table_left -= get_process_delta_time()
	if _table_left > 0.0:
		return
	_table_left = 0.5
	for child in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	var rounds := maxi(GameManager.match_state.round_number, 1)
	var local := NetworkManager.get_local_player()
	var mvp := _mvp_player()
	_mvp.text = "MATCH MVP   %s   -   %d ACS" % [mvp.state.display_name, mvp.state.combat_score_per_round(rounds)] \
		if mvp != null and mvp.state.combat_score() > 0 else ""
	_table.add_child(_row(["PLAYER", "ACS", "K", "D", "A", "HS%", "DMG"], UITheme.TEXT_DIM))
	for side in Team.ASSIGNABLE:
		var players := NetworkManager.get_players().filter(func(p: Player) -> bool: return p.state.team == side)
		players.sort_custom(func(a: Player, b: Player) -> bool: return a.state.combat_score() > b.state.combat_score())
		for player: Player in players:
			var colour := UITheme.ACCENT if player == local else UITheme.team_colour(side)
			var tag := "  *" if player == mvp else ""
			_table.add_child(_row([
				"[%d] %s%s" % [NetworkManager.level_of(player.peer_id), player.state.display_name, tag],
				str(player.state.combat_score_per_round(rounds)), str(player.state.kills),
				str(player.state.deaths), str(player.state.assists),
				"%d%%" % player.state.headshot_percent(), str(player.state.damage_dealt)], colour))


func _row(values: Array, colour: Color) -> Control:
	var row := HBoxContainer.new()
	var first := true
	for value in values:
		var cell := UITheme.label(String(value), UITheme.SIZE_BODY - 1, colour,
			HORIZONTAL_ALIGNMENT_LEFT if first else HORIZONTAL_ALIGNMENT_RIGHT)
		if first:
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			cell.custom_minimum_size = Vector2(70, 0)
		row.add_child(cell)
		first = false
	return row


## Pays this match's XP into the profile and animates the level bar.
func _record_xp(local_team: int) -> void:
	var local := NetworkManager.get_local_player()
	var eligible := NetworkManager.is_online and local != null and local_team != Team.Side.NONE
	if eligible:
		var present := {}
		for player in NetworkManager.get_players():
			present[player.state.team] = true
		eligible = present.has(Team.Side.ALPHA) and present.has(Team.Side.BRAVO)
	if not eligible:
		_xp_total.text = "No XP in practice"
		_level_label.text = "LEVEL %d  %s" % [Profile.level, Profile.title().to_upper()]
		_level_bar.value = float(Profile.xp) / float(Profile.xp_for_level(Profile.level))
		return

	var match_state := GameManager.match_state
	var won := match_state.winning_team == local_team
	var mvp := _mvp_player()
	var result := Profile.record_match(local.state, won, match_state.get_score(local_team),
		maxi(match_state.round_number, 1), mvp == local)

	_xp_total.text = "+%d XP" % int(result["total"])
	var lines := PackedStringArray()
	for line: Array in result["lines"]:
		lines.append("%s   +%d" % [line[0], int(line[1])])
	_xp_lines.text = "\n".join(lines)
	_animate_level(int(result["level_before"]), int(result["xp_before"]), int(result["level_after"]),
		int(result["xp_after"]))


## Fills the bar from where it was to where it is now, rolling over once per
## level gained.
func _animate_level(level_before: int, xp_before: int, level_after: int, xp_after: int) -> void:
	if _xp_anim != null:
		_xp_anim.kill()
	_xp_anim = create_tween()
	var level := level_before
	_level_label.text = "LEVEL %d  %s" % [level, Profile.title_for(level).to_upper()]
	_level_bar.value = float(xp_before) / float(Profile.xp_for_level(level))
	while level < level_after:
		_xp_anim.tween_property(_level_bar, ^"value", 1.0, 0.6)
		var next := level + 1
		_xp_anim.tween_callback(func() -> void:
			_level_bar.value = 0.0
			_level_label.text = "LEVEL %d  %s   -   LEVEL UP!" % [next, Profile.title_for(next).to_upper()]
			Audio.play(&"multikill", -3.0, 0.0))
		level = next
	_xp_anim.tween_property(_level_bar, ^"value", float(xp_after) / float(Profile.xp_for_level(level_after)), 0.8)
