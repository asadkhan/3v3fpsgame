class_name Grenade
extends Node3D
## A thrown frag or smoke grenade. Every machine spawns and flies its own copy
## from the same start (see [method PlayerLoadout.throw_grenade]); the flight is
## a deterministic ray-bounce integration against the world, so all copies land
## in the same place. Only the host's frag deals damage.
##
## Frag: bounces, explodes 2.2 s after the throw - fireball, flash, debris,
## scorch, a shockwave that shakes nearby cameras - and deals up to
## [constant FRAG_DAMAGE] falling off to nothing at [constant FRAG_RADIUS],
## blocked by walls.
## Smoke: pops after 1.4 s and billows into an opaque cloud about
## [constant SMOKE_RADIUS] across that lasts [constant SMOKE_TIME] seconds.

enum Kind { FRAG, SMOKE }

const GRAVITY := 14.0
const FRAG_FUSE := 2.2
const SMOKE_FUSE := 1.4
const FRAG_DAMAGE := 150.0
const FRAG_RADIUS := 6.5
const SMOKE_RADIUS := 4.2
const SMOKE_TIME := 16.0

var kind: int = Kind.FRAG
## The player who threw it, credited with frag kills. May be freed.
var thrower: Node = null

var _velocity := Vector3.ZERO
var _age: float = 0.0
var _resting: bool = false
var _spin := Vector3.ZERO
var _model: Node3D = null
var _done: bool = false


static func spawn(parent: Node, p_kind: int, at: Vector3, velocity: Vector3, p_thrower: Node) -> Grenade:
	var grenade := Grenade.new()
	grenade.kind = p_kind
	grenade.thrower = p_thrower
	grenade._velocity = velocity
	parent.add_child(grenade)
	grenade.global_position = at
	return grenade


func _ready() -> void:
	var frag := kind == Kind.FRAG
	var path := "res://assets/weapons/cc0/frag/FragGrenadeModel.fbx" if frag \
		else "res://assets/weapons/cc0/smoke/Smoke_Grenade.fbx"
	_model = (load(path) as PackedScene).instantiate() as Node3D
	var material: Material = load("res://assets/weapons/cc0/%s/%s.tres" % ["frag" if frag else "smoke", "frag" if frag else "smoke"])
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
	add_child(_model)
	_spin = Vector3(randf_range(-12, 12), randf_range(-6, 6), randf_range(-12, 12))
	Audio.play_at(&"grenade_throw", global_position, -6.0, 0.1, 20.0)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if not _resting:
		_velocity.y -= GRAVITY * delta
		var from := global_position
		var to := from + _velocity * delta
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(from, to, CollisionLayers.WORLD)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			global_position = to
			_model.rotation += _spin * delta
		else:
			var normal: Vector3 = hit.normal
			global_position = hit.position + normal * 0.04
			var speed := _velocity.length()
			_velocity = _velocity.bounce(normal) * 0.4
			_velocity -= normal * normal.dot(_velocity) * 0.3
			_spin *= 0.5
			if speed > 2.0:
				Audio.play_at(&"grenade_bounce", global_position, -8.0, 0.15, 25.0)
			if _velocity.length() < 0.8 and normal.y > 0.6:
				_resting = true
	var fuse := FRAG_FUSE if kind == Kind.FRAG else SMOKE_FUSE
	if _age >= fuse:
		_done = true
		if kind == Kind.FRAG:
			_explode()
		else:
			_pop_smoke()


# --- Frag -------------------------------------------------------------------------------

func _explode() -> void:
	var at := global_position + Vector3(0, 0.1, 0)
	var parent := get_parent()
	Audio.play_at(&"grenade_boom", at, 6.0, 0.05, 180.0)
	_fireball(parent, at)
	BattleFx.burst(parent, BattleFx.dust_burst(Vector3.UP, Color(0.5, 0.46, 0.4)), at)
	BattleFx.burst(parent, BattleFx.sparks(Vector3.UP), at)
	var decal := Decal.new()
	decal.texture_albedo = BattleFx.scorch_texture()
	decal.size = Vector3(3.2, 1.2, 3.2)
	decal.cull_mask = 1
	parent.add_child(decal)
	decal.global_position = at
	decal.rotation.y = randf() * TAU
	parent.get_tree().create_timer(40.0).timeout.connect(decal.queue_free)
	# Shockwave: nearby cameras shake.
	var me := NetworkManager.get_local_player()
	if me != null:
		var d := me.global_position.distance_to(at)
		if d < 18.0:
			me.add_shake(clampf(1.0 - d / 18.0, 0.0, 1.0) * 4.0)
		if d < 9.0 and me.state.is_alive:
			var strength := clampf(1.0 - d / 9.0, 0.0, 1.0)
			EventBus.local_concussion.emit(strength)
			Audio.concuss(strength)
		if d < FRAG_RADIUS and NetworkManager.is_online and not multiplayer.is_server():
			EventBus.local_hit_from.emit(at)
	if not NetworkManager.is_online or multiplayer.is_server():
		_deal_blast_damage(at)
	_model.visible = false
	get_tree().create_timer(0.2).timeout.connect(queue_free)


