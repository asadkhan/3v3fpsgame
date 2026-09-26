class_name SpectatorCamera
extends Camera3D
## After you die: a moment on your own death camera, then a first-person view
## through a living teammate's eyes. Left click cycles to the next teammate.
##
## Teammates only, never enemies - watching the other side would hand a dead
## player information to call out. Local and purely visual: nothing here is
## replicated or authoritative. It follows the replicated position, facing and
## pitch of the watched body ([method Player.get_spectator_view]), smoothed so
## the 20 Hz updates read as continuous motion.
##
## Lives in the match scene as [code]Spectator[/code]; the HUD finds it through
## [constant GROUP] to show who is being watched.

const GROUP := &"spectator"

## How long the death camera plays before switching to a teammate.
const DEATH_CAM_SECONDS := 2.0

## How quickly the view catches up with the watched player's replicated view.
const FOLLOW_SHARPNESS := 18.0

## The teammate being watched, or null.
var target: Player = null

var _dead_for: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	fov = GameConfig.field_of_view
	current = false
	GameConfig.setting_changed.connect(func(key: String, value: Variant) -> void:
		if key == "video/field_of_view":
			fov = float(value))


## Whether the screen is currently showing a teammate's view.
func is_spectating() -> bool:
	return current and target != null and is_instance_valid(target)


func _process(delta: float) -> void:
	var local := NetworkManager.get_local_player()
	if local == null or local.state.is_alive:
		_dead_for = 0.0
		_release(local)
		return

	_dead_for += delta
	if _dead_for < DEATH_CAM_SECONDS:
		return

	# A freed target (the watched teammate disconnected) must be dropped before
	# it reaches the typed parameter below, which would reject it every frame.
	if target != null and not is_instance_valid(target):
		target = null
	if not _is_valid_target(target, local):
		target = _cycle(local, 0)
	if target == null:
		# Nobody left to watch: stay on the death camera.
		_release(local)
		return

	var wanted := target.get_spectator_view()
	if not current:
		global_transform = wanted
		make_current()
	else:
		var weight := 1.0 - exp(-FOLLOW_SHARPNESS * delta)
		global_position = global_position.lerp(wanted.origin, weight)
		var from := global_transform.basis.get_rotation_quaternion()
		var to := wanted.basis.get_rotation_quaternion()
		global_basis = Basis(from.slerp(to, weight))


func _unhandled_input(event: InputEvent) -> void:
	if not is_spectating():
		return
	if event.is_action_pressed(&"fire"):
		var local := NetworkManager.get_local_player()
		var next := _cycle(local, 1)
		if next != null:
			target = next
			global_transform = target.get_spectator_view()
		get_viewport().set_input_as_handled()


## Living teammates in a stable order, and the one [param step] places after
## the current target.
func _cycle(local: Player, step: int) -> Player:
	if local == null:
		return null
	var mates: Array[Player] = []
	for player in NetworkManager.get_players():
		if _is_valid_target(player, local):
			mates.append(player)
	if mates.is_empty():
		return null
	mates.sort_custom(func(a: Player, b: Player) -> bool: return a.peer_id < b.peer_id)
	var index := mates.find(target)
	if index < 0:
		return mates[0]
	return mates[(index + step) % mates.size()]


func _is_valid_target(player: Player, local: Player) -> bool:
	return player != null and is_instance_valid(player) and not player.is_queued_for_deletion() \
		and player != local and player.state.is_alive and player.state.team == local.state.team


## Hands the screen back to the local player's own camera.
func _release(local: Player) -> void:
	if not current:
		return
	clear_current(false)
	target = null
	if local != null:
		local.make_view_current()
