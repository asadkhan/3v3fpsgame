class_name UITheme
extends RefCounted
## The game's visual language for 2D UI, in one place: colours, text sizes and
## the [Theme] every menu and the HUD are built with.
##
## [b]The SIGNALFALL identity.[/b] A near-future signal war at a sun-bleached
## desert relay. Two working colours carry the whole game: [b]amber[/b] is
## "signal" - the core, tracers, highlights, anything to act on - and
## [b]cyan[/b] is "tech" - the crosshair, shields, the Echo Field, barriers.
## Team blue and red are only ever used for sides. The world is warm sandstone
## so both read clearly against it.
##
## Built in code rather than as a hand-edited [code].tres[/code] so the whole
## palette is readable in one file and a colour change is one constant.
## [method build] is cached, so every screen shares the same [Theme] object.

# --- Palette ----------------------------------------------------------------

## Team colours. The same hues tint the player capsules in the world
## ([constant Player.TEAM_COLOURS]), so a colour means one side everywhere.
const ALPHA := Color(0.3, 0.72, 1.0)
const BRAVO := Color(1.0, 0.36, 0.3)

## The game's name, in one place.
const GAME_TITLE := "SIGNALFALL"
const GAME_TAGLINE := "3v3 TACTICAL SHOOTER"

const TEXT := Color(0.95, 0.94, 0.9)
const TEXT_DIM := Color(0.66, 0.66, 0.68)
## Signal amber - the accent for everything important.
const ACCENT := Color(1.0, 0.72, 0.28)
## Tech cyan - crosshair, shields, Echo Field, barriers.
const TECH := Color(0.36, 0.86, 1.0)
const DANGER := Color(1.0, 0.3, 0.28)
const GOOD := Color(0.45, 0.95, 0.6)
const SHIELD := TECH

const PANEL := Color(0.06, 0.07, 0.09, 0.78)
const PANEL_LIGHT := Color(0.12, 0.13, 0.16, 0.9)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.85)

# --- Type scale -------------------------------------------------------------

const SIZE_SMALL := 14
const SIZE_BODY := 18
const SIZE_LARGE := 28
const SIZE_HUGE := 56

static var _theme: Theme = null
static var _font: Font = null


## The house typeface: Bahnschrift - a condensed, engineered sans that reads
## instantly at small sizes and suits the tactical tone - falling back to
## common system sans-serifs where it is not installed.
static func font() -> Font:
	if _font != null:
		return _font
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Bahnschrift", "DIN Alternate", "Segoe UI", "Roboto", "Arial"])
	system.font_weight = 500
	system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_font = system
	return _font


static func team_colour(side: int) -> Color:
	match side:
		Team.Side.ALPHA:
			return ALPHA
		Team.Side.BRAVO:
			return BRAVO
		_:
			return TEXT_DIM


## The shared theme: dark translucent panels, flat buttons with an accent edge,
## outlined text that stays readable over any part of the 3D world.
static func build() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = SIZE_BODY

	theme.set_color(&"font_color", &"Label", TEXT)
	theme.set_color(&"font_outline_color", &"Label", OUTLINE)
	theme.set_constant(&"outline_size", &"Label", 4)

	theme.set_stylebox(&"panel", &"PanelContainer", _box(PANEL, 4, 12))
	theme.set_stylebox(&"panel", &"Panel", _box(PANEL, 4, 0))

	var normal := _box(PANEL_LIGHT, 3, 10, Color(1, 1, 1, 0.12))
	var hover := _box(Color(0.2, 0.21, 0.25, 0.95), 3, 10, ACCENT)
	var pressed := _box(Color(0.3, 0.26, 0.12, 0.95), 3, 10, ACCENT)
	var disabled := _box(Color(0.1, 0.1, 0.12, 0.6), 3, 10, Color(1, 1, 1, 0.05))
	theme.set_stylebox(&"normal", &"Button", normal)
	theme.set_stylebox(&"hover", &"Button", hover)
	theme.set_stylebox(&"pressed", &"Button", pressed)
	theme.set_stylebox(&"disabled", &"Button", disabled)
	theme.set_stylebox(&"focus", &"Button", _box(Color(0, 0, 0, 0), 3, 10, ACCENT))
	theme.set_color(&"font_color", &"Button", TEXT)
	theme.set_color(&"font_hover_color", &"Button", ACCENT)
	theme.set_color(&"font_pressed_color", &"Button", ACCENT)
	theme.set_color(&"font_disabled_color", &"Button", TEXT_DIM)

	var field := _box(Color(0.03, 0.03, 0.05, 0.9), 3, 8, Color(1, 1, 1, 0.18))
	theme.set_stylebox(&"normal", &"LineEdit", field)
	theme.set_stylebox(&"focus", &"LineEdit", _box(Color(0.03, 0.03, 0.05, 0.9), 3, 8, ACCENT))
	theme.set_color(&"font_color", &"LineEdit", TEXT)

	_theme = theme
	return theme


static func _box(colour: Color, radius: int, padding: int, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding * 0.6
	box.content_margin_bottom = padding * 0.6
	if border.a > 0.0:
		box.set_border_width_all(1)
		box.border_color = border
	return box


## A label in the house style.
static func label(text: String, size: int = SIZE_BODY, colour: Color = TEXT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", colour)
	l.add_theme_constant_override(&"outline_size", maxi(3, size / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Pins [param control] to a point of its parent ([param anchor], 0..1 on each
## axis) with the given offsets from that point. Screen-size independent, which
## setting `position` after an anchor preset is not.
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
