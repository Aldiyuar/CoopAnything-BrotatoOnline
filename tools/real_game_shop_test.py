import subprocess
import time
import os
import sys

GAME_EXE = r"D:\Brotato_Coop_Test\Brotato.exe"
LOG_FILE = r"D:\Brotato_Coop_Test\logs\coop_all.log"
SHOTS_DIR = r"D:\Brotato_Coop_Test\screenshots"

def run_real_game_shop_test():
    print("=" * 70)
    print(" BROTATO REAL-GAME MULTIPLAYER SHOP & UPGRADES VERIFICATION")
    print("=" * 70)
    
    # Clean previous log
    if os.path.exists(LOG_FILE):
        try:
            os.remove(LOG_FILE)
            print("[INIT] Reset coop_all.log")
        except Exception as e:
            print(f"[WARN] Could not remove log: {e}")
            
    # 1. Launch Host instance with --coop-host-shop
    print("\n[STEP 1] Launching real Host instance (--coop-host-shop)...")
    host_proc = subprocess.Popen(
        [GAME_EXE, "--windowed", "--coop-host-shop"],
        cwd=os.path.dirname(GAME_EXE)
    )
    print(f"         Host started with PID: {host_proc.pid}")
    
    # Allow host to initialize Godot and bind port 7777
    time.sleep(7)
    
    # 2. Launch Client instance with --coop-join-shop 127.0.0.1
    print("\n[STEP 2] Launching real Client instance (--coop-join-shop 127.0.0.1)...")
    client_proc = subprocess.Popen(
        [GAME_EXE, "--windowed", "--coop-join-shop", "127.0.0.1"],
        cwd=os.path.dirname(GAME_EXE)
    )
    print(f"         Client started with PID: {client_proc.pid}")
    
    # 3. Wait for handshake, shop transition, buy, reroll, ready and advance
    print("\n[STEP 3] Observing real game execution for 22 seconds (shop load + buy + reroll + ready)...")
    last_size = 0
    start_t = time.time()
    while time.time() - start_t < 22:
        time.sleep(2)
        if os.path.exists(LOG_FILE):
            with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                if len(content) > last_size:
                    new_text = content[last_size:]
                    last_size = len(content)
                    for line in new_text.strip().splitlines():
                        print("  [LIVE LOG] " + line)
                        
    # 4. Terminate game processes cleanly
    print("\n[STEP 4] Terminating game instances...")
    for p, name in [(host_proc, "Host"), (client_proc, "Client")]:
        try:
            p.terminate()
            p.wait(timeout=2)
        except Exception:
            subprocess.run(["taskkill", "/F", "/PID", str(p.pid)], capture_output=True)
            
    # 5. Check Captured Screenshots
    print("\n" + "=" * 70)
    print(" VERIFYING CAPTURED SHOP SCREENSHOTS")
    print("=" * 70)
    captured = []
    if os.path.exists(SHOTS_DIR):
        for f in os.listdir(SHOTS_DIR):
            if f.endswith(".png"):
                fp = os.path.join(SHOTS_DIR, f)
                sz = os.path.getsize(fp)
                captured.append((f, sz))
                print(f"  [SCREENSHOT] {f} ({sz} bytes)")
    
    # 6. Audit Unified Log
    print("\n" + "=" * 70)
    print(" AUDITING UNIFIED LOG FILE (coop_all.log)")
    print("=" * 70)
    if not os.path.exists(LOG_FILE):
        print(f"[FAIL] {LOG_FILE} was not found!")
        return False
        
    with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
        log_lines = f.readlines()
        
    print(f"Total log events recorded: {len(log_lines)}")
    errors = [l.strip() for l in log_lines if "[ERROR]" in l or "Parse Error" in l]
    warnings = [l.strip() for l in log_lines if "[WARN]" in l]
    
    if errors:
        print(f"\n[!] Detected {len(errors)} errors:")
        for err in errors:
            print("    " + err)
    else:
        print("\n[OK] ZERO ERRORS detected in unified log file!")
        
    # Check key milestones
    has_host = any("Hosting online game on port" in l for l in log_lines)
    has_peer = any("Peer connected" in l for l in log_lines)
    has_shop_loaded = any("CoopShop scene loaded successfully" in l for l in log_lines)
    has_host_buy = any("Host: Bought item in slot 0 for Player 0" in l for l in log_lines)
    has_client_buy = any("Executed BUY for player 1" in l or "Confirmed shop buy for player 1" in l for l in log_lines)
    has_client_reroll = any("Executed REROLL for player 1" in l or "Confirmed shop reroll for player 1" in l for l in log_lines)
    has_ready_advance = any("All players READY in shop" in l or "Advancing from shop to next wave" in l for l in log_lines)
    
    print("\nMilestones Verification:")
    print(f"  1. Server bound & Client connected:          {'[PASS]' if (has_host and has_peer) else '[FAIL]'}")
    print(f"  2. CoopShop scene loaded for both players:   {'[PASS]' if has_shop_loaded else '[FAIL]'}")
    print(f"  3. Host bought item (Container 1 local):     {'[PASS]' if has_host_buy else '[FAIL]'}")
    print(f"  4. Client bought item (RPC replicated):      {'[PASS]' if has_client_buy else '[FAIL]'}")
    print(f"  5. Client rerolled shop (RPC replicated):    {'[PASS]' if has_client_reroll else '[FAIL]'}")
    print(f"  6. Ready check passed & wave advanced:       {'[PASS]' if has_ready_advance else '[FAIL]'}")
    
    success = (len(errors) == 0) and has_host and has_peer and has_shop_loaded and has_host_buy and has_client_buy and has_client_reroll and has_ready_advance
    print(f"\n>>> OVERALL SHOP & UPGRADES VERIFICATION RESULT: {'SUCCESS' if success else 'FAILURE'} <<<")
    return success

if __name__ == "__main__":
    ok = run_real_game_shop_test()
    sys.exit(0 if ok else 1)
