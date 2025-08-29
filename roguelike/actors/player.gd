extends CharacterBody2D

const TILE_SIZE = 32  # 1タイルのサイズ（ピクセル）
const MAX_HP = 10  # Maximum health points

@onready var camera = get_parent().get_node("Camera2D")  # カメラへの参照

var hp = MAX_HP # Current health points

func _ready():
	# positionをTILE_SIZEの倍数にスナップさせる
	position = position.snapped(Vector2.ONE * TILE_SIZE)

func move(direction: Vector2):
	var target_position = position + direction * TILE_SIZE
	position = target_position
	
	# カメラを更新
	if camera:
		camera.position = position

func take_damage(amount: int):
	hp -= amount
	print("Player took ", amount, " damage. HP: ", hp)
	if hp <= 0:
		print("Player defeated!")
		# TODO: Implement game over logic
