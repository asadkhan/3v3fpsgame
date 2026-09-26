class_name PlayerModel
extends Node3D
## The body other players see: a rigged soldier, animated from what the network
## says this player is doing.
##
## Characters: "Military man" (Alpha) and "Solider" (Bravo) by madtrollstudio,
## CC BY 3.0, via Poly Pizza. Animations: Mesh2Motion human base and addon sets,
## CC0. Both are retargeted onto Godot's humanoid skeleton at import (bone maps
## in [code]assets/characters/retarget/[/code]), so every animation plays on
## either soldier.
##
## Layers, bottom to top:
## - legs: a 2D blend of idle, jog, backpedal, strafes and sprint by the body's
##   velocity in its own frame; the same for crouching; an in-air pose.
## - upper body: a two-handed forward hold, overridden onto the spine and arms.
## - [PlayerModelAim]: bends spine and neck with the aim pitch.
## - two-bone IK: each hand onto the held gun's [code]HandR[/code] /
##   [code]HandL[/code] marker, so the gun is really held whatever it is.
## Death plays one of four falls and holds the last frame.

const MODELS := {
	Team.Side.ALPHA: "res://assets/characters/soldiers/military_man.glb",
	Team.Side.BRAVO: "res://assets/characters/soldiers/soldier.glb",
	Team.Side.NONE: "res://assets/characters/soldiers/military_man.glb",
}
const ANIMATION_FILES := [
	"res://assets/characters/animations/m2m_base.glb",
	"res://assets/characters/animations/m2m_addon.glb",
]
const LOOPING := [&"Idle_A", &"Jog", &"Sprint", &"Walk", &"Walk_Backwards", &"Strafe_left",
	&"Strafe_right", &"Crouch_Idle", &"Crouch_Walk", &"Jump_air", &"Pistol_Aim_Neutral", &"Pistol_Idle"]
const DEATHS := [&"Death_B", &"Death_C", &"Death_D"]
## Bones the upper-body hold overrides.
const UPPER_BONES := [&"Spine", &"Chest", &"UpperChest", &"Neck", &"Head",
	&"LeftShoulder", &"LeftUpperArm", &"LeftLowerArm", &"LeftHand",
	&"RightShoulder", &"RightUpperArm", &"RightLowerArm", &"RightHand"]
## The speed the Jog clip is played at 1x, metres per second.
const JOG_SPEED := 4.2
## Scale that puts the model's eyes at the player's eye height (1.62 m).
const MODEL_SCALE := 0.97

static var _library: AnimationLibrary = null

var skeleton: Skeleton3D = null
var _model: Node3D = null
var _player: AnimationPlayer = null
var _tree: AnimationTree = null
var _aim: PlayerModelAim = null
var _ik_targets: Array[Node3D] = []
var _iks: Array[SkeletonModifier3D] = []
var _dead: bool = false
var _team: int = -99


## Builds (or rebuilds, on a team change) the soldier for [param team].
func build(team: int) -> void:
	if team == _team and _model != null:
		return
	_team = team
	if _model != null:
		remove_child(_model)
		_model.queue_free()
	var scene := load(MODELS.get(team, MODELS[Team.Side.NONE])) as PackedScene
	_model = scene.instantiate() as Node3D
	# The glTF faces +Z; the player faces -Z.
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	skeleton = _model.get_node("%GeneralSkeleton") as Skeleton3D
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Cloth and webbing: the source marks everything 40% metallic, which
		# mirrors the sky and turns the khaki blue-grey.
		for i in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(i) as BaseMaterial3D
			if material != null:
				material.metallic = 0.0
				material.roughness = 0.9

	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	_model.add_child(_player)
	_player.root_node = _player.get_path_to(_model)
	_player.add_animation_library(&"", _shared_library())
	_tree = _build_tree()
	_model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.active = true

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


