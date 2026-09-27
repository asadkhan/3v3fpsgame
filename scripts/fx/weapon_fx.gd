class_name WeaponFx
extends Node3D
## everything about a shot that's only worth showing to the machine that
## pulled the trigger.
##
## this is the network boundary for weapon presentation: the weapon knows
## where a round stopped and emits impact_requested, then stops. this node
## decides whether to draw it. the machine that draws the effect is always
## the one whose input caused the shot, not necessarily the authoritative one.
##
## no muzzle flash/tracer logic lives here yet - flash is a light driven by
## the local trigger, and tracers spawn the same way impacts do.

## the effect spawned where a round stops.
@export var impact_scene: PackedScene

## ignore impacts further than this. legit hits at max weapon range (45m)
## are fine - this just stops a bad network origin from spamming effects.
@export var max_impact_distance: float = 100.0

@onready var _weapon: Weapon = get_parent().get_node_or_null(^"Weapon") as Weapon
## found by walking up rather than a fixed number of get_parent() hops -
## this node actually lives at Player/Head/WeaponMount/WeaponFx.
@onready var _player: Player = _find_player()

## impacts alive at once, capped so a pathological frame can't spawn
## hundreds of nodes and stall the game.
const MAX_LIVE_EFFECTS := 24

var _live: int = 0


func _ready() -> void:
	if _weapon == null:
		push_warning("WeaponFx: no sibling Weapon node; impacts will not be drawn.")
		return
	_weapon.impact_requested.connect(_on_impact_requested)

	# when this machine isn't the one that resolved the shot, the impact
	# arrives as a verdict from the host instead of this weapon's own signal.
	if _player != null:
		_player.shot_resolved.connect(_on_shot_resolved)
		_player.shot_fired.connect(_on_shot_fired)


func _find_player() -> Player:
	var node := get_parent()
	while node != null:
		if node is Player:
			return node as Player
		node = node.get_parent()
	return null


## who draws what, so every shot draws exactly once on every machine:
##
## - tracer: shooter's own machine draws it instantly on trigger pull
##   (_on_shot_fired). every other machine draws it when it learns about the
##   shot - the host from its own resolution, clients from the host's
##   verdict - plus a muzzle flash, since the shooter's viewmodel is invisible.
## - impact: drawn from whichever resolution this machine sees - the
##   weapon's own hitscan (offline/host) or the verdict (clients).
func _on_impact_requested(at: Vector3, normal: Vector3, zone: int, surface: int) -> void:
	_spawn_impact(at, normal, zone, surface)
	if _is_remote_shooter():
		_spawn_tracer(at, true)


func _on_shot_resolved(at: Vector3, normal: Vector3, _victim: Player, zone: int, _killed: bool,
		is_local: bool, surface: int) -> void:
	if is_local:
		# already drawn from the weapon's own signal - drawing again doubles it.
		return
	_spawn_impact(at, normal, zone, surface)
	if _is_remote_shooter():
		_spawn_tracer(at, true)


## this machine's own shot: trace a purely visual ray to find where the
## tracer should end. the real hit comes from the authority; this can
## disagree by a hair and nobody will notice.
func _on_shot_fired(origin: Vector3, direction: Vector3) -> void:
	if _weapon == null or _weapon.data == null:
		return
	if _weapon.data.is_melee:
		Audio.play(&"knife_heavy" if _weapon.melee_heavy else &"knife_swing", -2.0, 0.08)
		return
	Audio.play(_shot_sound(), -3.0, 0.05)
	_echo(false)
	var end := origin + direction * _weapon.data.max_range
	var space := get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(origin, end, CollisionLayers.WEAPON_MASK)
		if _player != null:
			query.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			end = hit.position
	_spawn_tracer(end, false)


## the gunshot sound for the held weapon.
func _shot_sound() -> StringName:
	var data := _weapon.data if _weapon != null else null
	if data == null:
		return &"shot_rifle"
	match data.category:
		WeaponData.Category.PISTOL:
			return &"shot_pistol"
		WeaponData.Category.SUBMACHINE_GUN:
			return &"shot_smg"
	return &"shot_burst" if data.fire_mode == WeaponData.FireMode.BURST else &"shot_rifle"


var _last_echo_ms: int = -1000


