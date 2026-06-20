@echo off
REM Batch script to process all monster sprites with transparency

echo Processing monster sprites...
echo.

REM Process green screen backgrounds (tolerance 30)
python make_transparent.py "../../../.gemini/antigravity/brain/ba502b55-5ec7-4039-91c3-12f19e2177d2/hitodama_ghost_1767844226398.png" "../assets/hitodama.png" 30
python make_transparent.py "../../../.gemini/antigravity/brain/ba502b55-5ec7-4039-91c3-12f19e2177d2/poison_mushroom_1767844240955.png" "../assets/poison_mushroom.png" 30
python make_transparent.py "../../../.gemini/antigravity/brain/ba502b55-5ec7-4039-91c3-12f19e2177d2/prankster_imp_1767844275767.png" "../assets/prankster_imp.png" 30
python make_transparent.py "../../../.gemini/antigravity/brain/ba502b55-5ec7-4039-91c3-12f19e2177d2/animated_armor_fullbody_1767845431108.png" "../assets/animated_armor.png" 30
python make_transparent.py "../../../.gemini/antigravity/brain/ba502b55-5ec7-4039-91c3-12f19e2177d2/merman_enemy_1767844345901.png" "../assets/merman.png" 30

REM Process blue screen backgrounds (tolerance 30)
python make_transparent.py "../../../.gemini/antigravity/brain/ba502b55-5ec7-4039-91c3-12f19e2177d2/dragon_boss_1767844314828.png" "../assets/dragon.png" 30
python make_transparent.py "../../../.gemini/antigravity/brain/ba502b55-5ec7-4039-91c3-12f19e2177d2/grim_reaper_1767844331085.png" "../assets/grim_reaper.png" 30
python make_transparent.py "../../../.gemini/antigravity/brain/ba502b55-5ec7-4039-91c3-12f19e2177d2/water_snake_solid_red_1767847138260.png" "../assets/water_snake.png" 30 255,0,0

REM Giant mantis already has transparency
echo Copying giant mantis (already transparent)...
copy "../../../.gemini/antigravity/brain/ba502b55-5ec7-4039-91c3-12f19e2177d2/giant_mantis_1767844259196.png" "../assets/giant_mantis.png"

echo.
echo All sprites processed successfully!
echo Files saved to ../assets/
pause
