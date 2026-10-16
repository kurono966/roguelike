extends SceneTree

class Target extends Node2D:
	var hp = 100
	var hits = 0
	var reaction: Callable
	func take_damage(amount, _source, _elements):
		hp -= amount
		hits += 1
		if reaction.is_valid(): reaction.call()

var failures = 0
var main

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func target_at(cell: Vector2i):
	var target = Target.new()
	target.position = Vector2(cell) * 32
	target.add_to_group("entities")
	main.add_child(target)
	return target

func run_test():
	main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	for entity in get_nodes_in_group("entities"):
		entity.remove_from_group("entities")
	var first = target_at(Vector2i(25, 25))
	var second = target_at(Vector2i(26, 25))
	var third = target_at(Vector2i(27, 25))
	var entrant = target_at(Vector2i(30, 25))
	var distant = target_at(Vector2i(25, 28))
	# Damage reactions simulate knockback and movement while the effect resolves.
	first.reaction = func():
		second.position = Vector2(30, 30) * 32
		entrant.position = Vector2(26, 25) * 32
	main._apply_chain_lightning(main.player, first, 5, 3, [])
	check(first.hits == 1 and second.hits == 1 and third.hits == 1, "Original adjacent chain was not resolved atomically from one snapshot")
	check(entrant.hits == 0, "Target moving into adjacency joined an existing discharge")
	check(distant.hits == 0, "Nonadjacent target was chained")
	# Movement after the action must not continue a pending asynchronous chain.
	distant.position = Vector2(28, 25) * 32
	await create_timer(0.6).timeout
	check(entrant.hits == 0 and distant.hits == 0, "Late movement was included in chain")
	for target in [first, second, third, entrant, distant]:
		target.hits = 0
	first.reaction = Callable()
	second.position = Vector2(26, 25) * 32
	entrant.position = Vector2(30, 25) * 32
	distant.position = Vector2(25, 28) * 32
	main._map_data[25][25] = main.CellType.WATER
	main._apply_chain_lightning(main.player, first, 5, 1, [])
	check(first.hits == 1 and second.hits == 1 and third.hits == 0, "Chain depth limit ignored")
	check(distant.hits == 0, "Water allowed nonadjacent chain jump")
	var diagonal = target_at(Vector2i(24, 24))
	var hit_list = []
	main._apply_chain_lightning(main.player, first, 5, 3, hit_list)
	check(diagonal.hits == 1, "Diagonal adjacency no longer conducts")
	check(first.hits == 2 and second.hits == 2, "Cycle hit an actor more than once per discharge")
	var caster = load("res://actors/enemy/enemy.tscn").instantiate()
	caster.apply_definition({"id": "test", "name": "雷の術者", "skill": "lightning", "atk": 5})
	main.add_child(caster)
	await main._execute_enemy_skill_v2(caster, Vector2i(25, 25))
	check(first.hits == 3, "Enemy lightning entry point did not resolve")
	print("LIGHTNING_SNAPSHOT_TEST failures=", failures)
	quit(1 if failures else 0)
