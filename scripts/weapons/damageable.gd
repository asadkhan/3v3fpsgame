class_name Damageable
extends RefCounted
## The one way damage crosses between objects in this game.
##
## [b]Why this is a dispatcher and not a base class.[/b] The obvious design is
## [code]class_name Damageable extends Node[/code] that [Player] and
## [PracticeTarget] both extend. That does not work here: [Player] is already
## a [CharacterBody3D] and GDScript has no multiple inheritance, so making it a
## Damageable would mean either a pointless intermediate base or moving the
## character body out of the player. Neither is worth it for one method.
##
## So the contract is a pair of duck-typed methods plus this dispatcher:
##
## [codeblock]
## func apply_damage(amount: float, source: Node, zone: HitZone) -> float
## func resolve_hit_zone(point: Vector3, collider: Object) -> HitZone
## [/codeblock]
##
## Anything with those two methods can be shot. Nothing has to inherit from
## anything, and the weapon never has to know what a [Player] is - which is
## exactly the separation Chapter 3 asks for and the thing that would break
## first in Chapter 4, where the shooter and the target are on different
## machines.
##
## [b]Why the weapon cannot shortcut it.[/b] A weapon that reached into
## [code]target.health = 0[/code] would be welded to that one target type. Every
## later damage source - the Chapter 3 turret, Chapter 4's replicated hits,
## Chapter 6's abilities, environmental hazards - goes through
## [method deal_damage] as well, so they all behave identically and none of them
## needs to know what they are hitting.

## Which part of a target was hit.
enum HitZone {
	BODY,
	HEAD,
}

## The method a target must implement to be damageable. Checked by
## [method is_damageable] so a typo produces a clear message rather than a
## "nonexistent function" error from deep inside a raycast.
const APPLY_DAMAGE := &"apply_damage"

## Applies [param amount] damage to [param target] and returns how much health
## was actually removed.
##
## [param zone] is the hit zone the shooter resolved, and [param source] is
## whoever caused it, so a target can attribute a kill later without the weapon
## having to report back. Both are optional so a test or an environmental
## hazard can call this with the minimum.
##
## Returns 0.0 for a target that is not damageable, is already dead, or
## declined the hit. A return of 0.0 is therefore the single signal a shooter
## needs to decide whether to show a hit marker - it does not have to ask a
## second question of the same object.
static func deal_damage(
		target: Object,
		amount: float,
		source: Node = null,
		zone: HitZone = HitZone.BODY) -> float:
	if not is_damageable(target) or amount <= 0.0:
		return 0.0
	return float(target.call(APPLY_DAMAGE, amount, source, zone))


## Whether [param target] implements the damage contract.
static func is_damageable(target: Object) -> bool:
	return target != null and target.has_method(APPLY_DAMAGE)


## Finds the thing responsible for [param collider], which is not always the
## collider itself.
##
## A raycast hands back the [CollisionObject3D] it touched, and a body can have
## several. A practice target's head is a [b]separate[/b] body from its torso so
## the weapon can tell them apart from the result dictionary alone - which means
## the node the ray actually hit is not the node that knows how to take damage.
##
## So this walks up from whatever was hit until it finds something that
## implements the contract, and hands that to [method deal_damage] instead. It
## is what lets a hitbox be a plain collider with no script on it at all.
##
## Returns [code]null[/code] when nothing up the chain is damageable, which is
## the answer for scenery.
static func find_target(collider: Object) -> Object:
	var node := collider as Node
	while node != null:
		if is_damageable(node):
			return node
		node = node.get_parent()
	return null


## Asks [param target] which hit zone a shot at [param point] should count as.
##
## Falls back to [constant HitZone.BODY] when the target does not answer, so a
## target that only cares about "I took damage" can implement one method instead
## of two.
static func resolve_zone(target: Object, point: Vector3, collider: Object) -> HitZone:
	if target == null or not target.has_method(&"resolve_hit_zone"):
		return HitZone.BODY
	return target.call(&"resolve_hit_zone", point, collider)


## Human-readable zone name, for the debug overlay and the test harness.
static func zone_name(zone: HitZone) -> String:
	return HitZone.keys()[zone]
