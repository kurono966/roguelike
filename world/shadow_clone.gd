class_name ShadowClone
extends Node2D

# 二重の薬で生成される「影」。実体を持たず、対象キャラクターの行動を
# 1ターン遅れで再現する。移動や通行の妨げにはならない。

const TILE_SIZE = 32

var source = null            # 再現対象のキャラクター（プレイヤーまたは敵）
var turns_remaining: int = 0 # 残りターン数
var history: Array = []      # {turn: int, action: Dictionary} の行動記録
var _reproduce_from_turn: int = 0  # このターン数に達したら記録済み行動の再生を開始
var _last_recorded_turn: int = -1  # 同一ターンに二重に記録しないためのガード
var _is_executing: bool = false    # 再現中フラグ（連鎖記録の防止）

# 影は本体の「姿」を借りて行動するため、戦闘時は本体のステータスを反映する。
var is_shadow: bool = true
var attack_power: int = 1
var hit_rate: float = 0.85
var defense: int = 0
var enemy_name: String = "影の分身"
var skill_cooldown: int = 0
var max_skill_cooldown: int = 0
var known_skills: Array[String] = []  # ソースのスキルをコピー

@onready var sprite: Sprite2D = $Sprite2D
var _wobble_time: float = 0.0


func _ready() -> void:
	z_index = 3 # 床より上、キャラクターより下
	add_to_group("shadow_clones")
	# 影は「実体」ではないので以下には属さない:
	#   entities / enemies / npcs / allies / player
	# → 攻撃されず、通行も塞がず、敵ターンの処理対象にもならない。


func _process(delta: float) -> void:
	_wobble_time += delta
	# ゆらゆら揺れるアニメーション（重なっていても視認できるように）
	var wobble_x = sin(_wobble_time * 3.0) * 4.0
	var wobble_y = cos(_wobble_time * 2.5) * 4.0
	if sprite:
		sprite.position = Vector2(TILE_SIZE / 2.0 + wobble_x, TILE_SIZE / 2.0 + wobble_y)


func setup(p_source, p_main, duration: int, current_turn: int) -> void:
	source = p_source
	turns_remaining = duration
	# 生成ターンには行動せず、次のターンから1ターン遅れで再生する。
	# 生成ターン(current_turn)に記録された行動は、current_turn+1 に再生される。
	_reproduce_from_turn = current_turn
	_copy_combat_stats()
	_build_visual()


func _copy_combat_stats() -> void:
	if not is_instance_valid(source) or not (source is Node):
		return
	if "attack_power" in source:
		attack_power = int(source.attack_power)
	elif source.has_method("get_attack_power"):
		attack_power = int(source.get_attack_power())
	if "hit_rate" in source:
		hit_rate = float(source.hit_rate)
	if "defense" in source:
		defense = int(source.defense)
	# スキルをコピー
	if "known_skills" in source:
		known_skills = source.known_skills.duplicate()
	elif "base_known_skills" in source:
		known_skills = source.base_known_skills.duplicate()
	# 表示名は本体の名前を引き継ぎつつ「影」であることを明示する
	var src_name = "分身"
	if "enemy_name" in source:
		src_name = source.enemy_name
	elif source.is_in_group("player"):
		src_name = "あなた"
	enemy_name = "%s(影)" % src_name


func _build_visual() -> void:
	# 対象の姿を半透明で描画する。対象が敵なら敵スプライト、プレイヤーなら @ を模した配色。
	var tex: Texture2D = null
	if is_instance_valid(source):
		var src_sprite = source.get_node_or_null("Sprite2D") if source is Node else null
		if src_sprite and src_sprite is Sprite2D and src_sprite.texture:
			tex = src_sprite.texture
	if tex == null:
		tex = AsciiArtGenerator.create_ascii_sprite("@", Color(0.6, 0.6, 1.0), false)
	if sprite:
		sprite.texture = tex
		sprite.position = Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
		sprite.scale = Vector2(1.0, 1.0)
		# 半透明の青紫色にして「影」であることを表現
		sprite.modulate = Color(0.55, 0.55, 1.0, 0.55)


func record_action(action: Dictionary, current_turn: int) -> void:
	# 同一ターン内での重複記録を防ぐ
	if current_turn == _last_recorded_turn:
		return
	_last_recorded_turn = current_turn
	history.append({"turn": current_turn, "action": action})
	# 行動履歴は必要な範囲だけ保持する（再生に必要な直近分 + 余裕）
	var max_keep = 64
	if history.size() > max_keep:
		history = history.slice(history.size() - max_keep)


func get_action_for_turn(turn: int) -> Dictionary:
	# 指定ターンに記録された行動を返す（なければ空）
	for entry in history:
		if entry.get("turn", -1) == turn:
			return entry.get("action", {})
	return {}


func get_grid() -> Vector2i:
	return Vector2i(int(position.x / TILE_SIZE), int(position.y / TILE_SIZE))


func is_valid() -> bool:
	return is_instance_valid(source) and turns_remaining > 0


# 影が「回復」行動を再現した時の見た目専用の処理。
# 影にHPは無いため数値上の回復はせず、演出のみ行う。
func heal(_amount: int) -> void:
	if has_method("_spawn_skill_particles"):
		_spawn_skill_particles(position + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0), "heal", 0.6)
	var float_text = load("res://ui/floating_text.tscn")
	if float_text:
		var ft = float_text.instantiate()
		ft.position = Vector2(TILE_SIZE / 2.0, -4)
		ft.set_text("+回復", Color(0.3, 1.0, 0.3))
		add_child(ft)


func _spawn_skill_particles(pos: Vector2, particle_type: String, duration: float = 0.5) -> void:
	var main = get_parent()
	if main and main.has_method("_spawn_skill_particles"):
		main._spawn_skill_particles(pos, particle_type, duration)
		return
	var particles = CPUParticles2D.new()
	particles.position = pos
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.amount = 20
	particles.lifetime = duration
	particles.color = Color(0.3, 1.0, 0.3, 1.0)
	particles.spread = 180.0
	add_child(particles)
	var timer = get_tree().create_timer(duration + 0.2)
	timer.timeout.connect(particles.queue_free)
