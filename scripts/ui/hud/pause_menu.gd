class_name HudPauseMenu
extends PanelContainer
## The Esc menu: shown whenever the mouse is released during a match. The game
## keeps running underneath - this is a multiplayer game, nothing pauses.
## Holds the two settings players reach for first (sensitivity and field of
## view, saved through [GameConfig]) and the way out of the match.

var _sensitivity: HSlider
var _sensitivity_value: Label
var _fov: HSlider
var _fov_value: Label
var _aim_mode: Button
var _volume: HSlider
var _volume_value: Label
var _head_bob: Button


func _ready() -> void:
	UITheme.pin(self, Vector2(0.5, 0.5), -200, -160, 200, -160)
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	add_child(column)
	column.add_child(UITheme.label("MENU", UITheme.SIZE_LARGE, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))

	var resume := Button.new()
	resume.text = "RESUME"
	resume.focus_mode = Control.FOCUS_NONE
	resume.pressed.connect(_on_resume)
	column.add_child(resume)

	var sens_row := _slider_row(column, "Sensitivity")
	_sensitivity = sens_row[0]
	_sensitivity_value = sens_row[1]
	_sensitivity.min_value = 0.05
	_sensitivity.max_value = 2.0
	_sensitivity.step = 0.01
	_sensitivity.value = GameConfig.mouse_sensitivity
	_sensitivity.value_changed.connect(_on_sensitivity)

	var volume_row := _slider_row(column, "Volume")
	_volume = volume_row[0]
	_volume_value = volume_row[1]
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.01
	_volume.value = GameConfig.master_volume
	_volume.value_changed.connect(func(value: float) -> void:
		GameConfig.master_volume = value
		_refresh_values())

	var fov_row := _slider_row(column, "Field of view")
	_fov = fov_row[0]
	_fov_value = fov_row[1]
	_fov.min_value = 70
	_fov.max_value = 110
	_fov.step = 1
	_fov.value = GameConfig.field_of_view
	_fov.value_changed.connect(_on_fov)
	_refresh_values()

	_aim_mode = Button.new()
	_aim_mode.focus_mode = Control.FOCUS_NONE
	_aim_mode.pressed.connect(_on_aim_mode)
	column.add_child(_aim_mode)
	_refresh_aim_mode()

	_head_bob = Button.new()
	_head_bob.focus_mode = Control.FOCUS_NONE
	_head_bob.pressed.connect(func() -> void:
		GameConfig.head_bob = not GameConfig.head_bob
		_refresh_aim_mode())
	column.add_child(_head_bob)
	_refresh_aim_mode()

	var leave := Button.new()
	leave.text = "LEAVE MATCH"
	leave.focus_mode = Control.FOCUS_NONE
	leave.pressed.connect(GameManager.return_to_menu)
	column.add_child(leave)

	column.add_child(UITheme.label("F3: developer panels", UITheme.SIZE_SMALL, UITheme.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_CENTER))


func _slider_row(parent: Control, title: String) -> Array:
	var header := HBoxContainer.new()
	parent.add_child(header)
	var name_label := UITheme.label(title, UITheme.SIZE_SMALL, UITheme.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var value_label := UITheme.label("", UITheme.SIZE_SMALL, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	header.add_child(value_label)
	var slider := HSlider.new()
	slider.focus_mode = Control.FOCUS_NONE
	parent.add_child(slider)
	return [slider, value_label]


func _refresh_values() -> void:
	_sensitivity_value.text = "%.2f" % _sensitivity.value
	_fov_value.text = "%d" % int(_fov.value)
	if _volume != null:
		_volume_value.text = "%d%%" % int(_volume.value * 100.0)


func _on_sensitivity(value: float) -> void:
	GameConfig.mouse_sensitivity = value
	_refresh_values()


func _on_fov(value: float) -> void:
	GameConfig.field_of_view = value
	_refresh_values()


func _on_aim_mode() -> void:
	GameConfig.aim_toggle = not GameConfig.aim_toggle
	_refresh_aim_mode()


func _refresh_aim_mode() -> void:
	_aim_mode.text = "AIM (right mouse):  %s" % ("TOGGLE" if GameConfig.aim_toggle else "HOLD")
	if _head_bob != null:
		_head_bob.text = "CAMERA BOB:  %s" % ("ON" if GameConfig.head_bob else "OFF")


func _on_resume() -> void:
	var player := NetworkManager.get_local_player()
	if player != null:
		player.capture_mouse(true)


## Visible while the mouse is free, except where another panel already offers
## the same way out (the match result screen).
func update_view() -> void:
	var in_match := not GameManager.is_in(GamePhase.Phase.MAIN_MENU)
	visible = in_match and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
		and not GameManager.is_in(GamePhase.Phase.MATCH_END)
