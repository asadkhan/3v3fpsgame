class_name ViewmodelArms
extends Node3D
## first-person arms: sleeves, elbow pads, wrist straps, gloves - built from
## primitives in code so they need no art assets and match the flat-shaded
## weapon models.
##
## Weapon adds one of these under its viewmodel whenever the model changes.
## the model scene marks where hands go with HandR/HandL markers (children of
## Model), each carrying metadata:
##   grip - how the hand holds it: "pistol" (raked grip), "vertical"
##          (foregrip), "rail" (under a handguard)
##   radius - how thick the held thing is, in metres
##   hand_scale - optional, shrinks the hand for a small gun
## no markers = no arms. shoulders are fixed points below/behind the camera;
## each arm reaches its hand with two-bone IK, so a new gun just needs its
## two markers.
##
## hands/forearms are a scanned skinned arm model (ARM_MODEL, fingerless
## gloves): placed on each marker, mirrored for the left hand, wrist bent so
## the forearm runs to the IK elbow, fingers curled round the grip. sleeves
## and upper arms are still built here from primitives in the team colour.
## falls back to primitives entirely if the model file is missing.
##
## re-solved every frame so ViewmodelAnimator can move the gun, pull the left
## hand off it (mag change), open the fingers (knife toss) while shoulders
## stay put under the camera. purely cosmetic and local.

const ARM_MODEL := "res://assets/characters/fp_arms/firstPersonHandsWithGloves.FBX"
const ARM_TEXTURES := "res://assets/characters/fp_arms/ArmWithGlove%s.png"

## arm model's axes in hand space (see _grip_basis): fingers point -Z, back
## of hand faces +X, knuckles run index to pinky along +X (-Y down the grip).
const MODEL_TO_HAND := Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))
## centre of the curled-fingers loop, in model space - a held object's axis
## runs through it. measured from the curled pose.
const MODEL_GRIP_CENTRE := Vector3(0.006, -0.013, -0.055)
## grip radius the curl angles below are tuned for; thicker grips open the hand.
const CURL_RADIUS := 0.019
## finger curl in degrees per joint (base, middle, tip).
const CURL_GRIP := [62.0, 78.0, 48.0]
const CURL_TRIGGER := [18.0, 22.0, 12.0]
const CURL_THUMB := [45.0, 40.0, 30.0]
## thumb bends about a different local axis than the fingers.
const THUMB_AXIS := Vector3(-1, 0, 0)
const FINGERS := [
	["BoneIndexBase", "BoneIndexMid", "BoneIndexEnd"],
	["BoneMiddleBase", "BoneMiddleMid", "BoneMiddleBaseEnd"],
	["BoneRingBase", "BoneRingMiddle", "BoneRingEnd"],
	["BonePinkyBase", "BonePinkyMid", "BonePinkyEnd"],
]
const THUMB := ["Bone003", "Bone004", "Bone005"]

static var _arm_scene: PackedScene = null
static var _skin: StandardMaterial3D = null

## shoulders, in the weapon's space: camera at origin looking down -Z.
const SHOULDER_R := Vector3(0.17, -0.3, 0.06)
const SHOULDER_L := Vector3(-0.19, -0.32, 0.04)
const UPPER_LENGTH := 0.24
const FORE_LENGTH := 0.23

## sleeve colour per side: blue-grey Alpha, tan Bravo, olive otherwise.
const SLEEVE_COLOURS := {
	Team.Side.NONE: Color(0.24, 0.26, 0.19),
	Team.Side.ALPHA: Color(0.19, 0.23, 0.29),
	Team.Side.BRAVO: Color(0.4, 0.34, 0.25),
}

var _body: Node = null
var _team: int = -1
var _fabric: BaseMaterial3D
var _leather: BaseMaterial3D
var _hard: BaseMaterial3D
var _nylon: BaseMaterial3D
var _accent: BaseMaterial3D
var _patch: BaseMaterial3D


