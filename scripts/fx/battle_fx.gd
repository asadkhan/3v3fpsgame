class_name BattleFx
extends RefCounted
## Shared battlefield effects: procedurally made textures (smoke puff, flame,
## scorch, stain) and ready-configured particle emitters for smoke, fire,
## embers, dust and blood. Textures are generated once and cached, so every
## emitter in the match shares them.
##
## CPU particles throughout: they run the same on every renderer and every GPU,
## and the counts here are small.

static var _cache: Dictionary = {}


# --- Textures -----------------------------------------------------------------------

## A soft, lumpy white puff: fractal noise inside a feathered circle.
static func smoke_texture() -> Texture2D:
	return _cached(&"smoke", func() -> Texture2D: return _puff(128, 0.55, 3, 1.0))


## A flame tongue: bright core, ragged edge, taller than wide.
static func flame_texture() -> Texture2D:
	return _cached(&"flame", func() -> Texture2D: return _puff(64, 0.9, 2, 1.6))


## A blackened blast mark: dark, irregular, soft-edged; alpha carries the shape.
static func scorch_texture() -> Texture2D:
	return _cached(&"scorch", func() -> Texture2D: return _blotch(256, Color(0.035, 0.03, 0.026), 0.82, 11.0))


## A dark oil or water stain.
static func stain_texture() -> Texture2D:
	return _cached(&"stain", func() -> Texture2D: return _blotch(256, Color(0.06, 0.055, 0.05), 0.6, 9.0))


static func _cached(key: StringName, make: Callable) -> Texture2D:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


