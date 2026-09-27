class_name WeaponData
extends Resource
## the stats for one weapon. data only - no firing logic lives here.
##
## it's a Resource (not RefCounted) because these numbers never change during
## a match and are authored by hand in the editor, saved as .tres files.
## one instance is shared by every player using that weapon.
##
## to make one: FileSystem dock -> right-click res://data/ -> New Resource ->
## WeaponData. see res://data/weapons/halberd.tres for an example.
##
## warning: don't change these values at runtime. load() caches resources, so
## every player holding the same weapon shares one instance - writing
## weapon.damage = 50 would silently buff everyone and never get saved.
## per-player state (ammo, trigger held, current recoil) lives on the
## runtime Weapon object instead. duplicate() if you genuinely need a copy.

## how a weapon is fired - whether holding the trigger keeps shooting.
enum FireMode {
	SEMI_AUTO, ## one shot per click, must release and re-click.
	AUTO,      ## keeps firing while the trigger is held.
	BURST,     ## fires a fixed group per click.
}

## broad category, used by the buy menu to sort/label - not a behaviour switch.
enum Category {
	PISTOL, ## cheap sidearm, always available, low damage.
	SUBMACHINE_GUN, ## high rate of fire, low range and damage.
	RIFLE, ## the general-purpose full auto weapon.
	SNIPER, ## slow, very high damage, needs a scope.
	SHOTGUN, ## many pellets, huge falloff.
	HEAVY, ## slow, high damage, expensive.
}

# --- Identity -----------------------------------------------------------

## stable id used in saves, network and buy menu. lowercase, unique, never
## shown to a player.
@export var weapon_id: StringName = &""

## name shown in the hud and buy menu - the weapon's real name, not a placeholder.
@export var display_name: String = "Unnamed"

@export var category: Category = Category.RIFLE

# --- Damage -------------------------------------------------------------

## damage at point-blank range, before falloff.
@export var damage: float = 25.0

## headshot damage multiplier. 2.0 = double damage.
@export var headshot_multiplier: float = 2.0

## fraction of damage still dealt at max range. 0.5 = half damage at max
## range. 1.0 disables falloff.
@export_range(0.0, 1.0, 0.05) var falloff_multiplier: float = 0.5

## distance in metres where falloff reaches full effect.
@export var max_range: float = 50.0

# --- Fire behaviour -----------------------------------------------------

@export var fire_mode: FireMode = FireMode.AUTO

## seconds between shots. 0.1 = 600 rounds per minute. (no separate rpm
## field - it's the same number with worse rounding, keep one source of truth.)
@export_range(0.01, 2.0, 0.01) var fire_interval: float = 0.1

## shots per trigger pull in burst mode.
@export_range(1, 10) var burst_count: int = 3

## cone half-angle in degrees shots can land in. 0 = perfect accuracy,
## higher = worse.
@export_range(0.0, 10.0, 0.1) var spread_degrees: float = 0.5

# --- Ammunition ---------------------------------------------------------

## rounds loaded per magazine.
@export_range(1, 100) var magazine_size: int = 30

## seconds to complete a reload.
@export_range(0.0, 10.0, 0.1) var reload_time: float = 2.5

## no reserve ammo count on purpose - players re-buy every round, so reserve
## ammo is infinite for now. Weapon still exposes reserve_ammo so a
## limited-ammo mode could be added later without reshaping the api.

# --- Economy ------------------------------------------------------------

## buy menu cost. zero means it can't be bought and is issued automatically.
@export var price: int = 0

# --- Recoil -------------------------------------------------------------

## how far one shot kicks the camera upwards, in degrees. applied as a
## decaying offset on top of the player's own aim, so the view always
## returns to where they were actually looking. see Player.add_recoil.
@export_range(0.0, 10.0, 0.05) var recoil_kick_degrees: float = 0.7

## random sideways jitter per shot, in degrees, on top of the pattern.
@export_range(0.0, 5.0, 0.05) var recoil_yaw_degrees: float = 0.25