## what the animator can change each frame: left hand can be pulled off its
## marker towards left_override (hand frame in viewmodel space) by
## left_weight, or hidden; either hand can open from its grip via grip_open
## (0 closed, 1 flat open).
var left_override := Transform3D.IDENTITY
var left_weight: float = 0.0
var left_visible: bool = true
var grip_open: Array[float] = [0.0, 0.0]

var _viewmodel: Node3D = null
var _arms: Array[Dictionary] = []


## builds both arms. viewmodel is the node this rig lives under (its
## transform places the shoulders); model is the weapon model holding the
## hand markers; body is the player, read for team colour.
func build(viewmodel: Node3D, model: Node3D, body: Node) -> void:
	_viewmodel = viewmodel
	_body = body
	_make_materials()
	for side in [1, -1]:
		var marker := model.find_child("HandR" if side == 1 else "HandL", true, false) as Node3D
		if marker == null:
			continue
		_arms.append(_build_arm(side, marker))
	_refresh_team()
	_solve_all()


func _process(_delta: float) -> void:
	_refresh_team()
	_solve_all()


func _refresh_team() -> void:
	var state: Variant = _body.get("state") if _body != null else null
	var team: int = state.team if state != null else Team.Side.NONE
	if team != _team:
		_team = team
		_fabric.albedo_color = SLEEVE_COLOURS.get(team, SLEEVE_COLOURS[Team.Side.NONE])


## rest frame of the hand a marker describes, in viewmodel space.
func hand_frame(marker: Node3D) -> Transform3D:
	var at := _relative(marker, _viewmodel)
	var grip := String(marker.get_meta(&"grip", "pistol"))
	return Transform3D(_grip_basis(grip, at.basis), at.origin)


# --- Layout ---------------------------------------------------------------------

## the hand's frame for each grip type. in that frame the held object runs
## along +Y, back of the hand faces +X, wrist towards +Z. left hand mirrors
## the geometry so its back faces -X. "custom" keeps the marker's own
## orientation (the knife).
static func _grip_basis(grip: String, marker_basis := Basis()) -> Basis:
	match grip:
		"custom":
			return marker_basis.orthonormalized()
		"rail":
			# palm up under the handguard, fingers over the right side.
			return Basis(Vector3.UP, Vector3.FORWARD, Vector3.LEFT)
		"vertical":
			return Basis(Vector3.RIGHT, Vector3(0, 1, -0.12).normalized(),
				Vector3(0, 0.12, 1).normalized())
		_:
			# pistol grip rakes back towards the bottom.
			var up := Vector3(0, 0.95, -0.3).normalized()
			return Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up))


## builds one arm as three moving parts: hand (on its marker), forearm and
## upper-arm sleeves, each built along its own +Y with the elbow's outside
## towards +Z so _solve only has to aim them.
func _build_arm(side: int, marker: Node3D) -> Dictionary:
	var r := float(marker.get_meta(&"radius", 0.02))
	var hand_scale := float(marker.get_meta(&"hand_scale", 1.0))
	var trigger := String(marker.get_meta(&"grip", "pistol")) == "pistol" and side == 1

	var hand_node := Node3D.new()
	add_child(hand_node)
	var glove := Node3D.new()
	glove.scale = Vector3(side, 1, 1) * hand_scale
	hand_node.add_child(glove)
	var scanned := _build_scanned_hand(glove)
	var fore_length := FORE_LENGTH
	var wrist_local: Vector3
	if scanned.is_empty():
		_build_glove(glove, r / hand_scale, trigger)
		wrist_local = glove.transform * Vector3(r + 0.008, -0.018, 0.075)
	else:
		wrist_local = glove.transform * (scanned.wrist as Vector3)
		fore_length = (scanned.fore_length as float) * hand_scale

	var upper := Node3D.new()
	add_child(upper)
	var fore := Node3D.new()
	add_child(fore)
	_build_upper_sleeve(upper)
	_build_fore_sleeve(fore, fore_length, not scanned.is_empty())
	return {
		"side": side, "marker": marker, "trigger": trigger, "r": r / hand_scale,
		"hand": hand_node, "glove": glove, "scanned": scanned, "wrist": wrist_local,
		"upper": upper, "fore": fore, "fore_length": fore_length, "open": -1.0,
	}


