class_name GridInventoryView
extends Control

signal item_action(item: BaseItem)
signal item_dropped(item: BaseItem) # Emitted when an item is successfully dropped/moved
signal item_clicked(item: BaseItem, button_index: int)
signal item_activated(item: BaseItem) # Double click (or Context Use)
signal item_throw_request(item: BaseItem) # Shift+Right Click
signal item_drop_to_floor(item: BaseItem, origin_grid)
signal item_trade_request(item: BaseItem, from_grid: GridInventoryView, to_grid: GridInventoryView) # For trading between grids

const CELL_SIZE = 32

# ...

func on_item_clicked(item: BaseItem, button_index: int):
	print("GridView: Item clicked: ", item.name, " Button: ", button_index)
	item_clicked.emit(item, button_index)

func on_item_activated(item: BaseItem):
	print("GridView: Item activated: ", item.name)
	item_activated.emit(item)
# ... (omitted)


var grid_data: InventoryGridData
var is_equipment_view: bool = false
var trade_mode: bool = false  # If true, emit trade_request instead of handling drops directly

@onready var background_rect = $Background
@onready var item_container = $ItemContainer

# Connected group visual effects
var connected_group_overlays: Array = []
var pulse_timer: Timer
var pulse_phase: float = 0.0

# For drag and drop preview
# For drag and drop preview
var preview_container: Control

# Keyboard Cursor
var cursor_pos: Vector2i = Vector2i(-1, -1)
var cursor_rect: Panel

func _ready():
	# Ensure this control can receive mouse events for drag and drop
	mouse_filter = MOUSE_FILTER_PASS
	
	# キーボード入力を受け取れるようにする
	focus_mode = Control.FOCUS_ALL
	
	if background_rect:
		background_rect.mouse_filter = MOUSE_FILTER_IGNORE
	if item_container:
		item_container.mouse_filter = MOUSE_FILTER_IGNORE
		
	if not preview_container:
		preview_container = Control.new()
		preview_container.visible = false
		preview_container.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(preview_container)

	# Initialize pulse timer for connected group effects
	if not pulse_timer:
		pulse_timer = Timer.new()
		pulse_timer.wait_time = 0.1  # Update every 100ms for slower blinking
		pulse_timer.autostart = false
		pulse_timer.timeout.connect(_on_pulse_timer)
		add_child(pulse_timer)

	# Cursor for keyboard navigation - using ColorRect for better visibility
	if not cursor_rect:
		# 外側の枠（境界線）
		cursor_rect = Panel.new()
		cursor_rect.visible = false
		cursor_rect.mouse_filter = MOUSE_FILTER_IGNORE
		cursor_rect.z_index = 100  # 確実に前面に表示
		
		# スタイルで枠線を作成
		var style = StyleBoxFlat.new()
		style.bg_color = Color(1.0, 1.0, 0.0, 0.3)  # 半透明の黄色背景
		style.border_color = Color(1.0, 1.0, 0.0, 1.0)  # 完全不透明の黄色枠線
		style.set_border_width_all(3)
		# 枠線を外側に描画するためにexpand_marginを設定
		style.set_expand_margin_all(3)
		style.draw_center = true
		cursor_rect.add_theme_stylebox_override("panel", style)
		
		# item_containerの子として追加（同じ座標系）
		if item_container:
			item_container.add_child(cursor_rect)
		else:
			add_child(cursor_rect)

func set_grid_data(data: InventoryGridData):
	if grid_data:
		grid_data.grid_changed.disconnect(_on_grid_changed)
	
	grid_data = data
	if grid_data:
		grid_data.grid_changed.connect(_on_grid_changed)
		custom_minimum_size = Vector2(grid_data.size.x * CELL_SIZE, grid_data.size.y * CELL_SIZE)
		size = custom_minimum_size # Force size update
		print("GridView: Set data. Size: ", grid_data.size, " MinSize: ", custom_minimum_size)
		# Force update background size if needed, or rely on anchors
	
	queue_redraw()
	refresh_view()

