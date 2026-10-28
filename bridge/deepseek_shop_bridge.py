"""
DeepSeek v4.1 Flash Free Shop Autopilot Bridge for Brotato (Enhanced + Synergy Engine)
Orchestrated by Antigravity (Gemini 3.8 Flash)
Subagent: DeepSeek v4.1 Flash Free via OpenCode CLI + Synergy Knowledge Base
"""

import os
import sys
import time
import json
import re
import subprocess

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

BRIDGE_DIR = r"D:\Brotato\bridge"
REQ_PATH = os.path.join(BRIDGE_DIR, "shop_request.json")
DEC_PATH = os.path.join(BRIDGE_DIR, "shop_decision.json")
UPG_REQ_PATH = os.path.join(BRIDGE_DIR, "upgrade_request.json")
UPG_DEC_PATH = os.path.join(BRIDGE_DIR, "upgrade_decision.json")
CRATE_REQ_PATH = os.path.join(BRIDGE_DIR, "crate_request.json")
CRATE_DEC_PATH = os.path.join(BRIDGE_DIR, "crate_decision.json")
LOG_PATH = os.path.join(BRIDGE_DIR, "autopilot_decisions.log")
PID_PATH = os.path.join(BRIDGE_DIR, "bridge.pid")
BROTATO_PID_PATH = os.path.join(BRIDGE_DIR, "brotato.pid")

def is_brotato_running():
    """Проверяет, запущен ли процесс Brotato (по сохраненному PID или по имени процесса)."""
    if os.path.exists(BROTATO_PID_PATH):
        try:
            with open(BROTATO_PID_PATH, "r", encoding="utf-8") as f:
                pid_str = f.read().strip()
                if pid_str and pid_str.isdigit():
                    pid = int(pid_str)
                    if sys.platform == "win32":
                        import ctypes
                        kernel32 = ctypes.windll.kernel32
                        handle = kernel32.OpenProcess(0x1000 | 0x00100000, False, pid)
                        if handle:
                            exit_code = ctypes.c_ulong()
                            res = kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code))
                            kernel32.CloseHandle(handle)
                            if res != 0 and exit_code.value == 259:
                                return True
                    else:
                        os.kill(pid, 0)
                        return True
        except Exception:
            pass

    # Проверка через tasklist в Windows
    if sys.platform == "win32":
        try:
            out = subprocess.check_output('tasklist /FI "IMAGENAME eq Brotato.exe" /NH', shell=True, text=True, errors="ignore")
            if "Brotato.exe" in out:
                return True
        except Exception:
            return True # При ошибке вызова tasklist не убиваем мост ложно
    return False

def log_event(text: str):
    """Выводит событие в консоль и безопасно дописывает в autopilot_decisions.log с временной меткой."""
    timestamp = time.strftime("[%Y-%m-%d %H:%M:%S]")
    line = f"{timestamp} {text}"
    print(line, flush=True)
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line + "\n")
            f.flush()
    except Exception:
        pass

# Подключаем движок синергий
import synergy_database as syn

OPENCODE_PATHS = [
    r"C:\Users\Vadim\AppData\Local\Programs\@opencodedesktop\resources\opencode-cli.exe",
    r"C:\Users\Vadim\AppData\Roaming\ai.opencode.desktop\cli\2.1.2-x64\opencode-cli.exe",
    r"C:\Users\Vadim\AppData\Roaming\npm\node_modules\@opencode\cli\bin\opencode.exe"
]

def find_opencode_cli():
    for p in OPENCODE_PATHS:
        if os.path.exists(p):
            return p
    return "opencode"

OPENCODE_CLI = find_opencode_cli()
MODEL_NAME = "opencode/deepseek-v4.1-flash-free"

# =====================================================================
# 1. АТОМАРНЫЙ ФАЙЛОВЫЙ ОБМЕН (IPC)
# =====================================================================

def write_json_atomic(path, data):
    """Атомарная запись через .tmp и последующий os.replace для исключения гонок с Godot."""
    tmp_path = f"{path}.tmp.{os.getpid()}_{int(time.time()*1000)}"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp_path, path)

