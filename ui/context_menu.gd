extends PopupMenu

signal item_context_action(action: String, item: BaseItem)

var current_item: BaseItem

func _ready():
	id_pressed.connect(_on_id_pressed)

func show_context_menu(item: BaseItem, screen_position: Vector2, context_type: String = "inventory"):
	current_item = item
	clear()
	
	# 消費アイテムかどうかの判定
	var is_consumable = item.heal > 0 or item.restore_mp > 0 or item.restore_hunger > 0 or \
		item.id in ["potion_str", "scroll_teleport", "warp_grass", "scroll_mapping"]
	
	if context_type == "floor":
		add_item("拾う", 4)
		
		# 装備可能なら装備オプション
		if item.equipment_type >= 0:
			add_item("装備", 2)
			
		# 消費アイテムなら使用オプション
		if is_consumable:
			add_item("使う", 0)
	else:
		# 消費アイテムのみ「使う」を表示
		if is_consumable:
			add_item("使う", 0)
			
		add_item("投げる", 1)
		
		if context_type == "equipment":
			add_item("外す", 3)
		elif item.equipment_type >= 0:
			# 装備可能なら装備オプション
			add_item("装備", 2)
		
	add_separator()
	add_item("キャンセル", 99)
	
	# Use popup_on_parent for proper positioning
	position = Vector2i(screen_position)
	reset_size()
	popup()

func _on_id_pressed(id: int):
	if not current_item: return
	
	match id:
		0: # Use
			item_context_action.emit("use", current_item)
		1: # Throw
			item_context_action.emit("throw", current_item)
		2: # Equip
			item_context_action.emit("equip", current_item)
		3: # Unequip
			item_context_action.emit("unequip", current_item)
		4: # Pickup
			item_context_action.emit("pickup", current_item)
		99: # Cancel
			pass
