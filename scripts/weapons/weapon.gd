class_name Weapon
extends Node3D
## One equipped weapon: its magazine, its trigger, its reload timer and the
## hitscan that turns a trigger pull into a line in the world.
##
## [b]What this owns versus what the player owns.[/b] The split is deliberate
## and it is the whole reason this is a separate node:
##
## - [b]The weapon owns[/b] when a shot happens, how much damage it does, what
##   it hits, recoil magnitude, magazine contents and reload progress.
## - [b]The player owns[/b] the camera, the aim direction, the input state and
##   the health that receives the damage. The player polls the trigger and
##   passes the aim ray in; it never decides whether a shot is legal.
##
## So [Player] contains no fire-rate maths, no magazine arithmetic and no
## knowledge of [member WeaponData], and this file contains no input polling and
## no reference to a camera. Chapter 3's brief asks for exactly that separation,
## and Chapter 4 needs it for a second reason: when the host has to validate a
## client's shot, it needs the origin and direction as two values it can be
## handed and re-run, not a ray buried inside a camera.
##
## [b]Why aim is passed in rather than read from a camera here.[/b] The ray
## starts at the camera, not the muzzle, so the crosshair tells the truth about
## where the bullet goes. The muzzle is only where the flash and the tracer
## start, which is why a shot can look like it comes from the barrel and still
## land exactly under the crosshair.
##
## [b]Not included, by design.[/b] No view bob, no ADS, no animation, no
## projectile path. [b]Not a singleton[/b] and not a global - it is a child of
## the player that owns it, so six players in a match means six of these.

# --- Configuration ------------------------------------------------------

## The stats. Assigned by [method equip] from the player's loadout; never
## written at runtime, because [method load] hands every player the same shared
## instance.
var data: WeaponData = null

## The body whose shots this weapon must not hit. Set by [method equip] so the
## raycast can exclude the shooter without this class needing to know what a
## Player is.
var shooter: CollisionObject3D = null

# --- Signals ------------------------------------------------------------
# Emitted rather than called directly on the player, so the weapon has no
# compile-time dependency on the player and Chapter 4 can drive the same
# signals from a replicated shot.

## A round left the barrel. Carries no hit information, because at the moment it
## is emitted nothing has been hit yet.
##
## The player listens and calls [method hitscan] with its own aim ray. That
## indirection is the point: this class has no camera and therefore no opinion
## about where the player is looking, and in Chapter 4 the host can call
## [method hitscan] itself with a client's ray without going anywhere near a
## camera.
signal fired

## The shot connected. [param killed] lets the hit marker change on a kill.
signal hit_confirmed(killed: bool, zone: int, health_left: int)

## A bullet landed somewhere and asked for an impact effect.
##
## [b]Deliberately a request, not a spawn.[/b] The weapon decides that a shot
## ended at a point; it does not know or care what that looks like. A local
## presentation node listens and draws it. That split is what keeps Chapter 4
## honest: the replicated shot is a gameplay fact, and the spark is something
## the machine that pressed the trigger draws locally, so the host validating
## someone else's shot cannot end up drawing sparks in front of the shooter.
signal impact_requested(position: Vector3, normal: Vector3, zone: int, surface: int)

## What a round ended on, so the presentation can tell a wall (spark, bullet
## hole) from a body (blood, no hole) from open air (nothing at all).
enum Surface {
	NONE,    ## Travelled its full range without hitting anything.
	WORLD,   ## Scenery.
	ENTITY,  ## Something damageable - a player or a practice target.
}

## The [enum Surface] of the most recent [method hitscan]. The host reads it to
## tell clients what a shot struck.
var last_surface: int = Surface.NONE

## The trigger was pulled with an empty magazine. Drives the dry-fire click.
signal dry_fired

## Reloading started. [param duration] is the full reload time.
signal reload_started(duration: float)

## Reloading finished, whether or not it was interrupted.
signal reload_finished

## Magazine contents changed, for the HUD and the debug overlay.
signal ammo_changed(magazine: int, reserve: int)

