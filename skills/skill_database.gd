class_name SkillDatabase
extends RefCounted

const SKILL_TYPE_SELF = "self"
const SKILL_TYPE_TARGET_ENEMY = "target_enemy" # Requires selecting a target
const SKILL_TYPE_DIRECTION = "direction" # Requires selecting a direction
const SKILL_TYPE_POINT = "point" # Requires selecting a grid tile

static func get_all_skills() -> Array[Dictionary]:
	return [
		{
			"id": "explosion",
			"name": "爆裂魔法",
			"mp_cost": 8,
			"type": SKILL_TYPE_POINT,
			"range": 5,
			"radius": 1, # 1 means center + 1 tile radius (3x3)
			"damage": 10,
			"is_magic": true,
			"elements": ["magic"],
			"description": "指定した地点で大爆発を起こす。\n[color=cyan]魔法[/color]: 威力は知力によって増加する。"
		},
		{
			"id": "meteor",
			"name": "メテオ・ストライク",
			"mp_cost": 15,
			"type": SKILL_TYPE_POINT,
			"range": 6,
			"radius": 2, # 2 means 5x5 radius
			"damage": 25,
			"is_magic": true,
			"elements": ["fire", "blunt", "magic"],
			"description": "星を落とし、広範囲に絶大な炎と物理ダメージを与える。\n[color=cyan]魔法[/color]: 威力は知力によって増加する。"
		},
		{
			"id": "fireball",
			"name": "火炎球",
			"mp_cost": 3,
			"type": SKILL_TYPE_DIRECTION,
			"cooldown": 0,
			"damage": 5,
			"range": 6,
			"is_magic": true,
			"elements": ["fire", "magic"],
			"description": "前方へ火の玉を放つ。\n[color=cyan]魔法[/color]: 威力は知力によって増加する。",
			"effect": "burn"
		},
		{
			"id": "iceball",
			"name": "アイス・ボール",
			"mp_cost": 3,
			"type": SKILL_TYPE_DIRECTION,
			"cooldown": 0,
			"damage": 5,
			"range": 6,
			"is_magic": true,
			"elements": ["ice", "magic"],
			"description": "前方へ氷の玉を放つ。\n[color=cyan]魔法[/color]: 威力は知力によって増加する。",
			"effect": "freeze"
		},
		{
			"id": "heal",
			"name": "癒やしの光",
			"mp_cost": 4,
			"type": SKILL_TYPE_SELF,
			"cooldown": 10,
			"heal_amount": 8,
			"is_magic": true,
			"elements": ["magic"],
			"description": "聖なる光でHPを回復する。\n[color=cyan]魔法[/color]: 回復量は知力によって増加する。"
		},
		{
			"id": "teleport",
			"name": "瞬間移動",
			"mp_cost": 5,
			"type": SKILL_TYPE_SELF,
			"cooldown": 20,
			"is_magic": true,
			"elements": ["magic"],
			"description": "ランダムな場所へ瞬時に移動する。"
		},
		{
			"id": "lightning",
			"name": "紫電",
			"mp_cost": 6,
			"type": SKILL_TYPE_DIRECTION, # Use direction-based targeting (same pipeline as fireball)
			"range": 5,
			"damage": 8,
			"is_magic": true,
			"elements": ["electric", "magic"],
			"description": "近くの敵に雷を落とす。\n[color=cyan]魔法[/color]: 威力は知力によって増加する。"
		},
		{
			"id": "charge",
			"name": "猛牛突進",
			"mp_cost": 4,
			"type": SKILL_TYPE_DIRECTION,
			"range": 4,
			"damage": 1.2,
			"knockback": true,
			"elements": ["blunt"],
			"description": "[牛頭鬼] 前方へ猛突進し、敵を吹き飛ばす。"
		},
		{
			"id": "acid_puddle",
			"name": "酸の水溜まり",
			"mp_cost": 3,
			"type": SKILL_TYPE_SELF,
			"description": "[粘液] 周囲に腐食性の酸を撒き散らす。"
		},
		{
			"id": "mug",
			"name": "強奪",
			"mp_cost": 2,
			"type": SKILL_TYPE_TARGET_ENEMY, # Need implementation for explicit targeting if not adjacent
			"range": 1,
			"damage": 1.0,
			"steal_gold": true,
			"elements": ["normal"],
			"description": "[小鬼] 攻撃と同時に金を盗む。"
		},
		{
			"id": "web_shot",
			"name": "蜘蛛の糸",
			"mp_cost": 4,
			"type": SKILL_TYPE_DIRECTION,
			"range": 5,
			"damage": 0.8,
			"effect": "paralyze",
			"elements": ["normal"],
			"description": "[土蜘蛛] 粘着く糸で敵を拘束し、麻痺させる。"
		},
		{
			"id": "blank_shot",
			"name": "ブランク・ショット",
			"mp_cost": 2,
			"type": SKILL_TYPE_DIRECTION,
			"range": 4,
			"damage": 1.0,
			"is_magic": false,
			"elements": ["normal"],
			"description": "無属性の遠距離攻撃。\\nMP消費が少なく、安定したダメージを与える。"
		},
		{
			"id": "arrow_shot",
			"name": "射撃",
			"mp_cost": 0, # Enemy skill, cost irrelevant? or use cost
			"type": SKILL_TYPE_DIRECTION,
			"range": 5,
			"damage": 3,
			"elements": ["pierce"],
			"description": "矢を放つ。"
		},
		{
			"id": "scramble",
			"name": "いたずら",
			"mp_cost": 0,
			"type": SKILL_TYPE_DIRECTION,
			"range": 5,
			"damage": 0,
			"effect": "scramble",
			"description": "インベントリをかき回す。"
		},
		{
			"id": "clairvoyance",
			"name": "千里眼",
			"mp_cost": 0,
			"type": "passive",
			"description": "草むらに潜む敵を遠くからでも発見できる。"
		},
		{
			"id": "blood_beam",
			"name": "ブラッド・ビーム",
			"mp_cost": 0,
			"hp_cost": 5,
			"type": SKILL_TYPE_DIRECTION,
			"range": 7,
			"damage": 1.4,
			"is_magic": false,
			"int_scaling": 1.5,
			"blind_chance": 0.4,
			"transfer_status": true,
			"elements": ["normal"],
			"description": "自分のHPを[color=red]5[/color]消費して血の光線を放つ。\n知力(INT)の[color=magenta]1.5倍[/color]の威力を加算する。\n[color=crimson]盲目[/color]: 40%の確率で敵の視界を奪う。\n[color=orchid]転移[/color]: 自身の状態異常を敵にも付与する。"
		},
		{
			"id": "freeze",
			"name": "氷結",
			"mp_cost": 5,
			"type": SKILL_TYPE_POINT,
			"range": 4,
			"radius": 1,
			"damage": 6,
			"is_magic": true,
			"effect": "freeze",
			"elements": ["ice", "magic"],
			"description": "指定した範囲の水を凍らせる。\n[color=cyan]魔法[/color]: 氷床は歩行可能になる。"
		},
		{
			"id": "collapse",
			"name": "崩壊",
			"mp_cost": 20,
			"type": SKILL_TYPE_DIRECTION,
			"range": 5,
			"is_magic": false,
			"description": "対象までの5マスに存在する床以外のすべてを消滅させる。\n[color=red]代償[/color]: 5ターン後に[color=yellow]睡眠[/color](10ターン)状態になる。\n(睡眠中ダメージを受けると90%の確率で目覚める)"
		},
		{
			"id": "wall",
			"name": "ウォール",
			"mp_cost": 5,
			"type": SKILL_TYPE_POINT,
			"range": 4,
			"damage": 6,
			"is_magic": true,
			"elements": ["magic"],
			"description": "指定したマスに壁を生成する。\nそのマスにいる生物はダメージを受けて周囲の空きマスに逃れるが、逃げ場がない場合は消滅する。"
		},
		{
			"id": "helm_splitter",
			"name": "兜割り",
			"mp_cost": 3,
			"type": SKILL_TYPE_TARGET_ENEMY,
			"range": 1,
			"damage": 1.5,
			"is_magic": false,
			"str_scaling": 1.2,
			"elements": ["blunt"],
			"description": "隣接する敵に強力な一撃を叩き込み、相手の防御力を60%貫通する物理攻撃。\n[color=pink]力依存[/color]: 力(STR)の1.2倍の威力を加算する。"
		},
		{
			"id": "super_seoi_nage",
			"name": "超背負投",
			"mp_cost": 4,
			"cooldown": 4,
			"type": SKILL_TYPE_TARGET_ENEMY,
			"range": 1,
			"throw_distance": 5,
			"landing_damage": 6,
			"collision_damage": 12,
			"str_scaling": 0.6,
			"is_magic": false,
			"elements": ["blunt"],
			"description": "隣接する対象を使用者の反対方向へ最大5マス投げ飛ばす。落下時にダメージを与え、壁や生物へ激突すると追加ダメージ。巻き込まれた生物もダメージを受ける。"
		},
		{
			"id": "gale_thrust",
			"name": "烈風突き",
			"mp_cost": 4,
			"type": SKILL_TYPE_DIRECTION,
			"range": 3,
			"damage": 1.2,
			"is_magic": false,
			"dex_scaling": 1.0,
			"elements": ["pierce"],
			"description": "前方の敵全員を貫通してダメージを与え、1マス押し戻す(ノックバック)物理攻撃。\n[color=pink]技量依存[/color]: 器用さ(DEX)の1.0倍の威力を加算する。"
		},
		{
			"id": "cyclone_slash",
			"name": "回転斬り",
			"mp_cost": 5,
			"type": SKILL_TYPE_SELF,
			"damage": 1.1,
			"is_magic": false,
			"str_scaling": 0.8,
			"dex_scaling": 0.4,
			"elements": ["slash"],
			"description": "自身の周囲8マスの敵全員を薙ぎ払う範囲物理攻撃。\n[color=pink]力・技量依存[/color]: STRの0.8倍、DEXの0.4倍の威力を加算する。"
		},
		{
			"id": "grass_snipe",
			"name": "グラス・スナイプ",
			"mp_cost": 4,
			"type": SKILL_TYPE_DIRECTION,
			"range": 6,
			"damage": 1.3,
			"is_magic": false,
			"dex_scaling": 1.5,
			"elements": ["pierce"],
			"description": "草むらから敵を射抜く遠距離物理攻撃。\n[color=pink]技量依存[/color]: 器用さ(DEX)の1.5倍の威力を加算する。\n[color=green]隠密[/color]: 自分が草むらにいる時に使用するとダメージが[color=yellow]2倍[/color]になる。\n[color=red]制約[/color]: 隣接する敵(1マス先)には当たらない。"
		}
	]

static func get_skill_by_id(skill_id: String) -> Dictionary:
	for skill in get_all_skills():
		if skill["id"] == skill_id:
			return skill
	return {}
