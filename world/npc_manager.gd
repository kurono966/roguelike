class_name NPCManager
extends Node

var main_node: Node2D
var tile_map: TileMap
var player: Node2D

const EnemyScene = preload("res://actors/enemy/enemy.tscn")
const EnemyDatabase = preload("res://actors/enemy/enemy_database.gd")

const CellType = MapDefinitions.CellType
const MAP_WIDTH = MapDefinitions.MAP_WIDTH
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT
const TILE_SIZE = MapDefinitions.TILE_SIZE

func setup(main: Node2D):
	main_node = main
	tile_map = main.tile_map
	player = main.player

func spawn_village_npcs():
	var npc_types = EnemyDatabase.get_npc_definitions(main_node.current_floor)
	if npc_types.is_empty(): return
	
	var npc_count = randi_range(3, 8)
	var spawned = 0
	
	# Walkable tiles definition
	var is_walkable = func(cell: int) -> bool:
		return cell == CellType.FLOOR or cell == CellType.GRASS or cell == CellType.ASH or cell == CellType.VOLCANIC_ASH or cell == CellType.CRYSTAL_FLOOR
	
	# Randomly select positions from walkable area of the village
	for i in range(npc_count):
		var success = false
		for attempt in range(100):
			var rx = randi_range(4, MAP_WIDTH - 5)
			var ry = randi_range(4, MAP_HEIGHT - 5)
			
			if is_walkable.call(main_node._map_data[rx][ry]):
				# Check if occupied by other entities
				var occupied = false
				if not main_node or not main_node.get_tree():
					continue
				for entity in main_node.get_tree().get_nodes_in_group("entities"):
					if is_instance_valid(entity):
						var e_grid = tile_map.local_to_map(entity.position)
						if e_grid == Vector2i(rx, ry):
							occupied = true
							break
				if not occupied:
					var type = npc_types.pick_random()
					_spawn_single_npc(type, Vector2(rx, ry) * TILE_SIZE)
					spawned += 1
					success = true
					break
		if not success:
			print("Village NPC Spawn: Failed to find valid position for NPC #", i)
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("平穏な里に辿り着いた。", Color(0.1, 1.0, 0.5))

func _spawn_single_npc(type: Dictionary, pos: Vector2):
	var npc = EnemyScene.instantiate()
	npc.enemy_name = type.name
	npc.enemy_id = type.get("id", type.name)
	npc.hp = int(type.hp)
	npc.max_hp = int(type.hp)
	npc.attack_power = int(type.atk)
	npc.exp_reward = 0
	if "color" in type: npc.base_color = type.color
	if "can_swim" in npc: npc.can_swim = type.get("swim", false)
	if "sprite" in type: npc.sprite_path = type.sprite
	if "skill" in type:
		npc.skill_id = type.skill
		npc.attack_range = type.get("range", 1)
		npc.max_skill_cooldown = type.get("cooldown", 5)
		npc.skill_cooldown = 0
	if "trade_items" in type:
		npc.trade_items = type.trade_items.duplicate()
	npc.is_npc = true
	npc.position = pos
	npc.add_to_group("npcs")
	npc.add_to_group("entities")
	main_node.add_child(npc)
	npc.visible = false
	print("NPC Spawned: ", npc.enemy_name, " at ", pos)

