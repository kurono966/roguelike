extends Control

const GridViewScene = preload("res://ui/grid_inventory_view.tscn")
const ItemContextMenuScript = preload("res://ui/item_context_menu.gd")

@onready var equipment_view_container = $HBoxContainer/EquipmentPanel/VBoxContainer
@onready var bag_view_container = $HBoxContainer/BagPanel/VBoxContainer

@onready var attack_label = $HBoxContainer/EquipmentPanel/VBoxContainer/StatsContainer/AttackLabel
@onready var defense_label = $HBoxContainer/EquipmentPanel/VBoxContainer/StatsContainer/DefenseLabel

@onready var detailed_stats_label = $HBoxContainer/DetailedStatsPanel/VBoxContainer/DetailedStatsLabel

var equipment_view
var bag_view
var floor_view
var floor_grid_data: InventoryGridData

enum ActiveView { EQUIPMENT, BAG, FLOOR }
var active_view_mode = ActiveView.BAG

var context_menu_source_view
var current_menu # Can be Control (custom menu) or PopupMenu (Window)

var player

func _input(event):
	if not visible:
		return

	# If context menu is open, pass specific navigation/cancel inputs to it and block the rest
	if current_menu:
		var pass_to_menu = false
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_UP, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_SPACE:
					pass_to_menu = true
			if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
				pass_to_menu = true
		
		if pass_to_menu:
			return # Let the child context menu handle it
		else:
			if event is InputEventKey:
				get_viewport().set_input_as_handled()
			return

	# Close UI on escape, cancel action or toggle_inventory
	if event.is_action_pressed("toggle_inventory") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		GameUI.toggle_ui()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed:
		var target_view = _get_active_view()
		if target_view:
			var dir = Vector2i.ZERO
			
			# Numpad directional input check
			var numpad_dir = InputHandler._get_numpad_direction(event)
			if numpad_dir != Vector2.ZERO:
				dir = Vector2i(numpad_dir)
			
			# Standard arrow keys (fallback)
			if dir == Vector2i.ZERO:
				if event.is_action_pressed("ui_up"): dir = Vector2i.UP
				elif event.is_action_pressed("ui_down"): dir = Vector2i.DOWN
				elif event.is_action_pressed("ui_left"): dir = Vector2i.LEFT
				elif event.is_action_pressed("ui_right"): dir = Vector2i.RIGHT
				elif event.is_action_pressed("ui_up_left"): dir = Vector2i(-1, -1)
				elif event.is_action_pressed("ui_up_right"): dir = Vector2i(1, -1)
				elif event.is_action_pressed("ui_down_left"): dir = Vector2i(-1, 1)
				elif event.is_action_pressed("ui_down_right"): dir = Vector2i(1, 1)
			
			if dir != Vector2i.ZERO:
				if dir.x != 0 and dir.y != 0:
					target_view.move_cursor(dir)
				elif dir.x != 0:
					var cursor = target_view.cursor_pos
					var grid_w = target_view.grid_data.size.x
					
					if dir.x < 0 and cursor.x == 0:
						_switch_view(-1)
					elif dir.x > 0 and cursor.x == grid_w - 1:
						_switch_view(1)
					else:
						target_view.move_cursor(dir)
				else:
					target_view.move_cursor(dir)
				get_viewport().set_input_as_handled()
				return
			
			# Accept Action (Show context menu)
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				var item = target_view.get_cursor_item()
				if item:
					var cursor_screen_pos = _get_cursor_screen_position(target_view)
					var is_equipped = (active_view_mode == ActiveView.EQUIPMENT)
					var is_floor_item = (active_view_mode == ActiveView.FLOOR)
					_show_context_menu(item, cursor_screen_pos, is_equipped, target_view, is_floor_item)
				get_viewport().set_input_as_handled()
				return
				
			# Space key handles toggle close
			if event.keycode == KEY_SPACE:
				GameUI.toggle_ui()
				get_viewport().set_input_as_handled()
				return
				
			# Delete / Backspace key to drop?
			if event.keycode == KEY_DELETE or event.is_action_pressed("ui_text_delete"):
				pass
		
		# Consume all other key inputs when inventory is active
		get_viewport().set_input_as_handled()

func _get_active_view() -> Control:
	match active_view_mode:
		ActiveView.EQUIPMENT: return equipment_view
		ActiveView.BAG: return bag_view
		ActiveView.FLOOR: return floor_view
	return null

