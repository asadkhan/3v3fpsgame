class_name HitMarker
extends Control
## the cross that flashes in the middle of the screen when a shot connects.
##
## drawn instead of built from Control children - it's just four lines, so
## _draw() is the whole widget.
##
## a child of the player, not the HUD, since it's a direct result of this
## player's own shot connecting. other players don't need one - their hits
## aren't news to you.

## how long the cross stays fully visible, in seconds. long enough to
## register at 60fps without lingering into the next shot.
@export var hold_time: float = 0.2

## how long the fade out takes after the hold
@export var fade_time: float = 0.1

## distance from screen centre to the start of each tick, and the tick length
@export var gap: float = 7.0
@export var length: float = 9.0

@export var normal_colour: Color = Color(1, 1, 1, 0.95)
@export var headshot_colour: Color = Color(1, 0.72, 0.25, 1.0)
@export var kill_colour: Color = Color(1, 0.25, 0.25, 1.0)

var _age: float = 0.0
var _showing: bool = false
var _colour: Color = normal_colour

## a headshot or kill gets a slightly longer, warmer cross so you can tell a
## body shot from a lethal one without reading a number.
var _tick_length: float = length


## flashes the cross. zone is a Damageable.HitZone; killed is whether the
## shot finished the target off.
func flash(zone: int, killed: bool) -> void:
	_age = 0.0
	_showing = true

	if killed:
		_colour = kill_colour
		_tick_length = length * 1.45
	elif zone == Damageable.HitZone.HEAD:
		_colour = headshot_colour
		_tick_length = length * 1.2
	else:
		_colour = normal_colour
		_tick_length = length

	queue_redraw()


## whether the cross is currently on screen
func is_showing() -> bool:
	return _showing


func _process(delta: float) -> void:
	if not _showing:
		return

	_age += delta
	if _age >= hold_time + fade_time:
		_showing = false
		queue_redraw()
		return
	queue_redraw()


func _draw() -> void:
	if not _showing:
		return

	var centre := size * 0.5
	var alpha := 1.0 if _age <= hold_time else 1.0 - (_age - hold_time) / fade_time
	var colour := _colour
	colour.a *= alpha

	# four ticks at the diagonals, pointing outwards. a gap in the middle
	# instead of a solid cross, so it doesn't hide the crosshair.
	# pops out and settles: bigger for the first few frames
	var pop := 1.0 + 0.45 * (1.0 - clampf(_age / 0.09, 0.0, 1.0))
	var width := 2.5 if _colour != normal_colour else 2.0
	for direction: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(1.0, 1.0)]:
		var d := direction.normalized()
		draw_line(centre + d * gap * pop, centre + d * (gap + _tick_length) * pop, Color(0, 0, 0, colour.a * 0.6), width + 2.0, true)
		draw_line(centre + d * gap * pop, centre + d * (gap + _tick_length) * pop, colour, width, true)
	# a kill also throws a ring outwards
	if _colour == kill_colour:
		var t := clampf(_age / (hold_time + fade_time), 0.0, 1.0)
		draw_arc(centre, lerpf(10.0, 34.0, t), 0.0, TAU, 40, Color(colour, colour.a * (1.0 - t)), 2.0, true)
