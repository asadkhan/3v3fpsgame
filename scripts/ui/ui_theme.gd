class_name UITheme
extends RefCounted
## the game's visual language for 2d ui, in one place: colours, fonts, text
## sizes, and the Theme every menu and the hud are built with.
##
## look: minimal tactical. condensed type, sharp corners, thin lines, dark
## glass behind text instead of big boxes. amber is the accent for anything
## to act on, cyan is tech (crosshair, shields), team blue/red only for sides.

# --- Palette ----------------------------------------------------------------

const ALPHA := Color(0.3, 0.72, 1.0)
const BRAVO := Color(1.0, 0.36, 0.3)

const GAME_TITLE := "SIGNALFALL"
const GAME_TAGLINE := "3V3 TACTICAL SHOOTER"

const TEXT := Color(0.96, 0.95, 0.92)
const TEXT_DIM := Color(0.62, 0.63, 0.66)
const ACCENT := Color(1.0, 0.7, 0.24)
const TECH := Color(0.36, 0.86, 1.0)
const DANGER := Color(1.0, 0.3, 0.28)
const GOOD := Color(0.47, 0.93, 0.58)
const SHIELD := TECH

const PANEL := Color(0.035, 0.04, 0.05, 0.82)
const PANEL_LIGHT := Color(1.0, 1.0, 1.0, 0.05)
const LINE := Color(1.0, 1.0, 1.0, 0.1)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
const SHADOW := Color(0.0, 0.0, 0.0, 0.7)

# --- Type scale -------------------------------------------------------------

const SIZE_TINY := 12
const SIZE_SMALL := 14
const SIZE_BODY := 18
const SIZE_LARGE := 28
const SIZE_HUGE := 56

static var _theme: Theme = null
static var _font: Font = null
static var _heading: Font = null


## body typeface: bahnschrift, falls back to common sans-serifs.
static func font() -> Font:
	if _font != null:
		return _font
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Bahnschrift", "DIN Alternate", "Segoe UI", "Roboto", "Arial"])
	system.font_weight = 500
	system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_font = system
	return _font


## heading typeface: bold condensed bahnschrift, for numbers and titles.
static func heading_font() -> Font:
	if _heading != null:
		return _heading
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Bahnschrift", "DIN Condensed", "Arial Narrow", "Roboto Condensed", "Arial"])
	system.font_weight = 700
	system.font_stretch = 75
	system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_heading = system
	return _heading


static func team_colour(side: int) -> Color:
	match side:
		Team.Side.ALPHA:
			return ALPHA
		Team.Side.BRAVO:
			return BRAVO
		_:
			return TEXT_DIM


## shared theme: dark glass panels with sharp corners, flat buttons that light
## an accent edge on hover, soft drop shadows on text.
static func build() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = SIZE_BODY
	theme.set_color(&"font_color", &"Label", TEXT)
	theme.set_color(&"font_shadow_color", &"Label", SHADOW)
	theme.set_constant(&"shadow_offset_x", &"Label", 0)
	theme.set_constant(&"shadow_offset_y", &"Label", 2)
	theme.set_constant(&"shadow_outline_size", &"Label", 3)

	theme.set_stylebox(&"panel", &"PanelContainer", glass(PANEL, 16))
	theme.set_stylebox(&"panel", &"Panel", glass(PANEL, 0))

	theme.set_stylebox(&"normal", &"Button", _button(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.14), 2))
	theme.set_stylebox(&"hover", &"Button", _button(Color(ACCENT, 0.16), ACCENT, 4))
	theme.set_stylebox(&"pressed", &"Button", _button(Color(ACCENT, 0.3), ACCENT, 4))
	theme.set_stylebox(&"disabled", &"Button", _button(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.05), 2))
	theme.set_stylebox(&"focus", &"Button", StyleBoxEmpty.new())
	theme.set_color(&"font_color", &"Button", TEXT)
	theme.set_color(&"font_hover_color", &"Button", Color(1, 0.93, 0.82))
	theme.set_color(&"font_pressed_color", &"Button", ACCENT)
	theme.set_color(&"font_disabled_color", &"Button", Color(TEXT_DIM, 0.5))
	theme.set_font(&"font", &"Button", heading_font())
	theme.set_font_size(&"font_size", &"Button", 20)

	var field := glass(Color(0, 0, 0, 0.45), 10, Color(1, 1, 1, 0.14))
	theme.set_stylebox(&"normal", &"LineEdit", field)
	theme.set_stylebox(&"focus", &"LineEdit", glass(Color(0, 0, 0, 0.55), 10, ACCENT))
	theme.set_color(&"font_color", &"LineEdit", TEXT)
	theme.set_color(&"font_placeholder_color", &"LineEdit", Color(TEXT_DIM, 0.6))
	theme.set_color(&"caret_color", &"LineEdit", ACCENT)
	theme.set_color(&"selection_color", &"LineEdit", Color(ACCENT, 0.35))

	# sliders: thin track, accent fill, small square grabber
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var filled := StyleBoxFlat.new()
	filled.bg_color = ACCENT
	filled.content_margin_top = 2
	filled.content_margin_bottom = 2
	theme.set_stylebox(&"slider", &"HSlider", track)
	theme.set_stylebox(&"grabber_area", &"HSlider", filled)
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", filled)
	theme.set_icon(&"grabber", &"HSlider", _square(12, TEXT))
	theme.set_icon(&"grabber_highlight", &"HSlider", _square(12, ACCENT))

	theme.set_stylebox(&"background", &"ProgressBar", _flat(Color(1, 1, 1, 0.1)))
	theme.set_stylebox(&"fill", &"ProgressBar", _flat(ACCENT))

	_theme = theme
	return theme


