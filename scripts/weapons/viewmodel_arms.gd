class_name ViewmodelArms
extends Node3D
## The first-person arms: tactical sleeves, elbow pads, wrist straps and hard-
## knuckle gloves, built in code from primitives so they need no art assets and
## fit the flat-shaded weapon models.
##
## [Weapon] adds one under its viewmodel whenever it swaps models. The model
## scene says where the hands go with [code]HandR[/code] / [code]HandL[/code]
## markers (children of its Model node), each carrying two pieces of metadata:
##   [code]grip[/code]   - how the hand holds there: [code]"pistol"[/code] (a
##                         raked pistol grip), [code]"vertical"[/code] (a
##                         foregrip), [code]"rail"[/code] (under a handguard)
##   [code]radius[/code] - how thick the thing being held is, in metres
##   [code]hand_scale[/code] - optional, for a small gun that needs smaller hands
## A model without markers simply has no arms. The shoulders sit at fixed
## points below and behind the camera, and each arm reaches its hand with
## two-bone IK, so a new gun only needs its two markers.
##
## The hands and forearms are a scanned, skinned arm model
## ([constant ARM_MODEL], fingerless tactical gloves): placed on each marker,
## mirrored for the left hand, its wrist bent so the forearm runs to the IK
## elbow and its fingers curled round the grip. The sleeves, straps and upper
## arms are still built here from primitives, in the team colour. Without the
## model file the whole hand falls back to primitives too.
##
## Purely cosmetic and local: the whole rig moves rigidly with the viewmodel
## (sway, aim, kick), and the sleeves take the owner's team colour.

const ARM_MODEL := "res://assets/characters/fp_arms/firstPersonHandsWithGloves.FBX"
const ARM_TEXTURES := "res://assets/characters/fp_arms/ArmWithGlove%s.png"

## The arm model's axes in the hand frame (see [method _grip_basis]): its
## fingers (-Z) point forward, the back of its hand (+Y) faces +X, and its
## knuckles run index to pinky (+X) down the grip (-Y).
const MODEL_TO_HAND := Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))
## The centre of the loop the curled fingers make, in model space: a held
## object's axis goes through it. Measured from the curled pose.
const MODEL_GRIP_CENTRE := Vector3(0.006, -0.013, -0.055)
## Grip radius the curl angles below are tuned for; thicker grips open the hand.
const CURL_RADIUS := 0.019
## Finger curl in degrees per joint (base, middle, tip): wrapped round a grip,
## and the straighter trigger finger.
const CURL_GRIP := [62.0, 78.0, 48.0]
const CURL_TRIGGER := [18.0, 22.0, 12.0]
const CURL_THUMB := [45.0, 40.0, 30.0]
## The thumb's joints bend about a different local axis from the fingers'.
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

## Shoulders, in the weapon's space: the camera is at the origin looking down -Z.
const SHOULDER_R := Vector3(0.17, -0.3, 0.06)
const SHOULDER_L := Vector3(-0.19, -0.32, 0.04)
const UPPER_LENGTH := 0.24
const FORE_LENGTH := 0.23

## Sleeve fabric per side: blue-grey for Alpha, tan for Bravo, olive otherwise.
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


## Builds both arms. [param viewmodel] is the node this rig lives under (its
## transform relative to the weapon places the shoulders); [param model] is the
## instanced weapon model holding the hand markers; [param body] is the player,
## read for the team colour.
func build(viewmodel: Node3D, model: Node3D, body: Node) -> void:
	_body = body
	_make_materials()
	var to_viewmodel := viewmodel.transform.affine_inverse()
	for side in [1, -1]:
		var marker := model.find_child("HandR" if side == 1 else "HandL", true, false) as Node3D
		if marker == null:
			continue
		var at := _relative(marker, viewmodel).origin
		var grip := String(marker.get_meta(&"grip", "pistol"))
		var radius := float(marker.get_meta(&"radius", 0.02))
		var hand_scale := float(marker.get_meta(&"hand_scale", 1.0))
		var shoulder := to_viewmodel * (SHOULDER_R if side == 1 else SHOULDER_L)
		_build_arm(side, shoulder, Transform3D(_grip_basis(grip), at), radius, hand_scale,
			grip == "pistol" and side == 1)
	_refresh_team()


