class_name PlaceholderEnvironment
extends Node3D
## A throwaway grey-box arena. It exists for one reason: to give the player
## something solid to stand on, walk into, and fail to walk through.
##
## [b]Everything in here is disposable.[/b] Chapter 7 deletes this scene and
## replaces it with the real map. Nothing outside [GameManager] should ever
## reference [PlaceholderEnvironment] by name - the match scene should simply
## be the thing that appears when gameplay starts, with this standing in until
## then.
##
## What lives in the [code].tscn[/code] and what lives here is a deliberate
## split. The ground, walls, sky, light, camera and spawn points are
## [b]authored[/b] in the scene file so they can be clicked and adjusted in the
## Inspector. Everything below is [b]generated[/b], because each piece is
## near-identical and a loop is a better home for it than a dozen copy-pasted
## nodes that all have to be deleted again in Chapter 7.
##
## The generated groups, in the order they are built:
## [codeblock]
## Cover     - chest-high blocks to walk around and hide behind
## Ramp      - one sloped slab, to prove the controller follows sloping ground
## Steps     - a short staircase, to prove the step-up logic
## Overhang  - a low slab to crouch under
## Range     - Chapter 3: practice targets, a backstop, a hostile turret
## [/codeblock]

## Cover block layout. Each entry is [code][centre, size, yaw_degrees][/code].
## Positions are metres relative to the centre of the floor, with [code]y = 0[/code]
## being the floor surface. The goal is not good level design - it is to give
## Chapter 3 a player something to walk into, and Chapter 4 something to hide
## behind.
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

# --- Movement test features (Chapter 2) -------------------------------
# These have no gameplay purpose whatsoever. They exist so the movement
# controller can be walked over something that is not a flat plane, because a
# controller that only ever gets tested on a flat floor hides every one of its
# real bugs: no slope following, no step climbing, no floor snapping.

## One sloped slab on the east side. 15 degrees is a clear, unambiguous grade -
## shallow enough that the controller has no excuse for bouncing off it, steep
## enough that a failure to follow the surface is obvious from across the room.
const RAMP_CENTRE := Vector3(20.0, 0.0, 0.0)
const RAMP_SIZE := Vector3(6.0, 0.5, 10.0)
const RAMP_PITCH_DEGREES := 15.0

## A staircase on the west side. Each step rises [constant STEP_RISE], which is
## deliberately under the controller's 0.4 m step height so walking up it is
## seamless; raise it above that value and the player has to jump, which is also
## a useful thing to be able to test.
const STEP_ORIGIN := Vector3(-20.0, 0.0, -1.2)
const STEP_COUNT := 4
const STEP_RISE := 0.3
const STEP_TREAD := 0.6
const STEP_WIDTH := 4.0

## A low slab to crouch under. [constant OVERHANG_CLEARANCE] is the gap between
## the floor and its underside, and it is the number that matters: it sits
## above the crouched height of 1.1 m and below the standing height of 1.8 m, so
## the player fits underneath only while crouched. Standing up inside it has to
## be refused, and the only way to prove that is to build something to refuse it
## inside of.
const OVERHANG_CENTRE := Vector3(-14.0, 0.0, 0.0)
const OVERHANG_CLEARANCE := 1.2
const OVERHANG_THICKNESS := 0.4

## Shared by every generated block. One material for all of them keeps the
## generated geometry visually distinct from the authored floor and walls,
## which makes it obvious at a glance what was made in code.
const COVER_COLOUR := Color(0.52, 0.54, 0.57)

## The movement test features get their own colour so it is immediately clear
## which geometry exists to be tested and which exists to be played around.
const TEST_COLOUR := Color(0.45, 0.62, 0.48)

