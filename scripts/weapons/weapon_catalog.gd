class_name WeaponCatalog
extends RefCounted
## Every weapon in the game, by [member WeaponData.weapon_id].
##
## A fixed list of paths rather than a folder scan: an exported build remaps
## resource files, so listing [code]res://data/weapons/[/code] at runtime is not
## reliable, and the buy menu's order is a design decision anyway.

## Always carried, never bought, never lost.
const SIDEARM_ID := &"wren"
const KNIFE_ID := &"knife"

## Buy-menu order.
const PATHS := {
	&"wren": "res://data/weapons/wren.tres",
	&"jackal": "res://data/weapons/jackal.tres",
	&"halberd": "res://data/weapons/halberd.tres",
	&"kestrel": "res://data/weapons/kestrel.tres",
	&"knife": "res://data/weapons/knife.tres",
}


## The weapon with [param weapon_id], or null for an unknown or empty id.
static func find(weapon_id: StringName) -> WeaponData:
	if not PATHS.has(weapon_id):
		return null
	return load(PATHS[weapon_id]) as WeaponData


static func sidearm() -> WeaponData:
	return find(SIDEARM_ID)


static func knife() -> WeaponData:
	return find(KNIFE_ID)


## Primary weapons a player can buy, in menu order.
static func buyable() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for weapon_id in PATHS:
		var data := find(weapon_id)
		if data != null and data.is_buyable():
			out.append(data)
	return out