func refresh_view():
	print("GridView: refresh_view called, item_container: ", item_container)
	print("GridView: self children count: ", get_child_count())
	if item_container:
		print("GridView: item_container children count: ", item_container.get_child_count())
	
	# Clear existing items (but keep cursor)
	if item_container:
		var children_to_remove = []
		for child in item_container.get_children():
			if child != cursor_rect:  # カーソルは削除しない
				children_to_remove.append(child)
		print("GridView: Removing ", children_to_remove.size(), " children from item_container")
		for child in children_to_remove:
			item_container.remove_child(child)
			child.queue_free()
	else:
		# If no item_container, clear from self
		var children_to_remove = []
		for child in get_children():
			if child != cursor_rect and child != background_rect and child != preview_container:
				children_to_remove.append(child)
		print("GridView: Removing ", children_to_remove.size(), " children from self")
		for child in children_to_remove:
			remove_child(child)
			child.queue_free()
	
	if not grid_data: return
	
	print("GridView: Creating ", grid_data.items.size(), " item views")
	# Create item views
	for item in grid_data.items:
		var item_view = _create_item_view(item)
		if item_container:
			item_container.add_child(item_view)
		else:
			add_child(item_view)
	print("GridView: refresh_view completed")

func _create_item_view(item: BaseItem) -> Control:
	# Load the draggable item script
	const DraggableItemScript = preload("res://ui/draggable_item.gd")
	
	var item_control = Control.new()
	item_control.set_script(DraggableItemScript)
	item_control.position = Vector2(item.grid_position.x * CELL_SIZE, item.grid_position.y * CELL_SIZE)
	
	var item_width = item.get_width()
	var item_height = item.get_height()
	item_control.size = Vector2(item_width * CELL_SIZE, item_height * CELL_SIZE)
	item_control.mouse_filter = MOUSE_FILTER_PASS

	var tooltip = item.name
	if item.description != "":
		tooltip += "\n" + item.description
	
	if item.attack > 0:
		tooltip += "\n攻撃力: " + str(item.attack)
	if item.defense > 0:
		tooltip += "\n防御力: " + str(item.defense)
	if item.strength > 0:
		tooltip += "\n筋力: +" + str(item.strength)
	if item.dexterity > 0:
		tooltip += "\n器用さ: +" + str(item.dexterity)
	if item.intelligence > 0:
		tooltip += "\n知力: +" + str(item.intelligence)
	if item.max_hp > 0:
		tooltip += "\n最大HP: +" + str(item.max_hp)
	if item.max_mp > 0:
		tooltip += "\n最大MP: +" + str(item.max_mp)
	if item.effects.has("crit_bonus"):
		tooltip += "\n会心率: +%d%%" % int(float(item.effects.crit_bonus) * 100.0)
	if item.effects.has("hit_bonus"):
		tooltip += "\n命中率: +%d%%" % int(float(item.effects.hit_bonus) * 100.0)
	if item.effects.has("penetration_bonus"):
		tooltip += "\n防御貫通: +%d%%" % int(float(item.effects.penetration_bonus) * 100.0)
	if item.effects.has("burn"):
		tooltip += "\n攻撃時に炎上を付与"
	item.ensure_connectors()
	if not item.connectors.is_empty():
		var connector_counts = {"red": 0, "blue": 0, "yellow": 0, "purple": 0}
		for connector in item.connectors:
			var color = str(connector.get("color", ""))
			if connector_counts.has(color):
				connector_counts[color] += 1
		tooltip += "\n端子: 赤%d 青%d 黄%d 紫%d" % [connector_counts.red, connector_counts.blue, connector_counts.yellow, connector_counts.purple]
		tooltip += "\n接続効果: 赤=攻撃 青=防御 黄=命中 紫=会心"
		
	item_control.tooltip_text = tooltip
	
	var hash_code = item.name.hash()
	var r = (hash_code & 0xFF) / 255.0
	var g = ((hash_code >> 8) & 0xFF) / 255.0
	var b = ((hash_code >> 16) & 0xFF) / 255.0
	var base_color = Color(r, g, b, 0.8)

	for cell in item.shape:
		var cell_node = ColorRect.new()
		cell_node.color = base_color
		cell_node.size = Vector2(CELL_SIZE, CELL_SIZE)
		cell_node.position = Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE)
		cell_node.mouse_filter = MOUSE_FILTER_IGNORE

		var border = ReferenceRect.new()
		border.border_color = Color.WHITE
		border.border_width = 1.0
		border.size = cell_node.size
		border.mouse_filter = MOUSE_FILTER_IGNORE
		cell_node.add_child(border)

		item_control.add_child(cell_node)
	
	if item.texture:
		var tex_rect = TextureRect.new()
		tex_rect.texture = item.texture
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.size = item_control.size
		tex_rect.mouse_filter = MOUSE_FILTER_IGNORE
		item_control.add_child(tex_rect)
	else:
		if _is_rectangular_item(item):
			var label = Label.new()
			label.text = item.name
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size = item_control.size
			label.clip_text = true
			label.add_theme_font_size_override("font_size", _get_fit_font_size_for_box(item.name, label.size))
			label.mouse_filter = MOUSE_FILTER_IGNORE
			item_control.add_child(label)
		else:
			_add_shaped_name_labels(item_control, item)

	# Set item and parent_grid properties
	item_control.item = item
	item_control.parent_grid = self
	
	item.ensure_connectors()
	if not item.connectors.is_empty():
		_add_connector_visuals(item_control, item)
	
	return item_control

