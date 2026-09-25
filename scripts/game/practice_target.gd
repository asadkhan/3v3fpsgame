class_name PracticeTarget
extends StaticBody3D
## A shootable dummy for the Chapter 3 test range. It exists to be hit, not to
## be clever, but it is the thing that proves the damage architecture actually
## holds together.
##
## [b]Two colliders on purpose.[/b] The torso and the head are separate
## [StaticBody3D]s, not two shapes on one body. That is not fussiness - a
## hitscan hands back the [CollisionObject3D] it struck, and with two shapes on
## one body the weapon could not tell a head hit from a body hit without
## guessing from the hit height. With two bodies it simply asks which one it
## hit. The head is then [b]the proof that a hitbox need not be the entity[/b]:
## the head body carries no script at all, and [method Damageable.find_target]
## walks up to this node to find out who is responsible.
##
## [b]The player resolves hit zones by height instead.[/b] That is not an
## inconsistency to be tidied up later, it is a deliberate difference. A second
## collider on a player would have to be raised and lowered every time the
## crouch height changed, and any moment the two disagreed the player would
## develop a hole in the head. Splitting the players' single capsule by
## [member Player.head_hit_fraction] cannot get out of sync with the crouch,
## because it is derived from the same height number the collider is resized
## from. Both approaches are here so neither is untested.
##
## [b]Disposable.[/b] Chapter 7 deletes this with the rest of the grey box. No
## gameplay system should reference it by name - a weapon shoots anything that
## implements [Damageable], and this happens to be one of those things.

## Health before the first hit.
@export var max_health: int = 100

## How far through the health bar a hit has to land to be a headshot, as a
## fraction measured up the body. Kept here for the target's own head collider
## to line up with; the target does not use it, because its head is a real
## collider rather than a band.
@export var head_fraction: float = 0.18

## Whether this target has a head you can actually shoot.
##
## The two headless targets on the range exist to make headshot maths checkable:
## every round that reaches one of them is by definition a body round, so a
## headshot multiplier applied to the wrong thing would show up as a wrong
## number rather than as a subtle feel problem. The head [b]mesh[/b] is hidden
## along with the collider, because a head that looks hittable and is not is
## worse than no head at all.
@export var has_head_collider: bool = true

## Colour at full health.
@export var healthy_colour: Color = Color(0.78, 0.30, 0.26)

## Colour once destroyed.
@export var dead_colour: Color = Color(0.22, 0.21, 0.21)

## How long the body takes to topple after being destroyed, in seconds. A short
## animation rather than a snap, so it is obvious the target died and did not
## simply teleport.
@export var death_tip_seconds: float = 0.45

var health: int = 0

## The hit zone of the most recent accepted hit, a [enum Damageable.HitZone].
## Kept because it is genuinely useful beyond the tests - a target that shows
## whether the last round was a head hit is a target you can use to teach the
## difference - and because a body that silently swallows a headshot is exactly
## the bug worth being able to see.
var last_zone: int = Damageable.HitZone.BODY

## Whether this target has been destroyed. Read it through [method is_dead]
## rather than directly, so every damageable answers that question the same way.
var _dead: bool = false

## Emitted on every accepted hit, so a test can count hits without polling.
signal damaged(amount: float, zone: int, source: Node)
signal destroyed(source: Node)

@onready var _body_mesh: MeshInstance3D = $BodyMesh
@onready var _head: StaticBody3D = $Head
@onready var _head_mesh: MeshInstance3D = $Head/HeadMesh
@onready var _label: Label3D = $HealthLabel

## Resting transform, captured in [method _ready] so [method reset] can put the
## target back exactly where it started without the scene having to re-state it.
var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _topple: float = 0.0


func _ready() -> void:
	add_to_group(&"practice_targets")
	_spawn_transform = transform
	health = max_health
	_apply_head_presence()
	_refresh_visuals()


## Turns the head collider on or off to match [member has_head_collider], and
## hides the head mesh with it.
##
## Applied as a collider [b]layer[/b] of zero rather than by disabling the
## collision shape, so a ray aimed at where the head was still returns the
## torso behind it. Disabling the shape would leave a hole in the target that
## rounds pass straight through, which would quietly make the headless targets
## useless for testing falloff and penetration.
func _apply_head_presence() -> void:
	if _head == null:
		return
	if has_head_collider:
		_head.collision_layer = CollisionLayers.TARGET if not _dead else CollisionLayers.CORPSE
		_head_mesh.visible = true
	else:
		_head.collision_layer = 0
		_head_mesh.visible = false


