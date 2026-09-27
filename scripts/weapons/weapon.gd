class_name Weapon
extends Node3D
## one equipped weapon: its magazine, trigger, reload timer, and the hitscan
## that turns a trigger pull into a line in the world.
##
## weapon owns: when a shot fires, how much damage, what it hits, recoil,
## magazine contents, reload progress. player owns: camera, aim direction,
## input, and the health that takes the damage. the player polls the
## trigger and hands in the aim ray - it never decides if a shot is legal.
##
## aim is passed in rather than read from a camera here because the ray
## starts at the camera, not the muzzle, so the crosshair tells the truth.
## the muzzle is just where the flash and tracer start.
##
## no view bob, no ads, no animation, no projectile path. not a singleton -
## it's a child of whichever player owns it.

# --- Configuration ------------------------------------------------------

## the loadout stats. set by equip(); never changed at runtime since load()
## hands every player the same shared instance.
var data: WeaponData = null

## the body this weapon's shots must not hit. set by equip() so the raycast
## can skip the shooter without this class knowing what a player is.
var shooter: CollisionObject3D = null

# --- Signals ------------------------------------------------------------
# emitted instead of called directly on the player, so the weapon has no
# hard dependency on it.

## a round left the barrel. no hit info yet, since nothing's been hit at
## this point.
##
## the player listens and calls hitscan() with its own aim ray - keeps this
## class free of any camera or aim opinion.
signal fired

## the shot connected. killed flags a kill for the hit marker.
signal hit_confirmed(killed: bool, zone: int, health_left: int)

## a bullet landed somewhere and wants an impact effect.
##
## just a request, not a spawn - the weapon decides a shot ended at a
## point, a local presentation node decides what that looks like.
signal impact_requested(position: Vector3, normal: Vector3, zone: int, surface: int)

## what a round ended on, so presentation can tell a wall (spark, bullet
## hole) from a body (blood, no hole) from open air (nothing).
enum Surface {
	NONE,    ## missed everything, travelled full range.
	WORLD,   ## hit scenery.
	ENTITY,  ## hit something damageable - a player or practice target.
}

## surface of the most recent hitscan. host reads this to tell clients
## what a shot struck.
var last_surface: int = Surface.NONE

## trigger pulled on an empty mag. drives the dry-fire click.
signal dry_fired

## reloading started. duration is the full reload time.
signal reload_started(duration: float)

## reloading finished, whether or not it was interrupted.
signal reload_finished

## magazine contents changed, for the hud and debug overlay.
signal ammo_changed(magazine: int, reserve: int)

## ask the player to kick the camera. degrees, positive is upward.
signal recoil_requested(pitch_degrees: float, yaw_degrees: float)

# --- Ammunition ---------------------------------------------------------

## rounds left in the magazine. the only ammo count that changes by firing.
var ammo_in_magazine: int = 0

## reserve ammo. infinite for now - players re-buy every round, so a
## per-match pool doesn't matter yet. kept here for the buy system and any
## future limited-ammo mode.
var reserve_ammo: int = 0

## when true, try_reload() always succeeds and never touches reserve_ammo.
## turn off for a real finite pool, no other code needs to change.
var infinite_reserve: bool = true

## how many magazines reserve_ammo starts with when infinite reserve is off.
@export var starting_reserve_magazines: int = 10

# --- State --------------------------------------------------------------

## true between reload_started and reload_finished.
var is_reloading: bool = false

## seconds left on the current reload.
var _reload_left: float = 0.0

## seconds until the next shot is allowed - the fire-rate limit.
var _cooldown_left: float = 0.0

## rounds left to fire in the current burst.
var _burst_left: int = 0

## seconds until the next round of a burst, which fires on its own
## interval rather than the frame rate.
var _burst_timer: float = 0.0

## set while the trigger's held, so semi-auto can tell a pull from a hold.
var _trigger_held: bool = false

## damage from the last hitscan. 0 for a miss, scenery, or an already-dead
## target. host uses this to only flash the hit marker on a real hit.
var last_damage_dealt: float = 0.0

## multiplies time between shots. player sets this every frame from how
## far into ads it is; 1.0 at the hip.
var fire_interval_scale: float = 1.0

## where the last shot ended, for the tracer and impact fx.
var _last_shot_end: Vector3 = Vector3.ZERO

