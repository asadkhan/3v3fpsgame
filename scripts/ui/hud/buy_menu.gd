class_name HudBuyMenu
extends Control
## the buy menu: open with B during the buy phase. full-screen over a blurred
## backdrop - primaries on top with stat bars, armor and utility below.
## buying is a request the host approves (see PlayerLoadout), so a card
## greys out rather than failing silently.

const CARD_PRIMARY := Vector2(304, 158)
const CARD_SMALL := Vector2(226, 86)

var _credits: Label
var _cards: Dictionary = {}          # weapon_id -> card refs
var _shield_cards: Dictionary = {}   # shield id -> card refs
var _grenade_cards: Dictionary = {}  # grenade id -> card refs
var _was_captured: bool = false
var _content: Control

var is_open: bool:
	get: return visible


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	add_child(UITheme.blur_backdrop(0.5))

	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 14)
	UITheme.pin(_content, Vector2(0.5, 0.5), -480, -270, 480, 270)
	add_child(_content)

	# header: title left, credits right
	var header := HBoxContainer.new()
	_content.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override(&"separation", 2)
	header.add_child(titles)
	titles.add_child(UITheme.heading("ARMORY", 44, UITheme.TEXT))
	titles.add_child(UITheme.rule(UITheme.ACCENT, 72, 3))
	var wallet := VBoxContainer.new()
	wallet.add_theme_constant_override(&"separation", -4)
	header.add_child(wallet)
	wallet.add_child(UITheme.caption("CREDITS", UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	_credits = UITheme.heading("", 40, UITheme.GOOD, HORIZONTAL_ALIGNMENT_RIGHT)
	wallet.add_child(_credits)

	_content.add_child(UITheme.caption("PRIMARY WEAPONS"))
	var primaries := HBoxContainer.new()
	primaries.add_theme_constant_override(&"separation", 14)
	_content.add_child(primaries)
	for data in WeaponCatalog.buyable():
		var stats := [
			["DAMAGE", clampf(data.damage / 40.0, 0.05, 1.0)],
			["FIRE RATE", clampf(data.rounds_per_minute() / 900.0, 0.05, 1.0)],
			["MAGAZINE", clampf(data.magazine_size / 40.0, 0.05, 1.0)],
		]
		var card := _card(data.display_name.to_upper(),
			WeaponData.Category.keys()[data.category].capitalize().to_upper(),
			stats, data.price, CARD_PRIMARY, UITheme.ACCENT)
		card.button.pressed.connect(_on_card_pressed.bind(data.weapon_id))
		primaries.add_child(card.button)
		_cards[data.weapon_id] = card

	var lower := HBoxContainer.new()
	lower.add_theme_constant_override(&"separation", 14)
	_content.add_child(lower)
	var armor := _section(lower, "ARMOR")
	for shield_id in PlayerLoadout.SHIELD_IDS:
		var card := _card(PlayerLoadout.shield_name(shield_id).to_upper(),
			"+%d SHIELD" % PlayerLoadout.shield_amount(shield_id), [], PlayerLoadout.shield_price(shield_id),
			CARD_SMALL, UITheme.SHIELD)
		card.button.pressed.connect(_on_shield_pressed.bind(shield_id))
		armor.add_child(card.button)
		_shield_cards[shield_id] = card
	var utility := _section(lower, "UTILITY")
	for grenade_id in PlayerLoadout.GRENADE_IDS:
		var card := _card(String(PlayerLoadout.GRENADE_NAME[grenade_id]).to_upper(),
			"MAX %d  /  KEY %s" % [int(PlayerLoadout.GRENADE_MAX[grenade_id]),
				"G" if grenade_id == PlayerLoadout.FRAG else "Q"],
			[], int(PlayerLoadout.GRENADE_PRICE[grenade_id]), CARD_SMALL, UITheme.ACCENT)
		card.button.pressed.connect(func() -> void:
			var player := NetworkManager.get_local_player()
			if player != null:
				player.loadout.request_buy_grenade(grenade_id))
		utility.add_child(card.button)
		_grenade_cards[grenade_id] = card

	# footer: key hints
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 18)
	_content.add_child(footer)
	for hint: Array in [["2", "WREN"], ["3", "KNIFE"], ["G", "FRAG"], ["Q", "SMOKE"], ["Y", "INSPECT"], ["B", "CLOSE"]]:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override(&"separation", 6)
		pair.add_child(UITheme.keycap(hint[0]))
		pair.add_child(UITheme.caption(hint[1], UITheme.TEXT_DIM))
		footer.add_child(pair)
	var note := UITheme.label("weapons you survive with carry over", UITheme.SIZE_SMALL, UITheme.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_RIGHT)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)


func _section(parent: Control, title: String) -> HBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	parent.add_child(column)
	column.add_child(UITheme.caption(title))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	column.add_child(row)
	return row