## spray pattern (see recoil_pattern): first recoil_vertical_shots rounds
## climb straight up by recoil_kick_degrees each, up to recoil_max_pitch;
## after that it sways side to side by up to recoil_sway_degrees, same
## shape every time, so it's learnable and can be pulled against.
@export_range(0, 30) var recoil_vertical_shots: int = 6
## opening rounds of a spray barely climb (each kicks this fraction of
## recoil_kick_degrees), so taps and short bursts stay on target.
@export_range(0, 10) var recoil_flat_shots: int = 2
@export_range(0.0, 1.0, 0.05) var recoil_flat_scale: float = 0.2
@export_range(0.0, 20.0, 0.1) var recoil_max_pitch: float = 5.0
@export_range(0.0, 10.0, 0.05) var recoil_sway_degrees: float = 1.2
## how much of the pattern moves the camera vs. the bullets, so a spray
## climbs above where the crosshair sits.
@export_range(0.0, 1.0, 0.05) var recoil_view_fraction: float = 0.55
## seconds off the trigger for the pattern to reset to the first shot.
@export_range(0.05, 2.0, 0.01) var recoil_reset_time: float = 0.35
## extra spread per round of a spray, in degrees, up to spray_bloom_max -
## first shot is as accurate as spread_degrees allows.
@export_range(0.0, 2.0, 0.01) var spray_bloom: float = 0.1
@export_range(0.0, 10.0, 0.05) var spray_bloom_max: float = 1.5
## how hard the gun rears up in the hands per shot, and how much the camera
## shakes. heavier gun = bigger both.
@export_range(0.0, 20.0, 0.1) var viewmodel_kick_degrees: float = 3.0
@export_range(0.0, 2.0, 0.05) var camera_shake: float = 0.3

## how fast the camera returns to true aim, degrees per second. higher =
## snappier recovery, keeps a burst from permanently walking the view off target.
@export_range(1.0, 180.0, 1.0) var recoil_recovery_degrees: float = 55.0

## how far the viewmodel pushes back along its axis when fired, in metres.
## purely cosmetic.
@export_range(0.0, 0.3, 0.005) var viewmodel_kick: float = 0.045

# --- Movement penalty ---------------------------------------------------

## movement speed multiplier while this weapon is equipped. 1.0 = no penalty,
## below 1.0 makes a heavy weapon cost something.
@export_range(0.1, 1.0, 0.01) var move_speed_multiplier: float = 0.95

## whether holding this weapon prevents sprinting.
@export var blocks_sprint: bool = false

# --- Aiming down sights -------------------------------------------------------
# a light zoom that tightens spread and steadies recoil, paid for with slower
# movement (and sometimes slower fire rate). hip fire stays viable. each
# value is a multiplier at full aim, blended in over ads_time.

## fov magnification while aimed. 1.0 = no zoom.
@export_range(1.0, 4.0, 0.05) var ads_zoom: float = 1.2

## seconds to go from hip to fully aimed (and back).
@export_range(0.0, 1.0, 0.01) var ads_time: float = 0.15

## spread while aimed, as a fraction of spread_degrees.
@export_range(0.0, 1.0, 0.05) var ads_spread_multiplier: float = 0.5

## recoil kick while aimed, as a fraction of the hip kick.
@export_range(0.0, 1.0, 0.05) var ads_recoil_multiplier: float = 0.8

## movement speed while aimed, on top of move_speed_multiplier.
@export_range(0.1, 1.0, 0.01) var ads_move_multiplier: float = 0.76

## time between shots while aimed, as a multiple of fire_interval. above
## 1.0 fires slower.
@export_range(0.5, 2.0, 0.01) var ads_fire_interval_multiplier: float = 1.0

## where the weapon moves while aimed, relative to hip position: towards
## screen centre and slightly closer. tuned per model to line sights up
## with the crosshair.
@export var ads_viewmodel_offset: Vector3 = Vector3(-0.22, 0.03, 0.02)

