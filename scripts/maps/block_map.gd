class_name BlockMap
extends Node3D
## base class for a map built from box geometry described as data.
## a map script extends this, fills in layout tables and calls the
## _add_* helpers from _build(). generates geometry (colliders sized to
## match meshes) instead of hand-placing it, so a wall moves by editing
## one number and there are no gaps to spot by eye.
##
## floor's top surface is y = 0. boxes stand on the floor unless a base
## height is given.

## group names: spawn barriers and bomb sites.
const BARRIER_GROUP := &"spawn_barriers"
const SITE_GROUP := &"bomb_sites"

## shared materials by key, built once per map.
var _materials: Dictionary = {}
var _barriers: Array[StaticBody3D] = []


## smoke, fire, dust and distant war sounds. see BattlefieldAtmosphere.
var atmosphere: BattlefieldAtmosphere = null


func _ready() -> void:
	atmosphere = BattlefieldAtmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	_build()
	GraphicsQuality.apply(self)
	GameConfig.setting_changed.connect(func(key: String, _value: Variant) -> void:
		if key == "video/graphics_quality":
			GraphicsQuality.apply(self))
	GameManager.state_changed.connect(_on_phase_changed)
	_set_barriers_active(GameManager.current_phase == GamePhase.Phase.BUY)


## override: build the map.
func _build() -> void:
	pass


# --- Materials ------------------------------------------------------------

## registers a material under key. mixes in a subtle noise texture so flat
## surfaces read as concrete/plaster instead of flat grey-box.
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


## one noise texture shared by every material and every map load.
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
	# pulled towards white so this only ever darkens a surface a little.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.86, 0.86, 0.86))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	texture.color_ramp = ramp
	_shared_detail = texture
	return texture


func _material(key: StringName) -> Material:
	return _materials.get(key)


## photo-scanned surfaces (poly haven, cc0) under assets/materials/surfaces/:
## ground, plaster, rock, concrete, trim, wood, container, steel. triplanar
## so any box can wear one without UVs.
const SURFACE_DIR := "res://assets/materials/surfaces/%s.tres"


## registers the shared surface under key.
func _define_surface(key: StringName, surface: String) -> void:
	_materials[key] = load(SURFACE_DIR % surface)


static func surface(surface_name: String) -> Material:
	return load(SURFACE_DIR % surface_name)


# --- Geometry -------------------------------------------------------------

## a solid box standing on the floor (or on base_height), footprint from
## min_xz to max_xz. the shape every layout table uses.
func _add_block(node_name: String, min_xz: Vector2, max_xz: Vector2, height: float,
		material_key: StringName, base_height: float = 0.0) -> StaticBody3D:
	var size := Vector3(max_xz.x - min_xz.x, height, max_xz.y - min_xz.y)
	var centre := Vector3((min_xz.x + max_xz.x) * 0.5, base_height + height * 0.5,
		(min_xz.y + max_xz.y) * 0.5)
	return _add_box(node_name, centre, size, material_key)


## a solid box by centre and size.
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

	# collider sized separately from the mesh, so resizing the visual never
	# changes what you can walk into.
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	add_child(body)
	return body


## a flight of steps rising from start towards direction, each rise high and
## tread deep. each step is its own box, no joints to snag on. keep rise
## under the player's step_height (0.4m) or steps get jumped instead of walked.
func _add_stairs(node_name: String, start: Vector3, direction: Vector3, width: float,
		steps: int, rise: float, tread: float, material_key: StringName) -> void:
	var along := direction.normalized()
	var across := Vector3(-along.z, 0.0, along.x).abs()
	for i in steps:
		var height := rise * float(i + 1)
		var size := across * width + along.abs() * tread + Vector3(0.0, height, 0.0)
		var centre := start + along * (tread * (float(i) + 0.5)) + Vector3(0.0, height * 0.5, 0.0)
		_add_box("%s%d" % [node_name, i + 1], centre, size, material_key)


# --- Architectural detail ---------------------------------------------------
# visual only, never collision - play space stays exactly as authored.