# --- Damageable contract ------------------------------------------------

## Takes damage and returns how much was actually removed. [param zone] is
## accepted and recorded but does not change the outcome, because the caller
## has already multiplied the headshot multiplier into the amount by the time it
## arrives. Damage is flat per target, which is what makes the numbers on a
## practice target mean something when you compare a body hit to a head hit.
func apply_damage(amount: float, source: Node = null, zone: Damageable.HitZone = Damageable.HitZone.BODY) -> float:
	if _dead or amount <= 0.0:
		return 0.0

	var before := health
	health = maxi(0, health - int(round(amount)))
	var removed := float(before - health)
	last_zone = zone

	damaged.emit(removed, zone, source)
	if health == 0:
		_die(source)

	return removed


## Reports which part of the target was hit.
##
## The answer is "whichever body was struck" rather than "however high the hit
## landed", which is the whole point of this target's two colliders. A hit
## slightly below the head sphere counts as a body hit because the ray genuinely
## hit the body, not because of where it happened to be.
func resolve_hit_zone(_point: Vector3, collider: Object) -> Damageable.HitZone:
	return Damageable.HitZone.HEAD if collider == _head else Damageable.HitZone.BODY


func get_health() -> int:
	return health


func get_max_health() -> int:
	return max_health


## Whether this target has been destroyed.
##
## A method, not the [member _dead] field, and that is deliberate: it makes this
## answer the same question the same way [method Player.is_dead] does. A shooter
## asks every target it hits whether the hit finished it off, and it should not
## have to know whether to look for a method or a property first.
func is_dead() -> bool:
	return _dead


# --- Lifecycle ----------------------------------------------------------

## Puts the target back to full health and upright, so a test can run the same
## sequence more than once without rebuilding the scene.
func reset() -> void:
	health = max_health
	_dead = false
	_topple = 0.0
	transform = _spawn_transform
	collision_layer = CollisionLayers.TARGET
	_apply_head_presence()
	_refresh_visuals()


func _die(source: Node) -> void:
	_dead = true
	destroyed.emit(source)

	# Moved off the target layer because the two are no longer the same thing.
	# A destroyed dummy is scenery that happens to be a body: still solid, so it
	# can be shot again and still blocks the player, but no longer a live target
	# to be rewarded for shooting. This is the same split the player corpse gets
	# in [method Player.die].
	collision_layer = CollisionLayers.CORPSE
	_apply_head_presence()

	_refresh_visuals()


# --- Presentation -------------------------------------------------------

func _process(delta: float) -> void:
	if _dead and _topple < 1.0:
		_topple = minf(_topple + delta / maxf(death_tip_seconds, 0.01), 1.0)
		# Eased rather than linear, so the dummy falls over under its own weight
		# instead of pivoting at a constant rate like a machine part.
		#
		# The basis is rebuilt from the spawn transform rather than multiplied
		# into it, because the tilt has to happen in the parent's space: a
		# transform composed on top of its own would spin the dummy about its
		# own forward axis instead of tipping it over sideways onto the floor.
		var tilt := ease(_topple, 2.2) * PI * 0.5
		transform = Transform3D(
			Basis(Vector3.FORWARD, tilt) * _spawn_transform.basis,
			_spawn_transform.origin)
		# Sinks by half the body's width as it goes over, so the dummy ends up
		# lying on the floor rather than half sunk into it.
		position.y = _spawn_transform.origin.y - 0.3 * _topple


func _refresh_visuals() -> void:
	var health_colour := healthy_colour.lerp(dead_colour, 1.0 - float(health) / float(maxi(max_health, 1)))
	_body_mesh.material_override = _tint(health_colour)
	_head_mesh.material_override = _tint(health_colour.lightened(0.15))
	_label.text = "DOWN" if _dead else str(health)
	_label.modulate = Color(1.0, 0.4, 0.4) if _dead else Color(1.0, 1.0, 1.0)


## One shared material, made per target so tinting this dummy cannot tint the
## other ones. Meshes are shared sub-resources between targets in the scene, so
## writing to one of them directly would repaint the whole range.
func _tint(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material


## One line for the debug overlay.
func debug_line() -> String:
	return "%s  %d/%d%s" % [name, health, max_health, "  DOWN" if _dead else ""]
