extends CanvasLayer

# 強化されたログUI - RichTextLabelを使用して装飾をサポート
var log_rich_label: RichTextLabel
var log_panel: Panel
var mode_label: Label
var log_history: Array = []
const MAX_LINES = 250  # 履歴として保持する行数
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
	
	mode_label = Label.new()
	mode_label.position = Vector2(10, 5)
	mode_label.add_theme_font_size_override("font_size", 12)
	mode_label.add_theme_color_override("font_color", Color(0.65, 0.67, 0.72))
	log_panel.add_child(mode_label)

	# RichTextLabelの作成
	log_rich_label = RichTextLabel.new()
	log_rich_label.bbcode_enabled = true
	log_rich_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_rich_label.offset_left = 10
	log_rich_label.offset_top = 25
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
		
		var context = _get_log_context()
		var detail = _is_detail_message(message)
		if not log_history.is_empty() and log_history.back().get("raw", "") == message and log_history.back().get("text", "") == bb_message and log_history.back().get("context", "") == context:
			log_history.back()["count"] += 1
		else:
			log_history.append({"text": bb_message, "raw": message, "count": 1, "detail": detail, "context": context})
		if log_history.size() > MAX_LINES:
			log_history = log_history.slice(log_history.size() - MAX_LINES)
		_update_display()
		print("Log added: ", message)

func _get_log_context() -> String:
	var player = get_tree().get_first_node_in_group("player")
	if not player: return ""
	var main = player.get_parent()
	if not main or not "_turn_count" in main: return ""
	var floor_name = "地上" if main.current_floor == 0 else "%d階" % main.current_floor
	return "%s / T%d" % [floor_name, main._turn_count]

func _is_detail_message(message: String) -> bool:
	for prefix in ["HP回復 +", "MP回復 +", "水の中で傷が癒える", "結晶の魔力でMPが回復した", "装備変更:", "遠距離武器が再使用可能", "'H'", "'L'"]:
		if message.begins_with(prefix): return true
	return message.contains("ターゲットを選択してください") or message.ends_with("のターゲットを選択してください")

func _update_display():
	if not log_rich_label: return
	var scroll = log_rich_label.get_v_scroll_bar()
	var preserve_scroll = display_mode == DisplayMode.EXPANDED and scroll.value < scroll.max_value - scroll.page - 2.0
	var old_scroll = scroll.value
	log_rich_label.scroll_following = not preserve_scroll
	var full_text = ""
	var last_context = ""
	for entry in log_history:
		if display_mode != DisplayMode.EXPANDED and entry.get("detail", false): continue
		var context: String = entry.get("context", "")
		var prefix = ""
		if context != "" and context != last_context:
			prefix = "[color=#858994]〈%s〉[/color] " % context
		last_context = context
		var line: String = entry.get("text", "")
		var count: int = entry.get("count", 1)
		if count > 1: line += " [color=#a6a6a6]×%d[/color]" % count
		full_text += prefix + line + "\n"
	log_rich_label.text = full_text
	if preserve_scroll: scroll.call_deferred("set", "value", old_scroll)

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
	if mode_label: mode_label.text = "ログ履歴・詳細を表示中   L：非表示" if expanded else "ログ   L：拡大して詳細を見る"
	var viewport_size = get_viewport().get_visible_rect().size
	var available = (viewport_size - Vector2(40, 40)).max(Vector2.ONE)
	var panel_size = Vector2(500, 160)
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

	_update_display()