## a concrete cap along the top of a block and a plinth along its foot -
## what turns a box into a building.
func _add_trim(min_xz: Vector2, max_xz: Vector2, height: float, base_height: float = 0.0) -> void:
	var size := Vector3(max_xz.x - min_xz.x, 0.0, max_xz.y - min_xz.y)
	var centre := Vector3((min_xz.x + max_xz.x) * 0.5, 0.0, (min_xz.y + max_xz.y) * 0.5)
	var trim := _material(&"trim")
	var cap := _visual_box(self, centre + Vector3(0, base_height + height + 0.1, 0),
		size + Vector3(0.24, 0.2, 0.24), trim)
	cap.name = "Cap"
	var plinth := _visual_box(self, centre + Vector3(0, base_height + 0.2, 0),
		size + Vector3(0.08, 0.4, 0.08), _material(&"concrete"))
	plinth.name = "Plinth"


## dresses a cover block as a timber crate: plank faces, frame on every
## edge, cross-brace on the long sides.
func _dress_crate(body: StaticBody3D, size: Vector3) -> void:
	var frame := _material(&"wood_frame")
	_add_edge_frame(body, size, 0.12, frame)
	for axis in [0, 2]:
		for s in [-1.0, 1.0]:
			var face := Vector3.ZERO
			face[axis] = s * (size[axis] * 0.5 + 0.02)
			var along := 2 if axis == 0 else 0
			var length: float = Vector2(size[along], size.y).length() - 0.2
			var brace := _visual_box(body, face, Vector3(0.1, 0.1, 0.1), frame)
			var brace_size := Vector3(0.1, length, 0.05) if along == 0 else Vector3(0.05, length, 0.1)
			var angle: float = atan2(size[along], size.y) * s
			brace.mesh.size = brace_size
			if along == 0:
				brace.rotation.z = angle
			else:
				brace.rotation.x = angle