func _switch_view(direction: int):
	# direction: -1 (Left), 1 (Right)
	var current = int(active_view_mode)
	var next = current + direction
	
	# Clamp or Wrap?
	# Equipment(0) <-> Bag(1) <-> Floor(2)
	if next < 0: next = 0
	if next > 2: next = 2
	
	if next != current:
		_set_active_view(next)

func _set_active_view(mode: int):
	# Deactivate old cursor
	var old_view = _get_active_view()
	if old_view: old_view.set_cursor_active(false)
	
	active_view_mode = mode
	
	# Activate new cursor
	var new_view = _get_active_view()
	if new_view: 
		new_view.set_cursor_active(true)
		# Ensure cursor is in valid pos?
		if new_view.cursor_pos.x == -1:
			new_view.set_cursor_pos(Vector2i(0, 0))


func _ready():
	# Create views
	equipment_view = GridViewScene.instantiate()
	equipment_view.is_equipment_view = true
	equipment_view_container.add_child(equipment_view)
	
	bag_view = GridViewScene.instantiate()
	bag_view.is_equipment_view = false
	bag_view_container.add_child(bag_view)
	
	# Create Floor Panel dynamically
	var floor_panel = PanelContainer.new()
	floor_panel.name = "FloorPanel"
	floor_panel.custom_minimum_size = Vector2(250, 0) # Similar width to others
	
	# Add Label
	var vbox = VBoxContainer.new()
	var label = Label.new()
	label.text = "Floor (Feet)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	floor_panel.add_child(vbox)
	
	# Insert into HBoxContainer before DetailedStatsPanel (index 2 usually: Equim, Bag, [Here], Stats)
	$HBoxContainer.add_child(floor_panel)
	$HBoxContainer.move_child(floor_panel, 2)
	
	floor_view = GridViewScene.instantiate()
	floor_view.is_floor_view = true
	vbox.add_child(floor_view)
	
	# Connect signals
	equipment_view.connect("item_action", _on_item_action)
	bag_view.connect("item_action", _on_item_action)
	floor_view.connect("item_action", _on_floor_item_action) # Right click (Use/Equip) on floor
	
	equipment_view.connect("item_throw_request", _on_item_throw_request)
	bag_view.connect("item_throw_request", _on_item_throw_request)
	floor_view.connect("item_throw_request", _on_item_throw_request) # Can throw from floor? Maybe.

	# Pickup signal
	floor_view.connect("item_pickup_request", _on_floor_item_pickup)
	
	# Connect activate (Use) - Pass view info for context menu
	equipment_view.connect("item_activated", _on_view_item_activated.bind(equipment_view, true))
	bag_view.connect("item_activated", _on_view_item_activated.bind(bag_view, false))
	floor_view.connect("item_activated", _on_view_item_activated.bind(floor_view, false))

	# Connect clicked (Selection / Throw Mode)
	equipment_view.connect("item_clicked", _on_view_item_clicked.bind(equipment_view, true))
	bag_view.connect("item_clicked", _on_view_item_clicked.bind(bag_view, false))
	floor_view.connect("item_clicked", _on_view_item_clicked.bind(floor_view, false))
	

func initialize(p_player):
	player = p_player
	if not player:
		print("UnifiedUI: Initialize called with null player!")
		return
		
	var eq_comp = player.get_node_or_null("EquipmentComponent")
	if eq_comp:
		print("UnifiedUI: Initializing with player data. Bag items: ", eq_comp.bag_data.items.size())
		equipment_view.set_grid_data(eq_comp.equipment_data)
		bag_view.set_grid_data(eq_comp.bag_data)
		
		if not eq_comp.equipment_data.grid_changed.is_connected(_update_stats):
			eq_comp.equipment_data.grid_changed.connect(_update_stats)

		if not player.inventory_bonus_changed.is_connected(_on_inventory_bonus_changed):
			player.inventory_bonus_changed.connect(_on_inventory_bonus_changed)

		_update_stats()
		var bonus = player.get_inventory_bonus_state()
		_on_inventory_bonus_changed(bonus)
		
		# Connect to drop signals
		if not equipment_view.item_dropped.is_connected(_on_item_dropped):
			equipment_view.item_dropped.connect(_on_item_dropped)
		if not bag_view.item_dropped.is_connected(_on_item_dropped):
			bag_view.item_dropped.connect(_on_item_dropped)
		
		# Connect floor drop signal
		if not floor_view.item_drop_to_floor.is_connected(_on_item_drop_to_floor):
			floor_view.item_drop_to_floor.connect(_on_item_drop_to_floor)
		
		# キーボード操作を有効にするためにフォーカスを設定
		call_deferred("_set_initial_focus")
			
	else:
		print("UnifiedUI: Player has no equipment component!")

	_refresh_floor_items()
	
	# Activate Cursor
	_set_active_view(active_view_mode)

