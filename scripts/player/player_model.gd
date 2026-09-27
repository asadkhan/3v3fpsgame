class_name PlayerModel
extends Node3D
## The body other players see: a rigged soldier, animated from what the network
## says this player is doing.
##
## Character and animations: Mixamo's "Ch15" operator (urban camo, plate
## carrier, helmet, goggles, mask) with Mixamo rifle animations, downloaded by
## the project owner from mixamo.com. Falls back to the earlier soldiers
## ("Military man" / "Solider" by madtrollstudio, CC BY 3.0, with Mesh2Motion
## CC0 animations) if the Mixamo files are missing. Everything is retargeted
## onto Godot's humanoid skeleton at import (bone maps in
## [code]assets/characters/retarget/[/code]), so any animation plays on any
## character.
##
## Animations are addressed by role ([constant ROLES]): the set in use maps each
## role to a clip. Layers, bottom to top:
## - legs: a 2D blend of idle, run, backpedal and strafes by the body's velocity
##   in its own frame; the same for crouching; an in-air pose.
## - upper body: for the fallback set, whose clips hold no rifle, a two-handed
##   hold overridden onto the spine and arms. The Mixamo clips already hold one.
## - [PlayerModelAim]: bends spine and neck with the aim pitch.
## - two-bone IK: each hand onto the held gun's [code]HandR[/code] /
##   [code]HandL[/code] marker, so the gun is really held whatever it is.
## Death plays one of the falls and holds the last frame.

const MIXAMO_DIR := "res://assets/characters/mixamo/"
const MIXAMO_MODEL := MIXAMO_DIR + "ch15_soldier.scn"
## role -> [file, loops, strip travel]. Strip travel: the clip was exported
## with root motion, so its forward drift is removed and the body's own
## (networked) movement carries it instead.
const MIXAMO_ANIMS := {
	&"idle": ["rifle_idle", true, false],
	&"run": ["rifle_run", true, true],
	&"back": ["backwards_rifle_walk", true, true],
	&"strafe_l": ["strafe_left", true, true],
	&"strafe_r": ["strafe_right", true, true],
	&"crouch_idle": ["idle_crouching", true, false],
	&"crouch_walk": ["rifle_crouch_walk", true, true],
	&"air": ["rifle_jump", true, false],
	&"death_a": ["rifle_death", false, false],
	&"death_b": ["death_from_the_front", false, false],
	&"death_c": ["death_from_back_headshot", false, false],
	&"hold": ["rifle_idle", true, false],
}

const FALLBACK_MODELS := {
	Team.Side.ALPHA: "res://assets/characters/soldiers/military_man.glb",
	Team.Side.BRAVO: "res://assets/characters/soldiers/soldier.glb",
	Team.Side.NONE: "res://assets/characters/soldiers/military_man.glb",
}
const FALLBACK_FILES := [
	"res://assets/characters/animations/m2m_base.glb",
	"res://assets/characters/animations/m2m_addon.glb",
]
const FALLBACK_ANIMS := {
	&"idle": [&"Idle_A", true, false], &"run": [&"Jog", true, false], &"back": [&"Walk_Backwards", true, false],
	&"strafe_l": [&"Strafe_left", true, false], &"strafe_r": [&"Strafe_right", true, false],
	&"crouch_idle": [&"Crouch_Idle", true, false], &"crouch_walk": [&"Crouch_Walk", true, false],
	&"air": [&"Jump_air", true, false], &"death_a": [&"Death_B", false, false],
	&"death_b": [&"Death_C", false, false], &"death_c": [&"Death_D", false, false],
	&"hold": [&"Pistol_Aim_Neutral", true, false],
}
const DEATHS := [&"death_a", &"death_b", &"death_c"]
## Bones the upper-body hold overrides (fallback set only).
const UPPER_BONES := [&"Spine", &"Chest", &"UpperChest", &"Neck", &"Head",
	&"LeftShoulder", &"LeftUpperArm", &"LeftLowerArm", &"LeftHand",
	&"RightShoulder", &"RightUpperArm", &"RightLowerArm", &"RightHand"]
## Team colour washed over the Mixamo operator's urban camo: cool grey-blue
## for Alpha, sand for Bravo.
const TEAM_TINT := {
	Team.Side.ALPHA: Color(0.66, 0.8, 1.0),
	Team.Side.BRAVO: Color(1.0, 0.78, 0.52),
	Team.Side.NONE: Color(1, 1, 1),
}
## Scale that puts the model's eyes at the player's eye height (1.62 m).
const MODEL_SCALE := 0.98

