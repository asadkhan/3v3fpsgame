class_name ImpactEffect
extends Node3D
## the spark where a round stops. spawned by WeaponFx, lives a fraction of a
## second and deletes itself.
##
## built from code instead of a scene file since the only interesting part is
## the curve - swells, fades, dies - and a QuadMesh with a transparent
## material handles that fine on its own.
##
## local only. nothing spawns this directly - the weapon asks for an impact
## and a presentation node on the shooter's own machine decides whether to
## draw one, so a client that never fired doesn't paint a spark in the wrong
## place.

## how long the effect lives, in seconds
@export var lifetime: float = 0.22

## size at the moment of impact, and the size it grows to before vanishing
@export var start_scale: float = 0.06
@export var end_scale: float = 0.16

## colour for flesh hits vs scenery hits - caller decides, since only the
## weapon knows what it hit
@export var world_colour: Color = Color(1.0, 0.78, 0.45, 0.9)
@export var flesh_colour: Color = Color(0.9, 0.2, 0.2, 0.95)

@onready var _mesh: MeshInstance3D = $Quad

var _age: float = 0.0


## positions the effect against a surface and picks the colour from the hit
## zone. call right after instancing, before adding to the tree, so it's
## never visible in the wrong place for a frame.
##
## flesh: hit a body, so blood colours instead of dust.
func setup(at: Vector3, normal: Vector3, zone: int, flesh: bool = false) -> void:
	position = at
	# lift off the surface a tiny bit, otherwise the quad z-fights with the
	# wall it's marking and disappears
	position += normal.normalized() * 0.012

	# orient along the surface normal so the mark lies flat on a wall or floor
	var up := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	var reference := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var basis := Basis.looking_at(up, reference)
	transform = Transform3D(basis, position)

	var material := StandardMaterial3D.new()
	material.albedo_color = flesh_colour if flesh or zone == Damageable.HitZone.HEAD else world_colour
	# soft round glow instead of a bare quad, which read as a white square
	material.albedo_texture = MuzzleFlashMesh.glow_texture()
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if not flesh else BaseMaterial3D.BLEND_MODE_MIX
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = false
	_mesh.material_override = material

	scale = Vector3.ONE * start_scale

	_spawn_debris(at, up, flesh)


## how long the debris lives
const DEBRIS_LIFETIME := 0.5


## a one-shot burst of small bits thrown off the surface: grey dust off a
## wall, red off a body. a sibling of this effect rather than a child, so it
## isn't scaled by the spark's swell and can outlive it.
func _spawn_debris(at: Vector3, normal: Vector3, flesh: bool) -> void:
	if not is_inside_tree():
		return
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.amount = 12
	particles.lifetime = DEBRIS_LIFETIME
	particles.explosiveness = 1.0
	particles.direction = normal
	particles.spread = 40.0
	particles.initial_velocity_min = 1.5
	particles.initial_velocity_max = 4.0
	particles.gravity = Vector3(0, -12.0, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2
	var bit := QuadMesh.new()
	bit.size = Vector2(0.025, 0.025)
	particles.mesh = bit
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = flesh_colour if flesh else Color(0.72, 0.68, 0.6, 0.9)
	particles.material_override = material
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	get_parent().add_child(particles)
	particles.global_position = at
	particles.emitting = true
	get_tree().create_timer(DEBRIS_LIFETIME + 0.2).timeout.connect(particles.queue_free)

	# the cloud the round kicks up, and what it throws off
	if flesh:
		BattleFx.burst(get_parent(), BattleFx.blood_mist(normal), at)
	else:
		BattleFx.burst(get_parent(), BattleFx.dust_burst(normal, Color(0.66, 0.6, 0.5)), at + normal * 0.05)
		if randf() < 0.35:
			BattleFx.burst(get_parent(), BattleFx.sparks(normal), at)


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	var t := _age / lifetime
	# swells fast then holds, instead of growing linearly (linear reads as a
	# bubble, this reads as an impact)
	var grow := ease(t, 0.4)
	scale = Vector3.ONE * lerpf(start_scale, end_scale, grow)

	var material := _mesh.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color.a = (1.0 - t * t) * (1.0 if t < 0.999 else 0.0)