# --- Presentation -------------------------------------------------------------

## the weapon's model scene (scenes/weapons/models/): mesh pointing down -Z
## at real-world scale, with a Muzzle marker for tracers/flash and a Sight
## marker aiming lines up with. used for both the first-person viewmodel and
## the gun other players see. null keeps the placeholder block model.
@export var viewmodel_scene: PackedScene

## how far in front of the eye the Sight marker sits when fully aimed, in
## metres. with a Sight marker this replaces ads_viewmodel_offset.
@export_range(0.05, 0.6, 0.01) var ads_sight_distance: float = 0.26

## aiming shows a scope overlay (reticle + dark surround) and hides the
## weapon model once fully aimed - for scoped guns.
@export var scope_overlay: bool = false

@export_group("Melee")
## a blade instead of a gun: no ammo, no reload, no tracer. primary attack
## (damage, fire_interval) is a quick slash; alternate (right mouse) is a
## heavy stab. both reach max_range and land partway through the swing.
@export var is_melee: bool = false
@export var heavy_damage: float = 80.0
@export var heavy_interval: float = 1.0
## seconds from the click to the blade connecting.
@export var melee_hit_delay: float = 0.12
@export var heavy_hit_delay: float = 0.36
## damage multiplier from behind (victim facing away from attacker).
@export var backstab_multiplier: float = 2.0


## where the shot-th round of a spray goes (0 is the first), as
## (pitch up, yaw right) in degrees off the aim.
func recoil_pattern(shot: float) -> Vector2:
	var flat := float(recoil_flat_shots)
	var lifted := shot * recoil_flat_scale if shot <= flat \
		else flat * recoil_flat_scale + (shot - flat)
	var climb := minf(lifted, float(recoil_vertical_shots)) * recoil_kick_degrees
	var over := maxf(shot - float(recoil_vertical_shots), 0.0)
	var pitch := minf(climb + over * recoil_kick_degrees * 0.12, recoil_max_pitch)
	# one slow swing each way then back, same every spray: right first.
	var yaw := recoil_sway_degrees * sin(over * 0.55) if over > 0.0 else 0.0
	return Vector2(pitch, yaw)


func is_buyable() -> bool:
	return price > 0


## damage dealt at distance metres, after linear falloff. kept here so the
## shot logic and the hud's range indicator always agree.
func damage_at_distance(distance: float) -> float:
	if distance <= 0.0 or max_range <= 0.0:
		return damage

	# clamped so shots past max_range stop losing health instead of healing
	# the target.
	var t: float = clampf(distance / max_range, 0.0, 1.0)
	return damage * lerpf(1.0, falloff_multiplier, t)


## rounds per minute, for display. derived from fire_interval so they can
## never disagree.
func rounds_per_minute() -> float:
	return 60.0 / maxf(fire_interval, 0.0001)


## rough cost-to-damage ratio for balancing. crude - ignores fire rate,
## accuracy and range.
func value_per_damage() -> float:
	if damage <= 0.0:
		return 0.0
	return float(price) / damage


## warns about values that won't work. call when loading a weapon so a typo
## in a .tres file is caught here instead of surfacing as a gun that won't fire.
func validate() -> bool:
	var ok := true

	if weapon_id == &"":
		push_warning("WeaponData '%s' has no weapon_id." % display_name)
		ok = false

	if damage <= 0.0:
		push_warning("WeaponData '%s' has no damage." % display_name)
		ok = false

	if fire_interval <= 0.0:
		push_warning("WeaponData '%s' has a fire_interval of %f, which cannot fire." % [display_name, fire_interval])
		ok = false

	if magazine_size <= 0:
		push_warning("WeaponData '%s' has an empty magazine." % display_name)
		ok = false

	if max_range <= 0.0:
		push_warning("WeaponData '%s' has no range." % display_name)
		ok = false

	return ok
