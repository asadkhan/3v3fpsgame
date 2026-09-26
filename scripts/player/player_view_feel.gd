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

## Bob amplitudes in metres. Deliberately small: bob should be felt, not
## watched.
const BOB_WEAPON := Vector2(0.007, 0.005)
const BOB_CAMERA := 0.012
const SPRINT_BOB_SCALE := 1.35

## Metres per footstep. The bob is locked to the stride - one side-to-side
## sway per two steps, one dip per step - so it lines up with the footstep
## sounds ([constant Player.STEP_STRIDE]) instead of running on its own clock.
const STRIDE := 2.3

## How quickly the bob's output follows its target. Smooths starting,
## stopping and speed changes so nothing snaps.
const BOB_SMOOTHING := 10.0

## Sprint pose: the gun drops and cants away.
const SPRINT_POS := Vector3(0.025, -0.045, 0.03)
const SPRINT_ROT := Vector3(-0.22, 0.3, 0.16)

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
var _sprint_linear: float = 0.0
var _land: float = 0.0
var _land_velocity: float = 0.0
var _was_on_floor: bool = true
var _fall_speed: float = 0.0
var _time: float = 0.0
var _fov: float = 1.0
var _steady: float = 1.0          # 1 at the hip, 0.2 fully aimed
var _bob_weapon_out := Vector3.ZERO  # smoothed bob output
var _bob_camera_out := Vector3.ZERO

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
	_bob_weight = move_toward(_bob_weight, 1.0 if moving else 0.0, delta * 4.0)
	if moving:
		# A full phase cycle is two steps (left and right foot).
		_bob_phase = fmod(_bob_phase + horizontal * delta * TAU / (2.0 * STRIDE), TAU * 100.0)

	# Figure-of-eight: side-to-side once per two steps, a smooth dip on every
	# step. Pure sines, so there is no hard turnaround at the bottom - that
	# corner (from an abs(cos) curve) was what made the old bob look forced.
	var bob := _bob_amount()
	var target_weapon := Vector3(
		sin(_bob_phase) * BOB_WEAPON.x,
		(cos(_bob_phase * 2.0) - 1.0) * 0.5 * BOB_WEAPON.y,
		0.0) * bob
	var target_camera := Vector3(
		sin(_bob_phase) * BOB_CAMERA * 0.4,
		(cos(_bob_phase * 2.0) - 1.0) * 0.5 * BOB_CAMERA,
		0.0) * bob
	var follow := 1.0 - exp(-BOB_SMOOTHING * delta)
	_bob_weapon_out = _bob_weapon_out.lerp(target_weapon, follow)
	_bob_camera_out = _bob_camera_out.lerp(target_camera, follow)

	# Eased rather than linear, so going into and out of the sprint pose reads
	# as a movement of the arms rather than a slide.
	_sprint_linear = move_toward(_sprint_linear, 1.0 if sprinting else 0.0, delta * 4.5)
	_sprint = smoothstep(0.0, 1.0, _sprint_linear)

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
	var offset := _bob_weapon_out
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
	# The hand rolls slightly with the side-to-side sway of the walk.
	rotation.z -= _bob_weapon_out.x * 1.6
	rotation += SPRINT_ROT * _sprint
	rotation.x += _land * 1.5
	return rotation * _steady


func camera_offset() -> Vector3:
	if not GameConfig.head_bob:
		return Vector3(0.0, _land * 0.5, 0.0)
	return (_bob_camera_out + Vector3(0.0, _land * 0.5, 0.0)) * (1.0 - 0.7 * (1.0 - _steady))


func camera_roll() -> float:
	if not GameConfig.head_bob:
		return 0.0
	return _bob_camera_out.x * 0.12 * _steady


func fov_scale() -> float:
	return _fov
