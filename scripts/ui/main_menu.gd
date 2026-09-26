extends Control
## Title screen: host a match, join one, or quit.
##
## This is the real screen for [b]MAIN_MENU[/b] and the first of the
## [constant Main.SCREENS] entries. It is intentionally plain - default Godot
## controls, no styling - because presentation is Chapter 8's job and anything
## pretty added now would just be thrown away.
##
## Its only real content is the connection flow, which is the part that has to
## be right: [method NetworkManager.join_game] returns before the connection
## is actually established, so the move into the lobby has to wait for
## [signal NetworkManager.join_succeeded] rather than happening immediately.

@onready var _address_edit: LineEdit = %AddressEdit
@onready var _name_edit: LineEdit = %NameEdit
@onready var _status_label: Label = %StatusLabel

## Guards the join-succeeded handler so a late success from an abandoned
## attempt cannot drag us into the lobby.
var _awaiting_join: bool = false


func _ready() -> void:
	# Coming back here from a match leaves the pointer wherever the freed player
	# last put it - usually captured, which makes every button unclickable.
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
	%Title.text = UITheme.GAME_TITLE
	%Title.add_theme_font_size_override(&"font_size", UITheme.SIZE_HUGE + 16)
	%Title.add_theme_color_override(&"font_color", UITheme.ACCENT)
	%Title.add_theme_constant_override(&"outline_size", 10)
	%Subtitle.text = UITheme.GAME_TAGLINE
	%Subtitle.add_theme_color_override(&"font_color", UITheme.TECH)
	%Subtitle.add_theme_font_size_override(&"font_size", UITheme.SIZE_BODY)
	_build_backdrop()
	_name_edit.text = NetworkManager.local_display_name()
	_build_profile_card()


const BACKDROP_MAP := preload("res://scenes/maps/meridian.tscn")

## Seconds per full orbit of the backdrop camera.
const ORBIT_SECONDS := 90.0

var _orbit_camera: Camera3D
var _orbit_angle: float = 0.6


## A live view of the map behind the menu: Meridian in its own world, with a
## camera circling high above it, dimmed on the left where the text sits. Sets
## the tone - this is the place you are about to fight over - before a single
## button is pressed.
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
	_orbit_camera.fov = 55.0
	viewport.add_child(_orbit_camera)
	_orbit_camera.make_current()
	_update_orbit()

	# The old flat background becomes a readability gradient over the view:
	# dark on the left under the menu, clear on the right.
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
	_orbit_angle += TAU * delta / ORBIT_SECONDS
	_update_orbit()


func _update_orbit() -> void:
	var radius := 58.0
	_orbit_camera.position = Vector3(cos(_orbit_angle) * radius, 30.0, sin(_orbit_angle) * radius)
	_orbit_camera.look_at(Vector3(0.0, 0.0, -6.0), Vector3.UP)


## Your level, title, progress to the next level and career numbers - the
## first thing on screen, so every match visibly moves something.
func _build_profile_card() -> void:
	var card := PanelContainer.new()
	UITheme.pin(card, Vector2(0.0, 0.5), 40, -170, 360, -170)
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	card.add_child(column)

	column.add_child(UITheme.label(Profile.title().to_upper(), UITheme.SIZE_SMALL, UITheme.ACCENT))
	column.add_child(UITheme.label("LEVEL %d" % Profile.level, UITheme.SIZE_LARGE + 6, UITheme.TEXT))
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


## Stores the typed name before any path into a match, so the host - or the
## local body offline - is given it.
func _commit_name() -> void:
	var clean := NetworkManager.sanitize_name(_name_edit.text)
	if not clean.is_empty():
		GameConfig.display_name = clean


## Single-player, no session at all.
##
## Not an afterthought. The offline path is the one every automated Chapter 2
## and Chapter 3 test runs through, and it is also the fastest way to work on
## movement or weapon feel without a second instance to keep alive. It was a
## second button in Chapter 1 but became unreachable once Chapter 2 booted
## straight into the playtest; with the menu as the front door again, it needs
## to be back.
##
## Any existing session is left first, so pressing this after a failed join
## does not drop you into a lobby with a stale peer underneath.
func _on_offline_pressed() -> void:
	_commit_name()
	if NetworkManager.is_online:
		NetworkManager.leave_game()
	GameManager.change_state(GamePhase.Phase.LOBBY)


func _on_host_pressed() -> void:
	_commit_name()
	# A host is connected the instant create_server() succeeds, so the lobby
	# can be entered straight away.
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

	# Returns before the connection is up. On failure join_failed() fires
	# immediately; on success _on_join_succeeded() fires later.
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
	# Routed through GameManager so leaving always tears the network down.
	GameManager.quit_game()