func spawn_ally_near_player(data: Dictionary):
	if not player or not is_instance_valid(player):
		return
	
	var player_grid = tile_map.local_to_map(player.position)
	var spawn_positions = []
	
	# Retrieve database definition to check if this ally can swim
	var can_swim_check = false
	var ally_id = data.get("enemy_id", "zakomushi")
	var db_def = EnemyDatabase.get_enemy_def(ally_id)
	if not db_def.is_empty() and db_def.get("swim", false):
		can_swim_check = true
	
	# Find valid spawn positions around the player
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			if dx == 0 and dy == 0: continue
			var test_pos = player_grid + Vector2i(dx, dy)
			if test_pos.x >= 0 and test_pos.x < MAP_WIDTH and test_pos.y >= 0 and test_pos.y < MAP_HEIGHT:
				var cell = main_node._map_data[test_pos.x][test_pos.y]
				var is_walkable = cell == CellType.FLOOR or \
								  cell == CellType.GRASS or \
								  cell == CellType.ASH or \
								  cell == CellType.VOLCANIC_ASH or \
								  cell == CellType.CRYSTAL_FLOOR or \
								  cell == CellType.ICE or \
								  cell == CellType.DOOR_OPEN or \
								  cell == CellType.STAIRS or \
								  cell == CellType.STAIRS_BLUE or \
								  cell == CellType.STAIRS_GREEN or \
								  cell == CellType.STAIRS_RED or \
								  cell == CellType.STAIRS_PURPLE or \
								  cell == CellType.STAIRS_GOLD
				
				if cell == CellType.WATER and can_swim_check:
					is_walkable = true
					
				if is_walkable:
					# Check if position is not occupied
					var occupied = false
					if not main_node or not main_node.get_tree():
						continue
					for entity in main_node.get_tree().get_nodes_in_group("entities"):
						if is_instance_valid(entity) and entity != player:
							var entity_grid = tile_map.local_to_map(entity.position)
							if entity_grid == test_pos:
								occupied = true
								break
					if not occupied:
						var dist = test_pos.distance_to(player_grid)
						spawn_positions.append({"pos": test_pos, "dist": dist})
	
	# Sort by distance and pick closest
	spawn_positions.sort_custom(func(a, b): return a.dist < b.dist)
	
	var spawn_pos = player_grid
	if spawn_positions.size() > 0:
		spawn_pos = spawn_positions[0].pos
		
	var ally = EnemyScene.instantiate()
	
	ally.enemy_name = data.get("enemy_name", "仲間")
	ally.enemy_id = data.get("enemy_id", "zakomushi")
	if ally.enemy_id == "zakomushi" and ally.enemy_name != "仲間":
		ally.enemy_id = ally.enemy_name
		
	var def = EnemyDatabase.get_enemy_def(ally.enemy_id)
	if not def.is_empty():
		ally.enemy_name = def.name
		ally.hp = data.get("hp", int(def.hp))
		ally.max_hp = data.get("max_hp", int(def.hp))
		ally.attack_power = data.get("attack", int(def.atk))
		if "color" in def: ally.base_color = def.color
		if "swim" in def: ally.can_swim = def.swim
		if "sprite_path" in data and data["sprite_path"] != "":
			ally.sprite_path = data["sprite_path"]
		elif "sprite" in def:
			ally.sprite_path = def.sprite
		else:
			ally.sprite_path = ""
		if "weak" in def: ally.weaknesses = def.weak
		if "resist" in def: ally.resistances = def.resist
		if "fire_immune" in def: ally.fire_immune = def.fire_immune
		if "on_hit" in def: ally.on_hit_effects = def.on_hit
		if "penetration" in def: ally.penetration_rate = def.penetration
		if "intelligence" in def: ally.intelligence = def.intelligence
		if "knockback" in def: ally.has_knockback = def.knockback
		if "loot" in def: ally.loot_table = def.loot
		if "trade_items" in def: ally.trade_items = def.trade_items.duplicate()
	else:
		ally.hp = data.get("hp", 10)
		ally.max_hp = data.get("max_hp", 10)
		ally.attack_power = data.get("attack", 5)
		if "sprite_path" in data:
			ally.sprite_path = data["sprite_path"]
		else:
			ally.sprite_path = ""
		
	ally.defense = data.get("defense", 0)
	ally.attack_range = data.get("attack_range", 1.5)
	
	if "is_flying" in data:
		ally.is_flying = data["is_flying"]
	if "affection" in data and "affection" in ally:
		ally.affection = data["affection"]
	if "fear" in data and "fear" in ally:
		ally.fear = data["fear"]
	if "inventory_items" in data and "inventory_items" in ally:
		ally.inventory_items = data["inventory_items"].duplicate(true)
	if "trade_items" in data and "trade_items" in ally:
		ally.trade_items = data["trade_items"].duplicate(true)
	if "level" in data and "level" in ally:
		ally.level = data["level"]
	if "xp_value" in data and "xp_value" in ally:
		ally.xp_value = data["xp_value"]
		
	ally.is_npc = true
	ally.add_to_group("allies")
	ally.add_to_group("npcs")
	ally.add_to_group("entities")
	
	ally.position = Vector2(spawn_pos) * TILE_SIZE
	main_node.add_child(ally)
	
	# Set ally AI and appearance AFTER add_child so sprite node is initialized
	ally.set_ally(player)
	ally.visible = false