## the shot rolling back off the walls: at most one tail every quarter
## second so a spray doesn't turn into a roar.
func _echo(remote: bool, at := Vector3.ZERO) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_echo_ms < 250:
		return
	_last_echo_ms = now
	if remote:
		Audio.play_at(&"shot_echo", at, 0.0, 0.1, 160.0)
	else:
		get_tree().create_timer(0.06).timeout.connect(func() -> void: Audio.play(&"shot_echo", -18.0, 0.1))


## a round passing close to this machine's player cracks past their head.
func _crack_past_listener(from: Vector3, to: Vector3) -> void:
	var me := NetworkManager.get_local_player()
	if me == null or me == _player or not me.state.is_alive:
		return
	var eye := me.get_eye_position()
	var segment := to - from
	var t := clampf((eye - from).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
	var closest := from + segment * t
	var miss := closest.distance_to(eye)
	if miss < 3.0 and t > 0.02 and t < 0.999:
		Audio.play_at(&"bullet_crack", closest, lerpf(0.0, -12.0, miss / 3.0), 0.15, 25.0)


## a case falling from somebody else's gun.
func _eject_remote_casing(muzzle: Vector3) -> void:
	if _weapon == null or _weapon.data == null or _player == null:
		return
	var basis := _player.global_basis
	var velocity := basis * Vector3(randf_range(1.5, 2.2), randf_range(1.0, 1.6), 0.2)
	var at := muzzle + basis * Vector3(0.0, 0.0, 0.45)
	ShellCasing.spawn(_effects_parent(), Transform3D(basis, at), velocity,
		_weapon.data.category == WeaponData.Category.PISTOL)


func _listener_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if camera != null else Vector3.ZERO


func _is_remote_shooter() -> bool:
	return _player != null and _player.is_network_remote


func _spawn_tracer(to: Vector3, with_flash: bool) -> void:
	if _weapon == null:
		return
	if _weapon.data != null and _weapon.data.is_melee:
		# somebody else's knife: heard, not traced.
		if with_flash:
			Audio.play_at(&"knife_swing", _weapon.global_position, -2.0, 0.08, 25.0)
		return
	var from := _weapon.get_muzzle_position()
	if _player != null and _player.is_network_remote:
		var held: Variant = _player.get_third_person_muzzle()
		if held != null:
			from = held
	if with_flash:
		# somebody else's shot: heard from where they are, so it's locatable.
		var far := StringName(String(_shot_sound()) + "_far")
		var near := from.distance_to(_listener_position()) < 12.0
		Audio.play_at(_shot_sound() if near or not Audio.has_sound(far) else far, from, 2.0, 0.05, 140.0)
		_echo(true, from)
		_crack_past_listener(from, to)
		_eject_remote_casing(from)
	if from.distance_to(to) < 0.5:
		return
	var tracer := Tracer.new()
	tracer.setup(from, to, with_flash)
	_effects_parent().add_child(tracer)


## the one place an impact gets drawn: spark, debris, and a bullet hole on
## scenery. nothing for a round that hit only air.
##
## ignores anything further than max_impact_distance from the player's eye -
## full-range hits are fine, but a point way out there means a bad origin or
## a freed node, not worth drawing.
func _spawn_impact(at: Vector3, normal: Vector3, zone: int, surface: int) -> void:
	if surface == Weapon.Surface.NONE:
		return
	if impact_scene == null or _live >= MAX_LIVE_EFFECTS:
		return
	if _player != null and _player.get_eye_position().distance_to(at) > max_impact_distance:
		return

	var effect := impact_scene.instantiate() as ImpactEffect
	if effect == null:
		return

	# added to the world, not this node, so it stays put instead of getting
	# dragged around as the player walks. frees itself when it expires.
	_effects_parent().add_child(effect)
	effect.setup(at, normal, zone, surface == Weapon.Surface.ENTITY)
	var melee := _weapon != null and _weapon.data != null and _weapon.data.is_melee
	if melee:
		Audio.play_at(&"knife_hit" if surface == Weapon.Surface.ENTITY else &"knife_wall", at, 0.0, 0.06, 25.0)

	_live += 1
	effect.tree_exited.connect(_on_effect_freed)

	if surface == Weapon.Surface.WORLD and not melee:
		var hole := BulletHole.new()
		hole.setup(at, normal)
		_effects_parent().add_child(hole)


## the match scene, so effects get freed with it instead of lingering after
## the match ends.
func _effects_parent() -> Node:
	var match_scene := get_tree().get_first_node_in_group(&"match_scene")
	return match_scene if match_scene != null else get_tree().current_scene


func _on_effect_freed() -> void:
	_live = maxi(0, _live - 1)
