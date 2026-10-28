import subprocess
import time
import os
import sys

GAME_EXE = r"D:\Brotato_Coop_Test\Brotato.exe"
LOG_FILE = r"D:\Brotato_Coop_Test\logs\coop_all.log"

def run_live_test_and_monitor(duration_sec=16):
    print("=" * 60)
    print(" BROTATO CO-OP LIVE TEST & REAL-TIME ERROR MONITOR")
    print("=" * 60)
    
    # Ensure logs folder exists and clean previous log
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    if os.path.exists(LOG_FILE):
        try:
            os.remove(LOG_FILE)
            print(f"[INIT] Reset clean log file: {LOG_FILE}")
        except Exception as e:
            print(f"[WARN] Could not reset log file: {e}")
            
    # Launch Host
    print("\n[HOST] Launching Host instance (Port 7777)...")
    host_proc = subprocess.Popen(
        [GAME_EXE, "--windowed", "--coop-host"],
        cwd=os.path.dirname(GAME_EXE)
    )
    print(f"       Host started with PID: {host_proc.pid}")
    
    time.sleep(5) # Allow host to initialize Godot and bind port
    
    # Launch Client
    print("\n[CLIENT] Launching Client instance (Connecting to 127.0.0.1:7777)...")
    client_proc = subprocess.Popen(
        [GAME_EXE, "--windowed", "--coop-join", "127.0.0.1"],
        cwd=os.path.dirname(GAME_EXE)
    )
    print(f"         Client started with PID: {client_proc.pid}")
    
    print(f"\n[MONITOR] Monitoring session logs for {duration_sec} seconds...")
    start_time = time.time()
    last_pos = 0
    
    while time.time() - start_time < duration_sec:
        time.sleep(1)
        if os.path.exists(LOG_FILE):
            with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
                f.seek(last_pos)
                new_data = f.read()
                last_pos = f.tell()
                if new_data:
                    for line in new_data.strip().splitlines():
                        print(f"  -> {line}")
                        
    # Graceful shutdown
    print("\n[SHUTDOWN] Terminating test instances...")
    for p, name in [(host_proc, "Host"), (client_proc, "Client")]:
        try:
            p.terminate()
            p.wait(timeout=2)
        except Exception:
            subprocess.run(["taskkill", "/F", "/PID", str(p.pid)], capture_output=True)
            
    print("\n" + "=" * 60)
    print(" POST-TEST LOG & ERROR AUDIT")
    print("=" * 60)
    
    if not os.path.exists(LOG_FILE):
        print(f"[ERROR] Dedicated log file {LOG_FILE} was not created!")
        return False
        
    with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
        log_lines = f.readlines()
        
    print(f"Total log events recorded: {len(log_lines)}")
    
    errors = [l.strip() for l in log_lines if "[ERROR]" in l or "Parse Error" in l or "Failed" in l]
    warnings = [l.strip() for l in log_lines if "[WARN]" in l]
    
    if errors:
        print(f"\n[!] ERRORS DETECTED ({len(errors)}):")
        for err in errors:
            print(f"    {err}")
    else:
        print("\n[OK] Zero errors detected in log file!")
        
    if warnings:
        print(f"\n[i] WARNINGS ({len(warnings)}):")
        for w in warnings:
            print(f"    {w}")
    else:
        print("[OK] Zero warnings detected in log file!")
        
    # Check key lifecycle events
    has_host = any("Hosting online game on port" in l for l in log_lines)
    has_peer = any("Peer connected" in l for l in log_lines)
    has_virt_dev = any("Adding network player 1 (virtual device 101)" in l for l in log_lines)
    has_input = any("Received remote input from player 1" in l for l in log_lines)
    
    print("\nLifecycle Status:")
    print(f"  - Server bound & listening:            {'PASS' if has_host else 'FAIL'}")
    print(f"  - Client connected:                    {'PASS' if has_peer else 'FAIL'}")
    print(f"  - Virtual device 101 injected:         {'PASS' if has_virt_dev else 'FAIL'}")
    print(f"  - Remote inputs actively replicated:   {'PASS' if has_input else 'FAIL'}")
    
    success = (len(errors) == 0) and has_host and has_peer and has_virt_dev and has_input
    print(f"\nOverall Audit Result: {'SUCCESS' if success else 'FAILURE'}")
    return success

if __name__ == "__main__":
    dur = 16
    if len(sys.argv) > 1:
        dur = int(sys.argv[1])
    ok = run_live_test_and_monitor(dur)
    sys.exit(0 if ok else 1)