static var _library: AnimationLibrary = null
static var _mixamo: int = -1
## Metres per second the run clip covers at 1x, measured from its root motion.
static var _run_speed: float = 3.3

var skeleton: Skeleton3D = null
var _model: Node3D = null
var _player: AnimationPlayer = null
var _tree: AnimationTree = null
var _aim: PlayerModelAim = null
var _ik_targets: Array[Node3D] = []
var _iks: Array[SkeletonModifier3D] = []
var _dead: bool = false
var _team: int = -99


static func uses_mixamo() -> bool:
	if _mixamo < 0:
		_mixamo = 1 if ResourceLoader.exists(MIXAMO_MODEL) else 0
	return _mixamo == 1


## Builds (or rebuilds, on a team change) the soldier for [param team].
func build(team: int) -> void:
	if team == _team and _model != null:
		return
	_team = team
	if _model != null:
		remove_child(_model)
		_model.queue_free()
	var path: String = MIXAMO_MODEL if uses_mixamo() else FALLBACK_MODELS.get(team, FALLBACK_MODELS[Team.Side.NONE])
	_model = (load(path) as PackedScene).instantiate() as Node3D
	# Imported characters face +Z; the player faces -Z.
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	skeleton = _model.get_node("%GeneralSkeleton") as Skeleton3D
	# The character's own preview animations are not ours to play.
	for own: AnimationPlayer in _model.find_children("*", "AnimationPlayer", true, false):
		own.queue_free()
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(i) as BaseMaterial3D
			if material == null:
				continue
			if uses_mixamo():
				mesh.set_surface_override_material(i, _tinted(material, team))
			elif material.albedo_texture != null:
				mesh.set_surface_override_material(i, _field_kit(material.albedo_texture, team))

	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	_model.add_child(_player)
	_player.root_node = _player.get_path_to(_model)
	_player.add_animation_library(&"", _shared_library())
	_tree = _build_tree()
	_model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.active = true

	_add_armbands(team)

	_aim = PlayerModelAim.new()
	skeleton.add_child(_aim)
	_iks.clear()
	_ik_targets.clear()
	for side in ["Right", "Left"]:
		var target := Node3D.new()
		target.name = "%sHandTarget" % side
		add_child(target)
		var pole := Node3D.new()
		pole.name = "%sElbowPole" % side
		add_child(pole)
		var ik := ClassDB.instantiate(&"TwoBoneIK3D") as SkeletonModifier3D
		ik.set(&"setting_count", 1)
		ik.set(&"settings/0/root_bone_name", "%sUpperArm" % side)
		ik.set(&"settings/0/middle_bone_name", "%sLowerArm" % side)
		ik.set(&"settings/0/end_bone_name", "%sHand" % side)
		skeleton.add_child(ik)
		ik.set(&"settings/0/target_node", ik.get_path_to(target))
		ik.set(&"settings/0/pole_node", ik.get_path_to(pole))
		ik.influence = 0.0
		_iks.append(ik)
		_ik_targets.append(target)
		_ik_targets.append(pole)
	_dead = false


## A glowing band in the side's colour round each upper arm: the one thing
## that tells a teammate from an enemy at a glance, from any angle, in shade.
func _add_armbands(team: int) -> void:
	if team == Team.Side.NONE:
		return
	var colour := UITheme.team_colour(team)
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 1.4
	material.roughness = 0.6
	# The skeleton may carry the importer's scale; the band is sized in metres.
	var unit := 1.0 / maxf(skeleton.global_basis.get_scale().x, 0.0001)
	for side in ["Left", "Right"]:
		var bone := skeleton.find_bone("%sUpperArm" % side)
		var child := skeleton.find_bone("%sLowerArm" % side)
		if bone < 0 or child < 0:
			continue
		var length := skeleton.get_bone_rest(child).origin.length()
		var attach := BoneAttachment3D.new()
		attach.name = "%sArmband" % side
		attach.bone_name = "%sUpperArm" % side
		skeleton.add_child(attach)
		var band := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.062
		mesh.bottom_radius = 0.066
		mesh.height = 0.075
		mesh.radial_segments = 16
		mesh.rings = 1
		band.mesh = mesh
		band.material_override = material
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		band.scale = Vector3.ONE * unit
		band.position = Vector3(0.0, length * 0.3, 0.0)
		attach.add_child(band)


static var _tint_cache: Dictionary = {}


