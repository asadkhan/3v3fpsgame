extends Node
## Boot scene. Set as the project's main scene, so this is the first thing
## that runs, and it is never freed for the rest of the session.
##
## Its only job is routing: listen to [GameManager] and put the screen that
## belongs to the current phase under [member %ScreenHost]. It owns no game
## state of its own.
##
## [b]Why this scene never changes:[/b] routing has to outlive whatever it is
## routing to. If the router swapped itself out with the menu scene, there
## would be nothing left to handle the phase change that took the player out
## of the menu, and the game would need a second router. So the screens come
## and go as children of this node, which stays put.
##
## Nothing in this file is temporary. The grey box is a separate scene, and the
## debug overlay is a separate scene behind [constant DEV_OVERLAY_ENABLED], so
## both can be deleted for a release without touching the router.

## Set false to drop the debug overlay from a build, or delete
## [code]scenes/ui/dev_overlay.tscn[/code] and [code]scripts/ui/dev_overlay.gd[/code]
## and the four lines below that use them. That is the entire removal procedure.
const DEV_OVERLAY_ENABLED := true

const DEV_OVERLAY := preload("res://scenes/ui/dev_overlay.tscn")

## Chapter 4's development lobby: Host, Join, Leave, a roster and a status
## line. Behind its own flag for the same reason as the overlay - it is the one
## piece of Chapter 4 a shipped build must not carry, and it should be removable
## without touching the router or the match scene.
##
## Deleted entirely in Chapter 8, when a real lobby with team select replaces
## it. Nothing in [NetworkManager] depends on it; it depends on
## [NetworkManager], which is the correct direction for a dev tool.
const DEV_NETWORK_UI_ENABLED := true

const DEV_NETWORK_UI := preload("res://scenes/ui/dev_network_ui.tscn")

## Whether the game opens on the playtest or on the main menu.
##
## [b]Chapter 4 set this to false.[/b] Chapters 2 and 3 booted straight into the
## playtest because there was nothing to choose and a Host / Join button led
## nowhere - no second player could appear, so pressing it was strictly worse
## than skipping it. That stopped being true the moment networked spawning
## worked: the main menu's Host and Join are now the real front door, and hiding
## them would have made the chapter's headline feature something you had to know
## to go and find in a corner of the screen.
##
## Set it to true and the menu is bypassed again, which is occasionally useful
## for working on movement or weapon feel without going through two screens.
const BOOT_INTO_PLAYTEST := false

## Phase -> screen scene. Phases with no entry fall through to the debug
## overlay plus the placeholder arena, which is correct for every phase until
## each one has a scene of its own.
##
## All five gameplay phases deliberately share one scene. They are different
## phases of the same thing - a match with a player in it - and none of them has
## its own presentation yet, so there is nothing to distinguish between them.
## Once rounds have a real round-start screen, that phase gets its own entry
## here and the rest stay pointed at the playtest.
const SCREENS := {
	GamePhase.Phase.MAIN_MENU: preload("res://scenes/ui/main_menu.tscn"),
	GamePhase.Phase.LOBBY: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.WARMUP: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.BUY: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.ROUND_ACTIVE: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.ROUND_END: preload("res://scenes/game/playtest.tscn"),
	# MATCH_END keeps the match scene too. Freeing it would despawn every
	# networked body, and a rematch (MATCH_END -> LOBBY) would then have to
	# rebuild the whole session from nothing on every machine.
	GamePhase.Phase.MATCH_END: preload("res://scenes/game/playtest.tscn"),
}

## Shown for any phase that has no entry in [constant SCREENS]. Instanced only
## while it is needed rather than kept hidden in the tree: a hidden Node3D still
## collides and still runs its scripts, so a permanently resident copy meant
## every match had a second, invisible arena overlapping the real one - with its
## own practice turret shooting at the player.
const PLACEHOLDER_ENVIRONMENT := preload("res://scenes/game/placeholder_environment.tscn")

## Screens that bring their own complete interface, where the debug overlay
## would only get in the way. Every other screen keeps the overlay up, which is
## what lets the playtest report FPS, player position and movement state while
## it is being played.
const SCREENS_WITHOUT_OVERLAY := [
	GamePhase.Phase.MAIN_MENU,
]