# Dialog and recruitment system
var _talk_choice_npc = null
var _current_trade_npc = null
var _is_trading = false

func handle_talk():
	if not main_node or not main_node.get_tree():
		return
	var npcs = main_node.get_tree().get_nodes_in_group("npcs") + main_node.get_tree().get_nodes_in_group("allies")
	var has_visible_npc = false
	
	for npc in npcs:
		if is_instance_valid(npc) and npc != player:
			# NPC/Ally is visible (within vision)
			if main_node._can_player_recognize_entity(npc):
				has_visible_npc = true
				break
				
	if not has_visible_npc:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("話しかける相手が周りにいません。", Color.GRAY)
		return
		
	if main_node.target_manager:
		main_node.target_manager.start_talk_targeting(player.position)
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("話しかける相手を選択してください (方向キー/クリックで指定, ENTER/Vキー/左クリックで決定, ESC/右クリックでキャンセル)", Color.YELLOW)

func execute_talk_at(target_grid: Vector2i):
	# Find npc or ally at target_grid
	var target_entity = null
	if not main_node or not main_node.get_tree():
		return
	for entity in main_node.get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(entity):
			var e_grid = tile_map.local_to_map(entity.position)
			if e_grid == target_grid:
				target_entity = entity
				break
				
	if not target_entity:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("そこには誰もいません。", Color.GRAY)
		return

	var entity_name = "誰か"
	if "enemy_name" in target_entity:
		entity_name = target_entity.enemy_name
	
	if target_entity.is_in_group("npcs") or target_entity.is_in_group("allies"):
		# Check if NPC is already an ally
		if target_entity.is_in_group("allies"):
			if main_node.has_node("/root/LogUI"):
				main_node.get_node("/root/LogUI").add_log("%s: 「もう仲間だよ！」" % entity_name, Color(0.8, 1.0, 0.8))
			await main_node._end_player_turn()
			return
		
		# Check if NPC is weakened (HP <= 40%)
		var is_weakened = false
		if "hp" in target_entity and "max_hp" in target_entity:
			if target_entity.hp <= target_entity.max_hp * 0.4:
				is_weakened = true
				
		var npc_id = target_entity.enemy_id if "enemy_id" in target_entity else "default"
		var greeting = ""
		if is_weakened:
			match npc_id:
				"wanderer_swordsman", "放浪の剣士": greeting = "「ううっ、不覚にも魔物にやられてしまった... 傷が深くて動けん...」"
				"stray_mage", "はぐれ魔道士": greeting = "「あたた... 魔力も体力も底をついてしまった... 誰か助けてくれ...」"
				"villager", "村人": greeting = "「痛い、痛いよぉ... 誰か、ポーションかヒールで助けてください...」"
				"merchant", "商人": greeting = "「うう、商品も体もボロボロだ... 誰か助けてくれたら、お礼はするよ...」"
				"elder", "村の長老": greeting = "「ごほっ、ごほっ... 年寄りにはこの寒さは堪える... 誰か助けておくれ...」"
				"guard", "村の守備隊": greeting = "「くっ... 守備隊の誇りにかけて倒れるわけにはいかんが... もう限界だ...」"
				_: greeting = "「うう... 傷が痛む... 助けてくれ...」"
		else:
			match npc_id:
				"wanderer_swordsman", "放浪 of 剣士", "放浪の剣士": greeting = "「私は世界を旅する剣士だ。腕の立つ仲間を探しているのかい？」"
				"stray_mage", "はぐれ魔道士": greeting = "「私ははぐれ魔道士。何か用かい？ 魔法の研究で忙しいのだがね。」"
				"villager", "村人": greeting = "「こんにちは、旅の方。このあたりは魔物が多くて危険ですよ。」"
				"merchant", "商人": greeting = "「いらっしゃい！ 良い品が揃っているよ。見ていくだけでも歓迎さ！」"
				"elder", "村の長老": greeting = "「おお、旅の者よ。何か困ったことはないかね？」"
				"guard", "村の守備隊": greeting = "「ここは村の境界だ。警戒を怠るわけにはいかん。」"
				_: greeting = "「何か用かね？」"
				
		# Build options array
		var options = []
		if is_weakened:
			options.append("助ける")
		else:
			options.append("仲間にする")
		
		# Check if NPC has trade items
		if "trade_items" in target_entity and not target_entity.trade_items.is_empty():
			options.append("取引する")
			
		options.append("キャンセル")
		
		# Show dialog with customized title/greeting and options
		_talk_choice_npc = target_entity
		var game_ui = main_node.get_node_or_null("/root/GameUI")
		if game_ui and game_ui.has_method("show_dialog_menu"):
			# Format dialog title to show NPC Name & Greeting
			var dialog_title = "[%s]\n%s" % [entity_name, greeting]
			game_ui.show_dialog_menu(dialog_title, options)
		return
	else:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("%s は話しかけられても反応しない..." % entity_name, Color(0.8, 0.8, 0.8))
	
	await main_node._end_player_turn()

