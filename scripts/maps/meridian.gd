class_name MapMeridian
extends BlockMap
## [b]Meridian[/b] - the first competitive 3v3 map.
##
## [codeblock]
##               ATTACKER spawn                  z = +45
##        +--------[ spawn  ]--------+
##        |      attacker yard       |           z = +26..+32
##        | A lane |  mid  | B lane  |
##        |        |-link--|         |           z = +8..+12 (links)
##        |        |  mid  |         |
##        | A main |court  | B main  |           z = -14..-8
##        | A SITE |centre | B SITE  |           z = -32..-8
##        +---back-+-------+-back----+
##        |      defender yard       |           z = -36..-33
##        +--------[ spawn  ]--------+
##               DEFENDER spawn                  z = -45
## [/codeblock]
##
## Three routes from the attacker side - A lane, mid, B lane - with links
## between the lanes and mid, two sites near the defender spawn, and short
## doors from mid court into each site. The two sites are deliberately not
## mirror images: A is open with a raised ledge on its west wall, B is tighter
## with a raised platform in its back corner, so the two retakes play
## differently.
##
## Sizes are tuned for 3 players a side: every lane is 10-13 m wide, the
## longest clear sightline is kept under the Kestrel's 45 m range, and a rotate
## from site to site through mid court takes about six seconds at a run.
##
## All geometry is generated from the tables below; see [BlockMap].

const WALL_HEIGHT := 6.0
const OUTER_HEIGHT := 8.0

## Playable bounds (inside faces of the outer walls).
const MIN_X := -32.0
const MAX_X := 32.0
const MIN_Z := -45.0
const MAX_Z := 45.0

const SITE_COLOUR := Color(1.0, 0.8, 0.3)
const SIGN_COLOUR := Color(0.96, 0.93, 0.86)
const BARRIER_COLOUR := UITheme.TECH

## Full-height structures: [min corner (x, z), max corner (x, z)].
const STRUCTURES := [
	# Spawn rooms are carved out of the corners.
	[Vector2(-32, 32), Vector2(-12, 45)],
	[Vector2(12, 32), Vector2(32, 45)],
	[Vector2(-32, -45), Vector2(-12, -36)],
	[Vector2(12, -45), Vector2(32, -36)],
	# The blocks between the lanes and mid, split by the links.
	[Vector2(-19, 12), Vector2(-5, 26)],
	[Vector2(-19, -8), Vector2(-5, 8)],
	[Vector2(5, 12), Vector2(19, 26)],
	[Vector2(5, -8), Vector2(19, 8)],
	# The heart of the map, between the two sites.
	[Vector2(-9, -32), Vector2(9, -14)],
	# Chokes into each site from its main.
	[Vector2(-32, -8), Vector2(-27, -3)],
	[Vector2(27, -6), Vector2(32, 0)],
	# Door frames from mid court into each site. Offset from each other so
	# the doors do not line up into one site-to-site sightline.
	[Vector2(-10, -10), Vector2(-9, -8)],
	[Vector2(9, -14), Vector2(10, -12)],
	# Site back walls, each leaving one door to the defender yard.
	[Vector2(-32, -33), Vector2(-24, -32)],
	[Vector2(-18, -33), Vector2(-9, -32)],
	[Vector2(9, -33), Vector2(16, -32)],
	[Vector2(22, -33), Vector2(32, -32)],
]

