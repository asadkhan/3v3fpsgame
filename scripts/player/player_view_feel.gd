class_name PlayerViewFeel
extends Node
## procedural motion that makes the first-person view feel physical instead of
## glued to the mouse: weapon sway, walk/sprint bob, sprint pose, landing dip,
## idle breathing, plus a gentler matching camera bob and sprint FOV push.
##
## purely cosmetic and local - only offsets the viewmodel mount and the
## camera's local transform. the aim ray comes from the head, untouched here,
## so nothing in this file can move where a bullet goes. aiming down sights
## damps almost all of it.
##
## Player feeds it mouse movement (add_look) and calls update() each physics
## frame, then reads back weapon_offset, weapon_rotation, camera_offset,
## camera_roll and fov_scale.

# --- Tuning -----------------------------------------------------------------

## how far the weapon lags behind the mouse, per pixel of movement
const SWAY_PER_PIXEL := 0.0006
const SWAY_MAX := 0.08
## how quickly sway settles back (higher = snappier)
const SWAY_RETURN := 7.0

## bob amplitudes in metres, kept small - felt, not watched
const BOB_WEAPON := Vector2(0.007, 0.005)
const BOB_CAMERA := 0.012
const SPRINT_BOB_SCALE := 1.35

## metres per footstep. bob is locked to stride - one side sway per two
## steps, one dip per step - so it matches the footstep sounds
## (Player.STEP_STRIDE) instead of running on its own clock.
const STRIDE := 2.3

## how fast the bob output follows its target. smooths starts, stops and
## speed changes so nothing snaps.
const BOB_SMOOTHING := 10.0

## sprint pose: gun drops and cants away
const SPRINT_POS := Vector3(0.025, -0.045, 0.03)
const SPRINT_ROT := Vector3(-0.22, 0.3, 0.16)

## landing: metres of dip per m/s of fall speed, and recovery speed
const LAND_DIP_PER_SPEED := 0.006
const LAND_DIP_MAX := 0.09
const LAND_RECOVERY := 7.0

## sprint FOV push, as a multiplier
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
var _steady: float = 1.0          # 1 at the hip, 0 fully aimed
var _bob_weapon_out := Vector3.ZERO  # smoothed bob output
var _bob_camera_out := Vector3.ZERO

@onready var _player: Player = get_parent() as Player


## mouse movement in pixels, from the player's look handler
var _air: float = 0.0


func add_look(relative: Vector2) -> void:
	_look_accum += relative


func update(delta: float, velocity: Vector3, on_floor: bool, sprinting: bool, aim_amount: float) -> void:
	_time += delta
	var steady := 1.0 - aim_amount

	# sway: mouse movement pushes the weapon the other way, builds up over a
	# flick, then drifts back to centre
	_sway -= _look_accum * SWAY_PER_PIXEL
	_sway = _sway.clamp(Vector2.ONE * -SWAY_MAX, Vector2.ONE * SWAY_MAX)
	_look_accum = Vector2.ZERO
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-SWAY_RETURN * delta))

	# bob: phase advances with ground distance, matches the footsteps
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var moving := on_floor and horizontal > 0.5
	_bob_weight = move_toward(_bob_weight, 1.0 if moving else 0.0, delta * 4.0)
	if moving:
		# a full phase cycle is two steps (left and right foot)
		_bob_phase = fmod(_bob_phase + horizontal * delta * TAU / (2.0 * STRIDE), TAU * 100.0)

	# figure-of-eight: side-to-side once per two steps, smooth dip every step.
	# pure sines so there's no hard turnaround at the bottom (an abs(cos)
	# curve made the old version look forced).
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

	# eased rather than linear, so the sprint pose reads as the arms moving,
	# not sliding
	_sprint_linear = move_toward(_sprint_linear, 1.0 if sprinting else 0.0, delta * 4.5)
	_sprint = smoothstep(0.0, 1.0, _sprint_linear)

	# landing: remember fall speed while airborne, spend it as a dip on
	# touchdown, spring back with a little overshoot
	if not on_floor:
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif not _was_on_floor:
		_land_velocity -= minf(_fall_speed * LAND_DIP_PER_SPEED, LAND_DIP_MAX) * 22.0
		_fall_speed = 0.0
	_was_on_floor = on_floor
	_land_velocity += (-_land * LAND_RECOVERY * LAND_RECOVERY - _land_velocity * 2.0 * LAND_RECOVERY) * delta
	_land += _land_velocity * delta

	# weapon lags behind vertical motion: dips as you jump, rises as you fall
	var target_air := clampf(-velocity.y * 0.005, -0.035, 0.035) if not on_floor else 0.0
	_air = lerpf(_air, target_air, 1.0 - exp(-8.0 * delta))

	_fov = lerpf(_fov, lerpf(1.0, SPRINT_FOV, _sprint), 1.0 - exp(-8.0 * delta))
	_steady = steady


# --- Outputs ------------------------------------------------------------------

func _bob_amount() -> float:
	return _bob_weight * lerpf(1.0, SPRINT_BOB_SCALE, _sprint)


func weapon_offset() -> Vector3:
	var offset := _bob_weapon_out
	# idle breathing, only noticeable when standing still
	offset.y += sin(_time * 1.6) * 0.0025 * (1.0 - _bob_weight)
	offset += SPRINT_POS * _sprint
	offset.y += _land * 0.6
	offset.y += _air
	# sway also nudges the position a touch, not just the angle
	offset.x += _sway.x * 0.12
	offset.y -= _sway.y * 0.12
	return offset * _steady


func weapon_rotation() -> Vector3:
	var rotation := Vector3(_sway.y, _sway.x, _sway.x * 0.6)
	# hand rolls slightly with the side-to-side sway of the walk
	rotation.z -= _bob_weapon_out.x * 1.6
	rotation += SPRINT_ROT * _sprint
	rotation.x += _land * 1.5
	return rotation * _steady


func camera_offset() -> Vector3:
	# fully aimed the camera stays put - the gun hangs off the head, not the
	# camera, so any camera bob would wobble the sight
	if not GameConfig.head_bob:
		return Vector3(0.0, _land * 0.5, 0.0) * _steady
	return (_bob_camera_out + Vector3(0.0, _land * 0.5, 0.0)) * _steady


func camera_roll() -> float:
	if not GameConfig.head_bob:
		return 0.0
	return _bob_camera_out.x * 0.12 * _steady


func fov_scale() -> float:
	return _fov
