class_name MatchState
extends RefCounted
## The numbers for the match in progress: which round we are on, the score,
## and who has won.
##
## Deliberately [b]not[/b] an autoload. There is only ever one match running,
## so exactly one of these exists and [GameManager] owns it. Making it a
## singleton would give every system a second, competing way to ask "what is
## the score?" - ask [member GameManager.match_state] instead.
##
## This holds no nodes and no scene references, which keeps it trivial to
## replicate over the network in Chapter 4.

## The rules this match is being played under. Supplied by [GameManager] when
## the match is created. Held rather than read from a constant so that when a
## dedicated server becomes authoritative, the rules it owns are the same
## values every client scores against.
var rules: MatchRules

## Which round we are on. Incremented by [method start_round], so it is 0
## until the first [b]BUY[/b].
var round_number: int = 0

## Winner of the most recent round, or [constant Team.Side.NONE] if it ended
## with no winner (a draw, or a time-out with nobody ahead).
var last_round_winner: int = Team.Side.NONE

## Winner of the match, or [constant Team.Side.NONE] while it is still going.
var winning_team: int = Team.Side.NONE

var _scores: Dictionary = {}

## Consecutive rounds each side has lost, for the economy's loss bonus.
var _loss_streaks: Dictionary = {}


func _init(match_rules: MatchRules = null) -> void:
	# Optional so a bare MatchState.new() still works in a test, falling back
	# to the defaults rather than crashing on a null rules reference.
	rules = match_rules if match_rules != null else MatchRules.new()
	reset()


## Clears everything back to a fresh match. Called when a new lobby opens.
func reset() -> void:
	round_number = 0
	last_round_winner = Team.Side.NONE
	winning_team = Team.Side.NONE
	_scores = {
		Team.Side.ALPHA: 0,
		Team.Side.BRAVO: 0,
	}
	_loss_streaks = {
		Team.Side.ALPHA: 0,
		Team.Side.BRAVO: 0,
	}


func get_score(team: int) -> int:
	return _scores.get(team, 0)


## The team with more round wins, or [constant Team.Side.NONE] when level.
func get_leading_team() -> int:
	var alpha := get_score(Team.Side.ALPHA)
	var bravo := get_score(Team.Side.BRAVO)
	if alpha == bravo:
		return Team.Side.NONE
	return Team.Side.ALPHA if alpha > bravo else Team.Side.BRAVO


## Called at the start of each round, by [b]BUY[/b].
func start_round() -> void:
	round_number += 1


## Credits a round win. Returns true if it also won the match.
func add_round_win(team: int) -> bool:
	_scores[team] = get_score(team) + 1
	if _scores[team] >= rules.rounds_to_win:
		winning_team = team
		return true
	return false


## The side attacking in [param for_round] (default: the current round). ALPHA
## attacks the first half and BRAVO the second - see
## [method MatchRules.halftime_after]. Derived from the round number, so it
## needs no replication of its own.
func attacking_side(for_round: int = -1) -> int:
	var number := round_number if for_round < 0 else for_round
	return Team.Side.ALPHA if number <= rules.halftime_after() else Team.Side.BRAVO


func defending_side(for_round: int = -1) -> int:
	return Team.opposing_side(attacking_side(for_round))


## Whether the current round is the first one after the sides swapped.
func is_first_round_of_half() -> bool:
	return round_number == 1 or round_number == rules.halftime_after() + 1


func get_loss_streak(team: int) -> int:
	return _loss_streaks.get(team, 0)


## Updates both sides' loss streaks for a finished round.
func record_round_result(winner: int) -> void:
	for side in [Team.Side.ALPHA, Team.Side.BRAVO]:
		if winner == Team.Side.NONE:
			continue
		_loss_streaks[side] = 0 if side == winner else get_loss_streak(side) + 1


## Clears the loss streaks, at the start of each half.
func reset_loss_streaks() -> void:
	_loss_streaks[Team.Side.ALPHA] = 0
	_loss_streaks[Team.Side.BRAVO] = 0


func is_match_over() -> bool:
	return winning_team != Team.Side.NONE


## Everything a client needs to mirror the host's match, as plain data that can
## cross an RPC. The rules are deliberately not included - every peer loads the
## same [code]match_rules.tres[/code].
func to_dict() -> Dictionary:
	return {
		"round_number": round_number,
		"last_round_winner": last_round_winner,
		"winning_team": winning_team,
		"score_alpha": get_score(Team.Side.ALPHA),
		"score_bravo": get_score(Team.Side.BRAVO),
		"streak_alpha": get_loss_streak(Team.Side.ALPHA),
		"streak_bravo": get_loss_streak(Team.Side.BRAVO),
	}


## Replaces this match's numbers with a snapshot from [method to_dict].
func apply_dict(data: Dictionary) -> void:
	round_number = int(data.get("round_number", 0))
	last_round_winner = int(data.get("last_round_winner", Team.Side.NONE))
	winning_team = int(data.get("winning_team", Team.Side.NONE))
	_scores[Team.Side.ALPHA] = int(data.get("score_alpha", 0))
	_scores[Team.Side.BRAVO] = int(data.get("score_bravo", 0))
	_loss_streaks[Team.Side.ALPHA] = int(data.get("streak_alpha", 0))
	_loss_streaks[Team.Side.BRAVO] = int(data.get("streak_bravo", 0))


## "ALPHA 2 - 1 BRAVO" - for the HUD and the console.
func score_line() -> String:
	return "%s %d - %d %s" % [
		Team.side_name(Team.Side.ALPHA), get_score(Team.Side.ALPHA),
		get_score(Team.Side.BRAVO), Team.side_name(Team.Side.BRAVO),
	]
