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

	# When this machine is not the one that resolved the shot, the impact
	# arrives as a verdict from the host rather than as this weapon's own
	# signal, and this machine's own trigger pulls draw their tracer the moment
	# they happen rather than waiting for that verdict.
	if _player != null:
		_player.shot_resolved.connect(_on_shot_resolved)
		_player.shot_fired.connect(_on_shot_fired)


func _find_player() -> Player:
	var node := get_parent()
	while node != null:
		if node is Player:
			return node as Player
		node = node.get_parent()
	return null


## Who draws what, so every shot is drawn exactly once on every machine:
##
## - [b]Tracer.[/b] The shooter's own machine draws it instantly from the local
##   trigger ([method _on_shot_fired]). Every other machine draws it when it
##   learns about the shot - the host from its own resolution
##   ([method _on_impact_requested] on a remote body's weapon), clients from the
##   host's verdict ([method _on_shot_resolved]) - and adds a muzzle flash,
##   because the shooter's viewmodel is invisible to them.
## - [b]Impact.[/b] Drawn from whichever resolution this machine sees: the
##   weapon's own hitscan (offline, or the host), or the verdict (clients).
func _on_impact_requested(at: Vector3, normal: Vector3, zone: int, surface: int) -> void:
	_spawn_impact(at, normal, zone, surface)
	if _is_remote_shooter():
		_spawn_tracer(at, true)


func _on_shot_resolved(at: Vector3, normal: Vector3, _victim: Player, zone: int, _killed: bool,
		is_local: bool, surface: int) -> void:
	if is_local:
		# Already drawn from the weapon's own signal on the machine that ran the
		# raycast. Drawing it again would double every effect.
		return
	_spawn_impact(at, normal, zone, surface)
	if _is_remote_shooter():
		_spawn_tracer(at, true)


## This machine's own shot: trace a purely visual ray to find where the streak
## should end. The real result comes from the authority; this only decides where
## a line of light is drawn, so it may disagree by a hair and nobody can tell.
func _on_shot_fired(origin: Vector3, direction: Vector3) -> void:
	if _weapon == null or _weapon.data == null:
		return
	var end := origin + direction * _weapon.data.max_range
	var space := get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(origin, end, CollisionLayers.WEAPON_MASK)
		if _player != null:
			query.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			end = hit.position
	_spawn_tracer(end, false)


func _is_remote_shooter() -> bool:
	return _player != null and _player.is_network_remote


func _spawn_tracer(to: Vector3, with_flash: bool) -> void:
	if _weapon == null:
		return
	var from := _weapon.get_muzzle_position()
	if from.distance_to(to) < 0.5:
		return
	var tracer := Tracer.new()
	tracer.setup(from, to, with_flash)
	get_tree().current_scene.add_child(tracer)


## The one place an impact actually gets drawn: the spark and debris, plus a
## bullet hole on scenery. Nothing at all for a round that hit only air.
##
## Refuses anything further than [member max_impact_distance] from this
## player's eye. A round that travelled the weapon's whole range is fine; a
## point 400 m away came from either a wrong origin or a node that has since
## been freed, and neither is worth filling the screen with.
func _spawn_impact(at: Vector3, normal: Vector3, zone: int, surface: int) -> void:
	if surface == Weapon.Surface.NONE:
		return
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
	effect.setup(at, normal, zone, surface == Weapon.Surface.ENTITY)

	_live += 1
	effect.tree_exited.connect(_on_effect_freed)

	if surface == Weapon.Surface.WORLD:
		var hole := BulletHole.new()
		hole.setup(at, normal)
		get_tree().current_scene.add_child(hole)


func _on_effect_freed() -> void:
	_live = maxi(0, _live - 1)