func _set_initial_focus():
	# アクティブなビューにフォーカスを設定
	var active = _get_active_view()
	if active:
		active.grab_focus()
		# カーソルを初期位置に設定して表示
		active.set_cursor_pos(Vector2i(0, 0))
		active.set_cursor_active(true)
		print("UnifiedUI: Focus set to active view, cursor visible")
	else:
		print("UnifiedUI: No active view to focus")

func _refresh_floor_items():
	# Find items at player position
	if not player: return
	
	var found_items = []
	var world_items = get_tree().get_nodes_in_group("items")
	
	# Snap player pos to grid for comparison (assuming world items are also snapped or close)
	# WorldItem.position is usually centered/snapped. _spawn_enemies loops snaped it?
	# main.gd usually sets position = grid * TILE_SIZE.
	# player.gd sets position = grid * TILE_SIZE.
	# So exact match should work? Or distance check.
	var p_pos = player.position
	
	for wi in world_items:
		if not is_instance_valid(wi) or wi.is_queued_for_deletion():
			continue
		if wi is Node2D:
			if wi.position.distance_to(p_pos) < 16.0: # Half tile tolerance
				if "item_data" in wi and wi.item_data:
					# Attach reference to WorldItem node for removal later
					wi.item_data.set_meta("world_item_ref", wi)
					found_items.append(wi.item_data)
	
	# Create temporary grid data
	# Calculate required size
	var total_area = 0
	for item in found_items:
		total_area += item.get_width() * item.get_height()
	
	var grid_width = 8
	var min_height = ceil(float(total_area) / grid_width)
	var grid_height = max(4, int(min_height) + 2) # Base 4, plus buffer for packing efficiency
	
	# Attempt to fit. If fails, we might need a retry loop or just big enough buffer.
	# For now, generous buffer.
	
	floor_grid_data = InventoryGridData.new(Vector2i(grid_width, grid_height))
	
	var placed_items = []
	for item in found_items:
		var pos = floor_grid_data.find_free_space(item)
		if pos != Vector2i(-1, -1):
			floor_grid_data.place_item(item, pos.x, pos.y)
			placed_items.append(item)
		else:
			print("UnifiedUI: Failed to place floor item ", item.name, " in grid size ", grid_width, "x", grid_height)
			# Fallback: Expansion or just ignore for now (User request implies they want to see ALL)
			# Recalculate with larger height? for simple case, let's just make it huge if needed or depend on buffer.
			# With +2 rows buffer, usually fits unless very large items.
			pass
			
	floor_view.set_grid_data(floor_grid_data)

func _on_inventory_bonus_changed(bonus_data):
	equipment_view.set_border_style(bonus_data.color)
	_update_stats()

func _on_item_dropped(item: BaseItem):
	if item and item.has_meta("world_item_ref"):
		_remove_world_item_of(item)
		item.remove_meta("world_item_ref")
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s を拾った" % item.name, Color(0.5, 1.0, 1.0))
	
	_refresh_floor_items()
	_update_stats()

	if player and player.has_method("trigger_turn_end"):
		player.trigger_turn_end()

var is_throw_mode = false

func set_throw_mode(enabled: bool):
	is_throw_mode = enabled
	# Optional: Visual indicator?
	var label = $HBoxContainer/BagPanel/VBoxContainer/Label
	if not label: return

	if is_throw_mode:
		label.modulate = Color(1, 0.5, 0.5) # Reddish header
		label.text = "Select Item to Throw"
	else:
		label.modulate = Color.WHITE
		label.text = "Inventory (Bag)"

func _on_view_item_clicked(item, button_index, source_view, is_equipped):
	if button_index == MOUSE_BUTTON_LEFT:
		if is_throw_mode:
			print("UnifiedUI: Clicked in throw mode -> Throwing ", item.name)
			_throw_item(item)
			set_throw_mode(false)
			return