func handle_dialog_choice(option: String):
	if not _talk_choice_npc:
		return
	
	var npc = _talk_choice_npc
	_talk_choice_npc = null
	
	var entity_name = npc.enemy_name if "enemy_name" in npc else "誰か"
	
	if option == "取引する":
		if "trade_items" in npc and not npc.trade_items.is_empty():
			open_trade_menu(npc)
		else:
			if main_node.has_node("/root/LogUI"):
				main_node.get_node("/root/LogUI").add_log("%s: 「取引できるものはないよ」" % entity_name, Color(0.8, 0.8, 0.8))
			await main_node._end_player_turn()
	elif option == "仲間にする":
		_show_recruitment_demand(npc)
	elif option == "助ける":
		_help_npc(npc)
	elif option in ["100G払う", "80G払う", "30G払う", "150G払う", "120G払う", "50G払う"]:
		var cost = 50
		if option == "100G払う": cost = 100
		elif option == "80G払う": cost = 80
		elif option == "30G払う": cost = 30
		elif option == "150G払う": cost = 150
		elif option == "120G払う": cost = 120
		
		if player.gold >= cost:
			player.gold -= cost
			if main_node.PlayerUi:
				main_node.PlayerUi.update_gold(player.gold)
			if main_node.has_node("/root/LogUI"):
				main_node.get_node("/root/LogUI").add_log("%d ゴールドを支払いました。" % cost, Color.YELLOW)
			_recruit_npc(npc)
		else:
			if main_node.has_node("/root/LogUI"):
				main_node.get_node("/root/LogUI").add_log("ゴールドが足りません！", Color.RED)
			await main_node._end_player_turn()
	elif option == "エーテルを渡す":
		_recruit_with_item(npc, "ether", "エーテル")
	elif option == "銀のグミを渡す":
		_recruit_with_item(npc, "silver_gummy", "銀のグミ")
	elif option == "ポーションを渡す":
		var item_to_remove = null
		if player.equipment_component and player.equipment_component.bag_data:
			for item in player.equipment_component.bag_data.items:
				if item.id == "potion" or item.id == "high_potion":
					item_to_remove = item
					break
		if item_to_remove:
			player.equipment_component.bag_data.remove_item(item_to_remove)
			if main_node.has_node("/root/LogUI"):
				main_node.get_node("/root/LogUI").add_log("%s を渡しました。" % item_to_remove.name, Color.YELLOW)
			_recruit_npc(npc)
		else:
			if main_node.has_node("/root/LogUI"):
				main_node.get_node("/root/LogUI").add_log("ポーションを持っていません！", Color.RED)
			await main_node._end_player_turn()
	elif option == "キャンセル":
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("会話をキャンセルしました", Color(0.6, 0.6, 0.6))
		await main_node._end_player_turn()

