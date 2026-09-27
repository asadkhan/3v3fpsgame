class_name PracticeTurret
extends Node3D
## a dumb hostile that shoots at the player, so the practice range can hurt
## you back.
##
## no behaviour tree, no cover logic, no accuracy model, no memory. finds the
## nearest living player, turns towards them, fires when aimed at them.
##
## damages through Damageable rather than writing to PlayerState directly, so
## the turret and the player's own weapon share the exact same damage path.
##
## throwaway practice-range enemy, nothing fancier planned for it here.

## damage per shot. low enough that standing in the open doesn't end the run
## in two seconds.
@export var damage_per_shot: float = 9.0

## seconds between shots. slow on purpose - point is you *can* get hurt, not
## that standing still is fatal.
@export var fire_interval: float = 1.4

## how far it will engage. beyond this it doesn't even turn.
@export var engagement_range: float = 32.0

## seconds before its first shot, so a player spawning next to it gets a
## moment to notice it.
@export var start_delay: float = 3.0

## how fast the barrel swings onto target, radians per second. slow enough to
## watch it aim at you.
@export var turn_speed: float = 2.6

## how far off target it can be and still fire, in degrees. loose enough to
## skip frame-perfect tracking, tight enough that cover still works.
@export var aim_tolerance_degrees: float = 7.0

## whether a wall between the turret and the player blocks the shot.
@export var requires_line_of_sight: bool = true

## whether the turret shoots at all. toggle off to test the player in
## isolation.
@export var enabled: bool = true

## emitted on every shot, for the debug overlay
signal fired(hit: bool)

var _cooldown: float = 0.0
var _target: Player = null
var _flash_left: float = 0.0

@onready var _head: Node3D = $Head
@onready var _muzzle: Marker3D = $Head/Muzzle
@onready var _flash_light: OmniLight3D = $Head/Flash
@onready var _hull: StaticBody3D = $Collision


func _ready() -> void:
	add_to_group(&"practice_turrets")
	_cooldown = start_delay


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		_flash_light.light_energy = 0.0 if _flash_left <= 0.0 else 2.5

	if not enabled:
		return

	_cooldown = maxf(_cooldown - delta, 0.0)
	_target = _find_target()

	if _target == null:
		return

	_turn_towards(_target.get_eye_position(), delta)

	# every machine turns the turret, but only the health authority fires it -
	# otherwise a client could damage its own copy of a player and desync
	# health from the host
	if _cooldown <= 0.0 and _is_aimed_at(_target.get_eye_position()) \
			and (not NetworkManager.is_online or multiplayer.is_server()):
		_shoot()


## the nearest living player, or null. nearest rather than first, so whoever's
## closer takes the fire.
func _find_target() -> Player:
	var best: Player = null
	var best_distance := INF

	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or not player.state.is_alive:
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < best_distance and distance <= engagement_range * engagement_range:
			best_distance = distance
			best = player

	return best


## swings the barrel towards point, capped at turn_speed so it doesn't whip
## around like a searchlight when a player runs past fast.
func _turn_towards(point: Vector3, delta: float) -> void:
	var to_target := point - _head.global_position
	# flattened: turret only yaws, no pitch tracking
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return

	var wanted := atan2(-to_target.x, -to_target.z)
	var max_step := turn_speed * delta
	_head.rotation.y = rotate_toward(_head.rotation.y, wanted, max_step)


func _is_aimed_at(point: Vector3) -> bool:
	var to_target := point - _head.global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return false
	var wanted := atan2(-to_target.x, -to_target.z)
	return absf(angle_difference(_head.rotation.y, wanted)) <= deg_to_rad(aim_tolerance_degrees)


func _shoot() -> void:
	_cooldown = fire_interval
	_flash_left = 0.06
	_flash_light.light_energy = 2.5

	var target := _target
	var hit := false
	if target != null:
		# fire from the muzzle, not the centre, so a player right in front
		# isn't hidden behind the turret's own pedestal
		var origin := _muzzle.global_position
		var to_target := target.get_eye_position() - origin
		var distance := to_target.length()
		if distance > 0.001 and _has_line_of_sight(origin, to_target / distance, distance):
			# aims at the eye/head position, but hit resolution uses the
			# player's actual height band - so ducking really does miss it
			hit = Damageable.deal_damage(
				target, damage_per_shot, self, Damageable.HitZone.HEAD) > 0.0

	fired.emit(hit)


func _has_line_of_sight(origin: Vector3, direction: Vector3, distance: float) -> bool:
	if not requires_line_of_sight:
		return true

	var space := get_world_3d().direct_space_state
	if space == null:
		return false

	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * distance, CollisionLayers.WEAPON_MASK)
	# exclude its own hull, otherwise the ray always hits the pedestal first
	query.exclude = [_hull.get_rid()]
	var result := space.intersect_ray(query)

	# nothing in the way = clear shot. something in the way only blocks if
	# it's not the player being aimed at
	if result.is_empty():
		return true
	return Damageable.find_target(result.get("collider")) == _target


## one line for the debug overlay
func debug_line() -> String:
	if not enabled:
		return "%s  disabled" % name
	if _target == null:
		return "%s  no target" % name
	return "%s  engaging  t-%.1fs" % [name, _cooldown]
