class_name PracticeTurret
extends Node3D
## A deliberately stupid hostile that shoots at the player, so Chapter 3's
## combat loop runs both ways.
##
## [b]Why this exists at all.[/b] The chapter's own brief asks for a player who
## can take damage and can die, but the test range it also asks for is entirely
## static - dummies and a wall. Nothing in that range can answer back, so "the
## player can die" would be a claim about a code path nothing exercises. This
## is the cheapest thing that makes the claim true.
##
## [b]Why it is so simple.[/b] It has no behaviour tree, no cover logic, no
## accuracy model and no memory of the player. It finds the nearest living
## player, turns towards them, and fires when it is pointing at them. That is
## the entire algorithm, and it is the whole of the AI budget for Chapter 3 -
## Chapter 6 is where enemy behaviour is designed.
##
## [b]It damages the player through [Damageable], not by writing to
## [member PlayerState].[/b] That is the part worth keeping. The turret and the
## player's own weapon are two completely unrelated damage sources, and they go
## through exactly the same one method, so a bug in the damage path shows up
## whichever one you test with first.
##
## Disposable with the rest of the grey box.

## Damage per shot. Low enough that standing in the open does not end the test
## run in two seconds.
@export var damage_per_shot: float = 9.0

## Seconds between shots. Deliberately slow: the point is that the player can be
## hurt, not that standing still is fatal.
@export var fire_interval: float = 1.4

## How far it will engage. Beyond this the turret does not even turn.
@export var engagement_range: float = 32.0

## Seconds before the very first shot, so a player who spawns next to the turret
## gets a moment to find it.
@export var start_delay: float = 3.0

## How quickly the barrel swings onto the target, in radians per second. Slow
## enough that a player can watch it turn and understand it is aiming at them.
@export var turn_speed: float = 2.6

## How far off target the turret may be and still fire, in degrees. Loose
## enough not to need frame-perfect tracking, tight enough that hiding behind
## cover works.
@export var aim_tolerance_degrees: float = 7.0

## Whether a wall between the turret and the player blocks the shot. On, because
## a turret that shoots through the cover the chapter also asks for would be
## testing nothing.
@export var requires_line_of_sight: bool = true

## Whether the turret shoots at all. The test harness turns this off to measure
## the player in isolation, and back on to prove it can be hurt.
@export var enabled: bool = true

## Emitted on every shot, for the test harness and the debug overlay.
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

	# Every machine turns the turret, but only the authority for health fires
	# it. A client that fired would damage its own copy of a player, putting
	# its health out of step with the host's - and could "kill" a player the
	# host still thinks is alive.
	if _cooldown <= 0.0 and _is_aimed_at(_target.get_eye_position()) \
			and (not NetworkManager.is_online or multiplayer.is_server()):
		_shoot()


## The nearest living player, or null. Nearest rather than first, so a second
## player spawned closer to the turret takes the fire - which is the behaviour
## Chapter 4's two-instance tests will need.
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


## Swings the barrel towards [param point] at no more than [member turn_speed].
## The rate is capped rather than applied absolutely, so a player who runs past
## at speed does not make the turret whip around like a searchlight.
func _turn_towards(point: Vector3, delta: float) -> void:
	var to_target := point - _head.global_position
	# Flattened: the turret yaws only. A head that tracked pitch as well would
	# need to compensate for its own muzzle height, and a hostile that has to
	# aim at where a player's eyes are is aiming at a moving part.
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
		# From the muzzle, not the centre, so a player standing directly in front
		# of the turret is not hidden behind its own pedestal.
		var origin := _muzzle.global_position
		var to_target := target.get_eye_position() - origin
		var distance := to_target.length()
		if distance > 0.001 and _has_line_of_sight(origin, to_target / distance, distance):
			# The eye is roughly where a head is. The turret aims for the head
			# deliberately, so a player in the open is punished for not moving
			# - but the shot is resolved by the player's own height band, so
			# ducking genuinely makes the shot miss rather than just being
			# described as a miss.
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
	# The turret's own hull is on the target layer, so without excluding it the
	# first thing this ray hits is always the pedestal it is standing on.
	query.exclude = [_hull.get_rid()]
	var result := space.intersect_ray(query)

	# Nothing in the way at all is a clear shot. Something in the way is only a
	# blocker if it is not the player being aimed at.
	if result.is_empty():
		return true
	return Damageable.find_target(result.get("collider")) == _target


## One line for the debug overlay.
func debug_line() -> String:
	if not enabled:
		return "%s  disabled" % name
	if _target == null:
		return "%s  no target" % name
	return "%s  engaging  t-%.1fs" % [name, _cooldown]