func _build_upper_sleeve(upper: Node3D) -> void:
	var u := UPPER_LENGTH
	_limb(upper, Vector3.ZERO, Vector3(0, u, 0), 0.046, 0.038, _fabric)
	_limb(upper, Vector3(0, u * 0.6 - 0.01, 0), Vector3(0, u * 0.6 + 0.01, 0), 0.044, 0.043, _nylon)
	_box(upper, Vector3(0, u * 0.6, 0.04), Vector3(0.038, 0.055, 0.022), Vector3.UP, Vector3.BACK, _nylon)


## forearm sleeve: elbow ball and pad, sleeve bunched at the cuff, a strap, a
## velcro patch. wider and shorter over the scanned forearm so the model's
## bare skin never shows through.
func _build_fore_sleeve(fore: Node3D, length: float, scanned: bool) -> void:
	var s := 1.5 if scanned else 1.0
	var cuff := length - (0.05 if scanned else 0.03)
	_ellipsoid(fore, Vector3.ZERO, Vector3(0.038, 0.038, 0.038), Vector3.UP, Vector3.BACK, _fabric)
	_ellipsoid(fore, Vector3(0, 0, 0.024), Vector3(0.036, 0.046, 0.022), Vector3.UP, Vector3.BACK, _hard)
	_limb(fore, Vector3.ZERO, Vector3(0, cuff, 0), 0.037 * s, 0.031 * s, _fabric)
	_limb(fore, Vector3(0, cuff - 0.03, 0), Vector3(0, cuff, 0), 0.035 * s, 0.034 * s, _fabric)
	# folds where the sleeve bunches above the cuff, each a bit askew.
	for i in 3:
		var y := cuff - (0.045 + i * 0.03)
		var tilt := (Vector3.BACK if i % 2 == 0 else Vector3.RIGHT) * 0.004
		var fold := (0.0345 + i * 0.001) * s
		_limb(fore, Vector3(0, y - 0.006, 0) - tilt, Vector3(0, y + 0.006, 0) + tilt, fold, fold, _fabric)
	_box(fore, Vector3(0, cuff * 0.25, 0.033 * s), Vector3(0.03, 0.05, 0.006), Vector3.UP, Vector3.BACK, _patch)
	var band := cuff * 0.5
	_limb(fore, Vector3(0, band - 0.008, 0), Vector3(0, band + 0.008, 0), 0.036 * s, 0.0355 * s, _nylon)
	_box(fore, Vector3(0, band, 0.036 * s), Vector3(0.018, 0.024, 0.01), Vector3.UP, Vector3.BACK, _hard)
	if not scanned:
		_limb(fore, Vector3(0, cuff - 0.004, 0), Vector3(0, length + 0.004, 0), 0.03, 0.029, _nylon)
		_box(fore, Vector3(0, (cuff + length) * 0.5, 0.03), Vector3(0.022, 0.016, 0.005), Vector3.UP, Vector3.BACK, _accent)


# --- Per-frame solve ----------------------------------------------------------------

func _solve_all() -> void:
	if _viewmodel == null:
		return
	for arm in _arms:
		_solve(arm)