@onready var _muzzle_flash: OmniLight3D = $MuzzleFlash if has_node("MuzzleFlash") else null
@onready var _muzzle_point: Marker3D = $MuzzlePoint if has_node("MuzzlePoint") else null

## seconds the muzzle flash stays lit. long enough to read at 60fps, short
## enough it doesn't look like a light left on.
const MUZZLE_FLASH_TIME := 0.045

## peak brightness of the muzzle flash.
const MUZZLE_FLASH_ENERGY := 3.0

var _flash_left: float = 0.0

## keyframed viewmodel animation (draw, reload, inspect, knife swings).
var _animator: ViewmodelAnimator = null
## seconds left of the draw animation - can't fire until it's done.
var _draw_left: float = 0.0
## a melee swing that's started but hasn't connected yet: seconds left,
## or negative for none.
var _melee_pending: float = -1.0
## whether the swing in flight is the heavy one.
var melee_heavy: bool = false

## how far into a spray the next shot is (0 = first round, fully accurate).
## decays back to 0 over recoil_reset_time off the trigger.
var spray_index: float = 0.0
## the part of the recoil pattern the bullets take but the camera doesn't,
## in degrees (pitch, yaw) - applied to the next shot's direction.
var _spray_offset := Vector2.ZERO
var _since_shot: float = 99.0


# --- Lifecycle ----------------------------------------------------------

## binds this weapon to its stats and owner. called when equipped, safe to
## call again to re-equip after a loadout change.
func equip(p_data: WeaponData, p_shooter: CollisionObject3D) -> void:
	data = p_data
	shooter = p_shooter

	if data == null:
		ammo_in_magazine = 0
		reserve_ammo = 0
		_emit_ammo_changed()
		return

	ammo_in_magazine = data.magazine_size
	reserve_ammo = data.magazine_size * maxi(starting_reserve_magazines, 1)
	_cooldown_left = 0.0
	_burst_left = 0
	_melee_pending = -1.0
	_emit_ammo_changed()
	_apply_model()
	_draw_left = _animator.play_draw() if _animator != null else 0.0


# --- Model ----------------------------------------------------------------------

## the model currently shown, built from WeaponData's viewmodel scene.
var _model: Node3D = null
var _model_scene: PackedScene = null
## first-person arms holding the gun, rebuilt with each model.
var _arms: ViewmodelArms = null

## where the model's Sight marker is, in this node's space. see
## get_sight_position().
var _sight_position: Vector3 = Vector3.ZERO
var _has_sight: bool = false
var _has_red_dot: bool = false

## placeholder block rifle, used for weapons without a model.
@onready var _viewmodel: Node3D = $ViewModel if has_node("ViewModel") else null
var _placeholder_parts: Array[Node] = []


## swaps in the equipped weapon's model and moves the muzzle to its barrel.
func _apply_model() -> void:
	var scene := data.viewmodel_scene if data != null else null
	if scene == _model_scene or _viewmodel == null:
		return
	_model_scene = scene
	if _placeholder_parts.is_empty():
		for child in _viewmodel.get_children():
			if child is MeshInstance3D:
				_placeholder_parts.append(child)
	if _model != null:
		_viewmodel.remove_child(_model)
		_model.queue_free()
		_model = null
	if _arms != null:
		_viewmodel.remove_child(_arms)
		_arms.queue_free()
		_arms = null
	_has_sight = false
	for part in _placeholder_parts:
		(part as Node3D).visible = scene == null
	if _animator == null:
		_animator = ViewmodelAnimator.new()
		_animator.name = "Animator"
		add_child(_animator)
		_animator.cue.connect(_on_animation_cue)
	if scene == null:
		_animator.setup(_viewmodel, null, null, data)
		return

	_model = scene.instantiate() as Node3D
	_viewmodel.add_child(_model)
	# shadows off - a viewmodel sits close to the camera and would throw a
	# huge shadow of the gun across the world.
	for mesh: GeometryInstance3D in _model.find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var muzzle := WeaponModel.marker(_model, "Muzzle")
	var sight := WeaponModel.marker(_model, "Sight")
	_has_red_dot = _model.find_child("RedDot", true, false) != null
	if muzzle != null and is_inside_tree():
		var at := to_local(muzzle.global_position)
		if _muzzle_point != null:
			_muzzle_point.position = at
		if _muzzle_flash != null:
			_muzzle_flash.position = at
	if sight != null and is_inside_tree():
		_sight_position = to_local(sight.global_position)
		_has_sight = true
	_arms = ViewmodelArms.new()
	_arms.name = "Arms"
	_viewmodel.add_child(_arms)
	_arms.build(_viewmodel, _model, shooter)
	_animator.setup(_viewmodel, _model, _arms, data)