## dark glass panel, sharp corners, optional thin border.
static func glass(colour: Color, padding: int, border: Color = LINE) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding * 0.7
	box.content_margin_bottom = padding * 0.7
	if border.a > 0.0:
		box.set_border_width_all(1)
		box.border_color = border
	return box


## kept for older callers: a rounded box.
static func _box(colour: Color, radius: int, padding: int, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := glass(colour, padding, border)
	box.set_corner_radius_all(radius)
	return box


## flat button: faint fill, accent bar on the left edge.
static func _button(fill: Color, edge: Color, edge_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_width_left = edge_width
	box.border_color = edge
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


static func _flat(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	return box


static func _square(size: int, colour: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(colour)
	return ImageTexture.create_from_image(img)


## a label in the house style: soft shadow instead of a hard outline.
static func label(text: String, size: int = SIZE_BODY, colour: Color = TEXT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", colour)
	l.add_theme_color_override(&"font_shadow_color", SHADOW)
	l.add_theme_constant_override(&"shadow_offset_x", 0)
	l.add_theme_constant_override(&"shadow_offset_y", 2 if size < 30 else 3)
	l.add_theme_constant_override(&"shadow_outline_size", 3 if size < 30 else 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## a label in the bold condensed heading face.
static func heading(text: String, size: int = SIZE_LARGE, colour: Color = TEXT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, size, colour, align)
	l.add_theme_font_override(&"font", heading_font())
	return l


## small uppercase caption with letter spacing, e.g. section titles.
static func caption(text: String, colour: Color = TEXT_DIM, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text.to_upper(), SIZE_TINY + 1, colour, align)
	if _spaced == null:
		_spaced = FontVariation.new()
		_spaced.base_font = heading_font()
		_spaced.spacing_glyph = 2
	l.add_theme_font_override(&"font", _spaced)
	return l


static var _spaced: FontVariation = null


## a thin accent line, e.g. under a title.
static func rule(colour: Color = ACCENT, width: float = 48.0, height: float = 2.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = colour
	r.custom_minimum_size = Vector2(width, height)
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## a keycap: the key in a small bordered box, e.g. [G].
static func keycap(key: String, colour: Color = TEXT) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := glass(Color(0, 0, 0, 0.45), 6, Color(colour, 0.55))
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	cap.add_theme_stylebox_override(&"panel", box)
	var l := heading(key, SIZE_SMALL, colour, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(12, 0)
	cap.add_child(l)
	return cap


## full-screen blurred, darkened copy of whatever is behind it - the backdrop
## for menus opened over the game.
static func blur_backdrop(darkness: float = 0.55) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float darkness = 0.55;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 3.0).rgb;
	c = mix(c, vec3(dot(c, vec3(0.3, 0.59, 0.11))), 0.35);
	COLOR = vec4(c * (1.0 - darkness), 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"darkness", darkness)
	rect.material = material
	return rect


## soft dark fade from a screen corner, so hud text reads over bright sky
## without a box around it. corner: (0,1) bottom-left, (1,1) bottom-right...
static func corner_shade(corner: Vector2, size: Vector2, strength: float = 0.55) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, strength))
	gradient.set_color(1, Color(0, 0, 0, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = corner
	texture.fill_to = Vector2(1.0 - corner.x, corner.y) if corner.x != 0.5 else Vector2(1.0, corner.y)
	texture.width = 256
	texture.height = 128
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pin(rect, corner, -size.x * corner.x, -size.y * corner.y, size.x * (1.0 - corner.x), size.y * (1.0 - corner.y))
	return rect


## pins control to a point of its parent (anchor, 0..1 on each axis) with
## the given offsets from that point.
static func pin(control: Control, anchor: Vector2, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom


## "0:42" from seconds.
static func clock(seconds: float) -> String:
	var whole := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [whole / 60, whole % 60]