def read_json_safe(path, retries=5, delay=0.04):
    """Безопасное чтение с повторными попытками."""
    for _ in range(retries):
        try:
            if not os.path.exists(path):
                return None
            with open(path, "r", encoding="utf-8") as f:
                content = f.read().strip()
                if content:
                    return json.loads(content)
        except (json.JSONDecodeError, PermissionError, OSError):
            time.sleep(delay)
    return None

# =====================================================================
# 2. ПОДГОТОВКА ПРОМПТА С ДИРЕКТИВАМИ СИНЕРГИИ
# =====================================================================

def format_prompt_for_deepseek(data):
    meta = syn.resolve_character_meta(data)
    char = data.get("character", {})
    char_name = char.get("name", meta["name_ru"])
    bonuses = char.get("bonuses_and_penalties", [])
    gold = data.get("gold", 0)
    wave = data.get("wave", 1)
    reroll = data.get("reroll_price", 0)
    stats = data.get("stats", {})
    weapons = data.get("equipped_weapons", [])
    items = data.get("items", [])
    shop_items = data.get("shop_items", [])

    key_stats = [
        "Max hp", "Hp regeneration", "Lifesteal", "Damage", "Melee damage",
        "Ranged damage", "Elemental damage", "Attack speed", "Crit chance",
        "Armor", "Dodge", "Harvesting", "Luck"
    ]
    stat_summary = [f"{k}: {v}" for k, v in stats.items() if k in key_stats and v != 0]
    equipped_summary = [f"{w.get('name')} (T{w.get('tier', 1)})" for w in weapons]

    # Семантический анализ и тегирование витрины
    shop_summary = []
    for it in shop_items:
        slot = it.get("slot")
        name = it.get("name")
        itype = it.get("type")
        tier = it.get("tier", 1)
        price = it.get("price", 0)
        effects = "; ".join(it.get("effects", []))
        locked = " [Заморожен]" if it.get("locked") else ""

        tag, reason = syn.analyze_and_tag_shop_item(it, meta, weapons)
        shop_summary.append(
            f"- [Слот {slot}] {name} ({itype} Tier {tier}) — Цена: {price}г{locked}\n"
            f"   ВЕРДИКТ: {tag} ({reason})\n"
            f"   Эффекты: {effects if effects else 'Базовые'}"
        )

    prompt = f"""Ты — сильнейший гроссмейстер-прогеймер по Brotato. Твоя задача — провести идеальную математическую закупку в магазине под конкретного персонажа.

СТРАТЕГИЧЕСКАЯ ДИРЕКТИВА ДЛЯ ПЕРСОНАЖА [{char_name.upper()}]:
1. ВИНКОНДИШН: {meta['win_condition']}
2. ЦЕЛЕВОЕ ОРУЖИЕ: {', '.join(meta['target_weapons'])} (ПОКУПКА ЛЮБОГО ДРУГОГО ОРУЖИЯ СТРОЖАЙШЕ ЗАПРЕЩЕНА!)
3. ПРИОРИТЕТНЫЕ СТАТЫ: {'; '.join(meta['priority_stats'])}
4. БЕСПОЛЕЗНЫЕ СТАТЫ (НЕ ПОКУПАТЬ): {'; '.join(meta['useless_stats'])}

ТЕКУЩЕЕ СОСТОЯНИЕ:
- Волна: {wave} из 20 | Золото в наличии: {gold} | Стоимость Замены: {reroll}
- Оружие в инвентаре ({len(weapons)}/12): {', '.join(equipped_summary) if equipped_summary else 'Пусто'}
- Пассивные статы: {', '.join(stat_summary) if stat_summary else 'Базовые'}

АССОРТИМЕНТ МАГАЗИНА С ПРЕДВАРИТЕЛЬНОЙ РАЗМЕТКОЙ:
{chr(10).join(shop_summary)}

ПРАВИЛА ЗАКУПКИ:
1. Оружие: покупай ИСКЛЮЧИТЕЛЬНО товары с тегом [CORE / ОБЯЗАТЕЛЬНО К ПОКУПКЕ]! Если на него не хватает золота — обязательно заморозь его ("action": "lock"). Товары с тегом [ЗАПРЕЩЕНО / ЛОМАЕТ СИНЕРГИЮ] НЕ ПОКУПАЙ НИ В КОЕМ СЛУЧАЕ!
2. Предметы: бери [СИНЕРГИЧНЫЙ ПРЕДМЕТ], избегай [МУСОРНЫЙ СТАТ].
3. Реролл (Замена): если на витрине нет профильных товаров, а золото осталось — смело крути реролл ("reroll": true, "go_next": false). Ты не ограничен в числе рероллов!
4. Бюджет: сумма покупок не может превышать {gold} золота.

ФОРМАТ ОТВЕТА (ТОЛЬКО ВАЛИДНЫЙ JSON БЕЗ ЛИШНЕГО ТЕКСТА):
```json
{{
  "comment": "Четкое обоснование выбора под синергию Палок и персонажа (1-2 предложения на русском)",
  "actions": [
    {{"action": "buy", "slot": 0}},
    {{"action": "lock", "slot": 1}}
  ],
  "reroll": false,
  "go_next": true
}}
```"""
    return prompt

