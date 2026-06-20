extends Control

var panel: Panel
var rich_label: RichTextLabel
var close_button: Button

func _ready():
	# Make it cover the screen but with margins
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	
	# Background Panel
	panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 50
	panel.offset_top = 50
	panel.offset_right = -50
	panel.offset_bottom = -50
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.5)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	
	# Title
	var title = Label.new()
	title.text = "ヘルプ / 操作方法"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 15
	panel.add_child(title)
	
	# Close Button
	close_button = Button.new()
	close_button.text = "閉じる (Esc)"
	close_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	close_button.offset_bottom = -20
	close_button.custom_minimum_size = Vector2(120, 30)
	close_button.pressed.connect(close)
	panel.add_child(close_button)
	
	# Content
	rich_label = RichTextLabel.new()
	rich_label.bbcode_enabled = true
	rich_label.scroll_active = true
	rich_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	rich_label.offset_left = 30
	rich_label.offset_top = 60
	rich_label.offset_right = -30
	rich_label.offset_bottom = -70
	
	var help_text = """
[b]移動:[/b] 矢印キー, テンキー (斜め移動対応)
[b]攻撃:[/b] 敵に体当たり / Sキー / Tabキー (隣接時)
[b]足踏み(待機):[/b] Space, テンキー5

[b]アイテムを拾う:[/b] G
[b]インベントリ:[/b] I (Escで閉じる)
[b]ステータス詳細:[/b] @ (Escで閉じる)
[b]スキルメニュー:[/b] K
[b]休憩 (HP/MP回復):[/b] Q

[b]遠距離攻撃:[/b] F (射撃モード -> クリック/Fで発射)
[b]投げる:[/b] T (投擲モード -> クリック/Enterで投げる)
[b]決定/行動:[/b] Enter, F, 左クリック
[b]キャンセル:[/b] Esc, 右クリック, Space

[b]ログ表示切替:[/b] L
[b]ヘルプ:[/b] ? / H

[color=#888888]--- デバッグ機能 ---[/color]
[color=#aaaaaa]F1: 強化
F2: 次の階層へジャンプ
F5: セーブ
F9: ロード
F12: God Mode切替[/color]
"""
	rich_label.text = help_text.strip_edges()
	panel.add_child(rich_label)

func open():
	visible = true
	# Pause game? Ideally yes, but depends on game structure. 
	# Since input is handled by InputHandler, we just overlay this.
	
func close():
	visible = false

func _input(event):
	if not visible:
		return
		
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
