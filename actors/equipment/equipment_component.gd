class_name EquipmentComponent
extends Node

# Use the new grid data class
const InventoryGridData = preload("res://items/inventory_grid_data.gd")

var bag_data: InventoryGridData
var equipment_data: InventoryGridData

# Signals for UI updates
signal component_initialized

func _ready():
	# Initialize Bag (e.g., 10x4)
	bag_data = InventoryGridData.new(Vector2i(10, 4))
	
	# Initialize Equipment Grid (e.g., 6x6)
	equipment_data = InventoryGridData.new(Vector2i(6, 6))
	
	emit_signal("component_initialized")

# Helper to add item to bag (find free space)
func add_to_bag(item: BaseItem) -> bool:
	var pos = bag_data.find_free_space(item)
	if pos.x != -1:
		return bag_data.place_item(item, pos.x, pos.y)
	return false

# Helper to equip item (find free space in equipment grid)
func equip_item(item: BaseItem) -> bool:
	var pos = equipment_data.find_free_space(item)
	if pos.x != -1:
		return equipment_data.place_item(item, pos.x, pos.y)
	return false

# Helper to unequip item (move from equipment grid to bag)
func unequip_item(item: BaseItem) -> bool:
	# Try to find space in bag
	var bag_pos = bag_data.find_free_space(item)
	if bag_pos.x != -1:
		# Remove from equipment
		equipment_data.remove_item(item)
		# Add to bag
		return bag_data.place_item(item, bag_pos.x, bag_pos.y)
	return false

# Calculate total stats from items in the equipment grid
func get_total_stats() -> Dictionary:
	var stats = {
		"attack": 0,
		"defense": 0,
		"max_hp": 0,
		"max_mp": 0,
		"strength": 0,
		"dexterity": 0,
		"intelligence": 0,
		"crit_bonus": 0.0,
		"hit_bonus": 0.0,
		"penetration_bonus": 0.0
	}
	
	for item in equipment_data.items:
		item.ensure_connectors()
		stats.attack += item.attack
		stats.defense += item.defense
		# BaseItem currently only has attack/defense, but we can assume extended logic later
		# For now, just sum what we have if the Item class supports it
		if "max_hp" in item: stats.max_hp += item.max_hp
		if "max_mp" in item: stats.max_mp += item.max_mp
		if "strength" in item: stats.strength += item.strength
		if "dexterity" in item: stats.dexterity += item.dexterity
		if "intelligence" in item: stats.intelligence += item.intelligence
		stats.crit_bonus += float(item.effects.get("crit_bonus", 0.0))
		stats.hit_bonus += float(item.effects.get("hit_bonus", 0.0))
		stats.penetration_bonus += float(item.effects.get("penetration_bonus", 0.0))

	var connector_bonus = get_connector_bonus()
	stats.attack += connector_bonus.red
	stats.defense += connector_bonus.blue
	stats.hit_bonus += float(connector_bonus.yellow) * 0.03
	stats.crit_bonus += float(connector_bonus.purple) * 0.03
	
	return stats

func get_connector_bonus() -> Dictionary:
	var result = {"red": 0, "blue": 0, "yellow": 0, "purple": 0, "total": 0}
	if not equipment_data:
		return result
	var seen = {}
	for item in equipment_data.items:
		item.ensure_connectors()
		for connector in item.connectors:
			var cell: Vector2i = connector.get("cell", Vector2i.ZERO)
			var direction: Vector2i = connector.get("direction", Vector2i.ZERO)
			var world_cell = item.grid_position + cell
			var neighbor = equipment_data.get_item_at(world_cell.x + direction.x, world_cell.y + direction.y)
			if neighbor == null or neighbor == item:
				continue
			var opposite = -direction
			var neighbor_local = world_cell + direction - neighbor.grid_position
			for other_connector in neighbor.connectors:
				if other_connector.get("cell", Vector2i.ZERO) != neighbor_local:
					continue
				if other_connector.get("direction", Vector2i.ZERO) != opposite:
					continue
				var color = str(connector.get("color", ""))
				if color == str(other_connector.get("color", "")) and result.has(color):
					var endpoint_a = "%d,%d" % [world_cell.x, world_cell.y]
					var endpoint_b = "%d,%d" % [world_cell.x + direction.x, world_cell.y + direction.y]
					var endpoints = [endpoint_a, endpoint_b]
					endpoints.sort()
					var key = endpoints[0] + ":" + endpoints[1]
					if not seen.has(key):
						seen[key] = true
						result[color] += 1
						result.total += 1
	return result