# =====================================================================
# 3. УСТОЙЧИВЫЙ ПАРСИНГ ОТВЕТОВ LLM
# =====================================================================

def extract_json_from_response(raw_text):
    clean = re.sub(r"<think>.*?</think>", "", raw_text, flags=re.DOTALL)
    clean = re.sub(r"\[Hacking Everything\].*?\n", "", clean)

    # 1. Поиск в markdown блоках ```json ... ```
    json_blocks = re.findall(r"```(?:json)?\s*(\{.*?\})\s*```", clean, re.DOTALL)
    for block in json_blocks:
        try:
            parsed = json.loads(block)
            if isinstance(parsed, dict) and "actions" in parsed:
                return parsed
        except Exception:
            continue

    # 2. Поиск сбалансированного JSON-объекта с ключом "actions"
    pattern = re.compile(r"\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}", re.DOTALL)
    for match in pattern.finditer(clean):
        try:
            cand = json.loads(match.group(0))
            if isinstance(cand, dict) and "actions" in cand:
                return cand
        except Exception:
            continue

    # 3. Fallback: поиск от первого { до последнего }
    start = clean.find("{")
    end = clean.rfind("}")
    if start != -1 and end != -1 and end > start:
        candidate = clean[start:end+1]
        try:
            parsed = json.loads(candidate)
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            pass

    raise ValueError("Не удалось обнаружить валидный JSON с решениями в ответе модели")

# =====================================================================
# 4. ВЫЗОВ OPENCODE CLI
# =====================================================================

def consult_deepseek(prompt):
    print(f"[DeepSeek] Отправка запроса в {MODEL_NAME} через OpenCode...", flush=True)
    cmd = [
        OPENCODE_CLI,
        "run",
        "--model", MODEL_NAME,
        "--thinking=false",
        prompt
    ]
    start = time.time()
    
    # В Windows для скрытия черного окна дочернего консольного процесса используем CREATE_NO_WINDOW
    creationflags = 0
    if sys.platform == "win32":
        creationflags = subprocess.CREATE_NO_WINDOW

    res = subprocess.run(
        cmd,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=35,
        creationflags=creationflags
    )
    duration = time.time() - start
    print(f"[DeepSeek] Ответ получен за {duration:.2f} сек (код {res.returncode})", flush=True)

    if res.returncode != 0:
        raise RuntimeError(f"OpenCode CLI error: {res.stderr.strip() or res.stdout.strip()}")

    return extract_json_from_response(res.stdout)

# =====================================================================
# 5. ГИБРИДНЫЙ ЭВРИСТИЧЕСКИЙ FALLBACK (СИНЕРГИЙНЫЙ)
# =====================================================================

