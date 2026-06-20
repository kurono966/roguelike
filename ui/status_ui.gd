extends Control

var panel: Panel
var left_rich_label: RichTextLabel
var right_rich_label: RichTextLabel
var close_button: Button

func _ready():
	# Make it cover the screen but with margins
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	
	# Background Panel
	panel = Panel.new()
	add_child(panel)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.96) # Harmonious dark slate
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.4, 0.6, 0.8) # Sleek blue outline
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	
	# Title
	var title = Label.new()
	panel.add_child(title)
	title.text = "◆ キャラクター詳細ステータス ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 4)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 20
	
	# HBoxContainer for 2 columns
	var hbox = HBoxContainer.new()
	panel.add_child(hbox)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 48
	hbox.offset_top = 90
	hbox.offset_right = -48
	hbox.offset_bottom = -100
	hbox.add_theme_constant_override("separation", 60)
	
	# Left Column (RichTextLabel)
	left_rich_label = RichTextLabel.new()
	hbox.add_child(left_rich_label)
	left_rich_label.bbcode_enabled = true
	left_rich_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_rich_label.scroll_active = true
	left_rich_label.add_theme_font_size_override("normal_font_size", 18)
	left_rich_label.add_theme_font_size_override("bold_font_size", 18)
	left_rich_label.add_theme_font_size_override("bold_italics_font_size", 18)
	left_rich_label.add_theme_font_size_override("italics_font_size", 18)
	left_rich_label.add_theme_font_size_override("mono_font_size", 18)
	
	# Right Column (RichTextLabel)
	right_rich_label = RichTextLabel.new()
	hbox.add_child(right_rich_label)
	right_rich_label.bbcode_enabled = true
	right_rich_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_rich_label.scroll_active = true
	right_rich_label.add_theme_font_size_override("normal_font_size", 18)
	right_rich_label.add_theme_font_size_override("bold_font_size", 18)
	right_rich_label.add_theme_font_size_override("bold_italics_font_size", 18)
	right_rich_label.add_theme_font_size_override("italics_font_size", 18)
	right_rich_label.add_theme_font_size_override("mono_font_size", 18)
	
	# Close Button
	close_button = Button.new()
	panel.add_child(close_button)
	close_button.text = "閉じる (Esc)"
	close_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	close_button.offset_bottom = -25
	close_button.custom_minimum_size = Vector2(210, 50)
	close_button.add_theme_font_size_override("font_size", 20)
	
	# Style close button
	var btn_style_normal = StyleBoxFlat.new()
	btn_style_normal.bg_color = Color(0.15, 0.25, 0.35)
	btn_style_normal.set_border_width_all(1)
	btn_style_normal.border_color = Color(0.4, 0.6, 0.8)
	btn_style_normal.set_corner_radius_all(6)
	close_button.add_theme_stylebox_override("normal", btn_style_normal)
	
	var btn_style_hover = StyleBoxFlat.new()
	btn_style_hover.bg_color = Color(0.2, 0.35, 0.5)
	btn_style_hover.set_border_width_all(2)
	btn_style_hover.border_color = Color(0.5, 0.8, 1.0)
	btn_style_hover.set_corner_radius_all(6)
	close_button.add_theme_stylebox_override("hover", btn_style_hover)
	close_button.add_theme_stylebox_override("focus", btn_style_hover)
	
	close_button.pressed.connect(close)
	
	get_viewport().size_changed.connect(update_layout)
	update_layout()

func update_layout():
	var viewport_size = get_viewport_rect().size
	panel.size = Vector2(
		min(1100.0, max(480.0, viewport_size.x - 40.0)),
		min(700.0, max(360.0, viewport_size.y - 40.0))
	)
	panel.position = (viewport_size - panel.size) / 2

func open():
	visible = true
	update_status_info()
	update_layout() # Ensure correct position when opening
	close_button.grab_focus()

func close():
	visible = false

func _input(event):
	if not visible:
		return
		
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
		
	# Also toggle off if @ key is pressed again
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_AT or event.unicode == 64:
			close()
			get_viewport().set_input_as_handled()
			return