## plays the sound a clip marks, on the machine that can see the viewmodel.
func _on_animation_cue(cue: StringName) -> void:
	if _viewmodel == null or not _viewmodel.is_visible_in_tree():
		return
	match cue:
		&"mag_out":
			Audio.play(&"reload_out", -6.0)
		&"mag_in":
			Audio.play(&"reload_in", -4.0)
		&"rack":
			Audio.play(&"rack", -8.0)
		&"shing":
			Audio.play(&"knife_draw", -6.0)


## gun dips out of the way for a throw and comes back up; can't fire until
## it's back.
func throw_motion() -> void:
	Audio.play(&"grenade_throw", -4.0, 0.1)
	if _animator != null:
		_draw_left = _animator.play_draw()


## starts the inspect animation, if nothing else is happening.
func inspect() -> void:
	if data == null or _animator == null or is_reloading or _draw_left > 0.0:
		return
	if _animator.is_playing() and not _animator.is_playing(&"inspect"):
		return
	_animator.play_inspect()


## sight position in local (weapon mount) space, or null if there's no
## Sight marker. PlayerAim lines this up with the eye.
func get_sight_position() -> Variant:
	return _sight_position if _has_sight else null


## true when the gun has a red dot optic (hud hides the crosshair while aimed).
func has_red_dot() -> bool:
	return _has_red_dot


## hides the model when looking through a scope, so it doesn't fill the view.
func set_model_hidden(hidden: bool) -> void:
	if _viewmodel != null:
		_viewmodel.visible = not hidden


# --- Public queries -----------------------------------------------------

## whether the trigger would fire right now. hud uses this to grey out the
## fire icon.
##
## not gated on the burst counter - update_trigger() already decides
## whether a press can *start* a burst, and a burst already underway is
## firing by definition.
func can_fire() -> bool:
	if data == null or is_reloading or _draw_left > 0.0:
		return false
	if ammo_in_magazine <= 0 and not data.is_melee:
		return false
	return _cooldown_left <= 0.0


func is_full() -> bool:
	return data != null and ammo_in_magazine >= data.magazine_size


# --- Trigger ------------------------------------------------------------

## player calls this every frame with the current trigger state. keeping
## polling in the player lets input_enabled silence the weapon for a
## remote player without this class knowing about input.
##
## just_pressed/held are passed in rather than read from Input here, same
## reason the aim ray is passed in - keeps this class free of input.
func update_trigger(held: bool, just_pressed: bool, delta: float) -> void:
	_tick(delta)

	match data.fire_mode if data != null else WeaponData.FireMode.SEMI_AUTO:
		WeaponData.FireMode.SEMI_AUTO:
			if just_pressed:
				_try_fire()
		WeaponData.FireMode.AUTO:
			if held:
				_try_fire()
		WeaponData.FireMode.BURST:
			# one press starts the burst; holding doesn't queue another one.
			if just_pressed and _burst_left <= 0:
				_burst_left = maxi(data.burst_count, 1)
				_try_fire()
			elif _burst_left > 0:
				_burst_timer -= delta
				if _burst_timer <= 0.0:
					_try_fire()

	# semi-auto needs the trigger to come back up before the next pull
	# counts - the difference between one shot per click and one per frame.
	_trigger_held = held


## advances cooldowns, reload, and muzzle flash. player calls this every
## frame regardless of trigger state, so reload/flash still progress with
## the trigger released.
func _tick(delta: float) -> void:
	# allowed to dip one frame below zero; the overshoot carries into the
	# next shot's cooldown (see _try_fire). clamping at zero instead rounds
	# every interval up to a whole frame, which broke fire-rate accuracy.
	_cooldown_left = maxf(_cooldown_left - delta, -delta)
	_draw_left = maxf(_draw_left - delta, 0.0)
	_since_shot += delta
	if data != null and spray_index > 0.0 and _since_shot > data.fire_interval * 1.2:
		var rate := maxf(float(data.recoil_vertical_shots), 3.0) / data.recoil_reset_time
		spray_index = maxf(spray_index - rate * delta, 0.0)
	if _melee_pending >= 0.0:
		_melee_pending -= delta
		if _melee_pending < 0.0:
			fired.emit()
	if _burst_timer > 0.0:
		_burst_timer = maxf(_burst_timer - delta, 0.0)

	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		if _muzzle_flash != null:
			# faded out, not just switched off - assigning the light's own
			# energy back to itself never turns it off, which leaves a
			# permanent muzzle flash after the first shot.
			var t := _flash_left / MUZZLE_FLASH_TIME
			_muzzle_flash.light_energy = MUZZLE_FLASH_ENERGY * t * t
		if _flash_mesh != null:
			_flash_mesh.visible = _flash_left > 0.0

	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()


