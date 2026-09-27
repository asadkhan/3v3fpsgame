class_name DevNetworkUI
extends CanvasLayer
## dev-only host/join panel: the buttons you need to get two or three game
## instances talking to each other, nothing else.
##
## disposable, gets deleted eventually. separate scene so removing it never
## touches the router, match scene, or NetworkManager. every button just
## calls one NetworkManager method.
##
## sits in its own CanvasLayer on the router, like DevOverlay, so it draws
## over the 3d world and survives scene changes underneath it.

## port offered by default, matches NetworkManager.DEFAULT_PORT. editable
## here since running two instances on one machine sometimes needs a
## different port if the first is still in TIME_WAIT.
const DEFAULT_PORT := 27015

## last address typed, kept across a phase change so a failed join doesn't
## need retyping.
const ADDRESS_KEY := "user://dev_network_address"

@onready var _address_edit: LineEdit = $Panel/Rows/AddressRow/AddressEdit
@onready var _host_button: Button = $Panel/Rows/Buttons/HostButton
@onready var _join_button: Button = $Panel/Rows/Buttons/JoinButton
@onready var _leave_button: Button = $Panel/Rows/Buttons/LeaveButton
@onready var _status_label: Label = $Panel/Rows/StatusLabel
@onready var _local_label: Label = $Panel/Rows/LocalLabel
@onready var _roster_label: Label = $Panel/Rows/RosterLabel

## last thing that happened, shown under the buttons.
var _last_event: String = ""


func _ready() -> void:
	# survives a paused tree, so Leave still works while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_address_edit.text = _load_address()
	_address_edit.text_submitted.connect(_on_address_submitted)

	for button in [_host_button, _join_button, _leave_button]:
		button.focus_mode = Control.FOCUS_NONE
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)

	NetworkManager.hosting_started.connect(_on_hosting_started)
	NetworkManager.join_succeeded.connect(_on_join_succeeded)
	NetworkManager.join_failed.connect(_on_join_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.roster_updated.connect(_refresh)

	_refresh()


# --- Buttons --------------------------------------------------------------

func _on_host_pressed() -> void:
	if NetworkManager.is_online:
		# hosting while already in a session would orphan every live body's
		# authority, so leave first instead.
		_set_event("Already in a session - left it, hosting now.")
		NetworkManager.leave_game()
	NetworkManager.host_game(DEFAULT_PORT)
	_save_address()


func _on_join_pressed() -> void:
	var address := _address_edit.text.strip_edges()
	if address.is_empty():
		_set_event("Type an address first.")
		return
	if NetworkManager.is_online:
		NetworkManager.leave_game()
	NetworkManager.join_game(address, DEFAULT_PORT)
	_save_address()


func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	_set_event("Left the session.")


## enter in the address box also joins, since the mouse gets captured by
## the player as soon as the match scene appears.
func _on_address_submitted(_text: String) -> void:
	_address_edit.release_focus()
	_on_join_pressed()


## address field must give up focus once back in the game, or WASD/Enter
## would type into it / resubmit it.
func _process(_delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _address_edit.has_focus():
		_address_edit.release_focus()


# --- Signals --------------------------------------------------------------

func _on_hosting_started(port: int) -> void:
	_set_event("Hosting on port %d. Start clients with Join." % port)
	_refresh()


func _on_join_succeeded() -> void:
	_set_event("Connected to %s." % _address_edit.text.strip_edges())
	_refresh()


func _on_join_failed(reason: String) -> void:
	_set_event("Join failed: %s" % reason)
	_refresh()


func _on_server_disconnected() -> void:
	# host leaving is common during dev, and just "disconnected" reads like a crash.
	_set_event("The host left. This instance is offline again.")
	_refresh()


func _on_peer_disconnected(peer_id: int) -> void:
	_set_event("Peer %d disconnected." % peer_id)


# --- Readout --------------------------------------------------------------

func _refresh() -> void:
	var online := NetworkManager.is_online
	_host_button.disabled = online
	_join_button.disabled = online
	_leave_button.disabled = not online

	_status_label.text = NetworkManager.status_line()
	_local_label.text = "local peer: %d" % NetworkManager.local_peer_id
	_roster_label.text = _roster_text()


func _roster_text() -> String:
	var lines := NetworkManager.players.summary_lines()
	if lines.is_empty():
		return "nobody connected"
	return "\n".join(lines)


func _set_event(message: String) -> void:
	_last_event = message
	print("[NetUI] ", message)
	# roster stays visible, event appended below it instead of replacing it.
	_roster_label.text = "%s\n\n%s" % [_roster_text(), _last_event]


# --- Address persistence --------------------------------------------------

func _load_address() -> String:
	if not FileAccess.file_exists(ADDRESS_KEY):
		return NetworkManager.DEFAULT_ADDRESS
	var handle := FileAccess.open(ADDRESS_KEY, FileAccess.READ)
	if handle == null:
		return NetworkManager.DEFAULT_ADDRESS
	var text := handle.get_as_text().strip_edges()
	handle.close()
	return text if not text.is_empty() else NetworkManager.DEFAULT_ADDRESS


func _save_address() -> void:
	var handle := FileAccess.open(ADDRESS_KEY, FileAccess.WRITE)
	if handle == null:
		return
	handle.store_string(_address_edit.text.strip_edges())
	handle.close()