## Cover: [min (x, z), max (x, z), height, material, base height].
## 1.2 m hides a crouched player and is shot over standing; 2.2 m hides a
## standing player.
const COVER := [
	# Attacker yard
	[Vector2(-6, 28), Vector2(-4, 30), 1.2, &"crate", 0.0],
	[Vector2(18, 27), Vector2(20, 29), 2.2, &"metal", 0.0],
	# A lane
	[Vector2(-28, 18), Vector2(-26, 20), 1.2, &"crate", 0.0],
	[Vector2(-23, 6), Vector2(-21, 8), 2.2, &"metal", 0.0],
	[Vector2(-30, 0), Vector2(-28, 2), 1.2, &"crate", 0.0],
	# A site
	[Vector2(-21, -24), Vector2(-17, -20), 1.4, &"crate", 0.0],
	[Vector2(-20, -23), Vector2(-18, -21), 1.0, &"crate", 1.4],
	[Vector2(-14, -28), Vector2(-12, -26), 2.2, &"metal", 0.0],
	[Vector2(-28, -30), Vector2(-25, -28), 1.2, &"crate", 0.0],
	[Vector2(-15, -18), Vector2(-13, -16), WALL_HEIGHT, &"structure", 0.0],
	# Mid
	[Vector2(-1.5, 14), Vector2(1.5, 16), 2.2, &"metal", 0.0],
	[Vector2(-4, 2), Vector2(-2.5, 3.5), 1.2, &"crate", 0.0],
	[Vector2(2.5, -4), Vector2(4, -2.5), 1.2, &"crate", 0.0],
	[Vector2(-1.5, -12), Vector2(1.5, -10), 2.2, &"metal", 0.0],
	# B lane
	[Vector2(26, 18), Vector2(28, 20), 2.2, &"metal", 0.0],
	[Vector2(21, 6), Vector2(23, 8), 1.2, &"crate", 0.0],
	# B site
	[Vector2(15, -22), Vector2(20, -19), 1.2, &"crate", 0.0],
	[Vector2(13, -28), Vector2(15, -24), 1.4, &"crate", 0.0],
	[Vector2(21, -15), Vector2(23, -13), 2.2, &"metal", 0.0],
	[Vector2(13, -18), Vector2(15, -16), 2.2, &"metal", 0.0],
]


func _build() -> void:
	# A desert relay outpost: dusty ground, clay-plastered blocks, canyon rock
	# round the edge, timber crates and steel modules for cover.
	_define_surface(&"floor", "ground")
	_define_surface(&"structure", "plaster")
	_define_surface(&"outer", "rock")
	_define_surface(&"crate", "wood")
	_define_surface(&"metal", "container")
	_define_surface(&"platform", "concrete")
	_define_surface(&"concrete", "concrete")
	_define_surface(&"trim", "trim")
	_define_surface(&"steel", "steel")
	_define_surface(&"paving", "paving")
	var frame := (load(BlockMap.SURFACE_DIR % "wood") as Material).duplicate() as BaseMaterial3D
	frame.albedo_color = Color(0.62, 0.55, 0.48)
	_materials[&"wood_frame"] = frame

	_build_shell()

	for i in STRUCTURES.size():
		var entry: Array = STRUCTURES[i]
		_add_block("Structure%d" % (i + 1), entry[0], entry[1], WALL_HEIGHT, &"structure")
		_add_trim(entry[0], entry[1], WALL_HEIGHT)

	for i in COVER.size():
		var entry: Array = COVER[i]
		var body := _add_block("Cover%d" % (i + 1), entry[0], entry[1], entry[2], entry[3], entry[4])
		var size := Vector3(entry[1].x - entry[0].x, entry[2], entry[1].y - entry[0].y)
		match entry[3]:
			&"crate":
				_dress_crate(body, size)
			&"metal":
				_dress_container(body, size)
			&"structure":
				_add_trim(entry[0], entry[1], entry[2], entry[4])

	_build_levels()
	_build_spawns()
	_build_sites_and_signs()
	_build_dressing()
	_build_props()


## Concrete pads where people stand and fight - the spawns and both sites - so
## the ground reads as places, not one endless dirt field.
func _build_floor_finish() -> void:
	_add_floor_pad(Vector2(-12, 32), Vector2(12, 45), &"concrete")
	_add_floor_pad(Vector2(-12, -45), Vector2(12, -36), &"concrete")
	_add_floor_pad(Vector2(-32, -32), Vector2(-10, -8), &"paving")
	_add_floor_pad(Vector2(10, -32), Vector2(32, -8), &"paving")


