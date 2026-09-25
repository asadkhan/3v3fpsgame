extends GameState
## [b]MAIN_MENU[/b] - the title screen. Nothing is loaded and nobody is
## connected yet.
##
## The menu screen itself lives in [code]res://scenes/ui/[/code] and is driven
## by whoever boots the game; this state only decides what "being in the menu"
## means. Keeping it empty is honest - there is genuinely nothing to tear down
## here yet, and Chapter 8 will add it when there is a menu to manage.

## "Nobody connected" is what this phase means, so arriving here from a match
## ends the session. Without it a host who pressed MAIN_MENU would keep a live
## server with no match scene, and its clients would sit in a phase that no
## longer exists.
func enter(_previous: GameState) -> void:
	if NetworkManager.is_online:
		NetworkManager.leave_game()


## Leaves the menu and opens the lobby. The menu screen calls this.
## Hosting and joining happen through [NetworkManager] before or after this,
## never from in here.
func open_lobby() -> bool:
	return request_state(GamePhase.Phase.LOBBY)
