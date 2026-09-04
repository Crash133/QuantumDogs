extends TextureRect

@export var mult := 1
@export var decay_mult := 10
@export var progression := 100
@export var decay: Curve
@export var letter_spacing: float = -15.0

@onready var anim = $"../../../../AnimationPlayer"
@onready var text = $"../RichTextLabel"
@onready var aux_rect = $"../AuxRect"
@onready var aux_text = $"../AuxLabel"
@onready var style_label = $"../../Label"

var style = 0.0
var raw_style = 0.0
var ds = 0.0
var idle_time = 0.0
var level = -1

var decay_paused := false

var rects: Array[Rect2] = []
var param: Array[Vector2] = []
var labels := [
	"ormant",
	"locking",
	"ootstrapping",
	"ccelerated",
	"urge",
	["uper", "ooled"],
	["ingularity", "hift"]
]

func _ready() -> void:
	for i in range(7):
		var result := calculate_sprite_data(Rect2(300 * i, 0, 300, 300))

		rects.append(result.rect)
		param.append(result.y_range)
		
	print(rects)
		

func calculate_sprite_data(region_rect: Rect2) -> Dictionary:
	var base_texture := texture
	var image: Image

	if base_texture is AtlasTexture:
		var full_image: Image = base_texture.atlas.get_image()
		image = full_image.get_region(Rect2i(region_rect))
	else:
		image = base_texture.get_image()

	if image == null or image.is_empty():
		return {
			"rect": region_rect,
			"y_range": Vector2(0.0, 1.0)
		}

	var width := image.get_width()
	var height := image.get_height()

	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1

	# Find complete alpha bounding box
	for y in range(height):
		for x in range(width):
			if image.get_pixel(x, y).a > 0.9:
				min_x = min(min_x, x)
				min_y = min(min_y, y)
				max_x = max(max_x, x)
				max_y = max(max_y, y)

	# Completely transparent
	if max_x == -1:
		return {
			"rect": Rect2(region_rect.position, Vector2.ZERO),
			"y_range": Vector2(0.0, 0.0)
		}

	# Tight rectangle in atlas coordinates
	var tight_rect := Rect2(
		region_rect.position + Vector2(min_x, min_y),
		Vector2(
			max_x - min_x + 1,
			max_y - min_y + 1
		)
	)

	# Since tight_rect contains the entire alpha bounding box,
	# these are technically almost exactly 0 and 1.
	var tight_height := max_y - min_y + 1

	var i := 0.0
	var m := 1.0

	return {
		"rect": tight_rect,
		"y_range": Vector2(i, m)
	}

var hide_tween: Tween
func level_text() -> void:
	var t = labels[level]
	
	offset_transform_position.x = 0
	if t is Array:
		text.text = t[0]
		text.show()
		aux_text.text = t[1]
		aux_text.show()
	else:
		text.text = t
		text.show()
		aux_rect.hide()
		aux_text.hide()
	
	# Kill the previous tween if it exists and is active
	if hide_tween and hide_tween.is_running():
		hide_tween.kill()

	# Create a new tween and assign it to the member variable
	hide_tween = get_tree().create_tween()
	hide_tween.tween_interval(2.0)

	hide_tween.tween_callback(func():
		if t is Array:
			offset_transform_position.x = letter_spacing
		else:
			offset_transform_position.x = 0
		
		text.hide()
		aux_text.hide()
	)	
		

var last_nlevel := 0
func _process(delta: float) -> void:
	idle_time += delta
	var d = decay.sample(idle_time)
	
	if not decay_paused:
		style -= d * decay_mult * delta
		style = max(0, style)
	
	var nlevel = floori(style / (progression))
	
	if style == 0:
		level = -1
		nlevel = -1
	
	if level > -1:
		show_level()
	
	var fill = floori(style) % (progression + 1)
	fill /= float(progression)
	
	style_label.text = str(ceili(raw_style))
	
	if (nlevel > level):
		anim.play("style_upgrade_2")
	elif (nlevel < level):
		anim.play("style_downgrade")
	
	material.set("shader_parameter/fill_perc", fill)
	material.set("shader_parameter/alpha_mult", 1.0 if level >= 0 else 0.0)
	
	
	
func show_level():
	if level > 4:
		texture.region = rects[4]
		size = rects[4].size

		aux_rect.texture.region = rects[level]
		aux_rect.size = rects[level].size

		aux_rect.show()
	else:
		aux_rect.hide()
		aux_text.hide()

		texture.region = rects[level]
		size = rects[level].size
		
	
func pause_decay():
	decay_paused = true

func unpause_decay():
	decay_paused = false
	idle_time = 0

func next_level():
	level += 1
	
func prev_level():
	level -= 1
	level = max(level, 0)

func _on_player_dealt_damage(hit: HitData) -> void:
	var d = hit.damage * mult
	style += d
	raw_style += d
	style = min(style, (len(rects)) * progression )
	idle_time = 0


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if level > 4 and aux_text.hidden and anim_name == 'style_downgrade':
		offset_transform_position.x = letter_spacing
	else:
		offset_transform_position.x = 0
		
	


func _on_animation_player_animation_started(anim_name: StringName) -> void:
	offset_transform_position.x = 0