def make_smart_decision(data):
    """Строит математически оптимальный билд при сбоях LLM на базе базы знаний синергий."""
    meta = syn.resolve_character_meta(data)
    gold = data.get("gold", 0)
    wave = data.get("wave", 1)
    reroll_price = data.get("reroll_price", 1)
    shop_items = data.get("shop_items", [])
    weapons = data.get("equipped_weapons", [])

    actions = []
    spent = 0
    remaining_gold = gold
    comments = []

    # 1. Сначала выкупаем/морозим только CORE целевое оружие
    found_core = False
    for item in shop_items:
        tag, _ = syn.analyze_and_tag_shop_item(item, meta, weapons)
        slot = item.get("slot")
        name = item.get("name", "")
        price = item.get("price", 999)

        if "CORE" in tag:
            found_core = True
            if price <= remaining_gold:
                actions.append({"action": "buy", "slot": slot})
                remaining_gold -= price
                spent += price
                comments.append(f"{name} ({price}г)")
            elif not item.get("locked"):
                actions.append({"action": "lock", "slot": slot})
                comments.append(f"заморозка {name}")

    # 2. Покупка синергичных пассивных предметов
    for item in shop_items:
        tag, _ = syn.analyze_and_tag_shop_item(item, meta, weapons)
        slot = item.get("slot")
        name = item.get("name", "")
        price = item.get("price", 999)

        if "СИНЕРГИЧНЫЙ" in tag and price <= remaining_gold:
            actions.append({"action": "buy", "slot": slot})
            remaining_gold -= price
            spent += price
            comments.append(f"{name} ({price}г)")

    # 3. Реролл, если целевого оружия на витрине не было и хватает золота с запасом
    do_reroll = False
    reroll_count = data.get("reroll_count", 0)
    max_rerolls = 2 if wave <= 10 else 3
    if not found_core and reroll_count < max_rerolls:
        if remaining_gold >= reroll_price and reroll_price <= (remaining_gold * 0.25) and (remaining_gold - reroll_price >= 10):
            do_reroll = True

    summary = f"Синергия {meta['name_ru']}: потрачено {spent}г. " + (", ".join(comments) if comments else "нет профильных товаров")
    if do_reroll:
        summary += f" | Реролл за {reroll_price}г"

    return {
        "comment": summary,
        "actions": actions,
        "reroll": do_reroll,
        "go_next": not do_reroll
    }

# =====================================================================
# 6. ВАЛИДАЦИЯ И ЗАЩИТНЫЙ ШЛЮЗ (GUARDRAILS)
# =====================================================================

def validate_and_sanitize_decision(decision, data):
    """
    Защитный шлюз:
    1. Блокирует покупку несовместимого оружия (например Когтя для Мастера на все руки).
    2. Следит за бюджетом.
    3. Автоматически понижает покупку до заморозки, если золота не хватило.
    4. Сохраняет свободу рероллов при наличии средств.
    """
    meta = syn.resolve_character_meta(data)
    weapons = data.get("equipped_weapons", [])
    gold = data.get("gold", 0)
    shop_items = {item.get("slot"): item for item in data.get("shop_items", [])}

    sanitized_actions = []
    spent = 0

    actions = decision.get("actions", [])
    if isinstance(actions, list):
        for act in actions:
            if not isinstance(act, dict):
                continue
            action_type = act.get("action")
            slot = act.get("slot")
            if slot not in shop_items:
                continue

            item = shop_items[slot]
            price = item.get("price", 999)
            tag, reason = syn.analyze_and_tag_shop_item(item, meta, weapons)

            # ЗАЩИТА: Блокировка покупки запрещенного оружия
            if action_type == "buy" and "ЗАПРЕЩЕНО" in tag:
                print(f"[GUARDRAIL BLOCKED] Покупка {item.get('name')} заблокирована: {reason}", flush=True)
                continue

            if action_type == "buy":
                if spent + price <= gold:
                    spent += price
                    sanitized_actions.append({"action": "buy", "slot": slot})
                else:
                    if not item.get("locked"):
                        sanitized_actions.append({"action": "lock", "slot": slot})
            elif action_type in ["lock", "unlock"]:
                sanitized_actions.append({"action": action_type, "slot": slot})

    reroll = bool(decision.get("reroll", False))
    reroll_price = data.get("reroll_price", 0)
    wave = data.get("wave", 1)
    reroll_count = data.get("reroll_count", 0)
    max_rerolls = 2 if wave <= 10 else 3

    reroll_blocked = False
    if reroll:
        # Проверка лимита рероллов и защиты от банкротства
        if reroll_count >= max_rerolls:
            reroll = False
            reroll_blocked = True
        elif spent + reroll_price > gold:
            reroll = False
            reroll_blocked = True
        elif reroll_price > (gold * 0.35): # Реролл не должен сжигать больше трети банка
            reroll = False
            reroll_blocked = True

    # Если рероллим, то переход на следующий раунд строго запрещен (go_next = False)
    if reroll:
        go_next = False
    elif reroll_blocked:
        # Если реролл был запрошен, но заблокирован предохранителем, принудительно переходим дальше
        go_next = True
    else:
        go_next = decision.get("go_next", True)

    return {
        "request_id": data.get("request_id", ""),
        "comment": decision.get("comment", f"DeepSeek: закупка на {spent}г."),
        "actions": sanitized_actions,
        "reroll": reroll,
        "go_next": go_next
    }

