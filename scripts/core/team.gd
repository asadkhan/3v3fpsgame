class_name Team
extends RefCounted
## The two sides of a match.
##
## This lives in its own tiny script so that [PlayerState] and [MatchState]
## can both talk about teams without either of them depending on the other.
## Add more values here if the game ever grows past two sides.

enum Side {
	NONE,   ## Not assigned to a team yet.
	ALPHA,  ## Team 1.
	BRAVO,  ## Team 2.
}

## Every side a player can actually be assigned to. Used when filling a lobby.
## Typed as ints rather than as [enum Side] on purpose: a script-local enum
## used as a type annotation does not match `Team.Side` when it is passed in
## from another script, so cross-script enums are declared as plain ints.
const ASSIGNABLE: Array[int] = [Side.ALPHA, Side.BRAVO]


## Turns a [enum Side] value into something printable in the UI and console.
static func side_name(side: int) -> String:
	match side:
		Side.ALPHA:
			return "ALPHA"
		Side.BRAVO:
			return "BRAVO"
		_:
			return "NONE"


## The other side. Returns [constant Side.NONE] for unassigned players.
static func opposing_side(side: int) -> int:
	match side:
		Side.ALPHA:
			return Side.BRAVO
		Side.BRAVO:
			return Side.ALPHA
		_:
			return Side.NONE
