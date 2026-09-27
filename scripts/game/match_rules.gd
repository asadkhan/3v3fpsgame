class_name MatchRules
extends Resource
## the tunable numbers that define a match: phase lengths, rounds to win,
## players per team.
##
## these live in one res://data/match_rules.tres file instead of scattered
## literals, so balancing is a data edit and every system reads the same
## number. it's a Resource (not consts) so it can differ per map/mode and
## be sent from a dedicated server to clients on connect. GameManager owns
## the active instance; states read it via GameState.get_rules.
##
## read-only at runtime, like WeaponData - duplicate() for a private copy.

## where the shipped rules live. checked by load_default.
const DEFAULT_PATH := "res://data/match_rules.tres"

# --- Win condition -------------------------------------------------------

## round wins needed to take the match. first to this many.
@export_range(1, 20) var rounds_to_win: int = 5

## players on each side. session cap is derived from this (3v3 by default) -
## see NetworkManager.get_max_players.
@export_range(1, 8) var players_per_team: int = 3

# --- Phase lengths, in seconds -------------------------------------------

## one-off countdown before the very first round.
@export_range(0.0, 120.0, 0.5) var warmup_seconds: float = 5.0

## the freeze/buy window at the start of every round.
@export_range(0.0, 120.0, 0.5) var round_start_seconds: float = 3.0

## live combat.
@export_range(1.0, 600.0, 1.0) var round_seconds: float = 90.0

## how long the post-round result stays up.
@export_range(0.0, 120.0, 0.5) var round_end_seconds: float = 5.0


# --- Objective (Signal Core) ----------------------------------------------

## seconds the carrier must hold the plant key, standing on a site.
@export_range(0.5, 15.0, 0.5) var plant_seconds: float = 4.0

## seconds a defender must hold the defuse key beside a planted core.
@export_range(0.5, 20.0, 0.5) var defuse_seconds: float = 7.0

## seconds from planting until the core detonates. replaces the round clock.
@export_range(5.0, 120.0, 1.0) var detonation_seconds: float = 40.0

# --- Economy ----------------------------------------------------------------

## credits every player has at the start of each half.
@export_range(0, 20000, 50) var starting_credits: int = 800

## most credits a player can hold.
@export_range(0, 50000, 50) var max_credits: int = 9000

@export_range(0, 10000, 50) var round_win_credits: int = 3000

## paid to the losing side, plus loss_streak_bonus per earlier consecutive
## loss, capped at loss_streak_cap bonuses.
@export_range(0, 10000, 50) var round_loss_credits: int = 1900
@export_range(0, 5000, 50) var loss_streak_bonus: int = 500
@export_range(0, 10) var loss_streak_cap: int = 2

@export_range(0, 5000, 50) var kill_credits: int = 200

# --- Shields ------------------------------------------------------------------
# shield points absorb damage before health. kept if you survive the round,
# lost on death, cleared at half time.

@export_range(0, 100) var light_shield_amount: int = 25
@export_range(0, 5000, 50) var light_shield_price: int = 400
@export_range(0, 100) var heavy_shield_amount: int = 50
@export_range(0, 5000, 50) var heavy_shield_price: int = 1000
@export_range(0, 5000, 50) var plant_credits: int = 300


## rounds played before sides swap attack/defence: one fewer than the number
## needed to win, so each side attacks for half a full-length match.
func halftime_after() -> int:
	return maxi(rounds_to_win - 1, 1)


## total session size these rules imply: two teams of players_per_team.
func get_team_size() -> int:
	return players_per_team * 2


## loads the shipped rules, falling back to defaults if the file's missing
## or unreadable - a bad rules file shouldn't stop the game booting.
static func load_default() -> MatchRules:
	if ResourceLoader.exists(DEFAULT_PATH):
		var loaded := ResourceLoader.load(DEFAULT_PATH) as MatchRules
		if loaded != null:
			return loaded
		push_warning("MatchRules: %s exists but is not a MatchRules. Using defaults." % DEFAULT_PATH)
	else:
		push_warning("MatchRules: no rules file at %s. Using defaults." % DEFAULT_PATH)
	return MatchRules.new()


## reports values that would produce a broken match. returns true if usable.
func validate() -> bool:
	var ok := true

	if rounds_to_win < 1:
		push_warning("MatchRules: rounds_to_win must be at least 1.")
		ok = false

	if players_per_team < 1:
		push_warning("MatchRules: players_per_team must be at least 1.")
		ok = false

	if round_seconds <= 0.0:
		push_warning("MatchRules: round_seconds must be positive, or rounds never end.")
		ok = false

	return ok


## one-line summary for the debug overlay and logs.
func summary() -> String:
	return "%dv%d, first to %d, swap after %d | warmup %ds, buy %ds, round %ds, result %ds | plant %ss, defuse %ss, core %ds" % [
		players_per_team, players_per_team, rounds_to_win, halftime_after(),
		int(warmup_seconds), int(round_start_seconds),
		int(round_seconds), int(round_end_seconds),
		plant_seconds, defuse_seconds, int(detonation_seconds),
	]
