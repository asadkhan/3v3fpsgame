class_name PracticeTarget
extends StaticBody3D
## a shootable dummy for the test range. exists to be hit, and to prove the
## damage architecture holds together.
##
## torso and head are two separate StaticBody3Ds, not two shapes on one body -
## that way a hitscan can tell head from body just from which collider it
## hit, no guessing from hit height. the head has no script on it at all;
## Damageable.find_target walks up to this node to find who's responsible.
##
## the player instead resolves hit zones by height, which is a deliberate
## difference: a real head collider on a player would need to move every
## time crouch height changed, risking a gap. this target and the player
## cover both approaches so neither goes untested.

## health before the first hit.
@export var max_health: int = 100

## how far up the body a hit needs to land to count as a headshot (fraction
## of height). kept for the head collider to line up with; unused by this
## target itself since its head is a real collider, not a height band.
@export var head_fraction: float = 0.18

## whether this target has a head you can actually shoot.
##
## the headless targets on the range exist to make headshot math checkable:
## every hit on one of them is guaranteed a body hit, so a wrong headshot
## multiplier shows up as a wrong number instead of a subtle feel bug. the
## head mesh hides along with the collider so it never looks hittable when it isn't.
@export var has_head_collider: bool = true

## colour at full health.
@export var healthy_colour: Color = Color(0.78, 0.30, 0.26)

## colour once destroyed.
@export var dead_colour: Color = Color(0.22, 0.21, 0.21)

## how long the body takes to topple after being destroyed, in seconds.
@export var death_tip_seconds: float = 0.45

var health: int = 0

## hit zone of the most recent accepted hit. useful for showing whether the
## last round was a headshot, and for catching a headshot that got silently
## swallowed as a body hit.
var last_zone: int = Damageable.HitZone.BODY

## whether this target has been destroyed. read through is_dead() so every
## damageable answers that question the same way.
var _dead: bool = false

## emitted on every accepted hit, so a test can count hits without polling.
signal damaged(amount: float, zone: int, source: Node)
signal destroyed(source: Node)

@onready var _body_mesh: MeshInstance3D = $BodyMesh
@onready var _head: StaticBody3D = $Head
@onready var _head_mesh: MeshInstance3D = $Head/HeadMesh
@onready var _label: Label3D = $HealthLabel

## resting transform, captured in _ready() so reset() can put the target
## back where it started.
var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _topple: float = 0.0


func _ready() -> void:
	add_to_group(&"practice_targets")
	_spawn_transform = transform
	health = max_health
	_apply_head_presence()
	_refresh_visuals()


## turns the head collider on/off to match has_head_collider, hiding the
## mesh with it. sets the collision layer to zero rather than disabling the
## shape, so a ray aimed at the missing head still hits the torso behind it
## instead of passing straight through.
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

## takes damage, returns how much was actually removed. zone is recorded but
## doesn't change the outcome - the caller already applied the headshot
## multiplier before this gets called.
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


## reports which part of the target was hit - whichever body the ray struck,
## not how high the hit landed. that's the whole point of the two colliders.
func resolve_hit_zone(_point: Vector3, collider: Object) -> Damageable.HitZone:
	return Damageable.HitZone.HEAD if collider == _head else Damageable.HitZone.BODY


func get_health() -> int:
	return health


func get_max_health() -> int:
	return max_health


## whether this target has been destroyed. a method rather than exposing
## _dead directly, so it matches Player.is_dead()'s shape.
func is_dead() -> bool:
	return _dead


# --- Lifecycle ----------------------------------------------------------

## puts the target back to full health and upright, so a test can run the
## same sequence again without rebuilding the scene.
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

	# moved off the target layer: a destroyed dummy is scenery now, still solid
	# and shootable, but no longer a live target worth rewarding. same split
	# as the player corpse gets in Player.die().
	collision_layer = CollisionLayers.CORPSE
	_apply_head_presence()

	_refresh_visuals()


# --- Presentation -------------------------------------------------------

func _process(delta: float) -> void:
	if _dead and _topple < 1.0:
		_topple = minf(_topple + delta / maxf(death_tip_seconds, 0.01), 1.0)
		# eased, not linear, so it falls like dead weight instead of a machine part.
		# basis rebuilt from the spawn transform (not multiplied into the
		# current one) so the tilt happens in the parent's space - otherwise
		# it'd spin around its own forward axis instead of tipping over.
		var tilt := ease(_topple, 2.2) * PI * 0.5
		transform = Transform3D(
			Basis(Vector3.FORWARD, tilt) * _spawn_transform.basis,
			_spawn_transform.origin)
		# sinks a bit as it goes over so it ends up lying on the floor, not in it.
		position.y = _spawn_transform.origin.y - 0.3 * _topple


func _refresh_visuals() -> void:
	var health_colour := healthy_colour.lerp(dead_colour, 1.0 - float(health) / float(maxi(max_health, 1)))
	_body_mesh.material_override = _tint(health_colour)
	_head_mesh.material_override = _tint(health_colour.lightened(0.15))
	_label.text = "DOWN" if _dead else str(health)
	_label.modulate = Color(1.0, 0.4, 0.4) if _dead else Color(1.0, 1.0, 1.0)


## own material per target, so tinting one dummy doesn't repaint the others
## (meshes are shared sub-resources between targets in the scene).
func _tint(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material


## one line for the debug overlay.
func debug_line() -> String:
	return "%s  %d/%d%s" % [name, health, max_health, "  DOWN" if _dead else ""]
