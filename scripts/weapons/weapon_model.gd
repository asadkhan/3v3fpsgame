class_name WeaponModel
extends Node3D
## Root of a weapon model scene whose source file carries no usable materials
## (the CC0 FBX guns ship their PBR maps as loose PNGs). Applies [member
## material] to every mesh under it, so the same scene works as the first-
## person viewmodel and as the third-person gun.

@export var material: Material


func _ready() -> void:
	if material == null:
		return
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
