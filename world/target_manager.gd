class_name TargetManager
extends Node

var main_node: Node2D
var tile_map: TileMap

# Targeting State
var targeting_item = null
var targeting_skill = null
var targeting_is_ranged_weapon = false
var targeting_range = 0
var source_pos = Vector2.ZERO
var line_mode = false # For raycasts like wands/arrows
var aoe_radius = 0 # For explosions
var targeting_look: bool = false
var targeting_talk: bool = false

# Cursor
var keyboard_target_grid = Vector2i.ZERO

# Visuals
var cursor_sprite: Sprite2D
var path_line: Line2D
var aoe_sprite: Sprite2D # Optional
var pointer_polygon: Polygon2D

const TILE_SIZE = 32 # Assuming 32, or use MapDefinitions

func setup(main: Node2D):
	main_node = main
	tile_map = main.tile_map
	_create_visuals()

func _create_visuals():
	# Cursor - Simple box or crosshair
	cursor_sprite = Sprite2D.new()
	# Use a placeholder texture or create one on the fly if needed. 
	# For now, create a simple ColorRect based sprite or load if available.
	# We'll use a simple CanvasItem draw in _draw instead? No, Sprite is easier to manage.
	# Let's try to load the common selector if it exists, otherwise visible rect.
	# Assuming 'res://assets/ui/selector.png' exists. If not, we use a colored rect.
	if ResourceLoader.exists("res://assets/ui/selector.png"):
		cursor_sprite.texture = load("res://assets/ui/selector.png")
	else:
		# Create a placeholder texture
		var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 0, 0.5))
		cursor_sprite.texture = ImageTexture.create_from_image(img)
		
	cursor_sprite.visible = false
	cursor_sprite.z_index = 100 # On top
	add_child(cursor_sprite)
	
	# Dynamic target pointer (▼)
	pointer_polygon = Polygon2D.new()
	# Relative coordinates: tip is at (0, 0), top-left at (-6, -10), top-right at (6, -10)
	pointer_polygon.polygon = PackedVector2Array([
		Vector2(-6, -10),
		Vector2(6, -10),
		Vector2(0, 0)
	])
	pointer_polygon.color = Color(1.0, 0.25, 0.25) # Default Red
	pointer_polygon.z_index = 1 # Drawn above the cursor sprite
	
	# Add black outline to the pointer for high contrast
	var pointer_outline = Line2D.new()
	pointer_outline.points = PackedVector2Array([
		Vector2(-6, -10),
		Vector2(6, -10),
		Vector2(0, 0),
		Vector2(-6, -10)
	])
	pointer_outline.width = 1.0
	pointer_outline.default_color = Color(0, 0, 0, 0.8) # Semi-transparent black outline
	pointer_polygon.add_child(pointer_outline)
	
	cursor_sprite.add_child(pointer_polygon)
	
	# Path Line
	path_line = Line2D.new()
	path_line.width = 2.0
	path_line.default_color = Color(1, 0, 0, 0.5)
	path_line.visible = false
	path_line.z_index = 99
	add_child(path_line)

func start_targeting(source_position: Vector2, range_val: int, item=null, skill_id=null, is_ranged=false, aoe=0, line=false):
	targeting_item = item
	targeting_skill = skill_id
	targeting_is_ranged_weapon = is_ranged
	targeting_range = range_val
	source_pos = source_position
	aoe_radius = aoe
	line_mode = line
	
	# Initial cursor position logic
	var player_grid = tile_map.local_to_map(source_position)
	keyboard_target_grid = player_grid
	
	# Auto-target nearest visible enemy
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest_enemy = null
	var min_dist_sq = 999999.0
	
	for enemy in enemies:
		if is_instance_valid(enemy) and main_node.has_method("_can_player_recognize_entity") and main_node._can_player_recognize_entity(enemy):
			var e_grid = tile_map.local_to_map(enemy.position)
			var d_sq = Vector2(player_grid).distance_squared_to(Vector2(e_grid))
			
			if d_sq < min_dist_sq:
				min_dist_sq = d_sq
				nearest_enemy = enemy
	
	if nearest_enemy:
		keyboard_target_grid = tile_map.local_to_map(nearest_enemy.position)
		
	_update_visuals()
	
	# Set game state in Main
	main_node.set("_current_game_state", 2) 
	
	print("Targeting started. Range: ", range_val)

