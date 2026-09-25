class_name WeaponData
extends Resource
## The stats for one weapon. Data only - no firing logic lives here.
##
## [b]Why this is a Resource and not a RefCounted:[/b] the other three data
## types ([PlayerState], [MatchState], [Team]) are runtime state that changes
## as the game runs, so [RefCounted] is right for them. A weapon's stats never
## change during a match, and they are authored by hand in the editor and
## saved to [code]res://data/[/code] as [code].tres[/code] files. That is
## precisely what a [Resource] is for: it shows up in the Inspector, it can be
## saved and loaded from disk, and one instance can be shared by every player
## using that weapon instead of being rebuilt per spawn.
##
## [b]Why there is no behaviour here:[/b] Chapter 3 adds firing, recoil,
## reloads and ballistics. Keeping [b]what a weapon is[/b] separate from
## [b]what a weapon does[/b] is what lets the weapon logic be written and
## tested against plain numbers, and it means rebalancing is an edit to a
## [code].tres[/code] file rather than a change to code.
##
## [b]Creating one:[/b] in the FileSystem dock, right-click [code]res://data/[/code]
## -> Create New -> Resource, search for [b]WeaponData[/b], then fill in the
## Inspector. See [code]res://data/weapons/halberd.tres[/code] for a
## filled-in example.
##
## [b]Warning - do not change these values at runtime.[/b] [method load] is
## cached, so every player holding the Halberd gets the [b]same[/b] instance,
## not a copy. Writing [code]weapon.damage = 50[/code] would silently buff
## everyone using that weapon, and the change would not be saved. Per-player
## state that genuinely does change - ammo in the magazine, whether the trigger
## is held, current recoil - belongs in a separate runtime object in Chapter 3,
## not on this class. Use [method Resource.duplicate] if a private copy is
## genuinely needed.

## How a weapon is fired. Determines whether holding the trigger keeps
## shooting, which the trigger logic in Chapter 3 will branch on.
enum FireMode {
	SEMI_AUTO, ## One shot per click. Player must release and re-click.
	AUTO,      ## Keeps firing while the trigger is held.
	BURST,     ## Fires a fixed group per click. Added in Chapter 3.
}

## Broad category. Chapter 5's buy menu and any future AI use this to decide
## what a weapon is for; it is not a behaviour switch.
enum Category {
	PISTOL, ## Cheap sidearm. Always available, low damage.
	SUBMACHINE_GUN, ## High rate of fire, low range and damage.
	RIFLE, ## The general-purpose full auto weapon.
	SNIPER, ## Slow, very high damage, needs a scope.
	SHOTGUN, ## Many pellets, huge falloff. Defined here, implemented later.
	HEAVY, ## Slow, high damage, expensive.
}

# --- Identity -----------------------------------------------------------

## Stable identifier used in saves, the network, and the buy menu. Keep it
## lowercase and unique; never show this to a player.
@export var weapon_id: StringName = &""

## Name shown in the HUD and buy menu. This is player-facing, so it should be
## the weapon's real name in the game, not a placeholder.
@export var display_name: String = "Unnamed"

@export var category: Category = Category.RIFLE

# --- Damage -------------------------------------------------------------

## Damage at point-blank range, before falloff.
@export var damage: float = 25.0

## Multiplier applied when the shot lands on the head. A value of 2.0 means a
## headshot does double damage.
@export var headshot_multiplier: float = 2.0

## The fraction of [member damage] still dealt at maximum range. 0.5 means a
## shot at maximum range does half damage. 1.0 disables falloff.
@export_range(0.0, 1.0, 0.05) var falloff_multiplier: float = 0.5

## Distance in metres at which [member falloff] reaches full effect. Beyond
## this the weapon does [member falloff_multiplier] x [member damage].
@export var max_range: float = 50.0

# --- Fire behaviour -----------------------------------------------------

@export var fire_mode: FireMode = FireMode.AUTO

## Seconds between shots. A value of 0.1 is 600 rounds per minute. A
## designer-facing rounds-per-minute field is deliberately left out: it is the
## same number with a worse rounding error, and two ways to say one thing is
## how balance values drift apart.
@export_range(0.01, 2.0, 0.01) var fire_interval: float = 0.1

## Shots per trigger pull in [constant FireMode.BURST].
@export_range(1, 10) var burst_count: int = 3

## Cone half-angle in degrees that shots can land in, from straight down the
## crosshair. 0.0 is perfect accuracy; higher values are worse. Chapter 3
## turns this into actual aim deviation.
@export_range(0.0, 10.0, 0.1) var spread_degrees: float = 0.5

