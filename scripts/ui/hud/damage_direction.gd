class_name HudDamageDirection
extends Control
## red arcs around the crosshair pointing to where damage came from. each
## hit keeps its world position, so the arc swings as you turn toward (or
## away from) the attacker, and fades over LIFETIME.

const LIFETIME := 1.6
const RADIUS := 130.0
const ARC := 0.42

var _hits: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EventBus.local_hit_from.connect(_on_hit)


func _on_hit(from: Vector3) -> void:
	for hit in _hits:
		if (hit.at as Vector3).distance_to(from) < 1.5:
			hit.age = 0.0
			return
	_hits.append({"at": from, "age": 0.0})


func _process(delta: float) -> void:
	for hit in _hits:
		hit.age += delta
	_hits = _hits.filter(func(h: Dictionary) -> bool: return h.age < LIFETIME)
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _hits.is_empty():
		return
	var centre := size * 0.5
	var forward := -camera.global_basis.z
	forward.y = 0.0
	var right := camera.global_basis.x
	right.y = 0.0
	for hit in _hits:
		var to: Vector3 = (hit.at as Vector3) - camera.global_position
		to.y = 0.0
		if to.length_squared() < 0.01:
			continue
		# screen angle: 0 is straight ahead (up on screen), clockwise positive.
		var angle := atan2(to.normalized().dot(right.normalized()), to.normalized().dot(forward.normalized()))
		var fade := 1.0 - float(hit.age) / LIFETIME
		var colour := Color(0.95, 0.12, 0.08, 0.85 * fade * fade)
		var a := angle - PI * 0.5
		draw_arc(centre, RADIUS, a - ARC * 0.5, a + ARC * 0.5, 24, colour, 7.0, true)
		draw_arc(centre, RADIUS + 9.0, a - ARC * 0.2, a + ARC * 0.2, 12, Color(colour, colour.a * 0.6), 3.0, true)
