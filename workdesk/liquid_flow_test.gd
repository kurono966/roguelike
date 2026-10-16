extends Node

var main
var failures = 0
const C = MapDefinitions.CellType

func _ready(): call_deferred("_run")

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func reset():
	main._liquid_state.clear()
	main._hazards.clear()
	main._frozen_tiles.clear()
	main._burning_grass.clear()
	main._height_data = ElevationMap.normalize([], main.MAP_WIDTH, main.MAP_HEIGHT)
	for x in range(main.MAP_WIDTH):
		for y in range(main.MAP_HEIGHT): main._map_data[x][y] = C.WALL
	main.player.position = Vector2(20, 20) * 32
	main._map_data[20][20] = C.FLOOR
	main._turn_count = 1

func volume() -> int:
	var total = 0
	for data in main._liquid_state.values(): total += int(data.volume)
	return total

func _run():
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	for group in ["enemies", "npcs", "allies", "items"]:
		for node in get_tree().get_nodes_in_group(group): node.queue_free()
	await get_tree().process_frame
	main._is_on_world_map = false
	main.current_floor = 2
	var source = Vector2i(25, 25)
	var dest = Vector2i(26, 25)
	reset()
	main._map_data[25][25] = C.WATER
	main._height_data[25][25] = 2
	main._map_data[26][25] = C.GRASS
	main._height_data[26][25] = 0
	main._setup_pathfinding()
	main._ignite_grass(dest)
	main.liquid_manager.process_turn()
	check(main._map_data[25][25] == C.FLOOR and main._map_data[26][25] == C.WATER, "Water did not flow down cliff")
	check(volume() == 1, "Flow created/destroyed water")
	check(not main._burning_grass.has(dest), "Flood did not extinguish grass")
	check(main._astar_grid.is_point_solid(dest) and not main._astar_grid_swim.is_point_solid(dest), "Flow did not update movement modes")
	check(not main._astar_grid.is_point_solid(source), "Drained tile remains blocked")
	main.liquid_manager.process_turn()
	check(main._map_data[26][25] == C.WATER and volume() == 1, "Water flowed uphill or duplicated")
	main._save_current_floor_to_cache_with_key("liquid_test")
	main._liquid_state.clear()
	main._load_floor_from_cache("liquid_test", false)
	check(volume() == 1 and main._liquid_state[dest].ground == C.GRASS, "Cache lost volume/underlying terrain")
	reset()
	main._map_data[25][25] = C.WATER
	main._height_data[25][25] = 2
	main._map_data[26][25] = C.STAIRS
	main._height_data[26][25] = 0
	main._map_data[25][26] = C.DOOR_CLOSED
	main._height_data[25][26] = 0
	main.liquid_manager.process_turn()
	check(main._map_data[26][25] == C.STAIRS and main._map_data[25][26] == C.DOOR_CLOSED and volume() == 1, "Flow erased stairs or passed a closed door")
	reset()
	# Two higher sources collect in a lower pool; same-level depths later balance.
	for x in [24, 25, 26]: main._map_data[x][25] = C.WATER
	main._height_data[24][25] = 2
	main._height_data[26][25] = 2
	main._height_data[25][25] = 0
	main.liquid_manager.process_turn()
	check(volume() == 3 and main._liquid_state[source].volume == 3, "Lower pool did not collect volume")
	main._map_data[25][26] = C.FLOOR
	main._height_data[25][26] = 0
	main.liquid_manager.process_turn()
	check(volume() == 3 and main._map_data[25][26] == C.WATER, "Pool did not equalize along level ground")
	reset()
	main._map_data[25][25] = C.ICE
	main._liquid_state[source] = {"kind": C.WATER, "volume": 2, "ground": C.FLOOR}
	main._frozen_tiles[source] = {"permanent": true}
	main._height_data[25][25] = 2
	main._map_data[26][25] = C.FLOOR
	main._height_data[26][25] = 0
	main.liquid_manager.process_turn()
	check(main._map_data[25][25] == C.ICE and volume() == 2, "Frozen water moved/lost volume")
	main._frozen_tiles.clear()
	main._map_data[25][25] = C.WATER
	main.liquid_manager.process_turn()
	check(main._map_data[26][25] == C.WATER and volume() == 2, "Melted water did not resume flowing")
	reset()
	main._map_data[25][25] = C.LAVA
	main._height_data[25][25] = 2
	main._map_data[26][25] = C.FLOOR
	main._height_data[26][25] = 0
	main.liquid_manager.process_turn()
	check(main._map_data[25][25] == C.LAVA, "Lava ignored slower flow cadence")
	main._turn_count = 3
	main.liquid_manager.process_turn()
	check(main._map_data[26][25] == C.LAVA and volume() == 1, "Lava did not flow downhill")
	reset()
	main._map_data[25][25] = C.FLOOR
	main._height_data[25][25] = 2
	main._map_data[26][25] = C.FLOOR
	main._height_data[26][25] = 0
	main._hazards[source] = {"type": "acid_puddle", "duration": 7, "damage": 2}
	main.liquid_manager.process_turn()
	check(main._hazards.has(dest) and main._hazards[dest].duration == 7, "Acid did not flow while preserving lifetime")
	print("LIQUID_FLOW_TEST failures=", failures)
	await get_tree().create_timer(1.0).timeout
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