## puts the hand where it belongs this frame and aims both sleeves with
## two-bone IK from a shoulder fixed under the camera, whatever the gun does.
func _solve(arm: Dictionary) -> void:
	var side: int = arm.side
	var visible_now := side == 1 or left_visible
	for key in ["hand", "upper", "fore"]:
		(arm[key] as Node3D).visible = visible_now
	if not visible_now:
		return

	var frame := hand_frame(arm.marker)
	if side == -1 and left_weight > 0.0:
		frame = _blend(frame, left_override, left_weight)
	var hand_node := arm.hand as Node3D
	hand_node.transform = frame
	_apply_open(arm, grip_open[0 if side == 1 else 1])

	var wrist := frame * (arm.wrist as Vector3)
	var shoulder := _viewmodel.transform.affine_inverse() * (SHOULDER_R if side == 1 else SHOULDER_L)
	var fore_length: float = arm.fore_length
	var reach := wrist - shoulder
	var d := clampf(reach.length(), 0.05, UPPER_LENGTH + fore_length - 0.002)
	var dir := reach.normalized()
	var along := (UPPER_LENGTH * UPPER_LENGTH - fore_length * fore_length + d * d) / (2.0 * d)
	var out := sqrt(maxf(UPPER_LENGTH * UPPER_LENGTH - along * along, 0.0))
	# elbow bends outwards and down, in the camera's frame.
	var pole := _viewmodel.transform.basis.inverse() * Vector3(0.7 * side, -1.0, 0.25)
	pole = (pole - dir * pole.dot(dir)).normalized()
	var elbow := shoulder + dir * along + pole * out

	(arm.upper as Node3D).transform = Transform3D(_facing(elbow - shoulder, pole), shoulder)
	# out of reach (hand dropped off-screen), stretch the forearm instead of
	# leaving a gap at the wrist.
	var stretch := elbow.distance_to(wrist) / fore_length
	(arm.fore as Node3D).transform = Transform3D(
		_facing(wrist - elbow, pole).scaled_local(Vector3(1, stretch, 1)), elbow)

	var scanned: Dictionary = arm.scanned
	if not scanned.is_empty():
		var glove := arm.glove as Node3D
		var rig_to_skeleton := (frame * glove.transform * (scanned.model as Node3D).transform).affine_inverse()
		_bend_forearm(scanned, rig_to_skeleton * elbow)


## re-curls a scanned hand's fingers when openness changes.
func _apply_open(arm: Dictionary, amount: float) -> void:
	var scanned: Dictionary = arm.scanned
	if scanned.is_empty() or is_equal_approx(amount, arm.open):
		return
	arm.open = amount
	var skeleton := scanned.skeleton as Skeleton3D
	var closed := clampf(CURL_RADIUS / maxf(arm.r, 0.005), 0.6, 1.15) * (1.0 - amount)
	for i in FINGERS.size():
		_curl(skeleton, FINGERS[i], CURL_TRIGGER if i == 0 and arm.trigger else CURL_GRIP, closed)
	_curl(skeleton, THUMB, CURL_THUMB, closed, THUMB_AXIS)


static func _blend(a: Transform3D, b: Transform3D, weight: float) -> Transform3D:
	var t := clampf(weight, 0.0, 1.0)
	var q := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), t)
	return Transform3D(Basis(q), a.origin.lerp(b.origin, t))


# --- Scanned hand -----------------------------------------------------------------

## puts the skinned arm model under glove (the hand frame, mirrored for the
## left hand) with the finger-curl loop centred on the frame's origin; curl
## itself is set by _apply_open. returns the model, skeleton, wrist in glove
## space and forearm length - or empty if the model is missing.
func _build_scanned_hand(glove: Node3D) -> Dictionary:
	if _arm_scene == null:
		_arm_scene = load(ARM_MODEL) as PackedScene
		if _arm_scene == null:
			return {}
		_skin = StandardMaterial3D.new()
		_skin.albedo_texture = load(ARM_TEXTURES % "Albedo")
		_skin.normal_enabled = true
		_skin.normal_texture = load(ARM_TEXTURES % "Normal")
		_skin.roughness_texture = load(ARM_TEXTURES % "Roughness")
		_skin.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var model := _arm_scene.instantiate() as Node3D
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		model.free()
		return {}
	var skeleton := skeletons[0] as Skeleton3D
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = _skin
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.transform = Transform3D(MODEL_TO_HAND, -(MODEL_TO_HAND * MODEL_GRIP_CENTRE))
	glove.add_child(model)

	var wrist := skeleton.get_bone_global_rest(skeleton.find_bone("BoneHand")).origin
	var elbow := skeleton.get_bone_global_rest(skeleton.find_bone("BoneArm")).origin
	return {
		"model": model, "skeleton": skeleton,
		"wrist": model.transform * wrist, "fore_length": wrist.distance_to(elbow),
	}


