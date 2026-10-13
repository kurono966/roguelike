import os
import re

# Color constant mappings to RGB values
COLOR_MAP = {
    "Color.GREEN": "Color(0, 1, 0, 1)",
    "Color.SLATE_GRAY": "Color(0.44, 0.5, 0.56, 1)",
    "Color.AQUAMARINE": "Color(0.5, 1, 0.83, 1)",
    "Color.WHITE": "Color(1, 1, 1, 1)",
    "Color.BEIGE": "Color(0.96, 0.96, 0.86, 1)",
    "Color.SADDLE_BROWN": "Color(0.55, 0.27, 0.07, 1)",
    "Color.TURQUOISE": "Color(0.25, 0.88, 0.82, 1)",
    "Color.NAVY_BLUE": "Color(0, 0, 0.5, 1)",
    "Color.BLACK": "Color(0, 0, 0, 1)",
    "Color.CYAN": "Color(0, 1, 1, 1)",
    "Color.LIGHT_SLATE_GRAY": "Color(0.47, 0.53, 0.6, 1)",
    "Color.LIGHT_GRAY": "Color(0.75, 0.75, 0.75, 1)",
    "Color.DARK_SLATE_BLUE": "Color(0.28, 0.24, 0.55, 1)",
    "Color.ORANGE_RED": "Color(1, 0.27, 0, 1)",
    "Color.YELLOW": "Color(1, 1, 0, 1)",
    "Color.VIOLET": "Color(0.93, 0.51, 0.93, 1)",
    "Color.DARK_GREEN": "Color(0, 0.39, 0, 1)",
    "Color.BROWN": "Color(0.64, 0.16, 0.16, 1)",
    "Color.TEAL": "Color(0, 0.5, 0.5, 1)",
    "Color.GOLD": "Color(1, 0.84, 0, 1)",
    "Color.BLUE": "Color(0, 0, 1, 1)",
    "Color.LIGHT_BLUE": "Color(0.68, 0.85, 0.9, 1)",
    "Color.SKY_BLUE": "Color(0.53, 0.81, 0.92, 1)",
    "Color.DIM_GRAY": "Color(0.41, 0.41, 0.41, 1)",
    "Color.PURPLE": "Color(0.5, 0, 0.5, 1)",
    "Color.CHARTREUSE": "Color(0.87, 1, 0, 1)",
    "Color.ANTIQUE_WHITE": "Color(0.98, 0.92, 0.84, 1)",
    "Color.DARK_RED": "Color(0.55, 0, 0, 1)",
}

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content
    for constant, replacement in COLOR_MAP.items():
        content = content.replace(constant, replacement)
    
    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Fixed: {filepath}")
        return True
    return False

def main():
    data_dir = r"d:\My Document\Godot\Godot\roguelike\actors\enemy\data"
    fixed_count = 0
    
    for filename in os.listdir(data_dir):
        if filename.endswith('.tres'):
            filepath = os.path.join(data_dir, filename)
            if fix_file(filepath):
                fixed_count += 1
    
    print(f"\nFixed {fixed_count} files")

if __name__ == "__main__":
    main()