## The operator's own textured material with the team colour washed over it,
## matte like cloth rather than the importer's default.
static func _tinted(source: BaseMaterial3D, team: int) -> BaseMaterial3D:
	var key := "%d_%d" % [source.get_instance_id(), team]
	if not _tint_cache.has(key):
		var material := source.duplicate() as BaseMaterial3D
		material.albedo_color = TEAM_TINT.get(team, Color.WHITE)
		material.metallic = 0.0
		material.roughness = 0.88
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_tint_cache[key] = material
	return _tint_cache[key]


## Camouflage per side: woodland greens for Alpha, desert tans for Bravo.
const CAMO := {
	Team.Side.ALPHA: [Color(0.3, 0.32, 0.2), Color(0.17, 0.19, 0.12), Color(0.4, 0.36, 0.26)],
	Team.Side.BRAVO: [Color(0.72, 0.6, 0.42), Color(0.55, 0.43, 0.28), Color(0.82, 0.72, 0.55)],
	Team.Side.NONE: [Color(0.4, 0.4, 0.36), Color(0.28, 0.28, 0.26), Color(0.5, 0.5, 0.46)],
}
static var _kit_cache: Dictionary = {}


## The worn-kit material ([code]soldier_cloth.gdshader[/code]) over the
## model's flat atlas: fabric weave, team camouflage, dust towards the boots.
static func _field_kit(atlas: Texture2D, team: int) -> ShaderMaterial:
	var key := "%s_%d" % [atlas.resource_path, team]
	if _kit_cache.has(key):
		return _kit_cache[key]
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/soldier_cloth.gdshader")
	material.set_shader_parameter(&"atlas", atlas)
	material.set_shader_parameter(&"fabric_albedo", load("res://assets/materials/rough_linen/rough_linen_diff.jpg"))
	material.set_shader_parameter(&"fabric_normal", load("res://assets/materials/rough_linen/rough_linen_nor_gl.jpg"))
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	noise.width = 256
	noise.height = 256
	var fast := FastNoiseLite.new()
	fast.frequency = 0.02
	fast.fractal_octaves = 3
	noise.noise = fast
	material.set_shader_parameter(&"camo_noise", noise)
	var camo: Array = CAMO.get(team, CAMO[Team.Side.NONE])
	material.set_shader_parameter(&"camo_a", camo[0])
	material.set_shader_parameter(&"camo_b", camo[1])
	material.set_shader_parameter(&"camo_c", camo[2])
	_kit_cache[key] = material
	return material


static func _shared_library() -> AnimationLibrary:
	if _library != null:
		return _library
	_library = AnimationLibrary.new()
	if uses_mixamo():
		for role: StringName in MIXAMO_ANIMS:
			var entry: Array = MIXAMO_ANIMS[role]
			var source := (load(MIXAMO_DIR + String(entry[0]) + ".fbx") as PackedScene).instantiate()
			var ap := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			var anim := _skeleton_only(ap.get_animation(&"mixamo_com"))
			if entry[2]:
				var travelled := _strip_travel(anim)
				if role == &"run":
					_run_speed = maxf(travelled / anim.length, 0.5)
			anim.loop_mode = Animation.LOOP_LINEAR if entry[1] else Animation.LOOP_NONE
			_library.add_animation(role, anim)
			source.free()
	else:
		var sources: Dictionary = {}
		for path in FALLBACK_FILES:
			var source := (load(path) as PackedScene).instantiate()
			for ap: AnimationPlayer in source.find_children("*", "AnimationPlayer", true, false):
				for anim_name in ap.get_animation_list():
					if not sources.has(anim_name):
						sources[anim_name] = _skeleton_only(ap.get_animation(anim_name))
			source.free()
		_run_speed = 4.2
		for role: StringName in FALLBACK_ANIMS:
			var entry: Array = FALLBACK_ANIMS[role]
			if sources.has(entry[0]):
				var anim: Animation = (sources[entry[0]] as Animation).duplicate(true)
				anim.loop_mode = Animation.LOOP_LINEAR if entry[1] else Animation.LOOP_NONE
				_library.add_animation(role, anim)
	return _library


## Removes the hips' steady travel across the ground from a root-motion clip,
## keeping its sway and bob, and returns how far it had travelled.
static func _strip_travel(anim: Animation) -> float:
	var track := anim.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
	if track < 0 or anim.track_get_key_count(track) < 2:
		return 0.0
	var count := anim.track_get_key_count(track)
	var first: Vector3 = anim.track_get_key_value(track, 0)
	var last: Vector3 = anim.track_get_key_value(track, count - 1)
	var drift := Vector3(last.x - first.x, 0.0, last.z - first.z)
	var length := maxf(anim.length, 0.001)
	for k in count:
		var t := anim.track_get_key_time(track, k) / length
		var v: Vector3 = anim.track_get_key_value(track, k)
		anim.track_set_key_value(track, k, Vector3(v.x - first.x - drift.x * t, v.y, v.z - first.z - drift.z * t))
	return drift.length()


