extends Node2D

const Motion = preload("res://actors/grid_visual_motion.gd")
var player
var tile_map: TileMap
var failures: int = 0

func _ready():
	call_deferred("_run")

func _check(condition: bool, message: String):
	if not condition:
		failures += 1
		push_error(message)

func _stop_auto_explore(_reason: String = ""):
	# Exercise the real stop path without generating an entire world.
	var main = load("res://world/main.gd").new()
	main.player = player
	main._is_auto_exploring = true
	main._stop_auto_explore()
	_check(not main._is_auto_exploring, "Exploration did not stop")
	main.free()

func _run():
	var camera = Camera2D.new()
	camera.name = "Camera2D"
	add_child(camera)
	tile_map = TileMap.new()
	add_child(tile_map)
	player = load("res://actors/player.tscn").instantiate()
	add_child(player)
	player.set_process(false)
	var enemy = load("res://actors/enemy/enemy.tscn").instantiate()
	add_child(enemy)
	enemy.hp = 100
	enemy.max_hp = 100
	player.hp = 100
	player.max_hp = 100
	var combat = load("res://world/combat_manager.gd").new()
	add_child(combat)
	combat.setup(self)
	enemy.hit_rate = 0.0

	# Attack while the enemy still visually occupies its previous tile.
	for i in range(4):
		enemy.position = Vector2(32, 32)
		enemy.move_to_grid(Vector2i(2, 1))
		await combat.handle_attack(enemy, player)
		await get_tree().create_timer(0.15).timeout
		_check(enemy.position == Vector2(64, 32), "Attack changed enemy tile")
		_check(enemy.sprite.position.is_equal_approx(Vector2(16, 16)), "Attack retained a movement offset")

	# Recoil must replace movement, and repeated hits must not accumulate offsets.
	for actor in [player, enemy]:
		actor.move_to_grid(Vector2i(3, 3))
		actor.take_damage(1, enemy if actor == player else player)
		actor.take_damage(1, enemy if actor == player else player)
		await get_tree().create_timer(0.2).timeout
		_check(actor.position == Vector2(96, 96), "Hit changed logical tile")
		_check(actor.get_node("Sprite2D").position.is_equal_approx(Vector2(16, 16)), "Repeated hits retained an offset")

	player.move_to_grid(Vector2i(4, 3))
	await get_tree().process_frame
	_check(player.is_moving, "Movement completed before its visual tween")
	await get_tree().create_timer(0.16).timeout
	_check(not player.is_moving, "Movement flag did not clear")

	# Fast exploration followed immediately by encounter/hit/stop.
	for i in range(8):
		player.move_to_grid(Vector2i(5 + i, 3), true)
		player.take_damage(1, enemy)
		_stop_auto_explore()
		await get_tree().create_timer(0.13).timeout
		_check(player.position == Vector2(5 + i, 3) * 32, "Encounter changed player tile")
		_check(player.get_node("Sprite2D").position.is_equal_approx(Vector2(16, 16)), "Encounter left player one tile behind")

	var slide = Motion.slide(enemy, Vector2(320, 128), 0.15)
	_check(enemy.position == Vector2(320, 128), "Forced movement did not commit grid immediately")
	await slide.finished
	_check(enemy.sprite.position.is_equal_approx(Vector2(16, 16)), "Forced movement left visual offset")
	print("GRID_MOTION_TEST: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
