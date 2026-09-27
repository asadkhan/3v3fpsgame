class_name WeaponModel
extends Node3D
## root of a weapon model whose source file has no usable materials (the
## CC0 FBX guns ship their PBR maps as loose PNGs). slaps `material` onto
## every mesh under it so the same scene works as viewmodel and third-person gun.

@export var material: Material


func _ready() -> void:
	if material == null:
		return
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
