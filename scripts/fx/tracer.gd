class_name Tracer
extends MeshInstance3D
## A bullet tracer: a short bright streak racing from the muzzle to where the
## round stopped, then gone. Optionally leaves a brief flash at the muzzle - used
## for other players' shots, whose viewmodel (and its flash) nobody can see.
##
## Placeholder art until the effects pass; the look is three numbers below.

const SPEED := 420.0          # metres per second
const STREAK_LENGTH := 3.0
const THICKNESS := 0.018
const FLASH_TIME := 0.05
## Shortest time a tracer stays on screen. At full speed a close-range streak
## would cross in under a frame and never be seen; short ones slow down instead.
const MIN_VISIBLE_TIME := 0.05

static var _material: StandardMaterial3D = null
static var _flash_material: StandardMaterial3D = null

var _from: Vector3
var _to: Vector3
var _travelled: float = 0.0
var _total: float = 0.0
var _box: BoxMesh
var _flash: MeshInstance3D = null
var _flash_left: float = 0.0
var _speed: float = SPEED


## Call before adding to the tree.
func setup(from: Vector3, to: Vector3, with_flash: bool) -> void:
	_from = from
	_to = to
	_total = from.distance_to(to)
	_speed = minf(SPEED, (_total + STREAK_LENGTH) / MIN_VISIBLE_TIME)
	_box = BoxMesh.new()
	_box.size = Vector3(THICKNESS, THICKNESS, 0.01)
	mesh = _box
	material_override = _streak_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	if with_flash:
		_flash = MuzzleFlashMesh.create(0.35)
		_flash.material_override = _flash_material_shared()
		_flash_left = FLASH_TIME


func _ready() -> void:
	if _flash != null:
		get_parent().add_child(_flash)
		_flash.global_position = _from
	_update_streak()


func _process(delta: float) -> void:
	_travelled += _speed * delta
	if _flash != null:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.queue_free()
			_flash = null
	if _travelled - STREAK_LENGTH >= _total:
		if _flash != null:
			_flash.queue_free()
		queue_free()
		return
	_update_streak()


func _update_streak() -> void:
	if _total < 0.01:
		visible = false
		return
	var head := minf(_travelled, _total)
	var tail := clampf(_travelled - STREAK_LENGTH, 0.0, _total)
	var length := maxf(head - tail, 0.01)
	var direction := (_to - _from) / _total
	_box.size.z = length
	var centre := _from + direction * (tail + length * 0.5)
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(direction, up), centre)


static func _streak_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_material.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _material


static func _flash_material_shared() -> StandardMaterial3D:
	if _flash_material == null:
		_flash_material = MuzzleFlashMesh.material()
	return _flash_material