func _add_connector_visuals(item_control: Control, item: BaseItem):
	item.ensure_connectors()
	var colors = {
		"red": Color(1.0, 0.2, 0.15),
		"blue": Color(0.2, 0.55, 1.0),
		"yellow": Color(1.0, 0.85, 0.15),
		"purple": Color(0.75, 0.3, 1.0)
	}
	var glow_colors = {
		"red": Color(1.0, 0.4, 0.3),
		"blue": Color(0.4, 0.7, 1.0),
		"yellow": Color(1.0, 0.95, 0.4),
		"purple": Color(0.9, 0.5, 1.0)
	}
	for connector in item.connectors:
		var cell: Vector2i = connector.get("cell", Vector2i.ZERO)
		var direction: Vector2i = connector.get("direction", Vector2i.UP)
		var color = colors.get(str(connector.get("color", "")), Color.WHITE)
		var glow_color = glow_colors.get(str(connector.get("color", "")), Color.WHITE)
		var cell_center = Vector2(cell.x * CELL_SIZE + CELL_SIZE / 2.0, cell.y * CELL_SIZE + CELL_SIZE / 2.0)
		
		# Create connector base with rounded appearance
		var connector_base = _create_connector_base(cell, direction, color)
		item_control.add_child(connector_base)
		
		# Create inner glow effect
		var inner_glow = _create_inner_glow(cell, direction, glow_color)
		item_control.add_child(inner_glow)
		
		# Create center gem/crystal
		var center_gem = _create_center_gem(cell, direction, color)
		item_control.add_child(center_gem)
		
		# Create outer ring for active connectors
		if _is_connector_active(item, connector):
			var active_ring = _create_active_ring(cell, direction, glow_color)
			item_control.add_child(active_ring)

func _create_connector_base(cell: Vector2i, direction: Vector2i, color: Color) -> Polygon2D:
	var base = Polygon2D.new()
	base.color = color.darkened(0.3)
	base.z_index = 15
	
	var cell_center = Vector2(cell.x * CELL_SIZE + CELL_SIZE / 2.0, cell.y * CELL_SIZE + CELL_SIZE / 2.0)
	var triangle_tip = cell_center + Vector2(direction) * 12.0
	
	# Create triangle shape pointing in the connector direction
	var triangle_points = []
	if direction.x != 0:
		# Horizontal triangle
		var base_width = 8.0
		var triangle_height = 10.0
		var tip_x = triangle_tip.x
		var tip_y = triangle_tip.y
		var base_x = tip_x - (direction.x * triangle_height)
		
		triangle_points = [
			Vector2(tip_x, tip_y),  # Tip
			Vector2(base_x, tip_y - base_width / 2.0),  # Bottom left
			Vector2(base_x, tip_y + base_width / 2.0)   # Bottom right
		]
	else:
		# Vertical triangle
		var base_width = 8.0
		var triangle_height = 10.0
		var tip_x = triangle_tip.x
		var tip_y = triangle_tip.y
		var base_y = tip_y - (direction.y * triangle_height)
		
		triangle_points = [
			Vector2(tip_x, tip_y),  # Tip
			Vector2(tip_x - base_width / 2.0, base_y),  # Bottom left
			Vector2(tip_x + base_width / 2.0, base_y)   # Bottom right
		]
	
	base.polygon = PackedVector2Array(triangle_points)
	return base

