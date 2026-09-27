class_name CollisionLayers
extends RefCounted
## all the collision layers in one place so nobody has to repeat magic numbers.
##
## players aren't on the world layer - otherwise a wall raycast would also hit
## players, and there'd be no clean way to ask "what did i shoot".
##
## corpses get their own layer instead of staying on PLAYER: a dead body should
## still block movement but stop being a valid target. see Player.die.

## static geometry: floor, walls, cover, ramps, stairs, etc.
const WORLD := 1 << 0

## a living player body. also what a weapon's raycast looks for to find a target.
const PLAYER := 1 << 1

## practice targets and turrets. solid and shootable, but not players.
const TARGET := 1 << 2

## a dead player. still solid, no longer a valid target.
const CORPSE := 1 << 3

## what a player body collides with: world, props, corpses. excludes PLAYER on
## purpose - players don't block each other (yet).
const PLAYER_BODY_MASK := WORLD | TARGET | CORPSE

## what a weapon's hitscan checks against: world (shots stop at walls), players,
## targets, and corpses (a body in the way stops the bullet). shooter excludes
## itself at query time.
const WEAPON_MASK := WORLD | PLAYER | TARGET | CORPSE

## turns a layer mask's bits into a readable label, for the debug overlay.
static func describe(mask: int) -> String:
	var names: Array[String] = []
	if mask & WORLD:
		names.append("world")
	if mask & PLAYER:
		names.append("player")
	if mask & TARGET:
		names.append("target")
	if mask & CORPSE:
		names.append("corpse")
	return "none" if names.is_empty() else ", ".join(names)
