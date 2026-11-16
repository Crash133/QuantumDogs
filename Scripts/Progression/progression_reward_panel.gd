class_name ProgressionRewardPanel
extends Control

## Stage-reward layout (from the Figma "Progression UI" skeleton): the card deck
## top left, the offered cards staggered across the middle, and a sidebar with
## the currency overview over the purchasable permanent upgrades.

const CARD_SCENE: PackedScene = preload("res://Scenes/Progression/RewardCard.tscn")
const ROW_SCENE: PackedScene = preload("res://Scenes/Progression/UpgradeRow.tscn")
## Reference layout (Figma, 1440x1024): card size, gap and the lowered middle card.
const CARD_SIZE := Vector2(280, 400)
const CARD_GAP := 29.0
const STAGGER := 227.0

var view_model: ProgressionRewardViewModel
var selected: Array[StringName] = []
var stats: VBoxContainer
var choices: Control
var confirm: Button
var balance: Label
var status: Label
var _deck_info: Label

func _ready() -> void:
	balance = %Balance
	choices = %Choices
	stats = %Stats
	status = %Status
	confirm = %Confirm
	_deck_info = %DeckInfo
	_style_static()
	confirm.pressed.connect(func():
		if view_model != null: view_model.submit_selection(selected))
	choices.resized.connect(_layout_cards)

func _style_static() -> void:
	%Sidebar.add_theme_stylebox_override("panel", RewardStyle.box(RewardStyle.PANEL, Color(0.25, 0.9, 1.0, 0.35), 2, Vector4(0, 0, 0, 0)))
	%Header.add_theme_stylebox_override("panel", RewardStyle.box(RewardStyle.PANEL_RAISED, Color(0.25, 0.9, 1.0, 0.6), 2, Vector4(18, 14, 18, 14)))
	RewardStyle.label(%HeaderCaption, 13, RewardStyle.MUTED)
	RewardStyle.label(balance, 30, RewardStyle.CYAN)
	RewardStyle.label(%HeaderUnit, 12, RewardStyle.MUTED)
	RewardStyle.label(%DeckTitle, 14, RewardStyle.PALE)
	RewardStyle.label(_deck_info, 11, RewardStyle.CYAN)
	RewardStyle.label(status, 14, RewardStyle.AMBER, false)
	for index in 3:
		var sheet := get_node("Deck/Sheet%d" % index) as Panel
		sheet.add_theme_stylebox_override("panel", RewardStyle.box(RewardStyle.PANEL_RAISED if index == 2 else RewardStyle.PANEL, Color(0.25, 0.9, 1.0, 0.35 + 0.2 * index), 2, Vector4(0, 0, 0, 0)))
	confirm.add_theme_font_override("font", RewardStyle.FONT)
	confirm.add_theme_font_size_override("font_size", 16)
	confirm.add_theme_stylebox_override("normal", RewardStyle.box(Color(0.06, 0.16, 0.24, 0.96), RewardStyle.CYAN, 2, Vector4(18, 10, 18, 10)))
	confirm.add_theme_stylebox_override("hover", RewardStyle.glow_box(Color(0.08, 0.2, 0.3, 0.98), RewardStyle.CYAN, 14.0))
	confirm.add_theme_stylebox_override("pressed", RewardStyle.glow_box(Color(0.1, 0.26, 0.38, 1.0), RewardStyle.PALE, 10.0))
	confirm.add_theme_stylebox_override("disabled", RewardStyle.box(Color(0.03, 0.04, 0.07, 0.7), Color(0.4, 0.5, 0.6, 0.25), 2, Vector4(18, 10, 18, 10)))
	confirm.add_theme_color_override("font_disabled_color", RewardStyle.MUTED)

func set_view_model(value: ProgressionRewardViewModel) -> void:
	if view_model != null and view_model.changed.is_connected(refresh): view_model.changed.disconnect(refresh)
	view_model = value
	selected.clear()
	view_model.changed.connect(refresh)
	refresh()

