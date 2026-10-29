# CoopAnything-BrotatoOnline: Mod Engineering Log

## 1. Спецификация игры и движка
- **Игра:** Brotato (v1.1.15.1) + DLC Abyssal Terrors
- **Движок:** Godot Engine (v3.5.x, custom build, Pack format 1)
- **Загрузчик модов:** GodotModLoader v6.3.0 (встроен в Brotato)
- **Идентификатор мода:** `CoopAnything-BrotatoOnline` (v1.0.0)
- **Сетевой транспорт:** `NetworkedMultiplayerENet` (UDP, порт 7777)
- **Сетевая модель:** Host-authoritative (Хост — абсолютный источник истины)

---

## 2. Архитектура и реализованные сетевые подсистемы (100% Verified)

### 2.1 Подключение и виртуальные контроллеры
- Хост открывает ENet-сервер на порту `7777`.
- Клиенты подключаются по IP и получают назначенный слот игрока (`my_player_index`).
- В нативном `CoopService` удаленные игроки регистрируются как виртуальные устройства `100 + player_index`. Игра обрабатывает их как полноценных участников локального кооператива без вылетов `FocusEmulator`.
- Сохранения Клиента изолированы в папку `user://GOG-Saves-Client`, что исключает конфликты и порчу сохранений Хоста.

### 2.2 Синхронизация игроков (20 Hz)
- **Ввод Клиента:** передается Хосту через `rpc_unreliable_id(1, "rpc_send_player_input", ...)`.
- **Авторитетные координаты:** Хост с частотой 20 Hz рассылает точные мировые координаты и текущее HP всех персонажей через `rpc_sync_player_positions`.
- **Интерполяция:** Клиент плавно интерполирует куклу Хоста (при расхождении > 150 px — мгновенная коррекция), исключая рассинхрон физики и столкновений.

### 2.3 Общие враги и боевая система (Host-Authoritative Combat)
- На стороне Клиента отключен локальный спавнер `WaveManager`, исключая появление «фантомных» мобов.
- Хост централизованно спавнит врагов и деревья через `rpc_spawn_network_enemy` и `rpc_spawn_network_neutral`.
- Координаты и здоровье мобов синхронизируются пачками с частотой 20 Hz (`rpc_sync_enemy_batch`).
- **Устранение двойного урона (Double Damage Fix):** оружие обоих игроков физически симулируется на Хосте (включая виртуальную куклу Клиента). Клиент локально воспроизводит визуал попаданий для мгновенного отклика (flash, звуки, floating text), но **не отправляет дублирующий урон по RPC на Хост**. Это исключает 200–300% мультипликацию урона и гарантирует канонический баланс здоровья врагов.

### 2.4 Наземный лут: валюта и расходники (First-Come, First-Served)
- Клиенту запрещено создавать локальный дроп (`spawn_gold`, `spawn_consumables`).
- Весь лут создается на Хосте с фиксацией точной точки приземления (`push_back_destination`) и сетевого `item_id`:
  - Золото/материалы: `rpc_spawn_ground_gold`.
  - Расходники (ящики с предметами, плоды лечения): `rpc_spawn_ground_consumable`.
- **Подбор:** кто первый касается предмета, тот его и забирает:
  - Хост подбирает локально -> зачисляет себе -> рассылает `rpc_remove_ground_item`.
  - Клиент касается предмета -> скрывает локально -> шлет `rpc_request_item_pickup` -> Хост валидирует, начисляет валюту/лечение/сундук Клиенту и рассылает подтверждение удаления.
  - Баланс золота и уровни игроков непрерывно синхронизируются через `rpc_sync_all_players_gold_and_xp`.