func update_status_info():
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		left_rich_label.text = "[color=red]プレイヤーが見つかりません。[/color]"
		right_rich_label.text = ""
		return
		
	var gs = get_node_or_null("/root/GameState")
	
	# Class translation
	var class_name_str = "Balanced"
	if gs:
		match gs.player_class:
			0: class_name_str = "Balanced (バランス)"
			1: class_name_str = "Warrior (戦士)"
			2: class_name_str = "Rogue (盗賊)"
			3: class_name_str = "Mage (魔法使い)"
			4: class_name_str = "Swimmer (水泳選手)"
			99: class_name_str = "DEBUG (デバッグ)"
			
	var player_name_str = gs.player_name if gs else "Hero"
	
	# Equipment Stats
	var eq = {
		"attack": 0,
		"defense": 0,
		"max_hp": 0,
		"max_mp": 0,
		"strength": 0,
		"dexterity": 0,
		"intelligence": 0
	}
	if player.has_method("_get_equipment_stats"):
		eq = player._get_equipment_stats()
	
	# Attributes representation
	var str_total = player.strength + eq.strength
	var dex_total = player.dexterity + eq.dexterity
	var int_total = player.intelligence + eq.intelligence
	
	var str_text = "%d" % player.strength
	if eq.strength != 0:
		str_text += " [color=green](%+d)[/color]" % eq.strength
		
	var dex_text = "%d" % player.dexterity
	if eq.dexterity != 0:
		dex_text += " [color=green](%+d)[/color]" % eq.dexterity
		
	var int_text = "%d" % player.intelligence
	if eq.intelligence != 0:
		int_text += " [color=green](%+d)[/color]" % eq.intelligence

	# Active Status Effects
	var effects_text = ""
	if player.status_effects.is_empty():
		effects_text = "[color=#888888]なし[/color]"
	else:
		var list = []
		for eff_id in player.status_effects:
			var eff_name = eff_id
			var duration = player.status_effects[eff_id].get("duration", 0)
			if eff_id == "paralysis": eff_name = "麻痺"
			elif eff_id == "burn": eff_name = "炎上"
			elif eff_id == "sleep": eff_name = "睡眠"
			list.append("[color=yellow]%s[/color] (残り %d ターン)" % [eff_name, duration])
		effects_text = "\n".join(list)

	# Special traits
	var traits = []
	if player.can_swim:
		traits.append("[color=cyan]・水泳可能 (水路を移動可能)[/color]")
	if player.has_knockback:
		traits.append("[color=orange]・ノックバック付与 (攻撃時敵を弾き飛ばす)[/color]")
	
	# Check for class specific abilities
	if gs and gs.player_class == 2: # Rogue
		traits.append("[color=green]・草眼 (草むらのなかの視界が広い)[/color]")
		
	var traits_text = "\n".join(traits) if not traits.is_empty() else "[color=#888888]特になし[/color]"

	# Left Column BBCode
	var left_text = ""
	left_text += "[b][font_size=22]基本ステータス[/font_size][/b]\n"
	left_text += "[color=#aaaaaa]名前:[/color] [b]%s[/b]\n" % player_name_str
	left_text += "[color=#aaaaaa]クラス:[/color] %s\n" % class_name_str
	left_text += "[color=#aaaaaa]レベル:[/color] [color=yellow][b]%d[/b][/color]\n" % player.level
	left_text += "[color=#aaaaaa]経験値:[/color] %d / %d\n" % [player.exp, player.exp_to_next_level]
	left_text += "[color=#aaaaaa]所持金:[/color] [color=gold][b]%d Gold[/b][/color]\n" % player.gold
	left_text += "\n"
	left_text += "[b][font_size=22]バイタル[/font_size][/b]\n"
	left_text += "[color=#aaaaaa]ＨＰ:[/color] [color=red][b]%d[/b][/color] / [color=red]%d[/color]\n" % [player.hp, player.max_hp]
	left_text += "[color=#aaaaaa]ＭＰ:[/color] [color=cyan][b]%d[/b][/color] / [color=cyan]%d[/color]\n" % [player.mp, player.max_mp]
	left_text += "[color=#aaaaaa]満腹度:[/color] %d / %d\n" % [player.hunger, player.max_hunger]
	left_text += "\n"
	left_text += "[b][font_size=22]基礎能力値[/font_size][/b]\n"
	left_text += "[color=#aaaaaa]力 (STR):[/color] %s (合計: [b]%d[/b])\n" % [str_text, str_total]
	left_text += "[color=#aaaaaa]器用さ (DEX):[/color] %s (合計: [b]%d[/b])\n" % [dex_text, dex_total]
	left_text += "[color=#aaaaaa]知力 (INT):[/color] %s (合計: [b]%d[/b])\n" % [int_text, int_total]
	
	left_rich_label.text = left_text

	# Right Column (Combat Stats and Equipment)
	var right_text = ""
	right_text += "[b][font_size=22]戦闘能力値[/font_size][/b]\n"
	right_text += "[color=#aaaaaa]攻撃力:[/color] [color=orange][b]%d[/b][/color]\n" % player.attack_power
	right_text += "[color=#aaaaaa]防御力:[/color] [color=green][b]%d[/b][/color]\n" % player.defense_power
	right_text += "[color=#aaaaaa]会心率:[/color] %.1f%%\n" % (player.crit_rate * 100.0)
	right_text += "[color=#aaaaaa]貫通率:[/color] %.1f%%\n" % (player.penetration_rate * 100.0)
	
	right_text += "[color=#aaaaaa]命中率:[/color] %.1f%%\n" % (clamp(player.hit_rate, 0.0, 1.0) * 100.0)

	# Organization density details
	var bonus_info = player.get_inventory_bonus_state() if player.has_method("get_inventory_bonus_state") else {"message": ""}
	if bonus_info.message != "":
		right_text += "[color=#aaaaaa]整頓補正:[/color]%s\n" % bonus_info.message
	
	right_text += "\n"
	right_text += "[b][font_size=22]状態異常 / 特性[/font_size][/b]\n"
	right_text += "[color=#aaaaaa]状態異常:[/color]\n%s\n" % effects_text
	right_text += "[color=#aaaaaa]特殊特性:[/color]\n%s\n" % traits_text
	right_text += "\n"
	
	# Equipment details
	right_text += "[b][font_size=22]装備中のアイテム[/font_size][/b]\n"
	var equipped_items_text = ""
	if player.equipment_component and player.equipment_component.equipment_data and not player.equipment_component.equipment_data.items.is_empty():
		var items_list = []
		for item in player.equipment_component.equipment_data.items:
			var stat_parts = []
			if item.attack != 0: stat_parts.append("攻+%d" % item.attack)
			if item.defense != 0: stat_parts.append("防+%d" % item.defense)
			if item.max_hp != 0: stat_parts.append("HP+%d" % item.max_hp)
			if item.max_mp != 0: stat_parts.append("MP+%d" % item.max_mp)
			if item.strength != 0: stat_parts.append("力+%d" % item.strength)
			if item.dexterity != 0: stat_parts.append("器+%d" % item.dexterity)
			if item.intelligence != 0: stat_parts.append("知+%d" % item.intelligence)
			
			if item.effects.get("hit_bonus", 0.0) != 0.0:
				stat_parts.append("命中+%.1f%%" % (float(item.effects["hit_bonus"]) * 100.0))
			if item.effects.get("crit_bonus", 0.0) != 0.0:
				stat_parts.append("会心+%.1f%%" % (float(item.effects["crit_bonus"]) * 100.0))
			if item.effects.get("penetration_bonus", 0.0) != 0.0:
				stat_parts.append("貫通+%.1f%%" % (float(item.effects["penetration_bonus"]) * 100.0))

			var stat_desc = ""
			if not stat_parts.is_empty():
				stat_desc = " (" + "/".join(stat_parts) + ")"
			
			items_list.append("・[color=yellow]%s[/color]%s" % [item.name, stat_desc])
		equipped_items_text = "\n".join(items_list)
	else:
		equipped_items_text = "[color=#888888]装備なし[/color]"
		
	right_text += equipped_items_text
	if player.equipment_component:
		var connector_bonus = player.equipment_component.get_connector_bonus()
		right_text += "\n[color=#8fdcff]接続辺[/color]\n"
		right_text += "[color=#ff4d40]赤 %d: 攻撃+%d[/color]\n" % [connector_bonus.red, connector_bonus.red]
		right_text += "[color=#5599ff]青 %d: 防御+%d[/color]\n" % [connector_bonus.blue, connector_bonus.blue]
		right_text += "[color=#ffe04d]黄 %d: 命中+%d%%[/color]\n" % [connector_bonus.yellow, connector_bonus.yellow * 3]
		right_text += "[color=#bd66ff]紫 %d: 会心+%d%%[/color]\n" % [connector_bonus.purple, connector_bonus.purple * 3]
	
	right_rich_label.text = right_text
