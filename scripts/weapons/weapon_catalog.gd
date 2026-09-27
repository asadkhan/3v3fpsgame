class_name WeaponCatalog
extends RefCounted
## every weapon in the game, by weapon_id.
##
## fixed list of paths instead of scanning the folder: exported builds remap
## resource paths so scanning res://data/weapons/ at runtime isn't reliable,
## plus we want to control the buy menu order anyway.

## always carried, never bought, never lost.
const SIDEARM_ID := &"wren"
const KNIFE_ID := &"knife"

## buy-menu order.
const PATHS := {
	&"wren": "res://data/weapons/wren.tres",
	&"jackal": "res://data/weapons/jackal.tres",
	&"halberd": "res://data/weapons/halberd.tres",
	&"kestrel": "res://data/weapons/kestrel.tres",
	&"knife": "res://data/weapons/knife.tres",
}


## loaded weapons, kept alive here. without this, load() re-reads a weapon
## (model, textures and all) from disk whenever nothing else holds it - e.g.
## the hud asking for the sidearm's name every frame while the knife is out.
static var _cache: Dictionary = {}


## the weapon with this id, or null if unknown/empty.
static func find(weapon_id: StringName) -> WeaponData:
	if not PATHS.has(weapon_id):
		return null
	if not _cache.has(weapon_id):
		_cache[weapon_id] = load(PATHS[weapon_id]) as WeaponData
	return _cache[weapon_id]


static func sidearm() -> WeaponData:
	return find(SIDEARM_ID)


static func knife() -> WeaponData:
	return find(KNIFE_ID)


## primary weapons a player can buy, in menu order.
static func buyable() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for weapon_id in PATHS:
		var data := find(weapon_id)
		if data != null and data.is_buyable():
			out.append(data)
	return out