@onready var _screen_host: Node = %ScreenHost
## The fallback arena, or null while a real screen is showing.
var _placeholder: Node3D = null

## The screen currently in the tree, if any. Freed on every phase change.
var _current_screen: Node = null

## Which [PackedScene] [member _current_screen] was built from, so a phase
## change between two phases that share a screen can be recognised and ignored.
var _current_screen_scene: PackedScene = null

## Null when [constant DEV_OVERLAY_ENABLED] is false.
var _dev_overlay: CanvasLayer = null

## Null when [constant DEV_NETWORK_UI_ENABLED] is false. Held so it is created
## once and lives for the whole session rather than being re-instanced every
## time the phase routes to a different screen - a lobby that vanished on every
## round change would be a lobby you could not use to debug a round change.
var _dev_network_ui: CanvasLayer = null


func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)

	if DEV_OVERLAY_ENABLED:
		_dev_overlay = DEV_OVERLAY.instantiate()
		# Assigned before adding, so the overlay's _ready can already read it.
		_dev_overlay.screen_host = _screen_host
		add_child(_dev_overlay)

	if DEV_NETWORK_UI_ENABLED:
		_dev_network_ui = DEV_NETWORK_UI.instantiate()
		add_child(_dev_network_ui)

	# Done before the first render below, so the main menu is never even
	# instantiated on the way into the playtest. GameManager has already run
	# its own _ready by now, because autoloads are set up before the main scene.
	if BOOT_INTO_PLAYTEST:
		GameManager.change_state(GamePhase.Phase.LOBBY)

	# The game is already in a phase by the time this scene loads, so render
	# once here instead of only reacting to future changes.
	_show_phase(GameManager.current_phase)

	# The overlay's own _ready ran before the menu above was routed into place,
	# so it needs one explicit refresh. Without this it reports "no scene" until
	# the next phase change.
	if _dev_overlay != null:
		_dev_overlay.refresh()


## The one place a phase becomes a screen. Adding a real menu, HUD or match
## scene later means adding a line to [constant SCREENS] and nothing else.
func _on_state_changed(_previous_phase: int, current_phase: int) -> void:
	_show_phase(current_phase)


func _show_phase(phase: int) -> void:
	_swap_screen(phase)
	# The overlay refreshes itself off the same signal, so there is nothing else
	# to do here.


## Removes the outgoing screen and instantiates the incoming one, if this phase
## has a real screen.
func _swap_screen(phase: int) -> void:
	var wanted: PackedScene = SCREENS.get(phase, null)

	# Several phases share one screen on purpose. Rebuilding it between them
	# would throw away live state for nothing - most visibly the player, who
	# would respawn at the top of the map on every round transition. Keeping
	# the live instance is also the behaviour a real game wants: the match does
	# not restart because the round counter moved.
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


## Decides which development scaffolding is on screen.
func _apply_screen_mode(phase: int) -> void:
	# The placeholder arena is the fallback for phases with no screen of their
	# own. It is created and freed rather than hidden - see
	# [constant PLACEHOLDER_ENVIRONMENT] for why hiding was not enough.
	var wants_placeholder := _current_screen == null
	if wants_placeholder and _placeholder == null:
		_placeholder = PLACEHOLDER_ENVIRONMENT.instantiate()
		add_child(_placeholder)
	elif not wants_placeholder and _placeholder != null:
		_placeholder.queue_free()
		_placeholder = null

	if _dev_overlay != null:
		_dev_overlay.visible = not SCREENS_WITHOUT_OVERLAY.has(phase)

	# The network panel is hidden on the main menu for a different reason from
	# the overlay: the menu already has Host and Join, so showing both would
	# give the player two identical-looking buttons pointing at two different
	# places, and pressing the wrong one first would be baffling. The panel is
	# for a session that is already running and wants a Leave button and a
	# roster, neither of which the menu has room for.
	if _dev_network_ui != null:
		_dev_network_ui.visible = phase != GamePhase.Phase.MAIN_MENU
