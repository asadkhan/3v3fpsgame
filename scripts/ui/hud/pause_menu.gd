class_name HudPauseMenu
extends Control
## the esc menu: shown whenever the mouse is released during a match. the game
## keeps running underneath (it's multiplayer). blurred backdrop, big title
## and actions on the left, settings on the right, saved via GameConfig.

var _sensitivity: HSlider
var _sensitivity_value: Label
var _fov: HSlider
var _fov_value: Label
var _aim_mode: Button
var _volume: HSlider
var _volume_value: Label
var _music: HSlider
var _music_value: Label
var _head_bob: Button
var _quality: Button
var _was_visible: bool = false
var _start: Button
var _content: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	add_child(UITheme.blur_backdrop(0.5))

	_content = HBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 60)
	UITheme.pin(_content, Vector2(0.5, 0.5), -470, -250, 470, 250)
	add_child(_content)

	# left: title and the two ways out
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(340, 0)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override(&"separation", 10)
	_content.add_child(left)
	left.add_child(UITheme.caption(UITheme.GAME_TITLE, UITheme.ACCENT))
	left.add_child(UITheme.heading("PAUSED", 64, UITheme.TEXT))
	left.add_child(UITheme.rule(UITheme.ACCENT, 80, 3))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	left.add_child(gap)
	left.add_child(_button("RESUME", _on_resume))
	_start = _button("START MATCH", func() -> void:
		if GameManager.is_in(GamePhase.Phase.LOBBY) and NetworkManager.is_online and NetworkManager.is_host:
			GameManager.change_state(GamePhase.Phase.WARMUP))
	left.add_child(_start)
	left.add_child(_button("LEAVE MATCH", GameManager.return_to_menu))
	var hint := UITheme.label("F3 opens the developer panels", UITheme.SIZE_SMALL, UITheme.TEXT_DIM)
	left.add_child(hint)

	# right: settings
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override(&"panel", UITheme.glass(Color(0.025, 0.03, 0.04, 0.85), 22))
	_content.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	panel.add_child(column)

	column.add_child(UITheme.caption("GAMEPLAY", UITheme.ACCENT))
	var sens_row := _slider_row(column, "Mouse sensitivity")
	_sensitivity = sens_row[0]
	_sensitivity_value = sens_row[1]
	_sensitivity.min_value = 0.05
	_sensitivity.max_value = 2.0
	_sensitivity.step = 0.01
	_sensitivity.value = GameConfig.mouse_sensitivity
	_sensitivity.value_changed.connect(_on_sensitivity)
	_aim_mode = _button("", _on_aim_mode)
	column.add_child(_aim_mode)

	column.add_child(_spacer(6))
	column.add_child(UITheme.caption("AUDIO", UITheme.ACCENT))
	var volume_row := _slider_row(column, "Master volume")
	_volume = volume_row[0]
	_volume_value = volume_row[1]
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.01
	_volume.value = GameConfig.master_volume
	_volume.value_changed.connect(func(value: float) -> void:
		GameConfig.set_setting("audio/master_volume", value, false)
		_refresh_values())
	var music_row := _slider_row(column, "Music")
	_music = music_row[0]
	_music_value = music_row[1]
	_music.min_value = 0.0
	_music.max_value = 1.0
	_music.step = 0.01
	_music.value = GameConfig.music_volume
	_music.value_changed.connect(func(value: float) -> void:
		GameConfig.set_setting("audio/music_volume", value, false)
		_refresh_values())

	column.add_child(_spacer(6))
	column.add_child(UITheme.caption("VIDEO", UITheme.ACCENT))
	var fov_row := _slider_row(column, "Field of view")
	_fov = fov_row[0]
	_fov_value = fov_row[1]
	_fov.min_value = 70
	_fov.max_value = 110
	_fov.step = 1
	_fov.value = GameConfig.field_of_view
	_fov.value_changed.connect(_on_fov)
	_head_bob = _button("", func() -> void:
		GameConfig.head_bob = not GameConfig.head_bob
		_refresh_aim_mode())
	column.add_child(_head_bob)
	_quality = _button("", func() -> void:
		# AUTO -> LOW -> MEDIUM -> HIGH -> ULTRA -> AUTO
		var next: int = GameConfig.get_setting("video/graphics_quality") + 1
		GameConfig.set_setting("video/graphics_quality", -1 if next > GraphicsQuality.Level.ULTRA else next)
		_refresh_aim_mode())
	column.add_child(_quality)
	_refresh_values()
	_refresh_aim_mode()


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 42)
	button.pressed.connect(action)
	return button


func _spacer(height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s


func _slider_row(parent: Control, title: String) -> Array:
	# saved once the drag ends, not on every step.
	var header := HBoxContainer.new()
	parent.add_child(header)
	var name_label := UITheme.label(title, UITheme.SIZE_SMALL + 1, UITheme.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var value_label := UITheme.heading("", UITheme.SIZE_BODY, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	header.add_child(value_label)
	var slider := HSlider.new()
	slider.focus_mode = Control.FOCUS_NONE
	slider.drag_ended.connect(func(_changed: bool) -> void: GameConfig.save_settings())
	parent.add_child(slider)
	return [slider, value_label]


func _refresh_values() -> void:
	_sensitivity_value.text = "%.2f" % _sensitivity.value
	_fov_value.text = "%d" % int(_fov.value)
	_volume_value.text = "%d%%" % int(_volume.value * 100.0)
	_music_value.text = "%d%%" % int(_music.value * 100.0)


func _on_sensitivity(value: float) -> void:
	GameConfig.set_setting("input/mouse_sensitivity", value, false)
	_refresh_values()


func _on_fov(value: float) -> void:
	GameConfig.set_setting("video/field_of_view", value, false)
	_refresh_values()


func _on_aim_mode() -> void:
	GameConfig.aim_toggle = not GameConfig.aim_toggle
	_refresh_aim_mode()


func _refresh_aim_mode() -> void:
	_aim_mode.text = "AIM DOWN SIGHTS:  %s" % ("TOGGLE" if GameConfig.aim_toggle else "HOLD")
	_head_bob.text = "CAMERA BOB:  %s" % ("ON" if GameConfig.head_bob else "OFF")
	var chosen: int = GameConfig.get_setting("video/graphics_quality")
	_quality.text = "GRAPHICS:  %s" % (GraphicsQuality.NAMES[chosen] if chosen != GraphicsQuality.Level.AUTO
		else "AUTO (%s)" % GraphicsQuality.NAMES[GraphicsQuality.automatic()])


func _on_resume() -> void:
	var player := NetworkManager.get_local_player()
	if player != null:
		player.capture_mouse(true)


## visible while the mouse is free, except where another panel already
## offers the same way out (the match result screen).
func update_view() -> void:
	var in_match := not GameManager.is_in(GamePhase.Phase.MAIN_MENU)
	visible = in_match and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
		and not GameManager.is_in(GamePhase.Phase.MATCH_END)
	_start.visible = GameManager.is_in(GamePhase.Phase.LOBBY) and NetworkManager.is_online 		and NetworkManager.is_host
	if visible and not _was_visible:
		_content.modulate.a = 0.0
		create_tween().tween_property(_content, "modulate:a", 1.0, 0.15)
	_was_visible = visible
