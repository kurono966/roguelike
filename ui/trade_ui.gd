extends Control

const GridViewScene = preload("res://ui/grid_inventory_view.tscn")
const InventoryGridData = preload("res://items/inventory_grid_data.gd")

@onready var player_inventory_container = $HBoxContainer/PlayerPanel/VBoxContainer/PlayerInventoryContainer
@onready var npc_inventory_container = $HBoxContainer/NPCPanel/VBoxContainer/NPCInventoryContainer
@onready var gold_label = $HBoxContainer/PlayerPanel/VBoxContainer/GoldLabel
@onready var npc_name_label = $HBoxContainer/NPCPanel/VBoxContainer/NPCNameLabel
@onready var close_button = $CloseButton

var player
var npc
var player_view: GridInventoryView
var npc_view: GridInventoryView
var npc_grid_data: InventoryGridData

func _ready():
	close_button.pressed.connect(_on_close_pressed)
	visibility_changed.connect(_on_visibility_changed)
	mouse_filter = MOUSE_FILTER_PASS  # Allow drag-drop events

func initialize(p_player, p_npc):
	player = p_player
	npc = p_npc
	
	if npc and "enemy_name" in npc:
		npc_name_label.text = npc.enemy_name
	else:
		npc_name_label.text = "Merchant"
	
	# Create player inventory view
	if player and player.equipment_component and player_inventory_container:
		player_view = GridViewScene.instantiate()
		player_view.set_grid_data(player.equipment_component.bag_data)
		player_view.item_clicked.connect(_on_player_item_clicked)
		player_view.trade_mode = true  # Enable trade mode
		player_view.item_trade_request.connect(_on_trade_request)
		print("Player view created, trade_mode: ", player_view.trade_mode)
		player_inventory_container.add_child(player_view)
	
	# Create NPC inventory view
	if npc_inventory_container:
		npc_grid_data = InventoryGridData.new(Vector2i(5, 6))
		_populate_npc_inventory()
		
		npc_view = GridViewScene.instantiate()
		npc_view.set_grid_data(npc_grid_data)
		npc_view.item_clicked.connect(_on_npc_item_clicked)
		npc_view.trade_mode = true  # Enable trade mode
		npc_view.item_trade_request.connect(_on_trade_request)
		print("NPC view created, trade_mode: ", npc_view.trade_mode)
		npc_inventory_container.add_child(npc_view)
	
	_update_gold_label()

func _update_gold_label():
	if player:
		gold_label.text = "Gold: %d" % player.gold

func _populate_npc_inventory():
	if not npc or not npc_grid_data:
		return

	npc.ensure_inventory_initialized()
	for item in npc.inventory_items:
		item.grid_position = Vector2i(-1, -1)
		npc_grid_data.add_item(item)

func _on_player_item_clicked(item: BaseItem, button_index: int):
	# Show item details or handle right-click
	if button_index == MOUSE_BUTTON_RIGHT:
		# Sell item to NPC
		_sell_item(item)

func _on_npc_item_clicked(item: BaseItem, button_index: int):
	# Show item details or handle right-click
	if button_index == MOUSE_BUTTON_RIGHT:
		# Buy item from NPC
		_buy_item(item)

func _on_trade_request(item: BaseItem, from_grid: GridInventoryView, to_grid: GridInventoryView):
	print("Trade request received: ", item.name, " from ", from_grid, " to ", to_grid)
	print("player_view: ", player_view, " npc_view: ", npc_view)
	
	# Prevent dragging within the same grid
	if from_grid == to_grid:
		print("Invalid trade: Cannot drag within the same grid")
		return
	
	# Determine if this is a sell or buy operation
	if from_grid == player_view and to_grid == npc_view:
		# Selling item from player to NPC
		print("Selling item: ", item.name)
		_sell_item(item)
	elif from_grid == npc_view and to_grid == player_view:
		# Buying item from NPC to player
		print("Buying item: ", item.name)
		_buy_item(item)
	else:
		print("Invalid trade direction")

