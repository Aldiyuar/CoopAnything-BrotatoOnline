# Graph Report - bridge  (2026-10-21)

## Corpus Check
- 9 files · ~7,787 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 7 file(s) not represented in the graph (top: .gd 5, .log 1, .bat 1)

## Summary
- 95 nodes · 175 edges · 7 communities (5 shown, 2 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- main
- deepseek_shop_bridge.py
- МЕТОДОЛОГИЯ РАСЧЁТА СИНЕРГИЙ BROTATO (SYNERGY FRAMEWORK)
- manifest.json
- resolve_character_meta
- extract_json_from_response

## God Nodes (most connected - your core abstractions)
1. `resolve_character_meta()` - 13 edges
2. `main()` - 11 edges
3. `validate_and_sanitize_decision()` - 9 edges
4. `log_event()` - 7 edges
5. `write_json_atomic()` - 7 edges
6. `process_shop_request()` - 7 edges
7. `analyze_and_tag_shop_item()` - 7 edges
8. `TestBrotatoSynergyEngine` - 7 edges
9. `main()` - 6 edges
10. `read_json_safe()` - 6 edges

## Surprising Connections (you probably didn't know these)
- `format_prompt_for_deepseek()` --calls--> `analyze_and_tag_shop_item()`  [EXTRACTED]
  deepseek_shop_bridge.py → synergy_database.py
- `format_prompt_for_deepseek()` --calls--> `resolve_character_meta()`  [EXTRACTED]
  deepseek_shop_bridge.py → synergy_database.py
- `make_smart_decision()` --calls--> `analyze_and_tag_shop_item()`  [EXTRACTED]
  deepseek_shop_bridge.py → synergy_database.py
- `make_smart_decision()` --calls--> `resolve_character_meta()`  [EXTRACTED]
  deepseek_shop_bridge.py → synergy_database.py
- `format_prompt_for_upgrade()` --calls--> `evaluate_level_up_options()`  [EXTRACTED]
  deepseek_shop_bridge.py → synergy_database.py

## Import Cycles
- None detected.

## Communities (7 total, 2 thin omitted)

### Community 0 - "main"
Cohesion: 0.21
Nodes (8): format_shop_summary(), main(), make_smart_decision(), notify_neural_network(), is_brotato_running(), main(), read_json_safe(), write_json_atomic()

### Community 1 - "deepseek_shop_bridge.py"
Cohesion: 0.27
Nodes (8): consult_deepseek(), extract_json_from_response(), format_prompt_for_deepseek(), format_prompt_for_upgrade(), log_event(), process_crate_request(), process_shop_request(), process_upgrade_request()

### Community 2 - "МЕТОДОЛОГИЯ РАСЧЁТА СИНЕРГИЙ BROTATO (SYNERGY FRAMEWORK)"
Cohesion: 0.14
Nodes (13): 1. Фундаментальная формула урона Brotato, 2. Математический анализ персонажа: «Мастер на все руки» (Multitasker), 3. Математическое доказательство безальтернативности «Палки» (The Stick Monopoly), 4. Классификация предметов магазина для «Мастера на все руки», 5. Как рассчитывать синергии для новых персонажей (Памятка на будущее), Анализ дебаффа и математическая ловушка:, Группа 1: CORE ITEMS (Брать всегда и в первую очередь), Группа 2: СИНЕРГИЧНЫЕ СТАТЫ (Полезные предметы) (+5 more)

### Community 3 - "manifest.json"
Cohesion: 0.17
Nodes (11): dependencies, description, extra, godot, authors, compatible_game_version, compatible_mod_loader_version, name (+3 more)

### Community 5 - "resolve_character_meta"
Cohesion: 0.16
Nodes (7): validate_and_sanitize_decision(), analyze_and_tag_shop_item(), evaluate_crate_item(), evaluate_level_up_options(), resolve_character_meta(), TestLevelUpUpgrades, TestBrotatoSynergyEngine

## Knowledge Gaps
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `validate_and_sanitize_decision()` connect `resolve_character_meta` to `deepseek_shop_bridge.py`, `extract_json_from_response`?**
  _High betweenness centrality (0.073) - this node is a cross-community bridge._
- **Should `МЕТОДОЛОГИЯ РАСЧЁТА СИНЕРГИЙ BROTATO (SYNERGY FRAMEWORK)` be split into smaller, more focused modules?**
  _Cohesion score 0.14285714285714285 - nodes in this community are weakly interconnected._
- **Why does `resolve_character_meta()` connect `resolve_character_meta` to `deepseek_shop_bridge.py`, `extract_json_from_response`?**
  _High betweenness centrality (0.067) - this node is a cross-community bridge._
- **Why does `make_smart_decision()` connect `extract_json_from_response` to `deepseek_shop_bridge.py`, `resolve_character_meta`?**
  _High betweenness centrality (0.035) - this node is a cross-community bridge._