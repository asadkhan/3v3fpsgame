class_name BlockMap
extends Node3D
## Base class for a map built from box geometry described as data.
##
## A map script extends this, fills in its layout tables and calls the
## [code]_add_*[/code] helpers from [method _build]. Everything a match needs
## from a map is provided here, under the names the rest of the game looks for:
##
## - [code]AlphaSpawn[/code] / [code]BravoSpawn[/code] [Marker3D]s - read by
##   [Playtest] for spawn position and facing.
## - Spawn barriers - solid walls that only exist during the [b]BUY[/b] phase,
##   holding each side in its spawn while it prepares.
## - Sites - [Area3D]s in the group [code]bomb_sites[/code] with a
##   [code]site_name[/code] meta, for the objective (not built yet).
##
## [b]Why geometry is generated rather than hand-placed.[/b] Every box needs a
## collider sized exactly like its mesh, on the world layer, with a sensible
## material. Doing that by hand for a hundred boxes is where holes in the map
## come from; a table of centres and sizes is reviewable at a glance and a
## wall moves by editing one number.
##
## Coordinates: the floor's top surface is y = 0. Box tables give the
## [b]footprint[/b] and height, and boxes stand on the floor unless a base
## height is given.

## The group spawn barriers join, and the group sites join.
const BARRIER_GROUP := &"spawn_barriers"
const SITE_GROUP := &"bomb_sites"

## Shared materials by key, built once per map.
var _materials: Dictionary = {}
var _barriers: Array[StaticBody3D] = []


func _ready() -> void:
	_build()
	GameManager.state_changed.connect(_on_phase_changed)
	_set_barriers_active(GameManager.current_phase == GamePhase.Phase.BUY)


## Override: build the map.
func _build() -> void:
	pass


# --- Materials ------------------------------------------------------------

## Registers a material under [param key]. A subtle world-space noise is
## multiplied into the colour so large flat surfaces read as concrete or plaster
## rather than as untextured grey-box - the cheapest step up from placeholder
## art, and one that keeps every surface's colour exactly as authored.
func _define_material(key: StringName, colour: Color, roughness: float = 0.95, detail_scale: float = 0.35) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.albedo_texture = _detail_texture()
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * detail_scale
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_materials[key] = material


static var _shared_detail: NoiseTexture2D = null


## One noise texture shared by every material and every map load.
static func _detail_texture() -> NoiseTexture2D:
	if _shared_detail != null:
		return _shared_detail
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = noise
	# Pulled towards white so the texture only ever darkens a surface a little.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.86, 0.86, 0.86))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	texture.color_ramp = ramp
	_shared_detail = texture
	return texture


func _material(key: StringName) -> Material:
	return _materials.get(key)


# --- Geometry -------------------------------------------------------------

## A solid box standing on the floor (or on [param base_height]) whose footprint
## runs from [param min_xz] to [param max_xz]. The form every table uses.
func _add_block(node_name: String, min_xz: Vector2, max_xz: Vector2, height: float,
		material_key: StringName, base_height: float = 0.0) -> StaticBody3D:
	var size := Vector3(max_xz.x - min_xz.x, height, max_xz.y - min_xz.y)
	var centre := Vector3((min_xz.x + max_xz.x) * 0.5, base_height + height * 0.5,
		(min_xz.y + max_xz.y) * 0.5)
	return _add_box(node_name, centre, size, material_key)


