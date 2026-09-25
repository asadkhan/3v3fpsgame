extends Node
## Global signal hub. Registered as the [code]EventBus[/code] autoload.
##
## Use this for things that more than one unrelated system needs to hear
## about - the HUD, the audio layer, the scoreboard - so those systems do not
## each need a direct reference to whatever raised the event.
##
## [b]When not to use it:[/b] if exactly one system cares about something,
## that system should just call the other one directly. This file is not a
## dumping ground; if you find yourself adding a signal nobody listens to,
## delete it instead.

# --- Lobby / connection -------------------------------------------------

## A peer joined the session.
signal player_joined(peer_id: int, player_name: String)

## A peer left the session.
signal player_left(peer_id: int)

# --- Combat -------------------------------------------------------------

## Damage was dealt. [param amount] is the health actually removed.
signal player_damaged(victim_id: int, attacker_id: int, amount: float)

## A player was killed. [param killer_id] is [constant INVALID_PEER] for deaths
## caused by the environment. Raised on every machine: on the host by
## [method Player.die], on clients by the host's death announcement - so the
## kill feed and the round's elimination check see the same events everywhere.
signal player_died(victim_id: int, killer_id: int, was_headshot: bool)

## A shot was taken. For tracers, muzzle flash and the kill feed - the
## authoritative hit resolution is Chapter 3's job, not this signal's.
signal shot_fired(shooter_id: int, origin: Vector3, direction: Vector3)

## An ability was activated. [param ability_id] matches an entry in [code]res://data/[/code].
signal ability_used(user_id: int, ability_id: StringName)

# --- Objective ----------------------------------------------------------

## The Signal Core was planted on [param site]. [param planter_id] is 0 on
## clients (they only learn that it happened). Raised on every machine.
signal core_planted(planter_id: int, site: String)

## A defender finished defusing the planted core. Raised on every machine.
signal core_defused(defuser_id: int)

## The planted core's clock ran out. Raised by the round on the host, then by
## the objective's snapshot on clients.
signal core_detonated

# --- Match flow ---------------------------------------------------------

## A round is being set up. This fires at [b]BUY[/b], not when combat
## actually begins.
signal round_started(round_number: int)

## A round has been resolved. [param winning_team] is a [enum Team.Side], or
## [constant Team.Side.NONE] if the round ended with no winner.
signal round_ended(winning_team: int)

## The match is over. [param winning_team] is a [enum Team.Side].
signal match_ended(winning_team: int)

## Used as [param killer_id] on [signal player_died] when nobody got the kill.
const INVALID_PEER := 0
