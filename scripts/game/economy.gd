class_name Economy
extends RefCounted
## the credit rules, in one place. all amounts come from MatchRules; this
## class only applies them. host/offline authority only - clients receive
## balances through the player state rpc.


## adds (or, negative, removes) credits, clamped to 0..max.
static func add_credits(state: PlayerState, amount: int) -> void:
	var cap := GameManager.match_rules.max_credits
	state.credits = clampi(state.credits + amount, 0, cap)


## pays both sides for a finished round. called by ROUND_END before loss
## streaks update, so a side's first loss earns the base amount.
static func pay_round(winner: int) -> void:
	var rules := GameManager.match_rules
	var match_state := GameManager.match_state
	for player in NetworkManager.get_players():
		var side := player.state.team
		if side == Team.Side.NONE:
			continue
		var amount := rules.round_loss_credits
		if winner == Team.Side.NONE:
			amount = rules.round_loss_credits
		elif side == winner:
			amount = rules.round_win_credits
		else:
			var streak := mini(match_state.get_loss_streak(side), rules.loss_streak_cap)
			amount = rules.round_loss_credits + streak * rules.loss_streak_bonus
		add_credits(player.state, amount)
		player._publish_net_state()


## everyone back to the starting balance and a pistol - start of each half.
static func reset_for_half() -> void:
	for player in NetworkManager.get_players():
		player.state.credits = GameManager.match_rules.starting_credits
		player.state.shield = 0
		player.loadout.server_clear()
		player._publish_net_state()
