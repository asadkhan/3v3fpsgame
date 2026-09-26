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
	GraphicsQuality.apply(self)
	GameConfig.setting_changed.connect(func(key: String, _value: Variant) -> void:
		if key == "video/graphics_quality":
			GraphicsQuality.apply(self))
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


## The photo-scanned surfaces (Poly Haven, CC0) under
## [code]assets/materials/surfaces/[/code]: ground, plaster, rock, concrete,
## trim, wood, container, steel. Each is a world-space triplanar PBR material,
## so any box can wear it without UVs and the texture never stretches.
const SURFACE_DIR := "res://assets/materials/surfaces/%s.tres"


## Registers the shared surface [param surface] under [param key].
func _define_surface(key: StringName, surface: String) -> void:
	_materials[key] = load(SURFACE_DIR % surface)


static func surface(surface_name: String) -> Material:
	return load(SURFACE_DIR % surface_name)


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


# --- Architectural detail ---------------------------------------------------
# Visual only - never collision - so the play space stays exactly as authored.

## A concrete cap along the top of a block and a plinth along its foot: what
## turns a box into a building.
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


## Dresses a cover block as a large timber crate: plank faces, and a heavier
## frame along every edge with a cross-brace on the long sides.
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


## Dresses a cover block as a steel utility module: container-steel faces and
## a painted steel frame.
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


## A flat floor finish (concrete pad, etc.) laid just above the ground.
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

## A scanned prop model (Poly Haven, CC0, [code]assets/props/[/code]) standing
## at [param at]. With [param solid], it gets a box collider fitted to its
## mesh, on the world layer, so it blocks movement and bullets like any wall.
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
	label.font = UITheme.font()
	add_child(label)


# --- Set dressing (the relay-station look) -------------------------------------
# Visual only, no collision unless noted: masts sit on rooftops nobody can
# reach, strips are trim. Placeholder art until the art pass, built to the
# SIGNALFALL palette (amber signal, cyan tech).

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


## A relay mast standing on a rooftop at [param base]: a pole, cross-arms, a
## dish and a blinking red beacon on top.
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


## A signal pylon: a slim pillar with glowing bands and a small light, used to
## mark a site so it can be recognised from a distance. Solid.
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


## A thin glowing strip between two points - roofline and trim lighting.
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


## Strips around the top edge of a block footprint.
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
	# One slow blink for every beacon on the map, like aircraft warning lights.
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
