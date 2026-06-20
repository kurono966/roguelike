extends Panel

var drag_data: Dictionary = {}
var trade_ui

func _get_drag_data(at_position):
	var preview = TextureRect.new()
	if drag_data.has("item") and drag_data.item:
		var item = drag_data.item
		if item.has_method("get_icon"):
			preview.texture = item.get_icon()
		else:
			var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
			image.fill(Color(0.5, 0.5, 0.5))
			preview.texture = ImageTexture.create_from_image(image)
		preview.size = Vector2(32, 32)
		preview.modulate = Color(1, 1, 1, 0.8)
		set_drag_preview(preview)
		return drag_data
	return null

func _can_drop_data(at_position, data):
	return data is Dictionary and data.has("item")

func _drop_data(at_position, data):
	if not _can_drop_data(at_position, data):
		return
	
	var from_player = data.get("from_player", true)
	var item_data = data.get("item")
	
	# Check if dropped on player inventory (to buy) or NPC inventory (to sell)
	var in_player_area = trade_ui.player_inventory_container.get_global_rect().has_point(get_global_mouse_position())
	var in_npc_area = trade_ui.npc_inventory_container.get_global_rect().has_point(get_global_mouse_position())
	
	if from_player and in_npc_area:
		# Selling item from player to NPC
		trade_ui._sell_item(item_data, data.get("index", -1))
	elif not from_player and in_player_area:
		# Buying item from NPC to player
		trade_ui._buy_item(item_data, data.get("price", 0))
