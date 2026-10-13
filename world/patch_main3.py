file_path = r"d:\My Document\Godot\Godot\roguelike\world\main.gd"
with open(file_path, "r", encoding="utf-8") as f:
    code = f.read()

target = 'if tile_coords.y == -1 and player_grid.y == 0:'
replacement = 'if tile_coords.y == -1:'

if target in code:
    code = code.replace(target, replacement)
    print("Patched LF")
elif target.replace("\n", "\r\n") in code:
    code = code.replace(target.replace("\n", "\r\n"), replacement)
    print("Patched CRLF")
else:
    # Use simpler line modification
    lines = code.splitlines()
    for idx, line in enumerate(lines):
        if "if tile_coords.y == -1 and player_grid.y == 0:" in line:
            lines[idx] = "\tif tile_coords.y == -1:"
            print(f"Patched line {idx}")
    code = "\n".join(lines)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(code)