func _fireball(parent: Node, at: Vector3) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.35)
	flash.light_energy = 12.0
	flash.omni_range = 12.0
	parent.add_child(flash)
	flash.global_position = at + Vector3(0, 0.5, 0)
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.35)
	tween.tween_callback(flash.queue_free)

	var fire := BattleFx.flames(1.6)
	fire.one_shot = true
	fire.explosiveness = 0.9
	fire.amount = 26
	fire.lifetime = 0.5
	fire.initial_velocity_min = 2.0
	fire.initial_velocity_max = 6.0
	fire.spread = 80.0
	BattleFx.burst(parent, fire, at)
	var smoke := BattleFx.fire_smoke()
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.amount = 14
	smoke.preprocess = 0.0
	smoke.initial_velocity_min = 1.5
	smoke.initial_velocity_max = 3.5
	smoke.spread = 70.0
	BattleFx.burst(parent, smoke, at)


## Host only: damage everyone in range who is not behind cover.
func _deal_blast_damage(at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var targets: Array = []
	targets.append_array(NetworkManager.get_players())
	targets.append_array(get_tree().get_nodes_in_group(&"practice_targets"))
	for player in targets:
		if player == null or not is_instance_valid(player):
			continue
		if player is Player and not (player as Player).state.is_alive:
			continue
		var centre: Vector3 = (player as Node3D).global_position + Vector3(0, 0.9, 0)
		var d := centre.distance_to(at)
		if d > FRAG_RADIUS:
			continue
		var query := PhysicsRayQueryParameters3D.create(at, centre, CollisionLayers.WORLD)
		var blocked := space.intersect_ray(query)
		# Cover blocks the blast; the target's own body does not.
		if not blocked.is_empty() and Damageable.find_target(blocked.get("collider")) != player:
			continue
		var amount := FRAG_DAMAGE * pow(1.0 - d / FRAG_RADIUS, 1.3)
		var source: Node = thrower if thrower != null and is_instance_valid(thrower) else null
		Damageable.deal_damage(player, amount, source, Damageable.HitZone.BODY)


# --- Smoke ------------------------------------------------------------------------------

func _pop_smoke() -> void:
	Audio.play_at(&"smoke_pop", global_position, 0.0, 0.05, 40.0)
	var cloud := Node3D.new()
	get_parent().add_child(cloud)
	cloud.global_position = global_position
	# A thick core that blocks sight and a softer rolling outer layer.
	for layer in 2:
		var p := CPUParticles3D.new()
		p.amount = 140 if layer == 0 else 60
		p.lifetime = 5.0
		# Most of it bursts out at once, so it blooms within a second.
		p.explosiveness = 0.35
		p.preprocess = 0.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = SMOKE_RADIUS * (0.75 if layer == 0 else 0.95)
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 0.1
		p.initial_velocity_max = 0.6
		p.gravity = Vector3(0.05, 0.08, 0.02)
		p.angle_min = -180.0
		p.angle_max = 180.0
		p.angular_velocity_min = -6.0
		p.angular_velocity_max = 6.0
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * (3.8 if layer == 0 else 4.6)
		p.mesh = quad
		p.material_override = BattleFx.particle_material(BattleFx.smoke_texture(), false)
		p.scale_amount_curve = BattleFx._grow(0.6, 1.2)
		p.color_ramp = BattleFx._ramp([Color(0.78, 0.78, 0.76, 0.0), Color(0.8, 0.8, 0.78, 1.0 if layer == 0 else 0.8),
			Color(0.82, 0.82, 0.8, 0.95 if layer == 0 else 0.6), Color(0.84, 0.84, 0.82, 0.0)])
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.layers = 2
		BattleFx.tint(p)
		(p.material_override as ShaderMaterial).set_shader_parameter(&"fade_out", 0.2)
		(p.material_override as ShaderMaterial).set_shader_parameter(&"fade_in", 0.05)
		(p.material_override as ShaderMaterial).set_shader_parameter(&"density", 3.0 if layer == 0 else 1.6)
		p.position = Vector3(0, SMOKE_RADIUS * 0.45, 0)
		cloud.add_child(p)
		p.emitting = true
	var hiss := AudioStreamPlayer3D.new()
	hiss.stream = Audio._library.get(&"smoke_hiss")
	hiss.unit_size = 4.0
	hiss.max_distance = 30.0
	hiss.volume_db = -6.0
	cloud.add_child(hiss)
	hiss.play()
	var timer := cloud.get_tree().create_timer(SMOKE_TIME)
	timer.timeout.connect(func() -> void:
		for c in cloud.get_children():
			if c is CPUParticles3D:
				(c as CPUParticles3D).emitting = false
			elif c is AudioStreamPlayer3D:
				(c as AudioStreamPlayer3D).stop()
		cloud.get_tree().create_timer(5.5).timeout.connect(cloud.queue_free))
	queue_free()