func _show_recruitment_demand(npc):
	var entity_name = npc.enemy_name if "enemy_name" in npc else "誰か"
	var npc_id = npc.enemy_id if "enemy_id" in npc else "default"
	
	_talk_choice_npc = npc # Save it again for the next dialog choice
	
	var demand_text = ""
	var options = []
	
	match npc_id:
		"wanderer_swordsman", "放浪 of 剣士", "放浪の剣士":
			demand_text = "「私を雇うには 100 ゴールドが必要だが、払えるかい？」"
			options = ["100G払う", "キャンセル"]
		"stray_mage", "はぐれ魔道士":
			demand_text = "「私を連れていきたいなら、研究資金として 80 ゴールド、あるいは「エーテル」を1個譲ってほしいね。」"
			options = ["80G払う", "エーテルを渡す", "キャンセル"]
		"villager", "村人":
			demand_text = "「旅のお供をするには、支度金として 30 ゴールドか「銀のグミ」をいただけないでしょうか？」"
			options = ["30G払う", "銀のグミを渡す", "キャンセル"]
		"merchant", "商人":
			demand_text = "「商売を休んでお前さんについていくからには、保証金として 150 ゴールドもらうよ。」"
			options = ["150G払う", "キャンセル"]
		"guard", "村の守備隊":
			demand_text = "「任務外で同行するとなれば、手当として 120 ゴールド必要だ。」"
			options = ["120G払う", "キャンセル"]
		"elder", "村の長老":
			demand_text = "「老いた体を動かすのは骨が折れる。50 ゴールドか「ポーション」を分けてくれんかのぉ？」"
			options = ["50G払う", "ポーションを渡す", "キャンセル"]
		_:
			demand_text = "「旅のお供をするには、50 ゴールド必要じゃ。」"
			options = ["50G払う", "キャンセル"]
			
	var game_ui = main_node.get_node_or_null("/root/GameUI")
	if game_ui and game_ui.has_method("show_dialog_menu"):
		var dialog_title = "[%s]\n%s" % [entity_name, demand_text]
		game_ui.show_dialog_menu(dialog_title, options)

func _recruit_with_item(npc, item_id: String, item_name: String):
	var item_to_remove = null
	if player.equipment_component and player.equipment_component.bag_data:
		for item in player.equipment_component.bag_data.items:
			if item.id == item_id:
				item_to_remove = item
				break
	if item_to_remove:
		player.equipment_component.bag_data.remove_item(item_to_remove)
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("%s を渡しました。" % item_name, Color.YELLOW)
		_recruit_npc(npc)
	else:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("%s を持っていません！" % item_name, Color.RED)
		await main_node._end_player_turn()