static func _shared_library() -> AnimationLibrary:
	if _library != null:
		return _library
	_library = AnimationLibrary.new()
	var wanted: Array = LOOPING + DEATHS
	for path in ANIMATION_FILES:
		var source := (load(path) as PackedScene).instantiate()
		for ap: AnimationPlayer in source.find_children("*", "AnimationPlayer", true, false):
			for anim_name in ap.get_animation_list():
				if anim_name in wanted and not _library.has_animation(anim_name):
					_library.add_animation(anim_name, _skeleton_only(ap.get_animation(anim_name)))
		source.free()
	for anim_name in LOOPING:
		if _library.has_animation(anim_name):
			_library.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	for anim_name in DEATHS:
		if _library.has_animation(anim_name):
			_library.get_animation(anim_name).loop_mode = Animation.LOOP_NONE
	return _library


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
	for point in [[&"Idle_A", Vector2.ZERO], [&"Jog", Vector2(0, 1)], [&"Sprint", Vector2(0, 1.6)],
			[&"Walk_Backwards", Vector2(0, -1)], [&"Strafe_left", Vector2(-1, 0)],
			[&"Strafe_right", Vector2(1, 0)]]:
		loco.add_blend_point(_clip(point[0]), point[1], -1, "p%d" % loco.get_blend_point_count())
	root.add_node(&"loco", loco, Vector2(0, 0))
	var loco_speed := AnimationNodeTimeScale.new()
	root.add_node(&"loco_speed", loco_speed, Vector2(200, 0))
	root.connect_node(&"loco_speed", 0, &"loco")

	var crouch := AnimationNodeBlendSpace2D.new()
	crouch.min_space = Vector2(-2, -2)
	crouch.max_space = Vector2(2, 2)
	for point in [[&"Crouch_Idle", Vector2.ZERO], [&"Crouch_Walk", Vector2(0, 1)],
			[&"Crouch_Walk", Vector2(0, -1)], [&"Crouch_Walk", Vector2(1, 0)], [&"Crouch_Walk", Vector2(-1, 0)]]:
		crouch.add_blend_point(_clip(point[0]), point[1], -1, "p%d" % crouch.get_blend_point_count())
	root.add_node(&"crouch", crouch, Vector2(0, 200))

	var crouch_mix := AnimationNodeBlend2.new()
	root.add_node(&"crouch_mix", crouch_mix, Vector2(400, 100))
	root.connect_node(&"crouch_mix", 0, &"loco_speed")
	root.connect_node(&"crouch_mix", 1, &"crouch")

	root.add_node(&"air_clip", _clip(&"Jump_air"), Vector2(400, 300))
	var air := AnimationNodeBlend2.new()
	root.add_node(&"air", air, Vector2(600, 100))
	root.connect_node(&"air", 0, &"crouch_mix")
	root.connect_node(&"air", 1, &"air_clip")

	root.add_node(&"hold_clip", _clip(&"Pistol_Aim_Neutral"), Vector2(600, 300))
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
	_tree.set(&"parameters/loco_speed/scale", clampf(speed / JOG_SPEED, 0.6, 1.4) if speed > 0.3 else 1.0)
	_smooth_f(&"parameters/crouch_mix/blend_amount", clampf(crouch, 0.0, 1.0), delta * 8.0)
	_smooth_f(&"parameters/air/blend_amount", 1.0 if airborne else 0.0, delta * 6.0)
	var two_handed := gun != null and gun.find_child("HandL", true, false) != null
	# One-handed (the knife): the free arm swings with the legs instead.
	_smooth_f(&"parameters/upper/blend_amount", 1.0 if two_handed else 0.0, delta * 8.0)
	_aim.pitch = pitch

	_place_hands(gun, two_handed)


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
		clip = &"Death_D"
	# Not looping (set on load), so it holds the last frame.
	_player.play(clip, 0.1)


func revive() -> void:
	if _player == null:
		return
	_dead = false
	_player.stop()
	_tree.active = true
