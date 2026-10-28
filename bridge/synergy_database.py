"""
База мета-знаний и синергий Brotato (Brotato Meta Knowledge Base)
Модуль рассчитывает идеальный вектор развития для каждого персонажа,
размечает витрину магазина, карточки прокачки (Level Up) и ящики с предметами (Crates).
"""

from typing import Dict, Any, List, Tuple

# База знаний архетипов персонажей
CHARACTER_METAS: Dict[str, Dict[str, Any]] = {
    "character_multitasker": {
        "name_ru": "Мастер на все руки",
        "description": "Может носить до 12 видов оружия, но получает -5% общего урона за каждую единицу оружия.",
        "win_condition": (
            "МАТЕМАТИЧЕСКОЕ ПРАВИЛО: ТОЛЬКО ПАЛКИ! Каждая Палка даёт +4 к плоскому базовому урону ВСЕМ экипированным "
            "Палкам, полностью нивелируя дебафф -60% урона и разгоняя суммарный залп 12 Палок до 370+ базового урона! "
            "Любое другое оружие не имеет этого эффекта, наносит мизерный урон и гарантированно руинит билд."
        ),
        "target_weapons": [
            "палка", "stick", "weapon_stick", "weapon_stick_1", "weapon_stick_2", "weapon_stick_3", "weapon_stick_4"
        ],
        "strict_mono_weapon": True,
        "upgrade_stat_priorities": {
            # Приоритет 1 (S-Tier): прямое масштабирование на 12 палок
            "урон в ближнем бою": 100,
            "melee damage": 100,
            "скорость атаки": 85,
            "attack speed": 85,
            "макс. оз": 75,
            "max hp": 75,
            "броня": 70,
            "armor": 70,
            "кража жизни": 65,
            "lifesteal": 65,
            # Приоритет 2 (A/B-Tier): полезные второстепенные статы
            "удача": 40,
            "luck": 40,
            "уклонение": 35,
            "dodge": 35,
            "регенерация оз": 30,
            "hp regeneration": 30,
            "урожай": 50, # на ранних волнах
            "harvesting": 50,
            "критический урон": 20,
            "crit chance": 20,
            # Мусор (F-Tier): строго 0 очков
            "дальний бой": -100,
            "ranged damage": -100,
            "стихийный урон": -100,
            "elemental damage": -100,
            "инженерия": -100,
            "engineering": -100,
            "дальность": -50,
            "range": -50
        },
        "priority_stats": [
            "Урон в ближнем бою (Melee Damage) — 100% скалирование на все 12 палок",
            "Скорость атаки (Attack Speed) — компенсирует медленный базовый кулдаун палок",
            "Макс. ОЗ (Max HP) и Броня (Armor) — синергия с сетом Первобытного (+15 HP)",
            "Кража жизни (Lifesteal) — при 12 палках даёт перманентный отхил",
            "Урожай (Harvesting) — только на волнах 1-6 для экономики"
        ],
        "useless_stats": [
            "Дальний бой (Ranged Damage) — даёт ровно 0 палкам",
            "Стихийный урон (Elemental Damage) — даёт ровно 0 палкам",
            "Инженерия (Engineering) — бесполезна без турелей",
            "Дальность (Range) — увеличивает задержку возврата холодного оружия"
        ],
        "high_value_items": [
            "дерево", "tree", "item_tree", "кофе", "coffee", "item_coffee", "пришелец", "alien", "item_alien_eyes",
            "удобрение", "fertilizer", "item_fertilizer", "трактор", "tractor", "item_tractor", "поросенок", "piggy", "item_piggy_bank"
        ]
    }
}