# --- Combat range (Chapter 3) -------------------------------------------
# Laid out in the one stretch of the arena that no other generated group
# occupies: x -10..12, z 6..14. Every cover block, the ramp, the stairs and the
# overhang are outside that box, which is checked by hand rather than asserted -
# a test for "nothing else is here" would be more machinery than the fact is
# worth, and Chapter 7 deletes the lot.
#
# The layout is north-facing, so the player walks up the range from the spawn at
# z = 24:
#
# [codeblock]
#   z = 13   Turret       hostile, shoots back so combat runs both ways
#   z =  9   Targets x3   two with a body only, one for headshot practice
#   z =  6   Backstop     the obstacle: rounds that miss stop here
#   z = 16   (Chapter 1 cover wall) - what the player is behind at spawn
# [/codeblock]
#
# The Chapter 1 cover wall at z = 16 is deliberately left between the spawn and
# the range. It means the player has to move to fight rather than shooting from
# where they stood up, and it means the turret's line of sight to the spawn is
# blocked - so walking into the open is a decision, which is the only thing the
# turret is for.

## Where the three targets stand, and which of them has a real head collider.
## Every third target is a [PracticeTarget] either way; the difference is that
## one of these three also has a [code]Head[/code] body to shoot, so the
## collider-based hit zone is exercised against a known-good target rather than
## only against scenery.
const TARGET_SPOTS := [
	[Vector3(-3.5, 0.0, 9.0), false],
	[Vector3(0.0, 0.0, 9.0), false],
	[Vector3(3.5, 0.0, 9.0), true],
]

## The wall behind the targets. Rounds that miss a target hit this instead of
## flying off into the apron, which is the point of having an obstacle at all.
const BACKSTOP_CENTRE := Vector3(0.0, 0.0, 6.0)
const BACKSTOP_SIZE := Vector3(16.0, 2.8, 0.5)

## The turret, and the range it will engage at. Deliberately shorter than the
## target's own 32 m: at the spawn point the player is 11 m away and already
## inside that, so the shorter figure plus the cover wall at z = 16 is what keeps
## a player who only wants to walk around from being shot at.
const TURRET_POSITION := Vector3(0.0, 0.0, 13.0)
const TURRET_ENGAGEMENT_RANGE := 13.0

## Combat geometry gets its own colour again, so "this is here to shoot at" is
## obvious from across the room.
const RANGE_COLOUR := Color(0.62, 0.55, 0.42)

const TARGET_SCENE := preload("res://scenes/game/practice_target.tscn")
const TURRET_SCENE := preload("res://scenes/game/practice_turret.tscn")


func _ready() -> void:
	_build_cover()
	_build_ramp()
	_build_steps()
	_build_overhang()
	_build_range()


## Builds one [StaticBody3D] per entry in [constant COVER_BLOCKS]. A
## [StaticBody3D] rather than a bare [MeshInstance3D] because the player is a
## [CharacterBody3D] and would fall straight through a mesh that has no
## collision shape.
func _build_cover() -> void:
	var material := _make_material(COVER_COLOUR)

	for i in COVER_BLOCKS.size():
		var block: Array = COVER_BLOCKS[i]
		var centre: Vector3 = block[0]
		var size: Vector3 = block[1]
		var yaw_degrees: float = block[2]

		var body := _add_box("Cover%d" % (i + 1), size, material)
		# Lifted by half its height so the box rests on the floor instead of
		# straddling it.
		body.position = centre + Vector3(0.0, size.y * 0.5, 0.0)
		body.rotation.y = deg_to_rad(yaw_degrees)


## Builds the single sloped slab.
func _build_ramp() -> void:
	var pitch := deg_to_rad(RAMP_PITCH_DEGREES)
	var body := _add_box("Ramp", RAMP_SIZE, _make_material(TEST_COLOUR))
	body.position = RAMP_CENTRE + Vector3(0.0, _ramp_centre_height(RAMP_SIZE, pitch), 0.0)
	body.rotation.x = pitch


