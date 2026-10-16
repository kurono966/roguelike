extends CanvasLayer

# 強化されたログUI - RichTextLabelを使用して装飾をサポート
var log_rich_label: RichTextLabel
var log_panel: Panel
var log_history: Array = []
var _last_log_message: String = ""
var _last_log_bbcode: String = ""
var _last_log_count: int = 0
const MAX_LINES = 50  # 履歴として保持する行数
enum DisplayMode { NORMAL, EXPANDED, HIDDEN }
var display_mode: DisplayMode = DisplayMode.NORMAL

func get_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.85) # Dark translucent
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.25, 0.28, 1.0) # Muted metallic
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# テーマのロード
	var main_theme = load("res://ui/themes/main_theme.tres")
	
	# 背景パネルの作成
	log_panel = Panel.new()
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_panel.offset_left = 20
	log_panel.offset_bottom = -20
	log_panel.offset_top = -150  # Height of 130px
	log_panel.offset_right = 520  # Width of 500px
	
	log_panel.add_theme_stylebox_override("panel", get_panel_style())
	log_panel.theme = main_theme
	add_child(log_panel)
	
	# RichTextLabelの作成
	log_rich_label = RichTextLabel.new()
	log_rich_label.bbcode_enabled = true
	log_rich_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_rich_label.offset_left = 10
	log_rich_label.offset_top = 5
	log_rich_label.offset_right = -10
	log_rich_label.offset_bottom = -5
	
	log_rich_label.theme = main_theme
	log_rich_label.add_theme_constant_override("outline_size", 0) # No outlines for clean aesthetic
	log_rich_label.scroll_active = true
	log_rich_label.scroll_following = true
	
	log_panel.add_child(log_rich_label)
	get_viewport().size_changed.connect(_apply_display_mode)
	_apply_display_mode()
	
	# 初期メッセージ
	add_log("ローグライクへようこそ！", Color.GOLD)
	add_log("'H' キーでヘルプを表示", Color.CYAN)
	add_log("'L'キーでログ：通常 → 拡大 → 非表示", Color.GRAY)
	
	print("Enhanced LogUI initialized!")

func add_log(message: String, color: Color = Color.WHITE):
	if log_rich_label:
		# Map input color to dark fantasy palette
		var final_color = Color(0.75, 0.75, 0.75) # Default/Normal log: thin light gray
		
		# Detect standard colors and map them to our limited palette:
		if color == Color.GREEN or color == Color.GREEN_YELLOW or color == Color(0.3, 1.0, 0.3) or color == Color(0.5, 1.0, 0.5):
			final_color = Color(0.35, 0.65, 0.4) # Muted green (good event)
		elif color == Color.RED or color == Color(1.0, 0.4, 0.2) or color == Color(1.0, 0.5, 0.5) or color == Color.ORANGE:
			final_color = Color(0.75, 0.25, 0.25) # Muted red (bad event)
		elif color == Color.CYAN or color == Color.BLUE or color == Color(0.3, 0.6, 1.0):
			final_color = Color(0.4, 0.55, 0.75) # Muted blue (system/info)
		elif color == Color.GOLD or color == Color.YELLOW or color == Color(1.0, 0.8, 0.0):
			final_color = Color(0.85, 0.68, 0.25) # Muted gold (important info)
		elif color == Color.GRAY or color == Color.LIGHT_GRAY:
			final_color = Color(0.55, 0.55, 0.55) # Dim gray
		else:
			# If color has high brightness or is close to white, keep it as thin gray
			if color.v > 0.8 and color.s < 0.2:
				final_color = Color(0.75, 0.75, 0.75)
			else:
				# General fallback: check hue to map to nearest palette color
				var hue = color.h
				if color.s < 0.15:
					final_color = Color(0.75, 0.75, 0.75)
				elif hue >= 0.25 and hue < 0.45: # Green-ish
					final_color = Color(0.35, 0.65, 0.4)
				elif hue >= 0.45 and hue < 0.7: # Blue-ish
					final_color = Color(0.4, 0.55, 0.75)
				elif hue >= 0.12 and hue < 0.25: # Yellow/Gold
					final_color = Color(0.85, 0.68, 0.25)
				else: # Red/Orange/Purple
					final_color = Color(0.75, 0.25, 0.25)
					
		# BBCode string conversion
		var hex_color = final_color.to_html(false)
		var bb_message = ""
		if message.begins_with("[color="):
			bb_message = message
		else:
			bb_message = "[color=#%s]%s[/color]" % [hex_color, message]
		
		# 同一内容の連続ログは1行にまとめ、末尾の回数だけを更新する。
		# 間に別のログが入った場合は別イベントとして扱う。
		if message == _last_log_message and bb_message == _last_log_bbcode and not log_history.is_empty():
			_last_log_count += 1
			log_history[log_history.size() - 1] = {
				"text": bb_message,
				"count": _last_log_count,
			}
		else:
			_last_log_message = message
			_last_log_bbcode = bb_message
			_last_log_count = 1
			log_history.append({
				"text": bb_message,
				"count": _last_log_count,
			})
		_update_display()
		print("Log added: ", message)

func _update_display():
	if not log_rich_label:
		return
		
	var display_lines = log_history
	if log_history.size() > MAX_LINES:
		log_history = log_history.slice(log_history.size() - MAX_LINES)
		display_lines = log_history
	
	var full_text = ""
	for entry in display_lines:
		var line: String = entry.get("text", "")
		var count: int = entry.get("count", 1)
		if count > 1:
			line += " x %d" % count
		full_text += line + "\n"
	
	log_rich_label.text = full_text

func _input(event):
	if event.is_action_pressed("toggle_log") and not event.is_echo():
		toggle_visibility()
		get_viewport().set_input_as_handled()

func toggle_visibility():
	display_mode = (int(display_mode) + 1) % DisplayMode.size() as DisplayMode
	_apply_display_mode()

func _apply_display_mode():
	if not log_panel or not log_rich_label: return
	log_panel.visible = display_mode != DisplayMode.HIDDEN
	var expanded = display_mode == DisplayMode.EXPANDED
	var viewport_size = get_viewport().get_visible_rect().size
	var available = (viewport_size - Vector2(40, 40)).max(Vector2.ONE)
	var panel_size = Vector2(500, 130)
	if expanded:
		panel_size = Vector2(maxf(500, viewport_size.x * 0.8), maxf(130, viewport_size.y * 0.7))
		panel_size = panel_size.min(Vector2(1100, 700))
	panel_size = panel_size.min(available)
	log_panel.offset_left = 20
	log_panel.offset_right = 20 + panel_size.x
	log_panel.offset_bottom = -20
	log_panel.offset_top = -20 - panel_size.y
	for font_key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		if expanded:
			log_rich_label.add_theme_font_size_override(font_key, 20)
		else:
			log_rich_label.remove_theme_font_size_override(font_key)
