extends Node2D

var enemy_id: String
var enemy_name: String
var death_grid: Vector2i
var death_position: Vector2
var discovered = false

func _draw():
	# A pale skull and crossed remains stay readable on both grass and stone.
	draw_line(Vector2(7, 26), Vector2(25, 17), Color(0.06, 0.04, 0.07), 5)
	draw_line(Vector2(7, 17), Vector2(25, 26), Color(0.06, 0.04, 0.07), 5)
	draw_line(Vector2(7, 26), Vector2(25, 17), Color(0.70, 0.63, 0.53), 2)
	draw_line(Vector2(7, 17), Vector2(25, 26), Color(0.70, 0.63, 0.53), 2)
	draw_rect(Rect2(10, 9, 12, 11), Color(0.08, 0.06, 0.08))
	draw_rect(Rect2(11, 10, 10, 8), Color(0.84, 0.78, 0.65))
	draw_rect(Rect2(13, 17, 6, 4), Color(0.84, 0.78, 0.65))
	draw_rect(Rect2(12, 12, 3, 3), Color(0.10, 0.08, 0.10))
	draw_rect(Rect2(17, 12, 3, 3), Color(0.10, 0.08, 0.10))