func _create_inner_glow(cell: Vector2i, direction: Vector2i, glow_color: Color) -> Polygon2D:
	var glow = Polygon2D.new()
	glow.color = glow_color
	glow.z_index = 16
	
	var cell_center = Vector2(cell.x * CELL_SIZE + CELL_SIZE / 2.0, cell.y * CELL_SIZE + CELL_SIZE / 2.0)
	var triangle_tip = cell_center + Vector2(direction) * 12.0
	
	# Create smaller inner triangle
	var triangle_points = []
	if direction.x != 0:
		var base_width = 5.0
		var triangle_height = 7.0
		var tip_x = triangle_tip.x
		var tip_y = triangle_tip.y
		var base_x = tip_x - (direction.x * triangle_height)
		
		triangle_points = [
			Vector2(tip_x, tip_y),
			Vector2(base_x, tip_y - base_width / 2.0),
			Vector2(base_x, tip_y + base_width / 2.0)
		]
	else:
		var base_width = 5.0
		var triangle_height = 7.0
		var tip_x = triangle_tip.x
		var tip_y = triangle_tip.y
		var base_y = tip_y - (direction.y * triangle_height)
		
		triangle_points = [
			Vector2(tip_x, tip_y),
			Vector2(tip_x - base_width / 2.0, base_y),
			Vector2(tip_x + base_width / 2.0, base_y)
		]
	
	glow.polygon = PackedVector2Array(triangle_points)
	return glow

func _create_center_gem(cell: Vector2i, direction: Vector2i, color: Color) -> Polygon2D:
	var gem = Polygon2D.new()
	gem.color = color.lightened(0.2)
	gem.z_index = 17
	
	var cell_center = Vector2(cell.x * CELL_SIZE + CELL_SIZE / 2.0, cell.y * CELL_SIZE + CELL_SIZE / 2.0)
	var triangle_tip = cell_center + Vector2(direction) * 10.0
	
	# Create small center triangle
	var triangle_points = []
	if direction.x != 0:
		var base_width = 4.0
		var triangle_height = 5.0
		var tip_x = triangle_tip.x
		var tip_y = triangle_tip.y
		var base_x = tip_x - (direction.x * triangle_height)
		
		triangle_points = [
			Vector2(tip_x, tip_y),
			Vector2(base_x, tip_y - base_width / 2.0),
			Vector2(base_x, tip_y + base_width / 2.0)
		]
	else:
		var base_width = 4.0
		var triangle_height = 5.0
		var tip_x = triangle_tip.x
		var tip_y = triangle_tip.y
		var base_y = tip_y - (direction.y * triangle_height)
		
		triangle_points = [
			Vector2(tip_x, tip_y),
			Vector2(tip_x - base_width / 2.0, base_y),
			Vector2(tip_x + base_width / 2.0, base_y)
		]
	
	gem.polygon = PackedVector2Array(triangle_points)
	return gem

func _create_active_ring(cell: Vector2i, direction: Vector2i, glow_color: Color) -> Polygon2D:
	const PulsingRingScript = preload("res://ui/pulsing_connector_ring.gd")
	
	var ring = PulsingRingScript.new()
	ring.z_index = 18
	
	var cell_center = Vector2(cell.x * CELL_SIZE + CELL_SIZE / 2.0, cell.y * CELL_SIZE + CELL_SIZE / 2.0)
	var triangle_tip = cell_center + Vector2(direction) * 12.0
	
	# Create triangle outline for active connectors
	var triangle_points = []
	if direction.x != 0:
		var base_width = 9.0
		var triangle_height = 11.0
		var tip_x = triangle_tip.x
		var tip_y = triangle_tip.y
		var base_x = tip_x - (direction.x * triangle_height)
		
		triangle_points = [
			Vector2(tip_x, tip_y),
			Vector2(base_x, tip_y - base_width / 2.0),
			Vector2(base_x, tip_y + base_width / 2.0)
		]
	else:
		var base_width = 9.0
		var triangle_height = 11.0
		var tip_x = triangle_tip.x
		var tip_y = triangle_tip.y
		var base_y = tip_y - (direction.y * triangle_height)
		
		triangle_points = [
			Vector2(tip_x, tip_y),
			Vector2(tip_x - base_width / 2.0, base_y),
			Vector2(tip_x + base_width / 2.0, base_y)
		]
	
	ring.polygon = PackedVector2Array(triangle_points)
	
	# Setup pulsing animation
	ring.setup({
		"base": glow_color.lightened(0.3),
		"bright": glow_color.lightened(0.7)
	}, randf() * PI * 2)
	
	return ring