# --- Firing -------------------------------------------------------------

## fires one round if the weapon allows it. returns whether a shot happened.
func _try_fire() -> bool:
	if not can_fire():
		# an empty-mag click is a dry fire, not a silent no-op.
		if data != null and not is_reloading and ammo_in_magazine <= 0 \
				and _cooldown_left <= 0.0 and _burst_left <= 0:
			_cooldown_left = data.fire_interval
			dry_fired.emit()
		return false

	if data.is_melee:
		_cooldown_left = data.fire_interval
		_start_melee(false)
		return true

	if _animator != null and _animator.is_playing(&"inspect"):
		_animator.stop()
	ammo_in_magazine -= 1
	# scaled by aiming only on the shot that starts a new pull - rounds
	# inside a burst keep the weapon's own rhythm.
	_cooldown_left = data.fire_interval * fire_interval_scale + minf(_cooldown_left, 0.0)
	if _burst_left > 0:
		_burst_left -= 1
		if _burst_left > 0:
			_burst_timer = data.fire_interval
	_emit_ammo_changed()

	_flash_muzzle()
	_request_recoil()
	_eject_casing()
	fired.emit()
	return true


## throws a spent case out the right side of the viewmodel, on the machine
## that can see it.
func _eject_casing() -> void:
	if data == null or data.is_melee or _viewmodel == null or not _viewmodel.is_visible_in_tree():
		return
	var parent := get_tree().get_first_node_in_group(&"match_scene")
	if parent == null:
		parent = get_tree().current_scene
	if parent == null:
		return
	var port := (_sight_position if _has_sight else Vector3(0.1, -0.1, -0.2)) + Vector3(0.025, -0.03, 0.07)
	var basis := global_basis
	var velocity := basis * Vector3(randf_range(1.6, 2.4), randf_range(1.2, 1.9), randf_range(0.0, 0.5))
	if shooter is CharacterBody3D:
		velocity += (shooter as CharacterBody3D).velocity
	ShellCasing.spawn(parent, Transform3D(basis, global_transform * port), velocity,
		data.category == WeaponData.Category.PISTOL)


## knife's alt attack: a slower, harder stab. returns whether it started.
func try_heavy() -> bool:
	if data == null or not data.is_melee or not can_fire():
		return false
	_cooldown_left = data.heavy_interval
	_start_melee(true)
	return true


## starts a swing; it connects (emits fired) partway through.
func _start_melee(heavy: bool) -> void:
	melee_heavy = heavy
	_melee_pending = data.heavy_hit_delay if heavy else data.melee_hit_delay
	if _animator != null:
		if heavy:
			_animator.play_stab()
		else:
			_animator.play_slash()


## hitscans along an already-validated aim ray.
##
## public and separate from _try_fire so the host can re-run it with a
## client's origin/direction instead of trusting a client's damage number.
##
## returns the hit result, or an empty dictionary when nothing was hit.
func hitscan(origin: Vector3, direction: Vector3) -> Dictionary:
	last_damage_dealt = 0.0
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}

	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * data.max_range,
		CollisionLayers.WEAPON_MASK)

	# the muzzle sits inside the shooter's own capsule, so without this
	# every shot would hit the shooter first.
	if shooter != null:
		query.exclude = [shooter.get_rid()]

	# starting inside a shape shouldn't count as a hit - matters for a
	# target the player is standing inside after it drops.
	query.hit_from_inside = false

	var result := space.intersect_ray(query)
	if result.is_empty():
		_last_shot_end = origin + direction * data.max_range
		last_surface = Surface.NONE
		impact_requested.emit(_last_shot_end, -direction, Damageable.HitZone.BODY, Surface.NONE)
		return {}

	_last_shot_end = result.position
	_apply_damage_to(result, origin, direction)
	return result


