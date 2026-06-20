class_name MinimapController
extends Node

const CellType = MapDefinitions.CellType
const MINIMAP_TILE_SIZE: int = 3
const MINIMAP_PADDING: int = 4
const MINIMAP_MARGIN: int = 12
const MINIMAP_TOP_OFFSET: int = 72

var _minimap_layer: CanvasLayer
var _minimap_panel: PanelContainer
var _minimap_texture_rect: TextureRect
var _minimap_image: Image
var _minimap_texture: ImageTexture
var _floor_label: Label

var main_scene: Node2D

func setup(p_main_scene: Node2D):
	main_scene = p_main_scene
	_setup_minimap()

func _setup_minimap():
	var map_px_size = Vector2i(MapDefinitions.MAP_WIDTH * MINIMAP_TILE_SIZE, MapDefinitions.MAP_HEIGHT * MINIMAP_TILE_SIZE)

	_minimap_layer = CanvasLayer.new()
	_minimap_layer.layer = 110
	main_scene.add_child(_minimap_layer)

	_minimap_panel = PanelContainer.new()
	_minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_minimap_panel.offset_right = -MINIMAP_MARGIN
	_minimap_panel.offset_top = MINIMAP_MARGIN + MINIMAP_TOP_OFFSET

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.06, 0.08, 0.85) # Very dark gray-blue, translucent
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(0.25, 0.25, 0.28, 1.0) # Muted metallic
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(8)
	_minimap_panel.add_theme_stylebox_override("panel", panel_style)
	_minimap_layer.add_child(_minimap_panel)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	_minimap_panel.add_child(vbox)

	var header_hbox = HBoxContainer.new()
	header_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header_hbox)

	var map_title = Label.new()
	map_title.text = "✦ MAP"
	map_title.add_theme_font_size_override("font_size", 12)
	map_title.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25)) # Dull Gold
	header_hbox.add_child(map_title)

	var spacer = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	_floor_label = Label.new()
	_floor_label.text = "地上"
	_floor_label.add_theme_font_size_override("font_size", 12)
	_floor_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85)) # Warm off-white
	header_hbox.add_child(_floor_label)

	var sep = ColorRect.new()
	sep.color = Color(0.25, 0.25, 0.28, 0.4)
	sep.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(sep)

	_minimap_texture_rect = TextureRect.new()
	_minimap_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_texture_rect.custom_minimum_size = map_px_size
	_minimap_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vbox.add_child(_minimap_texture_rect)

const WorldCell = MapDefinitions.WorldCell

func _get_minimap_tile_color(cell_type: int, is_visible: bool) -> Color:
	var base := Color(0.0, 0.0, 0.0, 0.0)
	match cell_type:
		CellType.WALL:
			base = Color(0.22, 0.22, 0.22, 1.0)
		CellType.FLOOR:
			base = Color(0.48, 0.48, 0.48, 1.0)
		CellType.WATER:
			base = Color(0.20, 0.35, 0.75, 1.0)
		CellType.GRASS:
			base = Color(0.25, 0.55, 0.25, 1.0)
		CellType.STAIRS:
			base = Color(0.92, 0.86, 0.20, 1.0)
		CellType.STAIRS_BLUE:
			base = Color(0.25, 0.60, 1.00, 1.0)
		CellType.STAIRS_GREEN:
			base = Color(0.25, 0.90, 0.45, 1.0)
		_:
			base = Color(0.40, 0.40, 0.40, 1.0)

	if is_visible:
		return base.lightened(0.25)
	return base.darkened(0.35)

func _get_world_minimap_tile_color(cell_type: int) -> Color:
	match cell_type:
		WorldCell.SEA:
			return Color(0.12, 0.22, 0.38, 1.0)
		WorldCell.GRASS:
			return Color(0.20, 0.50, 0.22, 1.0)
		WorldCell.FOREST:
			return Color(0.10, 0.35, 0.12, 1.0)
		WorldCell.MOUNTAIN:
			return Color(0.50, 0.45, 0.42, 1.0)
		WorldCell.VILLAGE:
			return Color(0.95, 0.82, 0.35, 1.0)
		WorldCell.DUNGEON:
			return Color(0.95, 0.30, 0.30, 1.0)
		WorldCell.ROAD:
			return Color(0.40, 0.40, 0.45, 1.0)
		_:
			return Color(0.15, 0.22, 0.16, 1.0)

func update_minimap():
	if not _minimap_texture_rect:
		return

	var map_w = MapDefinitions.MAP_WIDTH
	var map_h = MapDefinitions.MAP_HEIGHT

	if _minimap_image == null or _minimap_image.get_width() != map_w or _minimap_image.get_height() != map_h:
		_minimap_image = Image.create(map_w, map_h, false, Image.FORMAT_RGBA8)
		_minimap_texture = ImageTexture.create_from_image(_minimap_image)
		_minimap_texture_rect.texture = _minimap_texture

	var is_world = main_scene._is_on_world_map

	for x in range(map_w):
		for y in range(map_h):
			var color = Color(0.0, 0.0, 0.0, 0.82)
			if is_world:
				color = _get_world_minimap_tile_color(main_scene._world_map_data[x][y])
			else:
				if main_scene._explored_tiles[x][y]:
					var is_visible = main_scene._visible_tiles[x][y]
					color = _get_minimap_tile_color(main_scene._map_data[x][y], is_visible)
			_minimap_image.set_pixel(x, y, color)

	if is_instance_valid(main_scene.player):
		var p = main_scene.tile_map.local_to_map(main_scene.player.position)
		if p.x >= 0 and p.x < map_w and p.y >= 0 and p.y < map_h:
			_minimap_image.set_pixel(p.x, p.y, Color(1.0, 0.2, 0.2, 1.0))

	_minimap_texture.update(_minimap_image)

func update_floor_label(floor_str: String):
	if _floor_label:
		_floor_label.text = floor_str
