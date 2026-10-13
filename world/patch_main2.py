file_path = r"d:\My Document\Godot\Godot\roguelike\world\main.gd"
with open(file_path, "r", encoding="utf-8") as f:
    code = f.read()

# Replace the incomplete if block with a comment
target = '# \xe4\xb8\xad\xe5\xbf\x83\xe3\x81\x8c\xe6\xb0\xb4\xe3\x81\xaa\xe3\x82\x89\xe5\x91\xa8\xe5\x9b\xb2\xe3\x82\x92\xe6\x8e\xa2\xe3\x81\x99\n\t\tif _map_data[spawn_pos.x][spawn_pos.y] == CellType.WATER or _map_data[spawn_pos.x][spawn_pos.y] == CellType.LAVA:'
replacement = '# Force spawn_pos.y to 1 for boundary testing'

# We also handle CRLF
if target in code:
    code = code.replace(target, replacement)
    print("Patched LF")
elif target.replace("\n", "\r\n") in code:
    code = code.replace(target.replace("\n", "\r\n"), replacement)
    print("Patched CRLF")
else:
    # Let's do a simpler replacement
    lines = code.splitlines()
    for idx, line in enumerate(lines):
        if "if _map_data[spawn_pos.x][spawn_pos.y] == CellType.WATER" in line:
            lines[idx] = "\t\t# Skipped water check for testing"
            print(f"Patched line {idx}")
    code = "\n".join(lines)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(code)