## Ask the player to kick the camera. Degrees, positive is upward.
signal recoil_requested(pitch_degrees: float, yaw_degrees: float)

# --- Ammunition ---------------------------------------------------------

## Rounds left in the magazine. The only ammunition number that changes by
## firing.
var ammo_in_magazine: int = 0

## Reserve ammunition. [b]Infinite in practice for now[/b], by design: players
## re-buy at the start of every round, so a per-match pool is a number nothing
## would ever consult. The field exists anyway because Chapter 5's buy system
## and any later limited-ammo mode both need the slot to be there, and adding
## it then would mean reshaping this API.
var reserve_ammo: int = 0

## When true, [method try_reload] always succeeds and never decrements
## [member reserve_ammo]. Set it false and the weapon draws down a real finite
## pool, with no other code changing.
var infinite_reserve: bool = true

## How many magazines' worth of rounds [member reserve_ammo] starts at when
## infinite reserve is off. Purely a starting figure for a mode that does not
## exist yet.
@export var starting_reserve_magazines: int = 10

# --- State --------------------------------------------------------------

## True between [signal reload_started] and [signal reload_finished].
var is_reloading: bool = false

## Seconds left of the current reload.
var _reload_left: float = 0.0

## Seconds until the next shot is allowed. This is the fire-rate limit, and it
## is the reason holding the trigger cannot outrun the weapon.
var _cooldown_left: float = 0.0

## Rounds left to fire in the current burst, for [constant WeaponData.FireMode.BURST].
var _burst_left: int = 0

## Seconds until the next round of a burst, which fires at the weapon's own
## interval rather than at the frame rate.
var _burst_timer: float = 0.0

## Set between the trigger going down and coming back up, so semi-auto can tell
## one pull from a hold.
var _trigger_held: bool = false

## Health actually removed by the most recent [method hitscan], 0.0 for a miss,
## scenery, or a target that was already down. The host reads this to tell a
## client whether its shot was a hit, so the hit marker only flashes for one.
var last_damage_dealt: float = 0.0

## Multiplies the time between shots. Set every frame by the owning player from
## how far into aiming down sights it is; 1.0 at the hip.
var fire_interval_scale: float = 1.0

## Where the last shot ended, for the tracer and the impact effect.
var _last_shot_end: Vector3 = Vector3.ZERO

@onready var _muzzle_flash: OmniLight3D = $MuzzleFlash if has_node("MuzzleFlash") else null
@onready var _muzzle_point: Marker3D = $MuzzlePoint if has_node("MuzzlePoint") else null

## Seconds the muzzle flash stays lit. Long enough to read at 60 fps, short
## enough not to become a permanent light source.
const MUZZLE_FLASH_TIME := 0.045

## Peak brightness of the muzzle flash.
const MUZZLE_FLASH_ENERGY := 3.0

var _flash_left: float = 0.0


# --- Lifecycle ----------------------------------------------------------

## Binds this weapon to its stats and its owner. Called by the player when the
## weapon is equipped, and safe to call again to re-equip after a loadout
## change.
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
	_emit_ammo_changed()
	_apply_model()


# --- Model ----------------------------------------------------------------------

## The model currently shown, built from [member WeaponData.viewmodel_scene].
var _model: Node3D = null
var _model_scene: PackedScene = null

## Where the model's Sight marker is, in this node's space. See
## [method get_sight_position].
var _sight_position: Vector3 = Vector3.ZERO
var _has_sight: bool = false

## The placeholder block rifle, kept for weapons without a model.
@onready var _viewmodel: Node3D = $ViewModel if has_node("ViewModel") else null
var _placeholder_parts: Array[Node] = []


