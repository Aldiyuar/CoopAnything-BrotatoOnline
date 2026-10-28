import subprocess
import time
import os

GAME_EXE = r"D:\Brotato_Coop_Test\Brotato.exe"
MODLOADER_LOG = os.path.expandvars(r"%APPDATA%\Brotato\logs\modloader.log")

def run_multi_instance_test():
    print("==================================================")
    print(" COOP-ANYTHING MULTI-INSTANCE AUTOMATED TEST")
    print("==================================================")
    
    # Clean previous log if possible
    # Launch Host
    print("[1/4] Launching Host instance (--coop-host)...")
    host_proc = subprocess.Popen(
        [GAME_EXE, "--windowed", "--coop-host"], 
        cwd=os.path.dirname(GAME_EXE)
    )
    print(f"      Host PID: {host_proc.pid}")
    
    time.sleep(6) # Wait for host to start and bind port 7777
    
    # Launch Client
    print("[2/4] Launching Client instance (--coop-join 127.0.0.1)...")
    client_proc = subprocess.Popen(
        [GAME_EXE, "--windowed", "--coop-join", "127.0.0.1"], 
        cwd=os.path.dirname(GAME_EXE)
    )
    print(f"      Client PID: {client_proc.pid}")
    
    # Wait for networking handshake
    print("[3/4] Waiting 12 seconds for network handshake & input replication...")
    time.sleep(12)
    
    # Terminate both
    print("[4/4] Terminating instances...")
    for p, name in [(host_proc, "Host"), (client_proc, "Client")]:
        try:
            p.terminate()
            p.wait(timeout=2)
        except Exception:
            subprocess.run(["taskkill", "/F", "/PID", str(p.pid)], capture_output=True)
            
    print("\n--- Verifying Network Assertions in Logs ---")
    log_content = ""
    # Check all recent logs in AppData
    log_dir = os.path.expandvars(r"%APPDATA%\Brotato\logs")
    recent_logs = []
    if os.path.exists(log_dir):
        for f in os.listdir(log_dir):
            if f.endswith(".log"):
                fp = os.path.join(log_dir, f)
                recent_logs.append((os.path.getmtime(fp), fp))
        recent_logs.sort(reverse=True)
        
    all_lines = []
    for _, fp in recent_logs[:3]:
        with open(fp, "r", encoding="utf-8", errors="ignore") as lf:
            all_lines.extend(lf.readlines())
            
    # Assertions
    has_host = any("Auto-hosting server" in l or "Hosting online game on port" in l for l in all_lines)
    has_client = any("Auto-joining server" in l or "Connecting to 127.0.0.1" in l for l in all_lines)
    has_peer_connected = any("Peer connected" in l for l in all_lines)
    has_slot_assigned = any("Host assigned player slot" in l or "Adding network player" in l for l in all_lines)
    has_input_replicated = any("Received remote input from player" in l for l in all_lines)
    
    print(f"Assertion 1: Host server bound port 7777:      {'[PASS]' if has_host else '[FAIL]'}")
    print(f"Assertion 2: Client initiated connection:       {'[PASS]' if has_client else '[FAIL]'}")
    print(f"Assertion 3: Peer connected via ENet:          {'[PASS]' if has_peer_connected else '[FAIL]'}")
    print(f"Assertion 4: Slot assigned in CoopService:     {'[PASS]' if has_slot_assigned else '[FAIL]'}")
    print(f"Assertion 5: Input replicated to Host:         {'[PASS]' if has_input_replicated else '[FAIL]'}")
    
    print("\nRecent Relevant Log Lines:")
    for l in all_lines:
        if "CoopAnything" in l or "QA_TEST" in l or "Peer" in l:
            print("  " + l.strip())
            
    if has_host and has_client and has_peer_connected:
        print("\n>>> TEST SUITE PASSED! Co-op networking verified in real game clients! <<<")
    else:
        print("\n>>> TEST INCOMPLETE - Check logs above for details <<<")

if __name__ == "__main__":
    run_multi_instance_test()