func start_look_targeting(source_position: Vector2):
	targeting_look = true
	source_pos = source_position
	
	# Initial cursor position logic (player's tile)
	var player_grid = tile_map.local_to_map(source_position)
	keyboard_target_grid = player_grid
	
	# Look for nearest target in "enemies", "npcs", "allies"
	var targets = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("npcs") + get_tree().get_nodes_in_group("allies")
	var nearest_target = null
	var min_dist_sq = 999999.0
	
	for target in targets:
		if is_instance_valid(target) and target != main_node.player:
			if main_node.has_method("_can_player_recognize_entity") and main_node._can_player_recognize_entity(target):
				var t_grid = tile_map.local_to_map(target.position)
				var d_sq = Vector2(player_grid).distance_squared_to(Vector2(t_grid))
				
				if d_sq < min_dist_sq:
					min_dist_sq = d_sq
					nearest_target = target
	
	if nearest_target:
		keyboard_target_grid = tile_map.local_to_map(nearest_target.position)
		
	_update_visuals()
	
	# Set game state to TARGETING (2)
	main_node.set("_current_game_state", 2)
	
	# Force updating tooltip immediately so user sees the info of the focused target right away!
	main_node._update_tooltip()
	
	print("Look targeting started.")

func start_talk_targeting(source_position: Vector2):
	targeting_talk = true
	source_pos = source_position
	
	# Initial cursor position logic (player's tile or nearest NPC/Ally)
	var player_grid = tile_map.local_to_map(source_position)
	keyboard_target_grid = player_grid
	
	# Look for nearest target in "npcs" and "allies"
	var targets = get_tree().get_nodes_in_group("npcs") + get_tree().get_nodes_in_group("allies")
	var nearest_target = null
	var min_dist_sq = 999999.0
	
	for target in targets:
		if is_instance_valid(target) and target != main_node.player:
			if main_node.has_method("_can_player_recognize_entity") and main_node._can_player_recognize_entity(target):
				var t_grid = tile_map.local_to_map(target.position)
				var d_sq = Vector2(player_grid).distance_squared_to(Vector2(t_grid))
				
				if d_sq < min_dist_sq:
					min_dist_sq = d_sq
					nearest_target = target
	
	if nearest_target:
		keyboard_target_grid = tile_map.local_to_map(nearest_target.position)
		
	_update_visuals()
	
	# Set game state to TARGETING (2)
	main_node.set("_current_game_state", 2)
	
	# Force updating tooltip
	if main_node.has_method("_update_tooltip"):
		main_node._update_tooltip()
	
	print("Talk targeting started.")

func cancel_targeting():
	targeting_item = null
	targeting_skill = null
	targeting_look = false
	targeting_talk = false
	cursor_sprite.visible = false
	path_line.visible = false
	
	# Restore Game State to PLAYER_TURN (0)
	main_node.set("_current_game_state", 0) 
	
	# Clear tooltip position override and hide tooltip
	if GameUI:
		if GameUI.has_method("hide_tooltip"):
			GameUI.hide_tooltip()
		if "tooltip_override_position" in GameUI:
			GameUI.tooltip_override_position = null
			
	print("Targeting cancelled.")

func move_cursor(direction: Vector2i):
	keyboard_target_grid += direction
	_update_visuals()

func update_cursor_mouse(global_pos: Vector2):
	keyboard_target_grid = tile_map.local_to_map(global_pos)
	_update_visuals()

