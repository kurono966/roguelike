extends CanvasLayer

@onready var hp_bar = $HPContainer/HPBar
@onready var hp_label = $HPContainer/HPLabel

# HPバーの最大幅を保持
var max_hp_bar_width: float = 190.0

func update_hp(current_hp: int, max_hp: int) -> void:
	# HPバーの幅を更新
	var hp_ratio = float(current_hp) / max(1, max_hp)  # 0除算を防ぐ
	var new_width = max_hp_bar_width * hp_ratio
	hp_bar.size.x = max(0, new_width)  # マイナスにならないように
	
	# HPラベルを更新
	hp_label.text = "HP: %d/%d" % [current_hp, max_hp]

	# アウトラインを設定して見やすくする
	hp_label.add_theme_constant_override("outline_size", 4)
	hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	
	# HPの割合に応じて色を変更
	var bar_color: Color
	
	if hp_ratio < 0.3:  # HPが30%以下の場合
		bar_color = Color(5.9, 0.1, 0.1)  # 赤
		# ラベルの色を変更
		hp_label.add_theme_color_override("font_color", Color(1, 1, 1))  # 白
	elif hp_ratio < 0.6:  # HPが30%~60%の場合
		bar_color = Color(4.0, 3.75, 0.0)  # 黄色
		hp_label.add_theme_color_override("font_color", Color(1, 1, 1))  # 白
	else:  # HPが60%以上
		bar_color = Color(0.2, 5.0, 0.2)  # 緑
		hp_label.add_theme_color_override("font_color", Color(1, 1, 1))  # 白
	
	# バーの色を更新
	hp_bar.self_modulate = bar_color
