class_name MuzzleFlashMesh
extends RefCounted
## Builds the muzzle flash sprite: two crossed additive quads with a soft
## radial glow, so it reads from the side as well as from behind. Shared by the
## viewmodel's own flash ([Weapon]) and the flash a [Tracer] shows for other
## players' shots. Placeholder art until the effects pass.

static var _texture: GradientTexture2D = null


## A new flash node of roughly [param size] metres across.
static func create(size: float) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	root.name = "FlashMesh"
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	root.mesh = quad
	root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.material_override = material()
	var cross := MeshInstance3D.new()
	cross.mesh = quad
	cross.material_override = root.material_override
	cross.rotation.y = PI * 0.5
	cross.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cross)
	var face := MeshInstance3D.new()
	var face_quad := QuadMesh.new()
	face_quad.size = Vector2(size * 0.7, size * 0.7)
	face.mesh = face_quad
	face.material_override = root.material_override
	face.rotation.x = PI * 0.5
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(face)
	return root


static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = glow_texture()
	mat.albedo_color = Color(1.0, 0.8, 0.45)
	mat.no_depth_test = false
	return mat


## A soft white-to-transparent radial glow, generated once.
static func glow_texture() -> GradientTexture2D:
	if _texture != null:
		return _texture
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.25, Color(1, 0.9, 0.6, 0.8))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	_texture = texture
	return texture
