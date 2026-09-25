class_name GamePhase
extends RefCounted
## The high-level phases a session moves through, in order:
##
## [codeblock]
## MAIN_MENU -> LOBBY -> WARMUP -> BUY -> ROUND_ACTIVE
##                                        ^                    |
##                                        +---- ROUND_END <-----+
##                                             |         |
##                                             +---> MATCH_END
## [/codeblock]
##
## The enum deliberately lives in its own script rather than inside
## [GameManager]. [GameManager] preloads every state script, so if the states
## also referred to [GameManager] for the enum, the two would depend on each
## other and Godot would report a cyclic reference. Keeping the enum separate
## lets the state scripts, the UI and the network layer all name a phase
## without loading [GameManager] at all.

enum Phase {
	MAIN_MENU,    ## Title screen. Nothing loaded, nobody connected.
	LOBBY,        ## Players are connected and waiting for the host.
	WARMUP,       ## One-off countdown before the very first round.
	BUY,          ## Preparation / buy window at the start of each round.
	ROUND_ACTIVE, ## Live combat.
	ROUND_END,    ## Post-round pause showing who won.
	MATCH_END,    ## Someone has won the match.
}


## Turns a [enum Phase] into a printable name, for logs and debug UI.
## Takes an int rather than [enum Phase] because a script-local enum used as a
## parameter type does not match `GamePhase.Phase` when passed from elsewhere.
static func phase_name(phase: int) -> String:
	var names := Phase.keys()
	if phase < 0 or phase >= names.size():
		return "INVALID"
	return names[phase]
