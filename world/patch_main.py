import os

file_path = r"d:\My Document\Godot\Godot\roguelike\world\main.gd"
with open(file_path, "r", encoding="utf-8") as f:
    code = f.read()

# Replace the player placement lines to set y = 1
target = "\t\tplayer.position = Vector2(spawn_pos) * TILE_SIZE\n\t\t_last_player_grid_pos = spawn_pos"
replacement = "\t\tspawn_pos.y = 1\n\t\tplayer.position = Vector2(spawn_pos) * TILE_SIZE\n\t\t_last_player_grid_pos = spawn_pos"

if target in code:
    code = code.replace(target, replacement)
    print("Replaced with LF line endings")
elif target.replace("\n", "\r\n") in code:
    code = code.replace(target.replace("\n", "\r\n"), replacement.replace("\n", "\r\n"))
    print("Replaced with CRLF line endings")
else:
    # Let's try locating it with regex or by parts
    print("Target not found. Let's print nearby lines.")
    lines = code.splitlines()
    for idx, line in enumerate(lines):
        if "player.position = Vector2(spawn_pos)" in line:
            print(f"Line {idx}: {repr(line)}")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(code)