func _process(_delta: float) -> void:
	_refresh_team()


func _refresh_team() -> void:
	var state: Variant = _body.get("state") if _body != null else null
	var team: int = state.team if state != null else Team.Side.NONE
	if team != _team:
		_team = team
		_fabric.albedo_color = SLEEVE_COLOURS.get(team, SLEEVE_COLOURS[Team.Side.NONE])


# --- Layout ---------------------------------------------------------------------

## The hand's frame for each kind of hold. In that frame the held object runs
## along +Y, the back of the hand faces +X and the wrist is towards +Z. The left
## hand is the same geometry mirrored, so its back faces -X.
static func _grip_basis(grip: String) -> Basis:
	match grip:
		"rail":
			# Palm up under the handguard, fingers over the right side.
			return Basis(Vector3.UP, Vector3.FORWARD, Vector3.LEFT)
		"vertical":
			return Basis(Vector3.RIGHT, Vector3(0, 1, -0.12).normalized(),
				Vector3(0, 0.12, 1).normalized())
		_:
			# A pistol grip rakes back towards the bottom.
			var up := Vector3(0, 0.95, -0.3).normalized()
			return Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up))


func _build_arm(side: int, shoulder: Vector3, hand: Transform3D, r: float, hand_scale: float,
		trigger: bool) -> void:
	var hand_node := Node3D.new()
	hand_node.transform = hand
	add_child(hand_node)
	var glove := Node3D.new()
	glove.scale = Vector3(side, 1, 1) * hand_scale
	hand_node.add_child(glove)
	var scanned := _build_scanned_hand(glove, r / hand_scale, trigger)
	var fore_length := FORE_LENGTH
	var wrist: Vector3
	if scanned.is_empty():
		_build_glove(glove, r / hand_scale, trigger)
		wrist = hand * (glove.transform * Vector3(r + 0.008, -0.018, 0.075))
	else:
		wrist = hand * (glove.transform * (scanned.wrist as Vector3))
		fore_length = (scanned.fore_length as float) * hand_scale

	# Two-bone IK: the elbow sits where both segments meet, bent outwards and
	# down.
	var reach := wrist - shoulder
	var d := clampf(reach.length(), 0.05, UPPER_LENGTH + fore_length - 0.002)
	var dir := reach.normalized()
	var along := (UPPER_LENGTH * UPPER_LENGTH - fore_length * fore_length + d * d) / (2.0 * d)
	var out := sqrt(maxf(UPPER_LENGTH * UPPER_LENGTH - along * along, 0.0))
	var pole := Vector3(0.7 * side, -1.0, 0.25)
	pole = (pole - dir * pole.dot(dir)).normalized()
	var elbow := shoulder + dir * along + pole * out
	var fore_dir := (wrist - elbow).normalized()
	if not scanned.is_empty():
		var rig_to_skeleton := (hand * glove.transform * (scanned.model as Node3D).transform).affine_inverse()
		_bend_forearm(scanned, rig_to_skeleton * elbow)

	# Upper arm: sleeve, a strap with a pouch, and the elbow pad.
	var upper_dir := (elbow - shoulder).normalized()
	_limb(shoulder, elbow, 0.046, 0.038, _fabric)
	_ellipsoid(elbow, Vector3(0.038, 0.038, 0.038), fore_dir, pole, _fabric)
	var strap_at := shoulder.lerp(elbow, 0.6)
	_limb(strap_at - upper_dir * 0.01, strap_at + upper_dir * 0.01, 0.044, 0.043, _nylon)
	_box(strap_at + pole * 0.04, Vector3(0.038, 0.055, 0.022), upper_dir, pole, _nylon)
	_ellipsoid(elbow + pole * 0.024, Vector3(0.036, 0.046, 0.022), fore_dir, pole, _hard)

	# Forearm: sleeve bunched at the cuff, a strap, the wrist band with its tab.
	# Over the scanned forearm the sleeve has to be wider and stop short of
	# the glove.
	var cuff := wrist - fore_dir * (0.03 if scanned.is_empty() else 0.05)
	var sleeve := 1.0 if scanned.is_empty() else 1.5
	_limb(elbow, cuff, 0.037 * sleeve, 0.031 * sleeve, _fabric)
	_limb(cuff - fore_dir * 0.03, cuff, 0.035 * sleeve, 0.034 * sleeve, _fabric)
	# Folds where the sleeve bunches above the cuff, each a little askew.
	var side_dir := fore_dir.cross(pole).normalized()
	for i in 3:
		var at := cuff - fore_dir * (0.045 + i * 0.03)
		var tilt := (pole if i % 2 == 0 else side_dir) * 0.004
		var fold := (0.0345 + i * 0.001) * sleeve
		_limb(at - fore_dir * 0.006 - tilt, at + fore_dir * 0.006 + tilt, fold, fold, _fabric)
	# A velcro patch on the outside of the forearm.
	_box(elbow.lerp(cuff, 0.25) + pole * 0.033 * sleeve, Vector3(0.03, 0.05, 0.006), fore_dir, pole, _patch)
	var band := elbow.lerp(cuff, 0.5)
	_limb(band - fore_dir * 0.008, band + fore_dir * 0.008, 0.036 * sleeve, 0.0355 * sleeve, _nylon)
	_box(band + pole * 0.036 * sleeve, Vector3(0.018, 0.024, 0.01), fore_dir, pole, _hard)
	if scanned.is_empty():
		_limb(cuff - fore_dir * 0.004, wrist + fore_dir * 0.004, 0.03, 0.029, _nylon)
		_box(cuff.lerp(wrist, 0.5) + pole * 0.03, Vector3(0.022, 0.016, 0.005), fore_dir, pole, _accent)


