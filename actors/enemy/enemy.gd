extends CharacterBody2D

const TILE_SIZE = 32  # 1タイルのサイズ（ピクセル）

var hp = 5 # Enemy's health points

func move(direction: Vector2):
	var target_position = position + direction * TILE_SIZE
	position = target_position

func take_damage(amount: int):
	hp -= amount
	print("Enemy took ", amount, " damage. HP: ", hp)
	if hp <= 0:
		print("Enemy defeated!")
		queue_free() # Remove the enemy node