func _help_npc(npc):
	var entity_name = npc.enemy_name if "enemy_name" in npc else "誰か"
	
	# Check for Potion / High Potion
	var potion_item = null
	if player.equipment_component and player.equipment_component.bag_data:
		for item in player.equipment_component.bag_data.items:
			if item.id == "potion" or item.id == "high_potion":
				potion_item = item
				break
				
	# Check for Heal Skill & MP
	var has_heal_skill = player.known_skills.has("heal")
	var has_enough_mp = player.mp >= 5
	
	var helped = false
	var method_used = ""
	
	if potion_item:
		# Consume potion
		player.equipment_component.bag_data.remove_item(potion_item)
		helped = true
		method_used = "potion"
	elif has_heal_skill and has_enough_mp:
		# Consume MP
		player.mp -= 5
		if main_node.PlayerUi:
			main_node.PlayerUi.update_mp(player.mp, player.max_mp)
		player._update_skill_ui()
		helped = true
		method_used = "heal"
		
	if helped:
		# Heal the NPC to full
		npc.heal(npc.max_hp - npc.hp)
		
		# Make them an ally
		npc.add_to_group("allies")
		if npc.is_in_group("npcs"):
			npc.remove_from_group("npcs")
		if npc.has_method("set_ally"):
			npc.set_ally(player)
			
		# Log the result
		if main_node.has_node("/root/LogUI"):
			if method_used == "potion":
				main_node.get_node("/root/LogUI").add_log("ポーションを使って %s を治療した！" % entity_name, Color(0.3, 1.0, 0.3))
			else:
				main_node.get_node("/root/LogUI").add_log("ヒールを使って %s を治療した！" % entity_name, Color(0.3, 1.0, 0.3))
			main_node.get_node("/root/LogUI").add_log("%s が仲間になった！" % entity_name, Color(0.0, 1.0, 0.5))
			
		# Visual effect on the NPC
		main_node._spawn_skill_particles(npc.position + Vector2(16, 16), "heal", 0.6)
	else:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("%s: 「うう... ポーションかヒール魔法があれば...」" % entity_name, Color(0.8, 0.8, 0.8))
			main_node.get_node("/root/LogUI").add_log("回復させる手段（ポーションまたはヒール魔法とMP5）がありません！", Color.RED)
			
	await main_node._end_player_turn()

func _recruit_npc(npc):
	var entity_name = npc.enemy_name if "enemy_name" in npc else "誰か"
	
	# Check if NPC is already an ally
	if npc.is_in_group("allies"):
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("%s はすでに仲間だ" % entity_name, Color.GRAY)
		await main_node._end_player_turn()
		return
	
	# Add NPC to allies group
	npc.add_to_group("allies")
	
	# Remove from npcs group if present
	if npc.is_in_group("npcs"):
		npc.remove_from_group("npcs")
	
	# Change NPC behavior to follow player
	if npc.has_method("set_ally"):
		npc.set_ally(player)
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("%s を仲間にした！" % entity_name, Color(0.0, 1.0, 0.5))
	
	await main_node._end_player_turn()

func open_trade_menu(npc):
	_current_trade_npc = npc
	_is_trading = true
	var npc_name = npc.enemy_name if "enemy_name" in npc else "商人"
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("%s と取引を開始した", Color(1.0, 0.85, 0.0))
	
	# Open trade UI via GameUI
	if main_node.GameUI and main_node.GameUI.has_method("open_trade_menu"):
		main_node.GameUI.open_trade_menu(npc)
	
	# Don't end turn - trade menu is modal
	# Turn will end after trade is completed

func cancel_trade():
	if _is_trading:
		_is_trading = false
		_current_trade_npc = null
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("取引をキャンセルしました", Color.GRAY)

func handle_shop_purchase():
	if not player: return
	if main_node._shop_uses_this_floor >= main_node.SHOP_MAX_USES_PER_FLOOR:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("No more trades on this floor.", Color.GRAY)
		return
	# Shop only available at stairs tiles
	var p_grid = tile_map.local_to_map(player.position)
	if p_grid.x < 0 or p_grid.x >= MAP_WIDTH or p_grid.y < 0 or p_grid.y >= MAP_HEIGHT:
		return
	var cell = main_node._map_data[p_grid.x][p_grid.y]
	var on_stairs = main_node._is_stairs_cell(cell)
	if not on_stairs:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("A trader only appears at the stairs.", Color.GRAY)
		return
	if main_node.SHOP_OFFERS.is_empty():
		return

	var offer = main_node.SHOP_OFFERS.pick_random()
	var price = int(offer["price"])
	var item_id = str(offer["id"])
	if player.gold < price:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("Not enough gold. Need %dG." % price, Color.RED)
		return

	var item = main_node.ItemDatabase.get_item_by_id(item_id)
	if item == null:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("Trade failed. (Unknown item)", Color.RED)
		return

	if not player.pickup_item(item):
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("Inventory full. Trade canceled.", Color.RED)
		return

	player.gold -= price
	main_node._shop_uses_this_floor += 1
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("Traded %dG for %s." % [price, item.name], Color(1.0, 0.85, 0.0))
	await main_node._end_player_turn()
