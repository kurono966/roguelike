file_path = r"d:\My Document\Godot\Godot\roguelike\world\main.gd"
with open(file_path, "r", encoding="utf-8") as f:
    code = f.read()

# Locate the segments
target_draw = """	if visibility_manager:
		visibility_manager.map_data = _map_data
		visibility_manager.visible_tiles = _visible_tiles
		visibility_manager.explored_tiles = _explored_tiles
		visibility_manager.burning_grass = _burning_grass
		visibility_manager.frozen_tiles = _frozen_tiles
		visibility_manager.steam_tiles = _steam_tiles
		visibility_manager.draw_map()"""

target_layers = """	# Setup layers
	# Ensure we have enough layers
	while tile_map.get_layers_count() < 3:
		tile_map.add_layer(-1)
	
	# Set dim color for memory layer (dark blue-gray, low saturation)
	tile_map.set_layer_modulate(LAYER_MEMORY, Color(0.25, 0.28, 0.35, 1.0))
	# Normal color for visible layer
	tile_map.set_layer_modulate(LAYER_VISIBLE, Color(0.95, 0.95, 0.95, 1.0))"""

# Normalize newlines
code_norm = code.replace("\r\n", "\n")
target_draw_norm = target_draw.replace("\r\n", "\n")
target_layers_norm = target_layers.replace("\r\n", "\n")

if target_draw_norm in code_norm and target_layers_norm in code_norm:
    # Remove target_layers_norm from its position
    code_norm = code_norm.replace(target_layers_norm + "\n", "")
    # Re-insert target_layers_norm before target_draw_norm
    code_norm = code_norm.replace(target_draw_norm, target_layers_norm + "\n\n" + target_draw_norm)
    
    # Restore original line endings (CRLF if it was CRLF)
    if "\r\n" in code:
        code = code_norm.replace("\n", "\r\n")
    else:
        code = code_norm
    print("Successfully moved layers setup before draw_map")
else:
    print("Targets not found")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(code)
