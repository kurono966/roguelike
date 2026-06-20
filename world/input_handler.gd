class_name InputHandler
extends Node

var main_node: Node2D
var player: CharacterBody2D
var tile_map: TileMap
var _web_audio_initialized = false
var _last_click_time = 0
var _waiting_for_dig_direction: bool = false
var debug_mode: bool = false
const KEY_LOCATION_NUMPAD_FALLBACK := 3

func setup(main: Node2D):
	main_node = main
	player = main.player
	tile_map = main.tile_map

static func _is_numpad_event(key_event: InputEventKey) -> bool:
	if key_event.location == KEY_LOCATION_NUMPAD_FALLBACK:
		return true

	match key_event.physical_keycode:
		KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9:
			return true
		_:
			return false

static func _get_numpad_direction(key_event: InputEventKey) -> Vector2:
	if not _is_numpad_event(key_event):
		return Vector2.ZERO

	match key_event.physical_keycode:
		KEY_KP_7:
			return Vector2(-1, -1)
		KEY_KP_9:
			return Vector2(1, -1)
		KEY_KP_1:
			return Vector2(-1, 1)
		KEY_KP_3:
			return Vector2(1, 1)
		KEY_KP_8:
			return Vector2.UP
		KEY_KP_2:
			return Vector2.DOWN
		KEY_KP_4:
			return Vector2.LEFT
		KEY_KP_6:
			return Vector2.RIGHT

	match key_event.keycode:
		KEY_KP_7, KEY_7, KEY_HOME:
			return Vector2(-1, -1)
		KEY_KP_9, KEY_9, KEY_PAGEUP:
			return Vector2(1, -1)
		KEY_KP_1, KEY_1, KEY_END:
			return Vector2(-1, 1)
		KEY_KP_3, KEY_3, KEY_PAGEDOWN:
			return Vector2(1, 1)
		KEY_KP_8, KEY_8, KEY_UP:
			return Vector2.UP
		KEY_KP_2, KEY_2, KEY_DOWN:
			return Vector2.DOWN
		KEY_KP_4, KEY_4, KEY_LEFT:
			return Vector2.LEFT
		KEY_KP_6, KEY_6, KEY_RIGHT:
			return Vector2.RIGHT
		_:
			return Vector2.ZERO

func _is_numpad_wait_key(key_event: InputEventKey) -> bool:
	if not _is_numpad_event(key_event):
		return false
	return key_event.physical_keycode == KEY_KP_5 or key_event.keycode == KEY_KP_5 or key_event.keycode == KEY_5 or key_event.keycode == KEY_CLEAR

