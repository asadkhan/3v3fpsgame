extends Node
## boot scene, set as the project's main scene - first thing that runs,
## never freed for the whole session.
##
## only job is routing: listen to GameManager and put the screen for the
## current phase under %ScreenHost. owns no game state itself.
##
## this scene never changes because routing has to outlive whatever it
## routes to - screens come and go as children of this node, which stays put.
##
## the debug overlay is a separate scene behind DEV_OVERLAY_ENABLED, so it
## can be deleted for a release without touching the router.

## set false to drop the debug overlay from a build, or delete
## scenes/ui/dev_overlay.tscn, scripts/ui/dev_overlay.gd and the four lines
## below that use them.
const DEV_OVERLAY_ENABLED := true

const DEV_OVERLAY := preload("res://scenes/ui/dev_overlay.tscn")

## dev lobby: host, join, leave, a roster, a status line. behind its own
## flag so it's removable without touching the router or the match scene.
const DEV_NETWORK_UI_ENABLED := true

const DEV_NETWORK_UI := preload("res://scenes/ui/dev_network_ui.tscn")

## whether the game opens on the playtest or the main menu. set true to
## skip the menu, handy when iterating on movement or weapon feel.
const BOOT_INTO_PLAYTEST := false

## phase -> screen scene. phases with no entry fall through to the debug
## overlay plus the placeholder arena.
##
## all five gameplay phases share one scene for now - none has its own
## presentation yet. once a phase gets a real screen, give it its own entry.
const SCREENS := {
	GamePhase.Phase.MAIN_MENU: preload("res://scenes/ui/main_menu.tscn"),
	GamePhase.Phase.LOBBY: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.WARMUP: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.BUY: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.ROUND_ACTIVE: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.ROUND_END: preload("res://scenes/game/playtest.tscn"),
	# MATCH_END keeps the match scene too - freeing it would despawn every
	# networked body, and a rematch would have to rebuild the session from
	# scratch on every machine.
	GamePhase.Phase.MATCH_END: preload("res://scenes/game/playtest.tscn"),
}

## shown for any phase with no entry in SCREENS. instanced only while
## needed rather than kept hidden - a hidden Node3D still collides and
## still runs scripts.
const PLACEHOLDER_ENVIRONMENT := preload("res://scenes/game/placeholder_environment.tscn")

## screens with their own complete interface, where the debug overlay
## would only get in the way.
const SCREENS_WITHOUT_OVERLAY := [
	GamePhase.Phase.MAIN_MENU,
]

@onready var _screen_host: Node = %ScreenHost
## fallback arena, or null while a real screen is showing.
var _placeholder: Node3D = null

## screen currently in the tree, if any. freed on every phase change.
var _current_screen: Node = null

## which PackedScene _current_screen was built from, so a phase change
## between two phases sharing a screen can be recognised and ignored.
var _current_screen_scene: PackedScene = null

## null when DEV_OVERLAY_ENABLED is false.
var _dev_overlay: CanvasLayer = null

## null when DEV_NETWORK_UI_ENABLED is false. held so it's created once
## and lives for the whole session instead of re-instancing per phase change.
var _dev_network_ui: CanvasLayer = null


func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)
	# every button in the game clicks - one hook here instead of a line
	# in every menu.
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is BaseButton:
			(node as BaseButton).pressed.connect(func() -> void: Audio.play(&"ui_click", -8.0)))

	if DEV_OVERLAY_ENABLED:
		_dev_overlay = DEV_OVERLAY.instantiate()
		# assigned before adding, so the overlay's _ready can already read it.
		_dev_overlay.screen_host = _screen_host
		add_child(_dev_overlay)

	if DEV_NETWORK_UI_ENABLED:
		_dev_network_ui = DEV_NETWORK_UI.instantiate()
		add_child(_dev_network_ui)

	# done before the first render below, so the main menu never gets
	# instantiated on the way into the playtest.
	if BOOT_INTO_PLAYTEST:
		GameManager.change_state(GamePhase.Phase.LOBBY)

	# game's already in a phase by the time this scene loads, so render
	# once here instead of only reacting to future changes.
	_show_phase(GameManager.current_phase)

	# overlay's _ready ran before the routing above, so it needs one
	# explicit refresh or it reports "no scene" until the next phase change.
	if _dev_overlay != null:
		_dev_overlay.refresh()


## whether the dev panels are on screen. off by default; F3 (toggle_dev_ui)
## flips them.
var _dev_ui_shown: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_dev_ui"):
		_dev_ui_shown = not _dev_ui_shown
		_apply_screen_mode(GameManager.current_phase)
		get_viewport().set_input_as_handled()


## the one place a phase becomes a screen. adding a real menu, hud or match
## scene later just means adding a line to SCREENS.
func _on_state_changed(_previous_phase: int, current_phase: int) -> void:
	_show_phase(current_phase)


func _show_phase(phase: int) -> void:
	_swap_screen(phase)
	# overlay refreshes itself off the same signal, nothing else to do here.


## removes the outgoing screen and instantiates the incoming one, if this
## phase has a real screen.
func _swap_screen(phase: int) -> void:
	var wanted: PackedScene = SCREENS.get(phase, null)

	# several phases share one screen on purpose - rebuilding it between
	# them would throw away live state, most visibly the player respawning
	# on every round transition.
	if wanted != null and wanted == _current_screen_scene and is_instance_valid(_current_screen):
		_apply_screen_mode(phase)
		return

	if _current_screen != null:
		_current_screen.queue_free()
		_current_screen = null
	_current_screen_scene = null

	if wanted != null:
		_current_screen = wanted.instantiate()
		_current_screen_scene = wanted
		_screen_host.add_child(_current_screen)

	_apply_screen_mode(phase)


## decides which dev scaffolding is on screen.
func _apply_screen_mode(phase: int) -> void:
	# placeholder arena is the fallback for phases with no screen of their
	# own; created and freed rather than hidden (see PLACEHOLDER_ENVIRONMENT).
	var wants_placeholder := _current_screen == null
	if wants_placeholder and _placeholder == null:
		_placeholder = PLACEHOLDER_ENVIRONMENT.instantiate()
		add_child(_placeholder)
	elif not wants_placeholder and _placeholder != null:
		_placeholder.queue_free()
		_placeholder = null

	if _dev_overlay != null:
		_dev_overlay.visible = _dev_ui_shown and not SCREENS_WITHOUT_OVERLAY.has(phase)

	# network panel hidden on the main menu - it already has host/join, so
	# showing both would be two confusing buttons for the same thing.
	if _dev_network_ui != null:
		_dev_network_ui.visible = _dev_ui_shown and phase != GamePhase.Phase.MAIN_MENU