## Swaps in the equipped weapon's model and moves the muzzle to its barrel.
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
	_has_sight = false
	for part in _placeholder_parts:
		(part as Node3D).visible = scene == null
	if scene == null:
		return

	_model = scene.instantiate() as Node3D
	_viewmodel.add_child(_model)
	# Shadows off: a viewmodel is drawn close to the camera and would throw a
	# huge shadow of the gun across the world.
	for mesh: GeometryInstance3D in _model.find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var muzzle := _model.find_child("Muzzle", true, false) as Node3D
	var sight := _model.find_child("Sight", true, false) as Node3D
	if muzzle != null and is_inside_tree():
		var at := to_local(muzzle.global_position)
		if _muzzle_point != null:
			_muzzle_point.position = at
		if _muzzle_flash != null:
			_muzzle_flash.position = at
	if sight != null and is_inside_tree():
		_sight_position = to_local(sight.global_position)
		_has_sight = true


## The sight's position in this node's space (which is the weapon mount's), or
## null for a weapon without a Sight marker. [PlayerAim] lines it up with the
## eye.
func get_sight_position() -> Variant:
	return _sight_position if _has_sight else null


## Hides the model while looking through a scope, when it would fill the view.
func set_model_hidden(hidden: bool) -> void:
	if _viewmodel != null:
		_viewmodel.visible = not hidden


# --- Public queries -----------------------------------------------------

## Whether the trigger would produce a shot right now. The HUD uses this to
## grey out the fire icon, and the test harness uses it to assert the fire-rate
## limit rather than inferring it from ammo counts.
##
## [b]Deliberately not gated on the burst counter.[/b] [method update_trigger]
## already decides whether a press may *start* a burst, and a burst that has
## started is in the middle of firing by definition. Folding that same
## condition in here meant the first round of every burst asked a question whose
## answer was always no - the counter had just been set to the burst size - so
## burst fire never fired at all.
func can_fire() -> bool:
	if data == null or is_reloading:
		return false
	if ammo_in_magazine <= 0:
		return false
	return _cooldown_left <= 0.0


func is_full() -> bool:
	return data != null and ammo_in_magazine >= data.magazine_size


# --- Trigger ------------------------------------------------------------

## The player calls this every frame with the current trigger state. Keeping
## the polling in the player is what lets [member Player.input_enabled] silence
## the weapon for a remote player without this class knowing anything about
## input.
##
## [param just_pressed] and [param held] are passed in rather than read from
## [code]Input[/code] here, for the same reason the aim ray is passed in: this
## class stays free of input and camera, so Chapter 4 can drive it from a
## network message instead.
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
			# One press starts the burst; holding does not queue another one.
			if just_pressed and _burst_left <= 0:
				_burst_left = maxi(data.burst_count, 1)
				_try_fire()
			elif _burst_left > 0:
				_burst_timer -= delta
				if _burst_timer <= 0.0:
					_try_fire()

	# Semi-auto needs to know the trigger came back up before the next pull
	# counts, which is the difference between one shot per click and one shot
	# per frame the mouse happens to be down.
	_trigger_held = held


## Advances cooldowns, the reload and the muzzle flash. The player calls this
## every frame regardless of trigger state, so a reload finishes and a flash
## fades even with the trigger released.
func _tick(delta: float) -> void:
	# Allowed to run up to one frame below zero, and that overshoot is carried
	# into the next shot's cooldown (see [method _try_fire]). Clamping at zero
	# instead rounds every interval up to a whole number of physics frames:
	# 0.09 s became 6 frames = 0.1 s, so a 667 RPM rifle fired at 600, and
	# small fire-rate differences (such as aiming's) vanished entirely. The
	# one-frame floor stops an idle weapon banking extra shots.
	_cooldown_left = maxf(_cooldown_left - delta, -delta)
	if _burst_timer > 0.0:
		_burst_timer = maxf(_burst_timer - delta, 0.0)

	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		if _muzzle_flash != null:
			# Faded on the way down rather than merely switched off.
			#
			# Assigning the light's own energy back to itself - which is what the
			# obvious-looking "0.0 if expired else unchanged" expression does -
			# leaves the flash at full brightness for ever after the first shot,
			# because nothing ever turns it back off. The room ends up lit by a
			# permanent muzzle.
			var t := _flash_left / MUZZLE_FLASH_TIME
			_muzzle_flash.light_energy = MUZZLE_FLASH_ENERGY * t * t
		if _flash_mesh != null:
			_flash_mesh.visible = _flash_left > 0.0

	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()


