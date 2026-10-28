"""
Unit tests for Brotato Synergy Engine & Guardrails
"""

import sys
import unittest

sys.path.insert(0, r"D:\Brotato\bridge")

import synergy_database as syn
import deepseek_shop_bridge as bridge

class TestBrotatoSynergyEngine(unittest.TestCase):

    def test_multitasker_meta_resolution(self):
        data = {
            "character": {
                "name": "Мастер на все руки",
                "id": "character_multitasker"
            }
        }
        meta = syn.resolve_character_meta(data)
        self.assertEqual(meta["name_ru"], "Мастер на все руки")
        self.assertTrue(meta["strict_mono_weapon"])
        self.assertIn("палка", meta["target_weapons"])

    def test_shop_tagging_stick_vs_claw(self):
        data = {"character": {"name": "Мастер на все руки"}}
        meta = syn.resolve_character_meta(data)

        stick_item = {"type": "Weapon", "name": "Палка", "slot": 0}
        claw_item = {"type": "Weapon", "name": "Коготь", "slot": 1}
        tree_item = {"type": "Item", "name": "Дерево", "slot": 2}
        elemental_item = {"type": "Item", "name": "Огненный шар", "effects": ["+3 стихийный урон"], "slot": 3}

        tag_stick, _ = syn.analyze_and_tag_shop_item(stick_item, meta, [])
        tag_claw, _ = syn.analyze_and_tag_shop_item(claw_item, meta, [])
        tag_tree, _ = syn.analyze_and_tag_shop_item(tree_item, meta, [])
        tag_elem, _ = syn.analyze_and_tag_shop_item(elemental_item, meta, [])

        self.assertIn("CORE", tag_stick)
        self.assertIn("ЗАПРЕЩЕНО", tag_claw)
        self.assertIn("СИНЕРГИЧНЫЙ", tag_tree)
        self.assertIn("МУСОРНЫЙ", tag_elem)

    def test_guardrail_blocks_claw_for_multitasker(self):
        data = {
            "request_id": "test_req",
            "character": {"name": "Мастер на все руки"},
            "gold": 100,
            "equipped_weapons": [{"name": "Палка"}],
            "shop_items": [
                {"slot": 0, "name": "Коготь", "type": "Weapon", "price": 20},
                {"slot": 1, "name": "Палка", "type": "Weapon", "price": 15}
            ]
        }
        # Допустим, модель галлюцинирует и пытается купить Коготь
        raw_decision = {
            "comment": "Покупаем Коготь и Палку",
            "actions": [
                {"action": "buy", "slot": 0},
                {"action": "buy", "slot": 1}
            ],
            "reroll": False,
            "go_next": True
        }
        sanitized = bridge.validate_and_sanitize_decision(raw_decision, data)

        bought_slots = [a["slot"] for a in sanitized["actions"] if a["action"] == "buy"]
        # Слот 0 (Коготь) ОБЯЗАН быть заблокирован guardrail'ом!
        self.assertNotIn(0, bought_slots)
        # Слот 1 (Палка) должен быть куплен
        self.assertIn(1, bought_slots)

    def test_crate_evaluation_take_stick_discard_claw(self):
        data = {"character": {"name": "Мастер на все руки"}}
        meta = syn.resolve_character_meta(data)

        stick_crate = {"type": "Weapon", "name": "Палка", "id": "weapon_stick"}
        claw_crate = {"type": "Weapon", "name": "Коготь", "id": "weapon_claw"}
        tree_crate = {"type": "Item", "name": "Дерево", "id": "item_tree"}
        elemental_crate = {"type": "Item", "name": "Огненный свиток", "effects": ["+3 стихийный урон"]}

        act_stick, _ = syn.evaluate_crate_item(stick_crate, meta, [])
        act_claw, _ = syn.evaluate_crate_item(claw_crate, meta, [])
        act_tree, _ = syn.evaluate_crate_item(tree_crate, meta, [])
        act_elem, _ = syn.evaluate_crate_item(elemental_crate, meta, [])

        self.assertEqual(act_stick, "take")
        self.assertEqual(act_claw, "discard")
        self.assertEqual(act_tree, "take")
        self.assertEqual(act_elem, "discard")

    def test_guardrail_forces_go_next_false_on_reroll(self):
        data = {
            "request_id": "test_reroll_guard",
            "gold": 100,
            "reroll_price": 5,
            "wave": 2,
            "reroll_count": 0,
            "shop_items": []
        }
        raw_decision = {
            "comment": "Рероллим",
            "actions": [],
            "reroll": True,
            "go_next": True # Модель ошиблась и передала go_next: true вместе с reroll: true!
        }
        sanitized = bridge.validate_and_sanitize_decision(raw_decision, data)
        self.assertTrue(sanitized["reroll"])
        self.assertFalse(sanitized["go_next"]) # Должно быть принудительно переопределено в False!

    def test_guardrail_prevents_excessive_rerolls(self):
        data = {
            "request_id": "test_reroll_limit",
            "gold": 100,
            "reroll_price": 5,
            "wave": 2,
            "reroll_count": 2, # Уже сделано 2 реролла на ранней волне
            "shop_items": []
        }
        raw_decision = {
            "comment": "Еще один реролл",
            "actions": [],
            "reroll": True,
            "go_next": False
        }
        sanitized = bridge.validate_and_sanitize_decision(raw_decision, data)
        self.assertFalse(sanitized["reroll"]) # Должно быть отменено!
        self.assertTrue(sanitized["go_next"]) # Должен перейти к следующей волне

if __name__ == "__main__":
    unittest.main()