# Ключевые слова для детекции архетипа
RANGED_KEYWORDS = [
    "pistol", "gun", "rifle", "smg", "shotgun", "bow", "slingshot", "revolver",
    "laser", "medical_gun", "sniper", "rocket", "пистолет", "ружье", "дробовик",
    "винтовка", "рогатка", "автомат", "лазер"
]
ELEMENTAL_KEYWORDS = [
    "torch", "wand", "taser", "flamethrower", "plasma", "lightning", "факел", "палочка", "тазер", "огнемет"
]
ENGINEERING_KEYWORDS = [
    "wrench", "screwdriver", "turret", "гаечный ключ", "отвертка", "турель"
]

def resolve_character_meta(data: Dict[str, Any]) -> Dict[str, Any]:
    char_info = data.get("character", {})
    char_id = str(char_info.get("id", "")).lower()
    char_name = str(char_info.get("name", "")).lower()

    if char_id in CHARACTER_METAS:
        return CHARACTER_METAS[char_id]

    for meta_id, meta in CHARACTER_METAS.items():
        if meta["name_ru"].lower() in char_name or "мастер" in char_name or "multitasker" in char_id:
            return meta

    # Авто-детекция архетипа на основе экипированного оружия и статов для остальных 40+ персонажей
    equipped = data.get("equipped_weapons", [])
    target_weapons = []
    for w in equipped:
        wid = str(w.get("id", "")).lower()
        wname = str(w.get("name", "")).lower()
        if wid:
            target_weapons.append(wid)
        if wname:
            target_weapons.append(wname)

    # Определяем доминирующий архетип по оружию
    weapons_str = " ".join(target_weapons)
    is_ranged = any(k in weapons_str for k in RANGED_KEYWORDS)
    is_elemental = any(k in weapons_str for k in ELEMENTAL_KEYWORDS)
    is_engineering = any(k in weapons_str for k in ENGINEERING_KEYWORDS)

    if is_ranged:
        return {
            "name_ru": char_info.get("name", "Дальнобойный персонаж"),
            "description": "Архетип: Дальний бой",
            "win_condition": "Собирай стрелковое оружие, разгоняй урон в дальнем бою и скорость атаки.",
            "target_weapons": target_weapons if target_weapons else ["pistol", "gun"],
            "strict_mono_weapon": False,
            "upgrade_stat_priorities": {
                "урон в дальнем бою": 100, "ranged damage": 100,
                "скорость атаки": 85, "attack speed": 85,
                "макс. оз": 75, "max hp": 75,
                "броня": 70, "armor": 70,
                "кража жизни": 65, "lifesteal": 65,
                "уклонение": 45, "dodge": 45,
                "удача": 40, "luck": 40,
                "дальность": 35, "range": 35,
                "критический урон": 40, "crit chance": 40,
                "урожай": 50, "harvesting": 50,
                "урон в ближнем бою": -100, "melee damage": -100,
                "инженерия": -80, "engineering": -80
            },
            "priority_stats": ["Урон в дальнем бою", "Скорость атаки", "Макс. ОЗ", "Броня"],
            "useless_stats": ["Урон в ближнем бою", "Инженерия"],
            "high_value_items": ["дерево", "tree", "item_tree", "кофе", "coffee", "item_coffee"]
        }
    elif is_elemental:
        return {
            "name_ru": char_info.get("name", "Стихийный персонаж"),
            "description": "Архетип: Стихии",
            "win_condition": "Собирай стихийное оружие, разгоняй периодический стихийный урон и выживаемость.",
            "target_weapons": target_weapons if target_weapons else ["torch", "wand"],
            "strict_mono_weapon": False,
            "upgrade_stat_priorities": {
                "стихийный урон": 100, "elemental damage": 100,
                "скорость атаки": 80, "attack speed": 80,
                "макс. оз": 75, "max hp": 75,
                "регенерация оз": 70, "hp regeneration": 70,
                "броня": 70, "armor": 70,
                "кража жизни": 60, "lifesteal": 60,
                "урожай": 50, "harvesting": 50,
                "урон в ближнем бою": -80, "melee damage": -80,
                "инженерия": -80, "engineering": -80
            },
            "priority_stats": ["Стихийный урон", "Скорость атаки", "Макс. ОЗ", "Регенерация ОЗ"],
            "useless_stats": ["Урон в ближнем бою", "Инженерия"],
            "high_value_items": ["дерево", "tree", "item_tree", "сосиска", "sausage", "item_scared_sausage"]
        }
    elif is_engineering:
        return {
            "name_ru": char_info.get("name", "Инженер"),
            "description": "Архетип: Инженерия",
            "win_condition": "Собирай ключи и отвертки, масштабируй Инженерию для усиления турелей и мин.",
            "target_weapons": target_weapons if target_weapons else ["wrench", "screwdriver"],
            "strict_mono_weapon": False,
            "upgrade_stat_priorities": {
                "инженерия": 100, "engineering": 100,
                "макс. оз": 80, "max hp": 80,
                "броня": 75, "armor": 75,
                "уклонение": 65, "dodge": 65,
                "регенерация оз": 60, "hp regeneration": 60,
                "скорость": 50, "speed": 50,
                "урожай": 50, "harvesting": 50,
                "урон в ближнем бою": -100, "melee damage": -100,
                "урон в дальнем бою": -100, "ranged damage": -100
            },
            "priority_stats": ["Инженерия", "Макс. ОЗ", "Броня", "Регенерация ОЗ"],
            "useless_stats": ["Урон в ближнем бою", "Урон в дальнем бою"],
            "high_value_items": ["дерево", "tree", "item_tree", "тулбокс", "toolbox"]
        }

    # По умолчанию — универсальный ближний бой
    return {
        "name_ru": char_info.get("name", "Unknown"),
        "description": "Стандартный персонаж (Ближний бой)",
        "win_condition": "Собирай моносинергию оружия, совместимого с текущим вооружением в руках.",
        "target_weapons": target_weapons if target_weapons else ["палка", "stick"],
        "strict_mono_weapon": True if "мастер" in char_name or "multitasker" in char_id else False,
        "upgrade_stat_priorities": {
            "урон в ближнем бою": 100, "melee damage": 100,
            "скорость атаки": 80, "attack speed": 80,
            "макс. оз": 70, "max hp": 70,
            "броня": 60, "armor": 60,
            "кража жизни": 55, "lifesteal": 55,
            "урожай": 50, "harvesting": 50,
            "дальний бой": -80, "ranged damage": -80,
            "стихийный урон": -60, "elemental damage": -60,
            "инженерия": -80, "engineering": -80
        },
        "priority_stats": ["Урон в ближнем бою", "Макс. ОЗ", "Броня", "Скорость атаки"],
        "useless_stats": ["Дальний бой", "Инженерия"],
        "high_value_items": ["дерево", "tree", "item_tree", "урожай", "кофе", "coffee"]
    }

