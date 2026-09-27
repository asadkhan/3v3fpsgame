extends Control
## title screen: host a match, join one, or quit.
##
## the important part is the connection flow: join_game() returns before the
## connection is actually up, so moving to the lobby has to wait for the
## join_succeeded signal instead of happening right away.

@onready var _address_edit: LineEdit = %AddressEdit
@onready var _name_edit: LineEdit = %NameEdit
@onready var _status_label: Label = %StatusLabel

## guards the join-succeeded handler so a late success from an abandoned
## attempt can't drag us into the lobby.
var _awaiting_join: bool = false


func _ready() -> void:
	# coming back from a match leaves the mouse wherever the freed player left
	# it - usually captured, which makes every button unclickable.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	NetworkManager.join_succeeded.connect(_on_join_succeeded)
	NetworkManager.join_failed.connect(_on_join_failed)

	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%OfflineButton.pressed.connect(_on_offline_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)

	_address_edit.text = NetworkManager.DEFAULT_ADDRESS
	_status_label.text = NetworkManager.last_disconnect_reason
	NetworkManager.last_disconnect_reason = ""

	theme = UITheme.build()
	_style()
	_build_backdrop()
	_name_edit.text = NetworkManager.local_display_name()
	_build_profile_card()
	_intro()


## fonts and colours for the scene's labels.
func _style() -> void:
	%Title.text = UITheme.GAME_TITLE
	%Title.add_theme_font_override(&"font", UITheme.heading_font())
	%Title.add_theme_font_size_override(&"font_size", 104)
	%Title.add_theme_color_override(&"font_color", UITheme.TEXT)
	%Title.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.6))
	%Title.add_theme_constant_override(&"shadow_offset_y", 4)
	%Title.add_theme_constant_override(&"shadow_outline_size", 10)
	%Subtitle.text = UITheme.GAME_TAGLINE
	_as_caption(%Subtitle, UITheme.ACCENT)
	_as_caption(%OperatorTitle, UITheme.ACCENT)
	_as_caption(%NameLabel, UITheme.TEXT_DIM)
	_as_caption(%AddressLabel, UITheme.TEXT_DIM)
	%Operator.add_theme_stylebox_override(&"panel", UITheme.glass(Color(0.025, 0.03, 0.04, 0.8), 20))
	for button: Button in [%OfflineButton, %HostButton, %JoinButton, %QuitButton]:
		button.add_theme_font_size_override(&"font_size", 24)
	_status_label.add_theme_color_override(&"font_color", UITheme.ACCENT)
	var version := UITheme.caption("V1.0  /  GODOT 4.7", Color(UITheme.TEXT_DIM, 0.6))
	UITheme.pin(version, Vector2(0.0, 1.0), 90, -44, 400, -24)
	add_child(version)


func _as_caption(label: Label, colour: Color) -> void:
	var model := UITheme.caption(label.text, colour)
	label.text = model.text
	label.add_theme_font_override(&"font", model.get_theme_font(&"font"))
	label.add_theme_font_size_override(&"font_size", model.get_theme_font_size(&"font_size"))
	label.add_theme_color_override(&"font_color", colour)
	model.free()


