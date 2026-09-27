class_name Damageable
extends RefCounted
## the one way damage crosses between objects in this game.
##
## it's a dispatcher, not a base class, because Player is already a
## CharacterBody3D and gdscript has no multiple inheritance - can't make
## it extend a Damageable node too.
##
## the contract is just two duck-typed methods plus this dispatcher:
##
## [codeblock]
## func apply_damage(amount: float, source: Node, zone: HitZone) -> float
## func resolve_hit_zone(point: Vector3, collider: Object) -> HitZone
## [/codeblock]
##
## anything with those two methods can be shot. no inheritance needed, and
## weapons never need to know what a Player actually is.
##
## always go through deal_damage instead of poking target.health directly -
## keeps every damage source (turrets, abilities, hazards, replicated hits)
## behaving the same way.

## which part of a target got hit.
enum HitZone {
	BODY,
	HEAD,
}

## method name a target must implement to be damageable.
const APPLY_DAMAGE := &"apply_damage"

## applies damage to target, returns how much health was actually removed.
##
## zone is the hit zone the shooter resolved, source is whoever caused it -
## both optional so a quick test can call this with the bare minimum.
##
## returns 0.0 if target isn't damageable, is already dead, or declined the
## hit - that's the one signal a shooter needs to decide on a hit marker.
static func deal_damage(
		target: Object,
		amount: float,
		source: Node = null,
		zone: HitZone = HitZone.BODY) -> float:
	if not is_damageable(target) or amount <= 0.0:
		return 0.0
	return float(target.call(APPLY_DAMAGE, amount, source, zone))


## whether target implements the damage contract.
static func is_damageable(target: Object) -> bool:
	return target != null and target.has_method(APPLY_DAMAGE)


## finds the thing actually responsible for collider, which isn't always
## the collider itself (e.g. a target's head is a separate body from its
## torso). walks up the tree until something implements the contract.
## returns null if nothing up the chain is damageable (plain scenery).
static func find_target(collider: Object) -> Object:
	var node := collider as Node
	while node != null:
		if is_damageable(node):
			return node
		node = node.get_parent()
	return null


## asks target which hit zone a shot at point should count as.
## falls back to BODY if the target doesn't answer, so a target that only
## cares about "i took damage" can skip implementing this.
static func resolve_zone(target: Object, point: Vector3, collider: Object) -> HitZone:
	if target == null or not target.has_method(&"resolve_hit_zone"):
		return HitZone.BODY
	return target.call(&"resolve_hit_zone", point, collider)


## human-readable zone name, for the debug overlay and test harness.
static func zone_name(zone: HitZone) -> String:
	return HitZone.keys()[zone]
