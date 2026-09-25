class_name ImpactEffect
extends Node3D
## The spark where a round stops. Spawned by [WeaponFx], lives for a fraction of
## a second and deletes itself.
##
## It draws itself from code rather than from a scene file because the only
## interesting part is the curve: it swells from nothing, fades out, and dies.
## Everything it knows is three numbers on the script, and a [QuadMesh] with a
## transparent material is a better fit for that than a hand-authored node tree
## that would then need a second script to animate.
##
## [b]Local only.[/b] Nothing spawns this directly. The weapon asks for an
## impact and a presentation node on the machine that pulled the trigger decides
## whether to draw one, which is what keeps Chapter 4 from painting a spark in
## the wrong place on a client that never fired.

## How long the effect lives, in seconds.
@export var lifetime: float = 0.22

## Size at the moment of impact, and the size it grows to before vanishing.
@export var start_scale: float = 0.06
@export var end_scale: float = 0.24

## Colour of a hit on flesh versus a hit on scenery. The caller decides which,
## because only the weapon knows what it hit.
@export var world_colour: Color = Color(0.85, 0.82, 0.75, 0.9)
@export var flesh_colour: Color = Color(0.9, 0.2, 0.2, 0.95)

@onready var _mesh: MeshInstance3D = $Quad

var _age: float = 0.0


## Positions the effect against a surface and picks the colour from the hit zone.
## Called immediately after instancing, before the node is added to the tree, so
## it is never visible for a frame in the wrong place.
func setup(at: Vector3, normal: Vector3, zone: int) -> void:
	position = at
	# Lifted off the surface by the tiniest amount. Sitting exactly on the
	# surface means the quad is half-buried in the wall it is supposed to be
	# marking, and the whole effect z-fights and disappears.
	position += normal.normalized() * 0.012

	# Oriented to face along the surface normal, so the mark lies flat on a
	# wall and flat on the floor rather than only ever facing the world.
	var up := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	var reference := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var basis := Basis.looking_at(up, reference)
	transform = Transform3D(basis, position)

	var material := StandardMaterial3D.new()
	material.albedo_color = flesh_colour if zone == Damageable.HitZone.HEAD else world_colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = false
	_mesh.material_override = material

	scale = Vector3.ONE * start_scale


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	var t := _age / lifetime
	# Swells fast then holds, rather than growing linearly. A linear growth
	# reads as a bubble; this reads as an impact.
	var grow := ease(t, 0.4)
	scale = Vector3.ONE * lerpf(start_scale, end_scale, grow)

	var material := _mesh.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color.a = (1.0 - t * t) * (1.0 if t < 0.999 else 0.0)
