class_name MatchRules
extends Resource
## The tunable numbers that define a match: how long each phase lasts, how many
## rounds it takes to win, and how many players are on each team.
##
## [b]Why these are data and not constants.[/b] They used to be literals spread
## across the phase files, which meant "how long is a round?" had five different
## answers depending on which file you asked, and changing the round length meant
## editing four scripts. Everything tunable now lives in one
## [code]res://data/match_rules.tres[/code] file, so balancing a match is a data
## edit and every system reads the same number.
##
## [b]Why a Resource rather than plain [code]const[/code]s.[/b] A const is
## fixed at compile time and cannot differ per map, per mode, or between a
## client and a server. When Chapter 4 introduces a dedicated server, the server
## owns the authoritative rules and sends them to clients on connect - which is
## only possible if the rules are a value that can be transmitted, not a
## constant baked into the executable. [GameManager] owns the active instance
## and states read it through [method GameState.get_rules].
##
## [b]Read-only at runtime, like [WeaponData].[/b] [method Resource.duplicate]
## if a private copy is genuinely needed.

## Where the shipped rules live. Checked by [method load_default].
const DEFAULT_PATH := "res://data/match_rules.tres"

# --- Win condition -------------------------------------------------------

## Round wins needed to take the match. First to this many.
@export_range(1, 20) var rounds_to_win: int = 5

## Players on each side. The brief is 3v3, so the session cap is derived from
## this rather than stated separately - see [method NetworkManager.get_max_players].
@export_range(1, 8) var players_per_team: int = 3

# --- Phase lengths, in seconds -------------------------------------------

## One-off countdown before the very first round.
@export_range(0.0, 120.0, 0.5) var warmup_seconds: float = 5.0

## The freeze / buy window at the start of every round.
@export_range(0.0, 120.0, 0.5) var round_start_seconds: float = 3.0

## Live combat.
@export_range(1.0, 600.0, 1.0) var round_seconds: float = 90.0

## How long the post-round result stays up.
@export_range(0.0, 120.0, 0.5) var round_end_seconds: float = 5.0


## Total session size these rules imply: two teams of [member players_per_team].
func get_team_size() -> int:
	return players_per_team * 2


## Loads the shipped rules, falling back to the defaults above if the file is
## missing or unreadable. A missing rules file should not stop the game booting;
## it should produce a playable match at default settings and a warning naming
## the path to fix.
static func load_default() -> MatchRules:
	if ResourceLoader.exists(DEFAULT_PATH):
		var loaded := ResourceLoader.load(DEFAULT_PATH) as MatchRules
		if loaded != null:
			return loaded
		push_warning("MatchRules: %s exists but is not a MatchRules. Using defaults." % DEFAULT_PATH)
	else:
		push_warning("MatchRules: no rules file at %s. Using defaults." % DEFAULT_PATH)
	return MatchRules.new()


## Reports values that will produce a broken match. Returns true if usable.
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


## One-line summary for the debug overlay and logs.
func summary() -> String:
	return "%dv%d, first to %d | warmup %ds, buy %ds, round %ds, result %ds" % [
		players_per_team, players_per_team, rounds_to_win,
		int(warmup_seconds), int(round_start_seconds),
		int(round_seconds), int(round_end_seconds),
	]