# =====================================================================
# 7. ОСНОВНОЙ ЦИКЛ ОБРАБОТКИ
# =====================================================================

def process_shop_request(data):
    request_id = data.get("request_id", "req_legacy")
    wave = data.get("wave", 1)
    gold = data.get("gold", 0)
    char = data.get("character", {}).get("name", "Unknown")

    log_event(f"[SHOP] Магазин открыт: Волна {wave} | Персонаж: {char} | Золото: {gold} | Request ID: {request_id}")

    prompt = format_prompt_for_deepseek(data)
    try:
        raw_decision = consult_deepseek(prompt)
        decision = validate_and_sanitize_decision(raw_decision, data)
        log_event(f"[SHOP DEEPSEEK] {decision.get('comment')}")
    except Exception as e:
        log_event(f"[SHOP WARNING] Ошибка DeepSeek: {e}. Переключение на Smart-Fallback...")
        raw_decision = make_smart_decision(data)
        decision = validate_and_sanitize_decision(raw_decision, data)
        decision["comment"] = f"[Эвристика Fallback]: {decision.get('comment')}"
        log_event(f"[SHOP FALLBACK] {decision.get('comment')}")

    for act in decision.get("actions", []):
        slot = act.get("slot")
        item_name = next((it.get("name") for it in data.get("shop_items", []) if it.get("slot") == slot), f"Слот {slot}")
        log_event(f"  -> Действие: {act.get('action').upper()} [{item_name}] (Слот {slot})")
    if decision.get("reroll"):
        log_event("  -> Действие: РЕРОЛЛ магазина")
    log_event(f"  -> Переход к следующей волне: {decision.get('go_next')}")

    return decision

# =====================================================================
# 8. ОБРАБОТКА УЛУЧШЕНИЙ УРОВНЯ (LEVEL UP / UPGRADES)
# =====================================================================

def format_prompt_for_upgrade(data):
    meta = syn.resolve_character_meta(data)
    char_name = data.get("character", {}).get("name", meta["name_ru"])
    level = data.get("level", 1)
    gold = data.get("gold", 0)
    reroll_price = data.get("reroll_price", 1)
    options = data.get("options", [])
    weapons = data.get("equipped_weapons", [])
    
    equipped_summary = [f"{w.get('name')} (T{w.get('tier', 1)})" for w in weapons]

    best_slot, best_score, heuristic_verdict = syn.evaluate_level_up_options(
        options, meta, gold, reroll_price, data.get("wave", 1)
    )

    options_summary = []
    for opt in options:
        slot = opt.get("slot")
        name = opt.get("name")
        effects = "; ".join(opt.get("effects", []))
        options_summary.append(f"- [Карточка {slot}] {name}: {effects}")

    prompt = f"""Ты — сильнейший гроссмейстер Brotato. Персонаж [{char_name.upper()}] повысил уровень (Уровень {level})!
Выбери математически идеальное улучшение характеристик.

СТРАТЕГИЯ ПЕРСОНАЖА:
- Винкондишн: {meta['win_condition']}
- Приоритетные статы: {'; '.join(meta['priority_stats'])}
- Бесполезные статы: {'; '.join(meta['useless_stats'])}
- Оружие в руках: {', '.join(equipped_summary) if equipped_summary else 'Нет'}
- Золото: {gold} | Стоимость Замены (реролла): {reroll_price}

ПРЕДЛОЖЕННЫЕ ВАРИАНТЫ:
{chr(10).join(options_summary)}

МАТЕМАТИЧЕСКАЯ ПОДСКАЗКА ЭВРИСТИКИ:
{heuristic_verdict}

ПРАВИЛА:
1. Если среди вариантов есть Урон в ближнем бою, Скорость атаки, Макс HP, Броня или Кража жизни — выбирай лучший из них ("action": "choose", "slot": <номер_слота>).
2. Если ВСЕ 4 варианта мусорные (дальний бой, стихии, инженерия), а денег хватает на Замену — жми реролл ("action": "reroll").
3. Если реролл слишком дорогой, бери наименее вредный стат (Удача или Уклонение).

ОТВЕТЬ ТОЛЬКО В JSON:
```json
{{
  "comment": "Краткое обоснование выбора под синергию (1 предложение)",
  "action": "choose",
  "slot": {best_slot}
}}
```
Или:
```json
{{
  "comment": "Мусорные статы, рероллим за {reroll_price}г в поисках ближнего боя",
  "action": "reroll"
}}
```"""
    return prompt, best_slot, best_score

