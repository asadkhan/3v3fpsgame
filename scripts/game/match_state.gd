class_name MatchState
extends RefCounted
## the numbers for the match in progress: round, score, who's won.
##
## not an autoload on purpose - only one match ever runs, and GameManager
## owns the one instance. use GameManager.match_state instead of making
## this a singleton.
##
## holds no nodes or scene refs, so it's trivial to replicate over the network.

## rules this match is played under, supplied by GameManager on creation.
var rules: MatchRules

## which round we're on. bumped by start_round, so it's 0 until the first BUY.
var round_number: int = 0

## winner of the most recent round, or NONE for a draw/timeout.
var last_round_winner: int = Team.Side.NONE

## winner of the match, or NONE while still going.
var winning_team: int = Team.Side.NONE

var _scores: Dictionary = {}

## consecutive rounds each side has lost, for the economy's loss bonus.
var _loss_streaks: Dictionary = {}


func _init(match_rules: MatchRules = null) -> void:
	# optional so a bare MatchState.new() still works in a test.
	rules = match_rules if match_rules != null else MatchRules.new()
	reset()


## clears everything back to a fresh match, called when a new lobby opens.
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


## the team with more round wins, or NONE when tied.
func get_leading_team() -> int:
	var alpha := get_score(Team.Side.ALPHA)
	var bravo := get_score(Team.Side.BRAVO)
	if alpha == bravo:
		return Team.Side.NONE
	return Team.Side.ALPHA if alpha > bravo else Team.Side.BRAVO


## called at the start of each round, by BUY.
func start_round() -> void:
	round_number += 1


## credits a round win. returns true if it also won the match.
func add_round_win(team: int) -> bool:
	_scores[team] = get_score(team) + 1
	if _scores[team] >= rules.rounds_to_win:
		winning_team = team
		return true
	return false


## the side attacking in for_round (default: current round). ALPHA attacks
## the first half, BRAVO the second - see MatchRules.halftime_after. derived
## from the round number, so it needs no replication of its own.
func attacking_side(for_round: int = -1) -> int:
	var number := round_number if for_round < 0 else for_round
	return Team.Side.ALPHA if number <= rules.halftime_after() else Team.Side.BRAVO


func defending_side(for_round: int = -1) -> int:
	return Team.opposing_side(attacking_side(for_round))


## whether the current round is the first one after the sides swapped.
func is_first_round_of_half() -> bool:
	return round_number == 1 or round_number == rules.halftime_after() + 1


func get_loss_streak(team: int) -> int:
	return _loss_streaks.get(team, 0)


## updates both sides' loss streaks for a finished round.
func record_round_result(winner: int) -> void:
	for side in [Team.Side.ALPHA, Team.Side.BRAVO]:
		if winner == Team.Side.NONE:
			continue
		_loss_streaks[side] = 0 if side == winner else get_loss_streak(side) + 1


## clears the loss streaks, at the start of each half.
func reset_loss_streaks() -> void:
	_loss_streaks[Team.Side.ALPHA] = 0
	_loss_streaks[Team.Side.BRAVO] = 0


func is_match_over() -> bool:
	return winning_team != Team.Side.NONE


## everything a client needs to mirror the host's match, as plain data for an
## RPC. rules aren't included - every peer loads the same match_rules.tres.
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


## replaces this match's numbers with a snapshot from to_dict.
func apply_dict(data: Dictionary) -> void:
	round_number = int(data.get("round_number", 0))
	last_round_winner = int(data.get("last_round_winner", Team.Side.NONE))
	winning_team = int(data.get("winning_team", Team.Side.NONE))
	_scores[Team.Side.ALPHA] = int(data.get("score_alpha", 0))
	_scores[Team.Side.BRAVO] = int(data.get("score_bravo", 0))
	_loss_streaks[Team.Side.ALPHA] = int(data.get("streak_alpha", 0))
	_loss_streaks[Team.Side.BRAVO] = int(data.get("streak_bravo", 0))


## "ALPHA 2 - 1 BRAVO" - for the hud and the console.
func score_line() -> String:
	return "%s %d - %d %s" % [
		Team.side_name(Team.Side.ALPHA), get_score(Team.Side.ALPHA),
		get_score(Team.Side.BRAVO), Team.side_name(Team.Side.BRAVO),
	]
