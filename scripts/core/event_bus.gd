extends Node
## global signal hub. autoload: EventBus.
##
## use this for things more than one unrelated system needs to hear about
## (hud, audio, scoreboard) so they don't each need a direct reference to
## whoever raised the event.
##
## if exactly one system cares, just call it directly instead. don't add a
## signal nobody listens to.

# --- Lobby / connection -------------------------------------------------

## a peer joined the session.
signal player_joined(peer_id: int, player_name: String)

## a peer left the session.
signal player_left(peer_id: int)

# --- Combat -------------------------------------------------------------

## damage was dealt. amount is the health actually removed.
signal player_damaged(victim_id: int, attacker_id: int, amount: float)

## the local player was hurt by something at `from` (damage-direction
## indicator). local presentation only.
signal local_hit_from(from: Vector3)

## a blast went off near the local player; strength 0..1.
signal local_concussion(strength: float)

## a player was killed. killer_id is INVALID_PEER for environmental deaths.
## raised on every machine: host via Player.die, clients via the host's
## death announcement, so the kill feed and elimination check agree everywhere.
signal player_died(victim_id: int, killer_id: int, was_headshot: bool)

## a shot was taken - for tracers, muzzle flash, kill feed. not the
## authoritative hit resolution.
signal shot_fired(shooter_id: int, origin: Vector3, direction: Vector3)

## an ability was activated. ability_id matches an entry in res://data/.
signal ability_used(user_id: int, ability_id: StringName)

## a standout moment for a player: first blood, multi-kill, ace, clutch.
## kind is one of the MatchTracker callout constants. raised everywhere.
signal player_callout(peer_id: int, kind: StringName)

# --- Objective ----------------------------------------------------------

## the signal core was planted on site. planter_id is 0 on clients (they
## only learn it happened). raised everywhere.
signal core_planted(planter_id: int, site: String)

## a defender finished defusing the planted core. raised everywhere.
signal core_defused(defuser_id: int)

## the planted core's clock ran out. raised by the round on the host, then
## by the objective's snapshot on clients.
signal core_detonated

# --- Match flow ---------------------------------------------------------

## a round is being set up. fires at BUY, not when combat actually begins.
signal round_started(round_number: int)

## a round was resolved. winning_team is Team.Side.NONE if nobody won.
signal round_ended(winning_team: int)

## the match is over.
signal match_ended(winning_team: int)

## used as killer_id on player_died when nobody got the kill.
const INVALID_PEER := 0