### 2.5 Межволновая фаза (Сундуки, Характеристики, Магазин)
- **Сундуки:** при взятии ящика на Хосте или Клиенте он сохраняется в `_consumables_to_process` того, кто его взял. На экране лута карточки открываются обоими игроками одновременно (`rpc_request_crate_take` / `rpc_request_crate_discard`).
- **Повышение уровня:** при левелапе Хост рассылает `rpc_player_levelled_up`. Экран `CoopUpgradesUI` дает каждому игроку выбрать улучшение (`rpc_request_upgrade`).
- **Сплит-магазин (`CoopShop`):** оба игрока одновременно закупаются в магазине со своего баланса (`rpc_request_shop_buy`), рероллят (`rpc_request_shop_reroll`) и жмут кнопку «Готов» (`rpc_notify_shop_ready`).
- **Переход к следующей волне:** происходит строго атомарно только после готовности всех подключенных игроков (`rpc_all_ready_advance_wave`).

---

### 2.5. Устранение двойного урона по врагам (Шаг 1 аудита)
- **Проблема**: Клиент при локальных расчетах коллизий вызывал `_on_enemy_took_damage` и отсылал на Хост `rpc_client_dealt_damage`, в то время как Хост уже авторитетно наносил урон через куклу Клиента `_players[1]`. Это приводило к удвоению урона и моментальному уничтожению элиты и боссов.
- **Решение**:
  - В `extensions/main.gd`: удален вызов `net.rpc_id(1, "rpc_client_dealt_damage", ...)` из `_on_enemy_took_damage`. Урон по врагам теперь рассчитывается **строго на Хосте** (`Host-authoritative`).
  - В `global/network_manager.gd`: метод `rpc_client_dealt_damage` заменен на deprecation no-op заглушку.
- **Верификация**: `real_game_arena_test.py` — 0 ошибок, 100% PASS.

### 2.6. Репликация смерти игроков, спектэйтор и GameOver (Шаг 2 аудита)
- **Проблема**:
  1. При смерти Клиента на Хосте позиция переставала отправляться (выпадал из батча `p_batch`), из-за чего на Клиенте кукла зависала на последней координате или продолжала получать сетевой инпут.
  2. При смерти всех игроков экран завершения забега (`_retry_wave` -> `coop_end_run.tscn`) переключался только локально на Хосте без синхронизации на Клиентах.
- **Решение**:
  - В `extensions/main.gd`:
    - В `_physics_process`: `p_batch` теперь гарантированно включает мертвых игроков со статусом `cur_hp = 0` и флагом `dead_flag = 1`.
    - Добавлен перехват `_on_player_died(p_player, args)`: Хост надежно транслирует `rpc_player_died(player_index)`.
  - В `global/network_manager.gd`:
    - Добавлен RPC `remotesync func rpc_player_died(player_index: int)`: клиент вызывает `p.die()`, скрывает оружие, коллизии и хитбокс.
    - В `rpc_sync_player_positions`: при флаге `dead_flag == 1` или `hp <= 0` кукла на клиенте переводится в состояние смерти `p.current_stats.health = 0; p.die()`.
  - В `extensions/entities/units/movement_behaviors/player_movement_behavior.gd`:
    - Если игрок мертв (`_parent.dead`), поведение движения немедленно возвращает `Vector2.ZERO`, отключая сетевой и локальный ввод.
  - В `extensions/ui/menus/ingame/retry_wave.gd`:
    - Создано расширение скрипта для окна повтора/завершения волны. При нажатии кнопок выбора и смене сцены (`_change_scene`) Хост транслирует `rpc_sync_change_scene(path)`.
  - В `mod_main.gd`: установлена регистрация расширения `retry_wave.gd`.
  - В `tools/real_game_death_test.py`:
    - Создан полноценный автотест реальных процессов: наносит летальный урон Клиенту на 5с, Хосту на 11с, на 14.5с симулирует отказ от повтора и проверяет загрузку `coop_end_run.tscn`.