## Scanned props, all against walls or in spawn corners so no sightline or
## route changes: supply crates and fuel barrels in the spawns, road barriers
## along the lane walls, units and boxes on the buildings.
func _build_props() -> void:
	_build_floor_finish()
	# Attacker spawn
	_add_prop("old_military_crate", Vector3(-10.6, 0.0, 43.8))
	_add_prop("wooden_military_crate", Vector3(-11.1, 0.0, 41.4), 90.0)
	_add_prop("wooden_military_crate", Vector3(-11.1, 0.465, 41.4), 84.0)
	_add_prop("Barrel_01", Vector3(11.2, 0.0, 44.2))
	_add_prop("Barrel_01", Vector3(10.5, 0.0, 44.4), 40.0)
	_add_prop("Barrel_01", Vector3(11.3, 0.0, 43.5), 75.0)
	_add_prop("portable_generator", Vector3(10.9, 0.0, 38.5), -90.0)
	# Defender spawn
	_add_prop("old_military_crate", Vector3(-10.6, 0.0, -43.8))
	_add_prop("portable_generator", Vector3(-10.9, 0.0, -38.5), 90.0)
	_add_prop("Barrel_01", Vector3(11.2, 0.0, -44.2))
	_add_prop("Barrel_01", Vector3(10.5, 0.0, -44.4), 20.0)
	_add_prop("wooden_crate_02", Vector3(11.3, 0.0, -41.0))
	# Lane walls
	_add_prop("concrete_road_barrier", Vector3(-31.6, 0.0, 12.0), 90.0)
	_add_prop("concrete_road_barrier", Vector3(-31.6, 0.0, 13.6), 92.0)
	_add_prop("concrete_road_barrier", Vector3(31.6, 0.0, 15.0), 90.0)
	_add_prop("utility_box_01", Vector3(-19.24, 0.0, 22.0), -90.0)
	_add_prop("utility_box_01", Vector3(19.24, 0.0, 16.0), 90.0)
	# Site corners
	_add_prop("Barrel_01", Vector3(-10.7, 0.0, -31.3))
	_add_prop("Barrel_01", Vector3(10.7, 0.0, -31.3), 50.0)
	_add_prop("wooden_crate_02", Vector3(31.4, 1.6, -30.0), 0.0)
	# Wall-mounted units, out of reach
	_add_prop("exterior_aircon_unit", Vector3(4.0, 3.2, -13.8), 0.0, false)
	_add_prop("exterior_aircon_unit", Vector3(-4.8, 3.6, 20.0), -90.0, false)
	_add_prop("exterior_aircon_unit", Vector3(-19.2, 3.4, 2.0), -90.0, false)
	_add_prop("exterior_aircon_unit", Vector3(19.2, 3.1, -3.0), 90.0, false)


## The relay-station identity: masts on the rooftops (the tallest on the
## central block - "the relay" the attackers are trying to overload), signal
## pylons marking each site, and roofline light strips - amber over the heart
## of the map, cyan over the spawns.
func _build_dressing() -> void:
	_add_relay_mast(Vector3(0.0, WALL_HEIGHT, -23.0), 9.0)
	_add_relay_mast(Vector3(-22.0, WALL_HEIGHT, 39.0), 5.0)
	_add_relay_mast(Vector3(22.0, WALL_HEIGHT, 38.0), 4.0)
	_add_relay_mast(Vector3(-20.0, WALL_HEIGHT, -41.0), 4.5)
	_add_relay_mast(Vector3(21.0, WALL_HEIGHT, -40.0), 5.5)
	_add_relay_mast(Vector3(-12.0, WALL_HEIGHT, 1.0), 3.5)

	_add_pylon(Vector3(-31.2, 0.0, -31.2), SITE_COLOUR)
	_add_pylon(Vector3(31.2, 0.0, -8.8), SITE_COLOUR)

	_outline_roof(Vector2(-9, -32), Vector2(9, -14), WALL_HEIGHT + 0.04, UITheme.ACCENT)
	_outline_roof(Vector2(-32, 32), Vector2(-12, 45), WALL_HEIGHT + 0.04, UITheme.TECH)
	_outline_roof(Vector2(12, 32), Vector2(32, 45), WALL_HEIGHT + 0.04, UITheme.TECH)
	_outline_roof(Vector2(-32, -45), Vector2(-12, -36), WALL_HEIGHT + 0.04, UITheme.TECH)
	_outline_roof(Vector2(12, -45), Vector2(32, -36), WALL_HEIGHT + 0.04, UITheme.TECH)


