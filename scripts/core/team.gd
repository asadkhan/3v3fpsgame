class_name Team
extends RefCounted
## the two sides of a match.
##
## kept separate so PlayerState and MatchState can both talk about teams
## without depending on each other. add more sides here if that ever happens.

enum Side {
	NONE,   ## no team yet.
	ALPHA,  ## team 1.
	BRAVO,  ## team 2.
}

## sides a player can actually be put on (used when filling a lobby).
## plain ints, not enum Side, because a script-local enum type doesn't
## match Team.Side coming in from another script.
const ASSIGNABLE: Array[int] = [Side.ALPHA, Side.BRAVO]


## printable name for a side.
static func side_name(side: int) -> String:
	match side:
		Side.ALPHA:
			return "ALPHA"
		Side.BRAVO:
			return "BRAVO"
		_:
			return "NONE"


## the other side. unassigned players get NONE back.
static func opposing_side(side: int) -> int:
	match side:
		Side.ALPHA:
			return Side.BRAVO
		Side.BRAVO:
			return Side.ALPHA
		_:
			return Side.NONE
