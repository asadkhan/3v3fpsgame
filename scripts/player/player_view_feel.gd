class_name PlayerViewFeel
extends Node
## The procedural motion that makes the first-person view feel physical rather
## than bolted to the mouse: weapon sway, walk and sprint bob, the sprint pose,
## landing impacts, idle breathing, and a matching (gentler) camera bob and
## sprint field-of-view push.
##
## Purely cosmetic and local: it only ever offsets the viewmodel mount and the
## camera's local transform. The aim ray is built from the head, which this
## never touches, so nothing here can move where a bullet goes. Aiming down
## sights damps almost all of it - a steady view is part of what aiming buys.
##
## [Player] feeds it the mouse movement ([method add_look]) and calls
## [method update] each physics frame; it reads the results back through
## [method weapon_offset], [method weapon_rotation], [method camera_offset],
## [method camera_roll] and [method fov_scale].

# --- Tuning -----------------------------------------------------------------

## How far the weapon lags behind the mouse, per pixel of movement.
const SWAY_PER_PIXEL := 0.0006
const SWAY_MAX := 0.08
## How quickly sway settles back (higher = snappier).
const SWAY_RETURN := 7.0

## Bob amplitudes (metres) and speed (cycles per metre travelled).
const BOB_WEAPON := Vector2(0.012, 0.009)
const BOB_CAMERA := 0.022
const BOB_FREQUENCY := 1.9
const SPRINT_BOB_SCALE := 1.6

## Sprint pose: the gun drops and cants away.
const SPRINT_POS := Vector3(0.03, -0.06, 0.04)
const SPRINT_ROT := Vector3(-0.35, 0.45, 0.25)

## Landing: metres of dip per m/s of fall speed, and how fast it recovers.
const LAND_DIP_PER_SPEED := 0.006
const LAND_DIP_MAX := 0.09
const LAND_RECOVERY := 7.0

## Sprint field of view push, as a multiplier.
const SPRINT_FOV := 1.06

# --- State ------------------------------------------------------------------

var _sway := Vector2.ZERO          # x = yaw sway, y = pitch sway (radians)
var _look_accum := Vector2.ZERO    # mouse movement since last update
var _bob_phase: float = 0.0
var _bob_weight: float = 0.0       # 0 standing still .. 1 moving
var _sprint: float = 0.0
var _land: float = 0.0
var _land_velocity: float = 0.0
var _was_on_floor: bool = true
var _fall_speed: float = 0.0
var _time: float = 0.0
var _fov: float = 1.0
var _steady: float = 1.0          # 1 at the hip, 0.2 fully aimed

@onready var _player: Player = get_parent() as Player


## Mouse movement in pixels, from the player's look handler.
func add_look(relative: Vector2) -> void:
	_look_accum += relative


func update(delta: float, velocity: Vector3, on_floor: bool, sprinting: bool, aim_amount: float) -> void:
	_time += delta
	var steady := 1.0 - 0.8 * aim_amount

	# Sway: mouse movement pushes the weapon the other way, building up over
	# a flick, then it drifts back to centre.
	_sway -= _look_accum * SWAY_PER_PIXEL
	_sway = _sway.clamp(Vector2.ONE * -SWAY_MAX, Vector2.ONE * SWAY_MAX)
	_look_accum = Vector2.ZERO
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-SWAY_RETURN * delta))

	# Bob: phase advances with ground distance, so it matches the footsteps.
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var moving := on_floor and horizontal > 0.5
	_bob_weight = move_toward(_bob_weight, 1.0 if moving else 0.0, delta * 6.0)
	if moving:
		_bob_phase += horizontal * delta * BOB_FREQUENCY * TAU / 2.0

	_sprint = move_toward(_sprint, 1.0 if sprinting else 0.0, delta * 6.0)

	# Landing: remember the fall speed while airborne, spend it as a dip on
	# touchdown, then spring back with a little overshoot.
	if not on_floor:
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif not _was_on_floor:
		_land_velocity -= minf(_fall_speed * LAND_DIP_PER_SPEED, LAND_DIP_MAX) * 22.0
		_fall_speed = 0.0
	_was_on_floor = on_floor
	_land_velocity += (-_land * LAND_RECOVERY * LAND_RECOVERY - _land_velocity * 2.0 * LAND_RECOVERY) * delta
	_land += _land_velocity * delta

	_fov = lerpf(_fov, lerpf(1.0, SPRINT_FOV, _sprint), 1.0 - exp(-8.0 * delta))
	_steady = steady


# --- Outputs ------------------------------------------------------------------

func _bob_amount() -> float:
	return _bob_weight * lerpf(1.0, SPRINT_BOB_SCALE, _sprint)


func weapon_offset() -> Vector3:
	var bob := _bob_amount()
	var offset := Vector3(
		sin(_bob_phase) * BOB_WEAPON.x * bob,
		-absf(cos(_bob_phase)) * BOB_WEAPON.y * bob,
		0.0)
	# Idle breathing, only noticeable when standing still.
	offset.y += sin(_time * 1.6) * 0.0025 * (1.0 - _bob_weight)
	offset += SPRINT_POS * _sprint
	offset.y += _land * 0.6
	# Sway also nudges the position a touch, not just the angle.
	offset.x += _sway.x * 0.12
	offset.y -= _sway.y * 0.12
	return offset * _steady


func weapon_rotation() -> Vector3:
	var rotation := Vector3(_sway.y, _sway.x, _sway.x * 0.6)
	rotation += SPRINT_ROT * _sprint
	rotation.x += _land * 1.5
	return rotation * _steady


func camera_offset() -> Vector3:
	if not GameConfig.head_bob:
		return Vector3(0.0, _land * 0.5, 0.0)
	var bob := _bob_amount()
	return Vector3(
		sin(_bob_phase) * BOB_CAMERA * 0.5 * bob,
		absf(cos(_bob_phase)) * BOB_CAMERA * bob - BOB_CAMERA * 0.5 * bob + _land * 0.5,
		0.0) * (1.0 - 0.7 * (1.0 - _steady))


func camera_roll() -> float:
	if not GameConfig.head_bob:
		return 0.0
	return sin(_bob_phase) * 0.004 * _bob_amount() * _steady


func fov_scale() -> float:
	return _fov
