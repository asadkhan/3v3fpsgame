extends GameState
## MAIN_MENU - the title screen. nothing loaded, nobody connected yet.
##
## the menu screen itself lives in res://scenes/ui/ and is driven by whoever
## boots the game; this state just decides what "being in the menu" means.

## "nobody connected" is what this phase means, so arriving here from a
## match ends the session - otherwise a host pressing main menu would keep
## a live server with no match scene, and clients stuck in a dead phase.
func enter(_previous: GameState) -> void:
	if NetworkManager.is_online:
		NetworkManager.leave_game()


## leaves the menu and opens the lobby. the menu screen calls this; hosting
## and joining happen through NetworkManager, never from in here.
func open_lobby() -> bool:
	return request_state(GamePhase.Phase.LOBBY)
