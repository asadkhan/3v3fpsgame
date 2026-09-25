class_name DevNetworkUI
extends CanvasLayer
## Development-only host / join panel: the four buttons you need to get two or
## three instances of the game talking to each other, and nothing else.
##
## [b]This whole file is disposable and Chapter 8 deletes it.[/b] It is a
## separate scene for the same reason [DevOverlay] is: removing it must not touch
## the permanent router, the match scene, or the [NetworkManager] that actually
## does the work. Every button here calls one [NetworkManager] method and does
## no networking of its own - if this file could host a game, deleting it would
## be a design change rather than a cleanup.
##
## ## Why a UI at all
##
## A development lobby is the minimum needed to *see* a network working, and
## seeing it working is the only way to know the authority rules are right. A
## roster that says "peer 3  Player 3  BRAVO  alive" answers at a glance the
## questions a logging statement would take a console window and a timestamp to
## answer. Chapter 8 replaces it with a real lobby, which will have team select
## and a ready-up state, and which is allowed to be a real design rather than
## three buttons and a text field.
##
## ## Why it sits in a [CanvasLayer] on its own
##
## It is added to the router, like [DevOverlay], so it draws over the 3D world
## from wherever the current phase routes to and survives the scene changing
## underneath it. A UI that had to be instanced into the match scene would be
## destroyed every time the phase changed, which is the moment you most want to
## press Leave.

## Port offered by default. Matches [constant NetworkManager.DEFAULT_PORT], but
## is editable here because the whole point of a development lobby is to run
## two games on one machine, and the second one needs to be able to aim at a
## different port if the first is still lingering in TIME_WAIT.
const DEFAULT_PORT := 27015

## Last address typed, kept across a phase change so a failed join can be
## retried without retyping it.
const ADDRESS_KEY := "user://dev_network_address"

@onready var _address_edit: LineEdit = $Panel/Rows/AddressRow/AddressEdit
@onready var _host_button: Button = $Panel/Rows/Buttons/HostButton
@onready var _join_button: Button = $Panel/Rows/Buttons/JoinButton
@onready var _leave_button: Button = $Panel/Rows/Buttons/LeaveButton
@onready var _status_label: Label = $Panel/Rows/StatusLabel
@onready var _local_label: Label = $Panel/Rows/LocalLabel
@onready var _roster_label: Label = $Panel/Rows/RosterLabel

## Last thing that happened, shown under the buttons. A connection that
## silently does nothing is the single most confusing failure in a network
## chapter, and the fix is almost always visible in one line of text.
var _last_event: String = ""


func _ready() -> void:
	# Survives a paused tree, so Leave still works if someone pauses to look at
	# the roster.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_address_edit.text = _load_address()
	_address_edit.text_submitted.connect(_on_address_submitted)

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
		# Hosting while already in a session would replace the peer underneath
		# live bodies and every synchroniser authority with it, leaving a set of
		# players that exist and are connected to nobody. Leaving first is
		# slower but it is the only version that ends in a state anybody can
		# reason about.
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


## Enter in the address box is Join. Without this, joining needs the mouse, and
## the mouse is captured by the player as soon as the match scene appears -
## so pressing Enter is the difference between a working two-instance test and
## a person alt-tabbing to click a button.
func _on_address_submitted(_text: String) -> void:
	_on_join_pressed()


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
	# Wording matters here. The host leaving is the most common thing to happen
	# during a development session, and a client that says only "disconnected"
	# reads as a crash.
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
	# The roster is the useful part and it is only a few lines, so the event is
	# appended under it rather than replacing it. A panel that only ever shows
	# the newest line loses the history you actually wanted - "join failed" then
	# "connected" is a sequence, and seeing only the second is misleading.
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
