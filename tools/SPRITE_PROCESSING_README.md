# Monster Sprite Processing Guide

This guide explains how to process the generated monster sprites with transparency.

## Prerequisites

- Python 3.x installed
- PIL (Pillow) library: `pip install pillow`

## Generated Monster Sprites

The following sprites were generated with green/blue backgrounds for transparency:

### Green Screen (#00FF00) Sprites:
1. **人魂 (Hitodama)** - Blue ghost spirit
2. **毒キノコ (Poison Mushroom)** - Purple toxic mushroom
3. **いたずら小僧 (Prankster Imp)** - Yellow mischievous imp
4. **動く鎧 (Animated Armor)** - Gray animated armor
5. **半魚人 (Merman)** - Teal fish-man

### Blue Screen (#0000FF) Sprites:
1. **ドラゴン (Dragon)** - Dark red dragon boss
2. **死神 (Grim Reaper)** - Black grim reaper
3. **水蛇 (Water Snake)** - Aquamarine sea serpent

### Already Transparent:
1. **大カマキリ (Giant Mantis)** - Chartreuse praying mantis (already has transparency)

## Processing Steps

### Option 1: Automatic Batch Processing (Recommended)

Run the batch script from the `tools` directory:

```batch
cd tools
process_sprites.bat
```

This will:
- Process all green screen backgrounds
- Process all blue screen backgrounds
- Copy the mantis sprite (already transparent)
- Save all processed sprites to `../assets/` directory

### Option 2: Manual Processing

Process each sprite individually:

```batch
cd tools

# Green screen backgrounds
python make_transparent.py "input_path/hitodama_ghost.png" "../assets/hitodama.png" 30
python make_transparent.py "input_path/poison_mushroom.png" "../assets/poison_mushroom.png" 30
python make_transparent.py "input_path/prankster_imp.png" "../assets/prankster_imp.png" 30
python make_transparent.py "input_path/animated_armor.png" "../assets/animated_armor.png" 30
python make_transparent.py "input_path/merman.png" "../assets/merman.png" 30

# Blue screen backgrounds
python make_transparent.py "input_path/dragon.png" "../assets/dragon.png" 30
python make_transparent.py "input_path/grim_reaper.png" "../assets/grim_reaper.png" 30
python make_transparent.py "input_path/water_snake.png" "../assets/water_snake.png" 30
```

### Tolerance Parameter

The tolerance value (default: 30) controls how similar colors need to be to the background:
- Lower values (10-20): Stricter matching, may leave background pixels
- Higher values (30-50): More forgiving, may remove sprite details

Adjust as needed for each sprite.

## Verification

After processing, check the sprites in Godot:
1. Open the project in Godot
2. Navigate to `res://assets/`
3. Verify each sprite displays correctly with transparency
4. Test in-game to ensure monsters render properly

## Sprite Paths in Code

The following paths are already configured in `enemy_database.gd`:

```gdscript
"人魂" -> "res://assets/hitodama.png"
"毒キノコ" -> "res://assets/poison_mushroom.png"
"大カマキリ" -> "res://assets/giant_mantis.png"
"いたずら小僧" -> "res://assets/prankster_imp.png"
"動く鎧" -> "res://assets/animated_armor.png"
"ドラゴン" -> "res://assets/dragon.png"
"死神" -> "res://assets/grim_reaper.png"
"半魚人" -> "res://assets/merman.png"
"水蛇" -> "res://assets/water_snake.png"
```

## Troubleshooting

### Background not fully removed
- Increase tolerance value (try 40 or 50)
- Check if background color is consistent

### Sprite details lost
- Decrease tolerance value (try 20 or 25)
- Ensure sprite colors are distinct from background

### File not found errors
- Verify input file paths are correct
- Check that output directory exists
- Ensure you're running from the `tools` directory

## Notes

- All sprites were generated via AI with pixel art style
- Original images are stored in `.gemini/antigravity/brain/` directory
- Processed sprites should be approximately 32x32 pixels or similar roguelike scale
- Always backup original files before processing
