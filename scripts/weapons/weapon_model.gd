class_name WeaponModel
extends Node3D
## root of a weapon model whose source file has no usable materials (the
## CC0 FBX guns ship their PBR maps as loose PNGs). slaps `material` onto
## every mesh under it so the same scene works as viewmodel and third-person gun.

@export var material: Material
## parts of the source model to hide (e.g. the iron sight under an optic)
@export var hidden_parts: Array[NodePath] = []


func _ready() -> void:
	for path in hidden_parts:
		var part := get_node_or_null(path) as Node3D
		if part != null:
			part.visible = false
	if material == null:
		return
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		# attachments added in the scene bring their own materials
		if mesh.material_override == null:
			mesh.material_override = material


## the Marker3D called marker_name under root, or null. only markers count -
## some source models have their own meshes called "Sight" or "Muzzle".
static func marker(root: Node, marker_name: String) -> Node3D:
	if root == null:
		return null
	var found := root.find_children(marker_name, "Marker3D", true, false)
	return found[0] as Node3D if not found.is_empty() else null
