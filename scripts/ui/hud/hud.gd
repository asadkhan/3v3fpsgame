class_name Hud
extends CanvasLayer
## The in-match heads-up display. Lives in the match scene ([Playtest]), so it
## exists exactly while a match does and survives every phase change inside it.
##
## Each piece is its own small script under [code]scripts/ui/hud/[/code]; this
## node builds them, tells them who "you" are, and drives the ones that read
## live state. It only ever [b]reads[/b] game state - nothing here changes the
## match except the explicit buttons (start, rematch, leave).
##
## Keys handled here: Tab (hold) scoreboard, Enter (host) start / rematch,
## B buy menu (buy phase only).

## Slower-changing pieces refresh at this interval rather than every frame.
const SLOW_REFRESH := 0.2

var _root: Control
var _crosshair: HudCrosshair
var _vignette: HudDamageVignette
var _top_bar: HudTopBar
var _status: HudPlayerStatus
var _kill_feed: HudKillFeed
var _announcer: HudAnnouncer
var _scoreboard: HudScoreboard
var _lobby: HudLobbyPanel
var _match_end: HudMatchEndPanel
var _pause: HudPauseMenu
var _objective_prompt: HudObjectivePrompt
var _buy: HudBuyMenu

## The player this machine drives, re-resolved each frame (bodies come and go).
var _player: Player = null
var _slow_left: float = 0.0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UITheme.build()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_vignette = _add(HudDamageVignette.new(), "DamageVignette")
	_crosshair = _add(HudCrosshair.new(), "Crosshair")
	_top_bar = _add(HudTopBar.new(), "TopBar")
	_status = _add(HudPlayerStatus.new(), "PlayerStatus")
	_kill_feed = _add(HudKillFeed.new(), "KillFeed")
	_announcer = _add(HudAnnouncer.new(), "Announcer")
	_objective_prompt = _add(HudObjectivePrompt.new(), "ObjectivePrompt")
	_lobby = _add(HudLobbyPanel.new(), "LobbyPanel")
	_scoreboard = _add(HudScoreboard.new(), "Scoreboard")
	_match_end = _add(HudMatchEndPanel.new(), "MatchEndPanel")
	_pause = _add(HudPauseMenu.new(), "PauseMenu")
	_buy = _add(HudBuyMenu.new(), "BuyMenu")

	GameManager.state_changed.connect(_on_phase_changed)


func _add(control: Control, node_name: String) -> Control:
	control.name = node_name
	_root.add_child(control)
	return control


func _process(delta: float) -> void:
	_track_local_player()
	var team := _player.state.team if _player != null else Team.Side.NONE
	_announcer.local_team = team
	_announcer.local_peer = _player.peer_id if _player != null else 0

	_crosshair.visible = _player != null and _player.state.is_alive \
		and not GameManager.is_in(GamePhase.Phase.MATCH_END)
	_vignette.update_view(_player, delta)
	_top_bar.update_view()
	_status.update_view(_player)
	_scoreboard.visible = Input.is_action_pressed(&"scoreboard")
	_announcer.visible = not _scoreboard.visible and not (_buy != null and _buy.is_open)
	_lobby.update_view(delta)
	_match_end.update_view(team)
	_pause.update_view()
	_pause.visible = _pause.visible and not _buy.is_open
	_buy.update_view(_player)
	var objective := get_tree().get_first_node_in_group(SignalCoreObjective.GROUP) as SignalCoreObjective
	_objective_prompt.update_view(objective, _player)
	_top_bar.core_planted = objective != null and objective.is_planted() \
		and GameManager.is_in(GamePhase.Phase.ROUND_ACTIVE)

	_slow_left -= delta
	if _slow_left <= 0.0:
		_slow_left = SLOW_REFRESH
		_scoreboard.update_view(_player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"start_match"):
		if GameManager.is_in(GamePhase.Phase.LOBBY):
			_lobby.start_match()
		elif GameManager.is_in(GamePhase.Phase.MATCH_END):
			_match_end.rematch()
	elif event.is_action_pressed(&"buy_menu"):
		_buy.toggle(_player)
	elif event.is_action_pressed(&"scoreboard"):
		# Refresh immediately on the press, not up to one slow tick later.
		_scoreboard.visible = true
		_scoreboard.update_view(_player)


## Follows the local body as it is spawned, replaced or removed, and flashes
## the vignette when its health drops.
##
## A health comparison rather than [signal Player.took_hit]: that signal is
## raised where damage is applied, which online is the host. A client learns of
## its own damage only as a new health value, so watching the value is the one
## method that works on every machine.
func _track_local_player() -> void:
	var current := NetworkManager.get_local_player()
	if current != _player:
		_player = current
		_last_health = _player.state.health if _player != null else PlayerState.MAX_HEALTH
		return
	if _player == null:
		return
	var health := _player.state.health
	if health < _last_health:
		_vignette.flash(float(_last_health - health))
	_last_health = health

var _last_health: int = PlayerState.MAX_HEALTH


func _on_phase_changed(_previous: int, current: int) -> void:
	# The result screen has buttons; give the player their pointer back.
	if current == GamePhase.Phase.MATCH_END and _player != null:
		_player.capture_mouse(false)