func refresh() -> void:
	if not is_node_ready() or view_model == null: return
	for box in [stats, choices]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	balance.text = "%.2f" % view_model.snapshot.get("style_points", 0.0)
	for row in view_model.snapshot.get("stats", []):
		var row_node := ROW_SCENE.instantiate() as UpgradeRow
		row_node.setup(row)
		row_node.pressed.connect(func(): view_model.purchase_stat(row.id))
		stats.add_child(row_node)
	var locked: bool = view_model.offer.get("selection_complete", false)
	for weapon_id in view_model.offer.get("weapons", []):
		_add_card(weapon_id, "New weapon", _weapon_name(weapon_id), "Added to your loadout for the run.", weapon_id, locked)
	for card in view_model.offer.get("upgrades", []):
		_add_card(card.upgrade_id, "Upgrade  •  Lv%d" % card.level, _pretty(card.family_id), _describe(card), &"", locked)
	_layout_cards()
	_update_deck()
	status.text = view_model.error_message
	_update_confirm()

func _add_card(id: StringName, kind: String, title: String, detail: String, weapon_id: StringName, locked: bool) -> void:
	var card := CARD_SCENE.instantiate() as RewardCard
	card.toggle_mode = true
	card.setup(id, kind, title, detail, weapon_id)
	card.disabled = locked
	card.button_pressed = selected.has(id)
	card.toggled.connect(func(pressed):
		if pressed and not selected.has(id): selected.append(id)
		elif not pressed: selected.erase(id)
		_update_confirm())
	choices.add_child(card)
	card.refresh_state()

## Staggered fan from the design: the middle card sits lower than its neighbours.
func _layout_cards() -> void:
	if not is_node_ready(): return
	var cards := choices.get_children()
	if cards.is_empty(): return
	var area := choices.size
	var layout_scale := clampf(minf(area.x / 940.0, area.y / 640.0), 0.45, 1.15)
	var card_size := CARD_SIZE * layout_scale
	var gap := CARD_GAP * layout_scale
	var count := cards.size()
	var total_width := card_size.x * count + gap * (count - 1)
	var stagger := STAGGER * layout_scale if count > 1 else 0.0
	var group_height := card_size.y + stagger
	var origin := Vector2((area.x - total_width) * 0.5, maxf(0.0, (area.y - group_height) * 0.5))
	for index in count:
		var card := cards[index] as Control
		var lowered := stagger if index % 2 == 1 else 0.0
		# Cards keep their design size and are scaled whole, so their text scales too.
		card.custom_minimum_size = CARD_SIZE
		card.size = CARD_SIZE
		card.pivot_offset = CARD_SIZE * 0.5
		card.base_scale = Vector2.ONE * layout_scale
		card.scale = card.base_scale
		card.position = origin + Vector2((card_size.x + gap) * index, lowered) - CARD_SIZE * 0.5 * (1.0 - layout_scale)

func _update_deck() -> void:
	var required: int = view_model.offer.get("required_count", 0)
	var depth: int = view_model.offer.get("depth", 0)
	var kind := "WEAPON DRAFT" if view_model.offer.get("milestone", false) else "UPGRADES"
	_deck_info.text = "LEVEL %d  •  %s\nPICK %d" % [depth, kind, required]

func _update_confirm() -> void:
	confirm.disabled = view_model.offer.get("blocked", false) or view_model.offer.get("selection_complete", false) or selected.size() != view_model.offer.get("required_count", 0)

func _weapon_name(id: StringName) -> String:
	return _pretty(id)

func _pretty(id: StringName) -> String:
	return String(id).replace("_", " ").capitalize()

func _describe(card: WeaponUpgradeDefinition) -> String:
	var parts: PackedStringArray = []
	for key in card.modifier_data:
		var value: Variant = card.modifier_data[key]
		parts.append("%s %s" % [_pretty(StringName(String(key))), str(value)])
	return ", ".join(parts) if not parts.is_empty() else "Strengthens the %s line." % _pretty(card.family_id)