static func _puff(size: int, noise_amount: float, octaves: int, stretch: float) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 4.0 / size
	noise.fractal_octaves = octaves
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	for y in size:
		for x in size:
			var dx := (x - c) / c
			var dy := (y - c) / c / stretch
			var d := sqrt(dx * dx + dy * dy)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf(1.0 - d - (1.0 - n) * noise_amount * 0.6, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var shade := lerpf(0.75, 1.0, n)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _blotch(size: int, colour: Color, strength: float, lumpiness: float) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = lumpiness / size
	noise.fractal_octaves = 4
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - d) * 1.6 - (1.0 - n) * 0.9, 0.0, 1.0) * strength
			img.set_pixel(x, y, Color(colour.r, colour.g, colour.b, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- Emitters ---------------------------------------------------------------------------

## A billboard material for particles: [param additive] for fire and sparks,
## otherwise lit-by-nothing alpha smoke tinted by the particle colour.
static func particle_material(texture: Texture2D, additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.proximity_fade_enabled = not additive
	material.proximity_fade_distance = 0.6
	return material


static func _ramp(colours: Array) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array()
	gradient.colors = PackedColorArray()
	for i in colours.size():
		gradient.add_point(float(i) / maxf(colours.size() - 1, 1), colours[i])
	return gradient


static func _grow(from: float, to: float) -> Curve:
	var curve := Curve.new()
	# The default range is 0..1, which would clamp any growth past full size.
	curve.max_value = maxf(maxf(from, to), 1.0)
	curve.add_point(Vector2(0, from))
	curve.add_point(Vector2(1, to))
	return curve


static func _emitter(amount: int, lifetime: float, size: float, texture: Texture2D, additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	p.mesh = quad
	p.material_override = particle_material(texture, additive)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## A column of dark smoke rising from a fire far away: big, slow, leaning with
## the wind. [param scale] 1 is a burning building.
static func smoke_column(scale: float = 1.0) -> CPUParticles3D:
	var p := _emitter(60, 24.0, 9.0 * scale, smoke_texture(), false)
	p.preprocess = 24.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.5 * scale
	p.direction = Vector3(0.2, 1, 0.08)
	p.spread = 14.0
	p.gravity = Vector3(0.45, 0.35, 0.15)
	p.initial_velocity_min = 1.4 * scale
	p.initial_velocity_max = 2.2 * scale
	p.damping_min = 0.02
	p.damping_max = 0.05
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -5.0
	p.angular_velocity_max = 5.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _grow(0.45, 4.0)
	p.color_ramp = _ramp([Color(0.08, 0.07, 0.06, 0.0), Color(0.09, 0.08, 0.07, 0.85),
		Color(0.16, 0.15, 0.14, 0.7), Color(0.3, 0.29, 0.28, 0.35), Color(0.4, 0.39, 0.38, 0.0)])
	p.visibility_aabb = AABB(Vector3(-60, -5, -60) * scale, Vector3(120, 140, 120) * scale)
	return p


## Flames licking up out of a barrel or wreck, [param width] metres across.
static func flames(width: float = 0.5) -> CPUParticles3D:
	var p := _emitter(22, 0.7, 0.55 * width / 0.5, flame_texture(), true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = width * 0.35
	p.direction = Vector3.UP
	p.spread = 10.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.angle_min = -30.0
	p.angle_max = 30.0
	p.scale_amount_curve = _grow(1.0, 0.25)
	p.color_ramp = _ramp([Color(1.0, 0.85, 0.5, 0.0), Color(1.0, 0.62, 0.22, 0.95),
		Color(0.9, 0.3, 0.08, 0.6), Color(0.3, 0.08, 0.02, 0.0)])
	return p


## Glowing sparks drifting up from a fire.
static func embers() -> CPUParticles3D:
	var p := _emitter(14, 2.6, 0.03, MuzzleFlashMesh.glow_texture(), true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0.2, 0.4, 0.0)
	p.color_ramp = _ramp([Color(1.0, 0.7, 0.3, 1.0), Color(1.0, 0.4, 0.1, 0.8), Color(0.6, 0.15, 0.05, 0.0)])
	return p


## Thin grey smoke trailing off a fire.
static func fire_smoke() -> CPUParticles3D:
	var p := _emitter(10, 4.0, 0.9, smoke_texture(), false)
	p.preprocess = 4.0
	p.direction = Vector3.UP
	p.spread = 8.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.3
	p.gravity = Vector3(0.35, 0.25, 0.1)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_curve = _grow(0.6, 2.8)
	p.color_ramp = _ramp([Color(0.2, 0.19, 0.18, 0.0), Color(0.22, 0.2, 0.19, 0.45), Color(0.4, 0.38, 0.36, 0.0)])
	return p


## A one-shot cloud where a round kicks up the ground or a wall: [param colour]
## is the surface's dust.
static func dust_burst(normal: Vector3, colour: Color) -> CPUParticles3D:
	var p := _emitter(7, 1.1, 0.32, smoke_texture(), false)
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = normal
	p.spread = 35.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.0
	p.damping_min = 2.5
	p.damping_max = 4.0
	p.gravity = Vector3(0, -0.4, 0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_curve = _grow(0.5, 2.4)
	p.color_ramp = _ramp([Color(colour, 0.0), Color(colour, 0.7), Color(colour, 0.0)])
	return p


## Bright sparks skipping off a hard surface.
static func sparks(normal: Vector3) -> CPUParticles3D:
	var p := _emitter(9, 0.35, 0.02, MuzzleFlashMesh.glow_texture(), true)
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 55.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	p.color_ramp = _ramp([Color(1.0, 0.9, 0.6, 1.0), Color(1.0, 0.55, 0.2, 0.0)])
	return p


## A red mist where a round hits a body.
static func blood_mist(normal: Vector3) -> CPUParticles3D:
	var p := _emitter(8, 0.55, 0.22, smoke_texture(), false)
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 40.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.6
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_curve = _grow(0.4, 1.8)
	p.color_ramp = _ramp([Color(0.45, 0.02, 0.02, 0.0), Color(0.5, 0.03, 0.03, 0.85), Color(0.3, 0.02, 0.02, 0.0)])
	return p


## Adds a one-shot emitter to [param parent] at [param at] and frees it when
## it is done.
static func burst(parent: Node, particles: CPUParticles3D, at: Vector3) -> void:
	parent.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	parent.get_tree().create_timer(particles.lifetime + 0.3).timeout.connect(particles.queue_free)