func _is_connector_active(item: BaseItem, connector: Dictionary) -> bool:
	if not grid_data:
		return false
	var cell: Vector2i = connector.get("cell", Vector2i.ZERO)
	var direction: Vector2i = connector.get("direction", Vector2i.ZERO)
	var world_cell = item.grid_position + cell
	var neighbor = grid_data.get_item_at(world_cell.x + direction.x, world_cell.y + direction.y)
	if neighbor == null or neighbor == item:
		return false
	neighbor.ensure_connectors()
	var neighbor_local = world_cell + direction - neighbor.grid_position
	for other_connector in neighbor.connectors:
		if other_connector.get("cell", Vector2i.ZERO) == neighbor_local \
		and other_connector.get("direction", Vector2i.ZERO) == -direction \
		and str(other_connector.get("color", "")) == str(connector.get("color", "")):
			return true
	return false

func _is_rectangular_item(item: BaseItem) -> bool:
	return item.shape.size() == item.get_width() * item.get_height()

func _add_shaped_name_labels(item_control: Control, item: BaseItem):
	var runs = _get_shape_text_runs(item)
	if runs.is_empty():
		return
	var chunks = _split_text_for_runs(item.name, runs)
	for i in range(runs.size()):
		var chunk = chunks[i] if i < chunks.size() else ""
		if chunk == "":
			continue
		var run = runs[i]
		var label = Label.new()
		label.text = chunk
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(run["width"] * CELL_SIZE, CELL_SIZE)
		label.position = Vector2(run["x"] * CELL_SIZE, run["y"] * CELL_SIZE)
		label.clip_text = true
		label.add_theme_font_size_override("font_size", _get_fit_font_size(chunk, label.size.x))
		label.mouse_filter = MOUSE_FILTER_IGNORE
		item_control.add_child(label)

func _get_shape_text_runs(item: BaseItem) -> Array:
	var cells_by_y = {}
	for cell in item.shape:
		if not cells_by_y.has(cell.y):
			cells_by_y[cell.y] = []
		cells_by_y[cell.y].append(cell.x)
	
	var rows = cells_by_y.keys()
	rows.sort()
	var runs = []
	for y in rows:
		var xs = cells_by_y[y]
		xs.sort()
		var start_x = xs[0]
		var prev_x = xs[0]
		for i in range(1, xs.size()):
			if xs[i] != prev_x + 1:
				runs.append({"x": start_x, "y": y, "width": prev_x - start_x + 1})
				start_x = xs[i]
			prev_x = xs[i]
		runs.append({"x": start_x, "y": y, "width": prev_x - start_x + 1})
	
	runs.sort_custom(func(a, b):
		if a["width"] == b["width"]:
			if a["y"] == b["y"]:
				return a["x"] < b["x"]
			return a["y"] < b["y"]
		return a["width"] > b["width"]
	)
	return runs

func _split_text_for_runs(text: String, runs: Array) -> Array:
	var chunks = []
	chunks.resize(runs.size())
	for i in range(chunks.size()):
		chunks[i] = ""
	
	var total_width = 0
	for run in runs:
		total_width += run["width"]
	if total_width <= 0:
		return chunks
	
	var index = 0
	for i in range(runs.size()):
		var remaining_chars = text.length() - index
		var remaining_width = 0
		for j in range(i, runs.size()):
			remaining_width += runs[j]["width"]
		var target_len = int(ceil(float(remaining_chars) * float(runs[i]["width"]) / max(1.0, float(remaining_width))))
		if i == runs.size() - 1:
			target_len = remaining_chars
		target_len = clamp(target_len, 0, remaining_chars)
		chunks[i] = text.substr(index, target_len)
		index += target_len
	return chunks

func _get_fit_font_size(text: String, pixel_width: float) -> int:
	if text.length() <= 0:
		return 10
	var available_width = max(8.0, pixel_width - 4.0)
	var size_by_length = int(floor(available_width / float(text.length())))
	return clamp(size_by_length, 7, 12)

