class_name PlayerState
extends RefCounted
## Everything we know about one player: who they are, which side they are on,
## how much health they have, and how they are doing on the scoreboard.
##
## Deliberately [b]not[/b] an autoload. Every player needs their own instance,
## so a singleton would be wrong by definition. Each player node owns one, and
## in Chapter 4 the network layer decides which peer is authoritative for it.
##
## Being a plain object rather than a node means it can be created for a
## remote player we have not even spawned a scene for yet.

## Health a player starts each life with.
const MAX_HEALTH := 100

## Network id of the peer controlling this player.
var peer_id: int = 0

## Name shown on the scoreboard.
var display_name: String = "Player"

## Which side this player is on, a [enum Team.Side].
var team: int = Team.Side.NONE

var health: int = MAX_HEALTH
var is_alive: bool = true

var kills: int = 0
var deaths: int = 0
var assists: int = 0

## Whether the current death has been credited to the scoreboard yet. Guards
## [method record_death] against double counting.
var _death_recorded: bool = false


func _init(p_peer_id: int = 0, p_display_name: String = "Player", p_team: int = Team.Side.NONE) -> void:
	setup(p_peer_id, p_display_name, p_team)


## Fills in identity. Call once when the player slot is created.
func setup(p_peer_id: int, p_display_name: String, p_team: int = Team.Side.NONE) -> void:
	peer_id = p_peer_id
	display_name = p_display_name
	team = p_team
	respawn()


func assign_team(p_team: int) -> void:
	team = p_team


func is_on_team(p_team: int) -> bool:
	return team == p_team


## Applies damage and returns how much health was actually removed. A player
## at 1 health hit for 30 still only loses 1, so the caller can tell the
## difference between "nearly dead" and "dead".
func apply_damage(amount: float) -> float:
	if not is_alive or amount <= 0.0:
		return 0.0
	var before := health
	health = maxi(0, health - int(round(amount)))
	if health == 0:
		is_alive = false
	return float(before - health)


## Restores health, never above [constant MAX_HEALTH]. Does not revive.
func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	health = mini(MAX_HEALTH, health + int(round(amount)))


## Full reset back to [constant MAX_HEALTH] and alive. Keeps identity, team
## and score, so it doubles as "start of a new round" and "spawn".
func respawn() -> void:
	health = MAX_HEALTH
	is_alive = true
	_death_recorded = false


## Credits the death on the scoreboard, once.
##
## Guarded by its own flag rather than by [member is_alive], because reaching
## zero health through [method apply_damage] already clears that - so checking
## it here would silently refuse to credit a death caused by gunfire, and the
## player would never appear on the scoreboard. Dying and being *counted* are
## separate concerns and need separate guards.
##
## Returns false if this death was already recorded, so a double kill cannot
## be counted twice.
func record_death() -> bool:
	if _death_recorded:
		return false
	_death_recorded = true
	is_alive = false
	deaths += 1
	return true


func record_kill() -> void:
	kills += 1


func record_assist() -> void:
	assists += 1


## Resets only the scoreboard numbers, leaving identity and health alone.
## Used when a new match starts on the same players.
func reset_score() -> void:
	kills = 0
	deaths = 0
	assists = 0


## "12 / 3 / 1" - kills, deaths, assists.
func score_line() -> String:
	return "%d / %d / %d" % [kills, deaths, assists]
