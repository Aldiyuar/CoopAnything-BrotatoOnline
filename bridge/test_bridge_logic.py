"""
Unit tests for Brotato AI Bridge (Enhanced logic)
"""

import os
import sys
import tempfile
import unittest

# Добавляем путь к bridge
sys.path.insert(0, r"D:\Brotato\bridge")

import deepseek_shop_bridge as bridge

class TestBrotatoBridgeLogic(unittest.TestCase):

    def test_extract_json_with_think_and_markdown(self):
        sample = """
        <think>
        Player has 50 gold and 4 sticks. Stick synergy is very strong (+4 damage per stick).
        We should buy stick in slot 1 and lock the tree in slot 3.
        </think>
        [Hacking Everything] log line
        Here is the final decision:
        ```json
        {
          "comment": "Покупаем палку для синергии +4 урона и морозим дерево",
          "actions": [
            {"action": "buy", "slot": 1},
            {"action": "lock", "slot": 3}
          ],
          "reroll": false,
          "go_next": true
        }
        ```
        Good luck with wave 4!
        """
        parsed = bridge.extract_json_from_response(sample)
        self.assertEqual(parsed["actions"][0]["slot"], 1)
        self.assertEqual(parsed["actions"][1]["action"], "lock")
        self.assertTrue(parsed["go_next"])

    def test_extract_json_plain_object(self):
        sample = 'Превосходно. {"comment": "Все супер", "actions": [{"action": "buy", "slot": 0}], "reroll": true, "go_next": false}'
        parsed = bridge.extract_json_from_response(sample)
        self.assertEqual(parsed["actions"][0]["slot"], 0)
        self.assertTrue(parsed["reroll"])
        self.assertFalse(parsed["go_next"])

    def test_smart_heuristic_stick_synergy(self):
        data = {
            "gold": 60,
            "wave": 2,
            "reroll_price": 5,
            "equipped_weapons": [{"name": "Палка", "tier": 1}],
            "shop_items": [
                {"slot": 0, "name": "Пистолет", "type": "Weapon", "price": 20},
                {"slot": 1, "name": "Палка", "type": "Weapon", "price": 25, "locked": False},
                {"slot": 2, "name": "Дерево", "type": "Item", "price": 15, "effects": ["+1 дерево"]},
                {"slot": 3, "name": "Магический свиток", "type": "Item", "price": 50, "effects": ["+2 стихийный урон"]}
            ]
        }
        dec = bridge.make_smart_decision(data)
        actions = dec["actions"]
        # Должна быть куплена Палка (слот 1) и Дерево (слот 2), но НЕ пистолет (слот 0)
        bought_slots = [a["slot"] for a in actions if a["action"] == "buy"]
        self.assertIn(1, bought_slots)
        self.assertIn(2, bought_slots)
        self.assertNotIn(0, bought_slots)

    def test_validate_and_sanitize_budget_and_request_id(self):
        data = {
            "request_id": "test_req_42",
            "gold": 30,
            "reroll_price": 5,
            "shop_items": [
                {"slot": 0, "name": "Палка", "price": 25, "locked": False},
                {"slot": 1, "name": "Меч", "price": 20, "locked": False}
            ]
        }
        # ИИ хочет купить оба (25 + 20 = 45 > 30)
        raw_decision = {
            "comment": "Покупаем оба",
            "actions": [
                {"action": "buy", "slot": 0},
                {"action": "buy", "slot": 1}
            ],
            "reroll": True,
            "go_next": False
        }
        sanitized = bridge.validate_and_sanitize_decision(raw_decision, data)
        self.assertEqual(sanitized["request_id"], "test_req_42")
        # Слот 0 куплен за 25г. На слот 1 осталось 5г < 20г -> понижен до lock!
        self.assertEqual(sanitized["actions"][0], {"action": "buy", "slot": 0})
        self.assertEqual(sanitized["actions"][1], {"action": "lock", "slot": 1})
        # На реролл (5г) денег хватило (30 - 25 = 5 >= 5)
        self.assertTrue(sanitized["reroll"])
        self.assertFalse(sanitized["go_next"])

    def test_atomic_file_write_and_read(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            test_file = os.path.join(tmpdir, "test.json")
            payload = {"request_id": "atomic_123", "value": 42}
            bridge.write_json_atomic(test_file, payload)
            read_back = bridge.read_json_safe(test_file)
            self.assertEqual(read_back, payload)

if __name__ == "__main__":
    unittest.main()
