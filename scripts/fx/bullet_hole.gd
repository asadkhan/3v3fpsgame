class_name BulletHole
extends Decal
## A bullet hole projected onto whatever surface a round hit. Lingers, then
## fades out. At most [constant MAX_HOLES] exist at once; the oldest goes first,
## so a long spray can never pile up an unbounded number of decals.
##
## Placeholder art (a generated dark smudge with a lighter rim) until the
## effects pass.

const LIFETIME := 15.0
const FADE_TIME := 2.0
const MAX_HOLES := 64
const SIZE := 0.15

static var _texture: GradientTexture2D = null
static var _live: Array[BulletHole] = []

var _age: float = 0.0


## Places the decal on a surface at [param at] facing along [param normal].
## Call before adding to the tree.
func setup(at: Vector3, normal: Vector3) -> void:
	size = Vector3(SIZE, 0.2, SIZE)
	texture_albedo = _hole_texture()
	cull_mask = 1
	var n := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	# A decal projects along its local -Y, so Y points out of the surface.
	var reference := Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := reference.cross(n).normalized()
	var z := x.cross(n).normalized()
	var basis := Basis(x, n, z).rotated(n, randf() * TAU)
	transform = Transform3D(basis, at + n * 0.02)


func _enter_tree() -> void:
	_live.append(self)
	while _live.size() > MAX_HOLES:
		var oldest: BulletHole = _live.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _exit_tree() -> void:
	_live.erase(self)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var fade_start := LIFETIME - FADE_TIME
	modulate.a = 1.0 if _age < fade_start else 1.0 - (_age - fade_start) / FADE_TIME


static func _hole_texture() -> GradientTexture2D:
	if _texture != null:
		return _texture
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.03, 0.03, 0.03, 0.95))
	gradient.set_color(1, Color(0.2, 0.18, 0.15, 0.0))
	gradient.add_point(0.45, Color(0.05, 0.05, 0.04, 0.9))
	gradient.add_point(0.7, Color(0.3, 0.27, 0.24, 0.4))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	_texture = texture
	return texture
