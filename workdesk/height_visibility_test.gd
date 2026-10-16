extends Node

var failures = 0
var main
const C = MapDefinitions.CellType

func _ready(): call_deferred("_run")

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _run():
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	for group in ["enemies", "npcs", "allies", "items"]:
		for actor in get_tree().get_nodes_in_group(group): actor.queue_free()
	await get_tree().process_frame
	main._is_on_world_map = false
	main.current_floor = 2
	main._height_data = ElevationMap.normalize([], main.MAP_WIDTH, main.MAP_HEIGHT)
	main._steam_tiles.clear()
	main._traps.clear()
	main._burning_grass.clear()
	main._frozen_tiles.clear()
	main._liquid_state.clear()
	for x in range(main.MAP_WIDTH):
		for y in range(main.MAP_HEIGHT):
			main._map_data[x][y] = C.WALL
			main._explored_tiles[x][y] = false
	for x in range(22, 31): main._map_data[x][25] = C.FLOOR
	var observer = Vector2i(25, 25)
	var ridge = Vector2i(26, 25)
	var target = Vector2i(27, 25)
	main.player.position = Vector2(observer) * 32
	main._height_data[25][25] = 0
	main._height_data[26][25] = 2
	main._height_data[27][25] = 0
	main._setup_pathfinding()
	var enemy = load("res://actors/enemy/enemy.tscn").instantiate()
	enemy.position = Vector2(target) * 32
	enemy.add_to_group("enemies")
	enemy.add_to_group("entities")
	main.add_child(enemy)
	main._calculate_fov()
	check(main._visible_tiles[26][25], "Front of the ridge should be visible")
	check(not main._visible_tiles[27][25] and not main._explored_tiles[27][25], "Hidden valley leaked into FOV/exploration")
	check(not enemy.visible and not main.visibility_manager.is_entity_visible_to_player(enemy), "Enemy behind ridge remained visible")
	check(not main._has_line_of_sight(observer, target) and not main._has_line_of_sight(target, observer), "AI/attack LOS ignored the ridge")
	check(not main.turn_manager.can_actor_see(enemy, main.player), "Enemy perception ignored ridge")
	var npc = load("res://actors/enemy/enemy.tscn").instantiate()
	npc.position = Vector2(observer) * 32
	npc.is_npc = true
	npc.add_to_group("npcs")
	npc.add_to_group("entities")
	main.add_child(npc)
	check(not main.turn_manager.can_actor_see(npc, enemy), "Friendly NPC perception ignored ridge")
	npc.add_to_group("allies")
	check(not main.turn_manager.can_actor_see(npc, enemy), "Ally perception ignored ridge")
	npc.attack_range = 4
	npc.hit_rate = 1.0
	enemy.hp = 100
	enemy.max_hp = 100
	enemy.status_effects["paralyze"] = {"duration": 20}
	await main.turn_manager.process_enemy_turns()
	check(enemy.hp == 100, "Ally attacked a target hidden behind high terrain")
	var hp_before = enemy.hp
	await main._handle_ranged_attack(main.player, target, 1, "arrow")
	check(enemy.hp == hp_before, "Projectile passed through a terrain ridge")
	# High ground can see a low target over an intermediate normal-height tile.
	main._height_data[25][25] = 2
	main._height_data[26][25] = 1
	main._calculate_fov()
	check(main._visible_tiles[27][25] and enemy.visible, "High observer cannot see into the valley")
	check(main._has_line_of_sight(observer, target), "High-to-low LOS incorrectly blocked")
	check(main.turn_manager.can_actor_see(npc, enemy), "Ally cannot see from high ground")
	check(main.turn_manager.can_actor_see(enemy, npc), "Enemy cannot recognize visible high target")
	check(main.turn_manager._get_closest_hostile(enemy) != null, "Enemy did not acquire a visible NPC/player")
	await main.turn_manager.process_enemy_turns()
	check(enemy.hp < hp_before, "Ally did not attack after target became visible")
	await main._handle_ranged_attack(main.player, target, 1, "arrow")
	check(enemy.hp < hp_before, "Projectile could not reach a visible low target")
	# Each solid obstacle remains opaque even to high observers.
	for obstacle in [C.WALL, C.WOOD_WALL, C.DOOR_CLOSED, C.DOOR_LOCKED, C.TREE, C.TREE_FRUIT, C.ROCK]:
		main._map_data[26][25] = obstacle
		main._calculate_fov()
		check(not main._visible_tiles[27][25] and not main._has_line_of_sight(observer, target), "Obstacle became transparent: " + str(obstacle))
	main._map_data[26][25] = C.FLOOR
	main._steam_tiles[ridge] = {"turns_remaining": 3, "density": 3}
	main._calculate_fov()
	check(not main._visible_tiles[27][25] and not main._has_line_of_sight(observer, target), "Height ignored steam occlusion")
	main._steam_tiles.clear()
	main.set_tile_height(ridge, 2)
	# A tall target remains visible over lower ground.
	main._height_data[25][25] = 0
	main._height_data[26][25] = 1
	main._height_data[28][25] = 2
	main._calculate_fov()
	check(main._visible_tiles[28][25], "Visible higher terrain was shadowed as if it were a valley")
	# Submerged bed does not replace the water/ice surface for sight rays.
	main._height_data[27][25] = 0
	main._map_data[26][25] = C.WATER
	main._height_data[26][25] = 0
	check(not main._has_height_line_of_sight(observer, target), "Sight ray used water bed instead of surface")
	print("HEIGHT_VISIBILITY_TEST failures=", failures)
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
