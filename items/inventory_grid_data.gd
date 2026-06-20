class_name InventoryGridData
extends RefCounted

signal grid_changed

var size: Vector2i
var items: Array[BaseItem] = []

# 2D array storing references to items. null means empty.
# dimensions: [x][y]
var _grid: Array = []

func _init(p_size: Vector2i):
	size = p_size
	_init_grid()

func _init_grid():
	_grid.resize(size.x)
	for x in range(size.x):
		_grid[x] = []
		_grid[x].resize(size.y)
		for y in range(size.y):
			_grid[x][y] = null

func clear():
	items.clear()
	_init_grid()
	grid_changed.emit()

func can_place_item(item: BaseItem, x: int, y: int, ignore_item: BaseItem = null) -> bool:
	if x < 0 or y < 0: return false
	
	for cell in item.shape:
		var check_x = x + cell.x
		var check_y = y + cell.y
		
		if check_x < 0 or check_y < 0 or check_x >= size.x or check_y >= size.y:
			return false
		
		var occupying_item = _grid[check_x][check_y]
		if occupying_item != null and occupying_item != ignore_item:
			return false
			
	return true

func place_item(item: BaseItem, x: int, y: int) -> bool:
	if not can_place_item(item, x, y):
		return false
	
	item.grid_position = Vector2i(x, y)
	items.append(item)
	
	for cell in item.shape:
		var place_x = x + cell.x
		var place_y = y + cell.y
		_grid[place_x][place_y] = item
			
	grid_changed.emit()
	return true

func add_item(item: BaseItem) -> bool:
	# If item has a valid grid position, try placing it there
	if item.grid_position.x != -1 and item.grid_position.y != -1:
		if place_item(item, item.grid_position.x, item.grid_position.y):
			return true
	
	# Otherwise, find free space
	var free_pos = find_free_space(item)
	if free_pos.x != -1:
		return place_item(item, free_pos.x, free_pos.y)
	
	return false

func remove_item(item: BaseItem) -> bool:
	var index = items.find(item)
	if index == -1:
		return false
	
	items.remove_at(index)
	var x = item.grid_position.x
	var y = item.grid_position.y
	
	for cell in item.shape:
		var clear_x = x + cell.x
		var clear_y = y + cell.y
		if clear_x >= 0 and clear_y >= 0 and clear_x < size.x and clear_y < size.y:
			if _grid[clear_x][clear_y] == item:
				_grid[clear_x][clear_y] = null
	
	item.grid_position = Vector2i(-1, -1)
	grid_changed.emit()
	return true

func get_item_at(x: int, y: int) -> BaseItem:
	if x < 0 or x >= size.x or y < 0 or y >= size.y:
		return null
	return _grid[x][y]

# Find the first available position for an item
func find_free_space(item: BaseItem) -> Vector2i:
	for y in range(size.y):
		for x in range(size.x):
			if can_place_item(item, x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

# Calculate how many separate clusters of items exist on the grid
# 1 cluster = Organized, > 2 = Messy
func get_cluster_count() -> int:
	if items.is_empty():
		return 0
		
	var visited = {} # dictionary of visited item instances
	var clusters = 0
	
	for item in items:
		if visited.has(item):
			continue
			
		clusters += 1
		# Flood fill (BFS) to find all connected items
		var stack = [item]
		visited[item] = true
		
		while not stack.is_empty():
			var current_item = stack.pop_back()
			
			# Check neighbors of this item's occupied cells
			for cell in current_item.shape:
				var gx = current_item.grid_position.x + cell.x
				var gy = current_item.grid_position.y + cell.y
				
				# Check 4 neighbors
				var neighbors = [
					Vector2i(gx + 1, gy),
					Vector2i(gx - 1, gy),
					Vector2i(gx, gy + 1),
					Vector2i(gx, gy - 1)
				]
				
				for n in neighbors:
					if n.x >= 0 and n.x < size.x and n.y >= 0 and n.y < size.y:
						var neighbor_item = _grid[n.x][n.y]
						if neighbor_item != null and neighbor_item != current_item and not visited.has(neighbor_item):
							visited[neighbor_item] = true
							stack.append(neighbor_item)
	
	return clusters

# Check if all items form a single rectangular block with no holes (Perfectly organized)
func is_tightly_packed() -> bool:
	if items.is_empty():
		return true
		
	var min_x = size.x
	var min_y = size.y
	var max_x = -1
	var max_y = -1
	var total_cells = 0
	
	for item in items:
		for cell in item.shape:
			var gx = item.grid_position.x + cell.x
			var gy = item.grid_position.y + cell.y
			
			min_x = min(min_x, gx)
			min_y = min(min_y, gy)
			max_x = max(max_x, gx)
			max_y = max(max_y, gy)
			total_cells += 1
			
	if max_x == -1: return true # Should not happen if items is not empty
	
	# Calculate area of the bounding box
	var width = max_x - min_x + 1
	var height = max_y - min_y + 1
	var bounding_area = width * height
	
	# If occupied area equals bounding box area, it's a perfect rectangle
	return total_cells == bounding_area

func get_packing_density() -> float:
	if items.is_empty():
		return 1.0
		
	var min_x = size.x
	var min_y = size.y
	var max_x = -1
	var max_y = -1
	var total_cells = 0
	
	for item in items:
		for cell in item.shape:
			var gx = item.grid_position.x + cell.x
			var gy = item.grid_position.y + cell.y
			
			min_x = min(min_x, gx)
			min_y = min(min_y, gy)
			max_x = max(max_x, gx)
			max_y = max(max_y, gy)
			total_cells += 1
			
	if max_x == -1: return 1.0
	
	var width = max_x - min_x + 1
	var height = max_y - min_y + 1
	var bounding_area = float(width * height)
	
	if bounding_area == 0: return 0.0
	return float(total_cells) / bounding_area

func get_total_crit_bonus() -> float:
	var bonus = 0.0
	
	# Organization Bonus: +5% if tightly packed
	if not items.is_empty() and is_tightly_packed():
		bonus += 0.05
		
	# Item Effects Bonus (Charms, etc.)
	for item in items:
		if item.effects.has("crit_bonus"):
			bonus += item.effects["crit_bonus"]
			
	return bonus

func scramble() -> Array:
	var dropped_items = []
	var temp_items = items.duplicate()
	items.clear()
	_init_grid() # Clear grid
	
	temp_items.shuffle()
	
	for item in temp_items:
		item.grid_position = Vector2i(-1, -1)
		var placed = false
		
		# Try random positions first to create a "messy" look
		for i in range(20): # Try 20 times to find a random spot
			var rand_x = randi() % size.x
			var rand_y = randi() % size.y
			if place_item(item, rand_x, rand_y):
				placed = true
				break
		
		# If random placement failed, try standard packing
		if not placed:
			if not add_item(item):
				# If fails, try rotating
				item.rotate()
				if not add_item(item):
					item.rotate() # Rotate back
					item.rotate()
					item.rotate()
					dropped_items.append(item)
				
	grid_changed.emit()
	return dropped_items
