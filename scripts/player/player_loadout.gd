class_name PlayerLoadout
extends Node
## What a player is carrying: a bought primary (or none) and the free sidearm,
## which one is in their hands, and each one's magazine. Also the buy path.
##
## A child of [Player] rather than more code in it: the player script is
## movement, combat and networking already, and the loadout is a self-contained
## job with its own RPCs.
##
## [b]Authority.[/b] What you own ([member PlayerState.primary_id]) and your
## credits are the host's: buying is a request, the host checks the phase, the
## price and your balance, then tells everyone. Which slot is in your hands is
## yours - you switch instantly and tell everyone, so the host resolves your
## shots with the right weapon's numbers.
##
## Magazines are tracked per weapon on the owning machine, so switching away
## from a half-empty rifle and back does not refill it.

const SLOT_PRIMARY := 0
const SLOT_SIDEARM := 1
const SLOT_KNIFE := 2

## Something about the loadout changed - bought, lost, or switched.
signal changed

var held_slot: int = SLOT_SIDEARM

## weapon_id -> rounds left in that weapon's magazine.
var _slot_ammo: Dictionary = {}

@onready var _player: Player = get_parent() as Player


func has_primary() -> bool:
	return _player.state.primary_id != &""


func primary_data() -> WeaponData:
	return WeaponCatalog.find(_player.state.primary_id)


## The weapon in the player's hands right now.
func held_data() -> WeaponData:
	if held_slot == SLOT_KNIFE:
		return WeaponCatalog.knife()
	if held_slot == SLOT_PRIMARY:
		var data := primary_data()
		if data != null:
			return data
	return WeaponCatalog.sidearm()


## A fresh life: full magazines, best weapon in hand.
func refill() -> void:
	held_slot = SLOT_PRIMARY if has_primary() else SLOT_SIDEARM
	_equip(held_data(), true)
	# Cleared after the equip, which files the outgoing weapon's magazine away;
	# otherwise a sidearm you survived holding keeps last round's ammo.
	_slot_ammo.clear()


## The owner switching weapons (keys 1 / 2 / 3).
func switch_to(slot: int) -> void:
	if slot == held_slot or not _player.state.is_alive:
		return
	if slot == SLOT_PRIMARY and not has_primary():
		return
	held_slot = slot
	_equip(held_data(), false)
	if NetworkManager.is_online:
		_net_held_slot.rpc(slot)