## turns a raycast hit into damage, through the Damageable contract. never
## writes to a target's fields directly.
##
## collider may be a child hitbox rather than the entity itself, so it's
## resolved upward first - only the resolved target knows which of its own
## colliders was struck.
func _apply_damage_to(result: Dictionary, origin: Vector3, direction: Vector3) -> void:
	var collider: Object = result.get("collider")
	var point: Vector3 = result.get("position", _last_shot_end)
	var normal: Vector3 = result.get("normal", -direction)

	# a static body is scenery - stops bullets without being damageable.
	var target := Damageable.find_target(collider)
	if not Damageable.is_damageable(target):
		# a wall still gets a mark. where the round stopped is a fact about
		# the world regardless of whether anything got hurt.
		last_surface = Surface.WORLD
		impact_requested.emit(point, normal, Damageable.HitZone.BODY, Surface.WORLD)
		return

	# measured here, not read from the result - intersect_ray doesn't return
	# a distance, and a missing "distance" key defaults to 0.0, which is
	# full damage. computed from the origin actually used so it matches
	# the ray the crosshair is drawing.
	var distance := origin.distance_to(point)
	var zone := Damageable.resolve_zone(target, point, collider)
	var amount := data.damage_at_distance(distance)
	if data.is_melee:
		# a blade does its damage wherever it lands - except from behind.
		amount = data.heavy_damage if melee_heavy else data.damage
		if _is_behind(target, direction):
			amount *= data.backstab_multiplier
	elif zone == Damageable.HitZone.HEAD:
		amount *= data.headshot_multiplier

	var dealt := Damageable.deal_damage(target, amount, shooter, zone)
	last_damage_dealt = dealt

	# emitted before the early-out so an already-dead body still shows
	# where the round went - hit marker is accuracy feedback, not a
	# damage reward.
	last_surface = Surface.ENTITY
	impact_requested.emit(point, normal, zone, Surface.ENTITY)

	if dealt <= 0.0:
		# connected but did no damage - already dead, or the target
		# declined the hit. no hit marker.
		return

	var health_left := -1
	if target.has_method(&"get_health"):
		health_left = int(target.call(&"get_health"))
	var killed := target.has_method(&"is_dead") and bool(target.call(&"is_dead"))
	hit_confirmed.emit(killed, zone, health_left)


## whether a hit along direction comes from behind target - the two face
## roughly the same way, ignoring pitch.
static func _is_behind(target: Object, direction: Vector3) -> bool:
	if not target.has_method(&"get_look_direction"):
		return false
	var facing: Vector3 = target.call(&"get_look_direction")
	facing.y = 0.0
	var along := Vector3(direction.x, 0.0, direction.z)
	if facing.length_squared() < 0.0001 or along.length_squared() < 0.0001:
		return false
	return facing.normalized().dot(along.normalized()) > 0.5


## starts a reload if one is needed and allowed. returns whether it started.
func try_reload() -> bool:
	if data == null or data.is_melee or is_reloading or is_full():
		return false
	if not infinite_reserve and reserve_ammo <= 0:
		return false

	is_reloading = true
	_reload_left = data.reload_time
	if _animator != null:
		_animator.play_reload(data.reload_time)
	reload_started.emit(data.reload_time)
	return true


## cancels a reload in progress and keeps whatever's already in the magazine.
func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	_reload_left = 0.0
	if _animator != null and _animator.is_playing(&"reload"):
		_animator.stop()
	reload_finished.emit()


func _finish_reload() -> void:
	is_reloading = false
	_reload_left = 0.0

	var needed := data.magazine_size - ammo_in_magazine
	if infinite_reserve:
		# nothing drawn from a pool that doesn't exist yet - written this
		# way so the finite path below is the same code.
		ammo_in_magazine = data.magazine_size
	else:
		var taken := mini(needed, reserve_ammo)
		ammo_in_magazine += taken
		reserve_ammo -= taken

	_emit_ammo_changed()
	reload_finished.emit()


# --- Feel ---------------------------------------------------------------