func _on_view_item_activated(item, source_view, is_equipped):
	print("UnifiedUI: Executing item action ", item.name)
	
	if is_throw_mode:
		_throw_item(item)
		set_throw_mode(false) # Reset after selection
		return
	
	# シグナル経由（ダブルクリックやメニューからの実行）はアクションを実行する
	
	if is_equipped:
		# 装備中なら外す
		_unequip_item(item)
	elif source_view == floor_view:
		# 床アイテムのデフォルトアクション
		if item.equipment_type >= 0:
			# 装備を試みる
			if player and player.equipment_component and player.equipment_component.equip_item(item):
				_remove_world_item_of(item)
				_refresh_floor_items()
				_update_stats()
				player.trigger_turn_end()
		else:
			# 消費アイテム等はそのまま使用（拾わずに使用）
			if player and player.has_method("use_item"):
				player.use_item(item)
				_remove_world_item_of(item)
				_refresh_floor_items()
				_update_stats()
				player.trigger_turn_end()
	else:
		# バッグ内
		if item.equipment_type >= 0:
			_equip_item(item)
		else:
			_use_item(item)

func _on_floor_item_pickup(item):
	print("UnifiedUI: Pickup request ", item.name)
	var eq_comp = player.equipment_component
	if eq_comp and eq_comp.add_to_bag(item):
		_remove_world_item_of(item)
		_refresh_floor_items()
		_update_stats()
		# Add log? "Picked up X"
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s を拾った" % item.name, Color(0.5, 1.0, 1.0))
		player.trigger_turn_end()
	else:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("インベントリがいっぱいです", Color(1, 0.5, 0.5))

func _on_floor_item_action(item):
	# Right click on floor item -> Usually opens context menu handled by draggable_item.
	# If this is called, it might be a fallback or "Equip" request from context menu?
	# Context menu emits "equip", "unequip", "use", "pickup".
	# If "equip" from floor:
	print("UnifiedUI: Floor item action (Equip?) ", item.name)
	var eq_comp = player.equipment_component
	if eq_comp and eq_comp.equip_item(item):
		_remove_world_item_of(item)
		_refresh_floor_items()
		_update_stats()
		player.trigger_turn_end()

func _remove_world_item_of(item: BaseItem):
	if item.has_meta("world_item_ref"):
		var wi = item.get_meta("world_item_ref")
		if is_instance_valid(wi):
			wi.queue_free()

func _update_stats():
	if player:
		attack_label.text = "ATK: %d" % player.attack_power
		defense_label.text = "DEF: %d" % player.defense_power
		
		var txt = ""
		txt += "Strength: %d\n" % player.get_total_strength()
		txt += "Dexterity: %d\n" % player.get_total_dexterity()
		txt += "Intelligence: %d\n" % player.get_total_intelligence()
		txt += "\n"
		txt += "Hit Rate: %.1f%%\n" % (clamp(player.hit_rate, 0.0, 1.0) * 100.0)
		txt += "Critical Rate: %.1f%%\n" % (clamp(player.crit_rate, 0.0, 1.0) * 100.0)
		txt += "Penetration Rate: %.1f%%\n" % (clamp(player.penetration_rate, 0.0, 1.0) * 100.0)
		txt += "\n"
		txt += "Max HP: %d\n" % player.max_hp
		txt += "HP Bonus: %d\n" % player.initial_hp_bonus
		txt += "Level: %d\n" % player.level
		txt += "\n"
		if "can_swim" in player and player.can_swim:
			txt += "Ability: Swim\n"
		
		var bonus = player.get_inventory_bonus_state()
		if bonus.message != "":
			txt += "\n[Bonus]\n" + bonus.message.strip_edges()
			
		detailed_stats_label.text = txt

func _on_item_action(item):
	print("Item action on: ", item.name)
	var eq_comp = player.equipment_component
	if not eq_comp: return
	
	if item in eq_comp.bag_data.items:
		if eq_comp.equip_item(item):
			eq_comp.bag_data.remove_item(item)
			_update_stats()
	elif item in eq_comp.equipment_data.items:
		if eq_comp.add_to_bag(item):
			eq_comp.equipment_data.remove_item(item)
			_update_stats()

