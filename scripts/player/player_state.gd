class_name PlayerState
extends RefCounted
## everything we know about one player: identity, team, health, scoreboard.
##
## not an autoload - every player needs its own instance. each player node
## owns one, and network code decides which peer is authoritative for it.
##
## plain object, not a node, so it can exist for a remote player before
## we've even spawned a scene for them.

## health a player starts each life with.
const MAX_HEALTH := 100

## network id of the peer controlling this player.
var peer_id: int = 0

## name shown on the scoreboard.
var display_name: String = "Player"

## which side this player is on.
var team: int = Team.Side.NONE

var health: int = MAX_HEALTH
var is_alive: bool = true

## shield points, absorbed before health. bought in the buy phase, kept
## across rounds while alive, lost on death. not restored by respawn().
var shield: int = 0

## credits for the buy menu. host-authoritative, mirrored to clients.
var credits: int = 0

## bought primary weapon's id, or "" if only carrying the sidearm.
## kept across rounds while alive, lost on death.
var primary_id: StringName = &""

var kills: int = 0
var deaths: int = 0
var assists: int = 0

# --- Match stats (host-authoritative; mirrored to clients by MatchTracker) ----

var damage_dealt: int = 0
var headshot_kills: int = 0
var first_bloods: int = 0
var plants: int = 0
var defuses: int = 0
var aces: int = 0
var clutches: int = 0

## player's level from their local profile, shown next to their name.
var level: int = 1

## whether the current death has already been credited to the scoreboard.
## guards record_death() against double counting.
var _death_recorded: bool = false


func _init(p_peer_id: int = 0, p_display_name: String = "Player", p_team: int = Team.Side.NONE) -> void:
	setup(p_peer_id, p_display_name, p_team)


## fills in identity. call once when the player slot is created.
func setup(p_peer_id: int, p_display_name: String, p_team: int = Team.Side.NONE) -> void:
	peer_id = p_peer_id
	display_name = p_display_name
	team = p_team
	respawn()


func assign_team(p_team: int) -> void:
	team = p_team


func is_on_team(p_team: int) -> bool:
	return team == p_team


## applies damage, returns how much was actually removed (shield + health).
## shield soaks damage first, then health. a player at 1 hp hit for 30 still
## only loses 1, so the caller can tell "nearly dead" from "dead".
func apply_damage(amount: float) -> float:
	if not is_alive or amount <= 0.0:
		return 0.0
	var incoming := int(round(amount))
	var absorbed := mini(shield, incoming)
	shield -= absorbed
	var before := health
	health = maxi(0, health - (incoming - absorbed))
	if health == 0:
		is_alive = false
		shield = 0
	return float(absorbed + before - health)


## restores health, capped at MAX_HEALTH. does not revive.
func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	health = mini(MAX_HEALTH, health + int(round(amount)))


## full reset to MAX_HEALTH and alive. keeps identity/team/score, so it
## doubles as both "new round" and "spawn".
func respawn() -> void:
	health = MAX_HEALTH
	is_alive = true
	_death_recorded = false


## credits the death on the scoreboard, once. guarded by its own flag rather
## than is_alive (which apply_damage already clears), so dying and being
## *counted* stay separate concerns. returns false if already recorded.
func record_death() -> bool:
	if _death_recorded:
		return false
	_death_recorded = true
	is_alive = false
	shield = 0
	deaths += 1
	return true


func record_kill() -> void:
	kills += 1


func record_assist() -> void:
	assists += 1


## resets only the scoreboard numbers, leaves identity/health alone.
## used when a new match starts on the same players.
func reset_score() -> void:
	kills = 0
	deaths = 0
	assists = 0
	damage_dealt = 0
	headshot_kills = 0
	first_bloods = 0
	plants = 0
	defuses = 0
	aces = 0
	clutches = 0


## combat score: damage plus a bonus per kill, assist and objective play.
## divided by rounds played, this is the per-round figure on the scoreboard -
## rewards overall impact, not just the last hit.
func combat_score() -> int:
	return damage_dealt + kills * 150 + assists * 50 + (plants + defuses) * 50


func combat_score_per_round(rounds: int) -> int:
	return int(round(float(combat_score()) / float(maxi(rounds, 1))))


## share of kills that were headshots, 0..100.
func headshot_percent() -> int:
	return int(round(100.0 * headshot_kills / maxf(kills, 1)))


## everything the scoreboard and result screen need, as plain data for an RPC.
func stats_to_dict() -> Dictionary:
	return {
		"kills": kills, "deaths": deaths, "assists": assists,
		"damage": damage_dealt, "hs_kills": headshot_kills, "first_bloods": first_bloods,
		"plants": plants, "defuses": defuses, "aces": aces, "clutches": clutches,
	}


func apply_stats_dict(data: Dictionary) -> void:
	kills = int(data.get("kills", kills))
	deaths = int(data.get("deaths", deaths))
	assists = int(data.get("assists", assists))
	damage_dealt = int(data.get("damage", damage_dealt))
	headshot_kills = int(data.get("hs_kills", headshot_kills))
	first_bloods = int(data.get("first_bloods", first_bloods))
	plants = int(data.get("plants", plants))
	defuses = int(data.get("defuses", defuses))
	aces = int(data.get("aces", aces))
	clutches = int(data.get("clutches", clutches))


## "12 / 3 / 1" - kills, deaths, assists.
func score_line() -> String:
	return "%d / %d / %d" % [kills, deaths, assists]