## How far to lift a sloped box so its [b]top surface at the low end[/b] lands on
## the floor.
##
## This is not the same as seating the box's lowest corner on the ground, which
## is the obvious thing to try and is wrong here: a box rotates about its
## centre, so seating the corner leaves the low end of the walking surface
## floating half the box's thickness above the floor. The player then faces a
## lip they cannot step over and a slab they cannot get onto, which looks
## exactly like broken slope handling.
##
## Sinking the top surface to the floor instead buries the underside of the
## slab below it, which is harmless and leaves no gap to fall through.
static func _ramp_centre_height(size: Vector3, pitch_radians: float) -> float:
	return size.z * 0.5 * sin(pitch_radians) - size.y * 0.5 * cos(pitch_radians)


## Builds the staircase, each step a box tall enough to be its own step and
## resting on the floor rather than stacked on the one below. Stacking would be
## fewer nodes, but a player who clips a corner of the lower step would snag on
## the joint between two boxes rather than on a clean vertical face.
func _build_steps() -> void:
	var material := _make_material(TEST_COLOUR)

	for i in STEP_COUNT:
		var height := STEP_RISE * float(i + 1)
		var size := Vector3(STEP_WIDTH, height, STEP_TREAD)
		var body := _add_box("Step%d" % (i + 1), size, material)
		body.position = STEP_ORIGIN + Vector3(0.0, height * 0.5, float(i) * STEP_TREAD)


## Builds the low slab the crouch test happens underneath.
func _build_overhang() -> void:
	var size := Vector3(6.0, OVERHANG_THICKNESS, 6.0)
	var body := _add_box("Overhang", size, _make_material(TEST_COLOUR))
	body.position = OVERHANG_CENTRE + Vector3(0.0, OVERHANG_CLEARANCE + size.y * 0.5, 0.0)


## Builds the Chapter 3 combat range: three practice targets, a backstop, and
## the hostile turret.
##
## Instanced scenes rather than generated geometry, because unlike the cover
## blocks these are real classes with behaviour - a target that could be built
## out of a box and a shape would be a target that cannot report its own health.
func _build_range() -> void:
	# Turned to face the spawn. Every target is turned, not just the headshot
	# one, so that adding a spot with an asymmetric prop later does not
	# accidentally introduce a backwards target.
	for i in TARGET_SPOTS.size():
		var spot: Array = TARGET_SPOTS[i]
		var at: Vector3 = spot[0]
		var target := TARGET_SCENE.instantiate() as PracticeTarget
		target.name = "Target%d" % (i + 1)
		target.position = at
		# A target with no head collider is a fairer body-shot test: every round
		# that reaches it is a body round, so a headshot multiplier applied by
		# mistake would show up immediately as the wrong number.
		target.has_head_collider = bool(spot[1])
		add_child(target)

	var backstop := _add_box("Backstop", BACKSTOP_SIZE, _make_material(RANGE_COLOUR))
	backstop.position = BACKSTOP_CENTRE + Vector3(0.0, BACKSTOP_SIZE.y * 0.5, 0.0)

	var turret := TURRET_SCENE.instantiate() as PracticeTurret
	turret.name = "Turret"
	turret.position = TURRET_POSITION
	turret.engagement_range = TURRET_ENGAGEMENT_RANGE
	add_child(turret)


## Resets every target and re-arms the turret. The test harness calls this
## between scenarios so one test cannot leave the next one shooting a corpse.
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


func _make_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	return material


## Creates one solid box: a [StaticBody3D] with a matching mesh and collider,
## already parented to this scene.
##
## Every generated shape in this file goes through here. Each box is its own
## body so it can be moved, rotated or deleted on its own later without
## unpicking a shared parent, and the mesh and collider are sized separately on
## purpose: editing the mesh to look right should never silently change what
## you can walk into.
func _add_box(node_name: String, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	# Named explicitly. An unnamed node added at runtime gets an auto-generated
	# name like @MeshInstance3D@412, which is unreadable in the remote scene tree
	# and impossible to address with get_node().
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
