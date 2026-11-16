class_name RewardCard
extends CheckButton

## One selectable reward (a weapon or a weapon upgrade). The whole card is the
## toggle; its content is non-interactive children.

const WEAPON_ICONS := {
	&"mantis_blades": preload("res://Assets/FrontEndPrototype/Textures/Mantis.png"),
	&"rocket_lance": preload("res://Assets/FrontEndPrototype/Textures/Lance.png"),
	&"greatsword": preload("res://Assets/FrontEndPrototype/Textures/Sword.png"),
	&"saber": preload("res://Assets/FrontEndPrototype/Textures/Saber.png"),
}
const ICON_SHADER: Shader = preload("res://Shaders/WeaponIcon.gdshader")
const HOVER_SCALE := 1.045

var card_id: StringName
var _kind := ""
var _title := ""
var _detail := ""
var _weapon_id: StringName = &""
var _built := false
var _chip: Label
var _art: Control
var _title_label: Label
var _detail_label: Label
var _badge: Label
var base_scale := Vector2.ONE
var _tween: Tween

func setup(id: StringName, kind: String, title: String, detail: String, weapon_id: StringName = &"") -> void:
	card_id = id
	_kind = kind
	_title = title
	_detail = detail
	_weapon_id = weapon_id
	if _built:
		_apply()

func _ready() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_states()
	_build()
	toggled.connect(_on_toggled)
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	focus_entered.connect(_hover.bind(true))
	focus_exited.connect(_hover.bind(false))
	resized.connect(func(): pivot_offset = size * 0.5)
	pivot_offset = size * 0.5
	_apply()

func _style_states() -> void:
	var margin := Vector4(0, 0, 0, 0)
	add_theme_stylebox_override("normal", RewardStyle.box(RewardStyle.PANEL, Color(0.25, 0.9, 1.0, 0.28), 2, margin))
	add_theme_stylebox_override("hover", RewardStyle.box(RewardStyle.PANEL_RAISED, Color(0.25, 0.9, 1.0, 0.7), 2, margin))
	add_theme_stylebox_override("pressed", RewardStyle.glow_box(Color(0.06, 0.16, 0.24, 0.96), RewardStyle.CYAN))
	add_theme_stylebox_override("hover_pressed", RewardStyle.glow_box(Color(0.07, 0.19, 0.28, 0.98), RewardStyle.CYAN, 18.0))
	add_theme_stylebox_override("disabled", RewardStyle.box(Color(0.03, 0.04, 0.07, 0.7), Color(0.4, 0.5, 0.6, 0.2), 2, margin))
	add_theme_stylebox_override("focus", RewardStyle.box(Color(0, 0, 0, 0), RewardStyle.PALE, 2, margin))
	# The card is the checkbox: hide the built-in tick and draw our own badge.
	var blank := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "checked_mirrored", "unchecked_mirrored", "checked_disabled_mirrored", "unchecked_disabled_mirrored"]:
		add_theme_icon_override(icon_name, blank)

func _build() -> void:
	_built = true
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_chip = Label.new()
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RewardStyle.label(_chip, 12, RewardStyle.CYAN)
	column.add_child(_chip)
	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.custom_minimum_size = Vector2(0, 96)
	_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_art)
	_title_label = Label.new()
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RewardStyle.label(_title_label, 15, RewardStyle.PALE)
	column.add_child(_title_label)
	_detail_label = Label.new()
	_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RewardStyle.label(_detail_label, 13, RewardStyle.MUTED, false)
	column.add_child(_detail_label)
	_badge = Label.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RewardStyle.label(_badge, 13, RewardStyle.MUTED)
	column.add_child(_badge)

func _apply() -> void:
	_chip.text = _kind.to_upper()
	_title_label.text = _title.to_upper()
	_detail_label.text = _detail
	for child in _art.get_children():
		_art.remove_child(child)
		child.queue_free()
	if WEAPON_ICONS.has(_weapon_id):
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = WEAPON_ICONS[_weapon_id]
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		var material := ShaderMaterial.new()
		material.shader = ICON_SHADER
		material.set_shader_parameter(&"tint", RewardStyle.PALE)
		material.set_shader_parameter(&"outline", RewardStyle.CYAN)
		material.set_shader_parameter(&"outline_size", 3.0)
		icon.material = material
		_art.add_child(icon)
	else:
		var glyph := RewardGlyph.new()
		glyph.kind = &"upgrade"
		glyph.color = RewardStyle.CYAN
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		_art.add_child(glyph)
	_update_badge()

func _update_badge() -> void:
	if disabled:
		_badge.text = "LOCKED" if not button_pressed else "SELECTED"
	else:
		_badge.text = "SELECTED" if button_pressed else "SELECT"
	_badge.add_theme_color_override("font_color", RewardStyle.CYAN if button_pressed else RewardStyle.MUTED)

func _on_toggled(_pressed: bool) -> void:
	_update_badge()

func _hover(entered: bool) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	var scale_target := base_scale * (HOVER_SCALE if entered and not disabled else 1.0)
	_tween.tween_property(self, "scale", scale_target, 0.12)
	_tween.tween_property(self, "z_index", 1 if entered else 0, 0.0)

## Called after the offer locks or unlocks the cards.
func refresh_state() -> void:
	if _built:
		_update_badge()
