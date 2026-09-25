class_name HudKillFeed
extends VBoxContainer
## Top-right kill feed: "Killer  [WEAPON]  Victim", team-coloured, newest at the
## top, each line fading out after a few seconds. Driven by
## [signal EventBus.player_died], which is raised on every machine.

const MAX_ENTRIES := 5
const ENTRY_LIFETIME := 6.0
const FADE_TIME := 0.6


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.pin(self, Vector2(1.0, 0.0), -440, 16, -16, 260)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override(&"separation", 4)
	EventBus.player_died.connect(_on_player_died)


func _on_player_died(victim_id: int, killer_id: int, headshot: bool) -> void:
	var victim := NetworkManager.get_player_for(victim_id)
	var killer := NetworkManager.get_player_for(killer_id) if killer_id != EventBus.INVALID_PEER else null
	var local := NetworkManager.get_local_player()

	var text := ""
	if killer != null:
		var weapon_name := "KILLED"
		if killer.weapon != null and killer.weapon.data != null:
			weapon_name = killer.weapon.data.display_name.to_upper()
		text += "%s  [color=#%s]%s%s[/color]  " % [_name_bbcode(killer), UITheme.TEXT_DIM.to_html(false),
			weapon_name, "  (HS)" if headshot else ""]
	else:
		text += "[color=#%s]ELIMINATED[/color]  " % UITheme.TEXT_DIM.to_html(false)
	text += _name_bbcode(victim, victim_id)

	var involves_me := local != null and (local == killer or local == victim)
	_add_entry(text, involves_me)


func _name_bbcode(player: Player, fallback_id: int = 0) -> String:
	if player == null:
		return NetworkManager.players.display_name_of(fallback_id)
	var colour := UITheme.team_colour(player.state.team)
	return "[color=#%s]%s[/color]" % [colour.to_html(false), player.state.display_name]


func _add_entry(bbcode: String, highlight: bool) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	if highlight:
		var box := StyleBoxFlat.new()
		box.bg_color = UITheme.PANEL
		box.set_border_width_all(1)
		box.border_color = UITheme.ACCENT
		box.set_corner_radius_all(3)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		panel.add_theme_stylebox_override(&"panel", box)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"normal_font_size", UITheme.SIZE_SMALL + 1)
	label.add_theme_constant_override(&"outline_size", 3)
	label.add_theme_color_override(&"font_outline_color", UITheme.OUTLINE)
	label.text = bbcode
	panel.add_child(label)

	add_child(panel)
	move_child(panel, 0)
	while get_child_count() > MAX_ENTRIES:
		var oldest := get_child(get_child_count() - 1)
		remove_child(oldest)
		oldest.queue_free()

	var tween := panel.create_tween()
	tween.tween_interval(ENTRY_LIFETIME)
	tween.tween_property(panel, ^"modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(panel.queue_free)
