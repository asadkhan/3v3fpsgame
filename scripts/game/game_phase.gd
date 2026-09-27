class_name GamePhase
extends RefCounted
## the high-level phases a session moves through:
## main_menu -> lobby -> warmup -> buy -> round_active -> round_end -> (loop
## back to buy, or) -> match_end.
##
## lives in its own script instead of inside GameManager so states/UI/network
## can reference a phase without pulling in GameManager (which would create a
## cyclic reference, since it preloads all the state scripts).

enum Phase {
	MAIN_MENU,    ## title screen, nothing loaded, nobody connected.
	LOBBY,        ## players connected, waiting for the host.
	WARMUP,       ## one-off countdown before the first round.
	BUY,          ## prep / buy window at the start of each round.
	ROUND_ACTIVE, ## live combat.
	ROUND_END,    ## post-round pause showing who won.
	MATCH_END,    ## someone won the match.
}


## turns a phase into a printable name, for logs and debug ui.
## takes an int instead of Phase since a script-local enum type doesn't match
## GamePhase.Phase when passed in from elsewhere.
static func phase_name(phase: int) -> String:
	var names := Phase.keys()
	if phase < 0 or phase >= names.size():
		return "INVALID"
	return names[phase]