- **Защита загрузчика ресурсов (No loader found: res://)**:
  - Ресурсы дропа `ConsumableData` в Brotato дублируются через `.duplicate()`, что очищает их внутренний `resource_path` в пустую строку.
  - Добавлен резолвер `_get_consumable_res_path` по `my_id` (`consumable_item_box`, `consumable_fruit`, `consumable_legendary_item_box`), а также валидация путей в `rpc_sync_change_scene`, `rpc_spawn_ground_consumable` и `rpc_player_received_crate`.
- **Верификация**:
  - `real_game_death_test.py`: 9/9 майлстоунов PASS, 0 ошибок.
  - `real_game_postwave_test.py`: 7/7 майлстоунов PASS, 0 ошибок.
  - `real_game_arena_test.py`: 8/8 майлстоунов PASS, 0 ошибок.

### 2.7. Устранение скрытых блокеров магазина, сундуков и гонок лута (Аудит)
- **Проблемы**:
  1. Разрыв контракта витрины магазина: `rpc_confirm_shop_reroll` вызывался с 4 аргументами вместо 2, отсутствовали методы сериализации `_serialize_shop_items`, `_deserialize_shop_items` и RPC `rpc_sync_initial_shop_items`.
  2. Двойная выдача лута из сундуков на Хосте: ручной `RunData.add_item` перед `container._on_TakeButton_pressed()` удваивал предметы у Хоста.
  3. Ошибка парсера и преждевременное закрытие `UpgradesUI` на Клиенте: несуществующий идентификатор `_things_to_process_player_containers` вызывал SCRIPT ERROR, а локальный вызов `options_processed` менял сцену раньше Хоста.
  4. Асинхронный `yield(..., "ready")` при спавне дропа: удаление монеты Хостом во время `yield` на Клиенте приводило к фантомным неудаляемым монетам.
  5. Локальная гибель мобов на Клиенте от визуального урона пуль до подтверждения Хостом.
  6. Спам в `coop_all.log` 60 раз в секунду из `rpc_send_player_input`.
- **Решение**:
  - В `global/network_manager.gd`:
    - Реализованы `_serialize_shop_items`, `_deserialize_shop_items` и `remotesync func rpc_sync_initial_shop_items`.
    - `rpc_confirm_shop_reroll` расширен до 4 аргументов с десериализацией и обновлением карточек витрины Клиента.
    - Убран лишний `RunData.add_item` в `rpc_request_crate_take` и в тестовом шаге 1.
    - В `rpc_spawn_ground_gold` и `rpc_spawn_ground_consumable` нода регистрируется в `ground_items` до `yield`, а после `yield` проверяется валидность.
    - В `close_session()` добавлена очистка `network_enemies.clear()`.
    - Логирование инпута в `rpc_send_player_input` ограничено событием перехода из покоя.
  - В `extensions/ui/menus/ingame/upgrades_ui.gd`:
    - Ошибка `_things_to_process_player_containers` устранена, контейнер берется через `_get_player_container`.
  - В `extensions/main.gd`:
    - Добавлен перехват `on_upgrades_options_processed`: Клиент блокирует локальный переход и ожидает сетевой смены сцены от Хоста.
    - В `_on_enemy_took_damage` на Клиенте здоровье моба удерживается `>= 1` до подтверждения гибели Хостом (`host_killed`).
    - На Клиенте в `on_gold_picked_up` и `on_consumable_picked_up` добавлен `net.ground_items.erase(item_id)`.
    - В `_physics_process` Клиента подавляется локальная очередь призывов `_entity_spawner.queue_to_spawn_summons`.
    - В `_ready()` добавлена очистка `net.ground_items.clear()`.
- **Верификация**:
  - `real_game_postwave_test.py`: 7/7 майлстоунов PASS, 0 ошибок.
  - `real_game_arena_test.py`: 8/8 майлстоунов PASS, 0 ошибок.
  - `real_game_death_test.py`: 9/9 майлстоунов PASS, 0 ошибок.

### 2.8. Устранение рассинхронизации позиций (Rubberbanding), интерполяция 60 FPS и защита фаз волны
- **Устранение Rubberbanding (рывки при задержке сети):**
  - В `network_manager.gd::rpc_send_player_input`: на Хосте увеличен порог коррекции физического ввода с `80.0` до `150.0 / 300.0`. Хост полностью доверяет своей авторитетной физической симуляции ввода, не стягивая марионетку игрока к устаревшим координатам Клиента.
  - В `network_manager.gd::rpc_sync_player_positions`: для локального игрока Клиента (`my_player_index`) порог коррекции поднят с `60.0` до `180.0 / 350.0`. При штатном пинге локальное предсказание не дергает персонажа назад, коррекция наступает только при реальном расхождении.
- **Плавная покадровая 60 FPS интерполяция для удаленных сущностей:**
  - В `network_manager.gd`: пакеты позиций мобов и игроков (`rpc_sync_enemy_batch`, `rpc_sync_player_positions`) теперь сохраняют целевую точку `net_target_pos` у сущностей и делают жесткий телепорт только при скачке `dist > 250.0`.
  - В `extensions/main.gd`: в `_physics_process(delta)` на Клиенте каждый физический кадр (60 раз в секунду) выполняется `linear_interpolate(target, clamp(delta * 16.0, 0.0, 1.0))` для удаленного игрока, сетевых врагов и деревьев, устраняя дискретность 20 Hz пакетов.
- **Защита межволнового перехода (`_cleaning_up`):**
  - В `extensions/main.gd`: добавлена проверка `_cleaning_up` в `_network_register_enemy`, `_network_register_neutral`, `_on_EntitySpawner_enemy_spawned`, `_on_EntitySpawner_neutral_spawned`, `spawn_gold` и `spawn_consumables`. Исключены паразитные регистрации и спавны во время очистки комнаты.
  - При смерти мобов во время очистки (`_cleaning_up = true`) Хост не шлет индивидуальные `rpc_enemy_died`, так как обе стороны очищают списки централизованно.
  - На Клиенте в `_physics_process` очищается очередь `queue_to_spawn_trees`.
  - В `network_manager.gd::rpc_sync_change_scene`: добавлена очистка словарей `network_enemies.clear()` и `ground_items.clear()` при смене сцен.
- **Результаты верификации (2 реальных процесса):**
  - `real_game_arena_test.py`: 8/8 майлстоунов PASS, 0 ошибок.
  - `real_game_postwave_test.py`: 7/7 майлстоунов PASS, 0 ошибок.
  - `real_game_death_test.py`: 9/9 майлстоунов PASS, 0 ошибок.

### 2.9. Устранение гонок состояний магазина, ящиков, дропа и устойчивость к дисконнектам
- **Проблемы**:
  1. Покупки Хоста (игрок 0) в магазине не рассылались Клиенту через RPC, из-за чего на Клиенте не списывалось золото Хоста, не закрывалась карточка товара и купленный предмет/оружие отсутствовали в `RunData.players_data[0]`.
  2. В `coop_shop.gd` кнопка `reroll_btn` дублировала подключение `_on_client_reroll_pressed()`, вызывая двойной RPC-запрос на Хост за один клик.
  3. В `upgrades_ui.gd` при живом клике игрока выбор карточки происходил локально, а пришедший ответ `rpc_confirm_upgrade` / `rpc_confirm_crate_take` повторно нажимал кнопку, прокликивая следующий апгрейд.
  4. На Клиенте кукла Хоста могла коснуться монеты, вызывая отправку `rpc_request_item_pickup` с `player_index = 0`.
  5. В `spawn_gold` и `spawn_consumables` отсутствовала проверка `_cleaning_up` после корутины `yield(..., "ready")`.
  6. На Клиенте в `_physics_process` очереди `queue_to_spawn` и `queue_to_spawn_bosses` не очищались, создавая риск фантомных миньонов от AI боссов/элиток.
  7. При дисконнекте Клиента игра на Хосте зависала в магазине или `UpgradesUI` из-за ожидания готовности отключенного игрока.
- **Решение**:
  - В `extensions/ui/menus/shop/coop_shop.gd`:
    - Перехвачен `on_shop_item_bought`: покупки Хоста автоматически рассылают `rpc_confirm_shop_buy`.
    - Убран дублирующий коннект на `reroll_btn` в `_setup_coop_shop_network()`.
    - Добавлен флаг `_reroll_pending` для блокировки спама реролла.
  - В `global/network_manager.gd`:
    - Добавлен хелпер `get_resource_path(res)` для надежного резолвинга путей дублированных ресурсов.
    - В `rpc_confirm_shop_buy`: на Клиенте купленный Хостом предмет/оружие добавляется в `RunData.players_data[0]` через `add_weapon` / `add_item`.
    - В `rpc_confirm_upgrade` и `rpc_confirm_crate_take`: добавлена проверка `_upgrade_choice_pending` / `_crate_choice_pending`, исключающая двойной клик карточек.
    - В `_on_peer_disconnected` добавлены `_handle_disconnected_player` и `is_player_slot_active`, чтобы кукла отключившегося пира переводилась в `die()`, очереди `UpgradesUI` сбрасывались, а готовность магазина проверялась только по оставшимся активным слотам.
    - В `_on_server_disconnected` на Клиенте добавлен автоматический возврат в главное меню (`title_screen_scene`).
  - В `extensions/main.gd`:
    - В `on_gold_picked_up` и `on_consumable_picked_up` на Клиенте добавлена проверка `player_index == net.my_player_index`.
    - Добавлена проверка `_cleaning_up` после `yield(..., "ready")` в `spawn_gold` и `spawn_consumables`.
    - Добавлен сброс `scale = Vector2.ONE`, `boosted = 0`, `value = Gold.INITIAL_VALUE` при взятии монеты из пула.
    - В `_physics_process` Клиента очищаются `queue_to_spawn` и `queue_to_spawn_bosses`.
  - В `extensions/entities/units/movement_behaviors/player_movement_behavior.gd`:
    - При гибели игрока гарантированно однократно отправляется нулевой вектор `(0, 0)` для сброса залипшего ввода.
- **Результаты верификации (2 реальных процесса на видимом рабочем столе):**
  - `real_game_arena_test.py`: 8/8 майлстоунов PASS, 0 ошибок.
  - `real_game_death_test.py`: 9/9 майлстоунов PASS, 0 ошибок.
  - `real_game_postwave_test.py`: 7/7 майлстоунов PASS, 0 ошибок.
  - Визуальная верификация: скриншоты подтвердили корректное разделение экрана, синхронизацию витрины магазина, открытие сундуков и переход на волну 2.

---

## 3. Статус автоматических тестов (Real Game Testing)

Все тесты запускаются на двух реальных окнах игры на физическом рабочем столе (`WinSta0\Default`) в режиме разделенного экрана (слева Хост `950x1000`, справа Клиент `950x1000`):

| Сценарий | Скрипт запуска | Проверяемые майлстоуны | Статус | Логи |
|---|---|---|---|---|
| **Бой на арене** | `python tools/real_game_arena_test.py` | 8/8 майлстоунов: ENet, подключение, спавн общих мобов, синхронное перемещение обоих игроков, лут, подбор, валюта | **PASS** | 0 [ERROR] |
| **Смерть и GameOver** | `python tools/real_game_death_test.py` | 9/9 майлстоунов: смерть P1, спектэйтор, смерть P0 (вайп), показ `_retry_wave`, синхронный переход в `coop_end_run.tscn` | **PASS** | 0 [ERROR] |
| **Послеволновая фаза** | `python tools/real_game_postwave_test.py` | 7/7 майлстоунов: открытие сундуков, выбор характеристик, закупка в магазине, реролл, переход на волну 2 | **PASS** | 0 [ERROR] |

---

## 4. Карта исходных файлов мода

Все исходники расположены в: `D:\Brotato_Project\mods-unpacked\CoopAnything-BrotatoOnline\`
- `manifest.json` — манифест мода (версия 1.0.0, зависимости ModLoader).
- `mod_main.gd` — инициализация мода, автозагрузка синглтона `NetworkManager`, регистрация виртуальных устройств.
- `global/network_constants.gd` — константы портов, сетевых ролей и сигналов.
- `global/network_logger.gd` — логирование с форматированием, PID и выводом в `coop_all.log`.
- `global/network_manager.gd` — ядро сетевого стека: сервер ENet, клиент ENet, RPC, CLI-автоматизация тестов.
- `extensions/main.gd` — хук главной игровой сцены: синхронизация мобов, снарядов, наземного лута и фаз волны.
- `extensions/entities/units/movement_behaviors/player_movement_behavior.gd` — чтение сетевого ввода и передача позиций.
- `extensions/singletons/coop_service.gd` — поддержка сетевых устройств `100+` в нативном локальном кооперативе.
- `extensions/ui/menus/ingame/pause_menu.gd` — подавление паузы при потере фокуса окна в онлайне.
- `extensions/ui/menus/ingame/retry_wave.gd` — синхронизация переключения экрана GameOver (`coop_end_run.tscn`) при завершении забега.
- `extensions/ui/menus/ingame/upgrades_ui.gd` — сетевая синхронизация сундуков и выбора статов.
- `extensions/ui/menus/shop/coop_shop.gd` — сетевой сплит-магазин с независимыми покупками, синхронизацией заморозки (Lock) и общей кнопкой готовности.
- `extensions/ui/menus/pages/main_menu.gd` — кнопка быстрого сетевого лобби в главном меню.
- `ui/online_dialog.gd` — графический диалог создания / подключения к онлайн-лобби по IP.

---

## 5. Оптимизации и архитектурные улучшения сетевого протокола (29-30 Октября 2026)

### 5.1 Строгий фокус на 2 игрока (Хост + Клиент)
- В `PROMPT_ONBOARDING_DEVELOPER.md` и `MOD_ARCHITECTURE.md` зафиксировано незыблемое архитектурное правило: проект разрабатывается и оптимизируется строго для кооператива на 2 игрока (Хост = игрок 0, Клиент = игрок 1). Рефакторинги на 3–4 игроков запрещены, чтобы не усложнять и не дестабилизировать проверенный сетевой стек.

### 5.2 Плоская сериализация мобов (Flat PoolIntArray Batching)
- В `extensions/main.gd` и `global/network_manager.gd` реализован метод `rpc_sync_enemy_batch_flat`:
  - 4 целых числа на моба: `[net_id, round(pos.x), round(pos.y), current_hp]`.
  - Отправка чанками максимум по 60 мобов (240 `int` = 960 байт полезной нагрузки) за пакет, что полностью укладывается в MTU (1400 байт) и предотвращает фрагментацию UDP-пакетов ENet при 100+ врагах на поздних волнах.

### 5.3 Монотонные порядковые номера сетевого ввода (Monotonic Input Seq)
- В `player_movement_behavior.gd` и `network_manager.gd` добавлено поле `client_input_seq`:
  - Клиент передает монотонно возрастающий счетчик пакета ввода.
  - Хост отбрасывает устаревшие (`seq <= last_processed_input_seq`) пакеты ввода, пришедшие не по порядку из-за сетевого джиттера UDP, предотвращая рывки и микро-телепорты.

### 5.4 Синхронизация заморозки предметов в магазине (Shop Item Lock)
- В `coop_shop.gd` и `network_manager.gd` добавлены методы:
  - `rpc_request_shop_lock(item_index, is_locked)` — Клиент запрашивает заморозку предмета в своем слоте.
  - `rpc_sync_shop_lock(player_index, item_index, is_locked)` — Хост валидирует запрос и реплицирует состояние блокировки обоим участникам.

### 5.5 Эмпирическая верификация
- Полный прогон всех 3 реальных тестов на физическом рабочем столе:
  - `real_game_arena_test.py`: **8/8 PASS, 0 [ERROR]**
  - `real_game_death_test.py`: **9/9 PASS, 0 [ERROR]**
  - `real_game_postwave_test.py`: **7/7 PASS, 0 [ERROR]**
- Визуальная инспекция скриншотов подтвердила безупречный рендеринг и синхронизацию.
