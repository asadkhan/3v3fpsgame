class_name PlaceholderEnvironment
extends Node3D
## throwaway grey-box arena. just gives the player something to stand on,
## walk into, and fail to walk through.
##
## everything here is disposable and will get replaced by the real map.
## nothing outside GameManager should reference this by name.
##
## ground/walls/sky/light/camera/spawn points are authored in the scene file
## (clickable in the inspector). everything below is generated in a loop
## since it's all near-identical repeated geometry.
##
## generated groups, in build order:
## [codeblock]
## Cover     - chest-high blocks to walk around and hide behind
## Ramp      - one sloped slab, tests sloped ground following
## Steps     - a short staircase, tests step-up logic
## Overhang  - a low slab to crouch under
## Range     - practice targets, a backstop, a hostile turret
## [/codeblock]

## cover block layout: [centre, size, yaw_degrees]. positions in metres
## relative to floor centre, y = 0 is the floor surface. not real level
## design, just stuff to walk into and hide behind.
const COVER_BLOCKS := [
	[Vector3(-10.0, 0.0, -8.0), Vector3(6.0, 2.0, 1.0), 0.0],
	[Vector3(8.0, 0.0, -6.0), Vector3(1.0, 2.0, 7.0), 0.0],
	[Vector3(-6.0, 0.0, 4.0), Vector3(1.0, 3.0, 1.0), 25.0],
	[Vector3(6.0, 0.0, 5.0), Vector3(1.0, 3.0, 1.0), -25.0],
	[Vector3(0.0, 0.0, -1.0), Vector3(4.0, 1.2, 4.0), 0.0],
	[Vector3(-14.0, 0.0, 12.0), Vector3(2.0, 4.0, 2.0), 0.0],
	[Vector3(14.0, 0.0, 11.0), Vector3(2.0, 4.0, 2.0), 0.0],
	[Vector3(0.0, 0.0, 16.0), Vector3(8.0, 2.5, 1.0), 0.0],
]

# --- Movement test features -------------------------------
# no gameplay purpose - just gives the movement controller something that
# isn't a flat plane, since flat-floor-only testing hides slope/step/snap bugs.

## sloped slab, east side. 15 degrees: shallow enough the controller has no
## excuse to bounce off it, steep enough a bad slope follow is obvious.
const RAMP_CENTRE := Vector3(20.0, 0.0, 0.0)
const RAMP_SIZE := Vector3(6.0, 0.5, 10.0)
const RAMP_PITCH_DEGREES := 15.0

## staircase, west side. STEP_RISE is under the controller's 0.4m step
## height so walking up feels seamless; raise it above that and you'd need
## to jump instead.
const STEP_ORIGIN := Vector3(-20.0, 0.0, -1.2)
const STEP_COUNT := 4
const STEP_RISE := 0.3
const STEP_TREAD := 0.6
const STEP_WIDTH := 4.0

## low slab to crouch under. OVERHANG_CLEARANCE sits above crouch height
## (1.1m) and below standing height (1.8m) so you only fit while crouched.
const OVERHANG_CENTRE := Vector3(-14.0, 0.0, 0.0)
const OVERHANG_CLEARANCE := 1.2
const OVERHANG_THICKNESS := 0.4

## shared by every generated cover block, so generated geometry reads as
## visually distinct from the authored floor/walls.
const COVER_COLOUR := Color(0.52, 0.54, 0.57)

## movement test features get their own colour to stand out as "test stuff".
const TEST_COLOUR := Color(0.45, 0.62, 0.48)

# --- Combat range -------------------------------------------
# lives in x -10..12, z 6..14, clear of every other generated group.
#
# north-facing, player walks up the range from spawn at z = 24:
#
# [codeblock]
#   z = 13   Turret       hostile, shoots back
#   z =  9   Targets x3   two body-only, one for headshot practice
#   z =  6   Backstop     stops rounds that miss
#   z = 16   cover wall - what the player is behind at spawn
# [/codeblock]
#
# the cover wall at z = 16 sits between spawn and range on purpose: forces
# the player to move to fight, and blocks the turret's line of sight to
# spawn so walking into the open is a choice.

## where the three targets stand, and which has a real head collider.
## one of three gets a Head body so the headshot hit zone is tested against
## a known target instead of only scenery.
const TARGET_SPOTS := [
	[Vector3(-3.5, 0.0, 9.0), false],
	[Vector3(0.0, 0.0, 9.0), false],
	[Vector3(3.5, 0.0, 9.0), true],
]

## wall behind the targets, catches rounds that miss.
const BACKSTOP_CENTRE := Vector3(0.0, 0.0, 6.0)
const BACKSTOP_SIZE := Vector3(16.0, 2.8, 0.5)

## turret position and engagement range. shorter than the target's own 32m
## range - at spawn the player is 11m away, already inside it, so this plus
## the cover wall is what keeps a walk-around player from getting shot.
const TURRET_POSITION := Vector3(0.0, 0.0, 13.0)
const TURRET_ENGAGEMENT_RANGE := 13.0

## combat geometry gets its own colour too, "shoot this" should read at a glance.
const RANGE_COLOUR := Color(0.62, 0.55, 0.42)

const TARGET_SCENE := preload("res://scenes/game/practice_target.tscn")
const TURRET_SCENE := preload("res://scenes/game/practice_turret.tscn")


