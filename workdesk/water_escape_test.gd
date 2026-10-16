extends SceneTree

class Target extends Node2D:
	var hp = 100
	var elements = []
	func take_damage(amount, _source, incoming):
		hp -= amount
		elements = incoming

var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func run_test():
	var main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main._is_on_world_map = false
	for entity in get_nodes_in_group("entities"):
		entity.remove_from_group("entities")
	for x in range(18, 33):
		for y in range(18, 33):
			main._map_data[x][y] = main.CellType.FLOOR
	main.player.position = Vector2(25, 25) * 32
	main.player.max_mp = 30
	main.player.mp = 30
	main._calculate_fov()
	var skill = SkillDatabase.get_skill_by_id("water_escape")
	var cell = Vector2i(27, 25)
	var target = Target.new()
	target.position = Vector2(cell) * 32
	main.add_child(target)
	target.add_to_group("entities")
	var neighbor = Target.new()
	neighbor.position = Vector2(28, 25) * 32
	main.add_child(neighbor)
	neighbor.add_to_group("entities")
	main._map_data[cell.x][cell.y] = main.CellType.GRASS
	main._ignite_grass(cell)
	check(main._apply_water_escape(cell, skill), "Valid cast failed")
	check(target.hp < 100 and "water" in target.elements, "Water damage missing")
	check(neighbor.hp == 100, "Single cell attack hit neighbor")
	check(main.player.mp == 25, "MP cost not charged once")
	check(main._map_data[cell.x][cell.y] == main.CellType.WATER, "Puddle not generated")
	check(not main._burning_grass.has(cell), "Puddle left burning grass")
	check(main._astar_grid.is_point_solid(cell) and not main._astar_grid_swim.is_point_solid(cell), "Water pathfinding not updated")
	check(main.player._pending_action_id == "skill:water_escape", "Skill action was not recorded")
	for terrain in [main.CellType.WALL, main.CellType.WOOD_WALL, main.CellType.STAIRS, main.CellType.PIT, main.CellType.CRYSTAL_FLOOR]:
		main._map_data[cell.x][cell.y] = terrain
		main._visible_tiles[cell.x][cell.y] = true
		check(not main._apply_water_escape(cell, skill), "Protected terrain accepted")
		check(main._map_data[cell.x][cell.y] == terrain, "Protected terrain replaced")
	check(main.player.mp == 25, "Rejected cast consumed MP")
	main._map_data[cell.x][cell.y] = main.CellType.FLOOR
	main.player.mp = 0
	check(not main._apply_water_escape(cell, skill), "Cast without MP succeeded")
	main.player.mp = 25
	check(not main._apply_water_escape(Vector2i(31, 25), skill), "Out of range cast succeeded")
	check(not main._apply_water_escape(Vector2i(-1, 25), skill), "Out of bounds cast succeeded")
	main._visible_tiles[cell.x][cell.y] = false
	check(not main._apply_water_escape(cell, skill), "Unseen cast succeeded")
	print("WATER_ESCAPE_TEST failures=", failures)
	main.queue_free()
	await process_frame
	quit(failures)