def analyze_and_tag_shop_item(item: Dict[str, Any], meta: Dict[str, Any], equipped_weapons: List[Dict[str, Any]]) -> Tuple[str, str]:
    itype = item.get("type")
    name = str(item.get("name", ""))
    item_id = str(item.get("id", "")).lower()
    name_lower = name.lower()
    effects = " ".join(item.get("effects", [])).lower()

    target_weapons = [w.lower() for w in meta.get("target_weapons", [])]

    if itype == "Weapon":
        # Сравнение по ID и по имени
        is_target = any(
            (tw == item_id or tw in item_id or tw in name_lower)
            for tw in target_weapons
        )
        if is_target:
            return ("[CORE / ОБЯЗАТЕЛЬНО К ПОКУПКЕ]", f"Ядро моносинергии ({meta['name_ru']}). Покупать или замораживать!")
        if meta.get("strict_mono_weapon", False):
            base_target = target_weapons[0] if target_weapons else "профильное оружие"
            return ("[ЗАПРЕЩЕНО / ЛОМАЕТ СИНЕРГИЮ]", f"Чужой тип оружия! Покупка запрещена, так как разрушает билд через {base_target}.")
        else:
            return ("[ВТОРИЧНОЕ ОРУЖИЕ]", "Не профильное оружие.")

    if itype == "Item":
        # Сравнение по ID и по имени для полезных предметов
        if any(hvi == item_id or hvi in item_id or hvi in name_lower for hvi in meta.get("high_value_items", [])):
            return ("[СИНЕРГИЧНЫЙ ПРЕДМЕТ]", "Высокая ценность для экономики или выживания.")

        # Оценка по эффектам на основе приоритетов
        priorities = meta.get("upgrade_stat_priorities", {})
        pos_score = 0
        neg_score = 0
        for stat_key, weight in priorities.items():
            if stat_key in effects:
                if weight > 0:
                    pos_score += weight
                elif weight < 0:
                    neg_score += abs(weight)

        if pos_score >= 60 and neg_score < 40:
            return ("[СИНЕРГИЧНЫЙ ПРЕДМЕТ]", "Усиливает ключевые характеристики сборки.")
        elif neg_score >= 80 and pos_score < 40:
            return ("[МУСОРНЫЙ СТАТ / НЕ БРАТЬ]", "Даёт неиспользуемые или вредные характеристики.")
        else:
            return ("[НЕЙТРАЛЬНО]", "Обычный предмет, брать только при избытке золота.")

    return ("[ОБЫЧНЫЙ ТОВАР]", "")