func _update_visuals():
	cursor_sprite.visible = true
	var target_pixel_pos = Vector2(keyboard_target_grid) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	cursor_sprite.position = target_pixel_pos
	
	if line_mode:
		path_line.visible = true
		path_line.clear_points()
		# From source center
		var src_center = source_pos + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
		path_line.add_point(src_center)
		path_line.add_point(target_pixel_pos)
		
		# Valid range color check
		var dist = Vector2(tile_map.local_to_map(source_pos)).distance_to(Vector2(keyboard_target_grid))
		if dist > targeting_range:
			path_line.default_color = Color(0.5, 0.5, 0.5, 0.5) # Out of range
			cursor_sprite.modulate = Color(0.5, 0.5, 0.5, 0.5)
		else:
			path_line.default_color = Color(1, 0, 0, 0.5)
			cursor_sprite.modulate = Color(1, 1, 0, 0.5)
	else:
		path_line.visible = false

	# Update pointer color based on context
	if is_instance_valid(pointer_polygon):
		if targeting_talk:
			pointer_polygon.color = Color(0.25, 1.0, 0.25) # Green for talk
		elif targeting_look:
			# If looking, check what's there
			var target_entity = null
			for entity in get_tree().get_nodes_in_group("entities"):
				if is_instance_valid(entity) and entity != main_node.player and not entity.is_in_group("items"):
					var e_grid = tile_map.local_to_map(entity.position)
					if e_grid == keyboard_target_grid:
						target_entity = entity
						break
			
			if target_entity:
				if target_entity.is_in_group("enemies"):
					pointer_polygon.color = Color(1.0, 0.25, 0.25) # Red for enemies
				elif target_entity.is_in_group("allies") or target_entity.is_in_group("npcs"):
					pointer_polygon.color = Color(0.25, 1.0, 0.25) # Green for allies
				else:
					pointer_polygon.color = Color(1.0, 0.85, 0.1) # Gold
			else:
				# Check if there is an item
				var has_item = false
				for item in get_tree().get_nodes_in_group("items"):
					if is_instance_valid(item):
						var i_grid = tile_map.local_to_map(item.position)
						if i_grid == keyboard_target_grid:
							has_item = true
							break
				if has_item:
					pointer_polygon.color = Color(1.0, 0.85, 0.1) # Gold for items
				else:
					pointer_polygon.color = Color(0.2, 0.75, 1.0) # Blue/cyan for empty ground
		else:
			# General skill/item/ranged weapon targeting
			# Check if target is out of range
			var out_of_range = false
			if targeting_range > 0:
				var dist = Vector2(tile_map.local_to_map(source_pos)).distance_to(Vector2(keyboard_target_grid))
				if dist > targeting_range:
					out_of_range = true
			
			if out_of_range:
				pointer_polygon.color = Color(0.5, 0.5, 0.5) # Gray if out of range
			else:
				# Within range: check what kind of entity we are targeting
				var target_entity = null
				for entity in get_tree().get_nodes_in_group("entities"):
					if is_instance_valid(entity) and entity != main_node.player and not entity.is_in_group("items"):
						var e_grid = tile_map.local_to_map(entity.position)
						if e_grid == keyboard_target_grid:
							target_entity = entity
							break
				
				if target_entity:
					if target_entity.is_in_group("enemies"):
						pointer_polygon.color = Color(1.0, 0.15, 0.15) # Strong Red for enemy targets
					elif target_entity.is_in_group("allies") or target_entity.is_in_group("npcs"):
						pointer_polygon.color = Color(0.25, 1.0, 0.25) # Green for allies
					else:
						pointer_polygon.color = Color(1.0, 0.6, 0.1) # Orange
				else:
					pointer_polygon.color = Color(1.0, 0.6, 0.1) # Orange/yellow for empty ground/AOE

	# If look targeting is active, update tooltip immediately
	if targeting_look and main_node and main_node.has_method("_update_tooltip"):
		main_node._update_tooltip()

func _process(delta: float):
	if is_instance_valid(pointer_polygon) and is_instance_valid(cursor_sprite) and cursor_sprite.visible:
		var time = Time.get_ticks_msec() / 1000.0
		# Oscillate between -6 and -14 pixels above the top edge of the tile (-TILE_SIZE/2.0 = -16)
		# So offset ranges from -22 to -30 relative to the center of the tile.
		var y_bob = -10.0 + sin(time * 10.0) * 4.0
		pointer_polygon.position = Vector2(0, -TILE_SIZE / 2.0 + y_bob)

func get_target_pos_global() -> Vector2:
	return Vector2(keyboard_target_grid) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)

func is_active() -> bool:
	return targeting_item != null or targeting_skill != null or targeting_look or targeting_talk