## menu slides in from the left, cards fade in.
func _intro() -> void:
	var column: Control = $Column
	column.modulate.a = 0.0
	column.position.x -= 40
	var tween := create_tween().set_parallel()
	tween.tween_property(column, "modulate:a", 1.0, 0.5)
	tween.tween_property(column, "position:x", column.position.x + 40, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for card: Control in [%Operator, _profile_card]:
		if card == null:
			continue
		card.modulate.a = 0.0
		tween.tween_property(card, "modulate:a", 1.0, 0.6).set_delay(0.2)


const BACKDROP_MAP := preload("res://scenes/maps/meridian.tscn")

## slow ground-level dolly shots through Meridian, cut between like a trailer:
## [camera from, camera to, look-at from, look-at to]. each lasts SHOT_SECONDS.
const SHOTS := [
	[Vector3(-25, 1.4, 26), Vector3(-25, 1.6, 12), Vector3(-24, 1.2, -10), Vector3(-22, 1.0, -20)],
	[Vector3(-4, 1.1, 30), Vector3(3, 1.3, 30), Vector3(18, 2.5, 20), Vector3(22, 3.0, 8)],
	[Vector3(-14, 1.7, -24), Vector3(-22, 1.9, -22), Vector3(-28, 1.5, -12), Vector3(-30, 1.8, -4)],
	[Vector3(0, 1.3, 22), Vector3(0, 1.4, 8), Vector3(0, 1.8, -20), Vector3(0, 2.2, -30)],
	[Vector3(24, 1.5, -12), Vector3(18, 1.7, -14), Vector3(12, 1.2, -28), Vector3(20, 1.4, -30)],
]
const SHOT_SECONDS := 11.0

var _orbit_camera: Camera3D
var _shot: int = 0
var _shot_time: float = 0.0


## a live view of the map behind the menu: Meridian in its own world with a
## camera circling above it, dimmed on the left where the text sits.
func _build_backdrop() -> void:
	var container := SubViewportContainer.new()
	container.name = "Backdrop"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	move_child(container, 0)

	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(viewport)
	viewport.add_child(BACKDROP_MAP.instantiate())
	_orbit_camera = Camera3D.new()
	_orbit_camera.fov = 62.0
	viewport.add_child(_orbit_camera)
	_orbit_camera.make_current()
	_update_orbit()

	# readability gradient over the backdrop: dark on the left under the
	# menu, clear on the right.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.02, 0.04, 0.92))
	gradient.set_color(1, Color(0.02, 0.02, 0.04, 0.15))
	gradient.add_point(0.55, Color(0.02, 0.02, 0.04, 0.55))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	$Background.texture = texture
	move_child($Background, 1)


func _process(delta: float) -> void:
	if _orbit_camera == null:
		return
	_shot_time += delta
	if _shot_time > SHOT_SECONDS:
		_shot_time = 0.0
		_shot = (_shot + 1) % SHOTS.size()
	_update_orbit()


func _update_orbit() -> void:
	var shot: Array = SHOTS[_shot]
	var t := smoothstep(0.0, 1.0, _shot_time / SHOT_SECONDS)
	_orbit_camera.position = (shot[0] as Vector3).lerp(shot[1], t)
	_orbit_camera.look_at((shot[2] as Vector3).lerp(shot[3], t), Vector3.UP)


## level, title, progress to next level and career numbers - the first
## thing on screen so every match visibly moves something.
var _profile_card: PanelContainer = null


func _build_profile_card() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", UITheme.glass(Color(0.025, 0.03, 0.04, 0.8), 20))
	UITheme.pin(card, Vector2(1.0, 0.0), -420, 60, -60, 60)
	add_child(card)
	_profile_card = card
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	card.add_child(column)

	column.add_child(UITheme.caption("CAREER  /  " + Profile.title(), UITheme.ACCENT))
	column.add_child(UITheme.heading("LEVEL %d" % Profile.level, 40, UITheme.TEXT))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.max_value = 1.0
	bar.value = float(Profile.xp) / float(Profile.xp_for_level(Profile.level))
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.GOOD
	bar.add_theme_stylebox_override(&"background", back)
	bar.add_theme_stylebox_override(&"fill", fill)
	column.add_child(bar)
	column.add_child(UITheme.label("%d / %d XP to level %d" % [Profile.xp, Profile.xp_for_level(Profile.level),
		Profile.level + 1], UITheme.SIZE_SMALL, UITheme.TEXT_DIM))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	column.add_child(spacer)
	if Profile.matches == 0:
		column.add_child(UITheme.label("Play your first match to start\nearning XP and career stats.",
			UITheme.SIZE_SMALL, UITheme.TEXT_DIM))
		return
	for line: Array in [
		["Matches", "%d   (%d%% won)" % [Profile.matches, Profile.win_rate()]],
		["K / D", "%.2f   (%d / %d)" % [Profile.kd_ratio(), Profile.kills, Profile.deaths]],
		["Headshot kills", "%d%%" % Profile.headshot_rate()],
		["Aces  /  Clutches", "%d  /  %d" % [Profile.aces, Profile.clutches]],
		["Match MVPs", str(Profile.mvps)],
		["Best ACS", str(Profile.best_score)],
	]:
		var row := HBoxContainer.new()
		var key := UITheme.label(line[0], UITheme.SIZE_SMALL, UITheme.TEXT_DIM)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		row.add_child(UITheme.label(line[1], UITheme.SIZE_SMALL, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
		column.add_child(row)


## stores the typed name before heading into a match, host or offline.
func _commit_name() -> void:
	var clean := NetworkManager.sanitize_name(_name_edit.text)
	if not clean.is_empty():
		GameConfig.display_name = clean


## single-player, no session at all. handy for testing movement/weapon feel
## without a second instance running. leaves any existing session first, so
## pressing this after a failed join doesn't drop you in with a stale peer.
func _on_offline_pressed() -> void:
	_commit_name()
	if NetworkManager.is_online:
		NetworkManager.leave_game()
	GameManager.change_state(GamePhase.Phase.LOBBY)


func _on_host_pressed() -> void:
	_commit_name()
	# hosting is live the instant create_server() succeeds, so we can jump
	# straight to the lobby.
	if NetworkManager.is_online:
		NetworkManager.leave_game()
	var error := NetworkManager.host_game()
	if error != OK:
		_status_label.text = "Could not host: %s" % error_string(error)
		return
	GameManager.change_state(GamePhase.Phase.LOBBY)


func _on_join_pressed() -> void:
	_commit_name()
	var address := _address_edit.text.strip_edges()
	if address.is_empty():
		address = NetworkManager.DEFAULT_ADDRESS

	if NetworkManager.is_online:
		NetworkManager.leave_game()

	_status_label.text = "Connecting to %s..." % address
	_awaiting_join = true

	# returns before the connection is up: join_failed() fires immediately
	# on failure, _on_join_succeeded() fires later on success.
	if NetworkManager.join_game(address) != OK:
		_awaiting_join = false


func _on_join_succeeded() -> void:
	if not _awaiting_join:
		return
	_awaiting_join = false
	GameManager.change_state(GamePhase.Phase.LOBBY)


func _on_join_failed(reason: String) -> void:
	_awaiting_join = false
	_status_label.text = reason


func _on_quit_pressed() -> void:
	# routed through GameManager so quitting always tears the network down.
	GameManager.quit_game()