func _get_fit_font_size_for_box(text: String, box_size: Vector2) -> int:
	if text.length() <= 0:
		return 10
	for font_size in range(12, 6, -1):
		var chars_per_line = max(1, int(floor((box_size.x - 4.0) / float(font_size))))
		var line_count = int(ceil(float(text.length()) / float(chars_per_line)))
		var max_lines = max(1, int(floor((box_size.y - 4.0) / float(font_size + 2))))
		if line_count <= max_lines:
			return font_size
	return 7

func on_item_right_click(item: BaseItem):
	emit_signal("item_action", item)

func _can_drop_data(at_position, data):
	print("GridView: _can_drop_data called at ", at_position)
	if not grid_data: 
		print("GridView: No grid_data")
		return false
	if typeof(data) != TYPE_DICTIONARY or not data.has("item"): 
		print("GridView: Invalid data type")
		return false
	
	var item = data["item"]
	var origin_grid = data.get("origin_grid", null)
	var offset = data.get("click_grid_offset", Vector2i.ZERO)
	var grid_pos = local_to_grid(at_position) - offset
	
	print("GridView: grid_pos=", grid_pos, " item=", item.name)
	
	if grid_pos.x < 0 or grid_pos.y < 0: 
		print("GridView: Invalid grid position")
		return false
	
	preview_container.visible = true
	for child in preview_container.get_children():
		child.queue_free()

	# If moving within the same grid, ignore the item being moved
	var ignore_item = item if (origin_grid == self) else null
	var can_place = grid_data.can_place_item(item, grid_pos.x, grid_pos.y, ignore_item)
	var preview_color = Color(0, 1, 0, 0.3) if can_place else Color(1, 0, 0, 0.3)
	
	print("GridView: can_place=", can_place)
	
	for cell in item.shape:
		var preview_cell = ColorRect.new()
		preview_cell.color = preview_color
		preview_cell.size = Vector2(CELL_SIZE, CELL_SIZE)
		preview_cell.position = Vector2((grid_pos.x + cell.x) * CELL_SIZE, (grid_pos.y + cell.y) * CELL_SIZE)
		preview_cell.mouse_filter = MOUSE_FILTER_IGNORE
		preview_container.add_child(preview_cell)

	return can_place

func _drop_data(at_position, data):
	print("GridView: _drop_data called at ", at_position, " trade_mode: ", trade_mode)
	preview_container.visible = false
	var item = data["item"]
	var origin_grid = data["origin_grid"]
	var offset = data.get("click_grid_offset", Vector2i.ZERO)
	var grid_pos = local_to_grid(at_position) - offset
	
	print("GridView: Dropping ", item.name, " at ", grid_pos, " origin_grid: ", origin_grid, " self: ", self)
	
	# If this is a floor view, emit signal to place item at player position
	if is_floor_view:
		print("GridView: Dropping to floor")
		item_drop_to_floor.emit(item, origin_grid)
		return
	
	if origin_grid == self:
		print("GridView: Moving within same grid")
		var old_pos = item.grid_position
		grid_data.remove_item(item)
		
		if not grid_data.place_item(item, grid_pos.x, grid_pos.y):
			print("GridView: Failed to place, reverting")
			grid_data.place_item(item, old_pos.x, old_pos.y) # Revert
		else:
			print("GridView: Successfully moved item")
			item_dropped.emit(item)
			
	else:
		print("GridView: Moving from different grid, trade_mode: ", trade_mode)
		if trade_mode:
			# In trade mode, emit signal instead of handling drop directly
			print("GridView: Trade mode, emitting trade_request")
			item_trade_request.emit(item, origin_grid, self)
		else:
			# Normal behavior: move item between grids
			if grid_data.can_place_item(item, grid_pos.x, grid_pos.y):
				origin_grid.grid_data.remove_item(item)
				grid_data.place_item(item, grid_pos.x, grid_pos.y)
				print("GridView: Successfully transferred item")
				item_dropped.emit(item)
			else:
				print("GridView: Cannot place item")

func _notification(what):
	if what == NOTIFICATION_DRAG_END:
		if preview_container:
			preview_container.visible = false

func local_to_grid(pos: Vector2) -> Vector2i:
	# Simple floor division for grid coordinate
	var gx = int(floor(pos.x / CELL_SIZE))
	var gy = int(floor(pos.y / CELL_SIZE))
	# Clamp to valid range.
	if grid_data:
		gx = clamp(gx, 0, grid_data.size.x - 1)
		gy = clamp(gy, 0, grid_data.size.y - 1)
	return Vector2i(gx, gy)