def process_upgrade_request(data):
    request_id = data.get("request_id", "upg_legacy")
    level = data.get("level", 1)
    gold = data.get("gold", 0)
    reroll_price = data.get("reroll_price", 1)
    options = data.get("options", [])
    meta = syn.resolve_character_meta(data)

    log_event(f"[LEVEL_UP] Повышение уровня: {level} | Персонаж: {meta['name_ru']} | Золото: {gold} | Реролл: {reroll_price} | Request ID: {request_id}")

    prompt, best_slot, best_score = format_prompt_for_upgrade(data)
    
    # Решение по умолчанию (Smart Fallback)
    fallback_action = "choose"
    fallback_slot = best_slot
    if best_score < 60 and gold >= reroll_price and (reroll_price <= 5 or reroll_price <= (gold * 0.2)):
        fallback_action = "reroll"

    try:
        raw_decision = consult_deepseek(prompt)
        action = raw_decision.get("action", fallback_action)
        slot = int(raw_decision.get("slot", fallback_slot))
        comment = raw_decision.get("comment", "DeepSeek выбор прокачки")
        log_event(f"[LEVEL_UP DEEPSEEK] {comment}")
    except Exception as e:
        log_event(f"[LEVEL_UP WARNING] Ошибка DeepSeek при Level Up: {e}. Применение Smart Fallback...")
        action = fallback_action
        slot = fallback_slot
        comment = f"[Эвристика Fallback]: {action.upper()}"
        log_event(f"[LEVEL_UP FALLBACK] {comment}")

    if action == "reroll":
        if gold < reroll_price:
            action = "choose"
            slot = best_slot
            comment += " (Не хватило золота на реролл, выбираем лучший стат)"
        else:
            log_event("  -> Действие: РЕРОЛЛ улучшений уровня")

    if action == "choose":
        opt_name = next((o.get("name") for o in options if o.get("slot") == slot), f"Слот {slot}")
        log_event(f"  -> Действие: ВЫБРАТЬ [{opt_name}] (Слот {slot})")

    return {
        "request_id": request_id,
        "action": action,
        "slot": slot,
        "comment": comment
    }

# =====================================================================
# 9. ОБРАБОТКА ЯЩИКОВ С ПРЕДМЕТАМИ (CRATES / CONSUMABLES)
# =====================================================================

def process_crate_request(data):
    request_id = data.get("request_id", "crate_legacy")
    item = data.get("item", {})
    char_name = data.get("character", {}).get("name", "Unknown")
    weapons = data.get("equipped_weapons", [])
    meta = syn.resolve_character_meta(data)

    action, reason = syn.evaluate_crate_item(item, meta, weapons)
    item_name = item.get("name", "Неизвестный предмет")
    log_event(f"[CRATE] Открыт ящик с предметом ({char_name}): [{item_name}] -> {action.upper()} ({reason})")

    return {
        "request_id": request_id,
        "action": action,
        "comment": reason
    }

