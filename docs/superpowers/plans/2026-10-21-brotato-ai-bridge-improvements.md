# Brotato AI Autopilot Bridge: Архитектурные улучшения

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Повысить надёжность и отказоустойчивость AI-автопилота Brotato (DeepSeek v4.1 Flash Free) за счёт атомарного IPC, защиты от рассинхронизации через `request_id`, гибридного fallback на смарт-эвристику и устойчивого парсинга ответов.

**Architecture:** Двусторонний асинхронный протокол обмена файлами между Godot 3.5 (`shop.gd`) и Python-мостом (`deepseek_shop_bridge.py`) через атомарную перезапись `.tmp` -> `replace` с Correlation ID (`request_id`). Если вызов LLM через OpenCode CLI сбоит или истекает таймаут, вызывается локальный алгоритм синергий (`make_smart_decision`), предотвращая пропуск магазина.

**Tech Stack:** Python 3, Godot 3.5 GDScript, OpenCode CLI (DeepSeek v4.1 Flash Free), ZipFile, Graphify.

---

## Global Constraints
- **Без лимитов на рероллы:** По требованию пользователя, не ограничивать количество рероллов за волну — ИИ полностью распоряжается бюджетом.
- **Сохранение обратной совместимости:** Структура `shop_request.json` и `shop_decision.json` расширяется полем `request_id`, сохраняя все базовые поля (`wave`, `gold`, `actions`, `reroll`, `go_next`, `comment`).
- **Синхронизация графа:** После модификации файлов запустить `graphify update .` в папке `bridge`.

---

## Tasks

### Task 1: Декомпозиция и улучшение `deepseek_shop_bridge.py`
- [ ] Добавить функции атомарного чтения и записи (`read_json_atomic`, `write_json_atomic`).
- [ ] Реализовать устойчивый парсер `extract_json_from_response` (очистка `<think>`, markdown-блоков, поиск валидного объекта с ключом `actions`).
- [ ] Интегрировать алгоритм синергий `make_smart_decision()` из `ag_bridge.py` как аварийный Fallback-движок при любых сбоях LLM.
- [ ] Добавить поддержку `request_id` в промпт, валидатор и результирующий JSON.
- [ ] Сохранить свободу рероллов (только проверка фактического наличия золота на покупку и реролл).

### Task 2: Модульное тестирование логики Python-моста
- [ ] Создать тестовый скрипт `test_bridge_logic.py`, проверяющий:
  - Парсинг ответов модели с разным уровнем «замусоренности».
  - Атомарную запись и чтение файлов.
  - Срабатывание смарт-эвристики при ошибке вызова CLI.
  - Сохранение `request_id`.
- [ ] Запустить тест и подтвердить 100% прохождение проверок.

### Task 3: Обновление хука GDScript (`shop.gd`) в `Antigravity-UnlockAll.zip`
- [ ] Распаковать текущий `shop.gd`, внести улучшения:
  - Генерация уникального `request_id` при каждом экспорте.
  - Атомарная запись `shop_request.json` через временный файл `.tmp` и `Directory.rename()`.
  - Проверка соответствия `request_id` в `_apply_decision()`.
  - Улучшенная обработка ожидания при частичной готовности файла.
- [ ] Запаковать обновлённый `shop.gd` обратно в `D:\Brotato\mods\Antigravity-UnlockAll.zip`.
- [ ] Сохранить открытую копию скрипта в папку мода/моста для прозрачности.

### Task 4: Синхронизация графа кодовой базы
- [ ] Выполнить `graphify update .` в каталоге `D:\Brotato\bridge`.
- [ ] Проверить обновлённый отчёт `GRAPH_REPORT.md` и удостовериться в устранении архитектурных узких мест.
