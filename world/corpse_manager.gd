extends Node2D

const Trace = preload("res://world/corpse_trace.gd")
const EnemyScene = preload("res://actors/enemy/enemy.tscn")
const ATTACK_GAIN = 2
var main
var corpses: Array = []
var rng = RandomNumberGenerator.new()

func setup(owner_main):
	main = owner_main
	z_index = 3 # Above vegetation, below items and actors; never blocks navigation.
	rng.randomize()

func add_corpse(enemy_id: String, enemy_name: String, death_position: Vector2):
	if main._is_on_world_map: return null
	var cell = main.tile_map.local_to_map(death_position + Vector2(16, 16))
	if not main._is_grid_in_bounds(cell): return null
	var corpse = Trace.new()
	corpse.enemy_id = enemy_id
	corpse.enemy_name = enemy_name
	corpse.death_grid = cell
	corpse.death_position = death_position
	corpse.position = Vector2(cell) * MapDefinitions.TILE_SIZE
	corpse.add_to_group("corpses")
	add_child(corpse)
	corpses.append(corpse)
	refresh_visibility()
	return corpse

func remove_corpse(corpse):
	if not corpses.has(corpse): return
	corpses.erase(corpse)
	if is_instance_valid(corpse):
		corpse.hide()
		corpse.queue_free()

func clear_all():
	for corpse in corpses.duplicate(): remove_corpse(corpse)

func refresh_visibility():
	for corpse in corpses:
		var pos = corpse.death_grid
		var seen = not main._is_on_world_map and main._is_grid_in_bounds(pos) and main._visible_tiles[pos.x][pos.y]
		corpse.discovered = corpse.discovered or seen
		corpse.visible = not main._is_on_world_map and corpse.discovered
		corpse.modulate = Color.WHITE if seen else Color(0.35, 0.35, 0.35)

func serialize() -> Array:
	var result = []
	for corpse in corpses:
		result.append({"enemy_id": corpse.enemy_id, "enemy_name": corpse.enemy_name,
			"x": corpse.death_grid.x, "y": corpse.death_grid.y,
			"death_x": corpse.death_position.x, "death_y": corpse.death_position.y,
			"discovered": corpse.discovered})
	return result

func restore(entries: Array):
	clear_all()
	for entry in entries:
		var pos = Vector2(float(entry.get("death_x", int(entry.get("x", 0)) * 32)), float(entry.get("death_y", int(entry.get("y", 0)) * 32)))
		var corpse = add_corpse(str(entry.get("enemy_id", "")), str(entry.get("enemy_name", "残骸")), pos)
		if corpse: corpse.discovered = corpse.discovered or bool(entry.get("discovered", false))
	refresh_visibility()

func find_target(actor) -> Dictionary:
	var origin = main.tile_map.local_to_map(actor.position)
	var best = {}
	var best_distance = INF
	for corpse in corpses:
		if not main.turn_manager.can_actor_see(actor, corpse): continue
		var distance = Vector2(origin).distance_squared_to(Vector2(corpse.death_grid))
		if distance >= best_distance: continue
		var grid = main._astar_grid_fly if actor.is_flying else (main._astar_grid_swim if actor.can_swim else main._astar_grid)
		var path = grid.get_id_path(origin, corpse.death_grid)
		if path.is_empty(): continue
		best = {"corpse": corpse, "path": path}
		best_distance = distance
	return best

func act(actor) -> bool:
	if main._is_on_world_map: return false
	var target = find_target(actor)
	if target.is_empty(): return false # Normal aggressive AI handles this turn.
	var corpse = target.corpse
	if target.path.size() == 1:
		resolve_corpse(actor, corpse)
	else:
		var direction = Vector2(target.path[1] - target.path[0])
		await main._try_move_character(actor, direction)
	return true

func resolve_corpse(actor, corpse):
	if not corpses.has(corpse): return
	var seen = corpse.visible and main._visible_tiles[corpse.death_grid.x][corpse.death_grid.y]
	var revived = null
	if rng.randf() < 0.5: revived = resurrect(corpse)
	if revived == null: actor.attack_power += ATTACK_GAIN
	if seen:
		var log_ui = main.get_node_or_null("/root/LogUI")
		if log_ui:
			var text = "%s は %s を蘇生した！" % [actor.enemy_name, corpse.enemy_name] if revived else "%s は %s の残骸を取り込み、攻撃力が%d上がった！" % [actor.enemy_name, corpse.enemy_name, ATTACK_GAIN]
			log_ui.add_log(text, Color(0.75, 0.55, 0.95))
	remove_corpse(corpse)

func resurrect(corpse):
	var definition = EnemyDatabase.get_enemy_def(corpse.enemy_id)
	if definition.is_empty(): return null
	# The keeper occupies the death tile: place the revived enemy beside it.
	for offset in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var cell = corpse.death_grid + offset
		if not main._is_grid_in_bounds(cell) or not main.can_step_height(corpse.death_grid, cell): continue
		if main._map_data[cell.x][cell.y] in [MapDefinitions.CellType.DOOR_CLOSED, MapDefinitions.CellType.DOOR_LOCKED]: continue
		if not main.map_controller.is_walkable(cell, definition.get("swim", false), definition.get("fly", false)): continue
		var occupied = false
		for entity in get_tree().get_nodes_in_group("entities"):
			if not is_instance_valid(entity) or entity.is_queued_for_deletion() or not entity is Node2D: continue
			if entity.has_method("take_damage") and main.tile_map.local_to_map(entity.position) == cell:
				occupied = true
				break
		if occupied: continue
		var enemy = EnemyScene.instantiate()
		enemy.apply_definition(definition)
		enemy.enemy_name = corpse.enemy_name
		enemy.position = Vector2(cell) * MapDefinitions.TILE_SIZE
		enemy.add_to_group("enemies")
		enemy.add_to_group("entities")
		main.add_child(enemy)
		main.visibility_manager.update_single_entity_visibility(enemy)
		return enemy
	return null
