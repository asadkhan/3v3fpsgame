class_name HudDamageVignette
extends TextureRect
## A red edge-of-screen flash when the local player takes damage, stronger for
## bigger hits, plus a faint persistent tint while health is low.

var _flash: float = 0.0
var _low_health: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.8, 0.05, 0.05, 0.0))
	gradient.set_color(1, Color(0.8, 0.05, 0.05, 0.85))
	gradient.set_offset(0, 0.45)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 1.0)
	texture.width = 256
	texture.height = 256
	self.texture = texture
	modulate.a = 0.0


func flash(amount: float) -> void:
	_flash = clampf(_flash + 0.25 + amount / 60.0, 0.0, 1.0)


func update_view(player: Player, delta: float) -> void:
	_flash = maxf(_flash - delta * 2.2, 0.0)
	_low_health = 0.0
	if player != null and player.state.is_alive and player.state.health <= 30:
		_low_health = 0.25 + 0.1 * sin(Time.get_ticks_msec() / 250.0)
	modulate.a = maxf(_flash, _low_health)
