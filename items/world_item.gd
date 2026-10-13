extends Node2D

class_name WorldItem

var item_data: BaseItem

@onready var label = $Label
var _bob_tween: Tween

func _ready():
	z_index = 4
	if item_data:
		_update_label()

func _exit_tree():
	if _bob_tween:
		_bob_tween.kill()
		_bob_tween = null

func set_item(data: BaseItem):
	item_data = data
	if is_inside_tree():
		_update_label()

func _update_label():
	if item_data and item_data.name:
		var ch = _get_icon_text()
		var col = _get_item_color()
		
		# Replace raw label text with pixel/ascii generated icon texture if Sprite2D exists, or render via label with custom style
		if has_node("Sprite2D"):
			var sprite = $Sprite2D
			sprite.texture = AsciiArtGenerator.create_ascii_sprite(ch, col, true)
			sprite.position = Vector2(16, 16)
			if has_node("Label"):
				$Label.visible = false
		else:
			label.text = ch
			label.modulate = col
			label.add_theme_font_size_override("font_size", 20)
			
		_start_bob()
	queue_redraw()

func _draw():
	pass

func _get_icon_text() -> String:
	if not item_data:
		return "?"
	
	if item_data.id.contains("potion"):
		return "P"
	if item_data.id.contains("ether"):
		return "E"
	if item_data.id.contains("scroll"):
		return "S"
	if item_data.id.contains("sword") or item_data.attack > 0:
		return "!"
	if item_data.id.contains("shield") or item_data.id.contains("armor") or item_data.defense > 0:
		return "#"
	if item_data.id.contains("ring"):
		return "o"
	if item_data.id.contains("gummy"):
		return "G"
	return item_data.name.substr(0, 1)

func _get_item_color() -> Color:
	if not item_data:
		return Color(0.95, 0.86, 0.30, 1.0)
	
	if item_data.id.contains("potion"):
		return Color(0.90, 0.16, 0.18, 1.0)
	if item_data.id.contains("ether"):
		return Color(0.22, 0.50, 1.0, 1.0)
	if item_data.id.contains("scroll"):
		return Color(0.92, 0.78, 0.48, 1.0)
	if item_data.id.contains("sword") or item_data.attack > 0:
		return Color(0.82, 0.84, 0.88, 1.0)
	if item_data.id.contains("shield") or item_data.id.contains("armor") or item_data.defense > 0:
		return Color(0.42, 0.70, 0.92, 1.0)
	if item_data.id.contains("ring"):
		return Color(0.96, 0.78, 0.18, 1.0)
	if item_data.id.contains("gummy"):
		return Color(0.82, 0.42, 0.95, 1.0)
	return Color(0.72, 0.95, 0.44, 1.0)

func _start_bob():
	if _bob_tween:
		_bob_tween.kill()
	_bob_tween = create_tween().set_loops()
	
	var target_node = get_node_or_null("Sprite2D") if (has_node("Sprite2D") and $Sprite2D.visible) else get_node_or_null("Label")
	if not target_node:
		return
		
	var start_y = 15.0 if target_node is Sprite2D else 6.0
	var end_y = 17.0 if target_node is Sprite2D else 8.0
	_bob_tween.tween_property(target_node, "position:y", start_y, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(target_node, "position:y", end_y, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

