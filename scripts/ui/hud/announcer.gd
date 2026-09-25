class_name HudAnnouncer
extends Control
## Centre-screen banners for the moments that matter: a round starting, the
## fight beginning, a round won or lost, and your own death or kill.
##
## Everything is phrased from the viewer's side - "ROUND WON" rather than
## "ALPHA WINS" - because that is the question a player is actually asking.

var _title: Label
var _subtitle: Label
var _tween: Tween
var _small: Label
var _small_tween: Tween

## The side this screen belongs to, supplied by [Hud] each frame.
var local_team: int = Team.Side.NONE
var local_peer: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.pin(self, Vector2(0.5, 0.3), -400, -60, 400, 80)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)
	_title = UITheme.label("", UITheme.SIZE_HUGE, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle = UITheme.label("", UITheme.SIZE_BODY, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_title)
	column.add_child(_subtitle)
	modulate.a = 0.0

	_small = UITheme.label("", UITheme.SIZE_BODY + 2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_small)
	UITheme.pin(_small, Vector2(0.5, 1.0), -300, 150, 300, 180)
	_small.modulate.a = 0.0

	GameManager.state_changed.connect(_on_phase_changed)
	EventBus.player_died.connect(_on_player_died)


func show_banner(title: String, subtitle: String = "", colour: Color = UITheme.TEXT, hold: float = 1.8) -> void:
	_title.text = title
	_title.add_theme_color_override(&"font_color", colour)
	_subtitle.text = subtitle
	if _tween != null:
		_tween.kill()
	modulate.a = 0.0
	scale = Vector2.ONE * 1.08
	pivot_offset = size * 0.5
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, ^"modulate:a", 1.0, 0.18)
	_tween.tween_property(self, ^"scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(hold)
	_tween.chain().tween_property(self, ^"modulate:a", 0.0, 0.4)


func _show_small(text: String, colour: Color) -> void:
	_small.text = text
	_small.add_theme_color_override(&"font_color", colour)
	if _small_tween != null:
		_small_tween.kill()
	_small.modulate.a = 1.0
	_small_tween = create_tween()
	_small_tween.tween_interval(1.6)
	_small_tween.tween_property(_small, ^"modulate:a", 0.0, 0.5)


func _on_phase_changed(_previous: int, current: int) -> void:
	var round_number := GameManager.match_state.round_number
	match current:
		GamePhase.Phase.WARMUP:
			show_banner("WARMUP", "The match starts shortly", UITheme.ACCENT)
		GamePhase.Phase.BUY:
			show_banner("ROUND %d" % round_number, "Buy phase - get ready", UITheme.TEXT)
		GamePhase.Phase.ROUND_ACTIVE:
			show_banner("FIGHT", "", UITheme.ACCENT, 0.6)
		GamePhase.Phase.ROUND_END:
			var winner := GameManager.match_state.last_round_winner
			if winner == Team.Side.NONE:
				show_banner("ROUND DRAW", "Nobody takes the round", UITheme.TEXT_DIM, 2.5)
			elif local_team == Team.Side.NONE:
				show_banner("%s WINS THE ROUND" % Team.side_name(winner), "", UITheme.team_colour(winner), 2.5)
			elif winner == local_team:
				show_banner("ROUND WON", GameManager.match_state.score_line(), UITheme.GOOD, 2.5)
			else:
				show_banner("ROUND LOST", GameManager.match_state.score_line(), UITheme.DANGER, 2.5)


func _on_player_died(victim_id: int, killer_id: int, headshot: bool) -> void:
	if local_peer == 0:
		return
	if victim_id == local_peer:
		var killer := NetworkManager.get_player_for(killer_id)
		var by := "by %s" % killer.state.display_name if killer != null and killer_id != victim_id else ""
		show_banner("ELIMINATED", by, UITheme.DANGER, 1.6)
	elif killer_id == local_peer:
		var victim := NetworkManager.get_player_for(victim_id)
		var victim_name := victim.state.display_name if victim != null else "enemy"
		_show_small("%s %s" % ["HEADSHOT -" if headshot else "ELIMINATED", victim_name],
			UITheme.ACCENT if headshot else UITheme.TEXT)
