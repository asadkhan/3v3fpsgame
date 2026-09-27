class_name HudPlayerStatus
extends Control
## the local player's own numbers along the bottom of the screen: health,
## shield and the echo field bottom-left, loadout and ammo bottom-right. no
## boxes - text sits on a soft corner shade. full-screen and click-through.

## health bar: slanted segments that light up to the value
class SegBar extends Control:
	var value: float = 1.0
	var colour: Color = UITheme.TEXT
	var segments: int = 10
	var slant: float = 4.0

	func _draw() -> void:
		var gap := 3.0
		var w := (size.x - gap * (segments - 1)) / segments
		for i in segments:
			var x := i * (w + gap)
			var fill := clampf(value * segments - i, 0.0, 1.0)
			var pts := PackedVector2Array([Vector2(x + slant, 0), Vector2(x + w + slant, 0),
				Vector2(x + w, size.y), Vector2(x, size.y)])
			draw_colored_polygon(pts, Color(1, 1, 1, 0.12))
			if fill > 0.0:
				var fw := w * fill
				var lit := PackedVector2Array([Vector2(x + slant, 0), Vector2(x + fw + slant, 0),
					Vector2(x + fw, size.y), Vector2(x, size.y)])
				draw_colored_polygon(lit, colour)


var _health: Label
var _health_bar: SegBar
var _shield: Label
var _shield_bar: SegBar
var _name: Label
var _ability_key: Label
var _ability_box: PanelContainer
var _ability_fill: ProgressBar
var _ability_state: Label
var _ammo: Label
var _reserve: Label
var _weapon_name: Label
var _reload: Label
var _credits: Label
var _slots: HBoxContainer
var _slot_signature: String = ""
var _last_ammo: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UITheme.corner_shade(Vector2(0, 1), Vector2(620, 260), 0.6))
	add_child(UITheme.corner_shade(Vector2(1, 1), Vector2(620, 260), 0.6))
	_build_left()
	_build_right()


func _build_left() -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override(&"separation", 2)
	UITheme.pin(column, Vector2(0.0, 1.0), 40, -200, 400, -30)
	add_child(column)

	_credits = UITheme.caption("", UITheme.GOOD)
	column.add_child(_credits)
	_name = UITheme.caption("", UITheme.TEXT_DIM)
	column.add_child(_name)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	column.add_child(row)
	_health = UITheme.heading("100", 64, UITheme.TEXT)
	row.add_child(_health)
	var tags := VBoxContainer.new()
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override(&"separation", -4)
	tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tags)
	_shield = UITheme.heading("", UITheme.SIZE_LARGE - 2, UITheme.SHIELD)
	tags.add_child(_shield)
	tags.add_child(UITheme.caption("HEALTH", UITheme.TEXT_DIM))

	# echo field: a keycap with its state and charge under it
	var ability := VBoxContainer.new()
	ability.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ability.alignment = BoxContainer.ALIGNMENT_CENTER
	ability.add_theme_constant_override(&"separation", 3)
	row.add_child(ability)
	_ability_box = PanelContainer.new()
	_ability_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_box.custom_minimum_size = Vector2(46, 42)
	_ability_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ability.add_child(_ability_box)
	_ability_key = UITheme.heading("F", UITheme.SIZE_LARGE, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_ability_key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ability_box.add_child(_ability_key)
	_ability_fill = ProgressBar.new()
	_ability_fill.show_percentage = false
	_ability_fill.max_value = 1.0
	_ability_fill.custom_minimum_size = Vector2(46, 3)
	_ability_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ability.add_child(_ability_fill)
	_ability_state = UITheme.caption("ECHO", UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	ability.add_child(_ability_state)

	_shield_bar = SegBar.new()
	_shield_bar.colour = UITheme.SHIELD
	_shield_bar.segments = 5
	_shield_bar.custom_minimum_size = Vector2(0, 4)
	_shield_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_shield_bar)
	_health_bar = SegBar.new()
	_health_bar.custom_minimum_size = Vector2(0, 9)
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_health_bar)


