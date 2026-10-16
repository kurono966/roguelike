extends CanvasLayer

var player
var title: Label
var summary: Label
var buttons: Array[Button] = []
var choices: VBoxContainer
var hint: Label
var _previous_paused = false
var _owns_pause = false

func _ready():
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_previous_paused = get_tree().paused
	_owns_pause = true
	get_tree().paused = true
	var shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.02, 0.04, 0.88)
	add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = PanelContainer.new()
	panel.theme = load("res://ui/themes/main_theme.tres")
	center.add_child(panel)
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	title = Label.new()
	title.add_theme_color_override("font_color", Color.GOLD)
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	summary = Label.new()
	column.add_child(summary)
	choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 8)
	column.add_child(choices)
	hint = Label.new()
	column.add_child(hint)
	refresh()

func refresh():
	if not player.has_pending_growth_choices():
		close()
		return
	var color_turn = player.is_connector_growth_turn()
	var remaining_levels = maxi(player.pending_growth_choices, player.pending_connector_choices)
	title.text = "LEVEL UP — Lv.%d：%s" % [player.level - remaining_levels + 1, "コネクタの色を選択" if color_turn else "能力を選択"]
	summary.text = "力 %d / 技 %d / 知力 %d　最大HP %d / 最大MP %d\n赤 %d / 青 %d / 黄 %d / 紫 %d\n毎レベル、能力1つ＋色1つを選択（残り%dレベル）" % [player.strength, player.dexterity, player.intelligence, player.max_hp, player.max_mp, player.get_connector_affinity("red"), player.get_connector_affinity("blue"), player.get_connector_affinity("yellow"), player.get_connector_affinity("purple"), remaining_levels]
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	buttons.clear()
	var options = player.get_growth_options()
	for index in range(options.size()):
		var option = options[index]
		var button = Button.new()
		button.text = "%d. %s — %s" % [index + 1, option.label, option.detail]
		button.custom_minimum_size = Vector2(560, 46)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if color_turn:
			var palette = {"red": Color("ff756b"), "blue": Color("76b5ff"), "yellow": Color("ffe66b"), "purple": Color("d397ff")}
			button.add_theme_color_override("font_color", palette[option.key])
			button.add_theme_color_override("font_focus_color", palette[option.key])
			button.tooltip_text = "習得に関わるスキル（レベル・能力の条件も必要）\n" + player.get_skill_color_requirements_text(str(option.key))
		button.pressed.connect(_choose.bind(str(option.key)))
		choices.add_child(button)
		buttons.append(button)
	hint.text = "1～%dキー、または↑↓とEnterで選択。選択中はゲームが停止します。" % options.size()
	buttons.front().grab_focus()

func _choose(key: String):
	if not _owns_pause: return
	if player.is_connector_growth_turn():
		player.choose_connector_growth(key)
	else:
		player.choose_level_growth(key)

func _unhandled_key_input(event: InputEvent):
	if not event is InputEventKey or not event.pressed or event.is_echo(): return
	var options = player.get_growth_options()
	if event.keycode >= KEY_1 and event.keycode < KEY_1 + options.size():
		_choose(str(options[event.keycode - KEY_1].key))
	get_viewport().set_input_as_handled()

func close():
	_release_pause()
	if is_instance_valid(player): player._growth_selection = null
	queue_free()

func _release_pause():
	if _owns_pause and is_inside_tree():
		_owns_pause = false
		get_tree().paused = _previous_paused

func _exit_tree():
	_release_pause()
