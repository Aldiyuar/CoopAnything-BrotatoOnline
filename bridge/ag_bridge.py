import os
import sys
import time
import json

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

BRIDGE_DIR = r"D:\Brotato\bridge"
REQ_PATH = os.path.join(BRIDGE_DIR, "shop_request.json")
DEC_PATH = os.path.join(BRIDGE_DIR, "shop_decision.json")

def format_shop_summary(data):
    char = data.get("character", {})
    char_name = char.get("name", "Unknown")
    bonuses = char.get("bonuses_and_penalties", [])
    gold = data.get("gold", 0)
    wave = data.get("wave", 1)
    reroll = data.get("reroll_price", 0)
    stats = data.get("stats", {})
    weapons = data.get("equipped_weapons", [])
    items = data.get("items", [])
    shop_items = data.get("shop_items", [])

    lines = []
    lines.append("=" * 60)
    lines.append(f" КАРТОШКА: {char_name.upper()} | ВОЛНА: {wave} | ЗОЛОТО: {gold} | РЕРОЛЛ: {reroll}")
    lines.append("-" * 60)
    if bonuses:
        lines.append("Особенности персонажа:")
        for b in bonuses:
            lines.append(f"  * {b}")
    
    key_stats = ["Max hp", "Hp regeneration", "Lifesteal", "Damage", "Melee damage", "Ranged damage", "Elemental damage", "Attack speed", "Crit chance", "Armor", "Dodge", "Harvesting", "Luck"]
    stat_summary = []
    for k, v in stats.items():
        if k in key_stats and v != 0:
            stat_summary.append(f"{k}: {v}")
    if stat_summary:
        lines.append(f"Ключевые статы: {', '.join(stat_summary)}")
    
    if weapons:
        w_strs = [f"{w.get('name')} (T{w.get('tier', 1)})" for w in weapons]
        lines.append(f"Оружие в руках ({len(weapons)}): {', '.join(w_strs)}")
    
    lines.append("\nТовары в магазине:")
    for item in shop_items:
        slot = item.get("slot")
        name = item.get("name")
        itype = item.get("type")
        tier = item.get("tier", 1)
        price = item.get("price")
        effects = "; ".join(item.get("effects", []))
        locked = " [LOCKED]" if item.get("locked") else ""
        lines.append(f"  [Слот {slot}] {name} ({itype} T{tier}) - Цена: {price}{locked}")
        if effects:
            lines.append(f"       -> {effects}")
    lines.append("=" * 60)
    return "\n".join(lines)

def make_smart_decision(data):
    """
    Продвинутый алгоритм билдостроения:
    - Моносинергия оружия: НИКОГДА не покупает случайные пушки другого типа!
      Если в руках Палки — берет ТОЛЬКО Палки (для +4 урона за каждую).
    - Оценивает синергию статов: для ближнего боя берет Melee Damage и HP.
    - Автореролл: если профильного оружия в магазине нет, а реролл дешевый — крутит магазин!
    """
    gold = data.get("gold", 0)
    wave = data.get("wave", 1)
    reroll_price = data.get("reroll_price", 1)
    char_info = data.get("character", {})
    char_name = char_info.get("name", "").lower()
    bonuses_text = " ".join(char_info.get("bonuses_and_penalties", [])).lower()
    weapons = data.get("equipped_weapons", [])
    shop_items = data.get("shop_items", [])
    
    actions = []
    spent = 0
    remaining_gold = gold
    comments = []
    
    # Определяем основные типы оружия в руках
    equipped_names = [w.get("name") for w in weapons]
    primary_weapon_name = equipped_names[0] if equipped_names else ""
    is_stick_build = any("палка" in w.lower() or "stick" in w.lower() for w in equipped_names)
    
    # 1. Покупка ТОЛЬКО профильного оружия
    found_core_weapon = False
    for item in shop_items:
        slot = item.get("slot")
        name = item.get("name")
        price = item.get("price", 999)
        itype = item.get("type")
        
        if itype == "Weapon":
            is_matching = False
            if is_stick_build and ("палка" in name.lower() or "stick" in name.lower()):
                is_matching = True
            elif name in equipped_names:
                is_matching = True
                
            if is_matching:
                found_core_weapon = True
                if price <= remaining_gold:
                    actions.append({"action": "buy", "slot": slot})
                    remaining_gold -= price
                    spent += price
                    comments.append(f"Куплено профильное оружие {name} ({price}г)")
                elif not item.get("locked"):
                    actions.append({"action": "lock", "slot": slot})
                    comments.append(f"Заморожено профильное оружие {name}")

    # 2. Покупка синергичных пассивных предметов
    for item in shop_items:
        slot = item.get("slot")
        name = item.get("name")
        price = item.get("price", 999)
        itype = item.get("type")
        effects_str = " ".join(item.get("effects", [])).lower()
        
        if itype != "Item" or price > remaining_gold:
            continue
            
        is_good = False
        
        # Стероиды, урон в ближнем бою, макс хп для милишников / палок
        if is_stick_build and any(w in effects_str for w in ["урон в ближнем бою", "melee damage", "макс. оз", "max hp"]):
            is_good = True
            
        # Экономика на волнах 1-5
        if wave <= 5 and any(w in effects_str for w in ["урожай", "дерево", "harvesting", "tree"]):
            is_good = True
            
        if is_good:
            actions.append({"action": "buy", "slot": slot})
            remaining_gold -= price
            spent += price
            comments.append(f"Куплен синергичный предмет {name} ({price}г)")

    # 3. Умный реролл: если профильное оружие не нашли, а реролл копеечный (например, 1-3 золота)
    do_reroll = False
    if not found_core_weapon and remaining_gold >= reroll_price and reroll_price <= (gold * 0.2):
        do_reroll = True
        comments.append(f"Реролл магазина за {reroll_price}г в поиске {primary_weapon_name}")

    summary = f"Автопилот: потрачено {spent}г. " + "; ".join(comments) if comments else "Автопилот: товары не подошли, копим золото."
    
    return {
        "comment": summary,
        "actions": actions,
        "reroll": do_reroll,
        "go_next": True
    }

