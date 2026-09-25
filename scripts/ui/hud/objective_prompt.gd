class_name HudObjectivePrompt
extends VBoxContainer
## Below the crosshair: what the objective lets you do right now ("Hold E to
## plant"), a progress bar while a plant or defuse is under way, and a small
## reminder when you are the one carrying the core.

var _prompt: Label
var _bar: ProgressBar
var _carrier: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.pin(self, Vector2(0.5, 0.5), -180, 60, 180, 150)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override(&"separation", 6)
	_prompt = UITheme.label("", UITheme.SIZE_BODY, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_prompt)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.ACCENT
	_bar.add_theme_stylebox_override(&"background", back)
	_bar.add_theme_stylebox_override(&"fill", fill)
	add_child(_bar)

	_carrier = UITheme.label("", UITheme.SIZE_SMALL, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	get_parent().add_child.call_deferred(_carrier)
	UITheme.pin(_carrier, Vector2(0.5, 1.0), -250, -170, 250, -145)


func update_view(objective: SignalCoreObjective, player: Player) -> void:
	_prompt.text = ""
	_bar.visible = false
	_carrier.text = ""
	if objective == null or player == null or not player.state.is_alive:
		return

	if objective.core_state == SignalCoreObjective.CoreState.CARRIED and objective.carrier_peer == player.peer_id:
		_carrier.text = "YOU CARRY THE SIGNAL CORE  -  plant it on A or B"

	if objective.planter_peer == player.peer_id:
		_prompt.text = "PLANTING..."
		_bar.visible = true
		_bar.value = objective.plant_progress
	elif objective.defuser_peer == player.peer_id:
		_prompt.text = "DEFUSING..."
		_bar.visible = true
		_bar.value = objective.defuse_progress
	elif objective.can_plant(player):
		_prompt.text = "Hold E to plant the core"
	elif objective.can_defuse(player):
		_prompt.text = "Hold E to defuse"
	elif objective.core_state == SignalCoreObjective.CoreState.DROPPED \
			and player.state.team == GameManager.match_state.attacking_side() \
			and player.global_position.distance_to(objective.core_position) < 6.0:
		_prompt.text = "Walk over the core to pick it up"