# --- Firing -------------------------------------------------------------

## Fires one round if the weapon allows it. Returns whether a shot happened, so
## a caller can tell "fired" from "refused" without reading the ammo count.
func _try_fire() -> bool:
	if not can_fire():
		# A click on an empty magazine is a dry fire, not a silent no-op. The
		# distinction is what makes an empty weapon feel broken rather than
		# merely unhelpful.
		if data != null and not is_reloading and ammo_in_magazine <= 0 \
				and _cooldown_left <= 0.0 and _burst_left <= 0:
			_cooldown_left = data.fire_interval
			dry_fired.emit()
		return false

	ammo_in_magazine -= 1
	# Scaled by aiming on the shots that start a new trigger pull; the rounds
	# inside a burst keep the weapon's own rhythm.
	_cooldown_left = data.fire_interval * fire_interval_scale + minf(_cooldown_left, 0.0)
	if _burst_left > 0:
		_burst_left -= 1
		if _burst_left > 0:
			_burst_timer = data.fire_interval
	_emit_ammo_changed()

	_flash_muzzle()
	_request_recoil()
	fired.emit()
	return true


## Performs the hitscan along an already-validated aim ray.
##
## Public and separate from [method _try_fire] on purpose: this is the part
## Chapter 4 re-runs on the host. The host can be handed a client's origin and
## direction and call this itself, rather than trusting a damage number the
## client sent.
##
## Returns the hit result, or an empty dictionary when the shot hit nothing.
func hitscan(origin: Vector3, direction: Vector3) -> Dictionary:
	last_damage_dealt = 0.0
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}

	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * data.max_range,
		CollisionLayers.WEAPON_MASK)

	# The muzzle sits inside the shooter's own capsule, so without this the
	# first thing every shot hits is the player holding the gun.
	if shooter != null:
		query.exclude = [shooter.get_rid()]

	# Starting inside a shape should not count as hitting it, which matters
	# for a target the player is standing inside after it drops.
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


## Turns a raycast hit into damage, through the [Damageable] contract. The
## weapon never writes to a target's fields.
##
## [param collider] is whatever the ray touched, which may be a child hitbox
## rather than the entity itself, so it is resolved upwards first. Only then is
## the hit zone asked for, because the target - not the weapon - knows which of
## its own colliders was struck.
func _apply_damage_to(result: Dictionary, origin: Vector3, direction: Vector3) -> void:
	var collider: Object = result.get("collider")
	var point: Vector3 = result.get("position", _last_shot_end)
	var normal: Vector3 = result.get("normal", -direction)

	# A static body is scenery. The world stops bullets without being damageable.
	var target := Damageable.find_target(collider)
	if not Damageable.is_damageable(target):
		# A wall still gets a mark on it. Where the round stopped is a fact
		# about the world; whether anything was hurt is a separate one.
		last_surface = Surface.WORLD
		impact_requested.emit(point, normal, Damageable.HitZone.BODY, Surface.WORLD)
		return

	# Measured here, not read from the result.
	#
	# [method PhysicsDirectSpaceState3D.intersect_ray] does not put a distance
	# in its dictionary - it reports the hit position, and the caller is
	# expected to work the distance out. Reading a "distance" key that is not
	# there returns the default of 0.0, and 0.0 is full damage, so the falloff
	# curve silently became a straight line: every shot at any range did
	# maximum damage and the falloff fields on the resource did nothing. It is
	# computed from the origin that was actually used rather than from the
	# muzzle, so it matches the ray the crosshair is drawing.
	var distance := origin.distance_to(point)
	var zone := Damageable.resolve_zone(target, point, collider)
	var amount := data.damage_at_distance(distance)
	if zone == Damageable.HitZone.HEAD:
		amount *= data.headshot_multiplier

	var dealt := Damageable.deal_damage(target, amount, shooter, zone)
	last_damage_dealt = dealt

	# Emitted before the early-out so a body that is already down still shows
	# where the round went. A hit marker is feedback about the player's
	# accuracy, not a reward for damage.
	last_surface = Surface.ENTITY
	impact_requested.emit(point, normal, zone, Surface.ENTITY)

	if dealt <= 0.0:
		# Connected but did no damage - already dead, or a target that declined
		# the hit. No hit marker, because the player did not achieve anything.
		return

	var health_left := -1
	if target.has_method(&"get_health"):
		health_left = int(target.call(&"get_health"))
	var killed := target.has_method(&"is_dead") and bool(target.call(&"is_dead"))
	hit_confirmed.emit(killed, zone, health_left)