# --- Scanned hand -----------------------------------------------------------------

## Puts the skinned arm model under [param glove] (the hand frame, mirrored for
## the left hand) with an object of radius [param r] in its grip, and curls its
## fingers round it. Returns the model, its skeleton, the wrist in glove space
## and the forearm length - or nothing if the model is missing.
func _build_scanned_hand(glove: Node3D, r: float, trigger: bool) -> Dictionary:
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

	var open := clampf(CURL_RADIUS / maxf(r, 0.005), 0.6, 1.15)
	for i in FINGERS.size():
		_curl(skeleton, FINGERS[i], CURL_TRIGGER if i == 0 and trigger else CURL_GRIP, open)
	_curl(skeleton, THUMB, CURL_THUMB, open, THUMB_AXIS)
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


## Swings the forearm about the wrist so it runs to [param elbow] (skeleton
## space) while the hand stays on the grip - the wrist bends, as a real one
## does.
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


## The glove, in the hand frame (see [method _grip_basis]) around an object of
## radius [param r] running along Y.
func _build_glove(glove: Node3D, r: float, trigger: bool) -> void:
	var x := r + 0.012
	# Palm and back of the hand, and the cuff that meets the wrist band.
	_blob(glove, Vector3(x, -0.002, 0.028), Vector3(0.015, 0.043, 0.042), _leather)
	_blob(glove, Vector3(x - 0.002, -0.014, 0.066), Vector3(0.017, 0.03, 0.022), _leather)
	# Hard knuckle guard across the back of the hand.
	_blob(glove, Vector3(x + 0.012, 0.0, 0.006), Vector3(0.008, 0.038, 0.017), _hard)
	for i in 4:
		var y := 0.03 - i * 0.02
		_part(glove, _sphere_mesh(0.0078), _hard, Transform3D(Basis(), Vector3(x + 0.011, y, -0.007)))
		var thick := 0.0095 if i < 3 else 0.0082
		var knuckle := Vector3(x, y, -0.006)
		if i == 0 and trigger:
			# Index finger along the frame, off the trigger.
			_limb_in(glove, knuckle, Vector3(x - 0.004, y + 0.012, -0.05), thick, _leather)
			_limb_in(glove, Vector3(x - 0.004, y + 0.012, -0.05), Vector3(x - 0.008, y + 0.016, -0.078), thick * 0.95, _leather)
			continue
		# Three joints wrapped round the grip: along the near side, across the
		# front, and the tip on the far side.
		var a := Vector3(r * 0.75, y, -r - thick * 0.8)
		var b := Vector3(-r * 0.75, y - 0.002, -r - thick * 0.8)
		var c := Vector3(-r - thick * 0.7, y - 0.004, -0.004)
		_limb_in(glove, knuckle, a, thick, _leather)
		_limb_in(glove, a, b, thick * 0.97, _leather)
		_limb_in(glove, b, c, thick * 0.92, _leather)
	# Thumb: from the heel of the palm, round the back of the grip.
	var t0 := Vector3(x - 0.004, 0.022, 0.045)
	var t1 := Vector3(r * 0.5, 0.042, r + 0.012)
	var t2 := Vector3(-r - 0.006, 0.046, 0.004)
	_limb_in(glove, t0, t1, 0.0108, _leather)
	_limb_in(glove, t1, t2, 0.0098, _leather)


