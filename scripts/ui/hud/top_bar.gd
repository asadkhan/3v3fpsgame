class_name HudTopBar
extends Control
## Top-centre match bar: ALPHA score and players alive, the round clock and
## phase, BRAVO's players alive and score. Read from [GameManager] and the
## player bodies every frame - cheap, and it cannot drift out of step.

const PHASE_TITLES := {
	GamePhase.Phase.LOBBY: "LOBBY",
	GamePhase.Phase.WARMUP: "WARMUP",
	GamePhase.Phase.BUY: "BUY PHASE",
	GamePhase.Phase.ROUND_ACTIVE: "",
	GamePhase.Phase.ROUND_END: "ROUND OVER",
	GamePhase.Phase.MATCH_END: "MATCH OVER",
}

var _alpha_score: Label
var _bravo_score: Label
var _alpha_pips: HudAlivePips
var _bravo_pips: HudAlivePips
var _clock: Label
var _phase: Label
var _round: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.pin(self, Vector2(0.5, 0.0), -300, 10, 300, 100)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_alpha_score = _score_box(row, UITheme.ALPHA)
	_alpha_pips = HudAlivePips.new()
	_alpha_pips.colour = UITheme.ALPHA
	row.add_child(_alpha_pips)

	var centre := VBoxContainer.new()
	centre.custom_minimum_size = Vector2(130, 0)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_theme_constant_override(&"separation", -4)
	row.add_child(centre)
	_clock = UITheme.label("--", UITheme.SIZE_LARGE + 6, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_phase = UITheme.label("", UITheme.SIZE_SMALL, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_round = UITheme.label("", UITheme.SIZE_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	centre.add_child(_clock)
	centre.add_child(_phase)
	centre.add_child(_round)

	_bravo_pips = HudAlivePips.new()
	_bravo_pips.colour = UITheme.BRAVO
	_bravo_pips.right_to_left = true
	row.add_child(_bravo_pips)
	_bravo_score = _score_box(row, UITheme.BRAVO)


func _score_box(parent: Control, colour: Color) -> Label:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(64, 52)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var label := UITheme.label("0", UITheme.SIZE_LARGE + 4, colour, HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return label


func update_view() -> void:
	var match_state := GameManager.match_state
	_alpha_score.text = str(match_state.get_score(Team.Side.ALPHA))
	_bravo_score.text = str(match_state.get_score(Team.Side.BRAVO))

	var phase := GameManager.current_phase
	var remaining := GameManager.current_state.get_time_remaining() if GameManager.current_state else 0.0
	var timed := phase in [GamePhase.Phase.WARMUP, GamePhase.Phase.BUY,
		GamePhase.Phase.ROUND_ACTIVE, GamePhase.Phase.ROUND_END]
	_clock.text = UITheme.clock(remaining) if timed else "--"
	_clock.add_theme_color_override(&"font_color",
		UITheme.DANGER if phase == GamePhase.Phase.ROUND_ACTIVE and remaining <= 10.0 else UITheme.TEXT)
	_phase.text = PHASE_TITLES.get(phase, "")
	_round.text = "ROUND %d  -  FIRST TO %d" % [maxi(match_state.round_number, 1), GameManager.match_rules.rounds_to_win]

	var counts := {Team.Side.ALPHA: [0, 0], Team.Side.BRAVO: [0, 0]}
	for player in NetworkManager.get_players():
		if not counts.has(player.state.team):
			continue
		counts[player.state.team][0] += 1
		if player.state.is_alive:
			counts[player.state.team][1] += 1
	_alpha_pips.set_counts(counts[Team.Side.ALPHA][0], counts[Team.Side.ALPHA][1])
	_bravo_pips.set_counts(counts[Team.Side.BRAVO][0], counts[Team.Side.BRAVO][1])