func _unhandled_input(event: InputEvent) -> void:
	if not main_node or not is_instance_valid(player):
		return

	# Block input if major UI is open
	var game_ui = get_node_or_null("/root/GameUI")
	if game_ui:
		if game_ui.is_visible or game_ui.is_skill_visible or game_ui.is_trade_visible or game_ui.is_status_visible or game_ui.help_ui.visible or game_ui.dialog_menu.visible:
			return

	if _waiting_for_dig_direction:
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or event.is_action_pressed("ui_cancel"):
			_waiting_for_dig_direction = false
			if main_node.has_node("/root/LogUI"):
				main_node.get_node("/root/LogUI").add_log("掘削をキャンセルしました。", Color(0.6, 0.6, 0.6))
			get_viewport().set_input_as_handled()
			return
			
		if event is InputEventKey and event.pressed and not event.is_echo():
			var direction = Vector2i.ZERO
			var numpad_direction = _get_numpad_direction(event)
			if numpad_direction != Vector2.ZERO:
				direction = Vector2i(numpad_direction)
			
			if direction == Vector2i.ZERO and Input.is_action_pressed("ui_left"): direction = Vector2i.LEFT
			elif direction == Vector2i.ZERO and Input.is_action_pressed("ui_right"): direction = Vector2i.RIGHT
			elif direction == Vector2i.ZERO and Input.is_action_pressed("ui_up"): direction = Vector2i.UP
			elif direction == Vector2i.ZERO and Input.is_action_pressed("ui_down"): direction = Vector2i.DOWN
			elif direction == Vector2i.ZERO and Input.is_action_pressed("ui_up_left"): direction = Vector2i(-1, -1)
			elif direction == Vector2i.ZERO and Input.is_action_pressed("ui_up_right"): direction = Vector2i(1, -1)
			elif direction == Vector2i.ZERO and Input.is_action_pressed("ui_down_left"): direction = Vector2i(-1, 1)
			elif direction == Vector2i.ZERO and Input.is_action_pressed("ui_down_right"): direction = Vector2i(1, 1)
			
			if direction != Vector2i.ZERO:
				_waiting_for_dig_direction = false
				var player_grid = tile_map.local_to_map(player.position)
				var target_grid = player_grid + direction
				await main_node._handle_dig(target_grid)
				get_viewport().set_input_as_handled()
				return
				
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos = main_node.get_global_mouse_position()
			var clicked_tile = tile_map.local_to_map(mouse_pos)
			var player_tile = tile_map.local_to_map(player.position)
			
			var diff = (clicked_tile - player_tile).abs()
			if diff.x <= 1 and diff.y <= 1 and clicked_tile != player_tile:
				_waiting_for_dig_direction = false
				await main_node._handle_dig(clicked_tile)
				get_viewport().set_input_as_handled()
				return
			else:
				_waiting_for_dig_direction = false
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("掘削をキャンセルしました。", Color(0.6, 0.6, 0.6))
				get_viewport().set_input_as_handled()
				return
		
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
			return

	# Web Audio Context Unlock
	if not _web_audio_initialized and OS.get_name() == "Web":
		if event is InputEventMouseButton and event.pressed:
			_web_audio_initialized = true
			var asp = AudioStreamPlayer.new()
			add_child(asp)
			asp.play()
			get_tree().create_timer(0.1).timeout.connect(asp.queue_free)

	# UI Toggles
	if event.is_action_pressed("toggle_inventory"):
		GameUI.toggle_ui()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_skills"):
		GameUI.toggle_skills()
		get_viewport().set_input_as_handled()
		return
	
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_AT or event.unicode == 64:
			GameUI.toggle_status()
			get_viewport().set_input_as_handled()
			return
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		GameUI.open_throw_selection()
		get_viewport().set_input_as_handled()
		return

	# Handle Targeting Mode using TargetManager
	var tm = main_node.target_manager
	
	if tm and (tm.is_active() or main_node._current_game_state == main_node.TurnPhase.TARGETING):
		# Safety: if no targeting context remains, cancel targeting
		if not tm.is_active():
			tm.cancel_targeting()
			return
			
		if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_X and tm.targeting_look):
			tm.cancel_targeting()
			get_viewport().set_input_as_handled()
			return
			
		# Keyboard Targeting
		var target_dir = Vector2i.ZERO
		if event.is_action_pressed("ui_up"): target_dir = Vector2i.UP
		elif event.is_action_pressed("ui_down"): target_dir = Vector2i.DOWN
		elif event.is_action_pressed("ui_left"): target_dir = Vector2i.LEFT
		elif event.is_action_pressed("ui_right"): target_dir = Vector2i.RIGHT
		elif event.is_action_pressed("ui_up_left"): target_dir = Vector2i(-1, -1)
		elif event.is_action_pressed("ui_up_right"): target_dir = Vector2i(1, -1)
		elif event.is_action_pressed("ui_down_left"): target_dir = Vector2i(-1, 1)
		elif event.is_action_pressed("ui_down_right"): target_dir = Vector2i(1, 1)

		if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
			tm.cancel_targeting()
			get_viewport().set_input_as_handled()
			return

		if target_dir != Vector2i.ZERO:
			tm.move_cursor(target_dir)
			get_viewport().set_input_as_handled()
			return

		# Enter, F, or V to Accept/Fire/Talk (Keyboard)
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_F or event.keycode == KEY_V:
				if tm.targeting_look:
					tm.cancel_targeting()
				elif tm.targeting_talk:
					var target_pos = tm.get_target_pos_global()
					var target_grid = main_node.tile_map.local_to_map(target_pos)
					tm.cancel_targeting()
					main_node._execute_talk_at(target_grid)
				else:
					var target_pos = tm.get_target_pos_global()
					if tm.targeting_item:
						if tm.targeting_is_ranged_weapon:
							main_node._execute_ranged_attack(target_pos)
						else:
							main_node._execute_throw(target_pos)
					elif tm.targeting_skill:
						main_node._execute_skill(target_pos)
				get_viewport().set_input_as_handled()
				return
		
		# Mouse Click
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var target_pos = main_node.get_global_mouse_position()
			# Allow clicking anywhere, update cursor
			tm.update_cursor_mouse(target_pos)
			
			if tm.targeting_look:
				pass
			elif tm.targeting_talk:
				var target_grid = main_node.tile_map.local_to_map(target_pos)
				tm.cancel_targeting()
				main_node._execute_talk_at(target_grid)
			else:
				if tm.targeting_item:
					if tm.targeting_is_ranged_weapon:
						main_node._execute_ranged_attack(target_pos)
					else:
						main_node._execute_throw(target_pos)
				elif tm.targeting_skill:
					main_node._execute_skill(target_pos)
			get_viewport().set_input_as_handled()
			return
		
		if event is InputEventMouseMotion:
			tm.update_cursor_mouse(main_node.get_global_mouse_position())
		return

	if main_node._current_game_state != main_node.TurnPhase.PLAYER_TURN:
		return

	# Block input if paralyzed
	if player.has_method("is_paralyzed") and player.is_paralyzed():
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_F3:
			debug_mode = !debug_mode
			if main_node.has_node("/root/LogUI"):
				main_node.get_node("/root/LogUI").add_log("デバッグモード: %s" % ("ON" if debug_mode else "OFF"), Color.MAGENTA)
			return
		elif debug_mode and (event.keycode == KEY_BRACERIGHT or event.unicode == 125):
			if is_instance_valid(player) and player.has_method("level_up"):
				player.level_up()
			return
		elif debug_mode and (event.keycode == KEY_BRACELEFT or event.unicode == 123):
			if main_node.has_method("_change_floor"):
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("DEBUG: Jumping to next floor...", Color.CYAN)
				main_node._change_floor(main_node.current_floor + 1, 0, false)
			return
		if event.keycode == KEY_F1:
			if player.has_method("apply_debug_upgrade"):
				player.apply_debug_upgrade()
			return
		if event.keycode == KEY_F12:
			var global_gs = main_node.get_node("/root/GameState")
			if global_gs:
				global_gs.god_mode = !global_gs.god_mode
				print("God Mode: ", "ON" if global_gs.god_mode else "OFF")
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("God Mode: %s" % ("ON" if global_gs.god_mode else "OFF"), Color.MAGENTA)
			return
		elif event.keycode == KEY_F5:
			# Save Game
			var save_mgr = main_node.get_node_or_null("/root/SaveManager")
			if save_mgr and save_mgr.save_game(player, main_node):
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("ゲームをセーブしました", Color.GREEN)
			else:
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("セーブに失敗しました", Color.RED)
			return
		elif event.keycode == KEY_EQUAL or event.keycode == KEY_QUESTION or event.keycode == KEY_H:
			# Help
			if GameUI.has_method("toggle_help"):
				GameUI.toggle_help()
			return
		elif event.keycode == KEY_F9:
			# Load Game
			var save_mgr = main_node.get_node_or_null("/root/SaveManager")
			if save_mgr and save_mgr.save_exists():
				main_node._load_game()
			else:
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("セーブデータが見つかりません", Color.GRAY)
			return
		elif event.keycode == KEY_F2:
			# Debug: Skip Floor
			if main_node.has_method("_descend_stairs"):
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("DEBUG: Jumping to next floor...", Color.CYAN)
				main_node._descend_stairs(0)
			return
	if event.is_action_pressed("target_enemy") or (event is InputEventKey and event.pressed and event.keycode == KEY_S):
		if main_node._try_attack_adjacent_enemy():
			await main_node._end_player_turn()
		else:
			var log_ui = main_node.get_tree().root.get_node_or_null("LogUI")
			if log_ui and log_ui.has_method("add_log"):
				log_ui.add_log("待機中...", Color(0.7, 0.7, 0.7))
			print("Player waits.")
			await main_node._end_player_turn()
		return

	# Handle talk choice input (must be before V key to prevent repeats)
	if main_node.has_method("_waiting_for_talk_choice") and main_node._waiting_for_talk_choice:
		if event is InputEventKey and event.pressed and not event.is_echo():
			if event.keycode == KEY_T:
				main_node._handle_talk_choice("trade")
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_R:
				main_node._handle_talk_choice("recruit")
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel"):
				main_node._waiting_for_talk_choice = false
				main_node._talk_choice_npc = null
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("会話をキャンセルしました", Color(0.6, 0.6, 0.6))
				await main_node._end_player_turn()
				get_viewport().set_input_as_handled()
				return
		return

	# Handle talk choice input (must be before V key to prevent repeats)
	if main_node.has_method("_waiting_for_talk_choice") and main_node._waiting_for_talk_choice:
		if event is InputEventKey and event.pressed and not event.is_echo():
			if event.keycode == KEY_T:
				main_node._handle_talk_choice("trade")
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_R:
				main_node._handle_talk_choice("recruit")
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel"):
				main_node._waiting_for_talk_choice = false
				main_node._talk_choice_npc = null
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("会話をキャンセルしました", Color(0.6, 0.6, 0.6))
				await main_node._end_player_turn()
				get_viewport().set_input_as_handled()
				return
		return

	# Handle talk choice input (must be before V key to prevent repeats)
	if main_node.has_method("_waiting_for_talk_choice") and main_node._waiting_for_talk_choice:
		if event is InputEventKey and event.pressed and not event.is_echo():
			if event.keycode == KEY_T:
				main_node._handle_talk_choice("trade")
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_R:
				main_node._handle_talk_choice("recruit")
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel"):
				main_node._waiting_for_talk_choice = false
				main_node._talk_choice_npc = null
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("会話をキャンセルしました", Color(0.6, 0.6, 0.6))
				await main_node._end_player_turn()
				get_viewport().set_input_as_handled()
				return
		return

	# Handle talk choice input (must be before V key to prevent repeats)
	if main_node.has_method("_waiting_for_talk_choice") and main_node._waiting_for_talk_choice:
		if event is InputEventKey and event.pressed and not event.is_echo():
			if event.keycode == KEY_T:
				main_node._handle_talk_choice("trade")
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_R:
				main_node._handle_talk_choice("recruit")
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel"):
				main_node._waiting_for_talk_choice = false
				main_node._talk_choice_npc = null
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("会話をキャンセルしました", Color(0.6, 0.6, 0.6))
				await main_node._end_player_turn()
				get_viewport().set_input_as_handled()
				return
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if main_node._current_game_state == main_node.TurnPhase.PLAYER_TURN:
			# Prevent new inputs while already moving/acting
			if main_node._is_path_following or main_node._is_auto_moving or main_node._is_resting or main_node._is_auto_exploring:
				return
			
			# Debounce clicks (prevent rapid firing bugs)
			var current_time = Time.get_ticks_msec()
			if current_time - _last_click_time < 250:
				return
			_last_click_time = current_time
			
			var mouse_pos = main_node.get_global_mouse_position()
			var clicked_tile = tile_map.local_to_map(mouse_pos)
			var player_tile = tile_map.local_to_map(player.position)
			
			if clicked_tile == player_tile:
				var cell = main_node._map_data[player_tile.x][player_tile.y]
				if cell == main_node.CellType.STAIRS:
					var next_branch = 10 if main_node._current_branch == 10 else 0
					main_node._change_floor(main_node.current_floor + 1, next_branch, false)
					get_viewport().set_input_as_handled()
					return
				elif cell == main_node.CellType.STAIRS_UP:
					var next_branch = 10 if main_node._current_branch == 10 else 0
					main_node._change_floor(main_node.current_floor - 1, next_branch, true)
					get_viewport().set_input_as_handled()
					return
				elif cell == main_node.CellType.STAIRS_BLUE:
					main_node._change_floor(main_node.current_floor + 1, 2, false)
					get_viewport().set_input_as_handled()
					return
				elif cell == main_node.CellType.STAIRS_GREEN:
					main_node._change_floor(main_node.current_floor + 1, 3, false)
					get_viewport().set_input_as_handled()
					return
				elif cell == main_node.CellType.STAIRS_RED:
					main_node._change_floor(main_node.current_floor + 1, 4, false)
					get_viewport().set_input_as_handled()
					return
				elif cell == main_node.CellType.STAIRS_PURPLE:
					main_node._change_floor(main_node.current_floor + 1, 5, false)
					get_viewport().set_input_as_handled()
					return
				elif cell == main_node.CellType.STAIRS_GOLD:
					if main_node._current_branch == 10 and main_node.current_floor == 3:
						main_node._change_floor(0, 0, true)
					else:
						main_node._change_floor(main_node.current_floor + 1, 10, false)
					get_viewport().set_input_as_handled()
					return

			main_node._handle_mouse_click(event.position)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.is_echo():
		# Zoom out (To world map)
		if event.keycode == KEY_COMMA or event.keycode == KEY_LESS or event.unicode == 60:
			if main_node.has_method("_zoom_out_to_world_map"):
				await main_node._zoom_out_to_world_map()
				get_viewport().set_input_as_handled()
				return
		
		# Zoom in (To local map)
		if event.keycode == KEY_PERIOD or event.keycode == KEY_GREATER or event.unicode == 62 or (main_node._is_on_world_map and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)):
			if main_node.has_method("_zoom_in_to_local_map"):
				await main_node._zoom_in_to_local_map()
				get_viewport().set_input_as_handled()
				return

		# Block general actions on the world map
		if main_node._is_on_world_map:
			if event.keycode in [KEY_Q, KEY_E, KEY_X, KEY_Z, KEY_G, KEY_B, KEY_C, KEY_D, KEY_R, KEY_V, KEY_F]:
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("ワールドマップではそのアクションを行えません。", Color.GRAY)
				get_viewport().set_input_as_handled()
				return

		if main_node._is_auto_moving or main_node._is_path_following or main_node._is_resting or main_node._is_auto_exploring:
			main_node._is_auto_moving = false
			main_node._is_path_following = false
			main_node._current_path.clear()
			main_node._path_continue_after_attack = false
			main_node._is_resting = false
			main_node._stop_auto_explore()
			return
		
		if event.keycode == KEY_Q:
			if not main_node._is_on_world_map:
				main_node._start_rest()
			return
		
		if event.keycode == KEY_E:
			if not main_node._is_on_world_map:
				main_node._start_auto_explore()
			return

		if event.keycode == KEY_X:
			main_node.start_look_mode()
			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_Z:
			main_node._start_auto_move_to_stairs()
			return
			
		if event.keycode == KEY_G:
			main_node._handle_pickup()
			return
			
		if event.keycode == KEY_B:
			main_node._handle_shop_purchase()
			return
			
		if event.keycode == KEY_C:
			await main_node._handle_close_door()
			return
			
		if event.keycode == KEY_D:
			# Check adjacent walls
			var player_grid = tile_map.local_to_map(player.position)
			var wall_count = 0
			var single_wall_pos = Vector2i.ZERO
			var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)]
			for d in dirs:
				var check = player_grid + d
				if check.x > 0 and check.x < main_node.MAP_WIDTH - 1 and check.y > 0 and check.y < main_node.MAP_HEIGHT - 1:
					if main_node._map_data[check.x][check.y] == main_node.CellType.WALL:
						wall_count += 1
						single_wall_pos = check
						
			if wall_count == 0:
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("掘れる壁が隣にありません。", Color(0.6, 0.6, 0.6))
			elif wall_count == 1:
				await main_node._handle_dig(single_wall_pos)
			else:
				_waiting_for_dig_direction = true
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("どの方向を掘りますか？ (方向キー/クリックで指定, ESC/右クリックでキャンセル)", Color.YELLOW)
			get_viewport().set_input_as_handled()
			return
			
		if event.keycode == KEY_R:
			main_node._handle_reload()
			return

		if event.keycode == KEY_V:
			await main_node._handle_talk()
			return

		var action_taken = false
		
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			var player_grid_pos = Vector2i(player.position / main_node.TILE_SIZE)
			var cell = main_node._map_data[player_grid_pos.x][player_grid_pos.y]
			if cell == main_node.CellType.STAIRS:
				var next_branch = 10 if main_node._current_branch == 10 else 0
				main_node._change_floor(main_node.current_floor + 1, next_branch, false)
				return
			elif cell == main_node.CellType.STAIRS_UP:
				var next_branch = 10 if main_node._current_branch == 10 else 0
				main_node._change_floor(main_node.current_floor - 1, next_branch, true)
				return
			elif cell == main_node.CellType.STAIRS_BLUE:
				main_node._change_floor(main_node.current_floor + 1, 2, false)
				return
			elif cell == main_node.CellType.STAIRS_GREEN:
				main_node._change_floor(main_node.current_floor + 1, 3, false)
				return
			elif cell == main_node.CellType.STAIRS_RED:
				main_node._change_floor(main_node.current_floor + 1, 4, false)
				return
			elif cell == main_node.CellType.STAIRS_PURPLE:
				main_node._change_floor(main_node.current_floor + 1, 5, false)
				return
			elif cell == main_node.CellType.STAIRS_GOLD:
				if main_node._current_branch == 10 and main_node.current_floor == 3:
					main_node._change_floor(0, 0, true)
				else:
					main_node._change_floor(main_node.current_floor + 1, 10, false)
				return

		if event.keycode == KEY_F:
			if player:
				var ranged_weapon = player._get_ranged_weapon() if player.has_method("_get_ranged_weapon") else null
				if ranged_weapon:
					var magazine_size = ranged_weapon.effects.get("magazine_size", 0)
					
					if magazine_size > 0:
						if player.ranged_weapon_shots_fired >= magazine_size:
							if main_node.has_node("/root/LogUI"):
								main_node.get_node("/root/LogUI").add_log("弾倉が空だ！ リロードが必要", Color.RED)
							return
						
						if player.ranged_weapon_cooldown > 0:
							if main_node.has_node("/root/LogUI"):
								main_node.get_node("/root/LogUI").add_log("遠距離武器はまだ使えない (あと%dターン)" % player.ranged_weapon_cooldown, Color.GRAY)
							return
					else:
						if player.ranged_weapon_cooldown > 0:
							if main_node.has_node("/root/LogUI"):
								main_node.get_node("/root/LogUI").add_log("遠距離武器はまだ使えない (あと%dターン)" % player.ranged_weapon_cooldown, Color.GRAY)
							return
					
					# Start targeting via TargetManager in Main
					main_node.start_ranged_attack(ranged_weapon)
				else:
					if main_node.has_node("/root/LogUI"):
						main_node.get_node("/root/LogUI").add_log("遠距離武器を装備していません。", Color.GRAY)
			return

		if event.keycode == KEY_SPACE or event.keycode == KEY_KP_5 or event.keycode == KEY_CLEAR or _is_numpad_wait_key(event):
			action_taken = true

		var direction = Vector2.ZERO
		var numpad_direction = _get_numpad_direction(event)
		if numpad_direction != Vector2.ZERO:
			direction = numpad_direction
		
		if direction == Vector2.ZERO and Input.is_action_pressed("ui_up_left"):
			direction = Vector2(-1, -1)
		elif direction == Vector2.ZERO and Input.is_action_pressed("ui_up_right"):
			direction = Vector2(1, -1)
		elif direction == Vector2.ZERO and Input.is_action_pressed("ui_down_left"):
			direction = Vector2(-1, 1)
		elif direction == Vector2.ZERO and Input.is_action_pressed("ui_down_right"):
			direction = Vector2(1, 1)
		elif direction == Vector2.ZERO:
			direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

		if direction != Vector2.ZERO:
			if player and ("is_moving" in player and player.is_moving):
				return
				
			if event.ctrl_pressed:
				var attacked = await main_node._execute_directional_attack(direction)
				if attacked:
					await main_node._end_player_turn()
				get_viewport().set_input_as_handled()
				return
			elif event.shift_pressed:
				main_node._start_auto_move(direction)
				return
			else:
				action_taken = await main_node._try_move_character(player, direction)
		
		if action_taken:
			await main_node._end_player_turn()