# --- Ammunition ---------------------------------------------------------

## Rounds loaded per magazine.
@export_range(1, 100) var magazine_size: int = 30

## Seconds to complete a reload.
@export_range(0.0, 10.0, 0.1) var reload_time: float = 2.5

## [b]No reserve ammo count on purpose.[/b] In a round-based tactical shooter
## players re-buy at the start of every round, so a per-match reserve would be
## a stat that is never meaningfully consulted. If the design later adds a
## limited-ammo mode, that is the moment to add it - and it belongs here
## rather than being tracked per player.
##
## This was re-confirmed when Chapter 3 was specified: reserve ammunition is
## infinite for now. The [Weapon] runtime object still exposes a
## [member Weapon.reserve_ammo] slot, so a finite-reserve mode can be switched
## on later without reshaping the weapon API.

# --- Economy ------------------------------------------------------------

## Cost in the buy menu, Chapter 5. Zero means it cannot be bought and is
## issued automatically.
@export var price: int = 0

# --- Recoil -------------------------------------------------------------
# Added in Chapter 3. Chapter 1 authored the damage, ballistics and ammunition
# numbers but had no field for recoil, because recoil is a firing behaviour
# rather than a statistic - and at the time nothing fired. It belongs here for
# the same reason [member damage] does: it is a per-weapon balance number a
# designer sets in the Inspector, not something the firing code should invent.

## How far one shot kicks the camera upwards, in degrees. Applied as a decaying
## offset on top of the player's own aim rather than by rotating the player, so
## the view always returns to where the player was actually looking. See
## [method Player.add_recoil].
@export_range(0.0, 10.0, 0.05) var recoil_kick_degrees: float = 0.7

## Random sideways kick per shot, in degrees. Small, and deliberately random
## rather than a fixed pattern: a learnable spray pattern is another game's
## signature, and this game should not have one.
@export_range(0.0, 5.0, 0.05) var recoil_yaw_degrees: float = 0.25

## How quickly the camera returns to the player's true aim, in degrees per
## second. Fast recovery keeps a burst from permanently walking the view off
## target, which is the "uncontrollable recoil" the Chapter 3 brief rules out.
@export_range(1.0, 180.0, 1.0) var recoil_recovery_degrees: float = 55.0

## How far the viewmodel is pushed back along its own axis when fired, in
## metres. Purely cosmetic - the muzzle flash and the tracer are what tell the
## player a shot happened.
@export_range(0.0, 0.3, 0.005) var viewmodel_kick: float = 0.045

# --- Movement penalty ---------------------------------------------------
# Also a Chapter 3 addition, and also per-weapon because the Chapter 3 brief
# lists it as one of the things that should differ between weapons.

## Multiplier applied to the player's movement speed while this weapon is
## equipped. 1.0 is no penalty. Values below 1.0 make carrying a heavy weapon a
## real cost without touching the player's own speed exports.
@export_range(0.1, 1.0, 0.01) var move_speed_multiplier: float = 0.95

## Whether holding this weapon prevents sprinting. A rifle that can be
## sprint-fired and a rifle that cannot are very different weapons, and that
## should be a decision in the data rather than an if-statement in the player.
@export var blocks_sprint: bool = false


## Whether this weapon can be picked in a buy menu at all.
func is_buyable() -> bool:
	return price > 0


## Damage dealt at [param distance] metres, after linear falloff. This is the
## one piece of maths kept on the data class, because both the shot logic in
## Chapter 3 and the HUD's range indicator need to agree on the answer, and
## two copies of a formula always drift apart.
func damage_at_distance(distance: float) -> float:
	if distance <= 0.0 or max_range <= 0.0:
		return damage

	# Clamped so shots past max_range stop losing health rather than going
	# negative and healing the target.
	var t: float = clampf(distance / max_range, 0.0, 1.0)
	return damage * lerpf(1.0, falloff_multiplier, t)


## Rounds per minute, for display. Derived from [member fire_interval] rather
## than stored, so the two can never disagree.
func rounds_per_minute() -> float:
	return 60.0 / maxf(fire_interval, 0.0001)


## Rough cost-to-damage ratio, useful when balancing the roster in Chapter 5.
## Deliberately crude - it compares raw damage only, and ignores fire rate,
## accuracy and range, so treat it as a starting point for questions rather
## than an answer.
func value_per_damage() -> float:
	if damage <= 0.0:
		return 0.0
	return float(price) / damage


## Fills in anything left blank and warns about values that will not work.
## Call this when loading a weapon so a typo in a .tres file is reported once,
## where it can be found, rather than surfacing later as a weapon that will
## not fire.
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
