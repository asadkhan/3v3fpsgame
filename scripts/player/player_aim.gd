class_name PlayerAim
extends Node
## aiming down sights. tracks how far into the aim the player is (amount, 0
## hip to 1 fully aimed, blended over WeaponData.ads_time) and turns the
## weapon's ADS numbers into the multipliers Player applies: fov, mouse
## sensitivity, spread, recoil, move speed, fire interval.
##
## local only - aiming changes what the shooter's own machine does, and all
## of that already reaches the host through the shot/transform paths, so
## nothing extra needs replicating.
##
## input: aim (right mouse, held by default - input/aim_toggle makes it a
## toggle). sprinting, reloading, dying, switching weapons or freeing the
## mouse drops the aim.

## 0 = hip, 1 = fully aimed.
var amount: float = 0.0

var _toggled: bool = false

@onready var _player: Player = get_parent() as Player


func is_aiming() -> bool:
	return amount > 0.5


## called by the player every physics frame, before movement and combat.
func update(delta: float) -> void:
	var data := _data()
	var wants := false
	if _can_aim():
		if GameConfig.aim_toggle:
			if Input.is_action_just_pressed(&"aim"):
				_toggled = not _toggled
			wants = _toggled
		else:
			wants = Input.is_action_pressed(&"aim")
	else:
		_toggled = false

	var duration := maxf(data.ads_time if data != null else 0.15, 0.01)
	amount = move_toward(amount, 1.0 if wants else 0.0, delta / duration)


## drops straight back to the hip - on death, a weapon switch, a respawn.
func reset() -> void:
	amount = 0.0
	_toggled = false


func _can_aim() -> bool:
	var weapon := _player.weapon
	return not _player.is_network_remote \
		and _player.input_enabled and _player.state.is_alive and not _player.objective_lock \
		and _player.is_mouse_captured() \
		and weapon != null and weapon.data != null and not weapon.is_reloading \
		and not weapon.data.is_melee \
		and not Input.is_action_pressed(&"sprint")


func _data() -> WeaponData:
	return _player.weapon.data if _player.weapon != null else null


func _blend(aimed_value: float) -> float:
	return lerpf(1.0, aimed_value, amount)


# --- Multipliers (all 1.0 at the hip) -----------------------------------------

func zoom() -> float:
	var data := _data()
	return _blend(data.ads_zoom) if data != null else 1.0


func spread_scale() -> float:
	var data := _data()
	return _blend(data.ads_spread_multiplier) if data != null else 1.0


func recoil_scale() -> float:
	var data := _data()
	return _blend(data.ads_recoil_multiplier) if data != null else 1.0


func move_scale() -> float:
	var data := _data()
	return _blend(data.ads_move_multiplier) if data != null else 1.0


func fire_interval_scale() -> float:
	var data := _data()
	return _blend(data.ads_fire_interval_multiplier) if data != null else 1.0


## how far to move the viewmodel from its hip position.
##
## with a Sight marker on the model, the offset is computed so the sight
## lands on screen centre at ads_sight_distance in front of the eye - new
## models line up without hand-tuning. weapon mount sits at the eye, so
## centring the sight just cancels its sideways/vertical position.
func viewmodel_offset() -> Vector3:
	var data := _data()
	if data == null:
		return Vector3.ZERO
	var sight: Variant = _player.weapon.get_sight_position()
	if sight != null:
		var at: Vector3 = sight
		return Vector3(-at.x, -at.y, -data.ads_sight_distance - at.z) * amount
	return data.ads_viewmodel_offset * amount


## whether the view is fully through a magnified scope: model hides, hud
## draws the scope overlay.
func is_scoped() -> bool:
	var data := _data()
	return data != null and data.scope_overlay and amount > 0.92