## applies the weapon's spread cone to an aim direction.
##
## a disc perpendicular to the aim, offset by tan(cone angle) - the usual
## cheap cone approximation. random rather than a fixed pattern, so there's
## no memorisable spray.
##
## spread_scale multiplies the cone - player passes its ads bonus here, so
## the weapon stays unaware of ads.
func apply_spread(direction: Vector3, spread_scale: float = 1.0) -> Vector3:
	if data == null or data.spread_degrees * spread_scale <= 0.0:
		return direction

	var up := Vector3.UP
	if absf(direction.normalized().dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right := direction.cross(up).normalized()
	var real_up := right.cross(direction).normalized()

	var radius := tan(deg_to_rad(data.spread_degrees * spread_scale))
	var offset := right * randf_range(-radius, radius) + real_up * randf_range(-radius, radius)
	return (direction + offset).normalized()


## where the last shot ended, for the tracer and impact effect.
func get_last_shot_end() -> Vector3:
	return _last_shot_end


## muzzle position in world space, for the flash and tracer origin.
##
## uses the marker, not the flash light - they sit in the same spot in the
## placeholder scene but will drift apart once the viewmodel gets styled.
func get_muzzle_position() -> Vector3:
	if _muzzle_point != null:
		return _muzzle_point.global_position
	if _muzzle_flash != null:
		return _muzzle_flash.global_position
	return global_position


func _flash_muzzle() -> void:
	_flash_left = MUZZLE_FLASH_TIME
	if _muzzle_flash != null:
		_muzzle_flash.light_energy = MUZZLE_FLASH_ENERGY
	if _flash_mesh == null and _muzzle_point != null:
		# built on first use instead of in the scene, so every weapon gets
		# one for free.
		_flash_mesh = MuzzleFlashMesh.create(0.22)
		_muzzle_point.add_child(_flash_mesh)
	if _flash_mesh != null:
		# a different shape each shot, so automatic fire flickers instead
		# of showing one frozen sprite.
		_flash_mesh.visible = true
		_flash_mesh.rotation.z = randf() * TAU
		_flash_mesh.scale = Vector3.ONE * randf_range(0.75, 1.2)


## viewmodel's flash sprite, created on the first shot.
var _flash_mesh: MeshInstance3D = null


## advances the spray one round: camera takes its share of the pattern
## step as a recoil kick, bullets take the rest as _spray_offset.
func _request_recoil() -> void:
	if data == null:
		return
	var from := data.recoil_pattern(spray_index)
	spray_index += 1.0
	_since_shot = 0.0
	var to := data.recoil_pattern(spray_index)
	var jitter := randf_range(-data.recoil_yaw_degrees, data.recoil_yaw_degrees)
	var step := to - from + Vector2(0.0, jitter)
	var view := data.recoil_view_fraction
	_spray_offset = from * (1.0 - view)
	recoil_requested.emit(step.x * view, step.y * view)


## applies the spray to a shot's direction: the pattern's off-camera share
## plus bloom that grows with each round of the spray. the first round of
## a spray always goes exactly where the crosshair is, within spread_degrees.
func apply_spray(direction: Vector3, spread_scale: float = 1.0) -> Vector3:
	if data == null:
		return direction
	var shot := maxf(spray_index - 1.0, 0.0)
	var up := Vector3.UP
	if absf(direction.normalized().dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right := direction.cross(up).normalized()
	var real_up := right.cross(direction).normalized()
	var offset := _spray_offset * spread_scale
	var out := direction.normalized() \
		+ real_up * tan(deg_to_rad(offset.x)) + right * tan(deg_to_rad(offset.y))
	var bloom := minf(shot * data.spray_bloom, data.spray_bloom_max) * spread_scale
	if bloom > 0.0:
		var radius := tan(deg_to_rad(bloom))
		var angle := randf() * TAU
		var r := radius * sqrt(randf())
		out += right * cos(angle) * r + real_up * sin(angle) * r
	return out.normalized()


## current spray bloom in degrees, for the crosshair.
func get_bloom() -> float:
	if data == null:
		return 0.0
	return minf(spray_index * data.spray_bloom, data.spray_bloom_max)


func _emit_ammo_changed() -> void:
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)


# --- Debug --------------------------------------------------------------

## one-line summary for the debug overlay.
func debug_line() -> String:
	if data == null:
		return "unarmed"
	var reload_text := "  reloading %.1fs" % _reload_left if is_reloading else ""
	return "%s  %d/%d  %s%s" % [
		data.display_name,
		ammo_in_magazine,
		data.magazine_size,
		FireModeName(data.fire_mode),
		reload_text,
	]


## readable name for a WeaponData.FireMode value.
static func FireModeName(mode: WeaponData.FireMode) -> String:
	return WeaponData.FireMode.keys()[mode]
