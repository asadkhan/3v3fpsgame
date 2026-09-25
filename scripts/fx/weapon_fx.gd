class_name WeaponFx
extends Node3D
## Everything about a shot that is only worth showing to the machine that pulled
## the trigger.
##
## [b]This node is the network boundary for weapon presentation.[/b] The weapon
## knows where a round stopped; it emits that as [signal Weapon.impact_requested]
## and stops there. This listens and decides to draw. In Chapter 4, when a
## client's shot is validated by the host, the host re-runs the hitscan and gets
## a position back - and the machine that draws the spark is still the one whose
## input caused it, not the one that happened to be authoritative. Keeping the
## two apart is why the two classes are separate, and it means a future
## "spectator mode shows other players' tracers" feature has somewhere to live
## without either class growing a flag it should not have.
##
## [b]Muzzle flash and tracer are not here yet[/b] and do not need to be: the
## flash is a light on the weapon, driven by the local trigger, and the tracer
## would be spawned the same way as an impact. Chapter 8 replaces this file.

## The effect spawned where a round stops.
@export var impact_scene: PackedScene

## Rejects impacts from further away than this. A round that travelled the
## weapon's whole 45 m range is a legitimate hit and should be marked; this is
## only here so a bad origin from a network message cannot fill the screen with
## effects.
@export var max_impact_distance: float = 100.0

@onready var _weapon: Weapon = get_parent().get_node_or_null(^"Weapon") as Weapon
## Found by walking up rather than by a fixed number of `get_parent()` hops:
## this node lives at Player/Head/WeaponMount/WeaponFx, and the old
## two-hop lookup landed on Head, so the player was always null and no network
## impact was ever drawn.
@onready var _player: Player = _find_player()

## Impacts alive at once. A full automatic burst is seven or eight rounds a
## second, and each effect is meant to last a fifth of that, so the cap is
## never reached in normal play - it exists so a pathological frame cannot
## spawn hundreds of nodes and stall the game.
const MAX_LIVE_EFFECTS := 24

var _live: int = 0


func _ready() -> void:
	if _weapon == null:
		push_warning("WeaponFx: no sibling Weapon node; impacts will not be drawn.")
		return
	_weapon.impact_requested.connect(_on_impact_requested)

	# Chapter 4: when this machine is not the one that resolved the shot, the
	# impact arrives as a verdict from the host rather than as this weapon's own
	# signal. Without this connection an online client's shots would produce no
	# visible hit at all - the muzzle flash comes from the local trigger, but
	# the impact comes from the authority, and only the authority's raycast ever
	# ran.
	if _player != null:
		_player.shot_resolved.connect(_on_shot_resolved)


func _find_player() -> Player:
	var node := get_parent()
	while node != null:
		if node is Player:
			return node as Player
		node = node.get_parent()
	return null


func _on_impact_requested(at: Vector3, normal: Vector3, zone: int) -> void:
	_spawn_impact(at, normal, zone)


## The one place an impact actually gets drawn, shared by the local
## weapon's own signal and the network's verdict.
##
## Refuses anything further than [member max_impact_distance] from this
## player's eye. A round that travelled the weapon's whole range is fine; a
## point 400 m away came from either a wrong origin or a node that has since
## been freed, and neither is worth filling the screen with.
func _spawn_impact(at: Vector3, normal: Vector3, zone: int) -> void:
	if impact_scene == null or _live >= MAX_LIVE_EFFECTS:
		return
	if _player != null and _player.get_eye_position().distance_to(at) > max_impact_distance:
		return

	var effect := impact_scene.instantiate() as ImpactEffect
	if effect == null:
		return

	# Added to the world rather than to this node, so the effect stays where it
	# was spawned instead of being dragged through the room as the player walks.
	# It removes itself when it expires, so nothing has to remember to clean up.
	get_tree().current_scene.add_child(effect)
	effect.setup(at, normal, zone)

	_live += 1
	effect.tree_exited.connect(_on_effect_freed)


func _on_effect_freed() -> void:
	_live = maxi(0, _live - 1)


## Draws an impact the network told us about rather than one this weapon found.
##
## The host broadcasts the point, the surface normal and the zone - the three
## things a spark needs and nothing more. No damage, no hit point precision, no
## "what did I hit" reconstruction: the client is not being asked to agree with
## the host about ballistics, only to show that something happened.
func _on_shot_resolved(at: Vector3, normal: Vector3, _victim: Player, zone: int, _killed: bool, is_local: bool) -> void:
	if is_local:
		# This machine's own shot, already drawn from the weapon's own signal on
		# whichever machine ran the raycast - here if we are the authority,
		# arriving as a verdict if we are not. Drawing it again would put two
		# effects on the same square centimetre.
		return
	_spawn_impact(at, normal, zone)
