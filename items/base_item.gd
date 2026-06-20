class_name BaseItem
extends Resource

@export var id: String
@export var display_name: String
@export var texture: Texture2D
@export var equipment_type: int = -1  # Will use EquipmentSlot.EquipmentType enum
@export var attack: int = 0
@export var defense: int = 0
@export var max_hp: int = 0
@export var max_mp: int = 0
@export var strength: int = 0
@export var dexterity: int = 0
@export var intelligence: int = 0
@export var value: int = 0  # Item value/price for trading
@export_multiline var description: String = ""
@export var shape: Array[Vector2i] = [] # An array of relative cell positions
@export var effects: Dictionary = {} # Dictionary to store item effects (e.g., {"burn": {"chance": 0.3, "duration": [3, 10], "damage": 1}})
@export var granted_skills: Array[String] = []
@export var heal: int = 0
@export var restore_mp: int = 0
@export var restore_hunger: int = 0
@export var rarity: int = 0
@export var prefix_name: String = ""
@export var suffix_name: String = ""
@export var generated_level: int = 0
@export var connectors: Array[Dictionary] = [] # {cell: Vector2i, direction: Vector2i, color: String}

var grid_position: Vector2i = Vector2i(-1, -1)

var name: String:
	get:
		return display_name
	set(value):
		display_name = value

func _init(p_id: String = "", p_name: String = "", p_texture: Texture2D = null, p_equipment_type: int = -1, p_width: int = 1, p_height: int = 1, p_description: String = "", p_shape = null):
	id = p_id
	display_name = p_name
	texture = p_texture
	equipment_type = p_equipment_type
	description = p_description

	# Clear and rebuild shape
	shape.clear()
	
	if p_shape != null and p_shape is Array and not p_shape.is_empty():
		for cell in p_shape:
			if cell is Vector2i:
				shape.append(cell)
			elif cell is Vector2:
				shape.append(Vector2i(int(cell.x), int(cell.y)))
	else:
		for y in range(p_height):
			for x in range(p_width):
				shape.append(Vector2i(x, y))


# These methods are used by the item slot
func get_icon() -> Texture2D:
	return texture

func get_equipment_type() -> int:
	return equipment_type

func get_width() -> int:
	if shape.is_empty():
		return 0
	var max_x = 0
	for cell in shape:
		if cell.x > max_x:
			max_x = cell.x
	return max_x + 1

func get_height() -> int:
	if shape.is_empty():
		return 0
	var max_y = 0
	for cell in shape:
		if cell.y > max_y:
			max_y = cell.y
	return max_y + 1

func rotate():
	"""Rotate the item 90 degrees clockwise"""
	if shape.is_empty():
		return
	
	# Calculate current dimensions
	var old_width = get_width()
	var old_height = get_height()
	
	# Rotate each cell 90 degrees clockwise: (x, y) -> (old_height - 1 - y, x)
	var new_shape: Array[Vector2i] = []
	for cell in shape:
		var new_x = old_height - 1 - cell.y
		var new_y = cell.x
		new_shape.append(Vector2i(new_x, new_y))

	var new_connectors: Array[Dictionary] = []
	for connector in connectors:
		var old_cell: Vector2i = connector.get("cell", Vector2i.ZERO)
		var old_direction: Vector2i = connector.get("direction", Vector2i.UP)
		new_connectors.append({
			"cell": Vector2i(old_height - 1 - old_cell.y, old_cell.x),
			"direction": Vector2i(-old_direction.y, old_direction.x),
			"color": str(connector.get("color", "red"))
		})

	shape = new_shape
	connectors = new_connectors

func ensure_connectors():
	if not connectors.is_empty() or shape.is_empty():
		return
	if attack == 0 and defense == 0 and max_hp == 0 and max_mp == 0 and strength == 0 and dexterity == 0 and intelligence == 0 and effects.is_empty() and granted_skills.is_empty():
		return
	var color = "yellow"
	if attack > defense and attack > 0:
		color = "red"
	elif defense > attack and defense > 0:
		color = "blue"
	elif intelligence > 0 or max_mp > 0:
		color = "purple"
	var candidates: Array[Dictionary] = []
	for cell in shape:
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if not shape.has(cell + direction):
				candidates.append({"cell": cell, "direction": direction})
	candidates.shuffle()
	var count = 2 if shape.size() >= 2 else 1
	for i in range(min(count, candidates.size())):
		connectors.append({
			"cell": candidates[i].cell,
			"direction": candidates[i].direction,
			"color": color
		})