func _sell_item(item_data):
	print("_sell_item called for: ", item_data.name, " at position: ", item_data.grid_position)
	if not player or not npc:
		print("ERROR: player or npc is null")
		return
	
	# Calculate sell price (50% of item value)
	var item_value = item_data.value if item_data.value > 0 else _calculate_default_value(item_data)
	var sell_price = int(item_value * 0.5)
	print("Sell price: ", sell_price, " Item value: ", item_value)
	
	# Remove item from player's bag_data
	if player.equipment_component and player.equipment_component.bag_data:
		print("Removing item from bag_data")
		print("Items in bag_data before removal: ", player.equipment_component.bag_data.items.size())
		
		# Find the actual item in bag_data by grid position
		var item_to_remove = null
		for item in player.equipment_component.bag_data.items:
			print("Checking item: ", item.name, " at ", item.grid_position, " id: ", item.id)
			if item.grid_position == item_data.grid_position and item.id == item_data.id:
				item_to_remove = item
				print("Found matching item!")
				break
		
		if item_to_remove:
			player.equipment_component.bag_data.remove_item(item_to_remove)
			print("Item removed successfully")
			print("Items in bag_data after removal: ", player.equipment_component.bag_data.items.size())
		else:
			print("ERROR: Could not find item in bag_data")
			print("Tried to find item with grid_position: ", item_data.grid_position, " id: ", item_data.id)
			return
	else:
		print("ERROR: player equipment_component or bag_data is null")
		return

	var old_gold = player.gold
	player.gold += sell_price
	print("Gold updated from ", old_gold, " to ", player.gold)
	
	# Ownership moves to the NPC, preserving the exact sold item.
	var buy_back_price = int(sell_price * 1.5)  # Buy back at 150% of sell price
	npc.add_inventory_item(item_data, buy_back_price)
	print("Added to NPC inventory: ", item_data.id, " price: ", buy_back_price)
	
	# Refresh views
	print("Refreshing views...")
	if player_view and is_instance_valid(player_view):
		print("Refreshing player_view")
		print("Player view grid_data before refresh: ", player_view.grid_data)
		print("Player view grid_data items before refresh: ", player_view.grid_data.items.size())
		player_view.refresh_view()
		print("Player view grid_data after refresh: ", player_view.grid_data)
		print("Player view grid_data items after refresh: ", player_view.grid_data.items.size())
	if npc_view and is_instance_valid(npc_view):
		print("Refreshing npc_view")
		npc_grid_data.clear()
		_populate_npc_inventory()
		npc_view.refresh_view()
	
	_update_gold_label()
	print("Gold label updated")
	
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and main_node.has_method("_end_player_turn"):
		await main_node._end_player_turn()
	
	if main_node and main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("%s を %dG で売却した" % [item_data.name, sell_price], Color(1.0, 0.85, 0.0))
	
	print("_sell_item completed")

func _calculate_default_value(item: BaseItem) -> int:
	# Calculate a default value based on item stats
	var value = 5  # Base value
	
	value += item.attack * 5
	value += item.defense * 5
	value += item.strength * 10
	value += item.dexterity * 10
	value += item.intelligence * 10
	value += item.max_hp * 2
	value += item.max_mp * 2
	
	# Add value for effects
	if item.effects and not item.effects.is_empty():
		value += 10
	
	return value

func _buy_item(item_data):
	if not player or not npc:
		return
	
	var item_value = item_data.value if item_data.value > 0 else _calculate_default_value(item_data)
	var buy_price = item_value
	
	if player.gold < buy_price:
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node and main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("ゴールドが足りない (必要: %dG)" % buy_price, Color.RED)
		return
	
	if not npc.remove_inventory_item(item_data):
		return

	if not player.pickup_item(item_data):
		npc.add_inventory_item(item_data)
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node and main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("インベントリがいっぱいで購入できない", Color.RED)
		return
	
	player.gold -= buy_price
	
	# Refresh views
	if player_view and is_instance_valid(player_view):
		player_view.refresh_view()
	if npc_view and is_instance_valid(npc_view):
		npc_grid_data.clear()
		_populate_npc_inventory()
		npc_view.refresh_view()
	
	_update_gold_label()
	
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and main_node.has_method("_end_player_turn"):
		await main_node._end_player_turn()
	
	if main_node and main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("%s を %dG で購入した" % [item_data.name, buy_price], Color(0.5, 1.0, 0.5))

func _on_close_pressed():
	visible = false

func _on_visibility_changed():
	if not visible:
		# Clean up views when UI is closed
		if player_view and is_instance_valid(player_view):
			player_view.queue_free()
			player_view = null
		if npc_view and is_instance_valid(npc_view):
			npc_view.queue_free()
			npc_view = null
		if npc_grid_data:
			npc_grid_data.clear()
			npc_grid_data = null

func _input(event):
	if not visible:
		return
	
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		visible = false
		get_viewport().set_input_as_handled()
