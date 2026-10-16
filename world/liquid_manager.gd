extends RefCounted

const C = MapDefinitions.CellType
const CAPACITY = 4
const DIRECTIONS = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const FLOODABLE = [C.FLOOR, C.GRASS, C.ASH, C.VOLCANIC_ASH, C.CRYSTAL_FLOOR, C.DOOR_OPEN]

var main

func process_turn():
	if main._is_on_world_map: return
	_sync_liquids()
	# Snapshot sources: transferred water never moves twice in one turn.
	var sources = main._liquid_state.keys()
	var changed = {}
	var lava_arrivals = []
	for pos in sources:
		var data: Dictionary = main._liquid_state[pos]
		var kind = int(data.kind)
		if int(data.volume) <= 0: continue
		if main._map_data[pos.x][pos.y] != kind or main._frozen_tiles.has(pos): continue
		if kind == C.LAVA and main._turn_count % 3 != 0: continue
		var target = _choose_target(pos, kind)
		if target == pos: continue
		var source_height = main.get_tile_height(pos)
		var dest_height = main.get_tile_height(target)
		# Strictly downhill movement, or volume equalization on the same level.
		if dest_height > source_height: continue
		var dest_volume = int(main._liquid_state.get(target, {}).get("volume", 0))
		if dest_height == source_height and int(data.volume) - dest_volume < 2: continue
		if not main._liquid_state.has(target):
			main._liquid_state[target] = {"kind": kind, "volume": 0, "ground": main._map_data[target.x][target.y]}
		var dest: Dictionary = main._liquid_state[target]
		data.volume -= 1
		dest.volume += 1
		changed[pos] = true
		changed[target] = true
	for pos in changed:
		var data: Dictionary = main._liquid_state[pos]
		if int(data.volume) <= 0:
			main._map_data[pos.x][pos.y] = int(data.ground)
			main._liquid_state.erase(pos)
		else:
			if int(data.kind) == C.LAVA and main._map_data[pos.x][pos.y] != C.LAVA: lava_arrivals.append(pos)
			main._map_data[pos.x][pos.y] = int(data.kind)
			if main._burning_grass.erase(pos) and int(data.kind) == C.WATER:
				main._create_steam(pos)
			if int(data.kind) == C.LAVA:
				for dir in DIRECTIONS: main._ignite_grass(pos + dir)
		main._update_astar_tile(pos, false)
	for entity in main.get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(entity) or entity.is_queued_for_deletion() or not entity.has_method("take_damage"): continue
		if "is_flying" in entity and entity.is_flying: continue
		if main._is_fire_immune(entity): continue
		if main.tile_map.local_to_map(entity.position) in lava_arrivals:
			entity.take_damage(5, null, ["fire"])
	_process_acid()
	if not changed.is_empty():
		if is_instance_valid(main.player):
			var pos = main.tile_map.local_to_map(main.player.position)
			var cell = main._map_data[pos.x][pos.y]
			main.player.update_terrain_info(cell == C.GRASS, cell == C.WATER, cell == C.CRYSTAL_FLOOR)
			if cell == C.WATER: main.player.remove_effect("burn")
		# Flooded grass and newly produced steam can change visibility immediately.
		main._calculate_fov()
		main._draw_map()

func _sync_liquids():
	# ICE retains its water volume until melting, while external terrain edits
	# invalidate stale liquid entries rather than resurrecting deleted water.
	for pos in main._liquid_state.keys():
		if not main._is_grid_in_bounds(pos):
			main._liquid_state.erase(pos)
			continue
		var cell = main._map_data[pos.x][pos.y]
		if cell != int(main._liquid_state[pos].kind) and not (cell == C.ICE and int(main._liquid_state[pos].kind) == C.WATER):
			main._liquid_state.erase(pos)
	for x in range(main._map_data.size()):
		for y in range(main._map_data[x].size()):
			var cell = main._map_data[x][y]
			var pos = Vector2i(x, y)
			if cell in [C.WATER, C.LAVA] and not main._liquid_state.has(pos):
				main._liquid_state[pos] = {"kind": cell, "volume": 1, "ground": C.FLOOR}

func _choose_target(pos: Vector2i, kind: int) -> Vector2i:
	var best = pos
	var best_level = main.get_tile_height(pos) * CAPACITY + int(main._liquid_state[pos].volume)
	for offset in range(4):
		# Rotate tie-breaking so the simulation has no permanent northward bias.
		var next = pos + DIRECTIONS[(offset + main._turn_count) % 4]
		if not main._is_grid_in_bounds(next) or next.x == 0 or next.y == 0 or next.x == main.MAP_WIDTH - 1 or next.y == main.MAP_HEIGHT - 1: continue
		if main._frozen_tiles.has(next): continue
		var cell = main._map_data[next.x][next.y]
		if cell != kind and cell not in FLOODABLE: continue
		if main.get_tile_height(next) > main.get_tile_height(pos): continue
		var volume = int(main._liquid_state.get(next, {}).get("volume", 0))
		if volume >= CAPACITY: continue
		var level = main.get_tile_height(next) * CAPACITY + volume
		if level < best_level:
			best = next
			best_level = level
	return best

func _process_acid():
	# Acid remains a timed damaging puddle and conserves its remaining lifetime.
	var reserved = {}
	for pos in main._hazards.keys():
		var data: Dictionary = main._hazards[pos]
		if data.get("type", "") != "acid_puddle": continue
		var target = pos
		for dir in DIRECTIONS:
			var next = pos + dir
			if not main._is_grid_in_bounds(next) or reserved.has(next) or main._hazards.has(next): continue
			if main._map_data[next.x][next.y] not in FLOODABLE: continue
			if main.get_tile_height(next) < main.get_tile_height(target): target = next
		if target == pos: continue
		reserved[target] = true
		main._hazards.erase(pos)
		main._hazards[target] = data
		main.hazard_manager.remove_hazard_visual(pos)
		main.hazard_manager.spawn_hazard_visual(target, "acid_puddle")
