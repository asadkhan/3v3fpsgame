class_name HudScopeOverlay
extends Control
## The view through a magnified scope: a round lens with a soft dark edge,
## black outside it, and a fine reticle - tech-cyan lines with an amber centre
## dot, in the SIGNALFALL palette. Shown only while the local player is fully
## aimed with a scoped weapon ([method Player.is_scoped]).

const LENS_FRACTION := 0.46   # lens radius as a fraction of screen height
const EDGE := Color(0.0, 0.0, 0.0, 1.0)

var _lens: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.0))
	gradient.set_color(1, EDGE)
	gradient.add_point(0.86, Color(0, 0, 0, 0.0))
	gradient.add_point(0.97, Color(0, 0, 0, 0.85))
	_lens = GradientTexture2D.new()
	_lens.gradient = gradient
	_lens.fill = GradientTexture2D.FILL_RADIAL
	_lens.fill_from = Vector2(0.5, 0.5)
	_lens.fill_to = Vector2(1.0, 0.5)
	_lens.width = 256
	_lens.height = 256
	resized.connect(queue_redraw)


func update_view(player: Player) -> void:
	var scoped := player != null and player.is_scoped()
	if scoped != visible:
		visible = scoped
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := size.y * LENS_FRACTION
	var lens_rect := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
	# Black outside the lens square, the soft round edge inside it.
	draw_rect(Rect2(0, 0, lens_rect.position.x, size.y), EDGE)
	draw_rect(Rect2(lens_rect.end.x, 0, size.x - lens_rect.end.x, size.y), EDGE)
	draw_rect(Rect2(lens_rect.position.x, 0, lens_rect.size.x, lens_rect.position.y), EDGE)
	draw_rect(Rect2(lens_rect.position.x, lens_rect.end.y, lens_rect.size.x, size.y - lens_rect.end.y), EDGE)
	draw_texture_rect(_lens, lens_rect, false)

	# Reticle: thin lines that stop short of the centre, thicker posts at the
	# edges, and an amber dot where the round goes.
	var line := Color(UITheme.TECH, 0.9)
	var gap := r * 0.06
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + dir * gap, c + dir * r * 0.9, line, 1.5, true)
		draw_line(c + dir * r * 0.6, c + dir * r * 0.9, line, 4.0, true)
	for i in range(1, 4):
		var y := c.y + gap * 1.8 * i
		draw_line(Vector2(c.x - 6.0 + i, y), Vector2(c.x + 6.0 - i, y), line, 1.5, true)
	draw_circle(c, 2.5, UITheme.ACCENT)