# --- Pieces ---------------------------------------------------------------------

func _limb(a: Vector3, b: Vector3, radius_a: float, radius_b: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius_a
	mesh.top_radius = radius_b
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 12
	mesh.rings = 1
	_part(self, mesh, material, Transform3D(_along(b - a), (a + b) * 0.5))


## A finger joint: a capsule from [param a] to [param b] under [param parent].
func _limb_in(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = a.distance_to(b) + radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 2
	_part(parent, mesh, material, Transform3D(_along(b - a), (a + b) * 0.5))


## An ellipsoid with radii [param radii] under [param parent], axis-aligned.
func _blob(parent: Node3D, at: Vector3, radii: Vector3, material: Material) -> void:
	_part(parent, _sphere_mesh(1.0), material, Transform3D(Basis.from_scale(radii), at))


func _box(at: Vector3, size: Vector3, along: Vector3, facing: Vector3, material: Material) -> void:
	_part(self, _box_mesh(size), material, Transform3D(_facing(along, facing), at))


func _ellipsoid(at: Vector3, size: Vector3, along: Vector3, facing: Vector3, material: Material) -> void:
	var basis := _facing(along, facing).scaled_local(size * 2.0)
	_part(self, _sphere_mesh(0.5), material, Transform3D(basis, at))


func _part(parent: Node3D, mesh: Mesh, material: Material, xform: Transform3D) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.transform = xform
	# A viewmodel is drawn close to the camera; its shadow would cover the world.
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


## A basis whose Y runs along [param dir].
static func _along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


## A basis whose Y runs along [param along] and whose Z faces [param facing].
static func _facing(along: Vector3, facing: Vector3) -> Basis:
	var y := along.normalized()
	var z := (facing - y * facing.dot(y)).normalized()
	return Basis(y.cross(z), y, z)


## [param node]'s transform in [param ancestor]'s space, whether or not either
## is in the tree yet.
static func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != ancestor:
		if at is Node3D:
			xform = (at as Node3D).transform * xform
		at = at.get_parent()
	return xform


func _make_materials() -> void:
	# Scanned cloth and leather (Poly Haven, CC0), projected in the arm's own
	# space since the primitives' UVs stretch. The sleeve cloth is pale, so the
	# team colour tints it.
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