## a buy card: a flat button with the name, a subtitle, optional stat bars
## and the price. returns {button, price, tag, bars}.
func _card(title: String, subtitle: String, stats: Array, price: int, card_size: Vector2, accent: Color) -> Dictionary:
	var button := Button.new()
	button.custom_minimum_size = card_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override(&"normal", _card_box(Color(0.03, 0.035, 0.045, 0.82), Color(1, 1, 1, 0.1)))
	button.add_theme_stylebox_override(&"hover", _card_box(Color(accent, 0.12), accent))
	button.add_theme_stylebox_override(&"pressed", _card_box(Color(accent, 0.24), accent))
	button.add_theme_stylebox_override(&"disabled", _card_box(Color(0.03, 0.035, 0.045, 0.6), Color(1, 1, 1, 0.04)))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	button.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	margin.add_child(column)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var name_label := UITheme.heading(title, UITheme.SIZE_LARGE - 2 if stats.size() > 0 else UITheme.SIZE_BODY + 2)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var tag := UITheme.caption("", UITheme.GOOD, HORIZONTAL_ALIGNMENT_RIGHT)
	top.add_child(tag)
	column.add_child(UITheme.caption(subtitle, Color(accent, 0.85)))

	var bars := []
	if stats.size() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(gap)
		for stat: Array in stats:
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override(&"separation", 8)
			column.add_child(row)
			var stat_name := UITheme.caption(stat[0], UITheme.TEXT_DIM)
			stat_name.custom_minimum_size = Vector2(84, 0)
			row.add_child(stat_name)
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.max_value = 1.0
			bar.value = stat[1]
			bar.custom_minimum_size = Vector2(0, 4)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color(UITheme.TEXT, 0.85)
			bar.add_theme_stylebox_override(&"fill", fill)
			row.add_child(bar)
			bars.append(bar)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var price_label := UITheme.heading("%d" % price, UITheme.SIZE_BODY + 2, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	column.add_child(price_label)
	return {"button": button, "price": price_label, "tag": tag, "bars": bars}


func _card_box(fill: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_border_width_all(1)
	box.border_width_bottom = 3
	box.border_color = edge
	return box


func toggle(player: Player) -> void:
	if visible:
		close(player)
	elif player != null and GameManager.is_in(GamePhase.Phase.BUY) and player.state.is_alive:
		_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_content.modulate.a = 0.0
		_content.pivot_offset = _content.size * 0.5
		_content.scale = Vector2.ONE * 0.97
		var tween := create_tween().set_parallel()
		tween.tween_property(_content, "modulate:a", 1.0, 0.16)
		tween.tween_property(_content, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close(player: Player) -> void:
	if not visible:
		return
	visible = false
	if _was_captured and player != null:
		player.capture_mouse(true)


func update_view(player: Player) -> void:
	if not visible:
		return
	if player == null or not GameManager.is_in(GamePhase.Phase.BUY) or not player.state.is_alive:
		close(player)
		return
	_credits.text = "%d" % player.state.credits
	for weapon_id in _cards:
		var data := WeaponCatalog.find(weapon_id)
		_state(_cards[weapon_id], player.loadout.can_buy(data), player.state.primary_id == weapon_id, "EQUIPPED")
	for shield_id in _shield_cards:
		var have: bool = player.state.shield >= PlayerLoadout.shield_amount(shield_id)
		_state(_shield_cards[shield_id], player.loadout.can_buy_shield(shield_id), have, "EQUIPPED")
	for grenade_id in _grenade_cards:
		var count := int(player.loadout.grenades[grenade_id])
		var full: bool = count >= int(PlayerLoadout.GRENADE_MAX[grenade_id])
		_state(_grenade_cards[grenade_id], player.loadout.can_buy_grenade(grenade_id), full,
			"x%d" % count if count > 0 else "")
		if count > 0 and not full:
			(_grenade_cards[grenade_id].tag as Label).text = "x%d" % count


## greys out what can't be bought, tags what's already owned.
func _state(card: Dictionary, can_buy: bool, owned: bool, owned_text: String) -> void:
	var button: Button = card.button
	button.disabled = not can_buy
	(card.tag as Label).text = owned_text if owned else ""
	button.modulate = Color(1, 1, 1, 1.0 if can_buy or owned else 0.55)
	(card.price as Label).add_theme_color_override(&"font_color",
		UITheme.GOOD if owned else (UITheme.ACCENT if can_buy else UITheme.DANGER))


func _on_shield_pressed(shield_id: StringName) -> void:
	var player := NetworkManager.get_local_player()
	if player != null:
		player.loadout.request_buy_shield(shield_id)


func _on_card_pressed(weapon_id: StringName) -> void:
	var player := NetworkManager.get_local_player()
	if player != null:
		player.loadout.request_buy(weapon_id)