def main():
    log_event("=" * 65)
    log_event("  BROTATO AI AUTOPILOT BRIDGE: DEEPSEEK v4.1 FLASH (HYBRID)")
    log_event("  Orchestrator: Antigravity | Subagent: OpenCode CLI")
    log_event(f"  PID: {os.getpid()} | CLI Path: {OPENCODE_CLI}")
    log_event(f"  Model: {MODEL_NAME}")
    log_event(f"  Log File: {LOG_PATH}")
    log_event(f"  Monitoring Shop:    {REQ_PATH}")
    log_event(f"  Monitoring Upgrade: {UPG_REQ_PATH}")
    log_event(f"  Monitoring Crate:   {CRATE_REQ_PATH}")
    log_event("=" * 65)

    # Очистка устаревших файлов запросов и решений предыдущих сессий
    for stale_path in [REQ_PATH, DEC_PATH, UPG_REQ_PATH, UPG_DEC_PATH, CRATE_REQ_PATH, CRATE_DEC_PATH]:
        if os.path.exists(stale_path):
            try:
                os.remove(stale_path)
            except Exception:
                pass

    # Сохраняем текущий PID процесса, чтобы игра могла управлять процессом
    try:
        with open(PID_PATH, "w", encoding="utf-8") as f:
            f.write(str(os.getpid()))
    except Exception:
        pass

    last_shop_mtime = 0
    last_shop_req_id = None

    last_upg_mtime = 0
    last_upg_req_id = None

    last_crate_mtime = 0
    last_crate_req_id = None

    loop_count = 0
    consecutive_missing_brotato = 0

    while True:
        loop_count += 1

        # Проверка активности игры Brotato (каждые 3 секунды / 15 итераций)
        if loop_count % 15 == 0:
            if not is_brotato_running():
                consecutive_missing_brotato += 1
                if consecutive_missing_brotato >= 3: # 3 проверки подряд (~9 секунд)
                    log_event("[SYSTEM] Процесс Brotato не обнаружен. Автоматическое завершение моста для исключения зомби-процессов.")
                    if os.path.exists(PID_PATH):
                        try:
                            os.remove(PID_PATH)
                        except Exception:
                            pass
                    sys.exit(0)
            else:
                consecutive_missing_brotato = 0

        # 1. Проверка запросов магазина
        if os.path.exists(REQ_PATH):
            try:
                mtime = os.path.getmtime(REQ_PATH)
                if mtime != last_shop_mtime:
                    data = read_json_safe(REQ_PATH)
                    if data:
                        req_id = data.get("request_id")
                        if req_id and req_id == last_shop_req_id:
                            pass
                        else:
                            last_shop_mtime = mtime
                            last_shop_req_id = req_id
                            decision = process_shop_request(data)
                            write_json_atomic(DEC_PATH, decision)
                            log_event(f"[IPC] Решение магазина записано в {DEC_PATH}\n")
            except Exception as e:
                log_event(f"[SHOP BRIDGE ERROR] {e}")

        # 2. Проверка запросов прокачки (Level Up)
        if os.path.exists(UPG_REQ_PATH):
            try:
                mtime = os.path.getmtime(UPG_REQ_PATH)
                if mtime != last_upg_mtime:
                    data = read_json_safe(UPG_REQ_PATH)
                    if data:
                        req_id = data.get("request_id")
                        if req_id and req_id == last_upg_req_id:
                            pass
                        else:
                            last_upg_mtime = mtime
                            last_upg_req_id = req_id
                            decision = process_upgrade_request(data)
                            write_json_atomic(UPG_DEC_PATH, decision)
                            log_event(f"[IPC] Решение прокачки записано в {UPG_DEC_PATH}\n")
            except Exception as e:
                log_event(f"[UPGRADE BRIDGE ERROR] {e}")

        # 3. Проверка запросов ящиков с предметами (Crates)
        if os.path.exists(CRATE_REQ_PATH):
            try:
                mtime = os.path.getmtime(CRATE_REQ_PATH)
                if mtime != last_crate_mtime:
                    data = read_json_safe(CRATE_REQ_PATH)
                    if data:
                        req_id = data.get("request_id")
                        if req_id and req_id == last_crate_req_id:
                            pass
                        else:
                            last_crate_mtime = mtime
                            last_crate_req_id = req_id
                            decision = process_crate_request(data)
                            write_json_atomic(CRATE_DEC_PATH, decision)
                            log_event(f"[IPC] Решение ящика записано в {CRATE_DEC_PATH}\n")
            except Exception as e:
                log_event(f"[CRATE BRIDGE ERROR] {e}")

        time.sleep(0.2)

if __name__ == "__main__":
    main()