## A copy of [param source] with only the skeleton's tracks: the source files
## also animate their own armature node, which does not exist here.
static func _skeleton_only(source: Animation) -> Animation:
	var anim := source.duplicate(true) as Animation
	for i in range(anim.get_track_count() - 1, -1, -1):
		if not String(anim.track_get_path(i)).begins_with("%GeneralSkeleton"):
			anim.remove_track(i)
	return anim


func _build_tree() -> AnimationTree:
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	var root := AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace2D.new()
	loco.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	loco.min_space = Vector2(-2, -2)
	loco.max_space = Vector2(2, 2)
	for point in [[&"idle", Vector2.ZERO], [&"run", Vector2(0, 1)],
			[&"back", Vector2(0, -1)], [&"strafe_l", Vector2(-1, 0)], [&"strafe_r", Vector2(1, 0)]]:
		loco.add_blend_point(_clip(point[0]), point[1], -1, "p%d" % loco.get_blend_point_count())
	root.add_node(&"loco", loco, Vector2(0, 0))
	var loco_speed := AnimationNodeTimeScale.new()
	root.add_node(&"loco_speed", loco_speed, Vector2(200, 0))
	root.connect_node(&"loco_speed", 0, &"loco")

	var crouch := AnimationNodeBlendSpace2D.new()
	crouch.min_space = Vector2(-2, -2)
	crouch.max_space = Vector2(2, 2)
	for point in [[&"crouch_idle", Vector2.ZERO], [&"crouch_walk", Vector2(0, 1)],
			[&"crouch_walk", Vector2(0, -1)], [&"crouch_walk", Vector2(1, 0)], [&"crouch_walk", Vector2(-1, 0)]]:
		crouch.add_blend_point(_clip(point[0]), point[1], -1, "p%d" % crouch.get_blend_point_count())
	root.add_node(&"crouch", crouch, Vector2(0, 200))

	var crouch_mix := AnimationNodeBlend2.new()
	root.add_node(&"crouch_mix", crouch_mix, Vector2(400, 100))
	root.connect_node(&"crouch_mix", 0, &"loco_speed")
	root.connect_node(&"crouch_mix", 1, &"crouch")

	root.add_node(&"air_clip", _clip(&"air"), Vector2(400, 300))
	var air := AnimationNodeBlend2.new()
	root.add_node(&"air", air, Vector2(600, 100))
	root.connect_node(&"air", 0, &"crouch_mix")
	root.connect_node(&"air", 1, &"air_clip")

	root.add_node(&"hold_clip", _clip(&"hold"), Vector2(600, 300))
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	for bone in UPPER_BONES:
		upper.set_filter_path(NodePath("%GeneralSkeleton:" + String(bone)), true)
	root.add_node(&"upper", upper, Vector2(800, 100))
	root.connect_node(&"upper", 0, &"air")
	root.connect_node(&"upper", 1, &"hold_clip")
	root.connect_node(&"output", 0, &"upper")

	tree.tree_root = root
	return tree


