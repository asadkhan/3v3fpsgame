extends Node
## The player's persistent profile: level, XP and career totals, saved to
## [code]user://profile.cfg[/code]. Registered as the [code]Profile[/code]
## autoload.
##
## Progression is deliberately simple and always moving: every finished match
## pays XP - more for winning and for playing well - and levels come quickly at
## first and steadily after. A title marks every few levels. It is local to the
## machine (there is no account server), so it is a motivator rather than a
## competitive rank; nothing in a match depends on it except the level shown
## beside your name.

const PATH := "user://profile.cfg"

## Emitted after a match result has been recorded.
signal changed

var level: int = 1
## XP into the current level.
var xp: int = 0
var matches: int = 0
var wins: int = 0
var kills: int = 0
var deaths: int = 0
var assists: int = 0
var headshot_kills: int = 0
var damage: int = 0
var aces: int = 0
var clutches: int = 0
var mvps: int = 0
var best_score: int = 0

# --- XP rules -------------------------------------------------------------------

const XP_MATCH := 200
const XP_WIN := 300
const XP_ROUND_WIN := 40
const XP_KILL := 20
const XP_ASSIST := 10
const XP_OBJECTIVE := 40
const XP_MVP := 150
const XP_ACE := 100
const XP_CLUTCH := 75

## Titles by level, lowest first.
const TITLES := [
	[1, "Recruit"], [5, "Operative"], [10, "Specialist"], [15, "Veteran"],
	[20, "Elite"], [30, "Vanguard"], [40, "Legend"],
]


func _ready() -> void:
	_load()


## XP needed to go from [param at_level] to the next.
static func xp_for_level(at_level: int) -> int:
	return 1000 + 150 * (at_level - 1)


static func title_for(at_level: int) -> String:
	var title: String = TITLES[0][1]
	for entry: Array in TITLES:
		if at_level >= int(entry[0]):
			title = entry[1]
	return title


func title() -> String:
	return title_for(level)


func kd_ratio() -> float:
	return float(kills) / float(maxi(deaths, 1))


func win_rate() -> int:
	return int(round(100.0 * wins / maxf(matches, 1)))


func headshot_rate() -> int:
	return int(round(100.0 * headshot_kills / maxf(kills, 1)))


## Records a finished match and pays its XP. Returns the breakdown for the
## result screen: {"lines": [[label, xp], ...], "total", "level_before",
## "xp_before", "level_after", "xp_after"}.
func record_match(state: PlayerState, won: bool, rounds_won: int, rounds_played: int, was_mvp: bool) -> Dictionary:
	var lines: Array = []
	lines.append(["Match played", XP_MATCH])
	if won:
		lines.append(["Victory", XP_WIN])
	if rounds_won > 0:
		lines.append(["Rounds won x%d" % rounds_won, rounds_won * XP_ROUND_WIN])
	if state.kills > 0:
		lines.append(["Kills x%d" % state.kills, state.kills * XP_KILL])
	if state.assists > 0:
		lines.append(["Assists x%d" % state.assists, state.assists * XP_ASSIST])
	var objective := state.plants + state.defuses
	if objective > 0:
		lines.append(["Plants and defuses x%d" % objective, objective * XP_OBJECTIVE])
	if state.aces > 0:
		lines.append(["Aces x%d" % state.aces, state.aces * XP_ACE])
	if state.clutches > 0:
		lines.append(["Clutches x%d" % state.clutches, state.clutches * XP_CLUTCH])
	if was_mvp:
		lines.append(["Match MVP", XP_MVP])
	var total := 0
	for line: Array in lines:
		total += int(line[1])

	var result := {"lines": lines, "total": total, "level_before": level, "xp_before": xp}

	matches += 1
	if won:
		wins += 1
	kills += state.kills
	deaths += state.deaths
	assists += state.assists
	headshot_kills += state.headshot_kills
	damage += state.damage_dealt
	aces += state.aces
	clutches += state.clutches
	if was_mvp:
		mvps += 1
	best_score = maxi(best_score, state.combat_score_per_round(rounds_played))

	xp += total
	while xp >= xp_for_level(level):
		xp -= xp_for_level(level)
		level += 1

	result["level_after"] = level
	result["xp_after"] = xp
	_save()
	changed.emit()
	return result


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for key in _keys():
		set(key, int(config.get_value("profile", key, get(key))))


func _save() -> void:
	var config := ConfigFile.new()
	for key in _keys():
		config.set_value("profile", key, get(key))
	var error := config.save(PATH)
	if error != OK:
		push_error("Profile: could not save (%s)" % error_string(error))


func _keys() -> Array[String]:
	return ["level", "xp", "matches", "wins", "kills", "deaths", "assists", "headshot_kills",
		"damage", "aces", "clutches", "mvps", "best_score"]