## Starts a reload if one is needed and allowed. Returns whether it started.
func try_reload() -> bool:
	if data == null or is_reloading or is_full():
		return false
	if not infinite_reserve and reserve_ammo <= 0:
		return false

	is_reloading = true
	_reload_left = data.reload_time
	reload_started.emit(data.reload_time)
	return true


## Cancels a reload in progress and keeps whatever is already in the magazine.
## Chapter 4 uses this when a player dies mid-reload.
func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	_reload_left = 0.0
	reload_finished.emit()


func _finish_reload() -> void:
	is_reloading = false
	_reload_left = 0.0

	var needed := data.magazine_size - ammo_in_magazine
	if infinite_reserve:
		# Nothing is drawn from a pool that does not exist yet. The subtraction
		# is still written out so the finite path below is the same code.
		ammo_in_magazine = data.magazine_size
	else:
		var taken := mini(needed, reserve_ammo)
		ammo_in_magazine += taken
		reserve_ammo -= taken

	_emit_ammo_changed()
	reload_finished.emit()


# --- Feel ---------------------------------------------------------------

## Applies the weapon's spread cone to an aim direction.
##
## A disc perpendicular to the aim, offset by the tangent of the cone angle,
## which is the standard cheap approximation of a cone. Random rather than a
## fixed pattern on purpose: a memorisable spray is another game's signature.
##
## [param spread_scale] multiplies the cone - the player passes its aiming
## bonus here, so the weapon itself stays unaware of ADS.
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


## Where the last shot ended, for the tracer and the impact effect.
func get_last_shot_end() -> Vector3:
	return _last_shot_end


## Muzzle position in world space, for the flash and the tracer origin.
##
## The marker, not the flash light. They sit in the same place in the
## placeholder scene, but a light is presentation and a marker is a fact about
## where the barrel ends, and the two are going to drift apart the moment
## anyone styles the viewmodel.
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
		# Built on first use rather than in the scene, so every weapon scene gets
		# one without having to author it.
		_flash_mesh = MuzzleFlashMesh.create(0.22)
		_muzzle_point.add_child(_flash_mesh)
	if _flash_mesh != null:
		# A different shape every shot, so automatic fire flickers rather than
		# showing one frozen sprite.
		_flash_mesh.visible = true
		_flash_mesh.rotation.z = randf() * TAU
		_flash_mesh.scale = Vector3.ONE * randf_range(0.75, 1.2)


## The viewmodel's flash sprite, created on the first shot.
var _flash_mesh: MeshInstance3D = null


func _request_recoil() -> void:
	if data == null:
		return
	var pitch := data.recoil_kick_degrees
	var yaw := randf_range(-data.recoil_yaw_degrees, data.recoil_yaw_degrees)
	if pitch > 0.0 or yaw != 0.0:
		recoil_requested.emit(pitch, yaw)


func _emit_ammo_changed() -> void:
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)


# --- Debug --------------------------------------------------------------

## One-line summary for the debug overlay.
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


## Readable name for a [enum WeaponData.FireMode] value.
static func FireModeName(mode: WeaponData.FireMode) -> String:
	return WeaponData.FireMode.keys()[mode]
