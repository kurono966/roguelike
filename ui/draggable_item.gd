extends Control

var item: BaseItem
var parent_grid: GridInventoryView

var _pressed_time = 0
var _is_dragging = false
const LONG_PRESS_THRESHOLD = 300 # ms (Slightly shorter than 500 for better feel)

const CELL_SIZE = 32

func _get_drag_data(at_position):
	if not item: 
		print("DraggableItem: No item set!")
		return null
	
	_is_dragging = true
	print("DraggableItem: Starting drag for ", item.name)
	
	# Create a custom preview that matches the item's shape
	var preview = Control.new()
	var hash_code = item.name.hash()
	var r = (hash_code & 0xFF) / 255.0
	var g = ((hash_code >> 8) & 0xFF) / 255.0
	var b = ((hash_code >> 16) & 0xFF) / 255.0
	var base_color = Color(r, g, b, 0.5)
	
	for cell in item.shape:
		var cell_preview = ColorRect.new()
		cell_preview.color = base_color
		cell_preview.size = Vector2(CELL_SIZE, CELL_SIZE)
		cell_preview.position = Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE)
		preview.add_child(cell_preview)

	# No offset needed – preview will be positioned by the drag system
	set_drag_preview(preview)
	
	# Return drag data with zero offset
	return {
		"item": item,
		"origin_grid": parent_grid,
		"click_grid_offset": Vector2i.ZERO
	}

func _can_drop_data(at_position, data):
	print("DraggableItem: _can_drop_data - forwarding to parent_grid")
	if not parent_grid:
		return false
	# Convert to parent grid's local position
	# global_position is the global position of this control
	# at_position is relative to this control
	var global_pos = global_position + at_position
	var parent_local_pos = global_pos - parent_grid.global_position
	return parent_grid._can_drop_data(parent_local_pos, data)

func _drop_data(at_position, data):
	print("DraggableItem: _drop_data - forwarding to parent_grid")
	if not parent_grid:
		return
	# Convert to parent grid's local position
	var global_pos = global_position + at_position
	var parent_local_pos = global_pos - parent_grid.global_position
	parent_grid._drop_data(parent_local_pos, data)

func _has_point(point: Vector2) -> bool:
	if not item: return false
	
	var grid_x = int(floor(point.x / CELL_SIZE))
	var grid_y = int(floor(point.y / CELL_SIZE))
	
	for cell in item.shape:
		if cell.x == grid_x and cell.y == grid_y:
			return true
	return false

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_context_menu()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed_time = Time.get_ticks_msec()
				_is_dragging = false
			elif not event.pressed: # Released
				# If duration is short and we haven't started a full drag operation
				# Godot's _get_drag_data fires when threshold is met.
				var duration = Time.get_ticks_msec() - _pressed_time
				if duration < 300 and not _is_dragging:
					# This is a click
					print("DraggableItem: Clicked (Time: ", duration, "ms) ", item.name)
					if parent_grid and parent_grid.has_method("on_item_clicked"):
						parent_grid.on_item_clicked(item, event.button_index)
				_is_dragging = false

func _show_context_menu():
	var menu_res = load("res://ui/context_menu.tscn")
	if menu_res:
		var menu = menu_res.instantiate()
		get_tree().root.add_child(menu)
		menu.item_context_action.connect(_on_context_action)
		
		var context_type = "inventory"
		if parent_grid:
			if "is_floor_view" in parent_grid and parent_grid.is_floor_view:
				context_type = "floor"
			elif "is_equipment_view" in parent_grid and parent_grid.is_equipment_view:
				context_type = "equipment"
			
		# Use viewport mouse position for proper coordinate system
		var mouse_pos = get_viewport().get_mouse_position()
		menu.show_context_menu(item, mouse_pos, context_type)
		menu.popup_hide.connect(func(): menu.queue_free())

func _on_context_action(action: String, action_item: BaseItem):
	if action_item != item: return
	
	if action == "use":
		print("ContextMenu: Use ", item.name)
		if parent_grid and parent_grid.has_method("on_item_activated"):
			parent_grid.on_item_activated(item)
	elif action == "throw":
		print("ContextMenu: Throw ", item.name)
		if parent_grid:
			parent_grid.emit_signal("item_throw_request", item)
	elif action == "equip" or action == "unequip":
		print("ContextMenu: ", action, " ", item.name)
		if parent_grid and parent_grid.has_method("on_item_right_click"):
			parent_grid.on_item_right_click(item)
	elif action == "pickup":
		print("ContextMenu: Pickup ", item.name)
		if parent_grid and parent_grid.has_method("on_item_pickup_request"):
			parent_grid.on_item_pickup_request(item)
