"""
Unit test for Level Up upgrade flow
"""

import sys
import unittest

sys.path.insert(0, r"D:\Brotato\bridge")

import synergy_database as syn
import deepseek_shop_bridge as bridge

class TestLevelUpUpgrades(unittest.TestCase):

    def test_level_up_recommends_reroll_when_all_trash(self):
        # Ровно ситуация со скриншота пользователя:
        # Плечи (+1 дальний), Нос (+5 удача), Спина (+3% уклонения), Мозг (+1 стихийный)
        # Золото: 58, реролл: 1
        data = {
            "request_id": "upg_test_screenshot",
            "character": {"name": "Мастер на все руки", "id": "character_multitasker"},
            "level": 2,
            "gold": 58,
            "reroll_price": 1,
            "wave": 1,
            "options": [
                {"slot": 0, "name": "Плечи", "effects": ["+1 Урон в дальнем бою"]},
                {"slot": 1, "name": "Нос", "effects": ["+5 Удача"]},
                {"slot": 2, "name": "Спина", "effects": ["+3 % уклонения"]},
                {"slot": 3, "name": "Мозг", "effects": ["+1 Стихийный урон"]}
            ]
        }
        meta = syn.resolve_character_meta(data)
        best_slot, best_score, verdict = syn.evaluate_level_up_options(
            data["options"], meta, data["gold"], data["reroll_price"], data["wave"]
        )
        # Лучший среди них — Нос (+5 удача, 40 очков)
        self.assertEqual(best_slot, 1)
        # Но очков меньше 60 (нет S-Tier статов), а реролл 1г при 58г -> должен быть реролл!
        self.assertIn("Математически выгоден реролл", verdict)

    def test_level_up_picks_melee_damage_immediately(self):
        # Если среди карточек есть Ближний бой
        data = {
            "request_id": "upg_test_melee",
            "character": {"name": "Мастер на все руки", "id": "character_multitasker"},
            "level": 3,
            "gold": 10,
            "reroll_price": 2,
            "wave": 2,
            "options": [
                {"slot": 0, "name": "Плечи", "effects": ["+1 Урон в дальнем бою"]},
                {"slot": 1, "name": "Кулак", "effects": ["+1 Урон в ближнем бою"]},
                {"slot": 2, "name": "Спина", "effects": ["+3 % уклонения"]},
                {"slot": 3, "name": "Мозг", "effects": ["+1 Стихийный урон"]}
            ]
        }
        meta = syn.resolve_character_meta(data)
        best_slot, best_score, verdict = syn.evaluate_level_up_options(
            data["options"], meta, data["gold"], data["reroll_price"], data["wave"]
        )
        self.assertEqual(best_slot, 1)
        self.assertGreaterEqual(best_score, 100) # S-Tier стат!

if __name__ == "__main__":
    unittest.main()
