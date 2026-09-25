class_name HudAlivePips
extends Control
## A row of bars, one per player on a side: lit while alive, dimmed once dead.

var colour: Color = UITheme.TEXT
var right_to_left: bool = false

var _total: int = 0
var _alive: int = 0

const PIP_SIZE := Vector2(10, 26)
const PIP_GAP := 5.0
const SLOTS := 3


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SLOTS * (PIP_SIZE.x + PIP_GAP), 52)


func set_counts(total: int, alive: int) -> void:
	if total == _total and alive == _alive:
		return
	_total = total
	_alive = alive
	custom_minimum_size.x = maxi(SLOTS, total) * (PIP_SIZE.x + PIP_GAP)
	queue_redraw()


func _draw() -> void:
	var y := (size.y - PIP_SIZE.y) * 0.5
	for i in _total:
		var slot := i if not right_to_left else (maxi(SLOTS, _total) - 1 - i)
		var x := slot * (PIP_SIZE.x + PIP_GAP)
		var lit := i < _alive
		var fill := colour if lit else Color(colour.r, colour.g, colour.b, 0.18)
		draw_rect(Rect2(Vector2(x, y), PIP_SIZE), fill)
		draw_rect(Rect2(Vector2(x, y), PIP_SIZE), Color(0, 0, 0, 0.6), false, 1.0)