static func _curl(skeleton: Skeleton3D, bones: Array, degrees: Array, amount: float,
		axis := Vector3.UP) -> void:
	for j in bones.size():
		var bone := skeleton.find_bone(bones[j])
		if bone < 0:
			continue
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(bone, rest * Quaternion(axis, deg_to_rad(degrees[j] * amount)))


## swings the forearm about the wrist so it runs to elbow (skeleton space)
## while the hand stays on the grip - like a real wrist bend.
static func _bend_forearm(scanned: Dictionary, elbow: Vector3) -> void:
	var skeleton := scanned.skeleton as Skeleton3D
	var arm := skeleton.find_bone("BoneArm")
	var roll := skeleton.find_bone("BoneWristRoll")
	var hand := skeleton.find_bone("BoneHand")
	var wrist := skeleton.get_bone_global_rest(hand).origin
	var arm_rest := skeleton.get_bone_global_rest(arm)
	var from := (arm_rest.origin - wrist).normalized()
	var to := (elbow - wrist).normalized()
	if from.cross(to).length() < 0.0001:
		return
	var swing := Transform3D(Basis(Quaternion(from, to)), wrist) * Transform3D(Basis(), -wrist)
	skeleton.set_bone_global_pose(arm, swing * arm_rest)
	if roll >= 0:
		skeleton.set_bone_global_pose(roll, swing * skeleton.get_bone_global_rest(roll))
	skeleton.set_bone_global_pose(hand, skeleton.get_bone_global_rest(hand))


## the glove, in hand space (see _grip_basis) around an object of radius r
## running along Y.
func _build_glove(glove: Node3D, r: float, trigger: bool) -> void:
	var x := r + 0.012
	# palm, back of hand, and the cuff meeting the wrist band.
	_blob(glove, Vector3(x, -0.002, 0.028), Vector3(0.015, 0.043, 0.042), _leather)
	_blob(glove, Vector3(x - 0.002, -0.014, 0.066), Vector3(0.017, 0.03, 0.022), _leather)
	# hard knuckle guard across the back of the hand.
	_blob(glove, Vector3(x + 0.012, 0.0, 0.006), Vector3(0.008, 0.038, 0.017), _hard)
	for i in 4:
		var y := 0.03 - i * 0.02
		_part(glove, _sphere_mesh(0.0078), _hard, Transform3D(Basis(), Vector3(x + 0.011, y, -0.007)))
		var thick := 0.0095 if i < 3 else 0.0082
		var knuckle := Vector3(x, y, -0.006)
		if i == 0 and trigger:
			# index finger runs straight along the frame, off the trigger.
			_limb_in(glove, knuckle, Vector3(x - 0.004, y + 0.012, -0.05), thick, _leather)
			_limb_in(glove, Vector3(x - 0.004, y + 0.012, -0.05), Vector3(x - 0.008, y + 0.016, -0.078), thick * 0.95, _leather)
			continue
		# three joints wrapped round the grip: near side, across the front,
		# tip on the far side.
		var a := Vector3(r * 0.75, y, -r - thick * 0.8)
		var b := Vector3(-r * 0.75, y - 0.002, -r - thick * 0.8)
		var c := Vector3(-r - thick * 0.7, y - 0.004, -0.004)
		_limb_in(glove, knuckle, a, thick, _leather)
		_limb_in(glove, a, b, thick * 0.97, _leather)
		_limb_in(glove, b, c, thick * 0.92, _leather)
	# thumb: from the heel of the palm, round the back of the grip.
	var t0 := Vector3(x - 0.004, 0.022, 0.045)
	var t1 := Vector3(r * 0.5, 0.042, r + 0.012)
	var t2 := Vector3(-r - 0.006, 0.046, 0.004)
	_limb_in(glove, t0, t1, 0.0108, _leather)
	_limb_in(glove, t1, t2, 0.0098, _leather)


