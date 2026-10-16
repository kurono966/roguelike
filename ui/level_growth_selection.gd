extends CanvasLayer

var player
var title: Label
var summary: Label
var buttons: Array[Button] = []
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
	for index in range(player.GROWTH_OPTIONS.size()):
		var option = player.GROWTH_OPTIONS[index]
		var button = Button.new()
		button.text = "%d. %s  —  %s" % [index + 1, option.label, option.detail]
		button.custom_minimum_size = Vector2(520, 46)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_choose.bind(str(option.key)))
		column.add_child(button)
		buttons.append(button)
	var hint = Label.new()
	hint.text = "1～3キー、または↑↓とEnterで選択。選択中はゲームが停止します。"
	column.add_child(hint)
	refresh()
	buttons.front().grab_focus()

func refresh():
	if player.pending_growth_choices <= 0:
		close()
		return
	title.text = "LEVEL UP  —  Lv.%d の成長を選択" % (player.level - player.pending_growth_choices + 1)
	summary.text = "力 %d / 技 %d / 知力 %d　最大HP %d / 最大MP %d\n1つ選択してください（残り%d回）" % [player.strength, player.dexterity, player.intelligence, player.max_hp, player.max_mp, player.pending_growth_choices]

func _choose(key: String):
	if not _owns_pause: return
	player.choose_level_growth(key)

func _unhandled_key_input(event: InputEvent):
	if not event is InputEventKey or not event.pressed or event.is_echo(): return
	if event.keycode >= KEY_1 and event.keycode < KEY_1 + player.GROWTH_OPTIONS.size():
		_choose(str(player.GROWTH_OPTIONS[event.keycode - KEY_1].key))
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
