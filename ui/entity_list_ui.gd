extends Control

signal ui_visibility_changed

var main_node: Node2D
var panel: PanelContainer
var list_container: VBoxContainer
var is_visible: bool = false

const TILE_SIZE = 32
const ELEMENT_NAMES = {
	"normal": "通常", "fire": "炎", "ice": "氷", "electric": "雷",
	"water": "水", "blunt": "打撃", "pierce": "刺突", "magic": "魔法",
}

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	
	# Get main node reference
	main_node = get_tree().get_first_node_in_group("main")
	
	# Get references from scene
	panel = $Panel
	list_container = $Panel/VBox/ListContainer
	preload("res://ui/panel_drag.gd").attach(panel, $Panel/VBox/Header)

func _get_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.85)
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.25, 0.28, 1.0)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	return style

func open():
	if not main_node:
		main_node = get_tree().get_first_node_in_group("main")
	
	is_visible = true
	refresh_list()

func close():
	is_visible = false

func refresh_list():
	if not main_node:
		main_node = get_tree().get_first_node_in_group("main")
		if not main_node:
			return
	
	# Clear existing entries
	for child in list_container.get_children():
		child.queue_free()
	
	# Get player position
	var player = main_node.player
	if not player:
		return
	
	var player_grid = main_node.tile_map.local_to_map(player.position)
	
	# Collect all visible entities
	var entities = []
	
	var tree = get_tree()
	if not tree:
		return
		
	# Enemies
	for enemy in tree.get_nodes_in_group("enemies"):
		if main_node.visibility_manager and main_node.visibility_manager.is_entity_visible_to_player(enemy):
			entities.append({"type": "enemy", "entity": enemy, "name": _get_entity_name(enemy)})
	
	# NPCs
	for npc in tree.get_nodes_in_group("npcs"):
		if main_node.visibility_manager and main_node.visibility_manager.is_entity_visible_to_player(npc):
			entities.append({"type": "npc", "entity": npc, "name": _get_entity_name(npc)})
	
	# Allies
	for ally in tree.get_nodes_in_group("allies"):
		if main_node.visibility_manager and main_node.visibility_manager.is_entity_visible_to_player(ally):
			entities.append({"type": "ally", "entity": ally, "name": _get_entity_name(ally)})
	
	# Items
	for item in tree.get_nodes_in_group("items"):
		if item.visible and main_node.visibility_manager:
			var item_grid = main_node.tile_map.local_to_map(item.position)
			if item_grid.x >= 0 and item_grid.x < main_node.MAP_WIDTH and item_grid.y >= 0 and item_grid.y < main_node.MAP_HEIGHT:
				if main_node.visibility_manager.visible_tiles[item_grid.x][item_grid.y]:
					var item_name = "アイテム"
					if "item_data" in item and item.item_data and "name" in item.item_data:
						item_name = item.item_data.name
					entities.append({"type": "item", "entity": item, "name": item_name})
	
	# Sort by distance
	entities.sort_custom(func(a, b):
		var pos_a = main_node.tile_map.local_to_map(a.entity.position)
		var pos_b = main_node.tile_map.local_to_map(b.entity.position)
		var dist_a = player_grid.distance_to(pos_a)
		var dist_b = player_grid.distance_to(pos_b)
		return dist_a < dist_b
	)
	
	if entities.is_empty():
		var empty_label = Label.new()
		empty_label.text = "視界内にエンティティはいません"
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		list_container.add_child(empty_label)
	else:
		for ent_data in entities:
			var entry = _create_entity_entry(ent_data, player_grid)
			list_container.add_child(entry)

func _get_entity_name(entity) -> String:
	# Use the same logic as the tooltip (X key look mode)
	var name_str = entity.name
	if "enemy_name" in entity and entity.enemy_name != "":
		name_str = entity.enemy_name
	
	# If still empty, try other properties
	if name_str == "" or name_str == "CharacterBody2D":
		if "display_name" in entity and entity.display_name != "":
			name_str = entity.display_name
		elif "entity_name" in entity and entity.entity_name != "":
			name_str = entity.entity_name
		elif "title" in entity and entity.title != "":
			name_str = entity.title
		elif "enemy_type" in entity and entity.enemy_type != "":
			name_str = entity.enemy_type
		elif "type" in entity and entity.type != "":
			name_str = str(entity.type)
	
	# Final fallback to class name if still empty
	if name_str == "" or name_str == "CharacterBody2D":
		var entity_class = entity.get_class()
		if entity_class.ends_with("GDScript"):
			entity_class = entity_class.substr(0, entity_class.length() - 8)
		name_str = entity_class
	
	return name_str

func _create_entity_entry(ent_data: Dictionary, player_grid: Vector2i) -> Control:
	var entry = VBoxContainer.new()
	entry.add_theme_constant_override("separation", 1)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	entry.add_child(hbox)
	
	# Type icon/color
	var type_label = Label.new()
	type_label.custom_minimum_size = Vector2(20, 0)
	match ent_data.type:
		"enemy":
			type_label.text = "[E]"
			type_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.35))
		"npc":
			type_label.text = "[N]"
			type_label.add_theme_color_override("font_color", Color(0.55, 0.65, 0.85))
		"ally":
			type_label.text = "[A]"
			type_label.add_theme_color_override("font_color", Color(0.45, 0.75, 0.45))
		"item":
			type_label.text = "[I]"
			type_label.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
		_:
			type_label.text = "?"
	hbox.add_child(type_label)
	
	# Name
	var name_label = Label.new()
	name_label.text = ent_data.name
	name_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)
	
	# Distance
	var ent_grid = main_node.tile_map.local_to_map(ent_data.entity.position)
	var dist = player_grid.distance_to(ent_grid)
	var dist_label = Label.new()
	dist_label.text = "%.1fm" % (roundf(dist * 10.0) / 10.0)
	dist_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hbox.add_child(dist_label)
	
	var entity = ent_data.entity
	if "weaknesses" in entity or "resistances" in entity:
		var affinity_label = RichTextLabel.new()
		affinity_label.bbcode_enabled = true
		affinity_label.fit_content = true
		affinity_label.scroll_active = false
		affinity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		affinity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		affinity_label.add_theme_font_size_override("normal_font_size", 12)
		var weak = _format_elements(entity.weaknesses if "weaknesses" in entity else [])
		var resist = _format_elements(entity.resistances if "resistances" in entity else [])
		affinity_label.text = "[color=#e6a078]弱:%s[/color]　[color=#89b9d9]耐:%s[/color]" % [weak, resist]
		entry.add_child(affinity_label)
	return entry

func _format_elements(elements: Array) -> String:
	var names = PackedStringArray()
	for element in elements:
		var element_name: String = ELEMENT_NAMES.get(element, str(element))
		if not names.has(element_name): names.append(element_name)
	return "・".join(names) if not names.is_empty() else "—"

func _process(_delta):
	refresh_list()