func _draw():
	if not grid_data: return
	
	var rect = Rect2(0, 0, grid_data.size.x * CELL_SIZE, grid_data.size.y * CELL_SIZE)
	
	# Draw Background
	draw_rect(rect, Color(0.2, 0.2, 0.2, 0.8))
	
	# Draw Grid Lines
	var col = Color(0.5, 0.5, 0.5, 0.5)
	for x in range(grid_data.size.x + 1):
		draw_line(Vector2(x * CELL_SIZE, 0), Vector2(x * CELL_SIZE, grid_data.size.y * CELL_SIZE), col)
	for y in range(grid_data.size.y + 1):
		draw_line(Vector2(0, y * CELL_SIZE), Vector2(grid_data.size.x * CELL_SIZE, y * CELL_SIZE), col)

	# Draw Status Border
	if border_color.a > 0:
		draw_rect(rect, border_color, false, 4.0) # Stroke only, 4px width

var border_color: Color = Color(0, 0, 0, 0)

func set_border_style(color: Color):
	border_color = color
	queue_redraw()

signal item_pickup_request(item: BaseItem)

var is_floor_view: bool = false

func on_item_pickup_request(item: BaseItem):
	item_pickup_request.emit(item)
	
func _on_grid_changed():
	queue_redraw()
	refresh_view()
	if is_equipment_view:
		_update_connected_group_effects()

# Cursor Logic
func set_cursor_active(active: bool):
	if active:
		if cursor_pos == Vector2i(-1, -1):
			cursor_pos = Vector2i(0, 0)
		_update_cursor_rect()
	
	cursor_rect.visible = active

func set_cursor_pos(pos: Vector2i):
	if not grid_data: return
	cursor_pos.x = clamp(pos.x, 0, grid_data.size.x - 1)
	cursor_pos.y = clamp(pos.y, 0, grid_data.size.y - 1)
	_update_cursor_rect()

func move_cursor(direction: Vector2i):
	if not grid_data: return
	
	var new_pos = cursor_pos + direction
	# Wrap around or clamp? Clamping is better for inventory.
	# Or wrap if moving between inventories is handled by parent?
	# Just clamp here.
	new_pos.x = clamp(new_pos.x, 0, grid_data.size.x - 1)
	new_pos.y = clamp(new_pos.y, 0, grid_data.size.y - 1)
	
	set_cursor_pos(new_pos)

func _update_cursor_rect():
	if not grid_data: return
	var rect_pos = Vector2(cursor_pos.x * CELL_SIZE, cursor_pos.y * CELL_SIZE)
	cursor_rect.position = rect_pos
	cursor_rect.size = Vector2(CELL_SIZE, CELL_SIZE)
	
	# Highlight larger item if cursor is on one?
	var item = get_cursor_item()
	if item:
		cursor_rect.position = Vector2(item.grid_position.x * CELL_SIZE, item.grid_position.y * CELL_SIZE)
		cursor_rect.size = Vector2(item.get_width() * CELL_SIZE, item.get_height() * CELL_SIZE)

func get_cursor_item() -> BaseItem:
	if not grid_data: return null
	return grid_data.get_item_at(cursor_pos.x, cursor_pos.y)

# Connected Group Visual Effects
func _update_connected_group_effects():
	# Clear existing overlays
	for overlay in connected_group_overlays:
		if overlay and is_instance_valid(overlay):
			overlay.queue_free()
	connected_group_overlays.clear()
	
	if not is_equipment_view or not grid_data:
		if pulse_timer:
			pulse_timer.stop()
		return
	
	# Get player's equipment component to find connected groups
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	var eq_comp = player.get_node_or_null("EquipmentComponent")
	if not eq_comp:
		return
	
	var groups = eq_comp.get_connected_groups()
	if groups.is_empty():
		if pulse_timer:
			pulse_timer.stop()
		return
	
	# Create overlay for each connected group
	for group in groups:
		var overlay = _create_group_overlay(group)
		if overlay:
			connected_group_overlays.append(overlay)
			if item_container:
				item_container.add_child(overlay)
			else:
				add_child(overlay)
	
	# Start pulse timer if not already running
	if not pulse_timer.is_stopped():
		pulse_timer.stop()
	pulse_timer.start()

