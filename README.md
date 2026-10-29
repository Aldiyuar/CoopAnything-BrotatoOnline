# CoopAnything-BrotatoOnline

[![Game](https://img.shields.io/badge/Brotato-v1.1.15.1%20%2B%20DLC-orange)](https://store.steampowered.com/app/1942280/Brotato/)
[![Engine](https://img.shields.io/badge/Godot-3.5.x-blue)](https://godotengine.org/)
[![ModLoader](https://img.shields.io/badge/GodotModLoader-6.3.0-green)](https://github.com/GodotModLoader/godot-mod-loader)
[![QA](https://img.shields.io/badge/QA%20Tests-PASS%20(0%20errors)-brightgreen)](tools/)

**CoopAnything-BrotatoOnline** turns the local same-PC co-op of **Brotato** into full online network multiplayer based on Godot's native `NetworkedMultiplayerENet` UDP stack (Host-authoritative model).

---

## Features

- **Host-Authoritative Networking & Combat:**
  - Fast UDP connection on port `7777` with zero third-party external dependencies.
  - Host authoritatively controls wave timing, enemy spawns, combat calculations, loot generation, and shop progression.
  - **No Double-Damage:** All player weapons are simulated authoritatively on the Host, eliminating double-damage bugs while keeping responsive local visual feedback on clients.
- **20 Hz Player Position & State Sync:**
  - Smooth interpolation for remote puppet characters with automatic drift reconciliation.
  - Real-time client input replication (`rpc_send_player_input`).
- **Player Death Replication & Spectator Support:**
  - Individual player deaths are broadcast via `rpc_player_died`, instantly disabling movement input and hiding collision/weapons.
  - In the event of a team wipe, the Retry/End Run window (`retry_wave.gd`) synchronizes scene transitions across all clients to `coop_end_run.tscn`.
- **Shared Enemies & World Spawns:**
  - All players fight the exact same enemies and trees at identical coordinates.
  - Rogue local client wave spawning is cleanly decoupled.
- **Synchronized Ground Loot & Currency:**
  - Materials/gold and consumables (crates, healing fruits) drop in identical locations on all screens.
  - **First-Come, First-Served:** Any player who walks over an item claims it; the item is immediately removed on all peers.
  - Gold balance and player levels are synchronized in real-time in the HUD.
- **Simultaneous Post-Wave Shop & Upgrades:**
  - Independent split-screen shopping from each player's personal bank account.
  - Simultaneous stat upgrade selection upon leveling up.
  - Crate opening with take/recycle options for the player who collected the crate.
  - Atomic wave advance: next wave starts only after all players press "Ready".

---

## Project Structure

```
Brotato_Project/
├── mods-unpacked/
│   └── CoopAnything-BrotatoOnline/  # GDScript source code of the mod
│       ├── manifest.json
│       ├── mod_main.gd
│       ├── global/
│       │   ├── network_manager.gd   # Core ENet server/client logic & RPCs
│       │   ├── network_logger.gd    # Unified logging
│       │   └── network_constants.gd # Ports, roles, packet definitions
│       ├── extensions/
│       │   ├── main.gd              # Arena, enemies, combat & ground loot hooks
│       │   ├── singletons/          # CoopService virtual device mapping (100+)
│       │   ├── entities/            # PlayerMovementBehavior network input & death lock
│       │   └── ui/                  # Split CoopShop, UpgradesUI, RetryWave & Pause hooks
│       └── ui/
│           └── online_dialog.gd     # In-game host/join GUI dialog
├── tools/                           # Automated multi-process QA suites
│   ├── build_mod.py                 # Zip packager and deployment script
│   ├── real_game_arena_test.py      # 2-process arena combat verification
│   ├── real_game_death_test.py      # 2-process death, wipe & GameOver verification
│   ├── real_game_postwave_test.py   # 2-process shop & crates verification
│   └── build_full_graph.py          # Graphify AST knowledge graph generator
├── graphify-out/                    # Architecture knowledge graph (AST)
├── MODLOG.md                        # Verified engineering change log
├── PROMPT_FOR_AI_TESTER.md          # Comprehensive AI developer prompt
└── PROMPT_FOR_EXTERNAL_AI_REVIEW.md # Prompt for external AI audit & review
```

---

## How to Build & Test

### 1. Build and Deploy
```powershell
python tools/build_mod.py "path/to/Brotato_Game_Folder"
```
This packages `mods-unpacked/CoopAnything-BrotatoOnline/` into `CoopAnything-BrotatoOnline.zip` inside the game's `mods/` directory.

### 2. Run Automated QA Tests
The project includes automated end-to-end tests that spawn two visible game instances side-by-side (`WinSta0\Default`):
- **Arena Combat Test (movement, shared enemies, ground loot):**
  ```powershell
  python tools/real_game_arena_test.py
  ```
- **Player Death & GameOver Test (spectator, team wipe, end run sync):**
  ```powershell
  python tools/real_game_death_test.py
  ```
- **Post-Wave Test (crates, upgrades, shop purchases, wave 2 transition):**
  ```powershell
  python tools/real_game_postwave_test.py
  ```

---

## How to Play

### Host:
1. Launch Brotato with the mod installed.
2. In the Main Menu, click **Online Co-op** -> **Host Game** (Port `7777` by default).
3. Wait for your friend to connect, then choose characters and start!

### Client:
1. Launch Brotato with the mod installed.
2. Click **Online Co-op** -> **Join Game**.
3. Enter the Host's IP address (LAN IP, Radmin VPN, Hamachi, or public IP / Playit.gg) and Port `7777`.
4. Click **Connect**.

---

## Credits

- **Aldiyuar** — Project Creator & Lead Developer
- **Brotato Team (Blobfish)** — Original Game
- **GodotModLoader Community** — Mod Loader framework
- **coop-anything** — Co-op Architecture & QA Playbooks

---

## License

This mod is distributed under the MIT License. Game code and assets belong to Blobfish.
