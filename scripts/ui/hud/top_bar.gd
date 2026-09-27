class_name HudTopBar
extends Control
## top-centre match bar: slanted team score tiles either side of the round
## clock, alive pips outside them, phase and round underneath. shapes are
## drawn here, numbers are labels on top. reads GameManager every frame.

const PHASE_TITLES := {
	GamePhase.Phase.LOBBY: "LOBBY",
	GamePhase.Phase.WARMUP: "WARMUP",
	GamePhase.Phase.BUY: "BUY PHASE",
	GamePhase.Phase.ROUND_ACTIVE: "",
	GamePhase.Phase.ROUND_END: "ROUND OVER",
	GamePhase.Phase.MATCH_END: "MATCH OVER",
}

const WIDTH := 640.0
const CX := WIDTH * 0.5
const TILE_H := 46.0
const SLOTS := 3

var _alpha_score: Label
var _bravo_score: Label
var _clock: Label
var _phase: Label
var _round: Label
var _alpha_role: Label
var _bravo_role: Label
var _counts := {Team.Side.ALPHA: [0, 0], Team.Side.BRAVO: [0, 0]}
var _urgent: bool = false

## set by Hud: the core is down, so the clock is its detonation timer.
var core_planted: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.pin(self, Vector2(0.5, 0.0), -CX, 10, CX, 110)

	_clock = _place(UITheme.heading("--", 36, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER), CX - 70, -2, 140, 50)
	_alpha_score = _place(UITheme.heading("0", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), CX - 166, 0, 80, TILE_H)
	_bravo_score = _place(UITheme.heading("0", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), CX + 86, 0, 80, TILE_H)
	_alpha_role = _place(UITheme.caption("", UITheme.ALPHA, HORIZONTAL_ALIGNMENT_CENTER), CX - 176, TILE_H + 3, 90, 16)
	_bravo_role = _place(UITheme.caption("", UITheme.BRAVO, HORIZONTAL_ALIGNMENT_CENTER), CX + 86, TILE_H + 3, 90, 16)
	_phase = _place(UITheme.caption("", UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), CX - 100, 52, 200, 16)
	_round = _place(UITheme.caption("", UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER), CX - 150, 70, 300, 16)


func _place(label: Label, x: float, y: float, w: float, h: float) -> Label:
	label.position = Vector2(x, y)
	label.size = Vector2(w, h)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
	return label


func _draw() -> void:
	# clock plate: a trapezoid, wide at the top
	var plate := PackedVector2Array([Vector2(CX - 84, 0), Vector2(CX + 84, 0),
		Vector2(CX + 70, 50), Vector2(CX - 70, 50)])
	draw_colored_polygon(plate, Color(0.02, 0.025, 0.03, 0.78))
	var edge := UITheme.DANGER if _urgent else UITheme.ACCENT
	draw_line(Vector2(CX - 70, 50), Vector2(CX + 70, 50), edge, 2.0)
	# score tiles, slanted away from the clock
	_tile(-1, UITheme.ALPHA)
	_tile(1, UITheme.BRAVO)
	_pips(-1, UITheme.ALPHA, _counts[Team.Side.ALPHA])
	_pips(1, UITheme.BRAVO, _counts[Team.Side.BRAVO])


func _tile(side: int, colour: Color) -> void:
	var inner := CX + side * 88.0
	var outer := CX + side * 166.0
	var pts := PackedVector2Array([Vector2(inner, 0), Vector2(outer, 0),
		Vector2(outer - side * 12.0, TILE_H), Vector2(inner - side * 12.0, TILE_H)])
	draw_colored_polygon(pts, Color(colour.darkened(0.25), 0.88))
	# glossy top half
	var top := PackedVector2Array([Vector2(inner, 0), Vector2(outer, 0),
		Vector2(outer - side * 6.0, TILE_H * 0.5), Vector2(inner - side * 6.0, TILE_H * 0.5)])
	draw_colored_polygon(top, Color(1, 1, 1, 0.08))


func _pips(side: int, colour: Color, counts: Array) -> void:
	var total: int = counts[0]
	var alive: int = counts[1]
	var start := CX + side * 182.0
	for i in maxi(total, SLOTS):
		if i >= total:
			break
		var x := start + side * i * 13.0
		var lit := i < alive
		var c := colour if lit else Color(colour, 0.18)
		var pts := PackedVector2Array([Vector2(x + 3, 8), Vector2(x + 10, 8), Vector2(x + 7, 38), Vector2(x, 38)])
		if side < 0:
			pts = PackedVector2Array([Vector2(x - 10, 8), Vector2(x - 3, 8), Vector2(x, 38), Vector2(x - 7, 38)])
		draw_colored_polygon(pts, c)


func update_view() -> void:
	var match_state := GameManager.match_state
	_alpha_score.text = str(match_state.get_score(Team.Side.ALPHA))
	_bravo_score.text = str(match_state.get_score(Team.Side.BRAVO))

	var phase := GameManager.current_phase
	var remaining := GameManager.current_state.get_time_remaining() if GameManager.current_state else 0.0
	var timed := phase in [GamePhase.Phase.WARMUP, GamePhase.Phase.BUY,
		GamePhase.Phase.ROUND_ACTIVE, GamePhase.Phase.ROUND_END]
	_clock.text = UITheme.clock(remaining) if timed else "--"
	_urgent = phase == GamePhase.Phase.ROUND_ACTIVE and (core_planted or remaining <= 10.0)
	_clock.add_theme_color_override(&"font_color", UITheme.DANGER if _urgent else UITheme.TEXT)
	_phase.text = "CORE PLANTED" if core_planted else PHASE_TITLES.get(phase, "")
	_phase.add_theme_color_override(&"font_color", UITheme.DANGER if core_planted else UITheme.ACCENT)
	var attacking := match_state.attacking_side(maxi(match_state.round_number, 1))
	_alpha_role.text = "ATTACK" if attacking == Team.Side.ALPHA else "DEFEND"
	_bravo_role.text = "ATTACK" if attacking == Team.Side.BRAVO else "DEFEND"
	_round.text = "ROUND %d  /  FIRST TO %d" % [maxi(match_state.round_number, 1), GameManager.match_rules.rounds_to_win]

	var counts := {Team.Side.ALPHA: [0, 0], Team.Side.BRAVO: [0, 0]}
	for player in NetworkManager.get_players():
		if not counts.has(player.state.team):
			continue
		counts[player.state.team][0] += 1
		if player.state.is_alive:
			counts[player.state.team][1] += 1
	_counts = counts
	queue_redraw()
