class_name HudBuyMenu
extends PanelContainer
## The buy menu: open with B during the buy phase. One card per primary weapon
## with its price and headline numbers; buying is a request the host approves
## (see [PlayerLoadout]), so a card greys out rather than failing silently.

var _credits: Label
var _grid: HBoxContainer
var _cards: Dictionary = {}   # weapon_id -> Button
var _shield_cards: Dictionary = {}   # shield id -> Button
var _was_captured: bool = false

var is_open: bool:
	get: return visible


func _ready() -> void:
	UITheme.pin(self, Vector2(0.5, 0.5), -470, -150, 470, -150)
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := UITheme.label("BUY", UITheme.SIZE_LARGE, UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_credits = UITheme.label("", UITheme.SIZE_LARGE, UITheme.GOOD, HORIZONTAL_ALIGNMENT_RIGHT)
	header.add_child(_credits)

	_grid = HBoxContainer.new()
	_grid.add_theme_constant_override(&"separation", 12)
	column.add_child(_grid)
	for data in WeaponCatalog.buyable():
		var card := Button.new()
		card.custom_minimum_size = Vector2(210, 150)
		card.focus_mode = Control.FOCUS_NONE
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.text = "%s\n%s\n\n%d dmg  -  %d rpm\n%d rounds\n\n%d credits" % [
			data.display_name.to_upper(),
			WeaponData.Category.keys()[data.category].capitalize(),
			int(data.damage), int(data.rounds_per_minute()), data.magazine_size, data.price]
		card.pressed.connect(_on_card_pressed.bind(data.weapon_id))
		_grid.add_child(card)
		_cards[data.weapon_id] = card

	var shields := HBoxContainer.new()
	shields.add_theme_constant_override(&"separation", 12)
	column.add_child(shields)
	for shield_id in PlayerLoadout.SHIELD_IDS:
		var card := Button.new()
		card.custom_minimum_size = Vector2(210, 70)
		card.focus_mode = Control.FOCUS_NONE
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.text = "%s  (+%d)\n%d credits" % [PlayerLoadout.shield_name(shield_id).to_upper(),
			PlayerLoadout.shield_amount(shield_id), PlayerLoadout.shield_price(shield_id)]
		card.add_theme_color_override(&"font_color", UITheme.SHIELD)
		card.pressed.connect(_on_shield_pressed.bind(shield_id))
		shields.add_child(card)
		_shield_cards[shield_id] = card

	column.add_child(UITheme.label("Sidearm: Wren (always carried, key 2).  Weapons you survive with carry over.  B to close.",
		UITheme.SIZE_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))


func toggle(player: Player) -> void:
	if visible:
		close(player)
	elif player != null and GameManager.is_in(GamePhase.Phase.BUY) and player.state.is_alive:
		_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
	_credits.text = "%d credits" % player.state.credits
	for weapon_id in _cards:
		var data := WeaponCatalog.find(weapon_id)
		var card: Button = _cards[weapon_id]
		var owned: bool = player.state.primary_id == weapon_id
		card.disabled = not player.loadout.can_buy(data)
		card.modulate = UITheme.GOOD if owned else Color.WHITE
	for shield_id in _shield_cards:
		var shield_card: Button = _shield_cards[shield_id]
		shield_card.disabled = not player.loadout.can_buy_shield(shield_id)
		var have: bool = player.state.shield >= PlayerLoadout.shield_amount(shield_id)
		shield_card.modulate = UITheme.GOOD if have else Color.WHITE


func _on_shield_pressed(shield_id: StringName) -> void:
	var player := NetworkManager.get_local_player()
	if player != null:
		player.loadout.request_buy_shield(shield_id)


func _on_card_pressed(weapon_id: StringName) -> void:
	var player := NetworkManager.get_local_player()
	if player != null:
		player.loadout.request_buy(weapon_id)
