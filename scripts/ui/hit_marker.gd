class_name HitMarker
extends Control
## The cross that flashes in the middle of the screen when a shot connects.
##
## [b]Drawn rather than composed out of labels.[/b] Four [Control] children with
## their own anchors would work, but every one of them would be something to
## keep positioned and to keep in sync, for a shape that is four lines. [method
## _draw] is the whole widget.
##
## [b]It is a child of the player, not of the HUD.[/b] It is a direct
## consequence of this player's own shot connecting, so it belongs to the player
## that fired. When Chapter 4 adds five more players, the other five need no
## hit marker at all - their hits are not news to you. Chapter 8 replaces it
## with the real HUD; nothing else has to know it exists.

## How long the cross stays fully visible, in seconds. Long enough to register
## at 60 fps without lingering into the next shot.
@export var hold_time: float = 0.16

## How long the fade out takes after the hold.
@export var fade_time: float = 0.1

## Distance from the centre of the screen to the start of each tick, and the
## length of the tick.
@export var gap: float = 7.0
@export var length: float = 9.0

@export var normal_colour: Color = Color(1, 1, 1, 0.95)
@export var headshot_colour: Color = Color(1, 0.72, 0.25, 1.0)
@export var kill_colour: Color = Color(1, 0.25, 0.25, 1.0)

var _age: float = 0.0
var _showing: bool = false
var _colour: Color = normal_colour

## Ticks drawn per hit. A headshot or a kill gets a slightly longer, warmer
## cross so the player can tell a body shot from a lethal one without reading a
## number - which is the entire reason a hit marker exists.
var _tick_length: float = length


## Flashes the cross. [param zone] is a [enum Damageable.HitZone]; [param
## killed] is whether the shot finished the target off.
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


## Whether the cross is currently on screen. The test harness asserts on this
## rather than on pixels.
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

	# Four ticks at the diagonals, pointing outwards. Drawn as a gap in the
	# middle rather than a continuous cross, because a solid cross sitting on top
	# of the crosshair hides the thing the player is aiming with.
	var unit := Vector2.ONE * 0.70710678  # 45 degrees
	for direction in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(1.0, 1.0)]:
		draw_line(centre + unit * gap, centre + unit * (gap + _tick_length), colour, 2.0, true)
