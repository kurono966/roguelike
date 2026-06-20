extends Node2D

class_name WorldItem

var item_data: BaseItem

@onready var label = $Label
var _bob_tween: Tween

func _ready():
	z_index = 4
	if item_data:
		_update_label()
	_start_bob()

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
		label.text = _get_icon_text()
		label.modulate = Color.WHITE
	queue_redraw()

func _draw():
	var center = Vector2(16, 17)
	var color = _get_item_color()
	
	draw_circle(center + Vector2(1, 2), 12, Color(0, 0, 0, 0.45))
	draw_circle(center, 11, Color(0.05, 0.04, 0.03, 0.95))
	draw_circle(center, 9, color.darkened(0.18))
	draw_circle(center + Vector2(-1, -1), 7, color.lightened(0.12))
	draw_arc(center, 12, -0.2, PI + 0.3, 18, Color(1.0, 0.95, 0.55, 0.55), 1.5)
	draw_arc(center, 10, PI * 0.85, PI * 1.55, 14, Color(0, 0, 0, 0.35), 1.0)

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
	if not is_instance_valid(label):
		return
	if _bob_tween:
		_bob_tween.kill()
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(label, "position:y", 6.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(label, "position:y", 8.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