import subprocess

def notify_neural_network(data, summary, conv_id):
    agentapi_bat = r"C:\Users\Vadim\.gemini\antigravity\bin\agentapi.bat"
    if not (os.path.exists(agentapi_bat) and conv_id):
        return False
        
    prompt_msg = (
        f"[МАГАЗИН BROTATO: ВОЛНА {data.get('wave')} | ЗОЛОТО: {data.get('gold')}]\n\n"
        f"{summary}\n\n"
        "Инструкция для нейросети Antigravity: Тщательно проанализируй персонажа, его пассивки, синергию оружия, "
        "текущие характеристики и товары в слотах. Прими оптимальное стратегическое решение и запиши его в "
        "D:\\Brotato\\bridge\\shop_decision.json с полями 'actions' (список {action: 'buy'|'lock'|'unlock', slot: 0..3}), "
        "'reroll' (true/false), 'go_next' (true/false) и 'comment'. Прокомментируй логику своего выбора в чате."
    )
    print(f"[AI] Передача состояния игры в нейросеть Antigravity (conv: {conv_id})...", flush=True)
    try:
        res = subprocess.run(
            [agentapi_bat, "send-message", conv_id, prompt_msg],
            capture_output=True,
            text=True,
            encoding="utf-8"
        )
        if res.returncode == 0:
            print("[AI] Запрос доставлен в активный контекст нейросети. Ждем решения...", flush=True)
            return True
        else:
            print(f"[AI ERROR] {res.stderr}", flush=True)
    except Exception as e:
        print(f"[AI EXCEPTION] {e}", flush=True)
    return False

def main():
    mode = "smart" if "--smart" in sys.argv else "agent"
    conv_id = "cd486931-07dd-44b2-b2d1-654266dfbd66"
    for i, arg in enumerate(sys.argv):
        if arg == "--conv" and i + 1 < len(sys.argv):
            conv_id = sys.argv[i + 1]

    print(f"=== Antigravity Brotato Bridge Запущен (Режим: {mode.upper()}) ===", flush=True)
    if mode == "agent":
        print(f"Нейросетевое управление активно! ID диалога: {conv_id}", flush=True)
    print(f"Мониторинг папки: {BRIDGE_DIR}", flush=True)
    
    last_mtime = 0
    while True:
        if os.path.exists(REQ_PATH):
            try:
                mtime = os.path.getmtime(REQ_PATH)
                if mtime != last_mtime:
                    last_mtime = mtime
                    time.sleep(0.1)
                    with open(REQ_PATH, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    
                    summary = format_shop_summary(data)
                    print(f"\n[EVENT: SHOP_OPENED] Волна {data.get('wave')} | Золото: {data.get('gold')}", flush=True)
                    print(summary, flush=True)
                    
                    if mode == "smart":
                        decision = make_smart_decision(data)
                        print(f"[DECISION] {decision.get('comment')}", flush=True)
                        with open(DEC_PATH, "w", encoding="utf-8") as f:
                            json.dump(decision, f, indent=2, ensure_ascii=False)
                        print("[ACTION] Решение передано в игру!\n", flush=True)
                    else:
                        notify_neural_network(data, summary, conv_id)
            except Exception as e:
                print(f"[ERROR] {e}", flush=True)
        time.sleep(0.4)

if __name__ == "__main__":
    main()