@rpc("any_peer", "call_remote", "reliable")
func _net_held_slot(slot: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != _player.peer_id and sender != NetworkManager.SERVER_PEER_ID:
		return
	held_slot = slot
	_equip(held_data(), false)


# --- Buying ---------------------------------------------------------------

## Asks to buy [param weapon_id]. Decided by the host (or locally offline).
func request_buy(weapon_id: StringName) -> void:
	if _is_authority():
		_server_buy(_player.peer_id, weapon_id)
	else:
		_rpc_buy.rpc_id(NetworkManager.SERVER_PEER_ID, weapon_id)


## Whether a purchase would be accepted right now - for greying out the menu.
func can_buy(data: WeaponData) -> bool:
	return data != null and data.is_buyable() \
		and GameManager.is_in(GamePhase.Phase.BUY) \
		and _player.state.is_alive \
		and _player.state.primary_id != data.weapon_id \
		and _player.state.credits >= data.price


@rpc("any_peer", "call_remote", "reliable")
func _rpc_buy(weapon_id: StringName) -> void:
	if multiplayer.is_server():
		_server_buy(multiplayer.get_remote_sender_id(), weapon_id)


func _server_buy(sender: int, weapon_id: StringName) -> void:
	if NetworkManager.is_online and sender != _player.peer_id:
		return
	var data := WeaponCatalog.find(weapon_id)
	if not can_buy(data):
		return
	_player.state.credits -= data.price
	_set_primary(weapon_id, true)
	_player._publish_net_state()


# --- Shields ----------------------------------------------------------------

const LIGHT_SHIELD := &"light_shield"
const HEAVY_SHIELD := &"heavy_shield"
const SHIELD_IDS: Array[StringName] = [LIGHT_SHIELD, HEAVY_SHIELD]


static func shield_amount(shield_id: StringName) -> int:
	var rules := GameManager.match_rules
	return rules.heavy_shield_amount if shield_id == HEAVY_SHIELD else rules.light_shield_amount


static func shield_price(shield_id: StringName) -> int:
	var rules := GameManager.match_rules
	return rules.heavy_shield_price if shield_id == HEAVY_SHIELD else rules.light_shield_price


static func shield_name(shield_id: StringName) -> String:
	return "Heavy Shield" if shield_id == HEAVY_SHIELD else "Light Shield"


## A shield can be bought when it would actually raise the current shield.
func can_buy_shield(shield_id: StringName) -> bool:
	return shield_id in SHIELD_IDS \
		and GameManager.is_in(GamePhase.Phase.BUY) \
		and _player.state.is_alive \
		and shield_amount(shield_id) > _player.state.shield \
		and _player.state.credits >= shield_price(shield_id)


func request_buy_shield(shield_id: StringName) -> void:
	if _is_authority():
		_server_buy_shield(_player.peer_id, shield_id)
	else:
		_rpc_buy_shield.rpc_id(NetworkManager.SERVER_PEER_ID, shield_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_buy_shield(shield_id: StringName) -> void:
	if multiplayer.is_server():
		_server_buy_shield(multiplayer.get_remote_sender_id(), shield_id)


func _server_buy_shield(sender: int, shield_id: StringName) -> void:
	if NetworkManager.is_online and sender != _player.peer_id:
		return
	if not can_buy_shield(shield_id):
		return
	_player.state.credits -= shield_price(shield_id)
	_player.state.shield = shield_amount(shield_id)
	_player._publish_net_state()
	if NetworkManager.is_online and _player.peer_id != multiplayer.get_unique_id():
		_net_shield_bought.rpc_id(_player.peer_id)
	else:
		_play_buy_sound()
	changed.emit()


## Host to the buyer: your shield purchase went through.
@rpc("any_peer", "call_remote", "reliable")
func _net_shield_bought() -> void:
	if multiplayer.get_remote_sender_id() == NetworkManager.SERVER_PEER_ID:
		_play_buy_sound()


## Host only: the player died, so the primary is gone.
func server_on_death() -> void:
	if has_primary():
		_set_primary(&"", false)


## Host only: the sides swapped, so everyone starts the half with a pistol.
func server_clear() -> void:
	_set_primary(&"", false)


func _set_primary(weapon_id: StringName, just_bought: bool) -> void:
	_apply_primary(weapon_id, just_bought)
	if NetworkManager.is_online:
		_net_primary.rpc(weapon_id, just_bought)


@rpc("any_peer", "call_remote", "reliable")
func _net_primary(weapon_id: StringName, just_bought: bool) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.SERVER_PEER_ID:
		return
	_apply_primary(weapon_id, just_bought)


func _apply_primary(weapon_id: StringName, just_bought: bool) -> void:
	var previous := _player.state.primary_id
	_player.state.primary_id = weapon_id
	if previous != &"":
		_slot_ammo.erase(previous)
	if weapon_id == &"":
		held_slot = SLOT_SIDEARM
		if _player.state.is_alive:
			_equip(held_data(), false)
	elif just_bought:
		# A new gun goes straight into your hands, fully loaded.
		held_slot = SLOT_PRIMARY
		_slot_ammo.erase(weapon_id)
		_equip(held_data(), true)
		_play_buy_sound()
	changed.emit()


func _play_buy_sound() -> void:
	if not _player.is_network_remote:
		Audio.play(&"buy", -6.0, 0.0)


# --- Internals --------------------------------------------------------------

## Puts [param data] in the player's hands, remembering the outgoing weapon's
## magazine and restoring the incoming one's unless [param fresh].
func _equip(data: WeaponData, fresh: bool) -> void:
	var weapon := _player.weapon
	if weapon == null or data == null:
		return
	if weapon.data != null and weapon.data != data:
		_slot_ammo[weapon.data.weapon_id] = weapon.ammo_in_magazine
	weapon.cancel_reload()
	weapon.equip(data, _player)
	if not fresh and _slot_ammo.has(data.weapon_id):
		weapon.ammo_in_magazine = int(_slot_ammo[data.weapon_id])
		weapon.ammo_changed.emit(weapon.ammo_in_magazine, weapon.reserve_ammo)
	# A new weapon comes up at the hip; each gun aims with its own numbers.
	_player.aim.reset()
	if not _player.is_network_remote and _player.is_inside_tree() and _player.state.is_alive:
		Audio.play(&"switch", -8.0)
	_player.weapon_changed.emit(weapon)
	changed.emit()


func _is_authority() -> bool:
	return not NetworkManager.is_online or multiplayer.is_server()
