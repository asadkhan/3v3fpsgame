class_name ShellCasing
extends MeshInstance3D
## a spent brass case thrown out of the ejection port: spins, falls,
## bounces off the floor with a tinkle, lies there a few seconds, fades.
##
## integrated by hand with a ray per step rather than a physics body -
## there can be dozens in the air during a spray and none should push anything.

const LIFETIME := 4.0
const GRAVITY := 11.0

static var _brass: StandardMaterial3D = null
static var _meshes: Dictionary = {}

var _velocity := Vector3.ZERO
var _spin := Vector3.ZERO
var _age: float = 0.0
var _bounces: int = 0
var _resting: bool = false


## adds a case to parent: a pistol case or a rifle case.
static func spawn(parent: Node, at: Transform3D, velocity: Vector3, pistol: bool) -> void:
	var casing := ShellCasing.new()
	parent.add_child(casing)
	if pistol:
		casing.setup(at, velocity, 0.02, 0.0045)
	else:
		casing.setup(at, velocity, 0.045, 0.005)


## length and radius in metres: about 45x5mm for a rifle, 20x4.5mm for a pistol.
func setup(at: Transform3D, velocity: Vector3, length: float, radius: float) -> void:
	mesh = _mesh(length, radius)
	material_override = _material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_transform = at
	_velocity = velocity
	_spin = Vector3(randf_range(-30, 30), randf_range(-12, 12), randf_range(-30, 30))


static func _mesh(length: float, radius: float) -> Mesh:
	var key := "%.3f_%.4f" % [length, radius]
	if not _meshes.has(key):
		var cylinder := CylinderMesh.new()
		cylinder.height = length
		cylinder.top_radius = radius * 0.82
		cylinder.bottom_radius = radius
		cylinder.radial_segments = 8
		cylinder.rings = 1
		_meshes[key] = cylinder
	return _meshes[key]


static func _material() -> StandardMaterial3D:
	if _brass == null:
		_brass = StandardMaterial3D.new()
		_brass.albedo_color = Color(0.78, 0.58, 0.28)
		_brass.metallic = 0.9
		_brass.roughness = 0.3
	return _brass


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	if _resting:
		if _age > LIFETIME - 0.6:
			scale = Vector3.ONE * clampf((LIFETIME - _age) / 0.6, 0.01, 1.0)
		return
	_velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + _velocity * delta
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, CollisionLayers.WORLD))
	if not hit.is_empty():
		var normal: Vector3 = hit.normal
		global_position = hit.position + normal * 0.004
		_velocity = _velocity.bounce(normal) * 0.35
		_velocity.x *= 0.6
		_velocity.z *= 0.6
		_spin *= 0.5
		_bounces += 1
		if _bounces <= 2:
			Audio.play_at(&"casing", global_position, -14.0 + _bounces * -4.0, 0.25, 18.0)
		if _velocity.length() < 0.5 or _bounces >= 4:
			_resting = true
			# lying on its side on the floor.
			global_basis = Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5)
		return
	global_position = to
	global_basis = global_basis.rotated(Vector3.RIGHT, _spin.x * delta).rotated(Vector3.UP, _spin.y * delta) \
		.rotated(Vector3.FORWARD, _spin.z * delta).orthonormalized()