static func _clip(anim_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = anim_name
	return node


# --- Per frame ----------------------------------------------------------------------

## [param local_velocity] is the body's velocity in its own frame (x right,
## z back), [param crouch] 0 standing to 1 crouched, [param pitch] the aim in
## radians (up positive), [param gun] the held third-person gun (or null).
func update(delta: float, local_velocity: Vector3, crouch: float, airborne: bool, pitch: float,
		gun: Node3D, walk_speed: float) -> void:
	if _tree == null or _dead:
		return
	var flat := Vector2(local_velocity.x, -local_velocity.z)
	var blend := flat / maxf(walk_speed, 0.1)
	_smooth(&"parameters/loco/blend_position", blend, delta * 10.0)
	_smooth(&"parameters/crouch/blend_position", blend * 1.4, delta * 10.0)
	var speed := flat.length()
	_tree.set(&"parameters/loco_speed/scale", clampf(speed / _run_speed, 0.6, 1.7) if speed > 0.3 else 1.0)
	_smooth_f(&"parameters/crouch_mix/blend_amount", clampf(crouch, 0.0, 1.0), delta * 8.0)
	_smooth_f(&"parameters/air/blend_amount", 1.0 if airborne else 0.0, delta * 6.0)
	var two_handed := gun != null and gun.find_child("HandL", true, false) != null
	# The fallback clips hold no rifle, so a two-handed hold goes over them;
	# one-handed (the knife), the free arm swings with the legs instead.
	_smooth_f(&"parameters/upper/blend_amount", 1.0 if two_handed and not uses_mixamo() else 0.0, delta * 8.0)
	_aim.pitch = pitch

	if uses_mixamo():
		# The clips hold a rifle properly with both hands: the gun goes into
		# them instead of the arms being pulled onto the gun.
		for ik in _iks:
			ik.influence = 0.0
		_mount_gun(gun, two_handed)
	else:
		_place_hands(gun, two_handed)


## Puts [param gun] in the animated hands: its grip in the right hand, its
## barrel running through the left (one-handed, along the aim).
func _mount_gun(gun: Node3D, two_handed: bool) -> void:
	if gun == null or skeleton == null:
		return
	var hand_r := gun.find_child("HandR", true, false) as Node3D
	if hand_r == null:
		return
	var sx := skeleton.global_transform
	var rb := skeleton.find_bone(&"RightHand")
	var rm := skeleton.find_bone(&"RightMiddleProximal")
	var lb := skeleton.find_bone(&"LeftHand")
	if rb < 0:
		return
	var right := sx * skeleton.get_bone_global_pose(rb).origin
	var grip := right.lerp(sx * skeleton.get_bone_global_pose(rm).origin, 0.55) if rm >= 0 else right
	var grip_local := ViewmodelArms._relative(hand_r, gun).origin

	var local_dir := Vector3.FORWARD
	var world_dir := -(gun.get_parent() as Node3D).global_basis.z
	var hand_l := gun.find_child("HandL", true, false) as Node3D
	if two_handed and hand_l != null and lb >= 0:
		var support := sx * skeleton.get_bone_global_pose(lb).origin
		local_dir = (ViewmodelArms._relative(hand_l, gun).origin - grip_local).normalized()
		world_dir = (support - grip).normalized()
	var from := _frame(local_dir, Vector3.UP)
	var to := _frame(world_dir, global_basis.y)
	var basis := to * from.inverse()
	gun.global_transform = Transform3D(basis, grip - basis * grip_local)


static func _frame(forward: Vector3, up: Vector3) -> Basis:
	var f := forward.normalized()
	var r := f.cross(up).normalized()
	if r.length_squared() < 0.0001:
		r = Vector3.RIGHT
	return Basis(r, r.cross(f), -f)


func _place_hands(gun: Node3D, two_handed: bool) -> void:
	for i in 2:
		var ik := _iks[i]
		var marker: Node3D = null
		if gun != null and gun.visible:
			marker = gun.find_child("HandR" if i == 0 else "HandL", true, false) as Node3D
		if marker == null or (i == 1 and not two_handed):
			ik.influence = move_toward(ik.influence, 0.0, 0.2)
			continue
		ik.influence = 1.0
		var target := _ik_targets[i * 2]
		var pole := _ik_targets[i * 2 + 1]
		target.global_position = marker.global_position
		# The elbow points outwards and down, as a rifle is really held.
		var side := 1.0 if i == 0 else -1.0
		pole.global_position = marker.global_position + global_basis * Vector3(0.35 * side, -0.45, 0.25)


func _smooth(param: StringName, to: Vector2, t: float) -> void:
	var from: Vector2 = _tree.get(param)
	_tree.set(param, from.lerp(to, clampf(t, 0.0, 1.0)))


func _smooth_f(param: StringName, to: float, t: float) -> void:
	var from: float = _tree.get(param)
	_tree.set(param, lerpf(from, to, clampf(t, 0.0, 1.0)))


# --- Death ---------------------------------------------------------------------------

func play_death(clip_override: StringName = &"") -> void:
	if _player == null or _dead:
		return
	_dead = true
	_tree.active = false
	for ik in _iks:
		ik.influence = 0.0
	_aim.pitch = 0.0
	var clip: StringName = clip_override if clip_override != &"" else DEATHS[randi() % DEATHS.size()]
	if not _player.has_animation(clip):
		clip = &"death_c"
	# Not looping (set on load), so it holds the last frame.
	_player.play(clip, 0.1)


func revive() -> void:
	if _player == null:
		return
	_dead = false
	_player.stop()
	_tree.active = true