func _ready() -> void:
	GraphicsQuality.apply(self)
	# same war going on around the range: smoke, dust, distant fire, scorches.
	var atmosphere := BattlefieldAtmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	for column in [[Vector3(-50, 0, -60), 1.6], [Vector3(60, 0, -35), 1.2], [Vector3(-35, 0, 70), 1.4]]:
		atmosphere.add_smoke_column(column[0], column[1])
	for scorch in [[Vector3(-4, 0, 8), 3.0], [Vector3(9, 0, -12), 2.4], [Vector3(-16, 0, -3), 2.0]]:
		atmosphere.add_scorch(scorch[0], scorch[1])
	_build_cover()
	_build_ramp()
	_build_steps()
	_build_overhang()
	_build_range()


## builds one StaticBody3D per COVER_BLOCKS entry - needs a real body since
## the player's a CharacterBody3D and would fall through a bare mesh.
func _build_cover() -> void:
	var material := _make_material(COVER_COLOUR)

	for i in COVER_BLOCKS.size():
		var block: Array = COVER_BLOCKS[i]
		var centre: Vector3 = block[0]
		var size: Vector3 = block[1]
		var yaw_degrees: float = block[2]

		var body := _add_box("Cover%d" % (i + 1), size, material)
		# lifted by half its height so it rests on the floor instead of
		# straddling it.
		body.position = centre + Vector3(0.0, size.y * 0.5, 0.0)
		body.rotation.y = deg_to_rad(yaw_degrees)


## builds the single sloped slab.
func _build_ramp() -> void:
	var pitch := deg_to_rad(RAMP_PITCH_DEGREES)
	var body := _add_box("Ramp", RAMP_SIZE, _make_material(TEST_COLOUR))
	body.position = RAMP_CENTRE + Vector3(0.0, _ramp_centre_height(RAMP_SIZE, pitch), 0.0)
	body.rotation.x = pitch


## how far to lift the sloped box so its top surface at the low end sits on
## the floor (not the same as seating its lowest corner - since the box
## rotates about its centre, that would leave a floating lip at the low end).
static func _ramp_centre_height(size: Vector3, pitch_radians: float) -> float:
	return size.z * 0.5 * sin(pitch_radians) - size.y * 0.5 * cos(pitch_radians)


## builds the staircase. each step is its own box resting on the floor
## rather than stacked on the one below, so clipping a corner snags on a
## clean face instead of the seam between two boxes.
func _build_steps() -> void:
	var material := _make_material(TEST_COLOUR)

	for i in STEP_COUNT:
		var height := STEP_RISE * float(i + 1)
		var size := Vector3(STEP_WIDTH, height, STEP_TREAD)
		var body := _add_box("Step%d" % (i + 1), size, material)
		body.position = STEP_ORIGIN + Vector3(0.0, height * 0.5, float(i) * STEP_TREAD)


## builds the low slab the crouch test happens under.
func _build_overhang() -> void:
	var size := Vector3(6.0, OVERHANG_THICKNESS, 6.0)
	var body := _add_box("Overhang", size, _make_material(TEST_COLOUR))
	body.position = OVERHANG_CENTRE + Vector3(0.0, OVERHANG_CLEARANCE + size.y * 0.5, 0.0)


## builds the combat range: three practice targets, a backstop, the turret.
## real instanced scenes, not generated geometry, since these need actual
## behaviour (health, AI) that a plain box can't have.
func _build_range() -> void:
	# every target faces the spawn, not just the headshot one, so an
	# asymmetric prop added later can't sneak in backwards.
	for i in TARGET_SPOTS.size():
		var spot: Array = TARGET_SPOTS[i]
		var at: Vector3 = spot[0]
		var target := TARGET_SCENE.instantiate() as PracticeTarget
		target.name = "Target%d" % (i + 1)
		target.position = at
		# no head collider = every round that lands is a body round, so a
		# wrongly-applied headshot multiplier shows up immediately.
		target.has_head_collider = bool(spot[1])
		add_child(target)

	var backstop := _add_box("Backstop", BACKSTOP_SIZE, _make_material(RANGE_COLOUR))
	backstop.position = BACKSTOP_CENTRE + Vector3(0.0, BACKSTOP_SIZE.y * 0.5, 0.0)

	var turret := TURRET_SCENE.instantiate() as PracticeTurret
	turret.name = "Turret"
	turret.position = TURRET_POSITION
	turret.engagement_range = TURRET_ENGAGEMENT_RANGE
	add_child(turret)


## resets every target and re-arms the turret between test scenarios.
func reset_range() -> void:
	for node in get_tree().get_nodes_in_group(&"practice_targets"):
		var target := node as PracticeTarget
		if target != null:
			target.reset()
	for node in get_tree().get_nodes_in_group(&"practice_turrets"):
		var turret := node as PracticeTurret
		if turret != null:
			turret.enabled = true
			turret.start_delay = 3.0


func _make_material(colour: Color) -> Material:
	# range wears the same scanned surfaces as Meridian.
	match colour:
		COVER_COLOUR:
			return BlockMap.surface("plaster")
		TEST_COLOUR:
			return BlockMap.surface("concrete")
		RANGE_COLOUR:
			return BlockMap.surface("wood")
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	return material


## one solid box: a StaticBody3D with matching mesh and collider, parented here.
##
## every generated shape goes through this. each box is its own body so it
## can be moved/rotated/deleted independently. mesh and collider are sized
## separately on purpose - tweaking the look shouldn't silently change what
## you can walk into.
func _add_box(node_name: String, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	# named explicitly - an auto-generated name is unreadable in the remote
	# scene tree and can't be addressed with get_node().
	body.name = node_name

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	body.add_child(collision)

	add_child(body)
	return body