## dresses a cover block as a sandbag emplacement: hides the box mesh
## (collider stays put) and stacks sandbags over its footprint, staggered
## course by course - outer ring per course, filled top. one multimesh per block.
func _dress_sandbags(body: StaticBody3D, size: Vector3) -> void:
	var mesh_instance := body.get_node("Mesh") as MeshInstance3D
	mesh_instance.visible = false
	var bag := Vector3(0.5, 0.15, 0.28)
	var transforms: Array[Transform3D] = []
	var colours: Array[Color] = []
	var half := size * 0.5
	var courses := maxi(int(round(size.y / (bag.y * 0.92))), 1)
	for course in courses:
		var y := -half.y + bag.y * 0.5 + course * (size.y - bag.y) / maxf(courses - 1, 1)
		var top := course == courses - 1
		var stagger := 0.5 if course % 2 == 1 else 0.0
		# rows run along x; bags lie lengthways.
		var rows := maxi(int(size.z / bag.z), 1)
		var per_row := maxi(int(size.x / bag.x), 1)
		for row in rows:
			var z := -half.z + bag.z * 0.5 + row * (size.z - bag.z) / maxf(rows - 1, 1)
			var edge_row := row == 0 or row == rows - 1
			for i in per_row + (1 if stagger > 0.0 else 0):
				var x := -half.x + bag.x * (i + 0.5 - stagger)
				if x < -half.x + bag.x * 0.3 or x > half.x - bag.x * 0.3:
					x = clampf(x, -half.x + bag.x * 0.3, half.x - bag.x * 0.3)
				var edge := edge_row or i == 0 or i >= per_row - 1
				if not top and not edge:
					continue
				var basis := Basis.from_euler(Vector3(randf_range(-0.05, 0.05), randf_range(-0.12, 0.12),
					randf_range(-0.06, 0.06))).scaled(bag * Vector3(randf_range(0.95, 1.08), randf_range(0.85, 1.1), 1.0))
				transforms.append(Transform3D(basis, Vector3(x, y, z)))
				var shade := randf_range(0.82, 1.08)
				colours.append(Color(shade, shade * randf_range(0.97, 1.02), shade * randf_range(0.92, 1.0)))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _sandbag_mesh()
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, colours[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Sandbags"
	instance.multimesh = multimesh
	instance.material_override = _sandbag_material()
	body.add_child(instance)


static var _bag_mesh: Mesh = null
static var _bag_material: Material = null


## a unit sandbag: a squashed, rounded pillow (scaled per bag).
static func _sandbag_mesh() -> Mesh:
	if _bag_mesh == null:
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 14
		sphere.rings = 7
		# flattened ends and sides read as a filled bag, not a ball.
		var arrays := sphere.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var v := verts[i]
			verts[i] = Vector3(signf(v.x) * pow(absf(v.x) * 2.0, 0.45) * 0.5, v.y, signf(v.z) * pow(absf(v.z) * 2.0, 0.6) * 0.5)
		arrays[Mesh.ARRAY_VERTEX] = verts
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_bag_mesh = mesh
	return _bag_mesh


static func _sandbag_material() -> Material:
	if _bag_material == null:
		var m := ORMMaterial3D.new()
		var base := "res://assets/materials/hessian_230/hessian_230_"
		m.albedo_texture = load(base + "diff.jpg")
		m.albedo_color = Color(0.86, 0.76, 0.58)
		m.normal_enabled = true
		m.normal_texture = load(base + "nor_gl.jpg")
		m.orm_texture = load(base + "arm.jpg")
		m.vertex_color_use_as_albedo = true
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * 2.5
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_bag_material = m
	return _bag_material


## dresses a cover block as a steel utility module: container-steel faces
## with a painted steel frame.
func _dress_container(body: StaticBody3D, size: Vector3) -> void:
	_add_edge_frame(body, size, 0.1, _material(&"steel"))


func _add_edge_frame(body: Node3D, size: Vector3, thickness: float, material: Material) -> void:
	var h := size * 0.5
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_visual_box(body, Vector3(x * (h.x - thickness * 0.4), 0, z * (h.z - thickness * 0.4)),
				Vector3(thickness, size.y + 0.02, thickness), material)
	for y in [-1.0, 1.0]:
		for x in [-1.0, 1.0]:
			_visual_box(body, Vector3(x * (h.x - thickness * 0.4), y * (h.y - thickness * 0.4), 0),
				Vector3(thickness, thickness, size.z + 0.02), material)
		for z in [-1.0, 1.0]:
			_visual_box(body, Vector3(0, y * (h.y - thickness * 0.4), z * (h.z - thickness * 0.4)),
				Vector3(size.x + 0.02, thickness, thickness), material)


## a flat floor finish (concrete pad, etc.) laid just above the ground.
func _add_floor_pad(min_xz: Vector2, max_xz: Vector2, material_key: StringName) -> void:
	var pad := MeshInstance3D.new()
	pad.name = "FloorPad"
	var plane := PlaneMesh.new()
	plane.size = max_xz - min_xz
	pad.mesh = plane
	pad.material_override = _material(material_key)
	pad.position = Vector3((min_xz.x + max_xz.x) * 0.5, 0.012, (min_xz.y + max_xz.y) * 0.5)
	add_child(pad)


# --- Props --------------------------------------------------------------------

## a scanned prop model (poly haven, cc0, assets/props/) standing at `at`.
## with solid true, gets a box collider fitted to its mesh so it blocks
## movement and bullets like any wall.
func _add_prop(prop_name: String, at: Vector3, yaw_degrees: float = 0.0, solid: bool = true,
		prop_scale: float = 1.0) -> Node3D:
	var scene := load("res://assets/props/%s/%s_1k.gltf" % [prop_name, prop_name]) as PackedScene
	if scene == null:
		push_warning("Missing prop %s" % prop_name)
		return null
	var model := scene.instantiate() as Node3D
	var root: Node3D = model
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = CollisionLayers.WORLD
		body.collision_mask = 0
		body.add_child(model)
		var bounds := _mesh_bounds(model)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = bounds.size
		collision.shape = shape
		collision.position = bounds.get_center()
		body.add_child(collision)
		root = body
	root.name = prop_name.to_pascal_case()
	root.position = at
	root.rotation.y = deg_to_rad(yaw_degrees)
	root.scale = Vector3.ONE * prop_scale
	add_child(root)
	return root


static func _mesh_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xform := Transform3D.IDENTITY
		var at: Node = mesh
		while at != null and at != root.get_parent():
			if at is Node3D:
				xform = (at as Node3D).transform * xform
			at = at.get_parent()
		var box: AABB = xform * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


# --- Match features ---------------------------------------------------------

## places a spawn marker. facing_yaw_degrees 0 looks towards -z.
func _add_spawn_marker(marker_name: String, at: Vector3, facing_yaw_degrees: float) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = at
	marker.rotation.y = deg_to_rad(facing_yaw_degrees)
	add_child(marker)


## a wall that's solid only during the buy phase. drawn as a faint coloured
## sheet so a player can see why they can't leave.
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


## a site: a trigger volume for the objective, a tinted floor patch and a
## large letter so it can be spotted from across the map.
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

	# the painted zone: a thin unlit sheet a hair above the floor.
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


## a large painted letter or word on a wall.
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
	label.font = UITheme.font()
	add_child(label)


# --- Set dressing (the relay-station look) -------------------------------------
# visual only, no collision unless noted: masts sit on rooftops nobody can
# reach, strips are trim. amber signal / cyan tech colour scheme.

var _beacons: Array[StandardMaterial3D] = []
var _beacon_time: float = 0.0


func _emissive(colour: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour.darkened(0.3)
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = energy
	return material


func _visual_box(parent: Node3D, centre: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = centre
	parent.add_child(mesh)
	return mesh


## a relay mast standing on a rooftop at base: pole, cross-arms, dish and a
## blinking red beacon on top.
func _add_relay_mast(base: Vector3, height: float) -> void:
	var mast := Node3D.new()
	mast.name = "RelayMast"
	mast.position = base
	add_child(mast)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.34, 0.37)
	steel.metallic = 0.6
	steel.roughness = 0.5
	_visual_box(mast, Vector3(0, height * 0.5, 0), Vector3(0.18, height, 0.18), steel)
	for i in 3:
		var y := height * (0.45 + 0.18 * i)
		var arm := _visual_box(mast, Vector3(0, y, 0), Vector3(1.6 - 0.4 * i, 0.07, 0.07), steel)
		arm.rotation.y = 0.5 * i
	var dish := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.55
	cone.bottom_radius = 0.1
	cone.height = 0.3
	dish.mesh = cone
	dish.material_override = steel
	dish.position = Vector3(0.35, height * 0.72, 0)
	dish.rotation = Vector3(0, 0, -1.2)
	mast.add_child(dish)
	var beacon_material := _emissive(Color(1.0, 0.2, 0.15), 4.0)
	_beacons.append(beacon_material)
	_visual_box(mast, Vector3(0, height + 0.12, 0), Vector3(0.22, 0.22, 0.22), beacon_material)


## a signal pylon: slim pillar with glowing bands and a small light, marks a
## site so it's visible from a distance. solid.
func _add_pylon(base: Vector3, colour: Color, height: float = 3.4) -> void:
	var body := _add_box("Pylon", base + Vector3(0, height * 0.5, 0), Vector3(0.5, height, 0.5), &"metal")
	var glow := _emissive(colour, 3.0)
	for i in 3:
		_visual_box(body, Vector3(0, -height * 0.5 + 0.9 + i * 0.9, 0), Vector3(0.56, 0.08, 0.56), glow)
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = 1.2
	light.omni_range = 5.0
	light.position = Vector3(0, height * 0.5 - 0.3, 0)
	body.add_child(light)


## a thin glowing strip between two points - roofline and trim lighting.
func _add_light_strip(from: Vector3, to: Vector3, colour: Color, energy: float = 2.0) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.07, length)
	strip.mesh = box
	strip.material_override = _emissive(colour, energy)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(strip)
	var direction := (to - from) / length
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	strip.global_transform = Transform3D(Basis.looking_at(direction, up), (from + to) * 0.5)


## strips around the top edge of a block footprint.
func _outline_roof(min_xz: Vector2, max_xz: Vector2, y: float, colour: Color) -> void:
	var a := Vector3(min_xz.x, y, min_xz.y)
	var b := Vector3(max_xz.x, y, min_xz.y)
	var c := Vector3(max_xz.x, y, max_xz.y)
	var d := Vector3(min_xz.x, y, max_xz.y)
	_add_light_strip(a, b, colour)
	_add_light_strip(b, c, colour)
	_add_light_strip(c, d, colour)
	_add_light_strip(d, a, colour)


func _process(delta: float) -> void:
	if _beacons.is_empty():
		return
	# one slow blink for every beacon on the map, like aircraft warning lights.
	_beacon_time += delta
	var on := fmod(_beacon_time, 1.6) < 0.25
	for material in _beacons:
		material.emission_energy_multiplier = 5.0 if on else 0.3


func _on_phase_changed(_previous: int, current: int) -> void:
	_set_barriers_active(current == GamePhase.Phase.BUY)


func _set_barriers_active(active: bool) -> void:
	for barrier in _barriers:
		barrier.visible = active
		barrier.get_node("Collision").set_deferred(&"disabled", not active)
