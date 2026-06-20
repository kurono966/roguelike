@echo off
REM Batch script to optimize ALL monster sprites to 64x64

echo Optimizing existing monster sprites...
echo.

REM Existing large sprites
python resize_image.py "../assets/zakomushi.png" "../assets/zakomushi.png" 64
python resize_image.py "../assets/kuragen.png" "../assets/kuragen.png" 64
python resize_image.py "../assets/red_orc.png" "../assets/red_orc.png" 64
python resize_image.py "../assets/minotaur.png" "../assets/minotaur.png" 64
python resize_image.py "../assets/orc.png" "../assets/orc.png" 64
python resize_image.py "../assets/bat.png" "../assets/bat.png" 64
python resize_image.py "../assets/slime.png" "../assets/slime.png" 64
python resize_image.py "../assets/spider.png" "../assets/spider.png" 64
python resize_image.py "../assets/skeleton.png" "../assets/skeleton.png" 64
python resize_image.py "../assets/goblin.png" "../assets/goblin.png" 64
python resize_image.py "../assets/mage.png" "../assets/mage.png" 64
python resize_image.py "../assets/rogue.png" "../assets/rogue.png" 64
python resize_image.py "../assets/warrior.png" "../assets/warrior.png" 64
python resize_image.py "../assets/swimmer.png" "../assets/swimmer.png" 64
python resize_image.py "../assets/shadow.png" "../assets/shadow.png" 64
python resize_image.py "../assets/armored_skeleton.png" "../assets/armored_skeleton.png" 64
python resize_image.py "../assets/skeleton_archer.png" "../assets/skeleton_archer.png" 64

echo.
echo All sprites optimized!
pause