func _on_item_throw_request(item):
	print("UnifiedUI: Throw request for ", item.name)
	
	# If item is on FLOOR, we need to pick it up logically or create temp?
	# Main targeting expects item.
	# If thrown from floor, we should remove WorldItem upon actual throw execution?
	# But targeting is async.
	# We'll handle removal in Main if we implement "throw from floor".
	# For now, let's treat it same. But we need to know source.
	
	GameUI.toggle_ui() # Hide UI
	var main_scene = get_tree().current_scene
	if main_scene.has_method("start_throw_targeting"):
		main_scene.start_throw_targeting(item) 

func _on_item_drop_to_floor(item: BaseItem, origin_grid):
	print("UnifiedUI: Dropping item to floor: ", item.name)
	
	if origin_grid == floor_view:
		# Dragged from floor and dropped on floor: do nothing, just refresh
		_refresh_floor_items()
		return
		
	# Check if there's already an item at player's position
	var main_scene = get_tree().current_scene
	if not main_scene or not main_scene.has_method("get_item_at_player_position"):
		print("UnifiedUI: Cannot access main scene")
		return
	
	var existing_item = main_scene.get_item_at_player_position()
	if existing_item:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("このマスには既にアイテムがあります", Color.GRAY)
		return
	
	# Remove from origin inventory
	if origin_grid and origin_grid.grid_data:
		origin_grid.grid_data.remove_item(item)
	
	# Place item at player position
	if main_scene.has_method("place_item_at_player"):
		main_scene.place_item_at_player(item)
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s を地面に置いた" % item.name, Color(0.8, 0.8, 0.8))
		
		# Refresh floor view
		_refresh_floor_items()
		_update_stats()

		if player and player.has_method("trigger_turn_end"):
			player.trigger_turn_end()
 
		# If item is floor item, Main needs to know to remove it. 
		# BaseItem metadata "world_item_ref" can be used by Main!

# コンテキストメニュー関連
func _show_context_menu(item: BaseItem, screen_pos: Vector2, is_equipped: bool, source_view, is_floor_item: bool = false):
	var menu_res = load("res://ui/context_menu.tscn")
	if not menu_res:
		print("UnifiedUI: Failed to load context menu scene")
		return
		
	var menu = menu_res.instantiate()
	get_tree().root.add_child(menu)
	current_menu = menu
	
	# Connect signals
	menu.item_context_action.connect(func(action, action_item): _on_context_menu_action(action, action_item))
	
	var context_type = "inventory"
	if is_floor_item:
		context_type = "floor"
	elif is_equipped:
		context_type = "equipment"
		
	menu.show_context_menu(item, screen_pos, context_type)
	menu.popup_hide.connect(func():
		current_menu = null
		menu.queue_free()
	)
	context_menu_source_view = source_view

func _get_cursor_screen_position(view: Control) -> Vector2:
	if not view or not view.has_method("get_cursor_item"):
		return Vector2.ZERO
	
	var cursor_pos = view.cursor_pos if "cursor_pos" in view else Vector2i.ZERO
	var cell_size = 32
	var local_pos = Vector2(cursor_pos.x * cell_size, cursor_pos.y * cell_size)
	# Center of the cell
	return view.global_position + local_pos + Vector2(cell_size / 2, cell_size / 2)

func _on_context_menu_action(action: String, item: BaseItem):
	match action:
		"use":
			_use_item(item)
		"throw":
			_throw_item(item)
		"equip":
			_equip_item(item)
		"unequip":
			_unequip_item(item)
		"pickup":
			_on_floor_item_pickup(item)
	
	context_menu_source_view = null

func _use_item(item: BaseItem):
	# バッグから消費アイテムを使用
	print("UnifiedUI: Using item: ", item.name)
	# プレイヤーのuse_itemメソッドに委譲
	if player and player.has_method("use_item"):
		player.use_item(item)
		_update_stats()

func _throw_item(item: BaseItem):
	# 投げる処理
	print("Throwing item: ", item.name)
	# item_throw_requestシグナルを発火
	if context_menu_source_view and context_menu_source_view.has_signal("item_throw_request"):
		context_menu_source_view.emit_signal("item_throw_request", item)

func _equip_item(item: BaseItem):
	# バッグから装備
	print("Equipping item: ", item.name)
	if player and player.equipment_component:
		if player.equipment_component.equip_item(item):
			# バッグからアイテムを削除
			player.equipment_component.bag_data.remove_item(item)
			_update_stats()

func _unequip_item(item: BaseItem):
	# 装備を外す
	print("Unequipping item: ", item.name)
	if player and player.equipment_component:
		if player.equipment_component.unequip_item(item):
			_update_stats()