def evaluate_crate_item(item: Dict[str, Any], meta: Dict[str, Any], equipped_weapons: List[Dict[str, Any]]) -> Tuple[str, str]:
    """
    Оценка предмета/оружия, выпавшего из ящика (Crate / Consumable Box).
    Возвращает: ("take", reason) или ("discard", reason)
    """
    tag, reason = analyze_and_tag_shop_item(item, meta, equipped_weapons)
    
    if "ЗАПРЕЩЕНО" in tag:
        return ("discard", f"Утилизация: {reason}")
    if "МУСОРНЫЙ" in tag:
        return ("discard", f"Утилизация: не профильный стат ({reason})")
    
    return ("take", f"Забираем: {reason if reason else 'Полезный предмет'}")

def evaluate_level_up_options(options: List[Dict[str, Any]], meta: Dict[str, Any], gold: int, reroll_price: int, wave: int) -> Tuple[int, int, str]:
    """
    Математическая оценка предложенных улучшений уровня.
    Возвращает: (лучший_слот, лучший_балл, вердикт)
    """
    priorities = meta.get("upgrade_stat_priorities", {})
    best_slot = -1
    best_score = -999
    best_name = ""

    for opt in options:
        slot = opt.get("slot", 0)
        name = opt.get("name", "")
        effects = " ".join(opt.get("effects", [])).lower()
        score = 0
        matched = False

        for stat_key, stat_weight in priorities.items():
            if stat_key in effects:
                score += stat_weight
                matched = True

        if not matched:
            score = 10 # Базовый нейтральный скор

        # Если ранняя волна (<=5), урожай ценится выше
        if wave <= 5 and any(w in effects for w in ["урожай", "harvesting"]):
            score += 25

        if score > best_score:
            best_score = score
            best_slot = slot
            best_name = name

    # Если лучший стат на витрине — мусор (score <= 10) или вторичный (score < 60),
    # а реролл дешёвый (reroll_price <= gold * 0.15 или reroll_price <= 5 при gold >= 20):
    should_reroll = False
    if best_score < 60 and gold >= reroll_price:
        if reroll_price <= 5 or reroll_price <= (gold * 0.2):
            should_reroll = True

    verdict = f"Лучший вариант: слот {best_slot} ({best_name}) со счётом {best_score}."
    if should_reroll:
        verdict += f" Ключевые статы (S-Tier) не выпали. Математически выгоден реролл за {reroll_price}г."

    return best_slot, best_score, verdict