# --- Pieces ---------------------------------------------------------------------

func _limb(parent: Node3D, a: Vector3, b: Vector3, radius_a: float, radius_b: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius_a
	mesh.top_radius = radius_b
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 12
	mesh.rings = 1
	_part(parent, mesh, material, Transform3D(_along(b - a), (a + b) * 0.5))


## a finger joint: a capsule from a to b under parent.
func _limb_in(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = a.distance_to(b) + radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 2
	_part(parent, mesh, material, Transform3D(_along(b - a), (a + b) * 0.5))


## an ellipsoid with radii radii under parent, axis-aligned.
func _blob(parent: Node3D, at: Vector3, radii: Vector3, material: Material) -> void:
	_part(parent, _sphere_mesh(1.0), material, Transform3D(Basis.from_scale(radii), at))


func _box(parent: Node3D, at: Vector3, size: Vector3, along: Vector3, facing: Vector3, material: Material) -> void:
	_part(parent, _box_mesh(size), material, Transform3D(_facing(along, facing), at))


func _ellipsoid(parent: Node3D, at: Vector3, size: Vector3, along: Vector3, facing: Vector3, material: Material) -> void:
	var basis := _facing(along, facing).scaled_local(size * 2.0)
	_part(parent, _sphere_mesh(0.5), material, Transform3D(basis, at))


func _part(parent: Node3D, mesh: Mesh, material: Material, xform: Transform3D) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.transform = xform
	# viewmodel is drawn close to the camera; its shadow would cover the world.
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)


static func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	return mesh


## a basis whose Y runs along dir.
static func _along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


## a basis whose Y runs along "along" and whose Z faces "facing".
static func _facing(along: Vector3, facing: Vector3) -> Basis:
	var y := along.normalized()
	var z := (facing - y * facing.dot(y)).normalized()
	return Basis(y.cross(z), y, z)


## node's transform in ancestor's space, whether or not either is in the tree yet.
static func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != ancestor:
		if at is Node3D:
			xform = (at as Node3D).transform * xform
		at = at.get_parent()
	return xform


func _make_materials() -> void:
	# scanned cloth/leather (poly haven, CC0), projected in the arm's own
	# space since primitive UVs stretch. sleeve cloth is pale so the team
	# colour tints it.
	_fabric = _scanned("rough_linen", SLEEVE_COLOURS[Team.Side.NONE], 9.0)
	_leather = _scanned("fabric_leather_02", Color(0.11, 0.11, 0.115), 14.0)
	_hard = _material(Color(0.11, 0.11, 0.12), 0.38)
	_nylon = _scanned("rough_linen", Color(0.13, 0.135, 0.14), 16.0)
	_accent = _material(UITheme.ACCENT, 0.5)
	_patch = _scanned("rough_linen", Color(0.22, 0.23, 0.2), 20.0)


static func _scanned(texture_id: String, tint: Color, tiles_per_metre: float) -> BaseMaterial3D:
	var base := "res://assets/materials/%s/%s_" % [texture_id, texture_id]
	var material := ORMMaterial3D.new()
	material.albedo_texture = load(base + "diff.jpg")
	material.albedo_color = tint
	material.normal_enabled = true
	material.normal_texture = load(base + "nor_gl.jpg")
	material.orm_texture = load(base + "arm.jpg")
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * tiles_per_metre
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


static func _material(colour: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	return material