## A solid box by centre and size.
func _add_box(node_name: String, centre: Vector3, size: Vector3, material_key: StringName,
		yaw_degrees: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	body.position = centre
	body.rotation.y = deg_to_rad(yaw_degrees)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _material(material_key)
	body.add_child(mesh_instance)

	# Sized separately from the mesh on purpose: what you can walk into must
	# never change because somebody resized the visual.
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	add_child(body)
	return body


## A flight of steps rising from [param start] towards [param direction]
## (a unit axis on the ground plane), each [param rise] high and [param tread]
## deep. Each step is its own box resting on the floor, so there are no joints
## to snag on. Rise must stay under [member Player.step_height] (0.4 m) for the
## steps to be walked rather than jumped.
func _add_stairs(node_name: String, start: Vector3, direction: Vector3, width: float,
		steps: int, rise: float, tread: float, material_key: StringName) -> void:
	var along := direction.normalized()
	var across := Vector3(-along.z, 0.0, along.x).abs()
	for i in steps:
		var height := rise * float(i + 1)
		var size := across * width + along.abs() * tread + Vector3(0.0, height, 0.0)
		var centre := start + along * (tread * (float(i) + 0.5)) + Vector3(0.0, height * 0.5, 0.0)
		_add_box("%s%d" % [node_name, i + 1], centre, size, material_key)


# --- Match features ---------------------------------------------------------

## Places a spawn marker. [param facing_yaw_degrees] 0 looks towards -Z.
func _add_spawn_marker(marker_name: String, at: Vector3, facing_yaw_degrees: float) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = at
	marker.rotation.y = deg_to_rad(facing_yaw_degrees)
	add_child(marker)


## A wall that is solid only during the buy phase. Drawn as a faint coloured
## sheet so a player can see why they cannot leave.
func _add_spawn_barrier(node_name: String, min_xz: Vector2, max_xz: Vector2, colour: Color) -> void:
	var body := _add_block(node_name, min_xz, max_xz, 4.0, &"barrier")
	var mesh := body.get_node("Mesh") as MeshInstance3D
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(colour.r, colour.g, colour.b, 0.22)
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 0.6
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_to_group(BARRIER_GROUP)
	_barriers.append(body)


## A site: a trigger volume for the future objective, a tinted floor patch and
## a large letter so it can be recognised from across the map.
func _add_site(site_name: String, min_xz: Vector2, max_xz: Vector2, colour: Color, letter_at: Vector3,
		letter_yaw_degrees: float) -> void:
	var size := Vector3(max_xz.x - min_xz.x, 3.0, max_xz.y - min_xz.y)
	var centre := Vector3((min_xz.x + max_xz.x) * 0.5, 1.5, (min_xz.y + max_xz.y) * 0.5)

	var area := Area3D.new()
	area.name = "Site%s" % site_name
	area.collision_layer = 0
	area.collision_mask = CollisionLayers.PLAYER
	area.position = centre
	area.set_meta(&"site_name", site_name)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	area.add_to_group(SITE_GROUP)
	add_child(area)

	# The painted zone: a thin unlit sheet a hair above the floor.
	var patch := MeshInstance3D.new()
	patch.name = "Site%sFloor" % site_name
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x, size.z)
	patch.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(colour.r, colour.g, colour.b, 0.1)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	patch.material_override = material
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.position = Vector3(centre.x, 0.02, centre.z)
	add_child(patch)

	add_sign(site_name, letter_at, letter_yaw_degrees, colour, 4.0)


## A large painted letter or word on a wall.
func add_sign(text: String, at: Vector3, yaw_degrees: float, colour: Color, pixel_scale: float = 1.0) -> void:
	var label := Label3D.new()
	label.name = "Sign_%s" % text.replace(" ", "_")
	label.text = text
	label.position = at
	label.rotation.y = deg_to_rad(yaw_degrees)
	label.pixel_size = 0.01 * pixel_scale
	label.font_size = 96
	label.outline_size = 12
	label.modulate = colour
	label.outline_modulate = Color(0.05, 0.05, 0.07, 0.9)
	label.shaded = false
	label.double_sided = false
	add_child(label)


func _on_phase_changed(_previous: int, current: int) -> void:
	_set_barriers_active(current == GamePhase.Phase.BUY)


func _set_barriers_active(active: bool) -> void:
	for barrier in _barriers:
		barrier.visible = active
		barrier.get_node("Collision").set_deferred(&"disabled", not active)