## Floor and the outer wall ring.
func _build_shell() -> void:
	var width := MAX_X - MIN_X
	var depth := MAX_Z - MIN_Z
	_add_box("Floor", Vector3(0.0, -0.5, 0.0), Vector3(width + 2.0, 1.0, depth + 2.0), &"floor")
	_add_block("WallWest", Vector2(MIN_X - 1.0, MIN_Z - 1.0), Vector2(MIN_X, MAX_Z + 1.0), OUTER_HEIGHT, &"outer")
	_add_block("WallEast", Vector2(MAX_X, MIN_Z - 1.0), Vector2(MAX_X + 1.0, MAX_Z + 1.0), OUTER_HEIGHT, &"outer")
	_add_block("WallNorth", Vector2(MIN_X, MAX_Z), Vector2(MAX_X, MAX_Z + 1.0), OUTER_HEIGHT, &"outer")
	_add_block("WallSouth", Vector2(MIN_X, MIN_Z - 1.0), Vector2(MAX_X, MIN_Z), OUTER_HEIGHT, &"outer")


## The raised positions: a ledge on A's west wall and a platform in B's back
## corner, each reached by 0.4 m steps the controller walks up.
func _build_levels() -> void:
	# A ledge: 1.2 m, stairs climbing west.
	_add_block("ALedge", Vector2(-32, -20), Vector2(-26, -12), 1.2, &"platform")
	_add_stairs("ALedgeStep", Vector3(-23.0, 0.0, -16.0), Vector3.LEFT, 4.0, 3, 0.4, 1.0, &"platform")

	# B platform: 1.6 m, stairs climbing east.
	_add_block("BPlatform", Vector2(26, -32), Vector2(32, -24), 1.6, &"platform")
	_add_stairs("BPlatformStep", Vector3(22.0, 0.0, -28.0), Vector3.RIGHT, 4.0, 4, 0.4, 1.0, &"platform")


func _build_spawns() -> void:
	# Attackers face -Z (yaw 0) towards the map; defenders face +Z.
	_add_spawn_marker("AlphaSpawn", Vector3(0.0, 0.0, 40.0), 0.0)
	_add_spawn_marker("BravoSpawn", Vector3(0.0, 0.0, -40.5), 180.0)

	# Sides swap spawns at half time, so the spawns are labelled by role and
	# the barriers are neutral rather than team-coloured.
	_add_spawn_barrier("AttackerBarrier", Vector2(-12, 31.6), Vector2(12, 32), BARRIER_COLOUR)
	_add_spawn_barrier("DefenderBarrier", Vector2(-12, -36), Vector2(12, -35.6), BARRIER_COLOUR)

	add_sign("ATTACKERS", Vector3(0.0, 4.2, 44.9), 180.0, SIGN_COLOUR, 2.0)
	add_sign("DEFENDERS", Vector3(0.0, 4.2, -44.9), 0.0, SIGN_COLOUR, 2.0)


func _build_sites_and_signs() -> void:
	_add_site("A", Vector2(-32, -32), Vector2(-10, -8), SITE_COLOUR, Vector3(-28.0, 3.6, -31.9), 0.0)
	_add_site("B", Vector2(10, -32), Vector2(32, -8), SITE_COLOUR, Vector3(27.0, 3.6, -31.9), 0.0)

	# Callouts, readable from the side that needs them. A Label3D faces +Z, so
	# a sign seen from the attacker side (looking -Z) keeps yaw 0.
	add_sign("< A", Vector3(-12.0, 3.0, 26.05), 0.0, SIGN_COLOUR, 1.4)
	add_sign("B >", Vector3(12.0, 3.0, 26.05), 0.0, SIGN_COLOUR, 1.4)
	add_sign("MID", Vector3(0.0, 3.4, -13.95), 0.0, SIGN_COLOUR, 1.6)
	add_sign("A >", Vector3(-4.0, 3.0, -32.05), 180.0, SIGN_COLOUR, 1.4)
	add_sign("< B", Vector3(4.0, 3.0, -32.05), 180.0, SIGN_COLOUR, 1.4)
	add_sign("A MAIN", Vector3(-26.95, 3.0, -5.5), 90.0, SIGN_COLOUR, 1.0)
	add_sign("B MAIN", Vector3(26.95, 3.0, -3.0), -90.0, SIGN_COLOUR, 1.0)