func _create_group_overlay(group: Array) -> Control:
	if group.is_empty():
		return null
	
	# Create a container for all item outlines and fills
	var container = Control.new()
	container.mouse_filter = MOUSE_FILTER_IGNORE
	container.z_index = 50  # Above items but below cursor
	
	# Create fill for all cells in the group
	_add_group_fill(container, group)
	
	# Create outline for each item in the group
	for item in group:
		_add_item_outline(container, item, group)
	
	return container

func _add_group_fill(container: Control, group: Array):
	# Create a fill for all cells in the connected group
	for item in group:
		var item_pos = item.grid_position
		for cell in item.shape:
			var world_pos = item_pos + cell
			var fill = ColorRect.new()
			fill.mouse_filter = MOUSE_FILTER_IGNORE
			fill.z_index = 49  # Below outlines but above items
			fill.color = Color(1.0, 0.8, 0.2, 0.2)  # Golden color with low alpha
			fill.position = Vector2(world_pos.x * CELL_SIZE, world_pos.y * CELL_SIZE)
			fill.size = Vector2(CELL_SIZE, CELL_SIZE)
			fill.set_meta("is_fill", true)
			container.add_child(fill)

func _add_item_outline(container: Control, item: BaseItem, group: Array):
	var item_pos = item.grid_position
	var group_cells = {}
	
	# Build a set of all cells occupied by items in the connected group
	for group_item in group:
		var group_item_pos = group_item.grid_position
		for cell in group_item.shape:
			var world_pos = group_item_pos + cell
			group_cells[world_pos] = true
	
	# Find outline edges for each cell
	var outline_edges = []  # Array of {cell_pos, edge_direction}
	for cell in item.shape:
		var world_pos = item_pos + cell
		
		# Check each direction for outer edge
		var directions = [
			{"dir": Vector2i.UP, "edge": "top"},
			{"dir": Vector2i.DOWN, "edge": "bottom"},
			{"dir": Vector2i.LEFT, "edge": "left"},
			{"dir": Vector2i.RIGHT, "edge": "right"}
		]
		
		for d in directions:
			var neighbor_pos = world_pos + d.dir
			# Only draw edge if neighbor is not occupied by any item in the connected group
			if not group_cells.has(neighbor_pos):
				outline_edges.append({"cell_pos": world_pos, "edge": d.edge})
	
	# Create individual edge lines for each outer edge
	for edge_data in outline_edges:
		var cell_pos = edge_data.cell_pos
		var edge = edge_data.edge
		
		var line = ColorRect.new()
		line.mouse_filter = MOUSE_FILTER_IGNORE
		line.z_index = 50
		line.color = Color(1.0, 0.8, 0.2, 0.8)  # Golden color
		
		# Position and size based on edge direction
		match edge:
			"top":
				line.position = Vector2(cell_pos.x * CELL_SIZE, cell_pos.y * CELL_SIZE)
				line.size = Vector2(CELL_SIZE, 2)
			"bottom":
				line.position = Vector2(cell_pos.x * CELL_SIZE, cell_pos.y * CELL_SIZE + CELL_SIZE - 2)
				line.size = Vector2(CELL_SIZE, 2)
			"left":
				line.position = Vector2(cell_pos.x * CELL_SIZE, cell_pos.y * CELL_SIZE)
				line.size = Vector2(2, CELL_SIZE)
			"right":
				line.position = Vector2(cell_pos.x * CELL_SIZE + CELL_SIZE - 2, cell_pos.y * CELL_SIZE)
				line.size = Vector2(2, CELL_SIZE)
		
		# Store reference for animation
		line.set_meta("is_outline", true)
		
		container.add_child(line)

func _on_pulse_timer():
	pulse_phase += 0.5  # Slower increment for slower blinking
	var alpha = 0.3 + 0.5 * (sin(pulse_phase) + 1.0) / 2.0  # Oscillate between 0.3 and 0.8
	var fill_alpha = 0.1 + 0.15 * (sin(pulse_phase) + 1.0) / 2.0  # Oscillate between 0.1 and 0.25 for fill
	
	for container in connected_group_overlays:
		if not is_instance_valid(container):
			continue
		# Iterate through all children in the container
		for child in container.get_children():
			if child.has_meta("is_outline"):
				child.color = Color(1.0, 0.8, 0.2, alpha)
			elif child.has_meta("is_fill"):
				child.color = Color(1.0, 0.8, 0.2, fill_alpha)
