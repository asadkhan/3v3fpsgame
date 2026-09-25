class_name HudPlayerStatus
extends Control
## The local player's own numbers, along the bottom of the screen: health and
## the Echo Field on the left, the weapon and its ammunition on the right.
## Full-screen and click-through; the two clusters are pinned to the corners.

var _health: Label
var _health_bar: ProgressBar
var _name: Label
var _ability_key: Label
var _ability_fill: ProgressBar
var _ability_state: Label
var _ammo: Label
var _reserve: Label
var _weapon_name: Label
var _reload: Label
var _credits: Label
var _slots: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_left()
	_build_right()


func _build_left() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.pin(panel, Vector2(0.0, 1.0), 24, -120, 360, -24)
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var health_column := VBoxContainer.new()
	health_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(health_column)
	_name = UITheme.label("", UITheme.SIZE_SMALL, UITheme.TEXT_DIM)
	_health = UITheme.label("100", UITheme.SIZE_HUGE - 12, UITheme.TEXT)
	_credits = UITheme.label("", UITheme.SIZE_SMALL, UITheme.GOOD)
	UITheme.pin(_credits, Vector2(0.0, 1.0), 26, -150, 360, -126)
	add_child(_credits)
	_health_bar = _bar(UITheme.TEXT)
	health_column.add_child(_name)
	health_column.add_child(_health)
	health_column.add_child(_health_bar)

	var ability := VBoxContainer.new()
	ability.custom_minimum_size = Vector2(76, 0)
	ability.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ability)
	_ability_key = UITheme.label("F", UITheme.SIZE_LARGE, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_ability_state = UITheme.label("ECHO", UITheme.SIZE_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_ability_fill = _bar(UITheme.ACCENT)
	ability.add_child(_ability_key)
	ability.add_child(_ability_state)
	ability.add_child(_ability_fill)


func _build_right() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.pin(panel, Vector2(1.0, 1.0), -300, -120, -24, -24)
	add_child(panel)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	_weapon_name = UITheme.label("", UITheme.SIZE_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	column.add_child(_weapon_name)

	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(ammo_row)
	_ammo = UITheme.label("30", UITheme.SIZE_HUGE - 12, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_reserve = UITheme.label("/ 30", UITheme.SIZE_BODY, UITheme.TEXT_DIM)
	_reserve.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_END
	ammo_row.add_child(_ammo)
	ammo_row.add_child(_reserve)

	_reload = UITheme.label("", UITheme.SIZE_SMALL, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	column.add_child(_reload)

	_slots = UITheme.label("", UITheme.SIZE_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	UITheme.pin(_slots, Vector2(1.0, 1.0), -400, -150, -26, -126)
	add_child(_slots)


func _bar(colour: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	bar.add_theme_stylebox_override(&"background", back)
	bar.add_theme_stylebox_override(&"fill", fill)
	return bar


func update_view(player: Player) -> void:
	visible = player != null
	if player == null:
		return

	var health := player.state.health
	_name.text = "%s  -  %s" % [player.state.display_name, Team.side_name(player.state.team)]
	_health.text = str(health)
	_health_bar.value = float(health) / float(PlayerState.MAX_HEALTH)
	var health_colour := UITheme.TEXT
	if health <= 30:
		health_colour = UITheme.DANGER
	_health.add_theme_color_override(&"font_color", health_colour)
	(_health_bar.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color = health_colour

	var field := player.get_node_or_null(^"EchoField") as EchoField
	if field != null:
		if field.is_active:
			_ability_state.text = "ACTIVE"
			_ability_fill.value = field.time_remaining / maxf(field.duration, 0.01)
		elif field.is_on_cooldown():
			_ability_state.text = "%ds" % ceili(field.cooldown * (1.0 - field.get_cooldown_progress()))
			_ability_fill.value = field.get_cooldown_progress()
		else:
			_ability_state.text = "ECHO"
			_ability_fill.value = 1.0
		var ability_ready := not field.is_active and not field.is_on_cooldown()
		_ability_key.add_theme_color_override(&"font_color", UITheme.ACCENT if ability_ready else UITheme.TEXT_DIM)

	_credits.text = "%d CREDITS" % player.state.credits
	var primary := player.loadout.primary_data()
	var primary_text := ("1  %s" % primary.display_name.to_upper()) if primary != null else "1  -"
	var sidearm_text := "2  %s" % WeaponCatalog.sidearm().display_name.to_upper()
	if player.loadout.held_slot == PlayerLoadout.SLOT_PRIMARY and primary != null:
		primary_text = "[%s]" % primary_text
	else:
		sidearm_text = "[%s]" % sidearm_text
	_slots.text = "%s     %s" % [primary_text, sidearm_text]

	var weapon := player.weapon
	if weapon == null or weapon.data == null:
		_weapon_name.text = ""
		_ammo.text = "-"
		_reserve.text = ""
		_reload.text = ""
		return
	_weapon_name.text = weapon.data.display_name.to_upper()
	_ammo.text = str(weapon.ammo_in_magazine)
	_reserve.text = " / %d" % weapon.data.magazine_size if weapon.infinite_reserve \
		else " / %d" % weapon.reserve_ammo
	var low := weapon.ammo_in_magazine <= int(weapon.data.magazine_size * 0.25)
	_ammo.add_theme_color_override(&"font_color", UITheme.DANGER if low else UITheme.TEXT)
	if weapon.is_reloading:
		_reload.text = "RELOADING"
	elif weapon.ammo_in_magazine == 0:
		_reload.text = "PRESS R TO RELOAD"
	else:
		_reload.text = ""
