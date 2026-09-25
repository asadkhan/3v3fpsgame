class_name CollisionLayers
extends RefCounted
## The game's collision layers in one place, because four different systems now
## have to agree about them and a magic number repeated in each is a bug waiting
## for someone to renumber one of them.
##
## [b]Why the player is not on the world layer.[/b] Everything static in the
## grey box sits on [constant WORLD] on layer 1, which is what the player
## collides with. A player body on the same layer would mean a raycast meant to
## find walls also finds players, and there would be no way to ask "what did I
## just shoot" without filtering the world out of the answer.
##
## [b]Why corpses get their own layer rather than just keeping PLAYER.[/b] A dead
## player still blocks movement - Chapter 5 wants that to matter - but must stop
## being a valid aim target and stop being an authoritative combatant. Those are
## three different questions and three different answers, so it needs to be a
## layer of its own. See [method Player.die].

## Static geometry: floor, walls, cover, ramp, stairs, the test obstacle.
const WORLD := 1 << 0

## A living player body. Also the layer a weapon's raycast looks for when it
## wants to find a player to shoot.
const PLAYER := 1 << 1

## Practice targets and the Chapter 3 turret. Solid, shootable, and not players.
const TARGET := 1 << 2

## A dead player. Still solid, no longer shootable as a combatant.
const CORPSE := 1 << 3

## What a player body collides with: the world, shootable props, and corpses.
## Deliberately excludes [constant PLAYER] - whether players block each other is
## a Chapter 4 decision, and leaving it out keeps the Chapter 2 movement
## behaviour unchanged.
const PLAYER_BODY_MASK := WORLD | TARGET | CORPSE

## What a weapon's hitscan looks for. Includes the world, because a shot has to
## stop at a wall, and corpses, because a body in the way should stop a bullet.
## The shooter excludes itself explicitly at query time.
const WEAPON_MASK := WORLD | PLAYER | TARGET | CORPSE

## Human-readable label for a layer mask's bits, for the debug overlay.
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
