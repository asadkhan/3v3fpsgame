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
	_status_label.text = ""


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
	if NetworkManager.is_online:
		NetworkManager.leave_game()
	GameManager.change_state(GamePhase.Phase.LOBBY)


func _on_host_pressed() -> void:
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