func _build_right() -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override(&"separation", 0)
	UITheme.pin(column, Vector2(1.0, 1.0), -560, -220, -40, -30)
	add_child(column)

	_slots = HBoxContainer.new()
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots.alignment = BoxContainer.ALIGNMENT_END
	_slots.add_theme_constant_override(&"separation", 6)
	column.add_child(_slots)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	column.add_child(gap)

	_weapon_name = UITheme.heading("", UITheme.SIZE_BODY + 4, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	column.add_child(_weapon_name)
	var line := UITheme.rule(UITheme.ACCENT, 60, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(line)

	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_row.add_theme_constant_override(&"separation", 6)
	column.add_child(ammo_row)
	_ammo = UITheme.heading("30", 72, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo.pivot_offset = Vector2(60, 50)
	_reserve = UITheme.heading("/ 30", UITheme.SIZE_LARGE - 2, UITheme.TEXT_DIM)
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ammo_row.add_child(_ammo)
	ammo_row.add_child(_reserve)

	_reload = UITheme.caption("", UITheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	column.add_child(_reload)


## rebuilds the loadout chips when what they show changes.
func _set_slots(entries: Array) -> void:
	var signature := str(entries)
	if signature == _slot_signature:
		return
	_slot_signature = signature
	for child in _slots.get_children():
		child.queue_free()
	for entry: Array in entries:
		var key: String = entry[0]
		var text: String = entry[1]
		var held: bool = entry[2]
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := UITheme.glass(Color(UITheme.ACCENT, 0.18) if held else Color(0, 0, 0, 0.35), 8,
			Color(0, 0, 0, 0))
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		if held:
			box.border_width_bottom = 2
			box.border_color = UITheme.ACCENT
		chip.add_theme_stylebox_override(&"panel", box)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 6)
		chip.add_child(row)
		row.add_child(UITheme.heading(key, UITheme.SIZE_SMALL, UITheme.ACCENT if held else UITheme.TEXT_DIM))
		row.add_child(UITheme.heading(text, UITheme.SIZE_SMALL, UITheme.TEXT if held else Color(UITheme.TEXT, 0.75)))
		_slots.add_child(chip)


## spectating: player is a teammate being watched, not this machine's own
## body, so credits, loadout and ammo aren't known here.
func update_view(player: Player, spectating: bool = false) -> void:
	visible = player != null
	if player == null:
		return

	var health := player.state.health
	_name.text = "%s  /  %s" % [player.state.display_name, Team.side_name(player.state.team)]
	_name.add_theme_color_override(&"font_color", UITheme.team_colour(player.state.team).lerp(UITheme.TEXT_DIM, 0.35))
	var shield := player.state.shield
	_shield.text = "+%d" % shield if shield > 0 else ""
	_shield_bar.visible = shield > 0
	_shield_bar.value = float(shield) / float(maxi(GameManager.match_rules.heavy_shield_amount, 1))
	_shield_bar.queue_redraw()
	_health.text = str(health)
	_health_bar.value = float(health) / float(PlayerState.MAX_HEALTH)
	var health_colour := UITheme.DANGER if health <= 30 else UITheme.TEXT
	_health.add_theme_color_override(&"font_color", health_colour)
	_health_bar.colour = health_colour
	_health_bar.queue_redraw()

	var field := player.get_node_or_null(^"EchoField") as EchoField
	if field != null:
		if field.is_active:
			_ability_state.text = "ACTIVE"
			_ability_fill.value = field.time_remaining / maxf(field.duration, 0.01)
		elif field.is_on_cooldown():
			_ability_state.text = "%dS" % ceili(field.cooldown * (1.0 - field.get_cooldown_progress()))
			_ability_fill.value = field.get_cooldown_progress()
		else:
			_ability_state.text = "ECHO"
			_ability_fill.value = 1.0
		var charged := not field.is_active and not field.is_on_cooldown()
		var tint := UITheme.ACCENT if charged else UITheme.TEXT_DIM
		_ability_key.add_theme_color_override(&"font_color", tint)
		_ability_box.add_theme_stylebox_override(&"panel", UITheme.glass(
			Color(UITheme.ACCENT, 0.14) if charged else Color(0, 0, 0, 0.4), 4, Color(tint, 0.7)))

	_credits.visible = not spectating
	_slots.visible = not spectating
	if spectating:
		_weapon_name.text = player.weapon.data.display_name.to_upper() if player.weapon and player.weapon.data else ""
		_ammo.text = "--"
		_reserve.text = ""
		_reload.text = ""
		return

	_credits.text = "%d  CREDITS" % player.state.credits
	var primary := player.loadout.primary_data()
	var held := player.loadout.held_slot
	var nades := player.loadout.grenades
	var entries := []
	entries.append(["1", primary.display_name.to_upper() if primary != null else "-",
		held == PlayerLoadout.SLOT_PRIMARY and primary != null])
	entries.append(["2", WeaponCatalog.sidearm().display_name.to_upper(),
		held != PlayerLoadout.SLOT_KNIFE and not (held == PlayerLoadout.SLOT_PRIMARY and primary != null)])
	entries.append(["3", "KNIFE", held == PlayerLoadout.SLOT_KNIFE])
	entries.append(["G", "FRAG x%d" % int(nades[PlayerLoadout.FRAG]), false])
	entries.append(["Q", "SMOKE x%d" % int(nades[PlayerLoadout.SMOKE]), false])
	_set_slots(entries)

	var weapon := player.weapon
	if weapon == null or weapon.data == null:
		_weapon_name.text = ""
		_ammo.text = "-"
		_reserve.text = ""
		_reload.text = ""
		return
	_weapon_name.text = weapon.data.display_name.to_upper()
	if weapon.data.is_melee:
		_ammo.text = "-"
		_reserve.text = ""
		_reload.text = ""
		_ammo.add_theme_color_override(&"font_color", UITheme.TEXT)
		return
	_ammo.text = str(weapon.ammo_in_magazine)
	# a small kick on every shot
	if _last_ammo >= 0 and weapon.ammo_in_magazine < _last_ammo:
		_ammo.scale = Vector2.ONE * 1.08
		create_tween().tween_property(_ammo, "scale", Vector2.ONE, 0.12)
	_last_ammo = weapon.ammo_in_magazine
	_reserve.text = "/ %d" % weapon.data.magazine_size if weapon.infinite_reserve \
		else "/ %d" % weapon.reserve_ammo
	var low := weapon.ammo_in_magazine <= int(weapon.data.magazine_size * 0.25)
	_ammo.add_theme_color_override(&"font_color", UITheme.DANGER if low else UITheme.TEXT)
	if weapon.is_reloading:
		_reload.text = "RELOADING"
	elif weapon.ammo_in_magazine == 0:
		_reload.text = "PRESS R TO RELOAD"
	else:
		_reload.text = ""
