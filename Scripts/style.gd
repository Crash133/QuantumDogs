extends TextureRect
class_name StyleHud

@export var feedback: Resource = preload("res://Resources/Style/style_feedback.tres")
@export var letter_spacing: float = 80.0
var current_rank_index: int = -1
var current_rating: float = 0.0
var _rating_label: Label
var _action_list: Control
var _payout_label: Label
var _animation_player: AnimationPlayer
var _regions: Array[Rect2] = []
var _rank_text: Label
var _aux_rect: TextureRect
var _aux_text: Label
var _notice_tween: Tween
const LABELS = ["ormant", "locking", "ootstrapping", "ccelerated", "urge", ["uper", "ooled"], ["ingularity", "hift"]]

func _ready() -> void:
	_rank_text = get_node_or_null("../RichTextLabel")
	_aux_rect = get_node_or_null("../AuxRect")
	_aux_text = get_node_or_null("../AuxLabel")
	_build_regions()
	var system := get_node_or_null("../../../../StyleSystem")
	if system != null:
		attach_style_system(system, get_node_or_null("../../Label"), get_node_or_null("../../ActionList"), get_node_or_null("../../PayoutLabel"), get_node_or_null("../../../../AnimationPlayer"))

func attach_style_system(system: Node, rating_display: Label, action_display: Control, payout_display: Label, animation: AnimationPlayer) -> void:
	_rating_label = rating_display
	_action_list = action_display
	_payout_label = payout_display
	_animation_player = animation
	system.style_changed.connect(_on_style_changed)
	system.action_tally_changed.connect(_on_action_tally_changed)
	system.style_points_awarded.connect(_on_style_points_awarded)
	system.damage_penalty_applied.connect(_on_damage_penalty_applied)

func format_action_entries(entries: Array) -> PackedStringArray:
	var rows := PackedStringArray()
	for entry in entries:
		if int(entry.get("count", 0)) > 0:
			rows.append("%d x %s" % [entry.count, entry.display_label])
	return rows

func _on_style_changed(rating: float, rank_index: int, normalized: float) -> void:
	var previous := current_rank_index
	current_rank_index = rank_index
	visible = rank_index >= 0
	current_rating = rating
	if _rating_label != null:
		_rating_label.text = str(ceili(rating))
	if material != null:
		material.set("shader_parameter/fill_perc", normalized)
		material.set("shader_parameter/alpha_mult", 1.0 if rank_index >= 0 else 0.0)
	_show_rank()
	if rank_index > previous:
		_play(&"style_upgrade_2")
	elif rank_index < previous:
		_play(&"style_downgrade")

func _on_action_tally_changed(entries: Array) -> void:
	if _action_list == null:
		return
	var rows := format_action_entries(entries)
	_action_list.set("text", "\n".join(rows))
	_action_list.visible = not rows.is_empty()
	if not rows.is_empty() and is_inside_tree():
		var pulse := create_tween()
		pulse.tween_property(_action_list, "scale", Vector2(1.06, 1.06), float(feedback.get("pulse_up")))
		pulse.tween_property(_action_list, "scale", Vector2.ONE, float(feedback.get("pulse_down")))

func _on_style_points_awarded(award: StyleAward) -> void:
	if _payout_label == null:
		return
	var amount := str(roundi(award.amount)) if is_equal_approx(award.amount, roundf(award.amount)) else String.num(award.amount, 2)
	_payout_label.text = "+%s STYLE POINTS" % amount
	_payout_label.modulate = Color.WHITE
	_payout_label.show()
	if is_inside_tree():
		if _notice_tween != null:
			_notice_tween.kill()
		_notice_tween = create_tween()
		_notice_tween.tween_interval(float(feedback.get("award_hold")))
		_notice_tween.tween_property(_payout_label, "modulate:a", 0.0, float(feedback.get("award_fade")))
		_notice_tween.tween_callback(_payout_label.hide)

func _on_damage_penalty_applied(_rating: float, _rank: int) -> void:
	modulate = Color(1.0, 0.35, 0.35, 1.0)
	if is_inside_tree():
		create_tween().tween_property(self, "modulate", Color.WHITE, float(feedback.get("damage_recover")))

func _build_regions() -> void:
	if not texture is AtlasTexture or texture.atlas == null:
		return
	var image: Image = texture.atlas.get_image()
	if image == null:
		return
	for index in range(7):
		var cell := image.get_region(Rect2i(300 * index, 0, 300, 300))
		var bounds := cell.get_used_rect()
		_regions.append(Rect2(Vector2(300 * index, 0) + Vector2(bounds.position), Vector2(bounds.size)))

func _show_rank() -> void:
	if _rank_text == null:
		return
	_rank_text.visible = current_rank_index >= 0
	if _aux_rect != null:
		_aux_rect.hide()
	if _aux_text != null:
		_aux_text.hide()
	if current_rank_index < 0 or current_rank_index >= LABELS.size():
		return
	var index := current_rank_index
	if index > 4:
		_rank_text.text = LABELS[index][0]
		_aux_text.text = LABELS[index][1]
		_aux_text.show()
		if _regions.size() > index:
			texture.region = _regions[4]
			_aux_rect.texture.region = _regions[index]
			_aux_rect.show()
	else:
		_rank_text.text = LABELS[index]
		if _regions.size() > index:
			texture.region = _regions[index]

func _play(animation: StringName) -> void:
	if _animation_player != null and _animation_player.has_animation(animation):
		_animation_player.play(animation)

# Kept for the existing approved AnimationPlayer tracks and connections.
func pause_decay() -> void:
	pass
func unpause_decay() -> void:
	pass
func next_level() -> void:
	_show_rank()
func prev_level() -> void:
	_show_rank()
func level_text() -> void:
	_show_rank()
func _on_animation_player_animation_finished(_name: StringName) -> void:
	if material != null:
		material.set("shader_parameter/alpha_mult", 1.0 if current_rank_index >= 0 else 0.0)
func _on_animation_player_animation_started(_name: StringName) -> void:
	pass
