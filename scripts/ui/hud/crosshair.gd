class_name HudCrosshair
extends Control
## A static crosshair: a centre dot and four short lines, outlined so it reads
## on any background. The hit marker ([HitMarker]) draws on top of it.

const GAP := 5.0
const LENGTH := 7.0
const THICKNESS := 2.0
const COLOUR := Color(0.55, 1.0, 0.85, 0.95)
const OUTLINE := Color(0, 0, 0, 0.75)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


## 0..1 aim amount from the local player; the lines close in as it rises, so
## the crosshair shows the tighter spread aiming buys.
var aim_amount: float = 0.0:
	set(value):
		if not is_equal_approx(value, aim_amount):
			aim_amount = value
			queue_redraw()


func _draw() -> void:
	var c := (size * 0.5).floor()
	var gap := lerpf(GAP, GAP * 0.45, aim_amount)
	var length := lerpf(LENGTH, LENGTH * 0.7, aim_amount)
	var arms := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	for pass_index in 2:
		var outline := pass_index == 0
		var colour := OUTLINE if outline else COLOUR
		var grow := 1.0 if outline else 0.0
		for dir: Vector2 in arms:
			var a := c + dir * (gap - grow)
			var b := c + dir * (gap + length + grow)
			draw_line(a, b, colour, THICKNESS + grow * 2.0)
		draw_rect(Rect2(c - Vector2.ONE * (1.0 + grow), Vector2.ONE * (2.0 + grow * 2.0)), colour)
