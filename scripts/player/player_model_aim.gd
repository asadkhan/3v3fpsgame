class_name PlayerModelAim
extends SkeletonModifier3D
## Bends a soldier's spine, chest and neck with where the player is aiming, on
## top of whatever the animation is doing. Runs before the arm IK, so the hands
## follow the gun wherever the torso turns.

## Aim pitch in radians, up positive.
var pitch: float = 0.0

const SHARES := {&"Spine": 0.25, &"Chest": 0.3, &"UpperChest": 0.15, &"Neck": 0.15, &"Head": 0.15}


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or is_zero_approx(pitch):
		return
	# The skeleton faces +Z, so its right is -X; looking up turns forward
	# towards +Y, which about -X is a positive rotation.
	for bone_name: StringName in SHARES:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var pose := skeleton.get_bone_global_pose(bone)
		var turn := Basis(Vector3.LEFT, pitch * SHARES[bone_name])
		skeleton.set_bone_global_pose(bone, Transform3D(turn * pose.basis, pose.origin))
